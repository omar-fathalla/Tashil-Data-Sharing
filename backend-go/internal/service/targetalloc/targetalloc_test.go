package targetalloc

import (
	"math"
	"math/rand"
	"strings"
	"testing"

	"github.com/tashil/data-sharing/backend/internal/domain"
)

func sum(v []int64) int64 {
	var s int64
	for _, x := range v {
		s += x
	}
	return s
}

func TestApportionSumsExactly(t *testing.T) {
	cases := []struct {
		total   int64
		weights []int64
	}{
		{150_000_000, []int64{1, 1, 1}},
		{100, []int64{1, 1, 1}},
		{7, []int64{3, 3, 3, 3}},
		{150_000_000, []int64{1184494100, 532424225, 497906544, 400579325, 343668305}},
		{1, []int64{5, 5}},
		{0, []int64{5, 5}},
	}
	for _, c := range cases {
		got := Apportion(c.total, c.weights)
		if sum(got) != c.total {
			t.Errorf("total %d weights %v: parts %v sum to %d", c.total, c.weights, got, sum(got))
		}
	}
	got := Apportion(100, []int64{1, 1, 1})
	if got[0] != 34 || got[1] != 33 || got[2] != 33 {
		t.Errorf("tie must go to the lowest index first, got %v", got)
	}
}

func TestApportionRandomisedExactSum(t *testing.T) {
	rng := rand.New(rand.NewSource(7))
	for i := 0; i < 500; i++ {
		n := 1 + rng.Intn(60)
		w := make([]int64, n)
		for j := range w {
			w[j] = int64(rng.Intn(10_000_000))
		}
		total := int64(rng.Intn(1_000_000_000_000))
		got := Apportion(total, w)
		anyPositive := false
		for _, x := range w {
			if x > 0 {
				anyPositive = true
			}
		}
		want := total
		if !anyPositive {
			want = 0
		}
		if sum(got) != want {
			t.Fatalf("iteration %d: sum %d want %d", i, sum(got), want)
		}
		for j := range got {
			if w[j] <= 0 && got[j] != 0 {
				t.Fatalf("zero weight got %d", got[j])
			}
		}
	}
}

func TestApportionIgnoresNonPositiveWeights(t *testing.T) {
	got := Apportion(10, []int64{0, -5, 1})
	if got[0] != 0 || got[1] != 0 || got[2] != 10 {
		t.Errorf("got %v", got)
	}
	if s := sum(Apportion(10, []int64{0, 0})); s != 0 {
		t.Errorf("no positive weight must allocate nothing, got %d", s)
	}
}

func cov(months ...string) []MonthCoverage {
	out := make([]MonthCoverage, len(months))
	for i, m := range months {
		out[i] = MonthCoverage{Month: m, Rows: 10}
	}
	return out
}

func TestResolveBaselinePriorYear(t *testing.T) {
	all2025 := []string{"2025-01", "2025-02", "2025-03", "2025-04", "2025-05", "2025-06", "2025-07", "2025-08", "2025-09", "2025-10", "2025-11", "2025-12"}
	b := ResolveBaseline(2026, 0, cov(append(all2025, "2026-01", "2026-02")...))
	if b.Kind != KindPriorYear || b.Year != 2025 || b.Partial || b.FallbackUsed {
		t.Fatalf("2026 target must use full 2025: %+v", b)
	}
	if b.Window.Start != "2025-01-01" || b.Window.End != "2025-12-31" {
		t.Errorf("window %+v", b.Window)
	}
	if got := b.CaptionAr(); got != "التوزيع حسب حصة كل فرع وصنف من مبيعات 2025." {
		t.Errorf("caption %q", got)
	}
}

func TestResolveBaselineFutureYearUsesLatestYear(t *testing.T) {
	b := ResolveBaseline(2027, 0, cov("2025-01", "2025-02", "2026-01", "2026-02", "2026-10"))
	if b.Kind != KindPriorYear || b.Year != 2026 || !b.Partial || b.MonthsCovered != 3 {
		t.Fatalf("2027 target must use 2026: %+v", b)
	}
	if !strings.Contains(b.CaptionAr(), "مبيعات 2026") || !strings.Contains(b.CaptionAr(), "3 أشهر فقط") {
		t.Errorf("caption must flag partial coverage: %q", b.CaptionAr())
	}
}

