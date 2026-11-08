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

func TestSheetSelectionSkipsFullYearWhenMonthlyExists(t *testing.T) {
	plan := buildSheetSelectionPlan("archive.xlsx", []string{"يناير 26", "فبراير 26", "sale out2026"})
	if !plan.yearsWithMonthly[2026] {
		t.Fatal("expected 2026 marked as having monthly sheets")
	}
	if plan.shouldIncludeSheet("sale out2026") {
		t.Fatal("full-year 2026 dump must be skipped when monthly tabs exist")
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
	if plan.shouldIncludeSheet("sale out2026") {
		t.Fatal("same-year full-year dump still skipped when monthly tabs exist")
	}
}

func TestWideWorkbookNoDoubleCountMonthlyPlusFullYear(t *testing.T) {
	// Monthly January 2026 (rev 600) plus a leftover full-year dump for 2026 (rev 100).
	// Without selection both would be ingested → 700. With selection only monthly stays → 600.
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
		t.Fatalf("expected only monthly sheet revenue 600 (no double count), got %v; processed=%v",
			rev, p.SheetsProcessed)
	}
	for _, name := range p.SheetsProcessed {
		if strings.EqualFold(strings.TrimSpace(name), "sale out2026") {
			t.Fatalf("full-year sheet must not be processed, got %v", p.SheetsProcessed)
		}
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
