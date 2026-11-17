package ingestion

import (
	"bytes"
	"context"
	"path/filepath"
	"strings"
	"testing"

	"github.com/tashil/data-sharing/backend/internal/domain"
	"github.com/tashil/data-sharing/backend/internal/service/bigquery"
	"github.com/tashil/data-sharing/backend/internal/service/bqsink"
)

func soFact(id, chain, store, supplier string, own bool, cat string, qty int, rev float64) domain.SellOutFact {
	return domain.SellOutFact{
		RecordID: id, TenantID: "tenant-adeco", RetailerChain: chain, StoreID: store, Supplier: supplier,
		IsOwnBrand: own, Barcode: "622" + id, Category: cat, QuantitySold: qty, NetRevenue: rev,
		TransactionDate: "2026-03-01", IngestionBatchID: "batch_" + chain,
	}
}

func TestPlanSellOutCategoryRefreshChangesCategoryOnly(t *testing.T) {
	stored := []domain.SellOutFact{
		soFact("a", "fathalla", "fat_1", "", true, "كلور عادى", 10, 100),            // bleach colours merged under regular
		soFact("b", "fathalla", "fat_1", "", true, "منظفات وعناية منزلية", 5, 50.5), // dish soap left on PM category
		soFact("c", "fathalla", "fat_2", "Clorox", false, "كلور ارضيات", 3, 30),     // competitor already right
		soFact("d", "kazyon", "kaz_1", "", true, "كلور عادى", 7, 70),                // no archived twin
		{RecordID: "x", TenantID: "tenant-other", RetailerChain: "fathalla", Category: "old", QuantitySold: 1, NetRevenue: 1},
	}
	replay := []domain.SellOutFact{
		soFact("a", "fathalla", "fat_1", "", true, "كلور ألوان", 10, 100),
		soFact("b", "fathalla", "fat_1", "", true, "سائل اطباق", 5, 50.5),
		soFact("c", "fathalla", "fat_2", "Clorox", false, "كلور ارضيات", 3, 30),
		soFact("e", "fathalla", "fat_3", "", true, "سائل اطباق", 2, 20), // not in BigQuery: never added
		{RecordID: "x", TenantID: "tenant-other", RetailerChain: "fathalla", Category: "new", QuantitySold: 1, NetRevenue: 1},
	}
	p := PlanSellOutCategoryRefresh("tenant-adeco", stored, replay)

	if p.StoredRows != 4 || p.ReplayRows != 4 || p.Matched != 3 || p.Unchanged != 1 || p.OnlyStored != 1 || p.OnlyReplay != 1 {
		t.Fatalf("counts: %+v", p)
	}
	if len(p.Changes) != 2 || p.Changes[0].RecordID != "a" || p.Changes[0].NewCategory != "كلور ألوان" ||
		p.Changes[1].RecordID != "b" || p.Changes[1].NewCategory != "سائل اطباق" || p.Changes[1].BatchID != "batch_fathalla" {
		t.Fatalf("changes: %+v", p.Changes)
	}
	if p.AfterRows != p.StoredRows || p.AfterQuantity != 25 || p.BeforeQuantity != 25 || p.AfterRevenue != p.BeforeRevenue {
		t.Fatalf("totals must be identical: %+v", p)
	}
	if v := p.Violations(); len(v) != 0 {
		t.Fatalf("violations: %v", v)
	}
	after := map[string]float64{}
	for _, tt := range p.After {
		after[tt.Chain+"|"+tt.Category] += tt.NetRevenue
	}
	if after["fathalla|كلور عادى"] != 0 || after["fathalla|كلور ألوان"] != 100 || after["kazyon|كلور عادى"] != 70 {
		t.Fatalf("after totals: %v", after)
	}
}

