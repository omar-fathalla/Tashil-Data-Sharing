package bqsink

import (
	"context"
	"strings"
	"testing"
	"time"

	"cloud.google.com/go/bigquery"

	"github.com/tashil/data-sharing/backend/internal/domain"
)

func field(s bigquery.Schema, name string) *bigquery.FieldSchema {
	for _, f := range s {
		if f.Name == name {
			return f
		}
	}
	return nil
}

func TestSchemaIncludesMetaAndDomainColumnsOnce(t *testing.T) {
	s := SchemaFor(domain.SellOutFact{})
	seen := map[string]int{}
	for _, f := range s {
		seen[f.Name]++
	}
	for _, name := range []string{ColTenantID, ColBatchID, ColSourceFile, ColIngestedAt, ColPartitionDate, "record_id", "net_revenue", "quantity_sold", "is_own_brand"} {
		if seen[name] != 1 {
			t.Fatalf("column %s appears %d times", name, seen[name])
		}
	}
	if f := field(s, "net_revenue"); f.Type != bigquery.FloatFieldType {
		t.Fatalf("net_revenue type %v", f.Type)
	}
	if f := field(s, ColPartitionDate); f.Type != bigquery.DateFieldType {
		t.Fatalf("partition_date type %v", f.Type)
	}
	pm := SchemaFor(domain.ProductMasterItem{})
	if f := field(pm, "active_chains"); f == nil || !f.Repeated {
		t.Fatalf("active_chains should be repeated string")
	}
	si := SchemaFor(domain.SellInRecord{})
	if f := field(si, ColIngestedAt); f.Type != bigquery.TimestampFieldType {
		t.Fatalf("ingested_at should be TIMESTAMP")
	}
}

func TestPlanSellOutReplacePeriods(t *testing.T) {
	now := time.Date(2026, 10, 24, 1, 0, 0, 0, time.UTC)
	facts := []domain.SellOutFact{
		{RecordID: "r1", RetailerChain: "Fathalla ", TransactionDate: "2026-09-30", NetRevenue: 10},
		{RecordID: "r2", RetailerChain: "fathalla", TransactionDate: "2026-09-15", NetRevenue: 5},
		{RecordID: "r3", RetailerChain: "gomla", TransactionDate: "2026-08-31", NetRevenue: 7},
	}
	p := PlanSellOut(Meta{TenantID: "adeco", BatchID: "b1", SourceFile: "f.xlsx"}, facts, ModeReplacePeriods, now)
	if p.Meta.TenantID != "tenant-adeco" || len(p.Rows) != 3 {
		t.Fatalf("bad plan meta/rows: %+v %d", p.Meta, len(p.Rows))
	}
	r := p.Rows[0]
	if r[ColChainKey] != "fathalla" || r[ColPeriodMonth] != "2026-09" || r[ColPartitionDate] != "2026-09-30" || r[ColTenantID] != "tenant-adeco" || r[ColBatchID] != "b1" {
		t.Fatalf("bad row meta: %+v", r)
	}
	var keys []string
	for _, q := range p.Params {
		if q.Name == "keys" {
			keys = q.Value.([]string)
		}
	}
	if strings.Join(keys, ",") != "fathalla|2026-09,gomla|2026-08" {
		t.Fatalf("unexpected keys %v", keys)
	}
	if !strings.Contains(p.DeleteWhere, "UNNEST(@keys)") {
		t.Fatalf("replace mode must delete by period keys: %s", p.DeleteWhere)
	}
	up := PlanSellOut(Meta{TenantID: "tenant-adeco", BatchID: "b1"}, facts, ModeUpsertRecords, now)
	if !strings.Contains(up.DeleteWhere, "record_id IN (SELECT record_id FROM {{staging}})") {
		t.Fatalf("upsert mode must delete by record_id: %s", up.DeleteWhere)
	}
}

func TestPlanSellInAndProductMaster(t *testing.T) {
	now := time.Date(2026, 10, 24, 1, 0, 0, 0, time.UTC)
	p := PlanSellIn(Meta{TenantID: "tenant-adeco", BatchID: "b2", SourceFile: "plan.xlsx"}, []domain.SellInRecord{
		{RecordID: "s1", RetailerChain: "", Year: 2026, MonthNum: 3},
	}, now)
	if p.Rows[0][ColPeriodMonth] != "2026-03" || p.Rows[0][ColPartitionDate] != "2026-03-01" || p.Rows[0][ColChainKey] != "fathalla" {
		t.Fatalf("bad sell-in row: %+v", p.Rows[0])
	}
	pm := PlanProductMaster(Meta{TenantID: "tenant-adeco", BatchID: "b3"}, &domain.ProductMasterSummaryResponse{
		SourceFilename: "pm.xlsx", Items: []domain.ProductMasterItem{{ItemCode: "FGCL-1", ActiveChains: []string{"fathalla"}}},
	}, now)
	if pm.Meta.SourceFile != "pm.xlsx" || pm.Rows[0][ColSourceFile] != "pm.xlsx" || pm.Rows[0][ColPartitionDate] != "2026-10-24" {
		t.Fatalf("bad pm plan: %+v", pm.Rows[0])
	}
	if got := pm.Rows[0]["active_chains"].([]string); len(got) != 1 {
		t.Fatalf("active_chains not carried")
	}
}

func TestBuildReplaceSQLIsSingleTransaction(t *testing.T) {
	spec := SellOutSpec()
	sql := BuildReplaceSQL("`p.d.sell_out_facts`", "`p.d._staging_x`", spec.Schema, "tenant_id = @tenant_id AND record_id IN (SELECT record_id FROM {{staging}})")
	if !strings.HasPrefix(sql, "BEGIN TRANSACTION;") || !strings.HasSuffix(sql, "COMMIT TRANSACTION;") {
		t.Fatalf("not a transaction: %s", sql)
	}
	if !strings.Contains(sql, "FROM `p.d._staging_x`)") || strings.Contains(sql, "{{staging}}") {
		t.Fatalf("staging placeholder not substituted: %s", sql)
	}
	if strings.Count(sql, "`tenant_id`") != 2 {
		t.Fatalf("column list should appear in INSERT and SELECT")
	}
}

func TestMissingColumnsAreNullable(t *testing.T) {
	have := bigquery.Schema{{Name: "tenant_id", Type: bigquery.StringFieldType}}
	want := bigquery.Schema{{Name: "tenant_id", Type: bigquery.StringFieldType}, {Name: "new_col", Type: bigquery.StringFieldType, Required: true}}
	m := MissingColumns(have, want)
	if len(m) != 1 || m[0].Name != "new_col" || m[0].Required {
		t.Fatalf("unexpected %+v", m)
	}
}

func TestConfigFromEnvDefaultsOff(t *testing.T) {
	t.Setenv("BIGQUERY_SINK_ENABLED", "")
	if ConfigFromEnv("p", "d").Enabled {
		t.Fatal("sink must default to disabled")
	}
	t.Setenv("BIGQUERY_SINK_ENABLED", "true")
	c := ConfigFromEnv("p", "d")
	if !c.Enabled || c.Location != "europe-west1" {
		t.Fatalf("unexpected %+v", c)
	}
	if New(context.Background(), Config{Enabled: false}).Enabled() {
		t.Fatal("disabled config must give Noop")
	}
	b := New(context.Background(), Config{Enabled: true})
	if r := b.WriteSellIn(context.Background(), Meta{}, nil); r.Status != StatusFailed {
		t.Fatalf("misconfigured sink must fail loudly, got %+v", r)
	}
}
