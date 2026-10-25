package ingestion

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"sync"
	"testing"
	"time"

	"github.com/tashil/data-sharing/backend/internal/domain"
	"github.com/tashil/data-sharing/backend/internal/service/bigquery"
	"github.com/tashil/data-sharing/backend/internal/service/bqsink"
	"github.com/tashil/data-sharing/backend/internal/service/dataquality"
	"github.com/tashil/data-sharing/backend/internal/service/firestore"
	"github.com/tashil/data-sharing/backend/internal/service/gemini"
)

// sharedSellOutTable stands in for tashil_analytics.sell_out_facts shared by all instances.
type sharedSellOutTable struct {
	mu    sync.Mutex
	rows  []domain.SellOutFact
	reads int
	err   error
}

func (s *sharedSellOutTable) ReadSellOut(_ context.Context, _ string) ([]domain.SellOutFact, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.reads++
	if s.err != nil {
		return nil, s.err
	}
	return append([]domain.SellOutFact{}, s.rows...), nil
}

// durableSink writes into the shared fake tables and supports tenant deletes.
type durableSink struct {
	fakeSink
	in            *sharedSellInTable
	out           *sharedSellOutTable
	failDelete    bool
	tenantDeletes []string
}

func (d *durableSink) WriteSellOut(_ context.Context, _ bqsink.Meta, f []domain.SellOutFact, _ bqsink.SellOutMode) *bqsink.Result {
	d.out.mu.Lock()
	d.out.rows = append(d.out.rows, f...)
	d.out.mu.Unlock()
	return &bqsink.Result{Status: bqsink.StatusOK, Table: bqsink.TableSellOut, RowsWritten: len(f)}
}
func (d *durableSink) WriteSellIn(_ context.Context, _ bqsink.Meta, r []domain.SellInRecord) *bqsink.Result {
	d.in.mu.Lock()
	d.in.rows = append([]domain.SellInRecord{}, r...)
	d.in.mu.Unlock()
	return &bqsink.Result{Status: bqsink.StatusOK, Table: bqsink.TableSellIn, RowsWritten: len(r)}
}
func (d *durableSink) DeleteTenant(_ context.Context, k bqsink.Kind, tenant string) *bqsink.Result {
	if d.failDelete {
		return &bqsink.Result{Status: bqsink.StatusFailed, Error: "boom"}
	}
	d.tenantDeletes = append(d.tenantDeletes, string(k)+":"+bqsink.NormalizeTenant(tenant))
	switch k {
	case bqsink.KindSellIn:
		d.in.mu.Lock()
		d.in.rows = nil
		d.in.mu.Unlock()
	case bqsink.KindSellOut:
		d.out.mu.Lock()
		d.out.rows = nil
		d.out.mu.Unlock()
	}
	return &bqsink.Result{Status: bqsink.StatusOK}
}

func newDurableInstance(t *testing.T, sink *durableSink, versions DataVersionStore) (*Processor, *bigquery.Client) {
	t.Helper()
	bq := bigquery.NewClient("p", "d", true)
	_ = bq.ClearTenantData(context.Background(), "all") // drop mock demo seed data
	p := NewProcessor(gemini.NewAgent("", "m", true), bq, firestore.NewClient("db", true))
	p.WithSink(sink)
	p.WithSellInStore(sink.in, versions)
	p.WithSellOutStore(sink.out, versions)
	return p, bq
}

func sellOutRows(n int, revenue float64) []domain.SellOutFact {
	out := make([]domain.SellOutFact, n)
	for i := range out {
		out[i] = domain.SellOutFact{RecordID: "fact_" + string(rune('a'+i)), TenantID: "tenant-adeco", RetailerChain: "fathalla",
			StoreID: "s1", Barcode: "6223000236024", SKUName: "x", QuantitySold: 2, NetRevenue: revenue, TransactionDate: "2026-03-01",
			IngestionBatchID: "batch_1"}
	}
	return out
}

func sumRevenue(f []domain.SellOutFact) float64 {
	s := 0.0
	for _, r := range f {
		s += r.NetRevenue
	}
	return s
}

