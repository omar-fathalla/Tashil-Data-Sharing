package ingestion

import (
	"context"
	"errors"
	"sync"
	"testing"

	"github.com/tashil/data-sharing/backend/internal/domain"
	"github.com/tashil/data-sharing/backend/internal/service/bigquery"
	"github.com/tashil/data-sharing/backend/internal/service/bqsink"
	"github.com/tashil/data-sharing/backend/internal/service/firestore"
	"github.com/tashil/data-sharing/backend/internal/service/gemini"
)

// sharedSellInTable stands in for tashil_analytics.sell_in_records shared by all instances.
type sharedSellInTable struct {
	mu    sync.Mutex
	rows  []domain.SellInRecord
	reads int
	err   error
}

func (s *sharedSellInTable) ReadSellIn(_ context.Context, _ string) ([]domain.SellInRecord, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.reads++
	if s.err != nil {
		return nil, s.err
	}
	return append([]domain.SellInRecord{}, s.rows...), nil
}

// tableSink writes sell-in into the shared table (replace-all is enough for these tests).
type tableSink struct {
	fakeSink
	table *sharedSellInTable
}

func (t *tableSink) WriteSellIn(_ context.Context, _ bqsink.Meta, r []domain.SellInRecord) *bqsink.Result {
	t.table.mu.Lock()
	t.table.rows = append([]domain.SellInRecord{}, r...)
	t.table.mu.Unlock()
	return &bqsink.Result{Status: bqsink.StatusOK, Table: bqsink.TableSellIn, RowsWritten: len(r)}
}

func newInstance(t *testing.T, table *sharedSellInTable, versions DataVersionStore) (*Processor, *bigquery.Client) {
	t.Helper()
	bq := bigquery.NewClient("p", "d", true)
	p := NewProcessor(gemini.NewAgent("", "m", true), bq, firestore.NewClient("db", true))
	p.WithSink(&tableSink{table: table})
	p.WithSellInStore(table, versions)
	return p, bq
}

func sellInRows(n int, value float64) []domain.SellInRecord {
	out := make([]domain.SellInRecord, n)
	for i := range out {
		out[i] = domain.SellInRecord{RecordID: "r", TenantID: "tenant-adeco", RetailerChain: "fathalla", Year: 2026, MonthNum: 3, ItemName: "x", NetValueEGP: value, NetQtyCases: 1}
	}
	return out
}

func sumValue(recs []domain.SellInRecord) float64 {
	s := 0.0
	for _, r := range recs {
		s += r.NetValueEGP
	}
	return s
}

func TestSellInInstancesConvergeThroughSharedVersion(t *testing.T) {
	ctx := context.Background()
	table := &sharedSellInTable{}
	versions := firestore.NewClient("shared", true) // one shared Firestore for both instances
	a, bqA := newInstance(t, table, versions)
	b, bqB := newInstance(t, table, versions)

	// Both start empty and do their startup load.
	for _, p := range []*Processor{a, b} {
		if _, err := p.SyncSellInFromStore(ctx, "adeco", true); err != nil {
			t.Fatal(err)
		}
	}

	// Instance A receives an upload: memory + BigQuery + version bump.
	recs := sellInRows(3, 100)
	if err := bqA.SetSellInRecords(ctx, "tenant-adeco", "plan.xlsx", recs); err != nil {
		t.Fatal(err)
	}
	if res := a.sinkSellIn(ctx, bqsink.Meta{TenantID: "tenant-adeco", SourceFile: "plan.xlsx"}, recs); res.Failed() {
		t.Fatalf("sink failed: %+v", res)
	}
	if got := len(bqB.SellInRecordsSnapshot("tenant-adeco")); got != 0 {
		t.Fatalf("B should not see data before sync, got %d", got)
	}

	changed, err := b.SyncSellInFromStore(ctx, "tenant-adeco", false)
	if err != nil || !changed {
		t.Fatalf("B should reload: changed=%v err=%v", changed, err)
	}
	if got := bqB.SellInRecordsSnapshot("tenant-adeco"); len(got) != 3 || sumValue(got) != 300 {
		t.Fatalf("B did not converge: %d rows, value %.2f", len(got), sumValue(got))
	}

	// A already applied its own version, so it does not re-read.
	readsBefore := table.reads
	if changed, _ := a.SyncSellInFromStore(ctx, "tenant-adeco", false); changed {
		t.Fatal("A should not reload its own write")
	}
	if changed, _ := b.SyncSellInFromStore(ctx, "tenant-adeco", false); changed {
		t.Fatal("B should not reload without a new version")
	}
	if table.reads != readsBefore {
		t.Fatalf("unchanged version must not query BigQuery (reads %d -> %d)", readsBefore, table.reads)
	}
}