func TestResolveBaselinePartialPriorYear(t *testing.T) {
	b := ResolveBaseline(2026, 0, cov("2025-01", "2025-02", "2025-03", "2025-04", "2026-05"))
	if b.Kind != KindPriorYear || !b.Partial || b.MonthsCovered != 4 {
		t.Fatalf("%+v", b)
	}
	if got := b.CaptionAr(); !strings.Contains(got, "(4 أشهر فقط: يناير – أبريل 2025)") {
		t.Errorf("caption %q", got)
	}
}

func TestResolveBaselineMonthlyTarget(t *testing.T) {
	b := ResolveBaseline(2026, 3, cov("2025-02", "2025-03", "2025-04"))
	if b.Kind != KindPriorYearMonth || b.Window.Start != "2025-03-01" || b.Window.End != "2025-03-31" {
		t.Fatalf("%+v", b)
	}
	if !strings.Contains(b.CaptionAr(), "مبيعات مارس 2025") {
		t.Errorf("caption %q", b.CaptionAr())
	}
	// Same month missing in the prior year: use the whole prior year and say so.
	b = ResolveBaseline(2026, 7, cov("2025-02", "2025-03"))
	if b.Kind != KindPriorYear || !b.FallbackUsed {
		t.Fatalf("%+v", b)
	}
	if !strings.Contains(b.CaptionAr(), "لا توجد مبيعات في يوليو 2025") {
		t.Errorf("caption %q", b.CaptionAr())
	}
}

func TestResolveBaselineTrailingTwelveMonths(t *testing.T) {
	var months []string
	for m := 1; m <= 10; m++ {
		months = append(months, "2026-"+pad2(m))
	}
	months = append(months, "2024-05") // older, outside the 12-month window
	b := ResolveBaseline(2026, 0, cov(months...))
	if b.Kind != KindTrailing12M || !b.FallbackUsed {
		t.Fatalf("no 2025 data must fall back to trailing months: %+v", b)
	}
	if b.Window.Start != "2025-11-01" || b.Window.End != "2026-10-31" {
		t.Errorf("window %+v", b.Window)
	}
	if b.MonthsCovered != 10 || !b.Partial {
		t.Errorf("months covered %d partial %v", b.MonthsCovered, b.Partial)
	}
	if !strings.Contains(b.CaptionAr(), "لا توجد مبيعات في العام السابق") || !strings.Contains(b.CaptionAr(), "آخر 10 أشهر متاحة") {
		t.Errorf("caption %q", b.CaptionAr())
	}
}

func pad2(m int) string {
	if m < 10 {
		return "0" + string(rune('0'+m))
	}
	return string(rune('0'+m/10)) + string(rune('0'+m%10))
}

func TestResolveBaselineNone(t *testing.T) {
	b := ResolveBaseline(2026, 0, nil)
	if b.Kind != KindNone || b.Window.Valid() {
		t.Fatalf("%+v", b)
	}
	if b.CaptionAr() == "" {
		t.Error("caption must explain the missing baseline")
	}
	if b := ResolveBaseline(2026, 0, []MonthCoverage{{Month: "2025-01", Rows: 0}}); b.Kind != KindNone {
		t.Errorf("zero-row months must not count: %+v", b)
	}
}

func TestActualWindow(t *testing.T) {
	if w := ActualWindow(2027, 0); w.Start != "2027-01-01" || w.End != "2027-12-31" {
		t.Errorf("%+v", w)
	}
	if w := ActualWindow(2028, 2); w.Start != "2028-02-01" || w.End != "2028-02-29" {
		t.Errorf("leap February: %+v", w)
	}
}

func row(store, storeName, sku, skuName string, baseRev float64, baseUnits int64, actRev float64, actUnits int64) Row {
	r := Row{
		StoreKey: store, StoreID: store, StoreName: storeName, SKUKey: sku, SKUName: skuName, Category: "عناية",
		UnitsPerCarton: 12, BaseRev: baseRev, BaseUnits: baseUnits, ActRev: actRev, ActUnits: actUnits,
	}
	if actRev != 0 || actUnits != 0 {
		r.ActRows = 1
	}
	return r
}

func target(rev float64) domain.TargetRecord {
	return domain.TargetRecord{
		ID: "t1", TargetType: "sell_out", RetailerChain: "fathalla", ChainDisplayName: "أسواق فتح الله",
		Year: 2026, BranchName: "كل الفروع", Category: "كل الفئات", TargetRevenueEGP: rev, TargetUnits: 250000,
	}
}

func input(rev float64, rows []Row) Input {
	return Input{
		Target: target(rev), Rows: rows, ActualWindow: ActualWindow(2026, 0), Source: "test",
		Baseline: ResolveBaseline(2026, 0, cov("2025-01", "2025-02")),
	}
}

