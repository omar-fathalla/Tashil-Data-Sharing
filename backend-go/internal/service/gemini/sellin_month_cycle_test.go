package gemini

import (
	"encoding/csv"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
)

// Boundary cases from Adeco company sales-month cycle (Document Date spans vs month label).
// Source: internal/month_cycle_expected.csv — synthetic rows only, never the customer in26.xlsx.
var monthCycleBoundaries = []struct {
	label        string // file month cell
	monthNum     int
	firstDocDate string
	lastDocDate  string
}{
	{"JAN", 1, "2026-01-03", "2026-01-29"},
	{"Feb", 2, "2026-01-31", "2026-03-05"},
	{"Mar", 3, "2026-03-07", "2026-04-02"},
	{"Apr", 4, "2026-04-09", "2026-04-30"},
	{"May", 5, "2026-05-02", "2026-06-04"},
	{"Jun", 6, "2026-06-06", "2026-07-02"},
	{"Jul", 7, "2026-07-04", "2026-07-30"},
	{"Aug", 8, "2026-08-01", "2026-09-03"},
	{"Sep", 9, "2026-09-05", "2026-10-01"},
	{"Oct", 10, "2026-10-03", "2026-10-29"},
}

func TestAdjustCycleYearYearBoundary(t *testing.T) {
	if y := adjustCycleYear(2025, 2025, 12, 1); y != 2026 {
		t.Fatalf("Jan cycle starting late Dec: got %d want 2026", y)
	}
	if y := adjustCycleYear(2026, 2026, 1, 12); y != 2025 {
		t.Fatalf("Dec cycle spilling into Jan: got %d want 2025", y)
	}
	if y := adjustCycleYear(2026, 2025, 12, 1); y != 2026 {
		t.Fatalf("explicit month-token year must not be nudged: got %d", y)
	}
	if y := adjustCycleYear(2026, 2026, 1, 2); y != 2026 {
		t.Fatalf("Feb cycle with Jan doc date must keep year, got %d", y)
	}
	if y := adjustCycleYear(2026, 2026, 3, 2); y != 2026 {
		t.Fatalf("Feb cycle with Mar doc date must keep year, got %d", y)
	}
}

func TestGPSOPMonthColumnDrivesPeriodNotDocumentDate(t *testing.T) {
	hdr := []string{
		"SOP Type", "SOP Number", "Document Date", "Item Number", "Item Description",
		"U Of M", "QTY", "Location Code", "Customer Number", "Customer Name", "Customer Class",
		"TO", "Branch", "month", "week",
	}
	rows := [][]string{hdr}
	// One row per boundary endpoint + Arabic month + #N/A fallback + year-boundary Jan.
	type want struct {
		year, month int
		week        string
	}
	expects := []want{}
	add := func(date, month, week, to string, y, m int, pw string) {
		rows = append(rows, []string{
			"Invoice", "INV-" + strconv.Itoa(len(rows)), date, "FG-QA-1", "صنف تجريبي",
			"CTN", "1", "L1", "C1", "عائله فتح الله ماركت - طنطا", "KA",
			to, "ALX", month, week,
		})
		expects = append(expects, want{y, m, pw})
	}
	for _, b := range monthCycleBoundaries {
		add(b.firstDocDate, b.label, "1", "10", 2026, b.monthNum, "W1")
		add(b.lastDocDate, b.label, "2", "10", 2026, b.monthNum, "W2")
	}
	// Arabic month name must map the same way.
	add("2026-03-05", "فبراير", "3", "10", 2026, 2, "W3")
	// #N/A month cell → fall back to Document Date.
	add("2026-04-15", "#N/A", "1", "10", 2026, 4, "W1")
	// Empty month cell → Document Date.
	add("2026-05-10", "", "", "10", 2026, 5, "Full Month")
	// Jan cycle starting late December of previous calendar year.
	add("2025-12-28", "JAN", "1", "10", 2026, 1, "W1")

	x, err := BuildSampleXLSX(rows)
	if err != nil {
		t.Fatal(err)
	}
	recs, rep, err := ParseSellInPlanWorkbookWithReport("tenant-adeco", "in26_month_cycle.xlsx", x, "fathalla")
	if err != nil {
		t.Fatal(err)
	}
	if rep == nil || rep.Layout != "gp_sop_export" {
		t.Fatalf("layout: %+v", rep)
	}
	if len(recs) != len(expects) {
		t.Fatalf("rows: got %d want %d", len(recs), len(expects))
	}
	for i, r := range recs {
		w := expects[i]
		if r.Year != w.year || r.MonthNum != w.month {
			t.Errorf("row %d: period %d-%02d want %d-%02d (MonthEN=%s PeriodWeek=%s)",
				i, r.Year, r.MonthNum, w.year, w.month, r.MonthEN, r.PeriodWeek)
		}
		if r.PeriodWeek != w.week {
			t.Errorf("row %d: PeriodWeek %q want %q", i, r.PeriodWeek, w.week)
		}
	}
	// Feb/Aug boundary dates must NOT land on Document Date's calendar month.
	if recs[2].MonthNum != 2 || recs[3].MonthNum != 2 {
		t.Fatalf("Feb cycle endpoints must be month 2, got %d / %d", recs[2].MonthNum, recs[3].MonthNum)
	}
	augFirst := 7 * 2 // Aug is 8th label (0-based index 7), first endpoint
	if recs[augFirst].MonthNum != 8 || recs[augFirst+1].MonthNum != 8 {
		t.Fatalf("Aug cycle endpoints must be month 8")
	}
	if !strings.Contains(rep.MonthCheck, "عمود الشهر") {
		t.Fatalf("MonthCheck should note month-column precedence, got %q", rep.MonthCheck)
	}
}

