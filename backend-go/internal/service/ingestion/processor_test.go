package ingestion

import (
	"context"
	"os"
	"path/filepath"
	"testing"

	"github.com/tashil/data-sharing/backend/internal/service/bigquery"
	"github.com/tashil/data-sharing/backend/internal/service/firestore"
	"github.com/tashil/data-sharing/backend/internal/service/gemini"
)

func TestProcessorUploadCarrefourFile(t *testing.T) {
	ctx := context.Background()
	agent := gemini.NewAgent("", "gemini-3.8-flash", true)
	bqRepo := bigquery.NewClient("test-proj", "test-dataset", true)
	fsRepo := firestore.NewClient("test-db", true)

	processor := NewProcessor(agent, bqRepo, fsRepo)

	fileContent := []byte("Header1,Header2\nSample1,Sample2\n")
	// Invented mock samples require staged human approval before durable write.
	staged, err := processor.ProcessUploadWithDryRun(ctx, "tenant-adeco", "carrefour_weekly.csv", fileContent, true)
	if err != nil {
		t.Fatalf("ProcessUpload preview failed: %v", err)
	}
	res, err := processor.CommitStagedUpload(ctx, "tenant-adeco", staged.BatchID, "")
	if err != nil {
		t.Fatalf("ProcessUpload commit failed: %v", err)
	}

	if res.RetailerDetected != "carrefour" {
		t.Errorf("expected retailer 'carrefour', got '%s'", res.RetailerDetected)
	}

	if res.ValidRows == 0 {
		t.Errorf("expected valid rows > 0, got 0")
	}

	if res.TotalRevenue <= 0 {
		t.Errorf("expected total revenue > 0, got %f", res.TotalRevenue)
	}

	// Verify persistence in Firestore
	batches, err := fsRepo.ListIngestionBatches(ctx, "tenant-adeco")
	if err != nil {
		t.Fatalf("failed to list batches: %v", err)
	}
	if len(batches) == 0 {
		t.Errorf("expected batch saved in firestore")
	}

	// Verify sample records have inferred category
	if len(res.SampleRecords) > 0 {
		for _, rec := range res.SampleRecords {
			if rec.Barcode == "" {
				t.Errorf("expected barcode to be populated")
			}
		}
	}
}

func TestProcessorExcludesAnomaliesAndDeduplicatesBigQueryFacts(t *testing.T) {
	ctx := context.Background()
	agent := gemini.NewAgent("", "gemini-3.8-flash", true)
	bqRepo := bigquery.NewClient("test-proj", "test-dataset", true)
	fsRepo := firestore.NewClient("test-db", true)

	processor := NewProcessor(agent, bqRepo, fsRepo)

	// Upload for an isolated tenant so we can inspect exact persisted BigQuery records
	tenantID := "tenant-unknown-clean-test"
	csvContent := []byte(
		"Store_Code_Branch,Barcode,Item_Description,Category,Sales_Units,Net_Val_EGP,Transaction_Date\n" +
			"Carrefour Maadi City Center,6221155001234,Adeco Olive Oil 500ml,زيوت طعام,100,25000.0,2026-03-07\n" +
			"Carrefour Dandy Mall,6221155001241,Adeco Sunflower Oil 1L,زيوت طعام,50,5500.0,2026-03-07\n" +
			"Carrefour City Stars,6221155001258,Adeco Corn Oil Returned,زيوت طعام,-10,-1200.0,2026-03-07\n" +
			"Carrefour Maadi City Center,1234,Short Barcode Defect Item,زيوت طعام,20,2000.0,2026-03-07\n",
	)

	res, err := processor.ProcessUpload(ctx, tenantID, "carrefour_march_upload.csv", csvContent)
	if err != nil {
		t.Fatalf("ProcessUpload failed: %v", err)
	}

	if res.ValidRows != 2 {
		t.Errorf("expected 2 valid rows (excluding 2 anomalies), got %d", res.ValidRows)
	}
	if res.AnomalyRows != 2 {
		t.Errorf("expected 2 anomaly rows, got %d", res.AnomalyRows)
	}
	if res.TotalRows != 4 {
		t.Errorf("expected TotalRows = ValidRows(2) + AnomalyRows(2) = 4, got %d", res.TotalRows)
	}
	if res.TotalRevenue != 30500.0 {
		t.Errorf("expected TotalRevenue 30500.0 (excluding anomalous rows), got %f", res.TotalRevenue)
	}
	if res.TotalQuantity != 150 {
		t.Errorf("expected TotalQuantity 150 (excluding anomalous rows), got %d", res.TotalQuantity)
	}
	if len(res.SampleRecords) != 2 {
		t.Errorf("expected SampleRecords to contain only the 2 valid records, got %d", len(res.SampleRecords))
	}

	// Verify BigQuery only persisted the 2 valid records and NOT the anomalous rows
	persisted, total, err := bqRepo.GetSellOutRecords(ctx, tenantID, bigquery.RecordFilter{Limit: 50})
	if err != nil {
		t.Fatalf("GetSellOutRecords failed: %v", err)
	}
	if total != 2 || len(persisted) != 2 {
		t.Fatalf("expected exactly 2 valid records in BigQuery, got %d", total)
	}
	for _, r := range persisted {
		if r.QuantitySold <= 0 || r.NetRevenue < 0 || len(r.Barcode) < 8 {
			t.Errorf("anomalous record leaked into BigQuery: %+v", r)
		}
	}

	// Re-upload the exact same file and verify BigQuery deduplicates by deterministic RecordID
	_, err = processor.ProcessUpload(ctx, tenantID, "carrefour_march_upload.csv", csvContent)
	if err != nil {
		t.Fatalf("second ProcessUpload failed: %v", err)
	}
	_, totalAfterReupload, err := bqRepo.GetSellOutRecords(ctx, tenantID, bigquery.RecordFilter{Limit: 50})
	if err != nil {
		t.Fatalf("GetSellOutRecords after re-upload failed: %v", err)
	}
	if totalAfterReupload != 2 {
		t.Errorf("expected BigQuery record count to remain 2 after re-upload, got %d", totalAfterReupload)
	}
}