func branchSum(r domain.TargetBreakdownResponse) float64 {
	var s float64
	for _, b := range r.Branches {
		s += b.AllocatedTargetEGP
	}
	return s
}

func TestBuildTotalsEqualTargetExactly(t *testing.T) {
	// Three branches with identical baselines: 100 / 3 cannot split evenly, yet the sum must be exact.
	rows := []Row{
		row("b1", "فرع 1", "s1", "A", 1000, 10, 400, 4),
		row("b2", "فرع 2", "s1", "A", 1000, 10, 300, 3),
		row("b3", "فرع 3", "s1", "A", 1000, 10, 200, 2),
	}
	r := Build(input(100, rows))
	if got := branchSum(r); got != 100 {
		t.Fatalf("branch allocations sum to %v, want exactly 100: %+v", got, r.Branches)
	}
	if r.Branches[0].AllocatedTargetEGP != 34 || r.Branches[1].AllocatedTargetEGP != 33 || r.Branches[2].AllocatedTargetEGP != 33 {
		t.Errorf("largest remainder, ties by position: %v %v %v",
			r.Branches[0].AllocatedTargetEGP, r.Branches[1].AllocatedTargetEGP, r.Branches[2].AllocatedTargetEGP)
	}
	if r.AllocationGranularityEG != 1 {
		t.Errorf("whole-pound target allocates in whole pounds, got %v", r.AllocationGranularityEG)
	}
}

func TestBuildLargeTargetExactSumAndSKUsAddToBranch(t *testing.T) {
	var rows []Row
	branches := []string{"b1", "b2", "b3", "b4", "b5", "b6", "b7"}
	for i, b := range branches {
		for j := 0; j < 9; j++ {
			rev := float64(1000+i*137+j*53) + 0.37*float64(j+1)
			rows = append(rows, row(b, "فرع "+b, "s"+string(rune('a'+j)), "SKU "+string(rune('a'+j)), rev, int64(10+j), rev/2, int64(5+j)))
		}
	}
	r := Build(input(150_000_000, rows))
	if got := branchSum(r); got != 150_000_000 {
		t.Fatalf("branches sum %v, want 150000000", got)
	}
	for _, b := range r.Branches {
		var s float64
		for _, k := range b.SKUs {
			s += k.AllocatedTargetEGP
		}
		if math.Abs(s-b.AllocatedTargetEGP) > 1e-6 {
			t.Errorf("branch %s: SKUs sum %v != branch %v", b.BranchName, s, b.AllocatedTargetEGP)
		}
	}
	var sharePct float64
	for _, b := range r.Branches {
		sharePct += b.SharePct
	}
	if math.Abs(sharePct-100) > 0.01 {
		t.Errorf("shares sum to %v", sharePct)
	}
}

func TestBuildFractionalTargetUsesCents(t *testing.T) {
	rows := []Row{
		row("b1", "فرع 1", "s1", "A", 100, 10, 0, 0),
		row("b2", "فرع 2", "s1", "A", 100, 10, 0, 0),
		row("b3", "فرع 3", "s1", "A", 100, 10, 0, 0),
	}
	r := Build(input(1000.01, rows))
	if r.AllocationGranularityEG != 0.01 {
		t.Fatalf("granularity %v", r.AllocationGranularityEG)
	}
	if got := math.Round(branchSum(r)*100) / 100; got != 1000.01 {
		t.Errorf("sum %v want 1000.01", got)
	}
}

func TestBuildProportionalToBaseline(t *testing.T) {
	rows := []Row{
		row("b1", "فرع 1", "s1", "A", 750, 75, 100, 10),
		row("b2", "فرع 2", "s1", "A", 250, 25, 100, 10),
	}
	r := Build(input(1000, rows))
	if r.Branches[0].BranchKey != "b1" || r.Branches[0].AllocatedTargetEGP != 750 || r.Branches[1].AllocatedTargetEGP != 250 {
		t.Fatalf("%+v", r.Branches)
	}
	if r.Branches[0].SharePct != 75 {
		t.Errorf("share %v", r.Branches[0].SharePct)
	}
}