func TestSellOutInstancesConverge(t *testing.T) {
	ctx := context.Background()
	sink := &durableSink{in: &sharedSellInTable{}, out: &sharedSellOutTable{}}
	versions := firestore.NewClient("shared", true)
	a, bqA := newDurableInstance(t, sink, versions)
	b, bqB := newDurableInstance(t, sink, versions)
	a.SyncDurableFromStore(ctx, "tenant-adeco", true)
	b.SyncDurableFromStore(ctx, "tenant-adeco", true)

	facts := sellOutRows(3, 40)
	if err := bqA.InsertSellOutFacts(ctx, facts); err != nil {
		t.Fatal(err)
	}
	if res := a.sinkSellOut(ctx, bqsink.Meta{TenantID: "tenant-adeco", BatchID: "batch_1"}, facts, bqsink.ModeUpsertRecords); res.Failed() {
		t.Fatal(res.Error)
	}
	if n := len(bqB.SellOutFactsSnapshot("tenant-adeco")); n != 0 {
		t.Fatalf("B saw %d facts before sync", n)
	}
	changed, err := b.SyncSellOutFromStore(ctx, "tenant-adeco", false)
	if err != nil || !changed {
		t.Fatalf("B should reload: %v %v", changed, err)
	}
	if got := bqB.SellOutFactsSnapshot("tenant-adeco"); len(got) != 3 || sumRevenue(got) != 120 {
		t.Fatalf("B did not converge: %d facts, %.2f", len(got), sumRevenue(got))
	}
	reads := sink.out.reads
	if c, _ := a.SyncSellOutFromStore(ctx, "tenant-adeco", false); c {
		t.Fatal("A reloaded its own write")
	}
	if c, _ := b.SyncSellOutFromStore(ctx, "tenant-adeco", false); c {
		t.Fatal("B reloaded without a version change")
	}
	if sink.out.reads != reads {
		t.Fatal("unchanged version queried BigQuery")
	}
	// Sell-In version is independent: no Sell-In reload was triggered by the Sell-Out write.
	if v, _ := versions.GetDataVersion(ctx, "tenant-adeco", SellInVersionKind); v != "" {
		t.Fatalf("sell-out write bumped sell-in version %q", v)
	}
}

func TestSellOutReplaceKeepsOtherTenants(t *testing.T) {
	bq := bigquery.NewClient("p", "d", true)
	_ = bq.ClearTenantData(context.Background(), "all")
	other := sellOutRows(1, 7)
	other[0].TenantID, other[0].RecordID = "tenant-pepsi", "fact_pepsi"
	_ = bq.InsertSellOutFacts(context.Background(), append(sellOutRows(2, 1), other...))
	bq.ReplaceSellOutFacts("tenant-adeco", sellOutRows(1, 5))
	if got := bq.SellOutFactsSnapshot("tenant-adeco"); len(got) != 1 || got[0].NetRevenue != 5 {
		t.Fatalf("adeco not replaced: %+v", got)
	}
	if got := bq.SellOutFactsSnapshot("tenant-pepsi"); len(got) != 1 || got[0].NetRevenue != 7 {
		t.Fatalf("other tenant touched: %+v", got)
	}
}

func TestSellOutEmptyStoreOrErrorKeepsMemory(t *testing.T) {
	ctx := context.Background()
	sink := &durableSink{in: &sharedSellInTable{}, out: &sharedSellOutTable{}}
	p, bq := newDurableInstance(t, sink, firestore.NewClient("shared", true))
	_ = bq.InsertSellOutFacts(ctx, sellOutRows(2, 3))
	if c, err := p.SyncSellOutFromStore(ctx, "tenant-adeco", true); err != nil || c {
		t.Fatalf("empty table without version must keep memory: %v %v", c, err)
	}
	sink.out.err = errors.New("bq down")
	if _, err := p.SyncSellOutFromStore(ctx, "tenant-adeco", true); err == nil {
		t.Fatal("expected error")
	}
	if n := len(bq.SellOutFactsSnapshot("tenant-adeco")); n != 2 {
		t.Fatalf("memory changed: %d", n)
	}
}

func TestSellOutArchiveDeleteBumpsVersion(t *testing.T) {
	ctx := context.Background()
	versions := firestore.NewClient("shared", true)
	sink := &durableSink{in: &sharedSellInTable{}, out: &sharedSellOutTable{}}
	p, _ := newDurableInstance(t, sink, versions)
	p.sinkDeleteArchived(ctx, &ArchivedFile{ID: "x", BatchID: "batch_1", TenantID: "tenant-adeco", FileName: "2026 out.xlsx", FileType: "sell_out"})
	if v, _ := versions.GetDataVersion(ctx, "tenant-adeco", SellOutVersionKind); v == "" {
		t.Fatal("sell-out archive delete did not bump the version")
	}
}