func TestClearTenantDataAndWideMatrixExcelIngestion(t *testing.T) {
	ctx := context.Background()
	agent := gemini.NewAgent("", "gemini-3.8-flash", true)
	bqRepo := bigquery.NewClient("test-proj", "test-dataset", true)
	fsRepo := firestore.NewClient("test-db", true)

	processor := NewProcessor(agent, bqRepo, fsRepo)

	// 1. Wipe all fake/seeded data for tenant-adeco
	if err := processor.ClearTenantData(ctx, "tenant-adeco"); err != nil {
		t.Fatalf("ClearTenantData failed: %v", err)
	}

	storesAfterClear, err := fsRepo.GetStoresByTenant(ctx, "tenant-adeco")
	if err != nil {
		t.Fatalf("GetStoresByTenant failed: %v", err)
	}
	if len(storesAfterClear) != 0 {
		t.Errorf("expected 0 stores after ClearTenantData, got %d", len(storesAfterClear))
	}

	kpisAfterClear, err := bqRepo.GetExecutiveKPIs(ctx, "tenant-adeco", "MTD")
	if err != nil {
		t.Fatalf("GetExecutiveKPIs after clear failed: %v", err)
	}
	if kpisAfterClear.TotalRevenue != 0 || kpisAfterClear.ActiveStoresCount != 0 {
		t.Errorf("expected 0 revenue and 0 active stores after ClearTenantData, got rev=%f, stores=%d", kpisAfterClear.TotalRevenue, kpisAfterClear.ActiveStoresCount)
	}

	// 2. Ingest a Wide Branch-Pivot Matrix CSV with new branches (سموحة, جاردينيا, نهال فيل, فرع العلمين الجديدة),
	// competing suppliers (ادكو (1) vs ارما التجارية vs بروكتر و جامبل), and quantities
	wideMatrixCSV := []byte(
		"المجموعة,المورد,الباركود,الصنف,سموحة,جاردينيا,نهال فيل,فرع العلمين الجديدة,الاجمالى,,كمية سموحة,كمية جاردينيا,كمية نهال فيل,كمية فرع العلمين الجديدة\n" +
			"صابون سائل اطباق,ادكو (1),6221133002532,بريل صابون سائل اطباق ليمون 2.5 لتر,55000,33000,22000,11000,121000,,500,300,200,100\n" +
			"صابون سائل اطباق,ارما التجارية,6223001362708,أوكسي سائل أطباق ليمون 3 كجم,40000,20000,10000,10000,80000,,400,200,100,100\n" +
			"منعمات ملابس,ادكو (1),6221133090263,فلفيتا منعم أقمشة مركز ندى الربيع 1 لتر,30000,15000,0,15000,60000,,300,150,0,150\n" +
			"منعمات ملابس,بروكتر و جامبل,8006540900111,داوني منعم أقمشة مركز 1 لتر,20000,10000,5000,4000,39000,,200,100,50,40\n",
	)

	res, err := processor.ProcessUpload(ctx, "tenant-adeco", "40-Adco -2026.csv", wideMatrixCSV)
	if err != nil {
		t.Fatalf("ProcessUpload wide matrix failed: %v", err)
	}

	if res.AutoCreatedStoresCount != 4 {
		t.Errorf("expected 4 auto-created branches, got %d", res.AutoCreatedStoresCount)
	}
	if res.CompetitorsDetected != 2 {
		t.Errorf("expected 2 competing suppliers detected, got %d", res.CompetitorsDetected)
	}
	// Adco revenue = 121,000 + 60,000 = 181,000 out of total market 300,000 => 60.33%
	if res.TotalRevenue != 181000.0 {
		t.Errorf("expected Adco TotalRevenue 181000.0, got %f", res.TotalRevenue)
	}
	if res.TenantMarketSharePct < 60.0 || res.TenantMarketSharePct > 60.5 {
		t.Errorf("expected TenantMarketSharePct ~60.33%%, got %f", res.TenantMarketSharePct)
	}

	// Verify Firestore auto-created the 4 branches including the new branch "فرع العلمين الجديدة"
	storesAfterIngest, err := fsRepo.GetStoresByTenant(ctx, "tenant-adeco")
	if err != nil {
		t.Fatalf("GetStoresByTenant after ingest failed: %v", err)
	}
	if len(storesAfterIngest) != 4 {
		t.Errorf("expected 4 stores in Firestore after wide matrix ingest, got %d", len(storesAfterIngest))
	}

	// Verify Executive KPIs include Market Share, Competing Suppliers, and Category Market Share
	kpis, err := bqRepo.GetExecutiveKPIs(ctx, "tenant-adeco", "MTD")
	if err != nil {
		t.Fatalf("GetExecutiveKPIs failed: %v", err)
	}
	if kpis.TotalRevenue != 181000.0 {
		t.Errorf("expected ExecutiveKPIs TotalRevenue 181000.0, got %f", kpis.TotalRevenue)
	}
	if kpis.TotalMarketRevenue != 300000.0 {
		t.Errorf("expected TotalMarketRevenue 300000.0, got %f", kpis.TotalMarketRevenue)
	}
	if len(kpis.SupplierShares) != 3 {
		t.Errorf("expected 3 suppliers in SupplierShares, got %d", len(kpis.SupplierShares))
	}
	if len(kpis.CategoryContributions) != 2 {
		t.Errorf("expected 2 categories in CategoryContributions, got %d", len(kpis.CategoryContributions))
	}

	// Verify unit price inference (55000 / 500 = 110.0 EGP)
	records, _, err := bqRepo.GetSellOutRecords(ctx, "tenant-adeco", bigquery.RecordFilter{Limit: 20})
	if err != nil {
		t.Fatalf("GetSellOutRecords failed: %v", err)
	}
	foundPril := false
	for _, r := range records {
		if r.Barcode == "6221133002532" && r.UnitPrice == 110.0 {
			foundPril = true
		}
		if !r.IsOwnBrand {
			t.Errorf("expected default GetSellOutRecords to return only own brand records, got supplier=%s", r.Supplier)
		}
	}
	if !foundPril {
		t.Errorf("expected inferred UnitPrice=110.0 for barcode 6221133002532")
	}
}

