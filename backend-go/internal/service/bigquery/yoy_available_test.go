package bigquery

import (
	"context"
	"fmt"
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

// Owner fixture: 2026 Jan–Oct vs 2025 Jan–Apr must compare Jan–Apr only
// (+26.1% revenue / +15.6% units). Full 2026 stays larger for display totals.
func TestStoreBenchmarkYoYLikeForLikePartialPriorYear(t *testing.T) {
	ctx := context.Background()
	c := NewClient("p", "d", true)
	tn := "tenant-yoy-l4l"
	const (
		prevRev   = 32179040.57
		prevUnits = 476948
		curRev    = 40564794.35
		curUnits  = 551555
		// Extra 2026 May–Oct mass so a naive full-year YoY looks like ~+295%.
		extraRev   = 86575205.65
		extraUnits = 700000
	)
	facts := []domain.SellOutFact{
		yoyFact(tn, "p1", "2025-01-15", prevRev/4, prevUnits/4),
		yoyFact(tn, "p2", "2025-02-15", prevRev/4, prevUnits/4),
		yoyFact(tn, "p3", "2025-03-15", prevRev/4, prevUnits/4),
		yoyFact(tn, "p4", "2025-04-15", prevRev-3*(prevRev/4), prevUnits-3*(prevUnits/4)),
		yoyFact(tn, "c1", "2026-01-15", curRev/4, curUnits/4),
		yoyFact(tn, "c2", "2026-02-15", curRev/4, curUnits/4),
		yoyFact(tn, "c3", "2026-03-15", curRev/4, curUnits/4),
		yoyFact(tn, "c4", "2026-04-15", curRev-3*(curRev/4), curUnits-3*(curUnits/4)),
	}
	for i, mo := range []string{"05", "06", "07", "08", "09", "10"} {
		facts = append(facts, yoyFact(tn, fmt.Sprintf("x%d", i),
			fmt.Sprintf("2026-%s-15", mo), extraRev/6, extraUnits/6))
	}
	if err := c.ReplaceTenantFacts(ctx, tn, facts); err != nil {
		t.Fatal(err)
	}
	sumRevUnits := func(f StoreMatrixFilter) (float64, int) {
		items, err := c.GetStoreBenchmarkMatrix(ctx, tn, f)
		if err != nil {
			t.Fatal(err)
		}
		var rev float64
		var units int
		for _, it := range items {
			rev += it.TotalRevenue
			units += it.TotalUnits
		}
		return rev, units
	}
	fullCur, _ := sumRevUnits(StoreMatrixFilter{Year: 2026})
	if fullCur < curRev+extraRev-1 {
		t.Fatalf("full 2026 display total should include May–Oct: got %v", fullCur)
	}
	// Both directions of same_months_as → Jan–Apr intersection.
	prevL4L, prevU := sumRevUnits(StoreMatrixFilter{Year: 2025, SameMonthsAsYear: 2026})
	curL4L, curU := sumRevUnits(StoreMatrixFilter{Year: 2026, SameMonthsAsYear: 2025})
	if math.Abs(prevL4L-prevRev) > 0.5 || prevU != prevUnits {
		t.Fatalf("prev like-for-like: want %v/%d got %v/%d", prevRev, prevUnits, prevL4L, prevU)
	}
	if math.Abs(curL4L-curRev) > 0.5 || curU != curUnits {
		t.Fatalf("cur like-for-like: want %v/%d got %v/%d", curRev, curUnits, curL4L, curU)
	}
	revYoY := math.Round(((curL4L-prevL4L)/prevL4L)*1000) / 10
	unitsYoY := math.Round(((float64(curU)-float64(prevU))/float64(prevU))*1000) / 10
	if math.Abs(revYoY-26.1) > 0.05 {
		t.Fatalf("revenue YoY: want ~+26.1 got %v", revYoY)
	}
	if math.Abs(unitsYoY-15.6) > 0.05 {
		t.Fatalf("units YoY: want ~+15.6 got %v", unitsYoY)
	}
	// ExecutiveKPIs must use the same intersection (not full Jan–Oct vs Jan–Apr).
	k, err := c.GetExecutiveKPIs(ctx, tn, "CUSTOM", "2026-01-01", "2026-10-31")
	if err != nil {
		t.Fatal(err)
	}
	if !k.YoYAvailable || math.Abs(k.RevenueYoYPct-26.1) > 0.05 {
		t.Fatalf("GetExecutiveKPIs revenue YoY: want ~+26.1 available, got %v available=%v", k.RevenueYoYPct, k.YoYAvailable)
	}
	if math.Abs(k.UnitsYoYPct-15.6) > 0.05 {
		t.Fatalf("GetExecutiveKPIs units YoY: want ~+15.6 got %v", k.UnitsYoYPct)
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
