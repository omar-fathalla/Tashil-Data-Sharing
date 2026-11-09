package ingestion

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"github.com/tashil/data-sharing/backend/internal/domain"
	"github.com/tashil/data-sharing/backend/internal/service/bigquery"
	"github.com/tashil/data-sharing/backend/internal/service/bqsink"
	"github.com/tashil/data-sharing/backend/internal/service/firestore"
	"github.com/tashil/data-sharing/backend/internal/service/gemini"
)

type fakePeriodCounter struct {
	counts []bqsink.PeriodMonthCount
	err    error
	calls  int
	lastID string
}

func (f *fakePeriodCounter) SellInArchivePeriodCounts(_ context.Context, _, archiveID string) ([]bqsink.PeriodMonthCount, error) {
	f.calls++
	f.lastID = archiveID
	return f.counts, f.err
}

type recordingSink struct {
	bqsink.Noop
	counter   *fakePeriodCounter
	wrote     int
	lastMeta  bqsink.Meta
	lastRecs  []domain.SellInRecord
	writeFail bool
}

func (r *recordingSink) Enabled() bool { return true }

func (r *recordingSink) SellInArchivePeriodCounts(ctx context.Context, tenantID, archiveID string) ([]bqsink.PeriodMonthCount, error) {
	return r.counter.SellInArchivePeriodCounts(ctx, tenantID, archiveID)
}

func (r *recordingSink) WriteSellIn(_ context.Context, meta bqsink.Meta, records []domain.SellInRecord) *bqsink.Result {
	r.wrote++
	r.lastMeta = meta
	r.lastRecs = append([]domain.SellInRecord{}, records...)
	if r.writeFail {
		return &bqsink.Result{Status: bqsink.StatusFailed, Error: "boom", Table: bqsink.TableSellIn}
	}
	return &bqsink.Result{Status: bqsink.StatusOK, Table: bqsink.TableSellIn, RowsWritten: len(records)}
}

func TestReplaySellInArchiveRequiresArchiveID(t *testing.T) {
	p := NewProcessor(gemini.NewAgent("", "", true), bigquery.NewClient("", "", true), firestore.NewClient("", true))
	_, err := p.ReplaySellInArchive(context.Background(), "tenant-adeco", "", "sell_in", false)
	if err == nil || !strings.Contains(err.Error(), "archive id is required") {
		t.Fatalf("want refuse without archive id, got %v", err)
	}
}

func TestReplaySellInArchiveRefusesNonSellInKind(t *testing.T) {
	p := NewProcessor(gemini.NewAgent("", "", true), bigquery.NewClient("", "", true), firestore.NewClient("", true))
	_, err := p.ReplaySellInArchive(context.Background(), "tenant-adeco", "arch_x", "sell_out", false)
	if err == nil || !strings.Contains(err.Error(), "sell_in") {
		t.Fatalf("want kind refuse, got %v", err)
	}
}

func TestAggregateSellInByPeriodAndDiff(t *testing.T) {
	recs := []domain.SellInRecord{
		{Year: 2026, MonthNum: 1, NetValueEGP: 10.5},
		{Year: 2026, MonthNum: 1, NetValueEGP: 0.25},
		{Year: 2026, MonthNum: 2, NetValueEGP: -1},
	}
	after := AggregateSellInByPeriod(recs)
	if len(after) != 2 || after[0].PeriodMonth != "2026-01" || after[0].Rows != 2 || after[0].Net != 10.75 {
		t.Fatalf("after: %+v", after)
	}
	before := []bqsink.PeriodMonthCount{
		{PeriodMonth: "2026-01", Rows: 5, Net: 100},
		{PeriodMonth: "2026-03", Rows: 1, Net: 9},
	}
	net := DiffPeriodMonthCounts(before, after)
	if len(net) != 3 {
		t.Fatalf("net keys: %+v", net)
	}
	by := map[string]PeriodMonthNet{}
	for _, n := range net {
		by[n.PeriodMonth] = n
	}
	if by["2026-01"].RowsDelta != -3 || by["2026-01"].NetDelta != -89.25 {
		t.Fatalf("jan net: %+v", by["2026-01"])
	}
	if by["2026-02"].RowsDelta != 1 || by["2026-03"].RowsDelta != -1 {
		t.Fatalf("moved months: %+v", by)
	}
}

