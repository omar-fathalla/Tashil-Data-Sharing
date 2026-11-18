package bigquery

import (
	"context"
	"fmt"
	"log"
	"sort"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"github.com/tashil/data-sharing/backend/internal/domain"
)

// AggregatesWriter mirrors a tenant's materialized layer to durable storage (BigQuery).
type AggregatesWriter interface {
	WriteAnalyticsAggregates(ctx context.Context, agg *domain.AnalyticsAggregates) error
}

type cachedPayload struct {
	version int64
	payload *domain.CPFRDashboardPayload
}

// precomputeStore is the in-memory materialized layer. Every source mutation bumps
// sourceVersion; anything computed at an older version is stale and recomputed.
type precomputeStore struct {
	sourceVersion atomic.Int64

	mu         sync.Mutex
	aggregates map[string]*domain.AnalyticsAggregates // normTenant -> layer
	payloads   map[string]cachedPayload               // normTenant|filter -> dashboard
	writer     AggregatesWriter
	tenants    []string
	timer      *time.Timer
	// disableBackgroundMirror skips scheduleRecompute and the async mirror in
	// GetAnalyticsAggregates (CLI backfill uses MaterializeAnalyticsAggregates instead).
	disableBackgroundMirror bool
	listenMu                sync.Mutex
	listeners               []func()
}

const maxCachedPayloads = 64

// recomputeDelay debounces bursts of source changes (e.g. multi-file uploads).
var recomputeDelay = 3 * time.Second

// aggregatesNow stamps AnalyticsAggregates.UpdatedAt. Tests inject a fixed clock.
var aggregatesNow = func() time.Time { return time.Now().UTC() }

// scheduleAfter runs the debounced background recompute. Tests replace it to
// avoid wall-clock AfterFunc races under Mac CI load.
var scheduleAfter = time.AfterFunc

// bumpSourceVersion marks every precomputed result stale and schedules a debounced
// background recompute (+ BigQuery mirror). Safe to call while holding c.mu.
func (c *Client) bumpSourceVersion() {
	c.precompute.sourceVersion.Add(1)
	c.scheduleRecompute()
	c.precompute.listenMu.Lock()
	ls := append([]func(){}, c.precompute.listeners...)
	c.precompute.listenMu.Unlock()
	for _, l := range ls {
		l() // listeners must not block (e.g. schedule a debounced job)
	}
}

// OnSourceChange registers a non-blocking callback run on every source change.
func (c *Client) OnSourceChange(f func()) {
	c.precompute.listenMu.Lock()
	c.precompute.listeners = append(c.precompute.listeners, f)
	c.precompute.listenMu.Unlock()
}

// AnalyticsSourceVersion is the current source version.
func (c *Client) AnalyticsSourceVersion() int64 { return c.precompute.sourceVersion.Load() }

// WithAggregatesWriter attaches the BigQuery mirror and the tenants to keep materialized.
// nil disables background recompute (reads still recompute lazily when stale).
func (c *Client) WithAggregatesWriter(w AggregatesWriter, tenants ...string) *Client {
	c.attachAggregatesWriter(w, tenants...)
	c.scheduleRecompute()
	return c
}

// AttachAggregatesWriterForSyncMirror sets the writer without scheduling background
// recompute. Used by CLI backfill together with MaterializeAnalyticsAggregates and
// DisableBackgroundAggregatesMirror so the process does not exit with writes in flight.
func (c *Client) AttachAggregatesWriterForSyncMirror(w AggregatesWriter, tenants ...string) *Client {
	c.attachAggregatesWriter(w, tenants...)
	return c
}

func (c *Client) attachAggregatesWriter(w AggregatesWriter, tenants ...string) {
	c.precompute.mu.Lock()
	c.precompute.writer = w
	c.precompute.tenants = append(c.precompute.tenants, tenants...)
	c.precompute.mu.Unlock()
}

// DisableBackgroundAggregatesMirror turns off scheduleRecompute and the async mirror
// inside GetAnalyticsAggregates. Call MaterializeAnalyticsAggregates for a synchronous write.
func (c *Client) DisableBackgroundAggregatesMirror() *Client {
	c.precompute.mu.Lock()
	c.precompute.disableBackgroundMirror = true
	if c.precompute.timer != nil {
		c.precompute.timer.Stop()
		c.precompute.timer = nil
	}
	c.precompute.mu.Unlock()
	return c
}

// AggregatesWriterAttached reports whether a mirror writer is configured (tests / dry-run guards).
func (c *Client) AggregatesWriterAttached() bool {
	c.precompute.mu.Lock()
	defer c.precompute.mu.Unlock()
	return c.precompute.writer != nil
}