func TestPurgeTenantDeletesDurableRowsAndOtherInstancesClear(t *testing.T) {
	ctx := context.Background()
	sink := &durableSink{in: &sharedSellInTable{rows: sellInRows(2, 10)}, out: &sharedSellOutTable{rows: sellOutRows(3, 4)}}
	versions := firestore.NewClient("shared", true)
	a, _ := newDurableInstance(t, sink, versions)
	b, bqB := newDurableInstance(t, sink, versions)
	a.SyncDurableFromStore(ctx, "tenant-adeco", true)
	b.SyncDurableFromStore(ctx, "tenant-adeco", true)
	if len(bqB.SellOutFactsSnapshot("tenant-adeco")) != 3 || len(bqB.SellInRecordsSnapshot("tenant-adeco")) != 2 {
		t.Fatal("startup load failed")
	}

	if err := a.PurgeTenantData(ctx, "tenant-adeco"); err != nil {
		t.Fatal(err)
	}
	want := map[string]bool{"sell_in:tenant-adeco": true, "sell_out:tenant-adeco": true}
	if len(sink.tenantDeletes) != 2 || !want[sink.tenantDeletes[0]] || !want[sink.tenantDeletes[1]] {
		t.Fatalf("durable deletes = %v", sink.tenantDeletes)
	}
	if !b.SyncDurableFromStore(ctx, "tenant-adeco", false) {
		t.Fatal("B should apply the purge")
	}
	if n, m := len(bqB.SellOutFactsSnapshot("tenant-adeco")), len(bqB.SellInRecordsSnapshot("tenant-adeco")); n != 0 || m != 0 {
		t.Fatalf("B still has sell-out=%d sell-in=%d", n, m)
	}

	// "Restart": a fresh instance loading from the (now empty, version-bumped) store stays empty.
	c, bqC := newDurableInstance(t, sink, versions)
	_ = bqC.InsertSellOutFacts(ctx, sellOutRows(1, 9)) // pretend the archive replay brought something back
	c.SyncDurableFromStore(ctx, "tenant-adeco", true)
	if n := len(bqC.SellOutFactsSnapshot("tenant-adeco")); n != 0 {
		t.Fatalf("restart resurrected %d sell-out facts", n)
	}
}

func TestPurgeFailureIsReportedAndDoesNotBump(t *testing.T) {
	ctx := context.Background()
	versions := firestore.NewClient("shared", true)
	sink := &durableSink{in: &sharedSellInTable{}, out: &sharedSellOutTable{}, failDelete: true}
	p, _ := newDurableInstance(t, sink, versions)
	if err := p.PurgeTenantData(ctx, "tenant-adeco"); err == nil {
		t.Fatal("expected error when BigQuery delete fails")
	}
	if v, _ := versions.GetDataVersion(ctx, "tenant-adeco", SellOutVersionKind); v != "" {
		t.Fatal("failed delete bumped the version")
	}
}

func TestClearTenantDataStaysMemoryOnly(t *testing.T) {
	ctx := context.Background()
	sink := &durableSink{in: &sharedSellInTable{}, out: &sharedSellOutTable{}}
	p, _ := newDurableInstance(t, sink, firestore.NewClient("shared", true))
	_ = p.ClearTenantData(ctx, "all") // used at startup and by tooling
	if len(sink.tenantDeletes) != 0 {
		t.Fatalf("ClearTenantData must never delete durable rows: %v", sink.tenantDeletes)
	}
}

func TestDataQualityRerunsAfterDurableReload(t *testing.T) {
	ctx := context.Background()
	pmPath := filepath.Join("..", "..", "..", "data", "archive", "tenant-adeco",
		"arch_pm_adeco_product-master_1792752915214440000_adeco_product_master_2026_08_01.xlsx")
	raw, err := os.ReadFile(pmPath)
	if err != nil {
		t.Skipf("real product master not available: %v", err)
	}
	old := dataquality.RerunDelay
	dataquality.RerunDelay = 20 * time.Millisecond
	defer func() { dataquality.RerunDelay = old }()

	sink := &durableSink{in: &sharedSellInTable{}, out: &sharedSellOutTable{}}
	versions := firestore.NewClient("shared", true)
	p, bq := newDurableInstance(t, sink, versions)
	fs := firestore.NewClient("dq", true)
	dq := dataquality.NewService(fs, bq).WithMaster(bq)
	dq.SetProductMasterFile("tenant-adeco", "pm.xlsx", raw)
	if _, err := dq.RunProductMaster(ctx, "tenant-adeco", "pm.xlsx", raw); err != nil {
		t.Fatal(err)
	}
	before, err := dq.Summary(ctx, "tenant-adeco")
	if err != nil {
		t.Fatal(err)
	}
	bq.OnSourceChange(dq.OnSourceChanged)

	// Another instance wrote Sell-Out; this instance reloads it from BigQuery.
	sink.out.rows = sellOutRows(2, 11)
	_, _ = versions.BumpDataVersion(ctx, "tenant-adeco", SellOutVersionKind)
	time.Sleep(5 * time.Millisecond)
	if c, err := p.SyncSellOutFromStore(ctx, "tenant-adeco", false); err != nil || !c {
		t.Fatalf("reload: %v %v", c, err)
	}
	deadline := time.Now().Add(10 * time.Second)
	for time.Now().Before(deadline) {
		after, _ := dq.Summary(ctx, "tenant-adeco")
		if after != nil && after.UpdatedAt.After(before.UpdatedAt) {
			return
		}
		time.Sleep(50 * time.Millisecond)
	}
	t.Fatal("data-quality checks did not re-run after the Sell-Out reload")
}
