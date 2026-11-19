package bigquery

import (
	"fmt"
	"math"
	"testing"

	"github.com/tashil/data-sharing/backend/internal/domain"
)

func TestBuildSellOutMonthlyPhasingEqualSplitWhenNoPriorYear(t *testing.T) {
	c := NewClient("test-project", "test-dataset", true)
	c.mu.Lock()
	defer c.mu.Unlock()

	tenant := "tenant-adeco"
	c.records = []domain.SellOutFact{
		{
			TenantID:        tenant,
			RetailerChain:   "fathalla",
			IsOwnBrand:      true,
			TransactionDate: "2026-01-15",
			NetRevenue:      1000,
			QuantitySold:    10,
		},
		{
			TenantID:        tenant,
			RetailerChain:   "fathalla",
			IsOwnBrand:      true,
			TransactionDate: "2026-02-10",
			NetRevenue:      2000,
			QuantitySold:    20,
		},
	}

	trec := domain.TargetRecord{
		ID:            "t1",
		TenantID:      tenant,
		TargetType:    "sell_out",
		RetailerChain: "fathalla",
		Year:          2026,
		Month:         0,
		BranchName:    "كل الفروع",
		Category:      "كل الفئات",
	}

	months := c.buildSellOutMonthlyPhasingLocked(normalizeTenantKey(tenant), trec, 12000, 120)
	if len(months) != 12 {
		t.Fatalf("expected 12 months, got %d", len(months))
	}
	if months[0].TargetRevenueEGP != 1000 {
		t.Fatalf("jan target want 1000 got %v", months[0].TargetRevenueEGP)
	}
	if math.Abs(months[0].SeasonalitySharePct-8.3) > 0.05 && math.Abs(months[0].SeasonalitySharePct-8.33) > 0.05 {
		// SharePct rounds to 1 decimal: 100/12 ≈ 8.3
		if math.Abs(months[0].SeasonalitySharePct-round2(100.0/12.0)) > 0.05 {
			t.Fatalf("empty prior share want ~8.3 got %v", months[0].SeasonalitySharePct)
		}
	}
	if months[0].ActualRevenueEGP != 1000 {
		t.Fatalf("jan actual want 1000 got %v", months[0].ActualRevenueEGP)
	}
	if !months[0].HasActuals {
		t.Fatal("jan should have actuals")
	}
	if months[1].ActualRevenueEGP != 2000 {
		t.Fatalf("feb actual want 2000 got %v", months[1].ActualRevenueEGP)
	}
	if months[2].ActualRevenueEGP != 0 {
		t.Fatalf("mar actual want 0 got %v", months[2].ActualRevenueEGP)
	}
	if months[2].HasActuals {
		t.Fatal("mar should not have actuals")
	}
}

func TestBuildSellOutMonthlyPhasingPriorYearWeights(t *testing.T) {
	c := NewClient("test-project", "test-dataset", true)
	c.mu.Lock()
	defer c.mu.Unlock()

	tenant := "tenant-adeco"
	// Full 2025: Jan=100 … pattern; use 100,200,300,...,1200 so shares ≡ sales/total
	c.records = nil
	for m := 1; m <= 12; m++ {
		c.records = append(c.records, domain.SellOutFact{
			TenantID: tenant, RetailerChain: "fathalla", IsOwnBrand: true,
			TransactionDate: "2025-" + pad2(m) + "-15",
			NetRevenue:      float64(m * 100),
			QuantitySold:    m * 10,
		})
	}
	trec := domain.TargetRecord{
		ID: "t-full", TenantID: tenant, TargetType: "sell_out",
		RetailerChain: "fathalla", Year: 2026, Month: 0,
		BranchName: "كل الفروع", Category: "كل الفئات",
	}
	months := c.buildSellOutMonthlyPhasingLocked(normalizeTenantKey(tenant), trec, 7800, 780)
	if len(months) != 12 {
		t.Fatalf("len %d", len(months))
	}
	var sumRev float64
	for _, m := range months {
		sumRev += m.TargetRevenueEGP
	}
	if math.Abs(sumRev-7800) > 0.05 {
		t.Fatalf("targets sum %v want 7800", sumRev)
	}
	// Jan sales=100, total=7800 → share ≈ 100/7800; target ≈ 7800 * share = 100
	if math.Abs(months[0].TargetRevenueEGP-100) > 1 {
		t.Fatalf("jan target want ~100 got %v (share=%v)", months[0].TargetRevenueEGP, months[0].SeasonalitySharePct)
	}
	if math.Abs(months[11].TargetRevenueEGP-1200) > 1 {
		t.Fatalf("dec target want ~1200 got %v", months[11].TargetRevenueEGP)
	}
	if months[11].SeasonalitySharePct <= months[0].SeasonalitySharePct {
		t.Fatalf("dec share should exceed jan: jan=%v dec=%v", months[0].SeasonalitySharePct, months[11].SeasonalitySharePct)
	}
}

