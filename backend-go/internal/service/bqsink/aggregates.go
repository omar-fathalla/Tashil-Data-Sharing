package bqsink

import (
	"context"
	"fmt"
	"strings"
	"time"

	"cloud.google.com/go/bigquery"

	"github.com/tashil/data-sharing/backend/internal/domain"
)

// Materialized analytics tables (precomputed layer), one full replace per tenant per source version.
const (
	TableAggChainProfitMonthly = "agg_chain_profit_monthly"
	TableAggSkuCostMargin      = "agg_sku_cost_margin"
	TableAggSellThrough        = "agg_sell_through"

	KindAggregates Kind = "analytics_aggregates"
)

func aggSpec(name string, sample interface{}, cluster []string, desc string) TableSpec {
	return TableSpec{Name: name, Schema: SchemaFor(sample), PartitionType: bigquery.DayPartitioningType,
		ClusterBy: append([]string{ColTenantID}, cluster...), Description: desc}
}

// AggregateSpecs returns the three materialized table definitions.
func AggregateSpecs() []TableSpec {
	return []TableSpec{
		aggSpec(TableAggChainProfitMonthly, domain.AggChainProfitMonthly{}, []string{"chain"}, "Precomputed chain profit per month (from the CPFR computation)."),
		aggSpec(TableAggSkuCostMargin, domain.AggSkuCostMargin{}, []string{"chain", "item_code"}, "Precomputed SKU cost and chain margin (from the CPFR computation)."),
		aggSpec(TableAggSellThrough, domain.AggSellThrough{}, []string{"chain"}, "Precomputed monthly sell-through and closing stock (from the CPFR computation)."),
	}
}

// PlanAggregates builds one replace-by-tenant plan per materialized table.
func PlanAggregates(agg *domain.AnalyticsAggregates, now time.Time) []Plan {
	meta := Meta{TenantID: NormalizeTenant(agg.TenantID), BatchID: fmt.Sprintf("agg_v%d", agg.Version), SourceFile: "precomputed"}
	specs := AggregateSpecs()
	build := func(n int, at func(i int) (interface{}, string)) []map[string]interface{} {
		rows := make([]map[string]interface{}, 0, n)
		for i := 0; i < n; i++ {
			v, chain := at(i)
			row := RowFor(v)
			for k, mv := range metaRow(meta, now) {
				row[k] = mv
			}
			row[ColPartitionDate] = agg.UpdatedAt.UTC().Format("2006-01-02")
			row[ColChainKey] = chainKey(chain)
			rows = append(rows, row)
		}
		return rows
	}
	where := "tenant_id = @tenant_id"
	return []Plan{
		{Kind: KindAggregates, Meta: meta, Table: specs[0], DeleteWhere: where, Params: baseParams(meta),
			Rows: build(len(agg.ChainProfitMonthly), func(i int) (interface{}, string) { r := agg.ChainProfitMonthly[i]; return r, r.Chain })},
		{Kind: KindAggregates, Meta: meta, Table: specs[1], DeleteWhere: where, Params: baseParams(meta),
			Rows: build(len(agg.SkuCostMargin), func(i int) (interface{}, string) { r := agg.SkuCostMargin[i]; return r, r.Chain })},
		{Kind: KindAggregates, Meta: meta, Table: specs[2], DeleteWhere: where, Params: baseParams(meta),
			Rows: build(len(agg.SellThrough), func(i int) (interface{}, string) { r := agg.SellThrough[i]; return r, r.Chain })},
	}
}

// WriteAnalyticsAggregates replaces the tenant's rows in the three materialized tables.
func (s *BigQuerySink) WriteAnalyticsAggregates(ctx context.Context, agg *domain.AnalyticsAggregates) error {
	if agg == nil {
		return nil
	}
	var errs []string
	for _, plan := range PlanAggregates(agg, time.Now()) {
		if len(plan.Rows) == 0 {
			if err := s.ensureTable(ctx, plan.Table); err != nil {
				errs = append(errs, err.Error())
				continue
			}
			sql := fmt.Sprintf("DELETE FROM %s WHERE tenant_id = @tenant_id", s.ref(plan.Table.Name))
			if err := s.runQuery(ctx, sql, plan.Params); err != nil {
				errs = append(errs, plan.Table.Name+": "+err.Error())
			}
			continue
		}
		if res := s.run(ctx, plan, "materialize"); res.Failed() {
			errs = append(errs, plan.Table.Name+": "+res.Error)
		}
	}
	if len(errs) > 0 {
		return fmt.Errorf("%s", strings.Join(errs, "; "))
	}
	return nil
}
