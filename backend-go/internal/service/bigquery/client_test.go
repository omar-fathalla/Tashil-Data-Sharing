package bigquery

import (
	"context"
	"testing"
	"time"

	"github.com/tashil/data-sharing/backend/internal/domain"
)

func TestInsertSellOutFactsDeduplication(t *testing.T) {
	client := NewClient("test-project", "test-dataset", true)
	ctx := context.Background()

	initialCount := len(client.records)

	// Create a new unique fact
	fact1 := domain.SellOutFact{
		RecordID:        "fact_tenant-adeco_carrefour_crf_cairo_maadi_6221155001234_2026-03-01",
		TenantID:        "tenant-adeco",
		RetailerChain:   "carrefour",
		StoreID:         "crf_cairo_maadi",
		StoreName:       "كارفور المعادي",
		Barcode:         "6221155001234",
		SKUName:         "Adeco Extra Virgin Olive Oil 500ml",
		Category:        "زيوت طعام",
		QuantitySold:    10,
		NetRevenue:      2500.0,
		UnitPrice:       250.0,
		TransactionDate: "2026-03-01",
	}

	err := client.InsertSellOutFacts(ctx, []domain.SellOutFact{fact1})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if len(client.records) != initialCount+1 {
		t.Fatalf("expected count %d, got %d", initialCount+1, len(client.records))
	}

	// Insert identical RecordID with updated revenue (simulating re-upload / duplicate click)
	fact1Updated := fact1
	fact1Updated.QuantitySold = 15
	fact1Updated.NetRevenue = 3750.0

	err = client.InsertSellOutFacts(ctx, []domain.SellOutFact{fact1Updated})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	// Verify total count did NOT increase (zero-tolerance duplicate prevention)
	if len(client.records) != initialCount+1 {
		t.Errorf("zero-tolerance deduplication failed: count grew to %d, expected %d", len(client.records), initialCount+1)
	}

	// Verify record content was updated in place
	found := false
	for _, r := range client.records {
		if r.RecordID == fact1.RecordID {
			found = true
			if r.NetRevenue != 3750.0 || r.QuantitySold != 15 {
				t.Errorf("expected updated revenue 3750.0, got %f", r.NetRevenue)
			}
		}
	}
	if !found {
		t.Errorf("expected record to be found")
	}
}

func TestGetExecutiveKPIsPeriodFiltering(t *testing.T) {
	client := NewClient("test-project", "test-dataset", true)
	ctx := context.Background()

	// Clear seed data and add known dates
	client.records = []domain.SellOutFact{
		{
			RecordID:        "rec_today",
			TenantID:        "tenant-adeco",
			RetailerChain:   "carrefour",
			StoreID:         "crf_cairo_maadi",
			StoreName:       "كارفور المعادي",
			Barcode:         "6221155001234",
			SKUName:         "Adeco Olive Oil",
			QuantitySold:    10,
			NetRevenue:      2500.0,
			TransactionDate: time.Now().Format("2006-01-02"),
		},
		{
			RecordID:        "rec_old",
			TenantID:        "tenant-adeco",
			RetailerChain:   "carrefour",
			StoreID:         "crf_cairo_maadi",
			StoreName:       "كارفور المعادي",
			Barcode:         "6221155001234",
			SKUName:         "Adeco Olive Oil",
			QuantitySold:    20,
			NetRevenue:      5000.0,
			TransactionDate: "2025-01-01",
		},
	}

	// Test TODAY
	todayKPIs, err := client.GetExecutiveKPIs(ctx, "tenant-adeco", "TODAY")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if todayKPIs.TotalRevenue != 2500.0 {
		t.Errorf("expected today revenue 2500.0, got %f", todayKPIs.TotalRevenue)
	}
	if todayKPIs.TotalUnitsSold != 10 {
		t.Errorf("expected today units 10, got %d", todayKPIs.TotalUnitsSold)
	}

	// Test MTD
	mtdKPIs, err := client.GetExecutiveKPIs(ctx, "tenant-adeco", "MTD")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if mtdKPIs.TotalRevenue != 2500.0 {
		t.Errorf("expected MTD revenue 2500.0, got %f", mtdKPIs.TotalRevenue)
	}

	// Test CUSTOM date range targeting 2025-01-01
	customKPIs, err := client.GetExecutiveKPIs(ctx, "tenant-adeco", "CUSTOM", "2024-12-31", "2025-01-02")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if customKPIs.TotalRevenue != 5000.0 || customKPIs.TotalUnitsSold != 20 {
		t.Errorf("expected custom date range revenue 5000.0 and units 20, got rev=%f units=%d", customKPIs.TotalRevenue, customKPIs.TotalUnitsSold)
	}
}