func (c *Client) scheduleRecompute() {
	p := &c.precompute
	p.mu.Lock()
	defer p.mu.Unlock()
	if p.writer == nil || p.disableBackgroundMirror {
		return
	}
	if p.timer != nil {
		p.timer.Stop()
	}
	p.timer = scheduleAfter(recomputeDelay, func() {
		p.mu.Lock()
		set := map[string]string{}
		for _, t := range p.tenants {
			set[normalizeTenantKey(t)] = t
		}
		for t := range p.aggregates {
			set[t] = t
		}
		p.mu.Unlock()
		for _, t := range set {
			if _, err := c.GetAnalyticsAggregates(context.Background(), t); err != nil {
				log.Printf("ERROR [precompute] tenant=%s recompute failed: %v", t, err)
			}
		}
	})
}

func payloadKey(normTenant string, f CPFRFilter) string {
	return normTenant + "|" + fmt.Sprintf("%+v", f)
}

// GetCPFRDashboardCached serves the dashboard from the materialized layer: it is computed once
// per (tenant, filter, source version) and reused until any source changes.
// It returns the payload and the source version it was computed at.
func (c *Client) GetCPFRDashboardCached(ctx context.Context, tenantID string, filter CPFRFilter) (*domain.CPFRDashboardPayload, int64, error) {
	c.syncChainDiscounts(ctx, tenantID)
	key := payloadKey(normalizeTenantKey(tenantID), filter)
	p := &c.precompute
	v := p.sourceVersion.Load()
	p.mu.Lock()
	if cp, ok := p.payloads[key]; ok && cp.version == v {
		p.mu.Unlock()
		return cp.payload, v, nil
	}
	p.mu.Unlock()

	payload, err := c.GetCPFRDashboard(ctx, tenantID, filter)
	if err != nil {
		return nil, 0, err
	}
	p.mu.Lock()
	if p.payloads == nil || len(p.payloads) >= maxCachedPayloads {
		p.payloads = map[string]cachedPayload{}
	}
	// Only store if no source changed while computing; otherwise the next read recomputes.
	if p.sourceVersion.Load() == v {
		p.payloads[key] = cachedPayload{version: v, payload: payload}
	}
	p.mu.Unlock()
	return payload, v, nil
}

// tenantChains lists every chain with sell-out or sell-in data for the tenant, sorted.
func (c *Client) tenantChains(tenantID string) []string {
	c.mu.RLock()
	defer c.mu.RUnlock()
	norm := normalizeTenantKey(tenantID)
	set := map[string]bool{}
	for _, r := range c.records {
		if !matchTenant(r.TenantID, norm) || !isOwnRecord(r) {
			continue
		}
		ch := strings.ToLower(strings.TrimSpace(r.RetailerChain))
		if ch == "" {
			ch = "fathalla"
		}
		set[ch] = true
	}
	for _, r := range c.sellInRecords[norm] {
		if ch := strings.ToLower(strings.TrimSpace(r.RetailerChain)); ch != "" {
			set[ch] = true
		}
	}
	out := make([]string, 0, len(set))
	for ch := range set {
		out = append(out, ch)
	}
	sort.Strings(out)
	return out
}

// BuildAnalyticsAggregatesFromPayload derives the three materialized tables for one chain
// ("all" for all chains) from the CPFR computation result. Exported for the equivalence test.
func BuildAnalyticsAggregatesFromPayload(chain string, p *domain.CPFRDashboardPayload, version int64, at time.Time) ([]domain.AggChainProfitMonthly, []domain.AggSkuCostMargin, []domain.AggSellThrough) {
	var profit []domain.AggChainProfitMonthly
	var through []domain.AggSellThrough
	for _, m := range p.MonthlyReconciliation {
		profit = append(profit, domain.AggChainProfitMonthly{
			Chain: chain, Year: m.Year, Month: m.MonthNum, HasActualSellOut: m.HasActualSellOut,
			SellOutUnits: m.SellOutUnits, SellOutValueEGP: m.SellOutValueEGP,
			SellOutValueWithCostEGP: m.SellOutValueWithCostEGP, SellOutMissingCostValueEGP: m.SellOutMissingCostValueEGP,
			SellOutMissingCostUnits: m.SellOutMissingCostUnits, FactoryCostInclVATEGP: m.SellOutFactoryCostInclVATEGP,
			ChainGrossMarginEGP: m.ChainGrossMarginEGP, ChainGrossMarginPct: m.ChainGrossMarginPct,
			Version: version, ComputedAt: at,
		})
		through = append(through, domain.AggSellThrough{
			Chain: chain, Year: m.Year, Month: m.MonthNum, SellInCases: m.SellInCases, SellInValueEGP: m.SellInValueEGP,
			SellOutEstCases: m.SellOutEstCases, SellThroughRatePct: m.SellThroughRatePct,
			ClosingStockCases: m.ClosingStockCases, ClosingStockValueEGP: m.ClosingStockValueEGP,
			Version: version, ComputedAt: at,
		})
	}
	var sku []domain.AggSkuCostMargin
	for _, it := range p.InventoryAndPOItems {
		sku = append(sku, domain.AggSkuCostMargin{
			Chain: chain, ItemCode: it.ItemCode, Barcode: it.Barcode, SKUName: it.SKUName, Brand: it.Brand,
			SellOutUnits: it.SellOutUnits, SellOutValueEGP: it.SellOutValueEGP, SellOutFactoryCostEGP: it.SellOutFactoryCostEGP,
			ChainGrossMarginEGP: it.ChainGrossMarginEGP, FactoryCostMissing: it.FactoryCostMissing,
			SellOutMissingCostValueEGP: it.SellOutMissingCostValueEGP, Version: version, ComputedAt: at,
		})
	}
	return profit, sku, through
}

