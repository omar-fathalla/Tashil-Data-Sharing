package gemini

import (
	"strings"
	"testing"
)

func TestSheetSelectionSkipsOtherYearFullSheet(t *testing.T) {
	plan := buildSheetSelectionPlan("2026 out.xlsx", []string{"sale out2025", "sale out2026"})
	if !plan.hasMatchingFileYearSheet || plan.fileYear != 2026 {
		t.Fatalf("expected file-year match for 2026, got %+v", plan)
	}
	if plan.shouldIncludeSheet("sale out2025") {
		t.Fatal("leftover 2025 full-year sheet must be skipped inside 2026 out.xlsx")
	}
	if !plan.shouldIncludeSheet("sale out2026") {
		t.Fatal("matching 2026 full-year sheet must stay")
	}
}

func TestSheetSelectionKeepsFullYearDespiteMonthlyNames(t *testing.T) {
	// Name-level selection must NOT silently drop the yearly sheet just because
	// a monthly tab exists — period coverage decides after parse.
	plan := buildSheetSelectionPlan("archive.xlsx", []string{"يناير 26", "فبراير 26", "sale out2026"})
	if !plan.shouldIncludeSheet("sale out2026") {
		t.Fatal("full-year sheet must stay open; monthlies must not drop it at name level")
	}
	if !plan.shouldIncludeSheet("يناير 26") || !plan.shouldIncludeSheet("فبراير 26") {
		t.Fatal("monthly sheets must stay")
	}
}

func TestSheetSelectionKeepsLoneFullYearSheet(t *testing.T) {
	plan := buildSheetSelectionPlan("2025 out.xlsx", []string{"sale out2025"})
	if !plan.shouldIncludeSheet("sale out2025") {
		t.Fatal("sole full-year sheet must be kept so row-period split can run")
	}
}

func TestSheetSelectionKeepsOtherYearMonthlyForTrends(t *testing.T) {
	plan := buildSheetSelectionPlan("2026 out.xlsx", []string{"يناير 25", "يناير 26", "sale out2026"})
	if !plan.shouldIncludeSheet("يناير 25") {
		t.Fatal("other-year monthly sheets stay for MoM/YoY trends")
	}
	if !plan.shouldIncludeSheet("sale out2026") {
		t.Fatal("same-year full-year sheet stays open at name level")
	}
}

func TestDedupeByPeriodPrefersValidMonthly(t *testing.T) {
	monthly := parsedSheetSummary{
		sheetName:          "يناير 26",
		sheetDate:          "2026-01-31",
		rows:               [][]string{wideHeader, {"x"}},
		preferOverFullYear: true,
	}
	fromYear := parsedSheetSummary{
		sheetName: "يناير 26",
		sheetDate: "2026-01-31",
		rows:      [][]string{wideHeader, {"y"}},
	}
	out := dedupeSheetsByPeriodCoverage([]parsedSheetSummary{monthly, fromYear})
	if len(out) != 1 || !out[0].preferOverFullYear {
		t.Fatalf("expected only preferred monthly kept, got %+v", out)
	}
}

func TestDedupePartialCoverageKeepsUncoveredYearlyMonths(t *testing.T) {
	janMonthly := parsedSheetSummary{
		sheetName:          "يناير 26",
		sheetDate:          "2026-01-31",
		rows:               [][]string{wideHeader, {"m"}},
		preferOverFullYear: true,
	}
	janFromYear := parsedSheetSummary{
		sheetName: "يناير 26",
		sheetDate: "2026-01-31",
		rows:      [][]string{wideHeader, {"y1"}},
	}
	febFromYear := parsedSheetSummary{
		sheetName: "فبراير 26",
		sheetDate: "2026-02-28",
		rows:      [][]string{wideHeader, {"y2"}},
	}
	out := dedupeSheetsByPeriodCoverage([]parsedSheetSummary{janMonthly, janFromYear, febFromYear})
	if len(out) != 2 {
		t.Fatalf("expected monthly Jan + yearly Feb, got %d: %+v", len(out), out)
	}
	var sawPrefer, sawFeb bool
	for _, sh := range out {
		if sh.preferOverFullYear && strings.HasPrefix(sh.sheetDate, "2026-01") {
			sawPrefer = true
		}
		if !sh.preferOverFullYear && strings.HasPrefix(sh.sheetDate, "2026-02") {
			sawFeb = true
		}
	}
	if !sawPrefer || !sawFeb {
		t.Fatalf("partial coverage failed: preferJan=%v febFromYear=%v out=%+v", sawPrefer, sawFeb, out)
	}
}