func TestPlanSellOutCategoryRefreshBlocksIdentityOrMeasureDrift(t *testing.T) {
	stored := []domain.SellOutFact{
		soFact("q", "fathalla", "fat_1", "", true, "old", 10, 100),
		soFact("r", "fathalla", "fat_1", "", true, "old", 10, 100),
		soFact("s", "fathalla", "fat_1", "", true, "old", 10, 100),
		soFact("t", "fathalla", "fat_1", "", true, "old", 10, 100),
		soFact("u", "fathalla", "fat_1", "", true, "old", 10, 100),
		soFact("u", "fathalla", "fat_1", "", true, "old", 10, 100),
		soFact("v", "fathalla", "fat_1", "", true, "old", 10, 100),
	}
	replay := []domain.SellOutFact{
		soFact("q", "fathalla", "fat_1", "", true, "new", 11, 100),   // quantity differs
		soFact("r", "fathalla", "fat_1", "", true, "new", 10, 100.5), // revenue differs
		soFact("s", "kazyon", "fat_1", "", true, "new", 10, 100),     // other chain: no cross-customer move
		soFact("t", "fathalla", "fat_9", "", true, "new", 10, 100),   // other store
		soFact("u", "fathalla", "fat_1", "", true, "new", 10, 100),   // duplicated in BigQuery
		soFact("v", "fathalla", "fat_1", "", true, "", 10, 100),      // empty sheet category
	}
	p := PlanSellOutCategoryRefresh("tenant-adeco", stored, replay)
	if len(p.Changes) != 0 {
		t.Fatalf("no row may change: %+v", p.Changes)
	}
	if len(p.Blocked) != 7 {
		t.Fatalf("blocked: %+v", p.Blocked)
	}
	if v := p.Violations(); len(v) != 0 {
		t.Fatalf("violations: %v", v)
	}
	out := FormatSellOutCategoryRefreshPlan(p, nil, nil)
	for _, want := range []string{"quantity", "net revenue", "chain", "store", "record_id not unique", "re-parsed category is empty", "RESULT: SAFE"} {
		if !strings.Contains(out, want) {
			t.Fatalf("report missing %q:\n%s", want, out)
		}
	}
}

func TestSellOutCategoryRefreshViolations(t *testing.T) {
	p := &SellOutCategoryRefreshPlan{StoredRows: 2, AfterRows: 1, BeforeQuantity: 3, AfterQuantity: 4, BeforeRevenue: 1, AfterRevenue: 2,
		Changes: []SellOutCategoryChange{{RecordID: "a", OldCategory: "x", NewCategory: "x"}, {RecordID: "b", OldCategory: "x", NewCategory: "y"}},
		Blocked: []SellOutCategoryBlock{{RecordID: "b"}}}
	if v := p.Violations(); len(v) != 5 {
		t.Fatalf("want 5 violations, got %v", v)
	}
	if !strings.Contains(FormatSellOutCategoryRefreshPlan(p, nil, nil), "RESULT: UNSAFE") {
		t.Fatal("unsafe plan must say so")
	}
}

func TestReconcileExpectedNormalizesSpelling(t *testing.T) {
	stored := []domain.SellOutFact{
		soFact("a", "fathalla", "fat_1", "", true, "منظفات وعناية منزلية", 1, 34.42),
		soFact("b", "fathalla", "fat_1", "Fairy", false, "سائل اطباق", 1, 5),
	}
	replay := []domain.SellOutFact{
		soFact("a", "fathalla", "fat_1", "", true, "سائل أطباق", 1, 34.42),
		soFact("b", "fathalla", "fat_1", "Fairy", false, "سائل اطباق", 1, 5),
	}
	exp, err := ParseExpectedCategoryCSV(strings.NewReader("chain,category,scope,net_revenue\nfathalla,سائل اطباق,own,\"34.42\"\n*,سائل أطباق,all,39.42\n"))
	if err != nil || len(exp) != 2 {
		t.Fatalf("parse: %v %+v", err, exp)
	}
	rec := ReconcileExpected(PlanSellOutCategoryRefresh("tenant-adeco", stored, replay), exp)
	if rec[0].Before != 0 || rec[0].After != 34.42 || rec[0].Delta() != 0 {
		t.Fatalf("own: %+v", rec[0])
	}
	if rec[1].Before != 5 || rec[1].After != 39.42 {
		t.Fatalf("all chains: %+v", rec[1])
	}
	if _, err := ParseExpectedCategoryCSV(strings.NewReader("fathalla,x,mine,1\n")); err == nil {
		t.Fatal("bad scope must fail")
	}
}