func TestGetSellOutRecordsDateFiltering(t *testing.T) {
	client := NewClient("test-project", "test-dataset", true)
	ctx := context.Background()

	client.records = []domain.SellOutFact{
		{
			RecordID:        "r1",
			TenantID:        "tenant-adeco",
			RetailerChain:   "carrefour",
			StoreID:         "s1",
			StoreName:       "Branch 1",
			Barcode:         "111111",
			SKUName:         "Item 1",
			TransactionDate: "2026-03-01",
		},
		{
			RecordID:        "r2",
			TenantID:        "tenant-adeco",
			RetailerChain:   "carrefour",
			StoreID:         "s1",
			StoreName:       "Branch 1",
			Barcode:         "222222",
			SKUName:         "Item 2",
			TransactionDate: "2026-03-05",
		},
		{
			RecordID:        "r3",
			TenantID:        "tenant-adeco",
			RetailerChain:   "carrefour",
			StoreID:         "s1",
			StoreName:       "Branch 1",
			Barcode:         "333333",
			SKUName:         "Item 3",
			TransactionDate: "2026-03-10",
		},
	}

	// Filter by StartDate and EndDate
	recs, total, err := client.GetSellOutRecords(ctx, "tenant-adeco", RecordFilter{
		StartDate: "2026-03-04",
		EndDate:   "2026-03-08",
		Limit:     10,
	})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if total != 1 || len(recs) != 1 {
		t.Fatalf("expected 1 record between 03-04 and 03-08, got %d", total)
	}
	if recs[0].RecordID != "r2" {
		t.Errorf("expected r2, got %s", recs[0].RecordID)
	}
}

func TestGetStoreBenchmarkMatrix(t *testing.T) {
	client := NewClient("test-project", "test-dataset", true)
	ctx := context.Background()

	// 1. Test normalized tenant "adeco" (without tenant- prefix) matches seed data
	stores, err := client.GetStoreBenchmarkMatrix(ctx, "adeco", StoreMatrixFilter{})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(stores) == 0 {
		t.Fatal("expected stores for tenant 'adeco', got 0")
	}

	// 2. Test full tenant "tenant-adeco" returns identical count
	storesFull, err := client.GetStoreBenchmarkMatrix(ctx, "tenant-adeco", StoreMatrixFilter{})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(storesFull) != len(stores) {
		t.Errorf("expected count %d, got %d", len(stores), len(storesFull))
	}

	// 3. Test Unilever and Pepsi have their own isolated store benchmarks
	unileverStores, err := client.GetStoreBenchmarkMatrix(ctx, "tenant-unilever", StoreMatrixFilter{})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(unileverStores) == 0 {
		t.Fatal("expected stores for tenant-unilever, got 0")
	}

	pepsiStores, err := client.GetStoreBenchmarkMatrix(ctx, "tenant-pepsi", StoreMatrixFilter{})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(pepsiStores) == 0 {
		t.Fatal("expected stores for tenant-pepsi, got 0")
	}

	// 4. Test unseeded foreign tenant has zero records (RLS)
	foreignStores, err := client.GetStoreBenchmarkMatrix(ctx, "tenant-unknown-foreign", StoreMatrixFilter{})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(foreignStores) != 0 {
		t.Errorf("expected 0 stores for unknown foreign tenant, got %d", len(foreignStores))
	}

	// 5. Test filtering by region and tier
	tierAStores, err := client.GetStoreBenchmarkMatrix(ctx, "tenant-adeco", StoreMatrixFilter{Tier: "Tier A"})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	for _, s := range tierAStores {
		if s.Tier != "Tier A" {
			t.Errorf("expected Tier A, got %s", s.Tier)
		}
	}
}