// Regression: wide-matrix row-total gap (الاجمالى − Σ branches) must persist under
// غير موزع على فرع (qty 0, revenue ≠ 0) so BQ / KPI totals match the file. Named
// branches with qty≤0 stay dropped by the anomaly gate.
func TestProcessorPersistsUnallocatedWideMatrixGap(t *testing.T) {
	ctx := context.Background()
	agent := gemini.NewAgent("", "gemini-3.8-flash", true)
	bqRepo := bigquery.NewClient("test-proj", "test-dataset", true)
	fsRepo := firestore.NewClient("test-db", true)
	processor := NewProcessor(agent, bqRepo, fsRepo)

	tenantID := "tenant-adeco-unalloc-persist"
	if err := processor.ClearTenantData(ctx, tenantID); err != nil {
		t.Fatalf("ClearTenantData: %v", err)
	}

	// Row 1: branches 100+50=150, الاجمالى 200 → unallocated +50 (qty 0)
	// Row 2: branches 80+40=120, الاجمالى 100 → unallocated -20 (qty 0)
	// Row 3: balanced named branches (no gap) — control
	// Row 4: named value-only (qty 0, rev 25) must still be anomaly-dropped; no gap vs الاجمالى
	wideCSV := []byte(
		"المجموعة,المورد,الباركود,الصنف,سموحة,ستانلى,الاجمالى,MONTH,كمية سموحة,كمية ستانلى,اجمالى كميات,YEAR\n" +
			"منعمات,ادكو (1),6223000233701,منتج أ,100,50,200,JAN,10,5,15,2026\n" +
			"منعمات,ادكو (1),6223000233702,منتج ب,80,40,100,FEB,8,4,12,2026\n" +
			"منعمات,ادكو (1),6223000233703,منتج ج,60,40,100,MAR,6,4,10,2026\n" +
			"منعمات,ادكو (1),6223000233704,منتج د,25,0,25,APR,0,0,0,2026\n",
	)

	// Gap recon flags validation → durable write requires staged preview + human commit.
	staged, err := processor.ProcessUploadWithDryRun(ctx, tenantID, "wide-unalloc-gap.csv", wideCSV, true, "fathalla")
	if err != nil {
		t.Fatalf("ProcessUploadWithDryRun: %v", err)
	}
	res, err := processor.CommitStagedUpload(ctx, tenantID, staged.BatchID, "fathalla")
	if err != nil {
		t.Fatalf("CommitStagedUpload: %v", err)
	}

	// Parser SupplierShares includes all observations (incl. value-only named + unallocated).
	const wantParseTotal = 425.0 // 200+100+100+25
	if res.TotalRevenue != wantParseTotal {
		t.Errorf("upload TotalRevenue %.2f want %.2f (parser/file الاجمالى)", res.TotalRevenue, wantParseTotal)
	}

	persisted, total, err := bqRepo.GetSellOutRecords(ctx, tenantID, bigquery.RecordFilter{Limit: 50})
	if err != nil {
		t.Fatalf("GetSellOutRecords: %v", err)
	}

	var unallocCount int
	var unallocSum float64
	var namedZeroQtyLeak bool
	var bqOwnSum float64
	for _, r := range persisted {
		bqOwnSum += r.NetRevenue
		if gemini.IsUnallocatedBranchName(r.StoreName) {
			unallocCount++
			unallocSum += r.NetRevenue
			if r.QuantitySold != 0 {
				t.Errorf("unallocated fact should keep qty 0, got %d: %+v", r.QuantitySold, r)
			}
		}
		if r.Barcode == "6223000233704" {
			namedZeroQtyLeak = true
		}
	}
	if unallocCount != 2 {
		t.Fatalf("expected 2 persisted unallocated facts (+50 and -20), got %d (total facts=%d)", unallocCount, total)
	}
	if unallocSum != 30.0 { // +50 -20
		t.Errorf("unallocated sum %.2f want 30", unallocSum)
	}
	if namedZeroQtyLeak {
		t.Errorf("named-branch qty=0 value-only row must stay anomaly-dropped")
	}
	// Named with qty>0: 150+120+100=370; unallocated 30; value-only 25 dropped → BQ 400
	const wantBQTotal = 400.0
	if bqOwnSum != wantBQTotal {
		t.Errorf("BQ own-brand sum %.2f want %.2f (gap rows persisted; named qty0 still dropped)", bqOwnSum, wantBQTotal)
	}

	kpis, err := bqRepo.GetExecutiveKPIs(ctx, tenantID, "CUSTOM", "2026-01-01", "2026-12-31")
	if err != nil {
		t.Fatalf("GetExecutiveKPIs: %v", err)
	}
	if kpis.TotalRevenue != wantBQTotal {
		t.Errorf("KPI TotalRevenue %.2f want %.2f (persisted facts incl. unallocated)", kpis.TotalRevenue, wantBQTotal)
	}

	// Gap-only subset (rows 1–3): file الاجمالى 400 == BQ after persist.
	gapOnlyFileTotal := 400.0
	if bqOwnSum != gapOnlyFileTotal {
		t.Errorf("gap-only file total %.2f should equal BQ after unallocated persist", gapOnlyFileTotal)
	}

	sawUnallocBranch := false
	for _, st := range res.DiscoveredBranches {
		if gemini.IsUnallocatedBranchName(st.BranchName) {
			sawUnallocBranch = true
		}
	}
	if !sawUnallocBranch {
		t.Errorf("discoveredBranches should still list %s", gemini.UnallocatedBranchName)
	}
}

