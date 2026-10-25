package bqsink

import (
	"testing"
	"time"

	"github.com/tashil/data-sharing/backend/internal/domain"
)

func TestPlanAggregatesReplacesByTenant(t *testing.T) {
	at := time.Date(2026, 10, 25, 12, 0, 0, 0, time.UTC)
	agg := &domain.AnalyticsAggregates{TenantID: "adeco", Version: 7, UpdatedAt: at,
		ChainProfitMonthly: []domain.AggChainProfitMonthly{{Chain: "Fathalla", Year: 2026, Month: 1, SellOutValueEGP: 10, Version: 7, ComputedAt: at}},
		SkuCostMargin:      []domain.AggSkuCostMargin{{Chain: "all", ItemCode: "X", Version: 7, ComputedAt: at}},
	}
	plans := PlanAggregates(agg, at)
	if len(plans) != 3 {
		t.Fatalf("expected 3 plans")
	}
	names := []string{TableAggChainProfitMonthly, TableAggSkuCostMargin, TableAggSellThrough}
	for i, p := range plans {
		if p.Table.Name != names[i] || p.DeleteWhere != "tenant_id = @tenant_id" || p.Meta.TenantID != "tenant-adeco" || p.Meta.BatchID != "agg_v7" {
			t.Fatalf("bad plan %d: %+v", i, p.Meta)
		}
		if field(p.Table.Schema, ColTenantID) == nil || field(p.Table.Schema, "version") == nil {
			t.Fatalf("schema of %s misses tenant_id/version", p.Table.Name)
		}
	}
	r := plans[0].Rows[0]
	if r[ColChainKey] != "fathalla" || r[ColPartitionDate] != "2026-10-25" || r["sell_out_value_egp"] != 10.0 {
		t.Fatalf("unexpected row %v", r)
	}
	if len(plans[2].Rows) != 0 {
		t.Fatalf("empty table must have no rows (writer then deletes the tenant's rows)")
	}
}
