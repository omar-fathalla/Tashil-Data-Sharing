package bigquery

import (
	"strings"

	"github.com/tashil/data-sharing/backend/internal/domain"
)

// Plan workbooks (Adco_Fathalla_Sell_In_Plan_2026_Clean.xlsx, sheet «Sell_In_Plan_2026») are the supplier's
// plan, not Sell-In actuals. Their rows live in a store of their own (sellInPlanRecords) that only the
// Brand Master reads; sellInRecords — and with it every Sell-In total, target achievement and branch line —
// never contains them. A row is a Plan row by its exact source marker (domain.SellInRecord.IsSellInPlan),
// never by its values.

// splitSellInPlan separates Plan rows from Sell-In rows. filename is the upload's file name, used for
// rows that carry none.
func splitSellInPlan(filename string, recs []domain.SellInRecord) (sellIn, plan []domain.SellInRecord) {
	for i := range recs {
		if strings.TrimSpace(recs[i].SourceFilename) == "" {
			recs[i].SourceFilename = strings.TrimSpace(filename)
		}
	}
	for _, r := range recs {
		if r.IsSellInPlan() {
			r.SourceKind = domain.SellInSourceKindPlan
			plan = append(plan, r)
		} else {
			sellIn = append(sellIn, r)
		}
	}
	if len(plan) == 0 {
		return recs, nil
	}
	return sellIn, plan
}

// putSellInPlanLocked stores Plan rows, replacing any Plan rows of the same source file. Caller holds c.mu.
func (c *Client) putSellInPlanLocked(normTenant string, plan []domain.SellInRecord) {
	if len(plan) == 0 {
		return
	}
	if c.sellInPlanRecords == nil {
		c.sellInPlanRecords = make(map[string][]domain.SellInRecord)
	}
	files := map[string]bool{}
	for i := range plan {
		if plan[i].TenantID == "" {
			plan[i].TenantID = normTenant
		}
		if strings.TrimSpace(plan[i].RetailerChain) == "" {
			plan[i].RetailerChain = "fathalla"
		}
		files[strings.ToLower(strings.TrimSpace(plan[i].SourceFilename))] = true
	}
	existing := c.sellInPlanRecords[normTenant]
	merged := make([]domain.SellInRecord, 0, len(existing)+len(plan))
	for _, r := range existing {
		if !files[strings.ToLower(strings.TrimSpace(r.SourceFilename))] {
			merged = append(merged, r)
		}
	}
	c.sellInPlanRecords[normTenant] = append(merged, plan...)
}

// SellInPlanRecordsSnapshot returns a copy of a tenant's Plan rows (Brand Master source). They are not
// Sell-In and are not part of SellInRecordsSnapshot.
func (c *Client) SellInPlanRecordsSnapshot(tenantID string) []domain.SellInRecord {
	c.mu.RLock()
	defer c.mu.RUnlock()
	src := c.sellInPlanRecords[normalizeTenantKey(tenantID)]
	out := make([]domain.SellInRecord, len(src))
	copy(out, src)
	return out
}