func TestProcessorGomlaUploadWithGomlaTargetDoesNotTriggerMismatch(t *testing.T) {
	ctx := context.Background()
	agent := gemini.NewAgent("", "gemini-3.8-flash", true)
	bqRepo := bigquery.NewClient("test-proj", "test-dataset", true)
	fsRepo := firestore.NewClient("test-db", true)

	processor := NewProcessor(agent, bqRepo, fsRepo)

	csvContent := []byte(
		"الباركود,إسم الصنف,إسم الفرع,الكمية المباعة,صافي المبيعات\n" +
			"6221155001234,Adeco Extra Virgin Olive Oil 500ml,فرع جملة ماركت - الكوثر - شارع المطار,10,2500\n" +
			"6221155001241,Adeco Pure Sunflower Oil 1L,فرع جملة ماركت - جسر السويس,15,1800\n",
	)

	// User selected "gomla" and staged upload
	res, err := processor.ProcessUploadWithDryRun(ctx, "tenant-adeco", "Daily_Sales_2026.csv", csvContent, true, "gomla")
	if err != nil {
		t.Fatalf("ProcessUploadWithDryRun failed: %v", err)
	}


	if res.ChainMismatchDetected {
		t.Errorf("expected ChainMismatchDetected to be false, got true (suggested: %s)", res.SuggestedChain)
	}

	if res.RetailerDetected != "gomla" {
		t.Errorf("expected RetailerDetected to be 'gomla', got '%s'", res.RetailerDetected)
	}

	if res.SuggestedChain != "" {
		t.Errorf("expected empty SuggestedChain, got '%s'", res.SuggestedChain)
	}
}

func TestMultiChainFathallaAndGomlaYearFilteringAndMonthlyTrends(t *testing.T) {
	ctx := context.Background()
	agent := gemini.NewAgent("", "gemini-3.8-flash", true)
	bqRepo := bigquery.NewClient("test-proj", "test-dataset", true)
	fsRepo := firestore.NewClient("test-db", true)
	processor := NewProcessor(agent, bqRepo, fsRepo)

	if err := processor.ClearTenantData(ctx, "tenant-adeco"); err != nil {
		t.Fatalf("ClearTenantData failed: %v", err)
	}

	// Simulate Gomla Market workbook with Year + Month columns (2025 يناير)
	gomlaCSV := []byte(
		"السنة,الشهر,المورد,الفئة,الباركود,إسم الصنف,الوحدة,إسم الفرع,صافى كمية المبيعات,صافى قيمة المبيعات\n" +
			"2025,يناير,ادكو / 318,منظفات سائلة,6221133002532,بريل صابون سائل 2.5 لتر,قطعة,الهرم (سهل حمزة),100,12000\n" +
			"2025,يناير,ادكو / 318,منعمات أقمشة,6221133090263,فلفيتا منعم 1 لتر,قطعة,الكوثر-شارع المطار,80,8000\n",
	)
	gomlaRes, err := processor.ProcessUpload(ctx, "tenant-adeco", "Book1 (2).csv", gomlaCSV, "gomla")
	if err != nil {
		t.Fatalf("Gomla ProcessUpload failed: %v", err)
	}
	if gomlaRes.RetailerDetected != "gomla" {
		t.Fatalf("expected gomla retailer, got %s", gomlaRes.RetailerDetected)
	}
	if gomlaRes.TotalRevenue != 20000.0 {
		t.Fatalf("expected gomla revenue 20000.0, got %.2f", gomlaRes.TotalRevenue)
	}

	// Simulate Fathalla wide matrix CSV (2026) and verify it does NOT wipe Gomla's 2025 data
	fathallaCSV := []byte(
		"المجموعة,المورد,الباركود,الصنف,سموحة,جاردينيا,نهال فيل,فرع العلمين الجديدة,الاجمالى,,كمية سموحة,كمية جاردينيا,كمية نهال فيل,كمية فرع العلمين الجديدة\n" +
			"صابون سائل اطباق,ادكو (1),6221133002532,بريل صابون سائل اطباق ليمون 2.5 لتر,55000,33000,22000,11000,121000,,500,300,200,100\n",
	)
	_, err = processor.ProcessUpload(ctx, "tenant-adeco", "40-Adco -2026.csv", fathallaCSV, "fathalla")
	if err != nil {
		t.Fatalf("Fathalla ProcessUpload failed: %v", err)
	}

	// 1. Query 2025 only -> should only return Gomla (20,000 EGP)
	kpis2025, err := bqRepo.GetExecutiveKPIs(ctx, "tenant-adeco", "CUSTOM", "2025-01-01", "2025-12-31")
	if err != nil {
		t.Fatalf("GetExecutiveKPIs 2025 failed: %v", err)
	}
	if kpis2025.TotalRevenue != 20000.0 {
		t.Errorf("expected 2025 TotalRevenue=20000.0, got %.2f", kpis2025.TotalRevenue)
	}
	if len(kpis2025.ChainShares) != 1 || kpis2025.ChainShares[0].RetailerChain != "gomla" {
		t.Errorf("expected only gomla in 2025 ChainShares, got %+v", kpis2025.ChainShares)
	}
	if len(kpis2025.DailyTrends) != 1 || kpis2025.DailyTrends[0].MonthKey != "2025-01" {
		t.Errorf("expected 1 monthly trend point (2025-01) in 2025, got %+v", kpis2025.DailyTrends)
	}

	// 2. Query 2026 only -> should only return Fathalla (121,000 EGP)
	kpis2026, err := bqRepo.GetExecutiveKPIs(ctx, "tenant-adeco", "CUSTOM", "2026-01-01", "2026-12-31")
	if err != nil {
		t.Fatalf("GetExecutiveKPIs 2026 failed: %v", err)
	}
	if kpis2026.TotalRevenue != 121000.0 {
		t.Errorf("expected 2026 TotalRevenue=121000.0, got %.2f", kpis2026.TotalRevenue)
	}
	if len(kpis2026.ChainShares) != 1 || kpis2026.ChainShares[0].RetailerChain != "fathalla" {
		t.Errorf("expected only fathalla in 2026 ChainShares, got %+v", kpis2026.ChainShares)
	}

	// 3. Query ALL periods -> should return BOTH Fathalla and Gomla in ChainShares and DailyTrends
	kpisAll, err := bqRepo.GetExecutiveKPIs(ctx, "tenant-adeco", "ALL")
	if err != nil {
		t.Fatalf("GetExecutiveKPIs ALL failed: %v", err)
	}
	if len(kpisAll.ChainShares) != 2 {
		t.Errorf("expected 2 chains (fathalla + gomla) in ALL ChainShares, got %d", len(kpisAll.ChainShares))
	}
}

