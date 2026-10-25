package ingestion

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"sync"
	"testing"

	"github.com/tashil/data-sharing/backend/internal/domain"
	"github.com/tashil/data-sharing/backend/internal/service/bigquery"
	"github.com/tashil/data-sharing/backend/internal/service/bqsink"
	"github.com/tashil/data-sharing/backend/internal/service/firestore"
	"github.com/tashil/data-sharing/backend/internal/service/gemini"
)

type fakeSink struct {
	mu       sync.Mutex
	fail     error
	sellOut  []bqsink.Meta
	modes    []bqsink.SellOutMode
	deletes  []bqsink.Meta
	rowsSeen int
}

func (f *fakeSink) Enabled() bool { return true }
func (f *fakeSink) res(table string, n int) *bqsink.Result {
	if f.fail != nil {
		return &bqsink.Result{Status: bqsink.StatusFailed, Table: table, Error: f.fail.Error()}
	}
	return &bqsink.Result{Status: bqsink.StatusOK, Table: table, RowsWritten: n}
}
func (f *fakeSink) WriteSellOut(_ context.Context, m bqsink.Meta, facts []domain.SellOutFact, mode bqsink.SellOutMode) *bqsink.Result {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.sellOut = append(f.sellOut, m)
	f.modes = append(f.modes, mode)
	f.rowsSeen += len(facts)
	return f.res(bqsink.TableSellOut, len(facts))
}
func (f *fakeSink) WriteSellIn(_ context.Context, _ bqsink.Meta, r []domain.SellInRecord) *bqsink.Result {
	return f.res(bqsink.TableSellIn, len(r))
}
func (f *fakeSink) WriteProductMaster(_ context.Context, _ bqsink.Meta, s *domain.ProductMasterSummaryResponse) *bqsink.Result {
	return f.res(bqsink.TableProductMaster, len(s.Items))
}
func (f *fakeSink) DeleteBatch(_ context.Context, k bqsink.Kind, m bqsink.Meta) *bqsink.Result {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.deletes = append(f.deletes, m)
	return f.res(bqsink.TableForKind(k).Name, 0)
}

func (f *fakeSink) DeleteTenant(_ context.Context, k bqsink.Kind, tenant string) *bqsink.Result {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.deletes = append(f.deletes, bqsink.Meta{TenantID: tenant})
	return f.res(bqsink.TableForKind(k).Name, 0)
}

func newTestProcessor(t *testing.T, dir string) *Processor {
	t.Helper()
	agent := gemini.NewAgent("", "gemini-3.8-flash", true)
	bqRepo := bigquery.NewClient("test-proj", "test-dataset", true)
	fsRepo := firestore.NewClient("test-db", true)
	p := NewProcessor(agent, bqRepo, fsRepo)
	if dir != "" {
		p.WithArchiveDir(dir)
	}
	return p
}

var sampleCSV = []byte("Header1,Header2\nSample1,Sample2\n")

func TestSinkDisabledByDefaultLeavesResponseUnchanged(t *testing.T) {
	p := newTestProcessor(t, "")
	res, err := p.ProcessUpload(context.Background(), "tenant-adeco", "carrefour_weekly.csv", sampleCSV)
	if err != nil {
		t.Fatal(err)
	}
	if res.BigQuerySync != nil {
		t.Fatalf("expected no bigquery_sync when sink disabled, got %+v", res.BigQuerySync)
	}
}

func TestSinkReceivesCommittedUpload(t *testing.T) {
	fs := &fakeSink{}
	p := newTestProcessor(t, "").WithSink(fs)
	res, err := p.ProcessUpload(context.Background(), "tenant-adeco", "carrefour_weekly.csv", sampleCSV)
	if err != nil {
		t.Fatal(err)
	}
	if res.BigQuerySync == nil || res.BigQuerySync.Status != bqsink.StatusOK {
		t.Fatalf("expected ok bigquery_sync, got %+v", res.BigQuerySync)
	}
	if len(fs.sellOut) != 1 || fs.sellOut[0].BatchID != res.BatchID || fs.sellOut[0].SourceFile != "carrefour_weekly.csv" {
		t.Fatalf("unexpected sink calls: %+v", fs.sellOut)
	}
	if fs.rowsSeen != res.ValidRows && fs.rowsSeen == 0 {
		t.Fatalf("sink got %d rows", fs.rowsSeen)
	}
}

func TestSinkPreviewDoesNotWriteButCommitDoes(t *testing.T) {
	fs := &fakeSink{}
	p := newTestProcessor(t, "").WithSink(fs)
	ctx := context.Background()
	staged, err := p.ProcessUploadWithDryRun(ctx, "tenant-adeco", "carrefour_weekly.csv", sampleCSV, true)
	if err != nil {
		t.Fatal(err)
	}
	if len(fs.sellOut) != 0 || staged.BigQuerySync != nil {
		t.Fatalf("preview must not write to BigQuery")
	}
	res, err := p.CommitStagedUpload(ctx, "tenant-adeco", staged.BatchID, "")
	if err != nil {
		t.Fatal(err)
	}
	if res.BigQuerySync == nil || len(fs.sellOut) != 1 {
		t.Fatalf("commit must write once, got %d writes, sync=%+v", len(fs.sellOut), res.BigQuerySync)
	}
}

