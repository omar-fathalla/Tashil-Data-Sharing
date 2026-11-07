package gemini

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"testing"

	"github.com/tashil/data-sharing/backend/internal/domain"
)

// Header layout copied from a real FATHALLA pivot export (title row, blank row, header);
// data rows are made up.
func book3LikeRows() [][]string {
	rows := [][]string{
		{"Details for Sum of الاجمالى - YEAR: 2026, MONTH: JAN"},
		{""},
		{"المجموعة", "المورد", "الباركود", "الصنف", " سموحة", " ستانلى", "الاجمالى", "MONTH", "كمية سموحة", "كمية ستانلى", "اجمالى كميات", "YEAR"},
	}
	months := []string{"JAN", "seb", "aug"}
	for i := 0; i < 30; i++ {
		v1, v2, q1, q2 := 100*(i+1), 50*(i+1), i+1, 2*(i+1)
		rows = append(rows, []string{"منعمات", "ادكو (1)", fmt.Sprintf("62230002337%02d", i), "صنف", fmt.Sprint(v1), fmt.Sprint(v2), fmt.Sprint(v1 + v2), months[i%3], fmt.Sprint(q1), fmt.Sprint(q2), fmt.Sprint(q1 + q2), "2026"})
	}
	return rows
}

const book3Plan = `{"header_row_index":2,"skip_rows":[0,1],"layout":"wide","confidence":0.95,"columns":[
{"index":0,"role":"category"},{"index":1,"role":"supplier"},{"index":2,"role":"barcode"},{"index":3,"role":"product_name"},
{"index":4,"role":"store_value","branch":"سموحة"},{"index":5,"role":"store_value","branch":"ستانلى"},{"index":6,"role":"total_value"},
{"index":7,"role":"month"},{"index":8,"role":"store_quantity","branch":"سموحة"},{"index":9,"role":"store_quantity","branch":"ستانلى"},
{"index":10,"role":"total_quantity"},{"index":11,"role":"year"}]}`

func stubClient(responses map[string]string, calls *[]string) *Client {
	c := NewAgent("test-key", "tier1-model", false).WithTier2Model("tier2-model")
	c.mapper = func(_ context.Context, model, prompt string) (string, error) {
		*calls = append(*calls, model)
		if strings.Count(prompt, "\nrow ") > mappingSampleRows {
			return "", errors.New("sent more than the sample")
		}
		if r, ok := responses[model]; ok {
			return r, nil
		}
		return "", errors.New("unavailable")
	}
	return c
}

func TestAIMappingWideBook3Layout(t *testing.T) {
	x, _ := BuildSampleXLSX(book3LikeRows())
	var calls []string
	c := stubClient(map[string]string{"tier1-model": book3Plan}, &calls)
	p, err := c.AnalyzeAndNormalize(context.Background(), "Book3.xlsx", x)
	if err != nil {
		t.Fatal(err)
	}
	if p.MappingSource != MappingSourceAI || p.AiTierUsed != "tier1" || p.Validation == nil || p.Validation.Status != "ok" {
		t.Fatalf("unexpected: source=%s tier=%s validation=%+v", p.MappingSource, p.AiTierUsed, p.Validation)
	}
	if p.MappingConfidence != 0.95 || p.ConfidenceScore != 0.95 {
		t.Fatalf("expected real AI confidence 0.95, got mapping=%.2f score=%.2f", p.MappingConfidence, p.ConfidenceScore)
	}
	// sum over i=1..30: value 150*i = 69750, units 3*i = 1395
	if p.Validation.ExtractedValue != 69750 || p.Validation.ExtractedUnits != 1395 {
		t.Fatalf("totals: %+v", p.Validation)
	}
	if strings.Join(p.Validation.MonthsDetected, ",") != "2026-01,2026-08,2026-09" {
		t.Fatalf("months: %v", p.Validation.MonthsDetected)
	}
}

func TestAIMappingEscalatesToTier2(t *testing.T) {
	x, _ := BuildSampleXLSX(book3LikeRows())
	var calls []string
	low := strings.Replace(book3Plan, `"confidence":0.95`, `"confidence":0.3`, 1)
	c := stubClient(map[string]string{"tier1-model": low, "tier2-model": book3Plan}, &calls)
	p, err := c.AnalyzeAndNormalize(context.Background(), "Book3.xlsx", x)
	if err != nil {
		t.Fatal(err)
	}
	if p.AiTierUsed != "tier2" || !p.Tier2Escalated || len(calls) != 2 {
		t.Fatalf("tier=%s calls=%v", p.AiTierUsed, calls)
	}
}

func TestAIMappingUnavailableFallsBackToDeterministic(t *testing.T) {
	x, _ := BuildSampleXLSX(book3LikeRows())
	var calls []string
	c := stubClient(nil, &calls)
	p, err := c.AnalyzeAndNormalize(context.Background(), "Book3.xlsx", x)
	if err != nil {
		t.Fatal(err)
	}
	if p.MappingSource != MappingSourceDeterministic || p.Validation == nil || p.Validation.ExtractedUnits != 1395 {
		t.Fatalf("source=%s validation=%+v", p.MappingSource, p.Validation)
	}
	if p.AiModelUsed != "" || p.AiTierUsed != "" || p.Tier2Escalated {
		t.Fatalf("deterministic must not claim AI tier/model: model=%q tier=%q esc=%v", p.AiModelUsed, p.AiTierUsed, p.Tier2Escalated)
	}
}

func TestValidationRejectsUnreadColumns(t *testing.T) {
	p := &domain.NormalizedRetailIngestionPayload{}
	for i := 0; i < 50; i++ {
		p.NormalizedRecords = append(p.NormalizedRecords, domain.NormalizedRecord{QuantitySold: 1, TransactionDate: "2026-01-31"})
	}
	if v := validateExtraction(p, nil); v.Status != "rejected" {
		t.Fatalf("expected rejected, got %+v", v)
	}
	err := validationError("Book3.xlsx", validateExtraction(p, nil))
	if !errors.Is(err, ErrUploadValidation) {
		t.Fatalf("expected ErrUploadValidation")
	}
}

func TestValidationFlagsSheetTotalMismatchAndRejectsNoMonth(t *testing.T) {
	p := &domain.NormalizedRetailIngestionPayload{NormalizedRecords: []domain.NormalizedRecord{{QuantitySold: 102, NetRevenue: 1000, TransactionDate: "2026-01-31"}}}
	v := validateExtraction(p, &mappingSourceTotals{units: 102, value: 1000, sheetUnits: 100, sheetValue: 1000, hasPeriodColumn: true})
	if v.Status != "flagged" {
		t.Fatalf("expected flagged, got %+v", v)
	}
	v = validateExtraction(p, &mappingSourceTotals{units: 102, value: 1000})
	if v.Status != "rejected" {
		t.Fatalf("expected rejected without month, got %+v", v)
	}
}
