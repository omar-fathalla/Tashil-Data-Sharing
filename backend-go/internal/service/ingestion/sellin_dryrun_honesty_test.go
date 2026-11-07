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
	if res.ConfidenceScore != 0 || res.MappingConfidence != 0 {
		t.Fatalf("deterministic sell-in must not present AI confidence (score=%.2f mapping=%.2f)", res.ConfidenceScore, res.MappingConfidence)
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

// Dry-run on instance A, commit on instance B sharing the archive mount (Sell-In restageFromDisk).
func TestSellInStagedCommitAcrossInstances(t *testing.T) {
	dir := t.TempDir()
	a := NewProcessor(gemini.NewAgent("", "m", true), bigquery.NewClient("test-proj", "test-dataset", true), firestore.NewClient("db", true)).WithArchiveDir(dir)
	a.SetCustomerRegistry(customers.New(&customers.MemoryStore{}))
	preview := sopWorkbook(t,
		[]string{"Invoice", "1", "2026-04-05", "FG-X", "صنف", "CTN", "2", "L", "C1", "عائله فتح الله ماركت - طنطا", "KA", "220", "ALX"},
	)
	res, err := a.ProcessSellInPlan(interactive(context.Background(), UploadGuards{}), "tenant-adeco", "cross_si.xlsx", preview, true, "fathalla")
	if err != nil {
		t.Fatal(err)
	}
	if res.ConfidenceScore != 0 {
		t.Fatalf("deterministic sell-in must not present AI confidence, got %.2f", res.ConfidenceScore)
	}
	if _, _, err := a.loadStaged("tenant-adeco", res.BatchID); err != nil {
		t.Fatalf("sell-in dry-run must persist under _staged: %v", err)
	}
	if n := len(a.bqRepo.(interface {
		SellInRecordsSnapshot(string) []domain.SellInRecord
	}).SellInRecordsSnapshot("tenant-adeco")); n != 0 {
		t.Fatalf("dry-run committed %d rows on A", n)
	}

	bqB := bigquery.NewClient("test-proj", "test-dataset", true)
	b := NewProcessor(gemini.NewAgent("", "m", true), bqB, firestore.NewClient("db", true)).WithArchiveDir(dir)
	b.SetCustomerRegistry(customers.New(&customers.MemoryStore{}))
	out, err := b.CommitStagedUpload(interactive(context.Background(), UploadGuards{}), "tenant-adeco", res.BatchID, "fathalla")
	if err != nil {
		t.Fatalf("commit on B via restageFromDisk: %v", err)
	}
	if !out.IsCommitted || out.ValidRows < 1 {
		t.Fatalf("expected committed sell-in on B, got %+v", out)
	}
	if n := len(bqB.SellInRecordsSnapshot("tenant-adeco")); n == 0 {
		t.Fatal("B must have committed Sell-In rows after cross-instance commit")
	}
	if _, _, err := b.loadStaged("tenant-adeco", res.BatchID); err == nil {
		t.Fatal("staging must be cleared after successful commit")
	}
}

func TestSellInDryRunUnknownBarcodeViaEnrichment(t *testing.T) {
	bq := bigquery.NewClient("test-proj", "test-dataset", true)
	p := NewProcessor(gemini.NewAgent("", "m", true), bq, firestore.NewClient("db", true)).WithArchiveDir(t.TempDir())
	p.SetCustomerRegistry(customers.New(&customers.MemoryStore{}))
	x := sopWorkbook(t,
		[]string{"Invoice", "1", "2026-05-05", "UNK-999", "صنف مش في الكارتة", "CTN", "1", "L", "C1", "عائله فتح الله ماركت - طنطا", "KA", "40", "ALX"},
	)
	res, err := p.ProcessSellInPlan(interactive(context.Background(), UploadGuards{}), "tenant-adeco", "unk.xlsx", x, true, "fathalla")
	if err != nil {
		t.Fatal(err)
	}
	if len(res.UnknownBarcodes) == 0 {
		t.Fatal("dry-run must report unknown barcodes via EnrichSellInRecords without SetSellInRecords")
	}
	if n := len(bq.SellInRecordsSnapshot("tenant-adeco")); n != 0 {
		t.Fatalf("preview must not commit, got %d rows", n)
	}
}

func TestSellInCommitFailureKeepsStaged(t *testing.T) {
	dir := t.TempDir()
	bq := bigquery.NewClient("test-proj", "test-dataset", true)
	p := NewProcessor(gemini.NewAgent("", "m", true), bq, firestore.NewClient("db", true)).WithArchiveDir(dir)
	p.SetCustomerRegistry(customers.New(&customers.MemoryStore{}))
	x := sopWorkbook(t,
		[]string{"Invoice", "1", "2026-06-05", "FG-1", "صنف", "CTN", "1", "L", "C1", "عائله فتح الله ماركت - طنطا", "KA", "10", "ALX"},
	)
	res, err := p.ProcessSellInPlan(interactive(context.Background(), UploadGuards{}), "tenant-adeco", "keep.xlsx", x, true, "fathalla")
	if err != nil {
		t.Fatal(err)
	}
	// Force a commit failure: replace staged Sell-In with a row missing period so SetSellInRecords rejects.
	p.stagedMu.Lock()
	st := p.staged[res.BatchID]
	st.SellInRecords = []domain.SellInRecord{{Year: 0, MonthNum: 0, NetValueEGP: 1, TenantID: "tenant-adeco"}}
	p.stagedMu.Unlock()
	_, err = p.CommitStagedUpload(interactive(context.Background(), UploadGuards{}), "tenant-adeco", res.BatchID, "fathalla")
	if err == nil {
		t.Fatal("expected SetSellInRecords failure")
	}
	p.stagedMu.Lock()
	_, still := p.staged[res.BatchID]
	p.stagedMu.Unlock()
	if !still {
		t.Fatal("failed commit must restore in-memory staged preview")
	}
	if _, _, err := p.loadStaged("tenant-adeco", res.BatchID); err != nil {
		t.Fatalf("disk staging must remain after failed commit: %v", err)
	}
}