func TestReplaySellInArchiveDryRunBeforeAfter(t *testing.T) {
	dir := t.TempDir()
	bq := bigquery.NewClient("", "", true)
	fs := firestore.NewClient("", true)
	p := NewProcessor(gemini.NewAgent("", "", true), bq, fs).WithArchiveDir(dir)

	raw, err := os.ReadFile(filepath.Join("..", "gemini", "testdata", "in26_synthetic.xlsx"))
	if err != nil {
		t.Fatal(err)
	}
	entry := p.SaveArchivedFile("tenant-adeco", "batch_sellin_in26", "in26.xlsx", raw, "fathalla", "2026", "01", 75, 1, 625)

	counter := &fakePeriodCounter{counts: []bqsink.PeriodMonthCount{
		{PeriodMonth: "2026-01", Rows: 40, Net: 400},
		{PeriodMonth: "2026-02", Rows: 35, Net: 225},
	}}
	sink := &recordingSink{counter: counter}
	p.WithSink(sink)

	rep, err := p.ReplaySellInArchive(context.Background(), "tenant-adeco", entry.ID, "sell_in", false)
	if err != nil {
		t.Fatal(err)
	}
	if sink.wrote != 0 {
		t.Fatal("dry-run must not write")
	}
	if counter.calls != 1 || counter.lastID != entry.ID {
		t.Fatalf("BEFORE query: calls=%d id=%s", counter.calls, counter.lastID)
	}
	if rep.BeforeRows != 75 || rep.Layout != "gp_sop_export" {
		t.Fatalf("report meta: %+v", rep)
	}
	if rep.AfterRows != 75 {
		t.Fatalf("after rows %d want 75", rep.AfterRows)
	}
	if rep.Executed {
		t.Fatal("dry-run marked executed")
	}
	out := FormatSellInArchiveReplayDryRun(rep)
	if !strings.Contains(out, "rows_before") || !strings.Contains(out, "TOTAL") || !strings.Contains(out, "dry run") {
		t.Fatalf("dry-run print:\n%s", out)
	}
}

type okAggregatesRefresher struct{}

func (okAggregatesRefresher) MaterializeAnalyticsAggregates(context.Context, string) (*domain.AnalyticsAggregates, error) {
	return &domain.AnalyticsAggregates{}, nil
}

type failAggregatesRefresher struct{ err error }

func (f failAggregatesRefresher) MaterializeAnalyticsAggregates(context.Context, string) (*domain.AnalyticsAggregates, error) {
	return nil, f.err
}

func TestReplaySellInArchiveExecuteReplacesOnlyArchive(t *testing.T) {
	dir := t.TempDir()
	bq := bigquery.NewClient("", "", true)
	fs := firestore.NewClient("", true)
	p := NewProcessor(gemini.NewAgent("", "", true), bq, fs).WithArchiveDir(dir).
		WithAggregatesRefresher(okAggregatesRefresher{})

	raw, err := os.ReadFile(filepath.Join("..", "gemini", "testdata", "in26_synthetic.xlsx"))
	if err != nil {
		t.Fatal(err)
	}
	entry := p.SaveArchivedFile("tenant-adeco", "batch_sellin_in26", "in26.xlsx", raw, "fathalla", "2026", "01", 75, 1, 625)
	// Sibling file must remain untouched (meta-wise); execute only writes the target archive id.
	_ = p.SaveArchivedFile("tenant-adeco", "batch_sellin_clean", "Adco_Fathalla_Sell_In_Plan_2026_Clean.xlsx",
		[]byte("not-used"), "fathalla", "2026", "01", 10, 1, 1)

	sink := &recordingSink{counter: &fakePeriodCounter{}}
	p.WithSink(sink)

	rep, err := p.ReplaySellInArchive(context.Background(), "tenant-adeco", entry.ID, string(bqsink.KindSellIn), true)
	if err != nil {
		t.Fatal(err)
	}
	if sink.wrote != 1 {
		t.Fatalf("writes=%d", sink.wrote)
	}
	if sink.lastMeta.ArchiveID != entry.ID || sink.lastMeta.BatchID != entry.BatchID || sink.lastMeta.SourceFile != "in26.xlsx" {
		t.Fatalf("meta: %+v", sink.lastMeta)
	}
	if rep.RowsWritten != 75 || !rep.Executed || rep.AggRefresh != "ok" {
		t.Fatalf("rep: %+v", rep)
	}
	// PlanSellIn delete key is archive/batch/file — not chain/month.
	plan := bqsink.PlanSellIn(sink.lastMeta, sink.lastRecs, time.Now())
	if !strings.Contains(plan.DeleteWhere, "archive_id") {
		t.Fatalf("replace key must be archive-scoped: %s", plan.DeleteWhere)
	}
	if strings.Contains(plan.DeleteWhere, "period_month") || strings.Contains(plan.DeleteWhere, "chain_key") {
		t.Fatalf("must not replace by chain/month: %s", plan.DeleteWhere)
	}
}