// GetAnalyticsAggregates returns the tenant's materialized layer, recomputing it only when a
// source changed since the last computation. A fresh computation is mirrored to BigQuery
// asynchronously (unless DisableBackgroundAggregatesMirror was called).
func (c *Client) GetAnalyticsAggregates(ctx context.Context, tenantID string) (*domain.AnalyticsAggregates, error) {
	agg, fresh, w, v, backgroundOK, err := c.loadOrComputeAnalyticsAggregates(ctx, tenantID)
	if err != nil {
		return nil, err
	}
	if fresh && w != nil && backgroundOK {
		go func() {
			wctx, cancel := context.WithTimeout(context.Background(), 5*time.Minute)
			defer cancel()
			if err := w.WriteAnalyticsAggregates(wctx, agg); err != nil {
				log.Printf("ERROR [precompute] BigQuery mirror tenant=%s version=%d failed: %v", agg.TenantID, v, err)
			}
		}()
	}
	return agg, nil
}

// MaterializeAnalyticsAggregates recomputes the tenant's agg_* layer and mirrors it to
// BigQuery synchronously. The caller must not exit until this returns; write failures
// are returned (unlike GetAnalyticsAggregates' fire-and-forget mirror).
func (c *Client) MaterializeAnalyticsAggregates(ctx context.Context, tenantID string) (*domain.AnalyticsAggregates, error) {
	agg, _, w, _, _, err := c.loadOrComputeAnalyticsAggregates(ctx, tenantID)
	if err != nil {
		return nil, err
	}
	if w == nil {
		return agg, fmt.Errorf("no aggregates writer configured")
	}
	if err := w.WriteAnalyticsAggregates(ctx, agg); err != nil {
		return agg, err
	}
	return agg, nil
}

func (c *Client) loadOrComputeAnalyticsAggregates(ctx context.Context, tenantID string) (
	agg *domain.AnalyticsAggregates, fresh bool, w AggregatesWriter, v int64, backgroundOK bool, err error,
) {
	c.syncChainDiscounts(ctx, tenantID)
	norm := normalizeTenantKey(tenantID)
	p := &c.precompute
	v = p.sourceVersion.Load()
	p.mu.Lock()
	backgroundOK = !p.disableBackgroundMirror
	if a, ok := p.aggregates[norm]; ok && a.Version == v {
		w = p.writer
		p.mu.Unlock()
		return a, false, w, v, backgroundOK, nil
	}
	p.mu.Unlock()

	at := aggregatesNow()
	agg = &domain.AnalyticsAggregates{TenantID: norm, Version: v, UpdatedAt: at,
		ChainProfitMonthly: []domain.AggChainProfitMonthly{}, SkuCostMargin: []domain.AggSkuCostMargin{}, SellThrough: []domain.AggSellThrough{}}
	chains := append([]string{"all"}, c.tenantChains(tenantID)...)
	for _, ch := range chains {
		f := CPFRFilter{RetailerChain: ch}
		payload, _, e := c.GetCPFRDashboardCached(ctx, tenantID, f)
		if e != nil {
			return nil, false, nil, v, backgroundOK, fmt.Errorf("compute chain %s: %w", ch, e)
		}
		pr, sk, th := BuildAnalyticsAggregatesFromPayload(ch, payload, v, at)
		agg.ChainProfitMonthly = append(agg.ChainProfitMonthly, pr...)
		agg.SkuCostMargin = append(agg.SkuCostMargin, sk...)
		agg.SellThrough = append(agg.SellThrough, th...)
	}

	p.mu.Lock()
	backgroundOK = !p.disableBackgroundMirror
	if p.sourceVersion.Load() != v {
		w = p.writer
		p.mu.Unlock()
		// Source changed mid-compute: serve it, but do not store or treat as fresh mirror.
		return agg, false, w, v, backgroundOK, nil
	}
	if p.aggregates == nil {
		p.aggregates = map[string]*domain.AnalyticsAggregates{}
	}
	p.aggregates[norm] = agg
	w = p.writer
	p.mu.Unlock()
	return agg, true, w, v, backgroundOK, nil
}