func TestRealWorkbooksFathallaAndGomlaEndToEnd(t *testing.T) {
	// Large local Downloads fixtures (~minutes). Opt-in only — on the shared CI Mac
	// these files exist and otherwise blow the suite past the job timeout.
	if os.Getenv("RUN_LARGE_LOCAL_INGEST_TESTS") != "1" {
		t.Skip("set RUN_LARGE_LOCAL_INGEST_TESTS=1 to run Downloads workbook e2e")
	}
	home, _ := os.UserHomeDir()
	if home == "" {
		home = os.Getenv("HOME")
	}
	fathallaPath := filepath.Join(home, "Downloads", "40-Adco -2026.xlsx")
	gomlaPath := filepath.Join(home, "Downloads", "Book1 (2).xlsx")

	fathallaBytes, err1 := os.ReadFile(fathallaPath)
	gomlaBytes, err2 := os.ReadFile(gomlaPath)
	if err1 != nil || err2 != nil {
		t.Skipf("skipping real workbook test because files are not present on disk: %v / %v", err1, err2)
	}

	ctx := context.Background()
	agent := gemini.NewAgent("", "gemini-3.8-flash", true)
	bqRepo := bigquery.NewClient("test-proj", "test-dataset", true)
	fsRepo := firestore.NewClient("test-db", true)
	processor := NewProcessor(agent, bqRepo, fsRepo)

	if err := processor.ClearTenantData(ctx, "adeco"); err != nil {
		t.Fatalf("ClearTenantData failed: %v", err)
	}

	fathallaRes, err := processor.ProcessUpload(ctx, "adeco", "40-Adco -2026.xlsx", fathallaBytes, "fathalla")
	if err != nil {
		t.Fatalf("Fathalla real workbook upload failed: %v", err)
	}
	if len(fathallaRes.DetectedSheets) != 23 {
		t.Fatalf("expected 23 detected sheets in Fathalla workbook, got %d", len(fathallaRes.DetectedSheets))
	}
	for i, sh := range fathallaRes.DetectedSheets {
		if sh.PeriodDate == "" || sh.TotalRevenue <= 0 || sh.RowCount <= 0 {
			t.Errorf("Sheet[%d] (%s) missing populated metadata: date=%q rev=%.2f rows=%d", i, sh.Name, sh.PeriodDate, sh.TotalRevenue, sh.RowCount)
		}
	}

	if _, err := processor.ProcessUpload(ctx, "adeco", "Book1 (2).xlsx", gomlaBytes, "gomla"); err != nil {
		t.Fatalf("Gomla real workbook upload failed: %v", err)
	}

	// 1. Verify 4/2024 (April 2024 MTD)
	kpis2024Apr, err := bqRepo.GetExecutiveKPIs(ctx, "adeco", "MTD", "2024-04-01", "2024-04-30")
	if err != nil {
		t.Fatalf("GetExecutiveKPIs 4/2024 failed: %v", err)
	}
	if kpis2024Apr.TotalRevenue != 6756868.0 {
		t.Errorf("expected 4/2024 TotalRevenue=6756868.0, got %.2f", kpis2024Apr.TotalRevenue)
	}
	if len(kpis2024Apr.ChainShares) != 1 || kpis2024Apr.ChainShares[0].RetailerChain != "fathalla" || kpis2024Apr.ChainShares[0].MarketShare != 100.0 {
		t.Errorf("expected only fathalla (100%%) in 4/2024 ChainShares, got %+v", kpis2024Apr.ChainShares)
	}
	if kpis2024Apr.RevenueMoMPct != -16.0 {
		t.Errorf("expected 4/2024 RevenueMoMPct=-16.0 (vs 3/2024), got %.1f", kpis2024Apr.RevenueMoMPct)
	}
	if len(kpis2024Apr.DailyTrends) != 10 {
		t.Errorf("expected 10 monthly trend points for 2024 (2024-01..2024-10) in MTD 4/2024, got %d", len(kpis2024Apr.DailyTrends))
	}

	// 2. Verify 2025 YTD (2025-01-01..2025-12-31) -> BOTH Fathalla and Gomla, no 3rd chain
	kpis2025, err := bqRepo.GetExecutiveKPIs(ctx, "adeco", "YTD", "2025-01-01", "2025-12-31")
	if err != nil {
		t.Fatalf("GetExecutiveKPIs 2025 YTD failed: %v", err)
	}
	if kpis2025.TotalRevenue != 124579930.50 {
		t.Errorf("expected 2025 TotalRevenue=124579930.50, got %.2f", kpis2025.TotalRevenue)
	}
	if len(kpis2025.ChainShares) != 2 {
		t.Fatalf("expected exactly 2 chains (fathalla + gomla) in 2025 ChainShares, got %+v", kpis2025.ChainShares)
	}
	if kpis2025.ChainShares[0].RetailerChain != "fathalla" || kpis2025.ChainShares[1].RetailerChain != "gomla" {
		t.Errorf("unexpected 2025 chains: %+v", kpis2025.ChainShares)
	}
	if len(kpis2025.DailyTrends) != 12 {
		t.Fatalf("expected 12 monthly trend points in 2025, got %d", len(kpis2025.DailyTrends))
	}
	jan2025 := kpis2025.DailyTrends[0]
	if jan2025.MonthKey != "2025-01" || jan2025.ChainRevenues["fathalla"] != 6717889.86 || jan2025.ChainRevenues["gomla"] != 6573015.0 {
		t.Errorf("unexpected 2025-01 per-chain revenues: %+v", jan2025)
	}

	// 3. Verify 1/2025 MTD (default ExecutiveScreen view) -> KPIs for Jan 2025 + full 12-month 2025 trend curve
	kpis2025JanMTD, err := bqRepo.GetExecutiveKPIs(ctx, "adeco", "MTD", "2025-01-01", "2025-01-31")
	if err != nil {
		t.Fatalf("GetExecutiveKPIs 1/2025 MTD failed: %v", err)
	}
	if kpis2025JanMTD.TotalRevenue != 13290904.86 {
		t.Errorf("expected 1/2025 MTD TotalRevenue=13290904.86, got %.2f", kpis2025JanMTD.TotalRevenue)
	}
	if len(kpis2025JanMTD.ChainShares) != 2 {
		t.Errorf("expected 2 chains in 1/2025 MTD ChainShares, got %+v", kpis2025JanMTD.ChainShares)
	}
	if len(kpis2025JanMTD.DailyTrends) != 12 {
		t.Errorf("expected 12 monthly trend points for 2025 in 1/2025 MTD, got %d", len(kpis2025JanMTD.DailyTrends))
	}

	// 4. Verify 2026 (2026-01-01..2026-12-31) -> ONLY Fathalla
	kpis2026, err := bqRepo.GetExecutiveKPIs(ctx, "adeco", "YTD", "2026-01-01", "2026-12-31")
	if err != nil {
		t.Fatalf("GetExecutiveKPIs 2026 failed: %v", err)
	}
	if kpis2026.TotalRevenue != 9537094.70 {
		t.Errorf("expected 2026 TotalRevenue=9537094.70, got %.2f", kpis2026.TotalRevenue)
	}
	if len(kpis2026.ChainShares) != 1 || kpis2026.ChainShares[0].RetailerChain != "fathalla" {
		t.Errorf("expected only fathalla in 2026 ChainShares, got %+v", kpis2026.ChainShares)
	}
	if kpis2026.RevenueMoMPct != -2.4 {
		t.Errorf("expected 2026 RevenueMoMPct=-2.4, got %.1f", kpis2026.RevenueMoMPct)
	}
	if len(kpis2026.DailyTrends) != 1 || len(kpis2026.DailyTrends[0].ChainDetails) != 1 || kpis2026.DailyTrends[0].ChainDetails[0].GrowthPct != -2.4 {
		t.Errorf("expected 2026-01 trend point with GrowthPct=-2.4, got %+v", kpis2026.DailyTrends)
	}

	// 5. Verify chain=gomla in 1/2025 does NOT leak Fathalla's 25 OOS incidents
	kpisGomla, err := bqRepo.GetExecutiveKPIs(ctx, "adeco", "MTD", "2025-01-01", "2025-01-31", "gomla")
	if err != nil {
		t.Fatalf("GetExecutiveKPIs gomla failed: %v", err)
	}
	if kpisGomla.TotalRevenue != 6573015.0 {
		t.Errorf("expected gomla TotalRevenue=6573015.0, got %.2f", kpisGomla.TotalRevenue)
	}
	if kpisGomla.TotalOOSIncidents != 0 || kpisGomla.OOSRatePct != 0.0 {
		t.Errorf("expected 0 OOS incidents for gomla, got incidents=%d rate=%.1f", kpisGomla.TotalOOSIncidents, kpisGomla.OOSRatePct)
	}
}

