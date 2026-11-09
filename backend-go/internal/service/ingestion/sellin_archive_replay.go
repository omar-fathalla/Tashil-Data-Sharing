package ingestion

import (
	"context"
	"fmt"
	"log"
	"math"
	"sort"
	"strings"

	"github.com/tashil/data-sharing/backend/internal/domain"
	"github.com/tashil/data-sharing/backend/internal/service/bqsink"
	"github.com/tashil/data-sharing/backend/internal/service/gemini"
)

// SellInArchiveReplayReport compares BigQuery BEFORE totals for one archive with AFTER
// totals from re-parsing the archived workbook with the current (#59) GP SOP parser.
type SellInArchiveReplayReport struct {
	TenantID    string                   `json:"tenant_id"`
	ArchiveID   string                   `json:"archive_id"`
	FileName    string                   `json:"file_name"`
	BatchID     string                   `json:"batch_id"`
	Kind        string                   `json:"kind"`
	Layout      string                   `json:"layout,omitempty"`
	Before      []bqsink.PeriodMonthCount `json:"before"`
	After       []bqsink.PeriodMonthCount `json:"after"`
	Net         []PeriodMonthNet         `json:"net"`
	BeforeRows  int                      `json:"before_rows"`
	AfterRows   int                      `json:"after_rows"`
	BeforeNet   float64                  `json:"before_net"`
	AfterNet    float64                  `json:"after_net"`
	Executed    bool                     `json:"executed"`
	RowsWritten int                      `json:"rows_written,omitempty"`
	SinkStatus  string                   `json:"sink_status,omitempty"`
	AggRefresh  string                   `json:"agg_refresh,omitempty"`
}

// PeriodMonthNet is AFTER − BEFORE for one period_month.
type PeriodMonthNet struct {
	PeriodMonth string  `json:"period_month"`
	RowsDelta   int     `json:"rows_delta"`
	NetDelta    float64 `json:"net_delta"`
}

// AggregatesRefresher recomputes and mirrors agg_sell_through (and sibling agg_* tables)
// synchronously — the caller must wait for MaterializeAnalyticsAggregates to return.
type AggregatesRefresher interface {
	MaterializeAnalyticsAggregates(ctx context.Context, tenantID string) (*domain.AnalyticsAggregates, error)
}

// WithAggregatesRefresher overrides the post-write aggregates refresh target (tests / explicit wiring).
func (p *Processor) WithAggregatesRefresher(r AggregatesRefresher) *Processor {
	p.aggRefresher = r
	return p
}

func (p *Processor) resolveAggregatesRefresher() AggregatesRefresher {
	if p.aggRefresher != nil {
		return p.aggRefresher
	}
	if r, ok := p.bqRepo.(AggregatesRefresher); ok {
		return r
	}
	return nil
}

// AggregateSellInByPeriod sums parsed Sell-In rows by YYYY-MM period_month.
func AggregateSellInByPeriod(recs []domain.SellInRecord) []bqsink.PeriodMonthCount {
	type acc struct {
		rows int
		net  float64
	}
	by := map[string]*acc{}
	for _, r := range recs {
		if r.Year <= 0 || r.MonthNum < 1 || r.MonthNum > 12 {
			continue
		}
		pm := fmt.Sprintf("%04d-%02d", r.Year, r.MonthNum)
		a := by[pm]
		if a == nil {
			a = &acc{}
			by[pm] = a
		}
		a.rows++
		a.net += r.NetValueEGP
	}
	out := make([]bqsink.PeriodMonthCount, 0, len(by))
	for pm, a := range by {
		out = append(out, bqsink.PeriodMonthCount{PeriodMonth: pm, Rows: a.rows, Net: math.Round(a.net*100) / 100})
	}
	sort.Slice(out, func(i, j int) bool { return out[i].PeriodMonth < out[j].PeriodMonth })
	return out
}

// DiffPeriodMonthCounts returns AFTER − BEFORE per period_month (union of keys).
func DiffPeriodMonthCounts(before, after []bqsink.PeriodMonthCount) []PeriodMonthNet {
	bMap := map[string]bqsink.PeriodMonthCount{}
	aMap := map[string]bqsink.PeriodMonthCount{}
	keys := map[string]bool{}
	for _, c := range before {
		bMap[c.PeriodMonth] = c
		keys[c.PeriodMonth] = true
	}
	for _, c := range after {
		aMap[c.PeriodMonth] = c
		keys[c.PeriodMonth] = true
	}
	ks := make([]string, 0, len(keys))
	for k := range keys {
		ks = append(ks, k)
	}
	sort.Strings(ks)
	out := make([]PeriodMonthNet, 0, len(ks))
	for _, k := range ks {
		b, a := bMap[k], aMap[k]
		out = append(out, PeriodMonthNet{
			PeriodMonth: k,
			RowsDelta:   a.Rows - b.Rows,
			NetDelta:    math.Round((a.Net-b.Net)*100) / 100,
		})
	}
	return out
}