func TestDedupeEmptyMonthlyDoesNotCoverYearly(t *testing.T) {
	emptyMonthly := parsedSheetSummary{
		sheetName:          "يناير 26",
		sheetDate:          "2026-01-31",
		rows:               [][]string{wideHeader}, // header only — invalid/empty
		preferOverFullYear: true,
	}
	fromYear := parsedSheetSummary{
		sheetName: "يناير 26",
		sheetDate: "2026-01-31",
		rows:      [][]string{wideHeader, {"y"}},
	}
	out := dedupeSheetsByPeriodCoverage([]parsedSheetSummary{emptyMonthly, fromYear})
	if len(out) != 2 {
		t.Fatalf("empty monthly must not claim coverage; expected both kept, got %d", len(out))
	}
}

func TestWideWorkbookNoDoubleCountOverlappingJanuary(t *testing.T) {
	// Valid monthly January (600) + full-year dump with same January (100) → keep 600 only.
	rowMonth := []string{"منعمات", "ادكو (1)", "6223000233726", "فلفيتا", "300", "300", "600", "jan", "3", "3", "6", "2026"}
	rowFull := []string{"منعمات", "ادكو (1)", "6223000233726", "فلفيتا", "50", "50", "100", "jan", "1", "1", "2", "2026"}
	x := buildMultiSheetXLSX(t, []string{"يناير 26", "sale out2026"}, map[string][][]string{
		"يناير 26":     {wideHeader, rowMonth},
		"sale out2026": {wideHeader, rowFull},
	})
	p, ok := parseWideMatrixXLSX("archive.xlsx", x)
	if !ok || p == nil {
		t.Fatal("expected wide workbook to parse")
	}
	var rev float64
	for _, r := range p.NormalizedRecords {
		rev += r.NetRevenue
	}
	if rev != 600 {
		t.Fatalf("expected preferred monthly revenue 600 (no double count), got %v; processed=%v",
			rev, p.SheetsProcessed)
	}
}

func TestWideWorkbookPartialCoverageKeepsUncoveredMonth(t *testing.T) {
	// Monthly January only + full-year sheet with Jan+Feb rows → Jan from monthly, Feb from yearly.
	rowJanMonthly := []string{"منعمات", "ادكو (1)", "6223000233726", "فلفيتا", "300", "300", "600", "jan", "3", "3", "6", "2026"}
	rowJanYear := []string{"منعمات", "ادكو (1)", "6223000233726", "فلفيتا", "50", "50", "100", "jan", "1", "1", "2", "2026"}
	rowFebYear := []string{"منعمات", "ادكو (1)", "6223000233726", "فلفيتا", "100", "100", "200", "feb", "2", "2", "4", "2026"}
	x := buildMultiSheetXLSX(t, []string{"يناير 26", "sale out2026"}, map[string][][]string{
		"يناير 26":     {wideHeader, rowJanMonthly},
		"sale out2026": {wideHeader, rowJanYear, rowFebYear},
	})
	p, ok := parseWideMatrixXLSX("archive.xlsx", x)
	if !ok || p == nil {
		t.Fatal("expected wide workbook to parse")
	}
	var rev float64
	var sawFeb bool
	for _, r := range p.NormalizedRecords {
		rev += r.NetRevenue
		if strings.HasPrefix(r.TransactionDate, "2026-02") {
			sawFeb = true
		}
	}
	if rev != 800 {
		t.Fatalf("expected 600 (monthly Jan) + 200 (yearly Feb) = 800, got %v; processed=%v",
			rev, p.SheetsProcessed)
	}
	if !sawFeb {
		t.Fatal("uncovered February from yearly sheet must remain")
	}
}

func TestWideWorkbookEmptyMonthlyDoesNotDropYearly(t *testing.T) {
	// Empty/invalid monthly tab + yearly with January data → yearly must survive.
	rowFull := []string{"منعمات", "ادكو (1)", "6223000233726", "فلفيتا", "50", "50", "100", "jan", "1", "1", "2", "2026"}
	x := buildMultiSheetXLSX(t, []string{"يناير 26", "sale out2026"}, map[string][][]string{
		"يناير 26":     {wideHeader}, // header only
		"sale out2026": {wideHeader, rowFull},
	})
	p, ok := parseWideMatrixXLSX("archive.xlsx", x)
	if !ok || p == nil {
		t.Fatal("expected yearly sheet to parse when monthly is empty")
	}
	var rev float64
	for _, r := range p.NormalizedRecords {
		rev += r.NetRevenue
	}
	if rev != 100 {
		t.Fatalf("empty monthly must not drop yearly; expected 100, got %v; processed=%v",
			rev, p.SheetsProcessed)
	}
}