func TestRequestedPeriodDateOverrideOnUploadAndCommit(t *testing.T) {
	ctx := context.Background()
	agent := gemini.NewAgent("", "gemini-3.8-flash", true)
	bqRepo := bigquery.NewClient("test-proj", "test-dataset", true)
	fsRepo := firestore.NewClient("test-db", true)
	processor := NewProcessor(agent, bqRepo, fsRepo)

	if err := processor.ClearTenantData(ctx, "adeco"); err != nil {
		t.Fatalf("ClearTenantData failed: %v", err)
	}

	csvContent := []byte("الباركود,اسم الصنف,الفرع,الكمية,القيمة\n6221155001234,زيت زيتون أديكو 500 مل,فرع سموحة,100,25000\n")

	// Dry-run upload with period_date override 2025-02-15
	ctxFeb := gemini.WithRequestedPeriodDate(ctx, "2025-02-15")
	stagedRes, err := processor.ProcessUploadWithDryRun(ctxFeb, "adeco", "gomla_feb.csv", csvContent, true, "gomla")
	if err != nil {
		t.Fatalf("ProcessUploadWithDryRun failed: %v", err)
	}
	if !stagedRes.IsStaged || stagedRes.BatchID == "" {
		t.Fatalf("expected staged result with BatchID, got %+v", stagedRes)
	}

	// Commit with override 2025-03-15
	ctxMar := gemini.WithRequestedPeriodDate(ctx, "2025-03-15")
	committedRes, err := processor.CommitStagedUpload(ctxMar, "adeco", stagedRes.BatchID, "gomla")
	if err != nil {
		t.Fatalf("CommitStagedUpload failed: %v", err)
	}
	if !committedRes.IsCommitted {
		t.Fatalf("expected committed result, got %+v", committedRes)
	}

	kpisMar, err := bqRepo.GetExecutiveKPIs(ctx, "adeco", "MTD", "2025-03-01", "2025-03-31")
	if err != nil {
		t.Fatalf("GetExecutiveKPIs 2025-03 failed: %v", err)
	}
	if kpisMar.TotalRevenue != 25000.0 || kpisMar.TotalUnitsSold != 100 {
		t.Errorf("expected March 2025 revenue=25000.0 and units=100, got rev=%f units=%d", kpisMar.TotalRevenue, kpisMar.TotalUnitsSold)
	}
}

