package gemini

import "testing"

// Pivot "Details for ..." exports put a title row and a blank row above the real header,
// and use month codes like "seb". Header structure mirrors the real FATHALLA sell-out export.
func TestWideMatrixHeaderBelowTitleRow(t *testing.T) {
	rows := [][]string{
		{"Details for Sum of الاجمالى - YEAR: 2026, MONTH: JAN, المجموعة: اقراص غسالات اطباق (+)"},
		{""},
		{"المجموعة", "المورد", "الباركود", "الصنف", " سموحة", " ستانلى", "الاجمالى", "MONTH", "كمية سموحة", "كمية ستانلى", "اجمالى كميات", "YEAR"},
		{"منعمات ملابس", "ادكو (1)", "6223000233726", "فلفيتا 1 لتر", "4380", "1679", "6059", "seb", "60", "23", "83", "2026"},
		{"منعمات ملابس", "ادكو (1)", "6223000233726", "فلفيتا 1 لتر", "1826", "1623", "3449", "aug", "24", "21", "45", "2026"},
		{"منعمات ملابس", "ادكو (1)", "6223000233726", "فلفيتا 1 لتر", "2580", "903", "3483", "JAN", "36", "12", "48", "2026"},
	}
	xlsxBytes, err := BuildSampleXLSX(rows)
	if err != nil {
		t.Fatalf("build xlsx: %v", err)
	}
	payload, ok := parseFullTabularPayload("Book3.xlsx", xlsxBytes)
	if !ok || payload == nil {
		t.Fatalf("expected workbook to parse")
	}
	if !payload.IsWideMatrixWorkbook {
		t.Fatalf("expected wide-matrix parser to handle header below title row")
	}
	var units int
	var revenue float64
	months := map[string]bool{}
	for _, r := range payload.NormalizedRecords {
		units += r.QuantitySold
		revenue += r.NetRevenue
		if len(r.TransactionDate) >= 7 {
			months[r.TransactionDate[:7]] = true
		}
	}
	if units != 176 {
		t.Errorf("expected 176 units, got %d", units)
	}
	if revenue != 12991 {
		t.Errorf("expected revenue 12991, got %v", revenue)
	}
	for _, m := range []string{"2026-01", "2026-08", "2026-09"} {
		if !months[m] {
			t.Errorf("expected month %s in %v", m, months)
		}
	}
}
