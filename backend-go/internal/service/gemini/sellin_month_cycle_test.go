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
	if y := adjustCycleYear(2025, 12, 1, true); y != 2026 {
		t.Fatalf("Jan cycle starting late Dec (year from doc date): got %d want 2026", y)
	}
	if y := adjustCycleYear(2026, 1, 12, true); y != 2025 {
		t.Fatalf("Dec cycle spilling into Jan: got %d want 2025", y)
	}
	if y := adjustCycleYear(2025, 12, 1, false); y != 2025 {
		t.Fatalf("year from month token must not be nudged: got %d", y)
	}
	if y := adjustCycleYear(2026, 1, 2, true); y != 2026 {
		t.Fatalf("Feb cycle with Jan doc date must keep year, got %d", y)
	}
	if y := adjustCycleYear(2026, 3, 2, true); y != 2026 {
		t.Fatalf("Feb cycle with Mar doc date must keep year, got %d", y)
	}
}

func TestResolveReportsYearSource(t *testing.T) {
	p := newSellInPeriodResolver(0)
	p.startRow()
	if y, m, ok := p.resolve(1, "", "", "Jan-25", "2025-12-28"); !ok || y != 2025 || m != 1 || p.yearSource != sellInYearMonthToken {
		t.Fatalf("Jan-25 year from month token: y=%d m=%d ok=%v src=%v", y, m, ok, p.yearSource)
	}
	p.startRow()
	if y, m, ok := p.resolve(2, "", "", "JAN", "2025-12-28"); !ok || y != 2025 || m != 1 || p.yearSource != sellInYearDate {
		t.Fatalf("JAN + Dec doc date: y=%d m=%d ok=%v src=%v", y, m, ok, p.yearSource)
	}
	p.startRow()
	if y, _, ok := p.resolve(3, "2027", "", "Feb", "2026-01-31"); !ok || y != 2027 || p.yearSource != sellInYearExplicit {
		t.Fatalf("explicit year column wins: y=%d ok=%v src=%v", y, ok, p.yearSource)
	}
	f := newSellInPeriodResolver(2026)
	f.startRow()
	if y, m, ok := f.resolve(4, "", "", "Mar", ""); !ok || y != 2026 || m != 3 || f.yearSource != sellInYearFilename {
		t.Fatalf("filename year fallback: y=%d m=%d ok=%v src=%v", y, m, ok, f.yearSource)
	}
}

func TestGPSOPMonthColumnDrivesPeriodNotDocumentDate(t *testing.T) {
	hdr := []string{
		"SOP Type", "SOP Number", "Document Date", "Item Number", "Item Description",
		"U Of M", "QTY", "Location Code", "Customer Number", "Customer Name", "Customer Class",
		"TO", "Branch", "month", "week",
	}
	rows := [][]string{hdr}
	type want struct {
		year, month int
	}
	expects := []want{}
	add := func(date, month, week, to string, y, m int) {
		rows = append(rows, []string{
			"Invoice", "INV-" + strconv.Itoa(len(rows)), date, "FG-QA-1", "صنف تجريبي",
			"CTN", "1", "L1", "C1", "عائله فتح الله ماركت - طنطا", "KA",
			to, "ALX", month, week,
		})
		expects = append(expects, want{y, m})
	}
	for _, b := range monthCycleBoundaries {
		// in26-style week numbers 1-5 must NOT become PeriodWeek W1..W5 (status stays مغلق).
		add(b.firstDocDate, b.label, "1", "10", 2026, b.monthNum)
		add(b.lastDocDate, b.label, "2", "10", 2026, b.monthNum)
	}
	add("2026-03-05", "فبراير", "3", "10", 2026, 2)
	add("2026-04-15", "#N/A", "1", "10", 2026, 4)
	add("2026-05-10", "", "", "10", 2026, 5)
	// Jan cycle starting late December — year from Document Date → nudge to 2026.
	add("2025-12-28", "JAN", "1", "10", 2026, 1)
	// Explicit year in month token must not jump across the Dec→Jan boundary.
	add("2025-12-28", "Jan-25", "4", "10", 2025, 1)
	// Unparseable (not empty/#N/A) → Document Date fallback + MonthCheck note.
	add("2026-06-15", "Q1", "5", "10", 2026, 6)

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
		if r.PeriodWeek != "Full Month" {
			t.Errorf("row %d: PeriodWeek %q want Full Month (gp_sop week must not drive status)", i, r.PeriodWeek)
		}
	}
	if recs[2].MonthNum != 2 || recs[3].MonthNum != 2 {
		t.Fatalf("Feb cycle endpoints must be month 2, got %d / %d", recs[2].MonthNum, recs[3].MonthNum)
	}
	augFirst := 7 * 2
	if recs[augFirst].MonthNum != 8 || recs[augFirst+1].MonthNum != 8 {
		t.Fatalf("Aug cycle endpoints must be month 8")
	}
	if !strings.Contains(rep.MonthCheck, "عمود الشهر") {
		t.Fatalf("MonthCheck should note month-column precedence, got %q", rep.MonthCheck)
	}
	if !strings.Contains(rep.MonthCheck, "مش مفهوم") {
		t.Fatalf("MonthCheck should note unparseable month cells, got %q", rep.MonthCheck)
	}
}