func TestReplaySellInArchiveExecuteFailsWhenAggregatesRefreshFails(t *testing.T) {
	dir := t.TempDir()
	bq := bigquery.NewClient("", "", true)
	fs := firestore.NewClient("", true)
	p := NewProcessor(gemini.NewAgent("", "", true), bq, fs).WithArchiveDir(dir).
		WithAggregatesRefresher(failAggregatesRefresher{err: errors.New("bq mirror timeout")})

	raw, err := os.ReadFile(filepath.Join("..", "gemini", "testdata", "in26_synthetic.xlsx"))
	if err != nil {
		t.Fatal(err)
	}
	entry := p.SaveArchivedFile("tenant-adeco", "batch_sellin_in26", "in26.xlsx", raw, "fathalla", "2026", "01", 75, 1, 625)
	sink := &recordingSink{counter: &fakePeriodCounter{}}
	p.WithSink(sink)

	rep, err := p.ReplaySellInArchive(context.Background(), "tenant-adeco", entry.ID, "sell_in", true)
	if err == nil {
		t.Fatal("want aggregates refresh failure")
	}
	if !strings.Contains(err.Error(), "aggregates refresh failed") || !strings.Contains(err.Error(), "bq mirror timeout") {
		t.Fatalf("clear failure message missing: %v", err)
	}
	if !strings.Contains(err.Error(), "sell_in_records updated") || !strings.Contains(err.Error(), "memory synced") {
		t.Fatalf("should state sell-in stayed durable/consistent: %v", err)
	}
	if sink.wrote != 1 {
		t.Fatalf("sell-in write must still happen before agg failure, wrote=%d", sink.wrote)
	}
	if rep == nil || rep.RowsWritten != 75 || !strings.Contains(rep.AggRefresh, "failed") {
		t.Fatalf("partial report: %+v", rep)
	}
}

// syncCountingWriter is a real AggregatesWriter used with *bigquery.Client.MaterializeAnalyticsAggregates.
type syncCountingWriter struct {
	calls atomic.Int32
	err   error
	gate  chan struct{} // if non-nil, block until closed (proves sync wait)
}

func (s *syncCountingWriter) WriteAnalyticsAggregates(context.Context, *domain.AnalyticsAggregates) error {
	s.calls.Add(1)
	if s.gate != nil {
		<-s.gate
	}
	return s.err
}

func TestReplaySellInArchiveExecuteRealClientMaterializeSync(t *testing.T) {
	dir := t.TempDir()
	bq := bigquery.NewClient("", "", true)
	w := &syncCountingWriter{}
	bq.AttachAggregatesWriterForSyncMirror(w, "tenant-adeco")
	bq.DisableBackgroundAggregatesMirror()

	fs := firestore.NewClient("", true)
	// No WithAggregatesRefresher override — uses real *bigquery.Client.MaterializeAnalyticsAggregates.
	p := NewProcessor(gemini.NewAgent("", "", true), bq, fs).WithArchiveDir(dir)

	raw, err := os.ReadFile(filepath.Join("..", "gemini", "testdata", "in26_synthetic.xlsx"))
	if err != nil {
		t.Fatal(err)
	}
	entry := p.SaveArchivedFile("tenant-adeco", "batch_sellin_in26", "in26.xlsx", raw, "fathalla", "2026", "01", 75, 1, 625)
	sink := &recordingSink{counter: &fakePeriodCounter{}}
	p.WithSink(sink)

	rep, err := p.ReplaySellInArchive(context.Background(), "tenant-adeco", entry.ID, "sell_in", true)
	if err != nil {
		t.Fatal(err)
	}
	if w.calls.Load() != 1 {
		t.Fatalf("Materialize must sync-write once, got %d", w.calls.Load())
	}
	if rep.AggRefresh != "ok" || sink.wrote != 1 {
		t.Fatalf("rep=%+v sink.wrote=%d", rep, sink.wrote)
	}
}

func TestReplaySellInArchiveExecuteRealClientMaterializeError(t *testing.T) {
	dir := t.TempDir()
	bq := bigquery.NewClient("", "", true)
	w := &syncCountingWriter{err: errors.New("agg load job failed")}
	bq.AttachAggregatesWriterForSyncMirror(w, "tenant-adeco")
	bq.DisableBackgroundAggregatesMirror()

	fs := firestore.NewClient("", true)
	p := NewProcessor(gemini.NewAgent("", "", true), bq, fs).WithArchiveDir(dir)

	raw, err := os.ReadFile(filepath.Join("..", "gemini", "testdata", "in26_synthetic.xlsx"))
	if err != nil {
		t.Fatal(err)
	}
	entry := p.SaveArchivedFile("tenant-adeco", "batch_sellin_in26", "in26.xlsx", raw, "fathalla", "2026", "01", 75, 1, 625)
	sink := &recordingSink{counter: &fakePeriodCounter{}}
	p.WithSink(sink)

	rep, err := p.ReplaySellInArchive(context.Background(), "tenant-adeco", entry.ID, "sell_in", true)
	if err == nil || !strings.Contains(err.Error(), "agg load job failed") {
		t.Fatalf("want materialize error, got %v", err)
	}
	if w.calls.Load() != 1 || sink.wrote != 1 {
		t.Fatalf("sell-in wrote=%d agg writes=%d", sink.wrote, w.calls.Load())
	}
	if rep == nil || !strings.Contains(rep.AggRefresh, "failed") {
		t.Fatalf("partial: %+v", rep)
	}
}
