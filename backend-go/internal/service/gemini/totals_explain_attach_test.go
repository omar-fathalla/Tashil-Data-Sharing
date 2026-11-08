package gemini

import (
	"errors"
	"strings"
	"testing"

	"github.com/tashil/data-sharing/backend/internal/domain"
	"github.com/tashil/data-sharing/backend/internal/service/totalsxplain"
)

func TestAttachTotalsExplanationReturnsArabic(t *testing.T) {
	v := &domain.IngestionValidation{
		Status:          "flagged",
		RecordCount:     40,
		ExtractedUnits:  400,
		ExtractedValue:  20000,
		SourceUnits:     400,
		SourceValue:     20000,
		SheetTotalUnits: 390,
		SheetTotalValue: 19500,
		MonthsDetected:  []string{"2026-01"},
		Issues:          []string{"value total 20000.00 is 2.6% off the sheet total column 19500.00"},
	}
	attachTotalsExplanation(v, totalsxplain.Provenance{
		Known:                 true,
		SheetName:             "يناير",
		HeaderRowIndex:        0,
		DataRowFirst:          1,
		DataRowLast:           40,
		SheetTotalValueColIdx: 12,
		NegativeValueCells:    6,
	})
	if v.ExplanationAR == "" {
		t.Fatal("expected explanation_ar")
	}
	if !strings.Contains(v.ExplanationAR, "يناير") {
		t.Fatalf("sheet missing: %s", v.ExplanationAR)
	}
	found := false
	for _, r := range v.DiffReasons {
		if r == totalsxplain.ReasonReturns || r == totalsxplain.ReasonSheetColumnGap {
			found = true
		}
	}
	if !found {
		t.Fatalf("expected returns/sheet gap reasons, got %v", v.DiffReasons)
	}
}

func TestValidationErrorAppendsExplanationAR(t *testing.T) {
	v := &domain.IngestionValidation{
		Status:        "rejected",
		Issues:        []string{"no month detected"},
		ExplanationAR: "لم يُكتشف عمود/قيمة شهر في الصفوف المقروءة، لذلك لا يمكن اعتماد الإجمالي لفترة محددة.",
	}
	err := validationError("x.xlsx", v)
	if !errors.Is(err, ErrUploadValidation) {
		t.Fatalf("wrap: %v", err)
	}
	msg := err.Error()
	if !strings.Contains(msg, "no month detected") {
		t.Fatalf("expected English issues kept: %v", err)
	}
	if !strings.Contains(msg, "لم يُكتشف عمود") {
		t.Fatalf("expected Arabic explanation appended: %v", err)
	}
	if !strings.Contains(msg, " — ") {
		t.Fatalf("expected issues — explanation join: %v", err)
	}
}

func TestValidationErrorNilSafe(t *testing.T) {
	err := validationError("x.xlsx", nil)
	if !errors.Is(err, ErrUploadValidation) {
		t.Fatalf("wrap: %v", err)
	}
}

func TestProvenanceFromPlanNoHardcodedSheet1(t *testing.T) {
	rows := [][]string{
		{"Barcode", "Qty", "Value", "Total"},
		{"1", "1.5", "10", "10"},
		{"2", "-2", "-5", "-5"},
		{"3", "3", "20", "20"},
	}
	plan := &ColumnMapPlan{
		HeaderRowIndex: 0,
		Layout:         "long",
		Columns: []ColumnRole{
			{Index: 0, Role: roleBarcode},
			{Index: 1, Role: roleQuantity},
			{Index: 2, Role: roleValue},
			{Index: 3, Role: roleTotalValue},
		},
	}
	p := provenanceFromPlan(rows, plan)
	if !p.Known {
		t.Fatal("expected Known=true for real plan+rows")
	}
	if p.SheetName != "" {
		t.Fatalf("must not hardcode SheetName, got %q", p.SheetName)
	}
	if p.NegativeValueCells != 1 || p.NegativeUnitsCells != 1 {
		t.Fatalf("neg counts value=%d units=%d", p.NegativeValueCells, p.NegativeUnitsCells)
	}
	if p.FractionalQtyCells != 1 {
		t.Fatalf("frac qty=%d", p.FractionalQtyCells)
	}
	if p.DataRowFirst != 1 || p.DataRowLast != 3 {
		t.Fatalf("rows %d–%d", p.DataRowFirst, p.DataRowLast)
	}
	if p.SheetTotalValueColIdx != 3 {
		t.Fatalf("sheet total col %d", p.SheetTotalValueColIdx)
	}

	empty := provenanceFromPlan(nil, nil)
	if empty.Known {
		t.Fatal("nil plan must keep Known=false")
	}
}

func TestProvenanceFromPayloadKnownOnlyWithSheetOrLayout(t *testing.T) {
	unknown := provenanceFromPayload(&domain.NormalizedRetailIngestionPayload{})
	if unknown.Known {
		t.Fatal("empty payload must stay Known=false")
	}
	known := provenanceFromPayload(&domain.NormalizedRetailIngestionPayload{
		SheetsProcessed: []string{"مبيعات"},
	})
	if !known.Known || known.SheetName != "مبيعات" {
		t.Fatalf("expected Known with sheet: %+v", known)
	}
}
