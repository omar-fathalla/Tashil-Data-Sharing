package bigquery

import (
	"context"
	"fmt"
	"strings"

	"github.com/tashil/data-sharing/backend/internal/domain"
)

type sellInReturnsCacheEntry struct {
	version int64
	report  SellInReturnsReport
}

func sellInReturnsCacheKey(tenant string, f SellInReturnsFilter) string {
	norm := func(s string) string {
		t := strings.ToLower(strings.TrimSpace(s))
		if t == "all" || t == "الكل" {
			return ""
		}
		return t
	}
	return fmt.Sprintf("%s|y=%d|m=%d|c=%s|b=%s|p=%s|g=%s",
		normalizeTenantKey(tenant),
		f.Year, f.Month,
		norm(f.Chain), norm(f.Branch), norm(f.Product), norm(f.ProductGroup),
	)
}

// GetSellInReturnsCached returns the Phase-1/2 المرتجعات report, served from an
// in-memory cache keyed by (tenant, filter, analytics source version).
// Aggregation skips GetSellInRecords enrich+sort (not needed for returns).
func (c *Client) GetSellInReturnsCached(ctx context.Context, tenantID string, filter SellInReturnsFilter) SellInReturnsReport {
	_ = ctx
	v := c.AnalyticsSourceVersion()
	key := sellInReturnsCacheKey(tenantID, filter)

	c.returnsCacheMu.RLock()
	if c.returnsCache != nil {
		if ent, ok := c.returnsCache[key]; ok && ent.version == v {
			rep := ent.report
			c.returnsCacheMu.RUnlock()
			return rep
		}
	}
	c.returnsCacheMu.RUnlock()

	recs := c.sellInRecordsForReturns(tenantID, filter.Year, filter.Chain)
	rep := AggregateSellInReturns(recs, filter)

	c.returnsCacheMu.Lock()
	if c.returnsCache == nil {
		c.returnsCache = make(map[string]sellInReturnsCacheEntry)
	}
	// Only store if source version is unchanged while we aggregated.
	if c.AnalyticsSourceVersion() == v {
		c.returnsCache[key] = sellInReturnsCacheEntry{version: v, report: rep}
	}
	c.returnsCacheMu.Unlock()
	return rep
}

// sellInRecordsForReturns returns year/chain-scoped Sell-In rows without the
// GetSellInRecords enrich+full-sort path (those dominate large-year latency).
func (c *Client) sellInRecordsForReturns(tenantID string, year int, chain string) []domain.SellInRecord {
	c.mu.RLock()
	defer c.mu.RUnlock()

	normTenant := normalizeTenantKey(tenantID)
	raw := c.sellInRecords[normTenant]
	chainFilter := strings.ToLower(strings.TrimSpace(chain))
	if chainFilter == "all" || chainFilter == "الكل" {
		chainFilter = ""
	}

	out := make([]domain.SellInRecord, 0, len(raw)/4+1)
	for _, r := range raw {
		if year > 0 && r.Year != year {
			continue
		}
		rChain := strings.ToLower(strings.TrimSpace(r.RetailerChain))
		if rChain == "" {
			rChain = "fathalla"
		}
		if chainFilter != "" && !strings.EqualFold(rChain, chainFilter) {
			continue
		}
		if r.TenantID == "" {
			r.TenantID = normTenant
		}
		if r.RetailerChain == "" {
			r.RetailerChain = rChain
		}
		out = append(out, r)
	}
	return out
}
