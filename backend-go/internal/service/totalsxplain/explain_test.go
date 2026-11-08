package totalsxplain

import (
	"strings"
	"testing"

	"github.com/tashil/data-sharing/backend/internal/domain"
)

func TestExplainReturnsGapGroundedInSheetAndColumns(t *testing.T) {
	v := &domain.IngestionValidation{
		Status:          "flagged",
		RecordCount:     100,
		ExtractedUnits:  1000,
		ExtractedValue:  50000,
		SourceUnits:     1000,
		SourceValue:     50000,
		SheetTotalUnits: 980,
		SheetTotalValue: 49000,
		MonthsDetected:  []string{"2026-01"},
		Issues:          []string{"value total 50000.00 is 2.0% off the sheet total column 49000.00"},
	}
	p := Provenance{
		Known:                 true,
		SheetName:             "مبيعات يناير",
		HeaderRowIndex:        0,
		DataRowFirst:          1,
		DataRowLast:           100,
		Layout:                "wide",
		ValueColumnIndex:      4,
		UnitsColumnIndex:      5,
		SheetTotalValueColIdx: 10,
		SheetTotalUnitsColIdx: 11,
		ValueColumnHeader:     "قيمة سموحة",
		SheetTotalValueHeader: "الإجمالي",
		NegativeValueCells:    8,
		NegativeUnitsCells:    8,
	}
	out := Explain(v, p)
	if out.ExplanationAR == "" {
		t.Fatal("expected Arabic explanation")
	}
	if !strings.Contains(out.ExplanationAR, "مبيعات يناير") {
		t.Fatalf("expected sheet name in explanation: %s", out.ExplanationAR)
	}
	if !strings.Contains(out.ExplanationAR, "عمود") {
		t.Fatalf("expected column grounding: %s", out.ExplanationAR)
	}
	if !strings.Contains(out.ExplanationAR, "صفوف البيانات") {
		t.Fatalf("expected row range: %s", out.ExplanationAR)
	}
	if !contains(out.Reasons, ReasonReturns) {
		t.Fatalf("expected returns reason, got %v", out.Reasons)
	}
	if !contains(out.Reasons, ReasonSheetColumnGap) {
		t.Fatalf("expected sheet_column_gap, got %v", out.Reasons)
	}
	if !strings.Contains(out.ExplanationAR, "50000.00") || !strings.Contains(out.ExplanationAR, "49000.00") {
		t.Fatalf("expected grounded numbers: %s", out.ExplanationAR)
	}
}

func TestExplainRounding(t *testing.T) {
	v := &domain.IngestionValidation{
		Status:          "flagged",
		RecordCount:     50,
		ExtractedUnits:  200,
		ExtractedValue:  1000,
		SourceUnits:     200,
		SourceValue:     1000,
		SheetTotalUnits: 201.4,
		SheetTotalValue: 1000,
		MonthsDetected:  []string{"2026-02"},
	}
	out := Explain(v, Provenance{
		Known:                 true,
		SheetName:             "فرع سموحة",
		HeaderRowIndex:        0,
		DataRowFirst:          1,
		DataRowLast:           50,
		FractionalQtyCells:    12,
		SheetTotalUnitsColIdx: 3,
	})
	if !contains(out.Reasons, ReasonRounding) {
		t.Fatalf("expected rounding, got %v (%s)", out.Reasons, out.ExplanationAR)
	}
	if !strings.Contains(out.ExplanationAR, "تقريب") {
		t.Fatalf("expected rounding Arabic: %s", out.ExplanationAR)
	}
}

func TestExplainMissingMonthAndUnread(t *testing.T) {
	v := &domain.IngestionValidation{
		Status:         "rejected",
		RecordCount:    50,
		ExtractedUnits: 50,
		ExtractedValue: 0,
		Issues: []string{
			"no month detected",
			"quantity equals the row count and value is zero: columns were not read",
		},
	}
	out := Explain(v, Provenance{Known: true, SheetName: "بيانات", HeaderRowIndex: 0, DataRowFirst: 1, DataRowLast: 50})
	if !contains(out.Reasons, ReasonMissingMonth) || !contains(out.Reasons, ReasonUnreadColumns) {
		t.Fatalf("expected missing_month+unread_columns, got %v", out.Reasons)
	}
	if !strings.Contains(out.ExplanationAR, "شهر") {
		t.Fatalf("expected month Arabic: %s", out.ExplanationAR)
	}
}