func TestGetPricingCompliance(t *testing.T) {
	client := NewClient("test-project", "test-dataset", true)
	ctx := context.Background()

	// 1. Test normalized tenant "adeco" returns pricing items
	items, err := client.GetPricingCompliance(ctx, "adeco", PricingComplianceFilter{})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(items) == 0 {
		t.Fatal("expected pricing items for adeco, got 0")
	}

	// 2. Test Unilever and Pepsi receive their own isolated pricing items
	unileverItems, err := client.GetPricingCompliance(ctx, "tenant-unilever", PricingComplianceFilter{})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(unileverItems) == 0 {
		t.Fatal("expected pricing items for tenant-unilever, got 0")
	}
	for _, item := range unileverItems {
		if item.TenantID != "tenant-unilever" {
			t.Errorf("expected tenant-unilever item, got %s (%s)", item.TenantID, item.SKUName)
		}
	}

	pepsiItems, err := client.GetPricingCompliance(ctx, "tenant-pepsi", PricingComplianceFilter{})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(pepsiItems) == 0 {
		t.Fatal("expected pricing items for tenant-pepsi, got 0")
	}
	for _, item := range pepsiItems {
		if item.TenantID != "tenant-pepsi" {
			t.Errorf("expected tenant-pepsi item, got %s (%s)", item.TenantID, item.SKUName)
		}
	}

	// 3. Test unknown foreign tenant receives 0 items (RLS isolation)
	foreignItems, err := client.GetPricingCompliance(ctx, "tenant-unknown-foreign", PricingComplianceFilter{})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(foreignItems) != 0 {
		t.Errorf("expected 0 pricing items for unknown foreign tenant, got %d", len(foreignItems))
	}

	// 4. Test dynamic tenant provisioning auto-seeding (e.g., juhayna)
	juhaynaItems, err := client.GetPricingCompliance(ctx, "juhayna", PricingComplianceFilter{})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(juhaynaItems) == 0 {
		t.Fatal("expected dynamically seeded pricing items for juhayna, got 0")
	}

	// 5. Test ViolationOnly filter
	violations, err := client.GetPricingCompliance(ctx, "tenant-adeco", PricingComplianceFilter{ViolationOnly: true})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	for _, v := range violations {
		if v.ViolationType == "compliant" {
			t.Errorf("expected only violations, got compliant item: %s", v.SKUName)
		}
	}

	// 6. Test category filter
	canned, err := client.GetPricingCompliance(ctx, "tenant-adeco", PricingComplianceFilter{Category: "صلصة ومعلبات"})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	for _, c := range canned {
		if c.Category != "صلصة ومعلبات" {
			t.Errorf("expected category صلصة ومعلبات, got %s", c.Category)
		}
	}
}

