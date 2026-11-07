package ingestion

import (
	"context"
	"sync/atomic"
	"testing"

	"github.com/tashil/data-sharing/backend/internal/domain"
	"github.com/tashil/data-sharing/backend/internal/service/bigquery"
	"github.com/tashil/data-sharing/backend/internal/service/customers"
	"github.com/tashil/data-sharing/backend/internal/service/firestore"
	"github.com/tashil/data-sharing/backend/internal/service/gemini"
)

// countingAgent wraps a real agent and counts AnalyzeAndNormalize calls.
type countingAgent struct {
	inner gemini.Agent
	n     atomic.Int64
}

func (a *countingAgent) AnalyzeAndNormalize(ctx context.Context, filename string, rawContent []byte) (*domain.NormalizedRetailIngestionPayload, error) {
	a.n.Add(1)
	return a.inner.AnalyzeAndNormalize(ctx, filename, rawContent)
}

func TestSellInDryRunDoesNotChangeCommittedData(t *testing.T) {
	bq := bigquery.NewClient("test-proj", "test-dataset", true)
	fs := firestore.NewClient("db", true)
	agent := gemini.NewAgent("", "m", true)
	p := NewProcessor(agent, bq, fs).WithArchiveDir(t.TempDir())
	reg := customers.New(&customers.MemoryStore{})
	p.SetCustomerRegistry(reg)

	// Seed committed Sell-In for tenant-adeco.
	seed := sopWorkbook(t,
		[]string{"Invoice", "1", "2026-01-05", "FG-1", "صنف", "CTN", "3", "L", "C1", "عائله فتح الله ماركت - طنطا", "KA", "150", "ALX"},
	)
	if _, err := p.ProcessSellInPlan(interactive(context.Background(), UploadGuards{}), "tenant-adeco", "seed.xlsx", seed, false, "fathalla"); err != nil {
		t.Fatal(err)
	}
	before := bq.SellInRecordsSnapshot("tenant-adeco")
	if len(before) == 0 {
		t.Fatal("expected seeded committed rows")
	}

	preview := sopWorkbook(t,
		[]string{"Invoice", "2", "2026-02-05", "FG-2", "صنف2", "CTN", "5", "L", "C1", "عائله فتح الله ماركت - طنطا", "KA", "999", "ALX"},
	)
	res, err := p.ProcessSellInPlan(interactive(context.Background(), UploadGuards{}), "tenant-adeco", "preview.xlsx", preview, true, "fathalla")
	if err != nil {
		t.Fatal(err)
	}
	if !res.IsStaged || res.IsCommitted {
		t.Fatalf("expected staged preview, got staged=%v committed=%v", res.IsStaged, res.IsCommitted)
	}
	if res.MappingSource != gemini.MappingSourceDeterministic {
		t.Fatalf("deterministic sell-in should report mapping_source=deterministic, got %q", res.MappingSource)
	}
	after := bq.SellInRecordsSnapshot("tenant-adeco")
	if len(after) != len(before) {
		t.Fatalf("dry-run changed committed row count: before=%d after=%d", len(before), len(after))
	}
	var beforeSum, afterSum float64
	for _, r := range before {
		beforeSum += r.NetValueEGP
	}
	for _, r := range after {
		afterSum += r.NetValueEGP
	}
	if beforeSum != afterSum {
		t.Fatalf("dry-run changed committed totals: before=%.2f after=%.2f", beforeSum, afterSum)
	}

	// Staged preview must still be commitable without re-calling Gemini.
	counter := &countingAgent{inner: agent}
	p.geminiAgent = counter
	beforeCalls := counter.n.Load()
	committed, err := p.CommitStagedUpload(interactive(context.Background(), UploadGuards{}), "tenant-adeco", res.BatchID, "fathalla")
	if err != nil {
		t.Fatal(err)
	}
	if !committed.IsCommitted {
		t.Fatal("expected committed result")
	}
	if counter.n.Load() != beforeCalls {
		t.Fatalf("commit must not re-call AI, calls=%d", counter.n.Load())
	}
	final := bq.SellInRecordsSnapshot("tenant-adeco")
	var finalSum float64
	for _, r := range final {
		finalSum += r.NetValueEGP
	}
	if finalSum < beforeSum+999-0.01 {
		t.Fatalf("commit should add preview rows, sum=%.2f", finalSum)
	}
}

func TestSellInDryRunTenantIsolation(t *testing.T) {
	bq := bigquery.NewClient("test-proj", "test-dataset", true)
	p := NewProcessor(gemini.NewAgent("", "m", true), bq, firestore.NewClient("db", true)).WithArchiveDir(t.TempDir())
	p.SetCustomerRegistry(customers.New(&customers.MemoryStore{}))

	seedA := sopWorkbook(t,
		[]string{"Invoice", "1", "2026-01-05", "FG-1", "صنف", "CTN", "1", "L", "C1", "عائله فتح الله ماركت - طنطا", "KA", "100", "ALX"},
	)
	if _, err := p.ProcessSellInPlan(interactive(context.Background(), UploadGuards{}), "tenant-adeco", "a.xlsx", seedA, false, "fathalla"); err != nil {
		t.Fatal(err)
	}
	previewB := sopWorkbook(t,
		[]string{"Invoice", "1", "2026-03-05", "FG-9", "صنف", "CTN", "1", "L", "C1", "عائله فتح الله ماركت - طنطا", "KA", "50", "ALX"},
	)
	if _, err := p.ProcessSellInPlan(interactive(context.Background(), UploadGuards{}), "tenant-unilever", "b.xlsx", previewB, true, "fathalla"); err != nil {
		t.Fatal(err)
	}
	if n := len(bq.SellInRecordsSnapshot("tenant-adeco")); n != 1 {
		t.Fatalf("tenant-adeco committed rows changed by other tenant preview: %d", n)
	}
	if n := len(bq.SellInRecordsSnapshot("tenant-unilever")); n != 0 {
		t.Fatalf("tenant-unilever preview must not commit: %d", n)
	}
}

func TestSellInRejectionDoesNotWrite(t *testing.T) {
	bq := bigquery.NewClient("test-proj", "test-dataset", true)
	p := NewProcessor(gemini.NewAgent("", "m", true), bq, firestore.NewClient("db", true)).WithArchiveDir(t.TempDir())
	x := sopWorkbook(t, []string{"Invoice", "1", "not a date", "FG-1", "صنف", "CTN", "2", "L", "C1", "عائله فتح الله ماركت - طنطا", "KA", "100", "ALX"})
	_, err := p.ProcessSellInPlan(interactive(context.Background(), UploadGuards{}), "tenant-adeco", "bad.xlsx", x, false, "fathalla")
	if err == nil {
		t.Fatal("expected rejection")
	}
	if n := len(bq.SellInRecordsSnapshot("tenant-adeco")); n != 0 {
		t.Fatalf("rejected upload wrote %d rows", n)
	}
}