func sumPeriodCounts(cs []bqsink.PeriodMonthCount) (rows int, net float64) {
	for _, c := range cs {
		rows += c.Rows
		net += c.Net
	}
	return rows, math.Round(net*100) / 100
}

// FormatSellInArchiveReplayDryRun prints the per-month BEFORE / AFTER / net table.
func FormatSellInArchiveReplayDryRun(rep *SellInArchiveReplayReport) string {
	if rep == nil {
		return ""
	}
	var b strings.Builder
	fmt.Fprintf(&b, "sell-in archive replay tenant=%s archive=%s file=%q kind=%s\n",
		rep.TenantID, rep.ArchiveID, rep.FileName, rep.Kind)
	fmt.Fprintf(&b, "%-10s %10s %10s %10s %16s %16s %16s\n",
		"period", "rows_before", "rows_after", "rows_net", "net_before", "net_after", "net_delta")
	before := map[string]bqsink.PeriodMonthCount{}
	after := map[string]bqsink.PeriodMonthCount{}
	for _, c := range rep.Before {
		before[c.PeriodMonth] = c
	}
	for _, c := range rep.After {
		after[c.PeriodMonth] = c
	}
	for _, n := range rep.Net {
		bf, af := before[n.PeriodMonth], after[n.PeriodMonth]
		fmt.Fprintf(&b, "%-10s %10d %10d %10d %16.2f %16.2f %16.2f\n",
			n.PeriodMonth, bf.Rows, af.Rows, n.RowsDelta, bf.Net, af.Net, n.NetDelta)
	}
	fmt.Fprintf(&b, "%-10s %10d %10d %10d %16.2f %16.2f %16.2f\n",
		"TOTAL", rep.BeforeRows, rep.AfterRows, rep.AfterRows-rep.BeforeRows,
		rep.BeforeNet, rep.AfterNet, math.Round((rep.AfterNet-rep.BeforeNet)*100)/100)
	if !rep.Executed {
		b.WriteString("dry run: pass -execute to replace only this archive's sell_in_records rows and refresh aggregates\n")
	}
	return b.String()
}

