package bqsink

import (
	"strings"
	"testing"
)

func TestRecordsFilterSQL(t *testing.T) {
	where, params := RecordsFilterSQL(RecordsQuery{TenantID: "tenant-adeco", Chain: "Fathalla", Store: "12", StartDate: "2026-01-01", EndDate: "2026-01-31"})
	for _, want := range []string{"is_own_brand", "LOWER(IFNULL(retailer_chain, '')) = LOWER(@chain)", "STRPOS(IFNULL(store_name, ''), @store)", "transaction_date >= @start_date", "transaction_date <= @end_date"} {
		if !strings.Contains(where, want) {
			t.Errorf("where missing %q: %s", want, where)
		}
	}
	names := map[string]bool{}
	for _, p := range params {
		names[p.Name] = true
	}
	for _, n := range []string{"tenant_id", "chain", "store", "start_date", "end_date"} {
		if !names[n] {
			t.Errorf("missing param %s", n)
		}
	}
	allWhere, _ := RecordsFilterSQL(RecordsQuery{TenantID: "t", Chain: "all", Supplier: "all_market"})
	if allWhere != "TRUE" {
		t.Errorf("all filters should not constrain: %s", allWhere)
	}
	supWhere, _ := RecordsFilterSQL(RecordsQuery{TenantID: "t", Supplier: "Nestle"})
	if !strings.Contains(supWhere, "@supplier") {
		t.Errorf("supplier filter missing: %s", supWhere)
	}
}

func TestRecordsSQLTenantScopedAndPaged(t *testing.T) {
	totals, skus, page := RecordsSQL("`p.d.sell_out_facts`", "TRUE")
	for name, q := range map[string]string{"totals": totals, "skus": skus, "page": page} {
		if !strings.Contains(q, "tenant_id = @tenant_id") {
			t.Errorf("%s not tenant scoped", name)
		}
		if strings.Contains(q, "ORDER BY ingested_at, record_id") {
			t.Errorf("%s keeps serving-view ORDER BY", name)
		}
	}
	if !strings.Contains(page, "LIMIT @limit OFFSET @offset") || !strings.Contains(page, "ORDER BY transaction_date DESC, net_revenue DESC") {
		t.Errorf("page query not paged/ordered: %s", page)
	}
	if !strings.Contains(skus, "GROUP BY COALESCE(NULLIF(item_code, '')") {
		t.Errorf("sku grouping missing")
	}
}