func TestSellOutCategoryMappingCSVAndSQL(t *testing.T) {
	p := &SellOutCategoryRefreshPlan{Changes: []SellOutCategoryChange{{RecordID: "fact_1", BatchID: "b1", OldCategory: "كلور عادى", NewCategory: "كلور ألوان", NetRevenue: 99}}}
	var buf bytes.Buffer
	if err := WriteSellOutCategoryMappingCSV(&buf, p); err != nil {
		t.Fatal(err)
	}
	if got := buf.String(); got != "record_id,ingestion_batch_id,old_category,new_category\nfact_1,b1,كلور عادى,كلور ألوان\n" {
		t.Fatalf("csv: %q", got)
	}
	up := SellOutCategoryUpdateSQL("`p.d.sell_out_facts`", "`p.d.m`")
	for _, want := range []string{"SET category = m.new_category", "t.tenant_id = @tenant_id", "t.record_id = m.record_id",
		"IFNULL(t.ingestion_batch_id, '') = m.ingestion_batch_id", "IFNULL(t.category, '') = m.old_category"} {
		if !strings.Contains(up, want) {
			t.Fatalf("update SQL missing %q: %s", want, up)
		}
	}
	for _, col := range []string{"quantity_sold", "net_revenue", "retailer_chain", "store_id", "record_id ="} {
		if strings.Contains(up, "SET "+col) || strings.Contains(up, ", "+col+" =") {
			t.Fatalf("update SQL must only set category: %s", up)
		}
	}
	rb := SellOutCategoryRollbackSQL("`p.d.sell_out_facts`", "`p.d.m`")
	if !strings.Contains(rb, "SET category = m.old_category") || !strings.Contains(rb, "IFNULL(t.category, '') = m.new_category") {
		t.Fatalf("rollback SQL: %s", rb)
	}
}