func TestBuildSellOutMonthlyPhasingPartialPriorNeutralMissing(t *testing.T) {
	c := NewClient("test-project", "test-dataset", true)
	c.mu.Lock()
	defer c.mu.Unlock()

	tenant := "tenant-adeco"
	// Jan–Apr 2025 only
	for m, rev := range []float64{100, 200, 150, 50} {
		c.records = append(c.records, domain.SellOutFact{
			TenantID: tenant, RetailerChain: "fathalla", IsOwnBrand: true,
			TransactionDate: "2025-" + pad2(m+1) + "-10",
			NetRevenue:      rev, QuantitySold: int(rev),
		})
	}
	trec := domain.TargetRecord{
		ID: "t-part", TenantID: tenant, TargetType: "sell_out",
		RetailerChain: "fathalla", Year: 2026, Month: 0,
		BranchName: "كل الفروع", Category: "كل الفئات",
	}
	months := c.buildSellOutMonthlyPhasingLocked(normalizeTenantKey(tenant), trec, 12000, 120)
	// May–Dec neutral → share 1/12 → target 1000
	for m := 5; m <= 12; m++ {
		if math.Abs(months[m-1].SeasonalitySharePct-8.3) > 0.15 {
			t.Fatalf("month %d share want ~8.3 got %v", m, months[m-1].SeasonalitySharePct)
		}
		if math.Abs(months[m-1].TargetRevenueEGP-1000) > 2 {
			t.Fatalf("month %d target want ~1000 got %v", m, months[m-1].TargetRevenueEGP)
		}
	}
	// Feb was heaviest among avail → highest target among Jan–Apr
	if months[1].TargetRevenueEGP <= months[0].TargetRevenueEGP {
		t.Fatalf("feb should exceed jan: %v vs %v", months[1].TargetRevenueEGP, months[0].TargetRevenueEGP)
	}
}

func TestBuildSellOutMonthlyPhasingBranchFallsBackToChain(t *testing.T) {
	c := NewClient("test-project", "test-dataset", true)
	c.mu.Lock()
	defer c.mu.Unlock()

	tenant := "tenant-adeco"
	// Chain has 2025 seasonality; new branch has none
	c.records = []domain.SellOutFact{
		{
			TenantID: tenant, RetailerChain: "fathalla", IsOwnBrand: true,
			StoreID: "old", StoreName: "قديم", TransactionDate: "2025-01-15",
			NetRevenue: 100, QuantitySold: 10,
		},
		{
			TenantID: tenant, RetailerChain: "fathalla", IsOwnBrand: true,
			StoreID: "old", StoreName: "قديم", TransactionDate: "2025-06-15",
			NetRevenue: 500, QuantitySold: 50,
		},
		{
			TenantID: tenant, RetailerChain: "fathalla", IsOwnBrand: true,
			StoreID: "new", StoreName: "جديد", TransactionDate: "2026-02-15",
			NetRevenue: 50, QuantitySold: 5,
		},
	}
	trec := domain.TargetRecord{
		ID: "t-br", TenantID: tenant, TargetType: "sell_out",
		RetailerChain: "fathalla", Year: 2026, Month: 0,
		BranchName: "كل الفروع", Category: "كل الفئات",
	}
	chain := c.buildSellOutMonthlyPhasingLocked(normalizeTenantKey(tenant), trec, 12000, 120)
	branch := c.buildSellOutMonthlyPhasingFilteredLocked(normalizeTenantKey(tenant), trec, 12000, 120, "new")
	// New branch has no Y-1 → same shares as chain
	for i := 0; i < 12; i++ {
		if math.Abs(branch[i].SeasonalitySharePct-chain[i].SeasonalitySharePct) > 0.05 {
			t.Fatalf("month %d branch share %v != chain %v", i+1, branch[i].SeasonalitySharePct, chain[i].SeasonalitySharePct)
		}
	}
	if !branch[1].HasActuals || branch[1].ActualRevenueEGP != 50 {
		t.Fatalf("feb actual for new branch %+v", branch[1])
	}
}

func TestBuildSellOutMonthlyPhasingSingleMonth(t *testing.T) {
	c := NewClient("test-project", "test-dataset", true)
	c.mu.Lock()
	defer c.mu.Unlock()

	trec := domain.TargetRecord{
		ID:            "t-mar",
		TenantID:      "tenant-adeco",
		TargetType:    "sell_out",
		RetailerChain: "fathalla",
		Year:          2026,
		Month:         3,
		BranchName:    "كل الفروع",
		Category:      "كل الفئات",
	}
	months := c.buildSellOutMonthlyPhasingLocked(normalizeTenantKey("tenant-adeco"), trec, 5000, 50)
	if len(months) != 1 {
		t.Fatalf("expected 1 month, got %d", len(months))
	}
	if months[0].Month != 3 {
		t.Fatalf("want month 3 got %d", months[0].Month)
	}
	if months[0].TargetRevenueEGP != 5000 {
		t.Fatalf("want target 5000 got %v", months[0].TargetRevenueEGP)
	}
	if months[0].SeasonalitySharePct != 100 {
		t.Fatalf("single month share want 100 got %v", months[0].SeasonalitySharePct)
	}
}

func pad2(m int) string { return fmt.Sprintf("%02d", m) }
