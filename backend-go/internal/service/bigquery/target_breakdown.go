package bigquery

import (
	"context"
	"strings"

	"github.com/tashil/data-sharing/backend/internal/domain"
	"github.com/tashil/data-sharing/backend/internal/service/targetalloc"
)

// GetTarget returns one saved target of a tenant by id.
func (c *Client) GetTarget(_ context.Context, tenantID, targetID string) (*domain.TargetRecord, bool) {
	c.mu.RLock()
	defer c.mu.RUnlock()
	for _, t := range c.targets[normalizeTenantKey(tenantID)] {
		if t.ID == targetID {
			cp := t
			return &cp, true
		}
	}
	return nil, false
}

type memTargetSource struct {
	c        *Client
	tenant   string
	chain    string
	chainSet bool
}

// TargetBreakdownSource serves the breakdown from the in-memory Sell-Out records (local runs and
// BigQuery fallback). It applies the same own-SKU, chain and date rules as the BigQuery path.
func (c *Client) TargetBreakdownSource(tenantID, chain string) targetalloc.Source {
	ch := targetalloc.ChainFilter(chain)
	return &memTargetSource{c: c, tenant: normalizeTenantKey(tenantID), chain: ch, chainSet: ch != ""}
}

func (m *memTargetSource) match(r domain.SellOutFact) bool {
	if !matchTenant(r.TenantID, m.tenant) || !isOwnRecord(r) {
		return false
	}
	return !m.chainSet || strings.EqualFold(r.RetailerChain, m.chain)
}

func (m *memTargetSource) Coverage(context.Context) ([]targetalloc.MonthCoverage, error) {
	m.c.mu.RLock()
	defer m.c.mu.RUnlock()
	counts := map[string]int64{}
	for _, r := range m.c.records {
		if !m.match(r) || len(r.TransactionDate) < 7 {
			continue
		}
		counts[r.TransactionDate[:7]]++
	}
	out := make([]targetalloc.MonthCoverage, 0, len(counts))
	for k, n := range counts {
		out = append(out, targetalloc.MonthCoverage{Month: k, Rows: n})
	}
	return out, nil
}

func (m *memTargetSource) Rows(_ context.Context, baseline, actual targetalloc.Window) ([]targetalloc.Row, error) {
	m.c.mu.RLock()
	defer m.c.mu.RUnlock()
	type key struct{ store, sku, name, cat string }
	agg := map[key]*targetalloc.Row{}
	var order []key
	inWin := func(d string, w targetalloc.Window) bool { return len(d) >= 10 && d[:10] >= w.Start && d[:10] <= w.End }
	for _, r := range m.c.records {
		if !m.match(r) {
			continue
		}
		inB, inA := inWin(r.TransactionDate, baseline), inWin(r.TransactionDate, actual)
		if !inB && !inA {
			continue
		}
		storeKey := r.StoreID
		if storeKey == "" {
			storeKey = r.StoreName
		}
		skuKey := r.ItemCode
		if skuKey == "" {
			skuKey = r.Barcode
		}
		if skuKey == "" {
			skuKey = r.SKUName
		}
		k := key{storeKey, skuKey, r.SKUName, r.Category}
		row := agg[k]
		if row == nil {
			row = &targetalloc.Row{StoreKey: storeKey, StoreID: r.StoreID, StoreName: r.StoreName, SKUKey: skuKey, SKUName: r.SKUName, Category: r.Category}
			agg[k] = row
			order = append(order, k)
		}
		if int64(r.UnitsPerCarton) > row.UnitsPerCarton {
			row.UnitsPerCarton = int64(r.UnitsPerCarton)
		}
		if r.StoreName != "" {
			row.StoreName = r.StoreName
		}
		if inB {
			row.BaseRev += r.NetRevenue
			row.BaseUnits += int64(r.QuantitySold)
		}
		if inA {
			row.ActRev += r.NetRevenue
			row.ActUnits += int64(r.QuantitySold)
			row.ActRows++
		}
	}
	out := make([]targetalloc.Row, 0, len(order))
	for _, k := range order {
		out = append(out, *agg[k])
	}
	return out, nil
}
