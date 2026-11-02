package gemini

import (
	"context"
	"testing"
)

// Re-reading the same archived file (another instance, or after a restart with a shared plan dir) must reuse
// the stored mapping plan instead of calling Gemini again, and produce the same totals.
func TestMappingPlanReusedAcrossReadsAndInstances(t *testing.T) {
	x, _ := BuildSampleXLSX(book3LikeRows())
	dir := t.TempDir()
	var calls []string
	c := stubClient(map[string]string{"tier1-model": book3Plan}, &calls).WithMappingPlanDir(dir)
	first, err := c.AnalyzeAndNormalize(context.Background(), "Book3.xlsx", x)
	if err != nil {
		t.Fatal(err)
	}
	second, err := c.AnalyzeAndNormalize(context.Background(), "Book3.xlsx", x)
	if err != nil {
		t.Fatal(err)
	}
	if len(calls) != 1 {
		t.Fatalf("second read must not call Gemini, calls=%v", calls)
	}
	if first.Validation.ExtractedValue != second.Validation.ExtractedValue || second.MappingSource != "ai" {
		t.Fatalf("cached plan changed the result: %+v vs %+v", first.Validation, second.Validation)
	}

	// A fresh client (another instance) sharing the plan directory also skips Gemini.
	var calls2 []string
	other := stubClient(map[string]string{}, &calls2).WithMappingPlanDir(dir)
	p, err := other.AnalyzeAndNormalize(context.Background(), "Book3.xlsx", x)
	if err != nil {
		t.Fatal(err)
	}
	if len(calls2) != 0 || p.Validation.ExtractedValue != first.Validation.ExtractedValue {
		t.Fatalf("shared plan not reused: calls=%v validation=%+v", calls2, p.Validation)
	}
}

func TestMappingPlanCacheKeyedByContent(t *testing.T) {
	if mappingPlanKey("a") == mappingPlanKey("b") || mappingPlanKey("a") != mappingPlanKey("a") {
		t.Fatal("key must be a stable content hash")
	}
}
