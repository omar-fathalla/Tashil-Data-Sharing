package gemini

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/tashil/data-sharing/backend/internal/domain"
	"github.com/tashil/data-sharing/backend/internal/service/gemini/guardrails"
)

type goldenExpected struct {
	ID                              string   `json:"id"`
	Filename                        string   `json:"filename"`
	Source                          string   `json:"source"`
	Kind                            string   `json:"kind"`
	MappingSource                   string   `json:"mapping_source"`
	RetailerDetected                string   `json:"retailer_detected"`
	MinRecords                      int      `json:"min_records"`
	ExtractedUnits                  *int     `json:"extracted_units"`
	ExtractedValue                  *float64 `json:"extracted_value"`
	MonthsDetected                  []string `json:"months_detected"`
	ValidationStatus                string   `json:"validation_status"`
	RequiresHumanApprovalWhenStaged bool     `json:"requires_human_approval_when_staged"`
	SchemaPlanFile                  string   `json:"schema_plan_file"`
}

func goldenRoot(t *testing.T) string {
	t.Helper()
	return filepath.Join("testdata", "golden")
}

func loadGoldenExpected(t *testing.T, id string) goldenExpected {
	t.Helper()
	raw, err := os.ReadFile(filepath.Join(goldenRoot(t), id, "expected.json"))
	if err != nil {
		t.Fatal(err)
	}
	var exp goldenExpected
	if err := json.Unmarshal(raw, &exp); err != nil {
		t.Fatal(err)
	}
	return exp
}

func assertGoldenPayload(t *testing.T, exp goldenExpected, p *domain.NormalizedRetailIngestionPayload) {
	t.Helper()
	if p == nil {
		t.Fatal("nil payload")
	}
	if exp.RetailerDetected != "" && p.RetailerDetected != exp.RetailerDetected {
		t.Fatalf("retailer=%q want %q", p.RetailerDetected, exp.RetailerDetected)
	}
	if exp.MappingSource != "" && p.MappingSource != exp.MappingSource {
		t.Fatalf("mapping_source=%q want %q", p.MappingSource, exp.MappingSource)
	}
	if len(p.NormalizedRecords) < exp.MinRecords {
		t.Fatalf("records=%d want >= %d", len(p.NormalizedRecords), exp.MinRecords)
	}
	if exp.ValidationStatus != "" {
		if p.Validation == nil || p.Validation.Status != exp.ValidationStatus {
			t.Fatalf("validation=%+v want status %q", p.Validation, exp.ValidationStatus)
		}
	}
	if exp.ExtractedUnits != nil {
		if p.Validation == nil || p.Validation.ExtractedUnits != *exp.ExtractedUnits {
			t.Fatalf("units=%v want %d", p.Validation, *exp.ExtractedUnits)
		}
	}
	if exp.ExtractedValue != nil {
		if p.Validation == nil || p.Validation.ExtractedValue != *exp.ExtractedValue {
			t.Fatalf("value=%v want %v", p.Validation, *exp.ExtractedValue)
		}
	}
	if len(exp.MonthsDetected) > 0 {
		got := ""
		if p.Validation != nil {
			got = strings.Join(p.Validation.MonthsDetected, ",")
		}
		want := strings.Join(exp.MonthsDetected, ",")
		if got != want {
			t.Fatalf("months=%q want %q", got, want)
		}
	}
	if exp.RequiresHumanApprovalWhenStaged {
		status := ""
		anoms := 0
		if p.Validation != nil {
			status = p.Validation.Status
		}
		anoms = len(p.AnomaliesDetected)
		d := guardrails.EvaluateApproval(guardrails.Input{
			MappingSource:     p.MappingSource,
			MappingConfidence: p.MappingConfidence,
			IsStaged:          true,
			ValidationStatus:  status,
			AnomalyCount:      anoms,
		})
		if !d.RequiresHumanApproval {
			t.Fatalf("expected human approval for staged golden %s", exp.ID)
		}
		m := guardrails.BuildSuccessMetrics(guardrails.EventsFromMappingSource(p.MappingSource), p.MappingSource, p.MappingConfidence, d)
		if m.ArabicSummary == "" || !m.HumanApprovalRequired {
			t.Fatalf("success metrics incomplete: %+v", m)
		}
	}
}

func TestGoldenSchemaPlansValidate(t *testing.T) {
	root := goldenRoot(t)
	entries, err := os.ReadDir(root)
	if err != nil {
		t.Fatal(err)
	}
	n := 0
	for _, e := range entries {
		if !e.IsDir() {
			continue
		}
		planPath := filepath.Join(root, e.Name(), "mapping_plan.json")
		raw, err := os.ReadFile(planPath)
		if err != nil {
			if os.IsNotExist(err) {
				continue
			}
			t.Fatal(err)
		}
		if _, err := guardrails.ValidateColumnMapPlanJSON(raw); err != nil {
			t.Fatalf("%s: %v", planPath, err)
		}
		n++
	}
	if n < 2 {
		t.Fatalf("expected at least 2 mapping plans, got %d", n)
	}
}