func TestSellInDeleteConvergesToEmpty(t *testing.T) {
	ctx := context.Background()
	table := &sharedSellInTable{rows: sellInRows(2, 50)}
	versions := firestore.NewClient("shared", true)
	a, _ := newInstance(t, table, versions)
	b, bqB := newInstance(t, table, versions)
	_, _ = a.SyncSellInFromStore(ctx, "tenant-adeco", true)
	_, _ = b.SyncSellInFromStore(ctx, "tenant-adeco", true)
	if len(bqB.SellInRecordsSnapshot("tenant-adeco")) != 2 {
		t.Fatal("startup load failed")
	}
	// A deletes the sell-in archive: BigQuery rows go away and the version is bumped.
	table.mu.Lock()
	table.rows = nil
	table.mu.Unlock()
	a.sinkDeleteArchived(ctx, &ArchivedFile{ID: "x", BatchID: "b1", TenantID: "tenant-adeco", FileName: "Adco_Fathalla_Sell_In_Plan_2026_Clean.xlsx", FileType: "sell_in"})
	if changed, err := b.SyncSellInFromStore(ctx, "tenant-adeco", false); err != nil || !changed {
		t.Fatalf("B should apply the delete: changed=%v err=%v", changed, err)
	}
	if n := len(bqB.SellInRecordsSnapshot("tenant-adeco")); n != 0 {
		t.Fatalf("B still has %d rows after delete", n)
	}
}

func TestSellInEmptyStoreNeverWipesReplayedMemory(t *testing.T) {
	ctx := context.Background()
	table := &sharedSellInTable{}
	p, bq := newInstance(t, table, firestore.NewClient("shared", true))
	_ = bq.SetSellInRecords(ctx, "tenant-adeco", "plan.xlsx", sellInRows(4, 10))
	if changed, err := p.SyncSellInFromStore(ctx, "tenant-adeco", true); err != nil || changed {
		t.Fatalf("empty BigQuery without a version must keep memory: changed=%v err=%v", changed, err)
	}
	if n := len(bq.SellInRecordsSnapshot("tenant-adeco")); n != 4 {
		t.Fatalf("memory wiped: %d rows", n)
	}
}

func TestSellInReadErrorKeepsMemory(t *testing.T) {
	ctx := context.Background()
	table := &sharedSellInTable{err: errors.New("bq down")}
	p, bq := newInstance(t, table, nil)
	_ = bq.SetSellInRecords(ctx, "tenant-adeco", "plan.xlsx", sellInRows(2, 10))
	if _, err := p.SyncSellInFromStore(ctx, "tenant-adeco", true); err == nil {
		t.Fatal("expected error")
	}
	if n := len(bq.SellInRecordsSnapshot("tenant-adeco")); n != 2 {
		t.Fatalf("memory changed on read error: %d", n)
	}
}

func TestSellInFailedWriteDoesNotBumpVersion(t *testing.T) {
	ctx := context.Background()
	versions := firestore.NewClient("shared", true)
	p := newTestProcessor(t, "")
	p.WithSink(&fakeSink{fail: errors.New("boom")})
	p.WithSellInStore(&sharedSellInTable{}, versions)
	p.sinkSellIn(ctx, bqsink.Meta{TenantID: "tenant-adeco"}, sellInRows(1, 1))
	if v, _ := versions.GetDataVersion(ctx, "tenant-adeco", SellInVersionKind); v != "" {
		t.Fatalf("failed write bumped version to %q", v)
	}
}
