package main

import (
	"context"
	"os"
	"path/filepath"
	"sync/atomic"
	"testing"

	"github.com/tashil/data-sharing/backend/internal/domain"
	"github.com/tashil/data-sharing/backend/internal/service/bigquery"
	"github.com/tashil/data-sharing/backend/internal/service/bqsink"
	"github.com/tashil/data-sharing/backend/internal/service/firestore"
	"github.com/tashil/data-sharing/backend/internal/service/gemini"
)

// countingSink tracks durable writes through the same Sink / AggregatesWriter surfaces
// wireBackfillProcessor uses in production (real processor wiring, not a Replay fake).
type countingSink struct {
	bqsink.Noop
	sellIn atomic.Int32
	agg    atomic.Int32
}

func (c *countingSink) Enabled() bool { return true }

func (c *countingSink) SellInArchivePeriodCounts(context.Context, string, string) ([]bqsink.PeriodMonthCount, error) {
	return nil, nil
}

func (c *countingSink) WriteSellIn(_ context.Context, _ bqsink.Meta, records []domain.SellInRecord) *bqsink.Result {
	c.sellIn.Add(1)
	return &bqsink.Result{Status: bqsink.StatusOK, Table: bqsink.TableSellIn, RowsWritten: len(records)}
}

func (c *countingSink) WriteSellOut(context.Context, bqsink.Meta, []domain.SellOutFact, bqsink.SellOutMode) *bqsink.Result {
	c.sellIn.Add(1)
	return &bqsink.Result{Status: bqsink.StatusOK}
}

func (c *countingSink) WriteProductMaster(context.Context, bqsink.Meta, *domain.ProductMasterSummaryResponse) *bqsink.Result {
	c.sellIn.Add(1)
	return &bqsink.Result{Status: bqsink.StatusOK}
}

func (c *countingSink) WriteAnalyticsAggregates(context.Context, *domain.AnalyticsAggregates) error {
	c.agg.Add(1)
	return nil
}

func TestWireBackfillProcessorDryRunNoAggregatesWriterNoWrites(t *testing.T) {
	dir := t.TempDir()
	bq := bigquery.NewClient("", "", true)
	fs := firestore.NewClient("", true)
	agent := gemini.NewAgent("", "", true)
	sink := &countingSink{}

	p := wireBackfillProcessor(dir, "tenant-adeco", false /* dry-run */, bq, fs, agent, sink)
	if bq.AggregatesWriterAttached() {
		t.Fatal("dry-run must not attach aggregates writer (would scheduleRecompute)")
	}

	raw, err := os.ReadFile(filepath.Join("..", "..", "internal", "service", "gemini", "testdata", "in26_synthetic.xlsx"))
	if err != nil {
		t.Fatal(err)
	}
	entry := p.SaveArchivedFile("tenant-adeco", "batch_sellin_in26", "in26.xlsx", raw, "fathalla", "2026", "01", 75, 1, 625)

	rep, err := p.ReplaySellInArchive(context.Background(), "tenant-adeco", entry.ID, "sell_in", false)
	if err != nil {
		t.Fatal(err)
	}
	if rep.Executed {
		t.Fatal("dry-run executed")
	}
	if sink.sellIn.Load() != 0 || sink.agg.Load() != 0 {
		t.Fatalf("dry-run must perform zero BQ writes; sellIn=%d agg=%d", sink.sellIn.Load(), sink.agg.Load())
	}
}

func TestWireBackfillProcessorExecuteAttachesSyncMirror(t *testing.T) {
	dir := t.TempDir()
	bq := bigquery.NewClient("", "", true)
	fs := firestore.NewClient("", true)
	agent := gemini.NewAgent("", "", true)
	sink := &countingSink{}

	_ = wireBackfillProcessor(dir, "tenant-adeco", true, bq, fs, agent, sink)
	if !bq.AggregatesWriterAttached() {
		t.Fatal("execute must attach aggregates writer for MaterializeAnalyticsAggregates")
	}
}