// ReplaySellInArchive re-parses one Sell-In archive with the current parser and compares
// (or replaces) its BigQuery rows. It never runs orphan cleanup and never touches other archives.
//
// archiveID is required. kind must be sell_in (empty defaults to sell_in).
func (p *Processor) ReplaySellInArchive(ctx context.Context, tenantID, archiveID, kind string, execute bool) (*SellInArchiveReplayReport, error) {
	archiveID = strings.TrimSpace(archiveID)
	if archiveID == "" {
		return nil, fmt.Errorf("archive id is required for sell-in month-cycle replay (refusing blind rewrite)")
	}
	kind = strings.ToLower(strings.TrimSpace(kind))
	if kind == "" {
		kind = string(bqsink.KindSellIn)
	}
	if kind != string(bqsink.KindSellIn) {
		return nil, fmt.Errorf("sell-in archive replay supports kind=%s only, got %q", bqsink.KindSellIn, kind)
	}
	tenantID = normalizeArchiveTenantID(tenantID)

	// CLI / cold process: sidecars live on disk until ListArchivedFiles loads them.
	_ = p.ListArchivedFiles(ctx, tenantID, "", "", "", "sell_in")

	entry, raw, err := p.GetArchivedFile(ctx, tenantID, archiveID)
	if err != nil {
		return nil, err
	}
	if entry == nil || !isSellInArchiveEntry(entry) {
		return nil, fmt.Errorf("archive %s is not a sell_in file", archiveID)
	}

	rep := &SellInArchiveReplayReport{
		TenantID:  tenantID,
		ArchiveID: archiveID,
		FileName:  entry.FileName,
		BatchID:   entry.BatchID,
		Kind:      string(bqsink.KindSellIn),
	}

	if counter, ok := p.sink.(bqsink.SellInArchivePeriodCounter); ok && p.sink != nil && p.sink.Enabled() {
		before, err := counter.SellInArchivePeriodCounts(ctx, tenantID, archiveID)
		if err != nil {
			return nil, fmt.Errorf("read BEFORE period counts: %w", err)
		}
		rep.Before = before
	}
	rep.BeforeRows, rep.BeforeNet = sumPeriodCounts(rep.Before)

	chain := entry.RetailChain
	if chain == "" {
		chain = "fathalla"
	}
	recs, parseRep, err := gemini.ParseSellInPlanWorkbookWithReport(tenantID, entry.FileName, raw, chain)
	if err != nil {
		return nil, fmt.Errorf("re-parse archive %s: %w", archiveID, err)
	}
	if parseRep != nil {
		rep.Layout = parseRep.Layout
	}
	for i := range recs {
		if entry.BatchID != "" {
			recs[i].BatchID = entry.BatchID
		}
		if strings.TrimSpace(recs[i].SourceFilename) == "" {
			recs[i].SourceFilename = entry.FileName
		}
		if strings.TrimSpace(recs[i].PeriodWeek) == "" {
			recs[i].PeriodWeek = "Full Month"
		}
	}
	rep.After = AggregateSellInByPeriod(recs)
	rep.AfterRows, rep.AfterNet = sumPeriodCounts(rep.After)
	rep.Net = DiffPeriodMonthCounts(rep.Before, rep.After)

	if !execute {
		return rep, nil
	}
	if p.sink == nil || !p.sink.Enabled() {
		return rep, fmt.Errorf("sink disabled: cannot execute archive replay")
	}

	meta := bqsink.Meta{
		TenantID:   tenantID,
		BatchID:    entry.BatchID,
		ArchiveID:  entry.ID,
		SourceFile: entry.FileName,
	}
	// Direct sink write: archiveDeleteWhere replaces only this archive/batch/file — not other tenant files.
	res := p.sink.WriteSellIn(ctx, meta, recs)
	rep.Executed = true
	if res != nil {
		rep.SinkStatus = res.Status
		rep.RowsWritten = res.RowsWritten
	}
	if res == nil || res.Failed() {
		errMsg := "nil result"
		if res != nil {
			errMsg = res.Error
		}
		return rep, fmt.Errorf("WriteSellIn failed: %s", errMsg)
	}
	p.noteSellInWritten(ctx, tenantID, res)
	p.setArchiveStoredRows(entry.ID, res.RowsWritten, entry.BatchID)

	// Reload authoritative Sell-In / Sell-Out from BigQuery before materializing aggregates.
	// Sync failure must abort before Materialize (agg_* must not be built on stale memory).
	if err := p.syncDurableSourcesBeforeMaterialize(ctx, tenantID); err != nil {
		rep.AggRefresh = "skipped: source sync failed"
		log.Printf("ERROR [sellin-archive-replay] source sync tenant=%s archive=%s: %v", tenantID, archiveID, err)
		return rep, fmt.Errorf(
			"executed_partial: sell_in_records updated (%d rows, archive=%s) but source reload failed before aggregates materialization: %w — agg_sell_through not refreshed; retry sync+MaterializeAnalyticsAggregates for tenant %s",
			res.RowsWritten, archiveID, err, tenantID,
		)
	}

	refresher := p.resolveAggregatesRefresher()
	if refresher == nil {
		rep.AggRefresh = "failed: no aggregates refresher"
		return rep, fmt.Errorf(
			"executed_partial: sell_in_records updated (%d rows, archive=%s) and memory synced from BigQuery, but aggregates refresh unavailable (no AggregatesRefresher); agg_sell_through not refreshed — retry aggregates for tenant %s",
			res.RowsWritten, archiveID, tenantID,
		)
	}
	if _, err := refresher.MaterializeAnalyticsAggregates(ctx, tenantID); err != nil {
		rep.AggRefresh = "failed: " + err.Error()
		log.Printf("ERROR [sellin-archive-replay] aggregates refresh tenant=%s archive=%s: %v", tenantID, archiveID, err)
		return rep, fmt.Errorf(
			"executed_partial: sell_in_records updated (%d rows, archive=%s) and memory synced from BigQuery, but aggregates refresh failed: %w — agg_sell_through may be stale; retry MaterializeAnalyticsAggregates for tenant %s",
			res.RowsWritten, archiveID, err, tenantID,
		)
	}
	rep.AggRefresh = "ok"
	return rep, nil
}

// syncDurableSourcesBeforeMaterialize reloads Sell-In and Sell-Out from the durable store.
// Unlike SyncDurableFromStore (log-and-continue for background poll), every configured
// source error is returned so archive replay never materializes on a failed load.
func (p *Processor) syncDurableSourcesBeforeMaterialize(ctx context.Context, tenantID string) error {
	if _, err := p.SyncSellInFromStore(ctx, tenantID, true); err != nil {
		return fmt.Errorf("sell_in: %w", err)
	}
	if _, err := p.SyncSellOutFromStore(ctx, tenantID, true); err != nil {
		return fmt.Errorf("sell_out: %w", err)
	}
	return nil
}