// GP SOP weeks 1-5 must keep PeriodWeek "Full Month" so analytics status stays مغلق
// (cpfr_analytics flips to قيد الإغلاق only when PeriodWeek is W1/W2).
func TestGPSOPWeekColumnDoesNotOpenMonthStatus(t *testing.T) {
	hdr := []string{
		"SOP Type", "SOP Number", "Document Date", "Item Number", "Item Description",
		"U Of M", "QTY", "Customer Name", "TO", "month", "week",
	}
	rows := [][]string{hdr}
	for w := 1; w <= 5; w++ {
		rows = append(rows, []string{
			"Invoice", "INV-" + strconv.Itoa(w), "2026-02-10", "FG-1", "صنف",
			"CTN", "1", "عائله فتح الله ماركت - طنطا", "100", "Feb", strconv.Itoa(w),
		})
	}
	x, err := BuildSampleXLSX(rows)
	if err != nil {
		t.Fatal(err)
	}
	recs, _, err := ParseSellInPlanWorkbookWithReport("tenant-adeco", "in26.xlsx", x, "fathalla")
	if err != nil {
		t.Fatal(err)
	}
	if len(recs) != 5 {
		t.Fatalf("got %d rows", len(recs))
	}
	for _, r := range recs {
		if r.PeriodWeek != "Full Month" {
			t.Fatalf("PeriodWeek=%q want Full Month (week %s would open قيد الإغلاق)", r.PeriodWeek, r.PeriodWeek)
		}
		// Mirror cpfr_analytics hasWeekly gate: W1/W2 ⇒ قيد الإغلاق, else مغلق.
		status := "مغلق (Full Month)"
		if r.PeriodWeek == "W1" || r.PeriodWeek == "W2" {
			status = "قيد الإغلاق (W1+W2 → EXP)"
		}
		if !strings.Contains(status, "مغلق") {
			t.Fatalf("status %q want مغلق", status)
		}
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
	if len(recs) != 1 || recs[0].Year != 2026 || recs[0].MonthNum != 3 || recs[0].PeriodWeek != "Full Month" {
		t.Fatalf("no month column → Document Date month + Full Month, got %+v", recs)
	}
}

// Locked Adeco in26 company-month totals (owner-approved). Used by fixture design and
// optional full-file acceptance (IN26_XLSX).
var monthCycleExpectedTotals = []struct {
	label string
	rows  int
	net   float64
}{
	{"JAN", 3539, 10212067.77},
	{"Feb", 4664, 11404520.48},
	{"Mar", 3493, 12592702.99},
	{"Apr", 3025, 9641468.61},
	{"May", 4179, 8483253.75},
	{"Jun", 3581, 12939113.05},
	{"Jul", 4427, 14550887.86},
	{"Aug", 4113, 16735656.86},
	{"Sep", 5003, 17531787.55},
	{"Oct", 4903, 19099943.93},
}

const (
	monthCycleExpectedTotalRows = 40927
	monthCycleExpectedTotalNet  = 133191402.85
)

// Assert label→boundary dates and per-month rows/net TO match the checked-in expected CSV.
func TestMonthCycleExpectedCSVMatchesFixtureDesign(t *testing.T) {
	path := os.Getenv("MONTH_CYCLE_EXPECTED_CSV")
	if path == "" {
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
	type rowExp struct {
		first, last string
		rows        int
		net         float64
	}
	byLabel := map[string]rowExp{}
	var totalRows int
	var totalNet float64
	for i, row := range records {
		if i == 0 || len(row) < 5 {
			continue
		}
		if strings.EqualFold(row[0], "TOTAL") {
			totalRows, _ = strconv.Atoi(strings.TrimSpace(row[3]))
			totalNet, _ = strconv.ParseFloat(strings.TrimSpace(row[4]), 64)
			continue
		}
		rows, _ := strconv.Atoi(strings.TrimSpace(row[3]))
		net, _ := strconv.ParseFloat(strings.TrimSpace(row[4]), 64)
		byLabel[row[0]] = rowExp{first: row[1], last: row[2], rows: rows, net: net}
	}
	for _, b := range monthCycleBoundaries {
		got, ok := byLabel[b.label]
		if !ok {
			t.Fatalf("missing label %q in expected CSV", b.label)
		}
		if got.first != b.firstDocDate || got.last != b.lastDocDate {
			t.Fatalf("%s: CSV dates %s..%s want %s..%s", b.label, got.first, got.last, b.firstDocDate, b.lastDocDate)
		}
	}
	for _, want := range monthCycleExpectedTotals {
		got, ok := byLabel[want.label]
		if !ok {
			t.Fatalf("missing totals for %q", want.label)
		}
		if got.rows != want.rows {
			t.Fatalf("%s rows: CSV %d want %d", want.label, got.rows, want.rows)
		}
		if got.net != want.net {
			t.Fatalf("%s net: CSV %v want %v", want.label, got.net, want.net)
		}
	}
	if totalRows != monthCycleExpectedTotalRows || totalNet != monthCycleExpectedTotalNet {
		t.Fatalf("TOTAL: CSV %d / %.2f want %d / %.2f", totalRows, totalNet, monthCycleExpectedTotalRows, monthCycleExpectedTotalNet)
	}
}