func TestUploadArchiveSaveFilterAndDownload(t *testing.T) {
	ctx := context.Background()
	tmpDir := t.TempDir()
	agent := gemini.NewAgent("", "gemini-3.8-flash", true)
	bqRepo := bigquery.NewClient("test-proj", "test-dataset", true)
	fsRepo := firestore.NewClient("test-db", true)
	processor := NewProcessor(agent, bqRepo, fsRepo).WithArchiveDir(tmpDir)

	fathallaCSV := []byte("الباركود,اسم الصنف,الفرع,الكمية,القيمة\n6221155001234,زيت زيتون أديكو 500 مل,فرع سموحة,100,25000\n")
	gomlaCSV := []byte("الباركود,اسم الصنف,الفرع,الكمية,القيمة\n6221155001241,زيت عباد الشمس أديكو 1 لتر,فرع الكوثر,50,12000\n")

	resFat, err := processor.ProcessUpload(ctx, "tenant-archive-test", "40-Adco -2026.xlsx", fathallaCSV, "fathalla")
	if err != nil {
		t.Fatalf("ProcessUpload fathalla failed: %v", err)
	}
	if resFat.ArchiveID == "" || resFat.ArchivedFile == nil {
		t.Fatalf("expected ArchiveID and ArchivedFile on IngestionResult")
	}

	resGom, err := processor.ProcessUpload(ctx, "tenant-archive-test", "Book1 (2).xlsx", gomlaCSV, "gomla")
	if err != nil {
		t.Fatalf("ProcessUpload gomla failed: %v", err)
	}
	if resGom.ArchiveID == "" {
		t.Fatalf("expected ArchiveID for gomla upload")
	}

	// List all archived files for tenant
	allArch := processor.ListArchivedFiles(ctx, "tenant-archive-test", "", "", "")
	if allArch.TotalCount != 2 || len(allArch.Files) != 2 {
		t.Fatalf("expected 2 archived files, got %d", allArch.TotalCount)
	}
	if allArch.ChainCounts["fathalla"] != 1 || allArch.ChainCounts["gomla"] != 1 {
		t.Errorf("unexpected chain counts: %+v", allArch.ChainCounts)
	}

	// Filter by chain=gomla
	gomlaArch := processor.ListArchivedFiles(ctx, "tenant-archive-test", "gomla", "2026", "")
	if len(gomlaArch.Files) != 1 || gomlaArch.Files[0].FileName != "Book1 (2).xlsx" {
		t.Errorf("expected 1 gomla file 'Book1 (2).xlsx', got %+v", gomlaArch.Files)
	}
	if gomlaArch.Files[0].ChainNameAr != "جملة ماركت" {
		t.Errorf("expected ChainNameAr 'جملة ماركت', got %s", gomlaArch.Files[0].ChainNameAr)
	}

	// Download raw bytes for Fathalla archive item
	entry, rawBytes, err := processor.GetArchivedFile(ctx, "tenant-archive-test", resFat.ArchiveID)
	if err != nil {
		t.Fatalf("GetArchivedFile failed: %v", err)
	}
	if entry.FileName != "40-Adco -2026.xlsx" {
		t.Errorf("expected FileName '40-Adco -2026.xlsx', got %s", entry.FileName)
	}
	if string(rawBytes) != string(fathallaCSV) {
		t.Errorf("downloaded bytes do not match uploaded bytes")
	}

	// Verify reload from disk index
	processor2 := NewProcessor(agent, bqRepo, fsRepo).WithArchiveDir(tmpDir)
	reloaded := processor2.ListArchivedFiles(ctx, "tenant-archive-test", "", "", "")
	if reloaded.TotalCount != 2 {
		t.Errorf("expected 2 archived files reloaded from disk, got %d", reloaded.TotalCount)
	}

	// Test staging a file with a chain mismatch (selected fathalla, file is gomla), then committing with override="gomla"
	mismatchCSV := []byte("الباركود,اسم الصنف,الفرع,الكمية,القيمة\n6221155001258,زيت ذرة أديكو,فرع جملة الدقي,30,9000\n")
	stagedMismatch, err := processor.ProcessUploadWithDryRun(ctx, "tenant-archive-test", "Gomla_October_2026.csv", mismatchCSV, true, "fathalla")
	if err != nil {
		t.Fatalf("ProcessUploadWithDryRun mismatch failed: %v", err)
	}
	if !stagedMismatch.ChainMismatchDetected || stagedMismatch.SuggestedChain != "gomla" {
		t.Fatalf("expected ChainMismatchDetected=true with SuggestedChain=gomla, got %+v", stagedMismatch)
	}

	committedMismatch, err := processor.CommitStagedUpload(ctx, "tenant-archive-test", stagedMismatch.BatchID, "gomla")
	if err != nil {
		t.Fatalf("CommitStagedUpload override failed: %v", err)
	}
	if committedMismatch.ChainMismatchDetected {
		t.Errorf("expected ChainMismatchDetected=false after committing with chain override")
	}
	if committedMismatch.RetailerDetected != "gomla" || committedMismatch.TargetRetailer != "gomla" {
		t.Errorf("expected RetailerDetected and TargetRetailer to be gomla, got %s / %s", committedMismatch.RetailerDetected, committedMismatch.TargetRetailer)
	}
	if committedMismatch.ArchivedFile == nil || committedMismatch.ArchivedFile.RetailChain != "gomla" || committedMismatch.ArchivedFile.ChainNameAr != "جملة ماركت" {
		t.Errorf("expected committed ArchivedFile to reflect gomla, got %+v", committedMismatch.ArchivedFile)
	}

	afterCommitArch := processor.ListArchivedFiles(ctx, "tenant-archive-test", "", "", "")
	if afterCommitArch.ChainCounts["fathalla"] != 1 || afterCommitArch.ChainCounts["gomla"] != 2 {
		t.Errorf("expected ChainCounts fathalla=1, gomla=2 after mismatch fix commit, got %+v", afterCommitArch.ChainCounts)
	}

	// Test staging a brand new file and then discarding it -> should be removed from archive
	stagedDiscard, err := processor.ProcessUploadWithDryRun(ctx, "tenant-archive-test", " accidental_upload_2026.csv", mismatchCSV, true, "carrefour")
	if err != nil {
		t.Fatalf("ProcessUploadWithDryRun for discard failed: %v", err)
	}
	if err := processor.DiscardStagedUpload(ctx, "tenant-archive-test", stagedDiscard.BatchID); err != nil {
		t.Fatalf("DiscardStagedUpload failed: %v", err)
	}
	afterDiscardArch := processor.ListArchivedFiles(ctx, "tenant-archive-test", "", "", "")
	if afterDiscardArch.TotalCount != 3 || afterDiscardArch.ChainCounts["carrefour"] != 0 {
		t.Errorf("expected discarded upload to be removed from archive, got count=%d counts=%+v", afterDiscardArch.TotalCount, afterDiscardArch.ChainCounts)
	}

	// Test staging a file with the same name as an existing committed file and discarding it -> should restore original file bytes
	modifiedFatCSV := []byte("الباركود,اسم الصنف,الفرع,الكمية,القيمة\n6221155001234,زيت زيتون معدل,فرع سموحة,999,99999\n")
	stagedOverwrite, err := processor.ProcessUploadWithDryRun(ctx, "tenant-archive-test", "40-Adco -2026.xlsx", modifiedFatCSV, true, "fathalla")
	if err != nil {
		t.Fatalf("ProcessUploadWithDryRun overwrite failed: %v", err)
	}
	if err := processor.DiscardStagedUpload(ctx, "tenant-archive-test", stagedOverwrite.BatchID); err != nil {
		t.Fatalf("DiscardStagedUpload overwrite failed: %v", err)
	}
	restoredEntry, restoredBytes, err := processor.GetArchivedFile(ctx, "tenant-archive-test", resFat.ArchiveID)
	if err != nil {
		t.Fatalf("GetArchivedFile after discard overwrite failed: %v", err)
	}
	if string(restoredBytes) != string(fathallaCSV) || restoredEntry.TotalRevenue != 25000 {
		t.Errorf("expected original committed file bytes and revenue to be restored after discard, got rev=%.2f", restoredEntry.TotalRevenue)
	}

	// Test DeleteArchivedFile: deleting a file removes it from archive and purges records from BigQuery
	delEntry, err := processor.DeleteArchivedFile(ctx, "tenant-archive-test", resGom.ArchiveID)
	if err != nil {
		t.Fatalf("DeleteArchivedFile failed: %v", err)
	}
	if delEntry.ID != resGom.ArchiveID {
		t.Errorf("expected deleted entry ID %s, got %s", resGom.ArchiveID, delEntry.ID)
	}
	afterDeleteArch := processor.ListArchivedFiles(ctx, "tenant-archive-test", "", "", "")
	if afterDeleteArch.TotalCount != 2 {
		t.Errorf("expected 2 files remaining after deleting Gomla, got %d", afterDeleteArch.TotalCount)
	}

	// When all remaining files are deleted, tenant data is completely zeroed out
	for _, f := range afterDeleteArch.Files {
		if _, err := processor.DeleteArchivedFile(ctx, "tenant-archive-test", f.ID); err != nil {
			t.Fatalf("DeleteArchivedFile on %s failed: %v", f.ID, err)
		}
	}
	finalArch := processor.ListArchivedFiles(ctx, "tenant-archive-test", "", "", "")
	if finalArch.TotalCount != 0 {
		t.Errorf("expected 0 files after deleting all, got %d", finalArch.TotalCount)
	}
	kpisAfterAllDelete, err := bqRepo.GetExecutiveKPIs(ctx, "tenant-archive-test", "ALL")
	if err != nil {
		t.Fatalf("GetExecutiveKPIs after all delete failed: %v", err)
	}
	if kpisAfterAllDelete.TotalRevenue != 0 || len(kpisAfterAllDelete.ChainShares) != 0 {
		t.Errorf("expected 0 revenue and 0 chain shares after deleting all archive files, got rev=%.2f shares=%+v", kpisAfterAllDelete.TotalRevenue, kpisAfterAllDelete.ChainShares)
	}
}

