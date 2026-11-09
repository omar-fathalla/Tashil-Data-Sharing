package ingestion

import (
	"context"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
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

func TestCommitSurfacesMappingLearnDiskFailure(t *testing.T) {
	bq := bigquery.NewClient("test-proj", "test-dataset", true)
	fs := firestore.NewClient("db", true)
	x, planJSON := aiWideFixture(t)
	arch := t.TempDir()
	planDir := t.TempDir()

	agent := gemini.NewAgent("test-key", "tier1-model", false).
		WithTier2Model("tier2-model").
		WithMappingPlanDir(planDir).
		WithColumnMapper(func(_ context.Context, model, prompt string) (string, error) {
			return planJSON, nil
		})
	p := NewProcessor(agent, bq, fs).WithArchiveDir(arch)

	preview, err := p.ProcessUploadWithDryRun(context.Background(), "tenant-adeco", "Book3.xlsx", x, true, "fathalla")
	if err != nil {
		t.Fatal(err)
	}
	var corrected gemini.ColumnMapPlan
	_ = json.Unmarshal([]byte(planJSON), &corrected)
	if err := p.SaveApprovedMappingCorrection("tenant-adeco", preview.BatchID, &corrected); err != nil {
		t.Fatal(err)
	}

	// After a successful save, block further durable writes so commit-time re-learn fails.
	tenantSeg := filepath.Join(planDir, "adeco")
	entries, err := os.ReadDir(tenantSeg)
	if err != nil {
		t.Fatal(err)
	}
	for _, e := range entries {
		_ = os.Remove(filepath.Join(tenantSeg, e.Name()))
	}
	_ = os.Remove(tenantSeg)
	if err := os.WriteFile(tenantSeg, []byte("block"), 0o644); err != nil {
		t.Fatal(err)
	}

	_, err = p.CommitStagedUpload(context.Background(), "tenant-adeco", preview.BatchID, "fathalla")
	if err == nil {
		t.Fatal("commit must surface mapping learn disk failure")
	}
	msg := err.Error()
	if !strings.Contains(msg, "البيانات اتحفظت بنجاح") || !strings.Contains(msg, "تصحيح الربط ما اتسجلش") {
		t.Fatalf("must say data saved but correction not learned, got %v", err)
	}
	if strings.Contains(msg, "مفيش حاجة اتحفظت") {
		t.Fatalf("must not imply nothing was saved: %v", err)
	}
}
