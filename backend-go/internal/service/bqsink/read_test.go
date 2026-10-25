package bqsink

import (
	"strings"
	"testing"
	"time"

	"cloud.google.com/go/bigquery"

	"github.com/tashil/data-sharing/backend/internal/domain"
)

// A row written by PlanSellIn and read back by DecodeSellInRow must round-trip every field.
func TestSellInRowRoundTrip(t *testing.T) {
	now := time.Date(2026, 10, 25, 12, 0, 0, 0, time.UTC)
	in := domain.SellInRecord{
		RecordID: "sellin_tenant-adeco_7", BatchID: "b1", SourceFilename: "plan.xlsx", TenantID: "tenant-adeco",
		RetailerChain: "fathalla", Year: 2026, MonthNum: 4, MonthAR: "أبريل", ItemCode: "FGCL-0550-0001",
		Barcode: "6223000236024", UnitsPerCarton: 12, ItemName: "كلوريل 500 جم", NetQtyCases: 10.5,
		NetValueEGP: 2540.34, OfficialListValueExclEGP: 2822.6, InvoiceDiscountPct: 10, VATRate: 0.14,
		PricingWaveStatus: "current_list", IngestedAt: now,
	}
	plan := PlanSellIn(Meta{TenantID: "adeco", BatchID: "b1", ArchiveID: "a1", SourceFile: "plan.xlsx"}, []domain.SellInRecord{in}, now)
	// Simulate what BigQuery returns: typed values for the same columns.
	row := map[string]bigquery.Value{}
	for k, v := range plan.Rows[0] {
		row[k] = v
	}
	row[ColIngestedAt] = now
	out, err := DecodeSellInRow(row)
	if err != nil {
		t.Fatal(err)
	}
	if out.RecordID != in.RecordID || out.TenantID != "tenant-adeco" || out.BatchID != "b1" || out.ItemName != in.ItemName ||
		out.NetValueEGP != in.NetValueEGP || out.NetQtyCases != in.NetQtyCases || out.UnitsPerCarton != 12 ||
		out.MonthNum != 4 || out.Barcode != in.Barcode || out.SourceFilename != "plan.xlsx" || !out.IngestedAt.Equal(now) ||
		out.OfficialListValueExclEGP != in.OfficialListValueExclEGP || out.PricingWaveStatus != "current_list" {
		t.Fatalf("round trip mismatch:\n in=%+v\nout=%+v", in, out)
	}
}

func TestSellInReadSQLFiltersTenantAndKeepsUploadOrder(t *testing.T) {
	sql := SellInReadSQL("`p.d.sell_in_records`")
	for _, want := range []string{"FROM `p.d.sell_in_records`", "tenant_id = @tenant_id", "ORDER BY ingested_at", "REGEXP_EXTRACT(record_id"} {
		if !strings.Contains(sql, want) {
			t.Fatalf("sql missing %q: %s", want, sql)
		}
	}
	if strings.Contains(sql, "``") {
		t.Fatalf("double back-quotes: %s", sql)
	}
}

func TestSellOutRowRoundTrip(t *testing.T) {
	now := time.Date(2026, 10, 25, 12, 0, 0, 0, time.UTC)
	in := domain.SellOutFact{RecordID: "fact_x", TenantID: "tenant-adeco", RetailerChain: "fathalla", StoreID: "s1", StoreName: "فرع 1",
		ItemCode: "FGCL-0550-0001", Barcode: "6223000236024", SKUName: "كلوريل", IsOwnBrand: true, UnitsPerCarton: 12,
		QuantitySold: 7, CartonsSold: 0.58, NetRevenue: 110.6, UnitPrice: 15.8, TransactionDate: "2026-03-14",
		IngestionBatchID: "batch_1", IngestedAt: now}
	plan := PlanSellOut(Meta{TenantID: "adeco", BatchID: "b9", SourceFile: "2026 out.xlsx"}, []domain.SellOutFact{in}, ModeReplacePeriods, now)
	row := map[string]bigquery.Value{}
	for k, v := range plan.Rows[0] {
		row[k] = v
	}
	row[ColIngestedAt] = now
	out, err := DecodeSellOutRow(row)
	if err != nil {
		t.Fatal(err)
	}
	if out != in {
		t.Fatalf("round trip mismatch:\n in=%+v\nout=%+v", in, out)
	}
}

func TestDeleteTenantIsAlwaysTenantScoped(t *testing.T) {
	sql := DeleteTenantSQL("`p.d.sell_out_facts`")
	if sql != "DELETE FROM `p.d.sell_out_facts` WHERE tenant_id = @tenant_id" {
		t.Fatalf("unexpected sql: %s", sql)
	}
	s := &BigQuerySink{}
	for _, tenant := range []string{"", "all", "*", " ALL "} {
		if res := s.DeleteTenant(nil, KindSellOut, tenant); res.Status != StatusSkipped {
			t.Fatalf("tenant %q must be refused, got %+v", tenant, res)
		}
	}
	if res := (Noop{}).DeleteTenant(nil, KindSellIn, "tenant-adeco"); res.Status != StatusDisabled {
		t.Fatalf("noop: %+v", res)
	}
}
