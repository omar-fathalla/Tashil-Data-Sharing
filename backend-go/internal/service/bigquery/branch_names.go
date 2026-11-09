package bigquery

import (
	"sort"
	"strings"

	"github.com/tashil/data-sharing/backend/internal/service/branchmaster"
)

// CollectBranchNameOccurrences gathers distinct raw store/customer names across
// in-memory Sell-Out, Sell-In, and Returns facts for a tenant (dry-run input).
// Does not touch production persistence.
func (c *Client) CollectBranchNameOccurrences(tenantID string) []branchmaster.RawOccurrence {
	c.mu.RLock()
	defer c.mu.RUnlock()

	norm := normalizeTenantKey(tenantID)
	type key struct {
		raw, chain, source string
	}
	seen := map[key]struct{}{}
	var out []branchmaster.RawOccurrence

	add := func(raw, chain, source string) {
		raw = strings.TrimSpace(raw)
		if raw == "" {
			return
		}
		chain = strings.ToLower(strings.TrimSpace(chain))
		k := key{raw: raw, chain: chain, source: source}
		if _, ok := seen[k]; ok {
			return
		}
		seen[k] = struct{}{}
		out = append(out, branchmaster.RawOccurrence{RawName: raw, ChainSlug: chain, Source: source})
	}

	for _, r := range c.records {
		if !matchTenant(r.TenantID, tenantID) && normalizeTenantKey(r.TenantID) != norm {
			continue
		}
		add(r.StoreName, r.RetailerChain, "sell_out")
	}
	for _, recs := range c.sellInRecords {
		for _, r := range recs {
			if normalizeTenantKey(r.TenantID) != norm && r.TenantID != "" && !matchTenant(r.TenantID, tenantID) {
				continue
			}
			add(r.CustomerName, r.RetailerChain, "sell_in")
			if r.NetValueEGP < 0 || strings.Contains(strings.ToLower(r.TransactionType), "return") || strings.Contains(r.TransactionType, "مرتجع") {
				add(r.CustomerName, r.RetailerChain, "returns")
			}
		}
	}

	sort.Slice(out, func(i, j int) bool {
		if out[i].ChainSlug != out[j].ChainSlug {
			return out[i].ChainSlug < out[j].ChainSlug
		}
		return out[i].RawName < out[j].RawName
	})
	return out
}