// End to end: a stored row set with stale Product Master categories is planned back to the sheet
// «المجموعة» values from the archived file, and the replay writes nothing to the sink.
func TestReplaySellOutArchivesForCategoryPlanIsReadOnly(t *testing.T) {
	t.Setenv("TASHIL_PRODUCT_MASTER_DIR", filepath.Join(t.TempDir(), "pm"))
	ctx := context.Background()
	dir := t.TempDir()
	const tenant = "tenant-catplan"
	sheet := []byte("المجموعة,المورد,الباركود,الصنف,سموحة,ستانلى,الاجمالى,MONTH,كمية سموحة,كمية ستانلى,اجمالى كميات,YEAR\n" +
		"كلور الوان,ادكو (1),6223001111001,ألوان,10000,0,10000,JAN,10,0,10,2026\n" +
		"كلور عادي,ادكو (1),6223001111002,عادى,4000,0,4000,JAN,4,0,4,2026\n" +
		"صابون سائل اطباق,ادكو (1),6223001111006,اطباق,5000,0,5000,JAN,5,0,5,2026\n" +
		"كلور الوان,هنكل,6223001111005,منافس ألوان,3000,0,3000,JAN,3,0,3,2026\n")

	up := newTestProcessor(t, dir)
	_ = up.ClearTenantData(ctx, tenant)
	if _, err := up.ProcessUpload(ctx, tenant, "out26-fathalla.csv", sheet, "fathalla"); err != nil {
		t.Fatalf("upload: %v", err)
	}
	stored := up.bqRepo.(*bigquery.Client).SellOutFactsSnapshot(tenant)
	if len(stored) == 0 {
		t.Fatal("no stored facts")
	}
	var archiveID string
	for _, f := range up.ListArchivedFiles(ctx, tenant, "", "", "").Files {
		archiveID = f.ID
	}
	// What BigQuery holds today: own-brand rows on the old Product Master grouping.
	for i := range stored {
		if stored[i].IsOwnBrand {
			stored[i].Category = "كلور عادى"
			if stored[i].Barcode == "6223001111006" {
				stored[i].Category = "منظفات وعناية منزلية"
			}
		}
	}

	sink := &fakeSink{}
	rp := newTestProcessor(t, dir).WithSink(sink)
	_ = rp.ClearTenantData(ctx, "all") // a tenant-scoped clear would also delete the archive

	files := rp.ReplaySellOutArchivesForCategoryPlan(ctx, tenant, []bqsink.ArchiveRows{{Kind: bqsink.KindSellOut, ArchiveID: archiveID, Rows: len(stored)}})
	if len(files) != 1 {
		t.Fatalf("replayed %d files (archive id %q)", len(files), archiveID)
	}
	if len(sink.sellOut) != 0 || len(sink.deletes) != 0 {
		t.Fatalf("replay must not write: writes=%d deletes=%d", len(sink.sellOut), len(sink.deletes))
	}
	plan := PlanSellOutCategoryRefresh(tenant, stored, rp.bqRepo.(*bigquery.Client).SellOutFactsSnapshot(tenant))
	if v := plan.Violations(); len(v) != 0 {
		t.Fatalf("violations: %v", v)
	}
	if len(plan.Changes) != 2 {
		t.Fatalf("changes: %+v", plan.Changes)
	}
	want := map[string]bool{"كلور عادى->كلور ألوان": true, "منظفات وعناية منزلية->صابون سائل اطباق": true}
	for _, c := range plan.Changes {
		if !want[c.OldCategory+"->"+c.NewCategory] {
			t.Fatalf("unexpected change %+v", c)
		}
	}
	if plan.Unchanged != 2 || plan.BeforeRevenue != plan.AfterRevenue || plan.BeforeQuantity != plan.AfterQuantity {
		t.Fatalf("plan: %+v", plan)
	}
}

func TestSelectSellOutArchivesForCategoryReplay(t *testing.T) {
	all := []*ArchivedFile{
		{ID: "pm", TenantID: "tenant-adeco", FileType: "product_master", FileName: "adeco_product_master.xlsx", UploadedAt: "1"},
		{ID: "out26", TenantID: "tenant-adeco", FileType: "sell_out", FileName: "2026 out.xlsx", UploadedAt: "3"},
		{ID: "out25", TenantID: "tenant-adeco", FileType: "sell_out", FileName: "2025 out.xlsx", UploadedAt: "2"},
		{ID: "deleted", TenantID: "tenant-adeco", FileType: "sell_out", FileName: "Book3.xlsx", UploadedAt: "4"},
		{ID: "in", TenantID: "tenant-adeco", FileType: "sell_in", FileName: "in26.xlsx", UploadedAt: "5"},
		{ID: "other", TenantID: "tenant-other", FileType: "sell_out", FileName: "2026 out.xlsx", UploadedAt: "6"},
	}
	stored := []bqsink.ArchiveRows{
		{Kind: bqsink.KindSellOut, ArchiveID: "out26", Rows: 80000},
		{Kind: bqsink.KindSellOut, SourceFile: "2025 OUT.xlsx", Rows: 29000},
		{Kind: bqsink.KindSellIn, ArchiveID: "in", Rows: 10},
	}
	got := SelectSellOutArchivesForCategoryReplay(all, "tenant-adeco", stored)
	var ids []string
	for _, e := range got {
		ids = append(ids, e.ID)
	}
	if strings.Join(ids, ",") != "pm,out25,out26" {
		t.Fatalf("selected %v", ids)
	}
}