func TestGPSOPNoMonthColumnFallsBackToDocumentDate(t *testing.T) {
	rows := [][]string{
		{"SOP Type", "SOP Number", "Document Date", "Item Number", "Item Description", "U Of M", "QTY", "Customer Name", "Extended Price", "Branch"},
		{"Invoice", "INV-1", "2026-03-05", "FG-1", "صنف", "CTN", "1", "عائله فتح الله ماركت - طنطا", "50", "ALX"},
	}
	x, err := BuildSampleXLSX(rows)
	if err != nil {
		t.Fatal(err)
	}
	recs, _, err := ParseSellInPlanWorkbookWithReport("tenant-adeco", "in26.xlsx", x, "fathalla")
	if err != nil {
		t.Fatal(err)
	}
	if len(recs) != 1 || recs[0].Year != 2026 || recs[0].MonthNum != 3 {
		t.Fatalf("no month column → Document Date month, got %+v", recs)
	}
}

// Optional: when MONTH_CYCLE_EXPECTED_CSV points at the expected table, assert label→boundary
// dates match the checked-in copy used for fixture design (does not parse customer xlsx).
func TestMonthCycleExpectedCSVMatchesFixtureDesign(t *testing.T) {
	path := os.Getenv("MONTH_CYCLE_EXPECTED_CSV")
	if path == "" {
		// Prefer repo-local fixture copy when present.
		cand := filepath.Join("testdata", "month_cycle_expected.csv")
		if _, err := os.Stat(cand); err != nil {
			t.Skip("set MONTH_CYCLE_EXPECTED_CSV or add testdata/month_cycle_expected.csv")
		}
		path = cand
	}
	f, err := os.Open(path)
	if err != nil {
		t.Fatal(err)
	}
	defer f.Close()
	r := csv.NewReader(f)
	records, err := r.ReadAll()
	if err != nil {
		t.Fatal(err)
	}
	byLabel := map[string][2]string{}
	var totalRows int
	var totalTO float64
	for i, row := range records {
		if i == 0 || len(row) < 5 {
			continue
		}
		if strings.EqualFold(row[0], "TOTAL") {
			totalRows, _ = strconv.Atoi(row[3])
			totalTO, _ = strconv.ParseFloat(row[4], 64)
			continue
		}
		byLabel[row[0]] = [2]string{row[1], row[2]}
	}
	for _, b := range monthCycleBoundaries {
		got, ok := byLabel[b.label]
		if !ok {
			t.Fatalf("missing label %q in expected CSV", b.label)
		}
		if got[0] != b.firstDocDate || got[1] != b.lastDocDate {
			t.Fatalf("%s: CSV %v want %s..%s", b.label, got, b.firstDocDate, b.lastDocDate)
		}
	}
	if totalRows != 40927 || totalTO != 133191402.85 {
		t.Fatalf("TOTAL rows/TO got %d / %.2f", totalRows, totalTO)
	}
}
