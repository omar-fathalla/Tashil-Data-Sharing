package ingestion

import (
	"context"
	"encoding/json"
	"sync/atomic"
	"testing"

	"github.com/tashil/data-sharing/backend/internal/service/bigquery"
	"github.com/tashil/data-sharing/backend/internal/service/firestore"
	"github.com/tashil/data-sharing/backend/internal/service/gemini"
)

// Correction save → re-upload must reuse the tenant-scoped mapping without another Gemini call;
// another tenant must not see that correction.
func TestSaveApprovedMappingCorrectionThenReuploadReuses(t *testing.T) {
	bq := bigquery.NewClient("test-proj", "test-dataset", true)
	fs := firestore.NewClient("db", true)
	x, planJSON := aiWideFixture(t)
	arch := t.TempDir()

	var mapCalls atomic.Int64
	agent := gemini.NewAgent("test-key", "tier1-model", false).
		WithTier2Model("tier2-model").
		WithMappingPlanDir(arch).
		WithColumnMapper(func(_ context.Context, model, prompt string) (string, error) {
			mapCalls.Add(1)
			return planJSON, nil
		})
	p := NewProcessor(agent, bq, fs).WithArchiveDir(arch)

	preview, err := p.ProcessUploadWithDryRun(context.Background(), "tenant-adeco", "Book3.xlsx", x, true, "fathalla")
	if err != nil {
		t.Fatal(err)
	}
	if preview.MappingSource != gemini.MappingSourceAI || mapCalls.Load() != 1 {
		t.Fatalf("setup: source=%s calls=%d", preview.MappingSource, mapCalls.Load())
	}

	var corrected gemini.ColumnMapPlan
	if err := json.Unmarshal([]byte(planJSON), &corrected); err != nil {
		t.Fatal(err)
	}
	for i := range corrected.Columns {
		if corrected.Columns[i].Branch == "سموحة" {
			corrected.Columns[i].Branch = "سموحة-approved"
		}
	}
	if err := p.SaveApprovedMappingCorrection("tenant-adeco", preview.BatchID, &corrected); err != nil {
		t.Fatal(err)
	}
	// Cross-tenant save must fail and not poison tenant-adeco cache.
	if err := p.SaveApprovedMappingCorrection("tenant-other", preview.BatchID, &corrected); err == nil {
		t.Fatal("cross-tenant correction save must fail")
	}

	again, err := p.ProcessUploadWithDryRun(context.Background(), "tenant-adeco", "Book3.xlsx", x, true, "fathalla")
	if err != nil {
		t.Fatal(err)
	}
	if mapCalls.Load() != 1 {
		t.Fatalf("re-upload must reuse correction without Gemini: calls=%d", mapCalls.Load())
	}
	if again.MappingSource != gemini.MappingSourceCache {
		t.Fatalf("re-upload source=%s want cache", again.MappingSource)
	}

	other, err := p.ProcessUploadWithDryRun(context.Background(), "tenant-other", "Book3.xlsx", x, true, "fathalla")
	if err != nil {
		t.Fatal(err)
	}
	if mapCalls.Load() != 2 || other.MappingSource != gemini.MappingSourceAI {
		t.Fatalf("tenant isolation broken: calls=%d source=%s", mapCalls.Load(), other.MappingSource)
	}
}
