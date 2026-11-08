package ingestion

import (
	"context"
	"errors"
	"testing"

	"github.com/tashil/data-sharing/backend/internal/service/bigquery"
	"github.com/tashil/data-sharing/backend/internal/service/firestore"
	"github.com/tashil/data-sharing/backend/internal/service/gemini"
	"github.com/tashil/data-sharing/backend/internal/service/gemini/guardrails"
)

func aiWideFixture(t *testing.T) ([]byte, string) {
	t.Helper()
	rows := [][]string{
		{"Details for Sum of الاجمالى - YEAR: 2026, MONTH: JAN"},
		{""},
		{"المجموعة", "المورد", "الباركود", "الصنف", " سموحة", " ستانلى", "الاجمالى", "MONTH", "كمية سموحة", "كمية ستانلى", "اجمالى كميات", "YEAR"},
		{"منعمات", "ادكو (1)", "6223000299901", "صنف QA", "500", "400", "900", "JAN", "3", "3", "6", "2026"},
	}
	x, err := gemini.BuildSampleXLSX(rows)
	if err != nil {
		t.Fatal(err)
	}
	plan := `{"header_row_index":2,"skip_rows":[0,1],"layout":"wide","confidence":0.95,"columns":[
{"index":0,"role":"category"},{"index":1,"role":"supplier"},{"index":2,"role":"barcode"},{"index":3,"role":"product_name"},
{"index":4,"role":"store_value","branch":"سموحة"},{"index":5,"role":"store_value","branch":"ستانلى"},{"index":6,"role":"total_value"},
{"index":7,"role":"month"},{"index":8,"role":"store_quantity","branch":"سموحة"},{"index":9,"role":"store_quantity","branch":"ستانلى"},
{"index":10,"role":"total_quantity"},{"index":11,"role":"year"}]}`
	return x, plan
}

func stubAIAgent(plan string) *gemini.Client {
	return gemini.NewAgent("test-key", "tier1-model", false).
		WithTier2Model("tier2-model").
		WithColumnMapper(func(_ context.Context, model, prompt string) (string, error) {
			return plan, nil
		})
}

// TestAIDirectCommitBlockedWithoutApproval ensures AI mapping never writes
// without a staged human commit (zero durable writes on the blocked path).
func TestAIDirectCommitBlockedWithoutApproval(t *testing.T) {
	bq := bigquery.NewClient("test-proj", "test-dataset", true)
	fs := firestore.NewClient("db", true)
	x, plan := aiWideFixture(t)
	p := NewProcessor(stubAIAgent(plan), bq, fs).WithArchiveDir(t.TempDir())

	before, _, err := bq.GetSellOutRecords(context.Background(), "tenant-qa", bigquery.RecordFilter{})
	if err != nil {
		t.Fatal(err)
	}
	beforeArch := len(p.ListArchivedFiles(context.Background(), "tenant-qa", "", "", "", "sell_out").Files)

	_, err = p.ProcessUploadWithDryRun(context.Background(), "tenant-qa", "fathalla_ai.xlsx", x, false, "fathalla")
	if err == nil || !errors.Is(err, guardrails.ErrHumanApprovalRequired) {
		t.Fatalf("expected ErrHumanApprovalRequired, got %v", err)
	}
	after, _, err := bq.GetSellOutRecords(context.Background(), "tenant-qa", bigquery.RecordFilter{})
	if err != nil {
		t.Fatal(err)
	}
	if len(after) != len(before) {
		t.Fatalf("blocked path must not write sell-out facts: before=%d after=%d", len(before), len(after))
	}
	afterArch := len(p.ListArchivedFiles(context.Background(), "tenant-qa", "", "", "", "sell_out").Files)
	if afterArch != beforeArch {
		t.Fatalf("blocked path must not archive: before=%d after=%d", beforeArch, afterArch)
	}
}

// TestAIStagedThenCommitWritesAfterApproval: preview is allowed; commit (human approval) persists.
func TestAIStagedThenCommitWritesAfterApproval(t *testing.T) {
	bq := bigquery.NewClient("test-proj", "test-dataset", true)
	fs := firestore.NewClient("db", true)
	x, plan := aiWideFixture(t)
	p := NewProcessor(stubAIAgent(plan), bq, fs).WithArchiveDir(t.TempDir())

	preview, err := p.ProcessUploadWithDryRun(context.Background(), "tenant-qa", "fathalla_ai.xlsx", x, true, "fathalla")
	if err != nil {
		t.Fatal(err)
	}
	if !preview.IsStaged || preview.MappingSource != gemini.MappingSourceAI {
		t.Fatalf("expected AI staged preview, got source=%s staged=%v", preview.MappingSource, preview.IsStaged)
	}
	if !preview.RequiresHumanApproval {
		t.Fatalf("preview must require human approval: metrics=%+v reasons=%v", preview.GuardrailMetrics, preview.GuardrailReasonsAR)
	}
	committed, err := p.CommitStagedUpload(context.Background(), "tenant-qa", preview.BatchID, "fathalla")
	if err != nil {
		t.Fatal(err)
	}
	if !committed.IsCommitted || committed.ValidRows == 0 {
		t.Fatalf("expected committed rows, got %+v", committed)
	}
	after, _, err := bq.GetSellOutRecords(context.Background(), "tenant-qa", bigquery.RecordFilter{RetailerChain: "fathalla"})
	if err != nil {
		t.Fatal(err)
	}
	if committed.ValidRows == 0 {
		t.Fatal("commit must report valid rows")
	}
	found := false
	for _, f := range after {
		if f.IngestionBatchID == committed.BatchID || f.Barcode == "6223000299901" {
			found = true
			break
		}
	}
	if !found {
		t.Fatalf("commit must persist AI facts; got %d fathalla records", len(after))
	}
}
