package bigquery

import "github.com/tashil/data-sharing/backend/internal/domain"

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