func TestExplainSourceCellGap(t *testing.T) {
	v := &domain.IngestionValidation{
		Status:         "rejected",
		RecordCount:    30,
		ExtractedUnits: 10,
		ExtractedValue: 100,
		SourceUnits:    200,
		SourceValue:    5000,
		MonthsDetected: []string{"2026-03"},
		Issues:         []string{"extracted value 100.00 differs from source cells 5000.00"},
	}
	out := Explain(v, Provenance{Known: true, SheetName: "Data", ValueColumnIndex: 2, UnitsColumnIndex: 3})
	if !contains(out.Reasons, ReasonSourceCellGap) {
		t.Fatalf("expected source_cell_gap, got %v", out.Reasons)
	}
}

func TestExplainUnknownProvenanceNoSheet1OrMatched(t *testing.T) {
	// Builders historically filled -1 sentinels; without Known that must stay quiet.
	v := &domain.IngestionValidation{Status: "ok", RecordCount: 10, ExtractedUnits: 10, ExtractedValue: 100}
	out := Explain(v, Provenance{
		Known:                 false,
		HeaderRowIndex:        -1,
		DataRowFirst:          -1,
		DataRowLast:           -1,
		ValueColumnIndex:      -1,
		UnitsColumnIndex:      -1,
		SheetTotalValueColIdx: -1,
		SheetTotalUnitsColIdx: -1,
	})
	if out.ExplanationAR != "" {
		t.Fatalf("expected empty for Known=false sentinels, got %q", out.ExplanationAR)
	}
	if contains(out.Reasons, ReasonMatched) {
		t.Fatalf("must not emit matched without Known: %v", out.Reasons)
	}
	if strings.Contains(out.ExplanationAR, "Sheet1") {
		t.Fatalf("must not invent Sheet1: %q", out.ExplanationAR)
	}
}

func TestExplainKnownWithoutSheetNameOmitsSheet1(t *testing.T) {
	v := &domain.IngestionValidation{
		Status:          "flagged",
		RecordCount:     20,
		ExtractedUnits:  100,
		ExtractedValue:  1000,
		SourceUnits:     100,
		SourceValue:     1000,
		SheetTotalValue: 900,
		MonthsDetected:  []string{"2026-01"},
	}
	out := Explain(v, Provenance{
		Known:                 true,
		HeaderRowIndex:        0,
		DataRowFirst:          1,
		DataRowLast:           20,
		SheetTotalValueColIdx: 9,
		NegativeValueCells:    3,
	})
	if out.ExplanationAR == "" {
		t.Fatal("expected explanation when Known with row/col provenance")
	}
	if strings.Contains(out.ExplanationAR, "Sheet1") {
		t.Fatalf("must not invent Sheet1 when SheetName empty: %s", out.ExplanationAR)
	}
	if !strings.Contains(out.ExplanationAR, "صفوف البيانات") {
		t.Fatalf("expected row grounding: %s", out.ExplanationAR)
	}
}

func TestExplainMatchedOnlyWhenKnown(t *testing.T) {
	v := &domain.IngestionValidation{Status: "ok", RecordCount: 10, ExtractedUnits: 10, ExtractedValue: 100}
	quiet := Explain(v, Provenance{})
	if quiet.ExplanationAR != "" {
		t.Fatalf("zero Provenance must stay quiet: %q", quiet.ExplanationAR)
	}
	out := Explain(v, Provenance{
		Known:          true,
		SheetName:      "يناير",
		HeaderRowIndex: 0,
		DataRowFirst:   1,
		DataRowLast:    10,
	})
	if !contains(out.Reasons, ReasonMatched) {
		t.Fatalf("expected matched when Known with location, got %v (%s)", out.Reasons, out.ExplanationAR)
	}
	if !strings.Contains(out.ExplanationAR, "يناير") {
		t.Fatalf("expected real sheet name: %s", out.ExplanationAR)
	}
}

func TestApplySetsFields(t *testing.T) {
	v := &domain.IngestionValidation{
		Status:          "flagged",
		RecordCount:     20,
		ExtractedUnits:  100,
		ExtractedValue:  1000,
		SourceUnits:     100,
		SourceValue:     1000,
		SheetTotalUnits: 90,
		SheetTotalValue: 900,
		MonthsDetected:  []string{"2026-01"},
	}
	Apply(v, Provenance{
		Known:                 true,
		SheetName:             "S",
		HeaderRowIndex:        0,
		DataRowFirst:          1,
		DataRowLast:           20,
		NegativeValueCells:    5,
		SheetTotalValueColIdx: 9,
	})
	if v.ExplanationAR == "" {
		t.Fatal("Apply should set ExplanationAR")
	}
	if len(v.DiffReasons) == 0 {
		t.Fatal("Apply should set DiffReasons")
	}
}

func contains(xs []string, want string) bool {
	for _, x := range xs {
		if x == want {
			return true
		}
	}
	return false
}