func TestExecutiveKPIsCategoryContributionsParetoAndOSA(t *testing.T) {
	client := NewClient("test-project", "test-dataset", true)
	ctx := context.Background()

	// 1. Verify seeded Adeco ExecutiveKPIs includes CategoryContributions, ParetoSKUs, OSARatePct, and YoY/MoM
	kpis, err := client.GetExecutiveKPIs(ctx, "tenant-adeco", "MTD")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if kpis.OSARatePct != 95.8 {
		t.Errorf("expected OSARatePct 95.8 (100 - 4.2), got %f", kpis.OSARatePct)
	}
	if kpis.RevenueMoMPct <= 0 || kpis.RevenueYoYPct <= 0 {
		t.Errorf("expected positive RevenueMoMPct and RevenueYoYPct, got MoM=%f YoY=%f", kpis.RevenueMoMPct, kpis.RevenueYoYPct)
	}
	if kpis.UnitsMoMPct <= 0 || kpis.UnitsYoYPct <= 0 {
		t.Errorf("expected positive UnitsMoMPct and UnitsYoYPct, got MoM=%f YoY=%f", kpis.UnitsMoMPct, kpis.UnitsYoYPct)
	}
	if kpis.RevenueGrowthPct != kpis.RevenueMoMPct {
		t.Errorf("expected RevenueGrowthPct == RevenueMoMPct (%f), got %f", kpis.RevenueMoMPct, kpis.RevenueGrowthPct)
	}
	if len(kpis.CategoryContributions) != 3 {
		t.Fatalf("expected 3 categories for Adeco, got %d", len(kpis.CategoryContributions))
	}
	if len(kpis.ParetoSKUs) != 7 {
		t.Fatalf("expected 7 Pareto SKUs for Adeco, got %d", len(kpis.ParetoSKUs))
	}

	// Verify CategoryContributions are sorted descending by revenue and SKUCount matches
	for i := 1; i < len(kpis.CategoryContributions); i++ {
		if kpis.CategoryContributions[i].TotalRevenue > kpis.CategoryContributions[i-1].TotalRevenue {
			t.Errorf("CategoryContributions not sorted descending at index %d", i)
		}
	}
	if kpis.CategoryContributions[0].Category != "زيوت طعام" || kpis.CategoryContributions[0].SKUCount != 4 {
		t.Errorf("expected top category زيوت طعام with 4 SKUs, got %+v", kpis.CategoryContributions[0])
	}

	// 2. Verify exact Pareto 80/20 cumulative share and IsTop80Contributor flagging on controlled dataset
	isolatedTenant := "tenant-unknown-pareto-test"
	today := time.Now().Format("2006-01-02")
	_ = client.InsertSellOutFacts(ctx, []domain.SellOutFact{
		{
			RecordID:        "p1",
			TenantID:        isolatedTenant,
			RetailerChain:   "carrefour",
			StoreID:         "s1",
			Barcode:         "10000001",
			SKUName:         "Hero SKU A (50%)",
			Category:        "Cat A",
			QuantitySold:    50,
			NetRevenue:      5000.0,
			TransactionDate: today,
		},
		{
			RecordID:        "p2",
			TenantID:        isolatedTenant,
			RetailerChain:   "carrefour",
			StoreID:         "s1",
			Barcode:         "10000002",
			SKUName:         "Core SKU B (35%)",
			Category:        "Cat A",
			QuantitySold:    35,
			NetRevenue:      3500.0,
			TransactionDate: today,
		},
		{
			RecordID:        "p3",
			TenantID:        isolatedTenant,
			RetailerChain:   "carrefour",
			StoreID:         "s1",
			Barcode:         "10000003",
			SKUName:         "Tail SKU C (15%)",
			Category:        "Cat B",
			QuantitySold:    15,
			NetRevenue:      1500.0,
			TransactionDate: today,
		},
	})

	paretoKPIs, err := client.GetExecutiveKPIs(ctx, isolatedTenant, "MTD")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if len(paretoKPIs.ParetoSKUs) != 3 {
		t.Fatalf("expected 3 Pareto SKUs, got %d", len(paretoKPIs.ParetoSKUs))
	}

	// SKU 1: 50% share, cumulative 50.0%, prevCumulative 0.0 < 80 -> IsTop80Contributor = true
	if paretoKPIs.ParetoSKUs[0].RevenueSharePct != 50.0 || paretoKPIs.ParetoSKUs[0].CumulativeSharePct != 50.0 || !paretoKPIs.ParetoSKUs[0].IsTop80Contributor {
		t.Errorf("unexpected Pareto SKU[0]: %+v", paretoKPIs.ParetoSKUs[0])
	}
	// SKU 2: 35% share, cumulative 85.0%, prevCumulative 50.0 < 80 -> IsTop80Contributor = true
	if paretoKPIs.ParetoSKUs[1].RevenueSharePct != 35.0 || paretoKPIs.ParetoSKUs[1].CumulativeSharePct != 85.0 || !paretoKPIs.ParetoSKUs[1].IsTop80Contributor {
		t.Errorf("unexpected Pareto SKU[1]: %+v", paretoKPIs.ParetoSKUs[1])
	}
	// SKU 3: 15% share, cumulative 100.0%, prevCumulative 85.0 >= 80 -> IsTop80Contributor = false
	if paretoKPIs.ParetoSKUs[2].RevenueSharePct != 15.0 || paretoKPIs.ParetoSKUs[2].CumulativeSharePct != 100.0 || paretoKPIs.ParetoSKUs[2].IsTop80Contributor {
		t.Errorf("unexpected Pareto SKU[2]: %+v", paretoKPIs.ParetoSKUs[2])
	}

	// Check CategoryContributions on controlled dataset: Cat A (85%, 2 SKUs), Cat B (15%, 1 SKU)
	if len(paretoKPIs.CategoryContributions) != 2 {
		t.Fatalf("expected 2 CategoryContributions, got %d", len(paretoKPIs.CategoryContributions))
	}
	if paretoKPIs.CategoryContributions[0].Category != "Cat A" || paretoKPIs.CategoryContributions[0].SharePct != 85.0 || paretoKPIs.CategoryContributions[0].SKUCount != 2 {
		t.Errorf("unexpected CategoryContributions[0]: %+v", paretoKPIs.CategoryContributions[0])
	}
	if paretoKPIs.CategoryContributions[1].Category != "Cat B" || paretoKPIs.CategoryContributions[1].SharePct != 15.0 || paretoKPIs.CategoryContributions[1].SKUCount != 1 {
		t.Errorf("unexpected CategoryContributions[1]: %+v", paretoKPIs.CategoryContributions[1])
	}
}