func TestBuildZeroBaselineBranchAndSKUGoToNoHistory(t *testing.T) {
	rows := []Row{
		row("b1", "فرع 1", "s1", "A", 600, 60, 300, 30),
		row("b1", "فرع 1", "s2", "B", 400, 40, 100, 10),
		row("b1", "فرع 1", "s3", "جديد", 0, 0, 50, 5),
		row("b2", "فرع جديد", "s1", "A", 0, 0, 70, 7),
		row("b3", "فرع بلا شيء", "s1", "A", 0, 0, 0, 0),
	}
	r := Build(input(2000, rows))
	if len(r.Branches) != 1 || r.Branches[0].BranchKey != "b1" {
		t.Fatalf("only branches with baseline get an allocation: %+v", r.Branches)
	}
	if r.Branches[0].AllocatedTargetEGP != 2000 || branchSum(r) != 2000 {
		t.Errorf("the single branch carries the whole target: %+v", r.Branches[0])
	}
	if len(r.Branches[0].SKUs) != 2 {
		t.Fatalf("zero-baseline SKU must not appear in the allocation table: %+v", r.Branches[0].SKUs)
	}
	var kinds []string
	for _, n := range r.NoHistory {
		kinds = append(kinds, n.Kind+":"+n.BranchKey+":"+n.SKUKey)
	}
	if len(r.NoHistory) != 2 {
		t.Fatalf("want 1 branch + 1 SKU entry, got %v", kinds)
	}
	// branch b1 actual includes the new SKU so it reconciles with the target row.
	if r.Branches[0].ActualRevenueEGP != 450 {
		t.Errorf("branch actual %v want 450", r.Branches[0].ActualRevenueEGP)
	}
	if r.ActualRevenueEGP != 520 || r.NoHistoryActualEGP != 120 {
		t.Errorf("totals actual %v no-history %v", r.ActualRevenueEGP, r.NoHistoryActualEGP)
	}
	for _, k := range r.Branches[0].SKUs {
		if k.AllocatedTargetEGP <= 0 {
			t.Errorf("no fake zero rows in the allocation table: %+v", k)
		}
	}
}

func TestBuildNoBaselineAllocatesNothing(t *testing.T) {
	rows := []Row{row("b1", "فرع 1", "s1", "A", 0, 0, 100, 10)}
	r := Build(input(500, rows))
	if len(r.Branches) != 0 || branchSum(r) != 0 {
		t.Fatalf("nothing may be invented without a baseline: %+v", r.Branches)
	}
	if len(r.NoHistory) != 1 || r.NoHistory[0].Kind != "branch" {
		t.Errorf("%+v", r.NoHistory)
	}
}

func TestBuildFutureYearHasNoActuals(t *testing.T) {
	rows := []Row{
		row("b1", "فرع 1", "s1", "A", 800, 80, 0, 0),
		row("b2", "فرع 2", "s1", "A", 200, 20, 0, 0),
	}
	in := input(1000, rows)
	in.Target.Year = 2027
	in.ActualWindow = ActualWindow(2027, 0)
	r := Build(in)
	if r.HasActuals {
		t.Fatal("a future year has no actual rows")
	}
	if r.AchievementPct != nil {
		t.Errorf("achievement must be nil (rendered as —), got %v", *r.AchievementPct)
	}
	for _, b := range r.Branches {
		if b.AchievementPct != nil {
			t.Errorf("branch achievement must be nil: %+v", b)
		}
		for _, k := range b.SKUs {
			if k.AchievementPct != nil {
				t.Errorf("sku achievement must be nil: %+v", k)
			}
		}
	}
	if r.GapEGP != 0 {
		t.Errorf("gap is not meaningful without actuals, got %v", r.GapEGP)
	}
	if branchSum(r) != 1000 {
		t.Errorf("a future-year target is still allocated in full: %v", branchSum(r))
	}
}

func TestBuildAchievementAndGap(t *testing.T) {
	rows := []Row{
		row("b1", "فرع 1", "s1", "A", 500, 50, 300, 30),
		row("b2", "فرع 2", "s1", "A", 500, 50, 800, 80),
	}
	r := Build(input(1000, rows))
	if !r.HasActuals || r.AchievementPct == nil || *r.AchievementPct != 110 {
		t.Fatalf("overall achievement %+v", r.AchievementPct)
	}
	if r.GapEGP != 100 {
		t.Errorf("gap %v", r.GapEGP)
	}
	var b1 domain.TargetBreakdownBranch
	for _, b := range r.Branches {
		if b.BranchKey == "b1" {
			b1 = b
		}
	}
	if b1.AchievementPct == nil || *b1.AchievementPct != 60 || b1.GapEGP != -200 {
		t.Errorf("b1 %+v", b1)
	}
}

