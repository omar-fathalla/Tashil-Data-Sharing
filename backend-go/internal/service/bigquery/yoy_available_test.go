package bigquery

import (
	"context"
	"math"
	"testing"

	"github.com/tashil/data-sharing/backend/internal/domain"
)

// Made-up fixture numbers only.
func yoyFact(tenant, id, date string, rev float64, units int) domain.SellOutFact {
	return domain.SellOutFact{
		RecordID: id, TenantID: tenant, RetailerChain: "gomla", StoreID: "gomla_s1",
		StoreName: "فرع 1", Barcode: "6220000000001", SKUName: "Item 1",
		QuantitySold: units, NetRevenue: rev, TransactionDate: date, IsOwnBrand: true,
	}
}

func TestExecutiveKPIsYoYAvailableFlag(t *testing.T) {
	ctx := context.Background()
	c := NewClient("p", "d", true)

	none := "tenant-yoy-none"
	if err := c.ReplaceTenantFacts(ctx, none, []domain.SellOutFact{
		yoyFact(none, "a1", "2026-01-10", 1000, 10),
		yoyFact(none, "a2", "2026-02-10", 2000, 20),
	}); err != nil {
		t.Fatal(err)
	}
	k, err := c.GetExecutiveKPIs(ctx, none, "ALL")
	if err != nil {
		t.Fatal(err)
	}
	if k.YoYAvailable || k.RevenueYoYPct != 0 || k.UnitsYoYPct != 0 {
		t.Fatalf("no last-year data: want yoy_available=false and 0%%, got %v %v %v", k.YoYAvailable, k.RevenueYoYPct, k.UnitsYoYPct)
	}

	some := "tenant-yoy-some"
	if err := c.ReplaceTenantFacts(ctx, some, []domain.SellOutFact{
		yoyFact(some, "b0", "2025-01-10", 1000, 10),
		yoyFact(some, "b1", "2026-01-10", 1500, 15),
	}); err != nil {
		t.Fatal(err)
	}
	k, err = c.GetExecutiveKPIs(ctx, some, "ALL")
	if err != nil {
		t.Fatal(err)
	}
	if !k.YoYAvailable || math.Abs(k.RevenueYoYPct-50) > 0.05 {
		t.Fatalf("Jan 2026 vs Jan 2025: want yoy_available=true and +50%%, got %v %v", k.YoYAvailable, k.RevenueYoYPct)
	}
}

func TestStoreBenchmarkSameMonthsAsYear(t *testing.T) {
	ctx := context.Background()
	c := NewClient("p", "d", true)
	tn := "tenant-yoy-matrix"
	if err := c.ReplaceTenantFacts(ctx, tn, []domain.SellOutFact{
		yoyFact(tn, "p1", "2025-01-10", 100, 1),
		yoyFact(tn, "p2", "2025-02-10", 100, 1),
		yoyFact(tn, "p3", "2025-03-10", 100, 1),
		yoyFact(tn, "p4", "2025-12-10", 100, 1),
		yoyFact(tn, "c1", "2026-01-10", 300, 3),
		yoyFact(tn, "c2", "2026-02-10", 300, 3),
	}); err != nil {
		t.Fatal(err)
	}
	sum := func(f StoreMatrixFilter) float64 {
		items, err := c.GetStoreBenchmarkMatrix(ctx, tn, f)
		if err != nil {
			t.Fatal(err)
		}
		s := 0.0
		for _, it := range items {
			s += it.TotalRevenue
		}
		return s
	}
	if got := sum(StoreMatrixFilter{Year: 2025}); math.Abs(got-400) > 0.01 {
		t.Fatalf("full 2025: want 400 got %v", got)
	}
	if got := sum(StoreMatrixFilter{Year: 2025, SameMonthsAsYear: 2026}); math.Abs(got-200) > 0.01 {
		t.Fatalf("2025 limited to 2026's months (Jan+Feb): want 200 got %v", got)
	}
	// A picked month wins over the same-months set.
	if got := sum(StoreMatrixFilter{Year: 2025, Month: 3, SameMonthsAsYear: 2026}); math.Abs(got-100) > 0.01 {
		t.Fatalf("explicit month: want 100 got %v", got)
	}
}

func TestCPFRMatchedYoYSameMonthsOnly(t *testing.T) {
	ctx := context.Background()
	run := func(withLastYear bool) *domain.CPFRDashboardPayload {
		c := NewClient("p", "d", true)
		pm, _ := c.LookupProductMaster("tenant-adeco", "", "6223000230015", "كلوريل أبيض 1050 جم")
		f := func(id, d string, q int, v float64) domain.SellOutFact {
			return domain.SellOutFact{RecordID: id, TenantID: "tenant-adeco", RetailerChain: "fathalla",
				StoreID: "fat_smouha", StoreName: "سموحة", Barcode: "6223000230015", SKUName: "كلوريل أبيض 1050 جم",
				QuantitySold: q, NetRevenue: v, UnitPrice: v / float64(q), TransactionDate: d, IsOwnBrand: true}
		}
		facts := []domain.SellOutFact{f("j26", "2026-01-15", 120, 3000), f("f26", "2026-02-15", 480, 12000)}
		if withLastYear {
			facts = append(facts, f("j25", "2025-01-15", 100, 2000)) // only Jan has last-year data
		}
		_ = c.ReplaceTenantFacts(ctx, "tenant-adeco", facts)
		si := func(id string, m int) domain.SellInRecord {
			return domain.SellInRecord{RecordID: id, TenantID: "tenant-adeco", RetailerChain: "fathalla", Year: 2026, MonthNum: m,
				RegionCode: "ALX", Governorate: "الإسكندرية", Sector: "MT", Brand: "كلوريل (Clorel)", ItemCode: pm.ItemCode,
				Barcode: "6223000230015", ItemName: pm.OfficialName, PromotionType: "عادي", NetQtyCases: 60, NetValueEGP: 9000}
		}
		_ = c.SetSellInRecords(ctx, "tenant-adeco", "plan_2026.xlsx", []domain.SellInRecord{si("s1", 1), si("s2", 2)})
		p, err := c.GetCPFRDashboard(ctx, "tenant-adeco", CPFRFilter{RetailerChain: "fathalla", Year: 2026})
		if err != nil {
			t.Fatal(err)
		}
		return p
	}

	p := run(true)
	var jan *domain.ReconciliationMonthItem
	for i := range p.MonthlyReconciliation {
		if p.MonthlyReconciliation[i].Year == 2026 && p.MonthlyReconciliation[i].MonthNum == 1 {
			jan = &p.MonthlyReconciliation[i]
		}
	}
	if jan == nil || jan.PrevYearSellOutValueEGP <= 0 {
		t.Fatalf("expected Jan 2026 with last-year Sell-Out, got %+v", jan)
	}
	want := math.Round((jan.SellOutValueEGP-jan.PrevYearSellOutValueEGP)/jan.PrevYearSellOutValueEGP*10000) / 100
	if !p.MatchedYoYAvailable || math.Abs(p.MatchedYoYValueGrowthPct-want) > 0.02 {
		t.Fatalf("matched YoY must compare Jan only (Feb has no 2025): want %v got %v (available=%v)",
			want, p.MatchedYoYValueGrowthPct, p.MatchedYoYAvailable)
	}

	p = run(false)
	if p.MatchedYoYAvailable || p.MatchedYoYValueGrowthPct != 0 {
		t.Fatalf("no last-year data: want matched_yoy_available=false, got %v %v", p.MatchedYoYAvailable, p.MatchedYoYValueGrowthPct)
	}
}
