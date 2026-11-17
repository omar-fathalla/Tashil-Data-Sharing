package bigquery

import (
	"context"
	"sort"
	"strings"
	"time"

	"github.com/tashil/data-sharing/backend/internal/domain"
)

// knownChainCacheEntry is one tenant's chain list at an analytics source version.
// The cache has its own mutex and is never read or written under c.mu, so a GET does not queue
// behind a long analytics write.
type knownChainCacheEntry struct {
	version int64
	chains  []domain.KnownChain
}

type chainAccum struct {
	sellIn  int
	sellOut int
	last    time.Time
	hasLast bool
}

func (a *chainAccum) addDate(t time.Time, ok bool) {
	if !ok {
		return
	}
	if !a.hasLast || t.After(a.last) {
		a.last = t
		a.hasLast = true
	}
}

// enrichmentChainKey is the map key chainDiscountProfile uses for a row.
//
// Sell-In applies customer→chain rules first (only "" / "fathalla" rows are remapped; a row already
// stored as "gomla" stays "gomla"). Both streams then use normChainKey (trim + lowercase). An empty
// result is "fathalla", matching enrichSellInRecordLocked and the CPFR sell-out loop. "all" is a
// filter sentinel, not a chain.
func enrichmentChainKey(customer, chain string, applySellInRules bool) string {
	raw := chain
	if applySellInRules {
		raw = resolveSellInChainFromCustomer(activeCustomerChainRules(), customer, chain)
	}
	switch k := normChainKey(raw); k {
	case "all", "الكل":
		return ""
	case "":
		return "fathalla"
	default:
		return k
	}
}

func sellInDataDate(year, month int) (time.Time, bool) {
	if year < 1990 || month < 1 || month > 12 {
		return time.Time{}, false
	}
	return time.Date(year, time.Month(month), 1, 0, 0, 0, 0, time.UTC), true
}

func sellOutDataDate(s string) (time.Time, bool) {
	s = strings.TrimSpace(s)
	if len(s) >= 10 {
		if t, err := time.ParseInLocation("2006-01-02", s[:10], time.UTC); err == nil {
			return t, true
		}
	}
	if len(s) >= 7 {
		if t, err := time.ParseInLocation("2006-01", s[:7], time.UTC); err == nil {
			return t, true
		}
	}
	return time.Time{}, false
}

// collectKnownChainsLocked scans counted rows. Caller holds c.mu for reading.
// Quarantined unknown customers are absent: ingestion never stores those Sell-In rows.
// Sell-out rows that are not the tenant's own brand are skipped, same as tenantChains.
func (c *Client) collectKnownChainsLocked(normTenant string) map[string]*chainAccum {
	out := map[string]*chainAccum{}
	touch := func(key string) *chainAccum {
		a := out[key]
		if a == nil {
			a = &chainAccum{}
			out[key] = a
		}
		return a
	}
	for _, r := range c.sellInRecords[normTenant] {
		if r.TenantID != "" && !matchTenant(r.TenantID, normTenant) {
			continue
		}
		k := enrichmentChainKey(r.CustomerName, r.RetailerChain, true)
		if k == "" {
			continue
		}
		a := touch(k)
		a.sellIn++
		a.addDate(sellInDataDate(r.Year, r.MonthNum))
	}
	for _, r := range c.records {
		if !matchTenant(r.TenantID, normTenant) || !isOwnRecord(r) {
			continue
		}
		k := enrichmentChainKey("", r.RetailerChain, false)
		if k == "" {
			continue
		}
		a := touch(k)
		a.sellOut++
		a.addDate(sellOutDataDate(r.TransactionDate))
	}
	return out
}

func decorateKnownChains(acc map[string]*chainAccum) []domain.KnownChain {
	out := make([]domain.KnownChain, 0, len(acc))
	for k, a := range acc {
		if a.sellIn+a.sellOut == 0 {
			continue
		}
		item := domain.KnownChain{
			Key:         k,
			Name:        k,
			DisplayName: getRetailChainDisplayName(k),
			SellInRows:  a.sellIn,
			SellOutRows: a.sellOut,
			RowCount:    a.sellIn + a.sellOut,
		}
		if a.hasLast {
			item.LastDataDate = a.last.UTC().Format("2006-01-02")
		}
		out = append(out, item)
	}
	sort.Slice(out, func(i, j int) bool {
		if out[i].DisplayName != out[j].DisplayName {
			return out[i].DisplayName < out[j].DisplayName
		}
		return out[i].Key < out[j].Key
	})
	return out
}

func cloneKnownChains(in []domain.KnownChain) []domain.KnownChain {
	if in == nil {
		return []domain.KnownChain{}
	}
	out := make([]domain.KnownChain, len(in))
	copy(out, in)
	return out
}

func (c *Client) knownChainsCached(norm string, version int64, exact bool) ([]domain.KnownChain, bool) {
	c.knownChainsMu.Lock()
	defer c.knownChainsMu.Unlock()
	e, ok := c.knownChainsCache[norm]
	if !ok || (exact && e.version != version) {
		return nil, false
	}
	return cloneKnownChains(e.chains), true
}

func (c *Client) storeKnownChains(norm string, version int64, chains []domain.KnownChain) {
	c.knownChainsMu.Lock()
	defer c.knownChainsMu.Unlock()
	if c.knownChainsCache == nil {
		c.knownChainsCache = map[string]knownChainCacheEntry{}
	}
	// A slower scan must not replace a snapshot taken at a newer source version.
	if prev, ok := c.knownChainsCache[norm]; ok && prev.version > version {
		return
	}
	c.knownChainsCache[norm] = knownChainCacheEntry{version: version, chains: cloneKnownChains(chains)}
}

// KnownChainsWithData returns chains that have counted Sell-In and/or own Sell-Out rows.
//
// It never takes c.mu's write lock. A fresh cache hit does not touch c.mu at all. A refresh uses
// TryRLock, so a writer that already holds the analytics lock (or is waiting for it) is not queued
// behind this read. While that lock is busy the last snapshot is served; with no snapshot yet the
// call waits only until ctx ends (the handler caps that at 5s) and returns ctx.Err().
func (c *Client) KnownChainsWithData(ctx context.Context, tenantID string) ([]domain.KnownChain, error) {
	if ctx == nil {
		ctx = context.Background()
	}
	norm := normalizeTenantKey(tenantID)
	ticker := time.NewTicker(25 * time.Millisecond)
	defer ticker.Stop()
	for {
		if chains, ok := c.knownChainsCached(norm, c.AnalyticsSourceVersion(), true); ok {
			return chains, nil
		}
		if c.mu.TryRLock() {
			acc := c.collectKnownChainsLocked(norm)
			ver := c.AnalyticsSourceVersion()
			c.mu.RUnlock()
			chains := decorateKnownChains(acc)
			c.storeKnownChains(norm, ver, chains)
			return cloneKnownChains(chains), nil
		}
		if stale, ok := c.knownChainsCached(norm, 0, false); ok {
			return stale, nil
		}
		select {
		case <-ctx.Done():
			return nil, ctx.Err()
		case <-ticker.C:
		}
	}
}
