package bigquery

import (
	"fmt"
	"sort"
	"strconv"
	"strings"

	"github.com/tashil/data-sharing/backend/internal/domain"
)

// ReplaceSellOutFacts swaps a tenant's whole Sell-Out fact set for facts loaded from the durable store
// (BigQuery), keeping other tenants untouched. Facts are kept exactly as stored: they were enriched at
// ingest time, and re-enriching against today's product master would change factory costs relative to
// what the uploading instance holds in memory.
func (c *Client) ReplaceSellOutFacts(tenantID string, facts []domain.SellOutFact) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.invalidateKPICache()
	c.bumpSourceVersion()
	slug := normalizeBQTenantSlug(tenantID)
	if c.cleanedTenants != nil && slug != "" {
		c.cleanedTenants[slug] = true // never auto-seed demo data over durable data
	}
	kept := make([]domain.SellOutFact, 0, len(c.records)+len(facts))
	for _, r := range c.records {
		if !matchTenant(r.TenantID, tenantID) {
			kept = append(kept, r)
		}
	}
	kept = append(kept, facts...)
	c.records = kept
}

// SellOutFactsSnapshot returns a copy of a tenant's in-memory Sell-Out facts.
func (c *Client) SellOutFactsSnapshot(tenantID string) []domain.SellOutFact {
	c.mu.RLock()
	defer c.mu.RUnlock()
	out := []domain.SellOutFact{}
	for _, r := range c.records {
		if matchTenant(r.TenantID, tenantID) {
			out = append(out, r)
		}
	}
	return out
}

// SellOutMonths returns the distinct calendar months (1..12) that have Sell-Out facts for tenant/year,
// ascending. year<=0 returns months across every year that has data.
func (c *Client) SellOutMonths(tenantID string, year int) []int {
	c.mu.RLock()
	defer c.mu.RUnlock()
	return monthsFromSellOutFacts(c.records, tenantID, year)
}

// monthsFromSellOutFacts is the pure helper behind SellOutMonths (testable without locking).
func monthsFromSellOutFacts(facts []domain.SellOutFact, tenantID string, year int) []int {
	set := map[int]bool{}
	yPrefix := ""
	if year > 0 {
		yPrefix = fmt.Sprintf("%04d-", year)
	}
	for _, r := range facts {
		if !matchTenant(r.TenantID, tenantID) {
			continue
		}
		if len(r.TransactionDate) < 7 {
			continue
		}
		if year > 0 && !strings.HasPrefix(r.TransactionDate, yPrefix) {
			continue
		}
		mo, err := strconv.Atoi(r.TransactionDate[5:7])
		if err != nil || mo < 1 || mo > 12 {
			continue
		}
		set[mo] = true
	}
	out := make([]int, 0, len(set))
	for m := range set {
		out = append(out, m)
	}
	sort.Ints(out)
	return out
}
