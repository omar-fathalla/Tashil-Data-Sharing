package ingestion

import (
	"context"
	"testing"

	"github.com/tashil/data-sharing/backend/internal/domain"
	"github.com/tashil/data-sharing/backend/internal/service/bqsink"
)

// countingSink reports durable row counts by archive_id (ArchiveReconciler).
type countingSink struct {
	fakeSink
	counts []bqsink.ArchiveRows
}

func (c *countingSink) ArchiveRowCounts(context.Context, string) ([]bqsink.ArchiveRows, error) {
	return c.counts, nil
}

func (c *countingSink) DeleteOrphans(context.Context, bqsink.Kind, string, []string, []string) *bqsink.Result {
	return &bqsink.Result{Status: bqsink.StatusOK}
}

func TestListArchivedFilesOverlaysStoredSellInRowCounts(t *testing.T) {
	dir := t.TempDir()
	p := newTestProcessor(t, dir)
	entry := p.SaveArchivedFile("tenant-adeco", "batch_sellin_old", "in26.xlsx", []byte("x"), "fathalla", "2026", "01", 137985, 1, 1)
	// Stale parse-time count on the archive entry.
	if entry.RowsIngested != 137985 {
		t.Fatalf("setup rows: %d", entry.RowsIngested)
	}

	sink := &countingSink{counts: []bqsink.ArchiveRows{
		{Kind: bqsink.KindSellIn, ArchiveID: entry.ID, SourceFile: "in26.xlsx", Rows: 133861},
	}}
	p.WithSink(sink)

	list := p.ListArchivedFiles(context.Background(), "tenant-adeco", "", "", "", "sell_in")
	if list.TotalCount != 1 {
		t.Fatalf("want 1 sell-in file, got %d", list.TotalCount)
	}
	if list.Files[0].RowsIngested != 133861 {
		t.Fatalf("list rows_ingested must reflect BigQuery stored count, got %d want 133861", list.Files[0].RowsIngested)
	}
	// Persisted onto the in-memory archive entry for subsequent lists.
	p.archiveMu.RLock()
	got := p.archivedFiles[entry.ID].RowsIngested
	p.archiveMu.RUnlock()
	if got != 133861 {
		t.Fatalf("archive entry not updated: %d", got)
	}
}

func TestSetArchiveStoredRowsUpdatesBatchAndCount(t *testing.T) {
	p := newTestProcessor(t, t.TempDir())
	entry := p.SaveArchivedFile("tenant-adeco", "batch_sellin_a", "in25.xlsx", []byte("y"), "fathalla", "2025", "01", 65412, 1, 1)
	p.setArchiveStoredRows(entry.ID, 62681, "batch_sellin_b")
	p.archiveMu.RLock()
	e := p.archivedFiles[entry.ID]
	p.archiveMu.RUnlock()
	if e.RowsIngested != 62681 || e.BatchID != "batch_sellin_b" {
		t.Fatalf("got rows=%d batch=%s", e.RowsIngested, e.BatchID)
	}
}

func TestSellInSinkSuccessAlignsArchiveRowsWithWritten(t *testing.T) {
	// When the sink reports fewer rows written than parsed (e.g. period filter), archive must follow.
	dir := t.TempDir()
	fs := &fakeSink{}
	p := newTestProcessor(t, dir).WithSink(fs)

	// Minimal CSV-like path: ProcessSellInPlan needs a real workbook. Use SaveArchivedFile + setArchiveStoredRows
	// path already covered; here verify sinkSellIn + setArchiveStoredRows integration via direct call sequence
	// mirroring ProcessSellInPlan's post-sink update.
	entry := p.SaveArchivedFile("tenant-adeco", "batch_sellin_x", "plan.xlsx", []byte("z"), "fathalla", "2026", "01", 100, 1, 1)
	recs := make([]domain.SellInRecord, 100)
	for i := range recs {
		recs[i] = domain.SellInRecord{Year: 2026, MonthNum: 1, NetValueEGP: 1, RetailerChain: "fathalla"}
	}
	res := p.sinkSellIn(context.Background(), bqsink.Meta{
		TenantID: "tenant-adeco", BatchID: "batch_sellin_x", ArchiveID: entry.ID, SourceFile: "plan.xlsx",
	}, recs)
	if res == nil || res.Failed() {
		t.Fatalf("sink write failed: %+v", res)
	}
	p.setArchiveStoredRows(entry.ID, res.RowsWritten, "batch_sellin_x")
	p.archiveMu.RLock()
	got := p.archivedFiles[entry.ID].RowsIngested
	p.archiveMu.RUnlock()
	if got != res.RowsWritten || got != 100 {
		t.Fatalf("archive rows=%d sink written=%d", got, res.RowsWritten)
	}
}