func TestTabularMultiSheetSkipsOtherYearFullSheet(t *testing.T) {
	header := []string{"Store_Name", "Barcode", "Item_Description", "Qty_Sold", "Net_Amount", "Date"}
	row25 := []string{"فتح الله سموحة", "6223000233726", "فلفيتا", "1", "100", "2025-01-31"}
	row26 := []string{"فتح الله سموحة", "6223000233726", "فلفيتا", "1", "600", "2026-01-31"}
	x := buildMultiSheetXLSX(t, []string{"sale out2025", "sale out2026"}, map[string][][]string{
		"sale out2025": {header, row25},
		"sale out2026": {header, row26},
	})
	rows, _, err := parseXLSXMultiSheetRows("2026 sales.xlsx", x)
	if err != nil {
		t.Fatal(err)
	}
	if len(rows) < 2 {
		t.Fatalf("expected header + 2026 data, got %d rows", len(rows))
	}
	joined := ""
	for _, r := range rows[1:] {
		joined += strings.Join(r, ",") + "|"
	}
	if strings.Contains(joined, "100") {
		t.Fatalf("2025 full-year sheet leaked into 2026 tabular concat: %q", joined)
	}
	if !strings.Contains(joined, "600") {
		t.Fatalf("2026 sheet missing from tabular concat: %q", joined)
	}
}

func TestTabularKeepsYearlyWhenMonthlyEmpty(t *testing.T) {
	header := []string{"Store_Name", "Barcode", "Item_Description", "Qty_Sold", "Net_Amount", "Date"}
	rowYear := []string{"فتح الله سموحة", "6223000233726", "فلفيتا", "1", "100", "2026-01-31"}
	x := buildMultiSheetXLSX(t, []string{"يناير 26", "sale out2026"}, map[string][][]string{
		"يناير 26":     {header}, // empty monthly
		"sale out2026": {header, rowYear},
	})
	rows, _, err := parseXLSXMultiSheetRows("archive.xlsx", x)
	if err != nil {
		t.Fatal(err)
	}
	joined := ""
	for _, r := range rows {
		joined += strings.Join(r, ",") + "|"
	}
	if !strings.Contains(joined, "100") {
		t.Fatalf("empty monthly must not drop yearly tabular rows: %q", joined)
	}
}

func TestTabularPeriodDedupeJanMonthlyPlusYearlyJanFeb(t *testing.T) {
	// Jan monthly (rev marker 600) + yearly with Jan (100) and Feb (200).
	// Expect Jan once from monthly + Feb from yearly — no Jan double-count.
	header := []string{"Store_Name", "Barcode", "Item_Description", "Qty_Sold", "Net_Amount", "Date"}
	rowJanMonthly := []string{"فتح الله سموحة", "6223000233726", "فلفيتا", "1", "600", "2026-01-15"}
	rowJanYear := []string{"فتح الله سموحة", "6223000233726", "فلفيتا", "1", "100", "2026-01-31"}
	rowFebYear := []string{"فتح الله سموحة", "6223000233726", "فلفيتا", "1", "200", "2026-02-28"}
	x := buildMultiSheetXLSX(t, []string{"يناير 26", "sale out2026"}, map[string][][]string{
		"يناير 26":     {header, rowJanMonthly},
		"sale out2026": {header, rowJanYear, rowFebYear},
	})
	rows, dates, err := parseXLSXMultiSheetRows("archive.xlsx", x)
	if err != nil {
		t.Fatal(err)
	}
	if len(rows) < 2 {
		t.Fatalf("expected header + data rows, got %d", len(rows))
	}
	var amounts []string
	for i, r := range rows[1:] {
		amt := ""
		if len(r) > 4 {
			amt = r[4]
		}
		amounts = append(amounts, amt)
		_ = i
	}
	joined := strings.Join(amounts, ",")
	if strings.Count(joined, "600") != 1 {
		t.Fatalf("expected monthly Jan (600) once, amounts=%q dates=%v", joined, dates)
	}
	if strings.Contains(joined, "100") {
		t.Fatalf("yearly Jan (100) must be deduped against monthly Jan, amounts=%q", joined)
	}
	if !strings.Contains(joined, "200") {
		t.Fatalf("uncovered yearly Feb (200) must remain, amounts=%q", joined)
	}
}