func TestReplaceTenantFactsSingleMonthPreservesOtherMonths(t *testing.T) {
	client := NewClient("test-project", "test-dataset", true)
	ctx := context.Background()

	tenantID := "tenant-adeco-monthly-test"

	// Upload Jan 2025 for gomla
	err := client.ReplaceTenantFacts(ctx, tenantID, []domain.SellOutFact{
		{
			RecordID:        "fact_jan_1",
			TenantID:        tenantID,
			RetailerChain:   "gomla",
			StoreID:         "gomla_smouha",
			StoreName:       "فرع سموحة",
			Barcode:         "6223001",
			SKUName:         "Item 1",
			QuantitySold:    100,
			NetRevenue:      10000.0,
			TransactionDate: "2025-01-15",
		},
	})
	if err != nil {
		t.Fatalf("unexpected error uploading Jan: %v", err)
	}

	// Upload Feb 2025 for gomla (single-month upload for same chain)
	err = client.ReplaceTenantFacts(ctx, tenantID, []domain.SellOutFact{
		{
			RecordID:        "fact_feb_1",
			TenantID:        tenantID,
			RetailerChain:   "gomla",
			StoreID:         "gomla_smouha",
			StoreName:       "فرع سموحة",
			Barcode:         "6223001",
			SKUName:         "Item 1",
			QuantitySold:    150,
			NetRevenue:      15000.0,
			TransactionDate: "2025-02-15",
		},
	})
	if err != nil {
		t.Fatalf("unexpected error uploading Feb: %v", err)
	}

	// Both Jan and Feb should be preserved!
	recs, total, err := client.GetSellOutRecords(ctx, tenantID, RecordFilter{Limit: 50})
	if err != nil {
		t.Fatalf("unexpected error getting records: %v", err)
	}
	if total != 2 || len(recs) != 2 {
		t.Fatalf("expected 2 records (Jan + Feb preserved), got %d", total)
	}

	// Re-upload Feb 2025 with updated revenue -> should replace Feb 2025 only and keep Jan 2025
	err = client.ReplaceTenantFacts(ctx, tenantID, []domain.SellOutFact{
		{
			RecordID:        "fact_feb_1_updated",
			TenantID:        tenantID,
			RetailerChain:   "gomla",
			StoreID:         "gomla_smouha",
			StoreName:       "فرع سموحة",
			Barcode:         "6223001",
			SKUName:         "Item 1",
			QuantitySold:    200,
			NetRevenue:      20000.0,
			TransactionDate: "2025-02-15",
		},
	})
	if err != nil {
		t.Fatalf("unexpected error re-uploading Feb: %v", err)
	}

	kpis, err := client.GetExecutiveKPIs(ctx, tenantID, "ALL")
	if err != nil {
		t.Fatalf("unexpected error getting KPIs: %v", err)
	}
	if kpis.TotalRevenue != 30000.0 || kpis.TotalUnitsSold != 300 {
		t.Errorf("expected combined Jan+Feb revenue 30000.0 and units 300, got rev=%f units=%d", kpis.TotalRevenue, kpis.TotalUnitsSold)
	}
}