func TestLargeBook6StreamingXLSXIngestion(t *testing.T) {
	if os.Getenv("RUN_LARGE_LOCAL_INGEST_TESTS") != "1" {
		t.Skip("set RUN_LARGE_LOCAL_INGEST_TESTS=1 to run Book6 large-file benchmark")
	}
	home, _ := os.UserHomeDir()
	if home == "" {
		home = os.Getenv("HOME")
	}
	book6Path := filepath.Join(home, "Downloads", "Book6.xlsx")
	book6Bytes, err := os.ReadFile(book6Path)
	if err != nil || len(book6Bytes) == 0 {
		t.Skip("Book6.xlsx not present in Downloads, skipping local large-file benchmark")
	}

	ctx := context.Background()
	agent := gemini.NewAgent("", "gemini-1.5-pro", true)
	bqRepo := bigquery.NewClient("test-proj", "test-dataset", true)
	fsRepo := firestore.NewClient("test-db", true)
	processor := NewProcessor(agent, bqRepo, fsRepo)

	res, err := processor.ProcessUploadWithDryRun(ctx, "tenant-adeco", "Book6.xlsx", book6Bytes, true, "beet-elgomla")
	if err != nil {
		t.Fatalf("ProcessUploadWithDryRun for 13.8MB Book6.xlsx failed: %v", err)
	}

	t.Logf("Book6.xlsx (13.8 MB) Ingestion Summary: ValidRows=%d, TotalRows=%d, Branches=%d, Categories=%d, Competitors=%d, AdcoRevenue=%.2f EGP, AdcoMarketShare=%.2f%%, DiscoveredRetailer=%s, ChainMismatch=%v",
		res.ValidRows, res.TotalRows, res.AutoCreatedStoresCount, len(res.DiscoveredCategories), res.CompetitorsDetected, res.TotalRevenue, res.TenantMarketSharePct, res.DiscoveredRetailer, res.ChainMismatchDetected)

	if res.ValidRows < 250000 {
		t.Errorf("expected >= 250,000 valid rows from Book6.xlsx, got %d", res.ValidRows)
	}
	if res.AutoCreatedStoresCount < 25 {
		t.Errorf("expected >= 25 branches from Book6.xlsx, got %d", res.AutoCreatedStoresCount)
	}
	if res.TotalRevenue < 40000000 {
		t.Errorf("expected Adco revenue > 40M EGP in Book6.xlsx, got %.2f", res.TotalRevenue)
	}
	if res.ChainMismatchDetected {
		t.Errorf("expected ChainMismatchDetected=false when uploading Book6.xlsx to beet-elgomla")
	}
}