func TestSinkFailureIsSurfacedButUploadSucceeds(t *testing.T) {
	fs := &fakeSink{fail: errors.New("permission denied")}
	p := newTestProcessor(t, "").WithSink(fs)
	res, err := p.ProcessUpload(context.Background(), "tenant-adeco", "carrefour_weekly.csv", sampleCSV)
	if err != nil {
		t.Fatalf("in-memory path must keep working: %v", err)
	}
	if res.BigQuerySync == nil || !res.BigQuerySync.Failed() || res.BigQuerySync.Error == "" {
		t.Fatalf("expected failed bigquery_sync with error, got %+v", res.BigQuerySync)
	}
	if res.ValidRows == 0 {
		t.Fatalf("in-memory ingestion should still succeed")
	}
}

func TestReplayDoesNotWriteToSinkButBackfillDoes(t *testing.T) {
	dir := t.TempDir()
	ctx := context.Background()
	first := newTestProcessor(t, dir)
	if _, err := first.ProcessUpload(ctx, "tenant-adeco", "carrefour_weekly.csv", sampleCSV); err != nil {
		t.Fatal(err)
	}

	fs := &fakeSink{}
	second := newTestProcessor(t, dir).WithSink(fs)
	if err := second.ReplayArchivedFilesToDatabase(ctx); err != nil {
		t.Fatal(err)
	}
	if len(fs.sellOut) != 0 {
		t.Fatalf("startup replay must not write to BigQuery, got %d writes", len(fs.sellOut))
	}
	if err := second.BackfillArchiveToSink(ctx); err != nil {
		t.Fatal(err)
	}
	if len(fs.sellOut) == 0 {
		t.Fatalf("backfill should write archived sell-out files")
	}
}

func TestDeleteArchivedFileDeletesBatchInSink(t *testing.T) {
	dir := t.TempDir()
	fs := &fakeSink{}
	p := newTestProcessor(t, dir).WithSink(fs)
	ctx := context.Background()
	res, err := p.ProcessUpload(ctx, "tenant-adeco", "carrefour_weekly.csv", sampleCSV)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := p.DeleteArchivedFile(ctx, "tenant-adeco", res.ArchiveID); err != nil {
		t.Fatal(err)
	}
	if len(fs.deletes) != 1 || fs.deletes[0].BatchID != res.BatchID {
		t.Fatalf("expected one batch delete for %s, got %+v", res.BatchID, fs.deletes)
	}
}

// Two instances sharing one archive directory (gcsfuse) each rewrite index.json from their own memory.
// Per-entry sidecars must keep both uploads visible to the next instance that starts.
func TestConcurrentInstancesDoNotLoseArchiveEntries(t *testing.T) {
	dir := t.TempDir()
	a := newTestProcessor(t, dir)
	b := newTestProcessor(t, dir)
	ea := a.SaveArchivedFile("tenant-adeco", "batch_a", "fathalla_jan.csv", []byte("a"), "fathalla", "2026", "01", 1, 1, 1)
	eb := b.SaveArchivedFile("tenant-adeco", "batch_b", "gomla_jan.csv", []byte("b"), "gomla", "2026", "01", 1, 1, 1)

	// Simulate the lost update: instance A rewrites index.json last, without B's entry.
	a.archiveMu.Lock()
	a.persistTenantArchiveIndexLocked("tenant-adeco")
	a.archiveMu.Unlock()

	c := newTestProcessor(t, dir)
	c.archiveMu.RLock()
	_, okA := c.archivedFiles[ea.ID]
	_, okB := c.archivedFiles[eb.ID]
	c.archiveMu.RUnlock()
	if !okA || !okB {
		t.Fatalf("expected both entries after restart, gotA=%v gotB=%v", okA, okB)
	}
	if _, err := os.Stat(filepath.Join(dir, "tenant-adeco", archiveSidecarDir, sidecarName(eb.ID))); err != nil {
		t.Fatalf("sidecar for B missing: %v", err)
	}

	// Deleting removes the sidecar so the entry does not come back.
	if _, err := c.DeleteArchivedFile(context.Background(), "tenant-adeco", eb.ID); err != nil {
		t.Fatal(err)
	}
	d := newTestProcessor(t, dir)
	d.archiveMu.RLock()
	_, stillB := d.archivedFiles[eb.ID]
	d.archiveMu.RUnlock()
	if stillB {
		t.Fatalf("deleted entry resurrected from sidecar")
	}
}