func TestBuildUnitsAndCartonsFromBaselinePrice(t *testing.T) {
	rows := []Row{
		row("b1", "فرع 1", "s1", "A", 1000, 100, 0, 0), // price 10
		row("b1", "فرع 1", "s2", "B", 1000, 0, 0, 0),   // revenue but no units, no price anywhere
	}
	rows[1].UnitsPerCarton = 0
	r := Build(input(2000, rows))
	var a, b domain.TargetBreakdownSKU
	for _, k := range r.Branches[0].SKUs {
		if k.SKUKey == "s1" {
			a = k
		} else {
			b = k
		}
	}
	if a.AvgUnitPriceEGP == nil || *a.AvgUnitPriceEGP != 10 {
		t.Fatalf("avg price %+v", a.AvgUnitPriceEGP)
	}
	if a.AllocatedUnits == nil || *a.AllocatedUnits != 100 || a.AllocatedCartons == nil || math.Abs(*a.AllocatedCartons-8.33) > 1e-9 {
		t.Errorf("units %+v cartons %+v", a.AllocatedUnits, a.AllocatedCartons)
	}
	if b.AvgUnitPriceEGP != nil || b.AllocatedUnits != nil || b.AllocatedCartons != nil {
		t.Errorf("no price must mean no quantity (—), got %+v", b)
	}
	if r.AllocatedUnitsTotal == nil || *r.AllocatedUnitsTotal != 100 {
		t.Errorf("units total %+v", r.AllocatedUnitsTotal)
	}
}

func TestBuildFallsBackToChainWidePrice(t *testing.T) {
	rows := []Row{
		row("b1", "فرع 1", "s1", "A", 500, 0, 0, 0),
		row("b2", "فرع 2", "s1", "A", 500, 100, 0, 0),
	}
	r := Build(input(1000, rows))
	for _, b := range r.Branches {
		if b.BranchKey == "b1" {
			k := b.SKUs[0]
			if k.AvgUnitPriceEGP == nil || *k.AvgUnitPriceEGP != 10 {
				t.Errorf("chain-wide SKU price expected for a branch without units: %+v", k)
			}
		}
	}
}

func TestBuildRespectsScopeAndExcludesUnattributed(t *testing.T) {
	rows := []Row{
		row("b1", "فرع الرحاب", "s1", "A", 600, 60, 100, 10),
		row("b2", "فرع سموحة", "s1", "A", 400, 40, 100, 10),
		row("", "", "s1", "A", 0, 0, 999, 9),
	}
	in := input(1000, rows)
	in.Target.BranchName = "رحاب"
	r := Build(in)
	if len(r.Branches) != 1 || r.Branches[0].BranchKey != "b1" || r.Branches[0].AllocatedTargetEGP != 1000 {
		t.Fatalf("branch scope must limit the allocation: %+v", r.Branches)
	}
	in.Target.BranchName = "كل الفروع"
	r = Build(in)
	if r.UnattributedActualEGP != 999 {
		t.Errorf("unattributed %v", r.UnattributedActualEGP)
	}
	if r.ActualRevenueEGP != 200 {
		t.Errorf("rows without a branch must not be credited to any branch: actual %v", r.ActualRevenueEGP)
	}
	if !r.HasActuals {
		t.Error("unattributed rows still prove the period has data")
	}
}

func TestBuildCategoryScope(t *testing.T) {
	a := row("b1", "فرع 1", "s1", "A", 500, 50, 10, 1)
	a.Category = "صابون"
	b := row("b1", "فرع 1", "s2", "B", 500, 50, 10, 1)
	b.Category = "شامبو"
	in := input(1000, []Row{a, b})
	in.Target.Category = "شامبو"
	r := Build(in)
	if len(r.Branches) != 1 || len(r.Branches[0].SKUs) != 1 || r.Branches[0].SKUs[0].SKUKey != "s2" {
		t.Fatalf("category scope: %+v", r.Branches)
	}
}

func TestBuildMergesGroupedRowsPerSKU(t *testing.T) {
	// BigQuery groups by category and name too; the same SKU may arrive in several rows.
	rows := []Row{
		row("b1", "فرع 1", "s1", "A", 300, 30, 100, 10),
		row("b1", "فرع 1", "s1", "A صغير", 200, 20, 50, 5),
	}
	r := Build(input(500, rows))
	if len(r.Branches[0].SKUs) != 1 {
		t.Fatalf("rows with one SKU key merge: %+v", r.Branches[0].SKUs)
	}
	k := r.Branches[0].SKUs[0]
	if k.BaselineRevenueEGP != 500 || k.ActualRevenueEGP != 150 || k.SKUName != "A" {
		t.Errorf("%+v", k)
	}
}
