package bigquery

import "github.com/tashil/data-sharing/backend/internal/domain"

// ReplaceSellInRecords swaps a tenant's whole Sell-In set for records loaded from the durable store
// (BigQuery). Records are re-enriched against the current product master so cost columns follow the
// latest price list, exactly like a fresh upload.
func (c *Client) ReplaceSellInRecords(tenantID string, records []domain.SellInRecord) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.bumpSourceVersion()
	if c.sellInRecords == nil {
		c.sellInRecords = make(map[string][]domain.SellInRecord)
	}
	norm := normalizeTenantKey(tenantID)
	out := make([]domain.SellInRecord, len(records))
	copy(out, records)
	// Plan rows older loads may still carry (stored by file name) are diverted to the Plan store.
	out, planRecords := splitSellInPlan("", out)
	c.putSellInPlanLocked(norm, planRecords)
	memo := sellInMatchMemo{}
	for i := range out {
		if out[i].TenantID == "" {
			out[i].TenantID = norm
		}
		c.enrichSellInRecordMemoLocked(&out[i], memo)
	}
	c.sellInRecords[norm] = out
}

// SellInRecordsSnapshot returns a copy of a tenant's in-memory Sell-In records.
func (c *Client) SellInRecordsSnapshot(tenantID string) []domain.SellInRecord {
	c.mu.RLock()
	defer c.mu.RUnlock()
	src := c.sellInRecords[normalizeTenantKey(tenantID)]
	out := make([]domain.SellInRecord, len(src))
	copy(out, src)
	return out
}