func TestGoldenFathallaWideRegression(t *testing.T) {
	exp := loadGoldenExpected(t, "fathalla-wide-jan2026")
	rows := [][]string{
		{"Details for Sum of الاجمالى - YEAR: 2026, MONTH: JAN"},
		{""},
		{"المجموعة", "المورد", "الباركود", "الصنف", " سموحة", " ستانلى", "الاجمالى", "MONTH", "كمية سموحة", "كمية ستانلى", "اجمالى كميات", "YEAR"},
	}
	for i := 0; i < 5; i++ {
		rows = append(rows, []string{
			"منعمات", "ادكو (1)", fmt.Sprintf("62230002999%02d", i), "صنف QA",
			"500", "400", "900", "JAN", "3", "3", "6", "2026",
		})
	}
	x, err := BuildSampleXLSX(rows)
	if err != nil {
		t.Fatal(err)
	}
	t.Setenv("ENVIRONMENT", "development")
	c := NewAgent("", "gemini-3.8-flash", true)
	p, err := c.AnalyzeAndNormalize(context.Background(), exp.Filename, x)
	if err != nil {
		t.Fatal(err)
	}
	assertGoldenPayload(t, exp, p)

	planRaw, err := os.ReadFile(filepath.Join(goldenRoot(t), "fathalla-wide-jan2026", "mapping_plan.json"))
	if err != nil {
		t.Fatal(err)
	}
	var calls []string
	c2 := stubClient(map[string]string{"tier1-model": string(planRaw)}, &calls)
	p2, err := c2.AnalyzeAndNormalize(context.Background(), exp.Filename, x)
	if err != nil {
		t.Fatal(err)
	}
	aiExp := exp
	aiExp.MappingSource = MappingSourceAI
	assertGoldenPayload(t, aiExp, p2)
}

func TestGoldenCarrefourLongRegression(t *testing.T) {
	exp := loadGoldenExpected(t, "carrefour-long-sample")
	csv := []byte("Store_Code_Branch,Barcode,Item_Description,Sales_Units,Net_Val_EGP,Transaction_Date\n" +
		"Carrefour Maadi City Center,6221155001234,Adeco Olive Oil QA,10,2500.0,2026-01-10\n" +
		"Carrefour Dandy Mall,6221155001241,Adeco Sunflower QA,20,2200.0,2026-01-11\n")
	t.Setenv("ENVIRONMENT", "development")
	c := NewAgent("", "gemini-3.8-flash", true)
	p, err := c.AnalyzeAndNormalize(context.Background(), exp.Filename, csv)
	if err != nil {
		t.Fatal(err)
	}
	assertGoldenPayload(t, exp, p)
}

func TestGoldenLivetestHistoricalFilesParseExpected(t *testing.T) {
	t.Run("sellin-sop-qa", func(t *testing.T) {
		exp := loadGoldenExpected(t, "sellin-sop-qa")
		path := filepath.Join("..", "ingestion", "testdata", "livetest", exp.Filename)
		raw, err := os.ReadFile(path)
		if err != nil {
			t.Fatal(err)
		}
		recs, report, err := ParseSellInPlanWorkbookWithReport("tenant-qa", exp.Filename, raw, "qa_test")
		if err != nil {
			t.Fatal(err)
		}
		if len(recs) < exp.MinRecords {
			t.Fatalf("records=%d want >= %d layout=%v", len(recs), exp.MinRecords, report)
		}
		var sum float64
		for _, r := range recs {
			sum += r.NetValueEGP
		}
		if exp.ExtractedValue != nil && sum != *exp.ExtractedValue {
			t.Fatalf("value=%.2f want %.2f", sum, *exp.ExtractedValue)
		}
		d := guardrails.EvaluateApproval(guardrails.Input{MappingSource: "deterministic", IsStaged: true})
		if !d.RequiresHumanApproval {
			t.Fatal("staged sell-in must require human approval")
		}
	})
	t.Run("sellout-form-vs-sheet", func(t *testing.T) {
		exp := loadGoldenExpected(t, "sellout-form-vs-sheet")
		path := filepath.Join("..", "ingestion", "testdata", "livetest", exp.Filename)
		raw, err := os.ReadFile(path)
		if err != nil {
			t.Fatal(err)
		}
		t.Setenv("ENVIRONMENT", "development")
		c := NewAgent("", "gemini-3.8-flash", true)
		p, err := c.AnalyzeAndNormalize(context.Background(), exp.Filename, raw)
		if err != nil {
			t.Fatal(err)
		}
		assertGoldenPayload(t, exp, p)
	})
}

func TestGoldenProdRefusesMockOnOpaqueHistorical(t *testing.T) {
	t.Setenv("ENVIRONMENT", "production")
	c := NewAgent("", "gemini-3.8-flash", true)
	_, err := c.AnalyzeAndNormalize(context.Background(), "opaque_historical.bin", []byte{0x00, 0x01})
	if err == nil {
		t.Fatal("expected mock refusal in production")
	}
}
