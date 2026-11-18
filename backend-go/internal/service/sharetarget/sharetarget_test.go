package sharetarget

import (
	"math"
	"testing"
)

const million = 1_000_000.0

func fixtureInputs() []CategoryInput {
	rows := WorkedExampleFathalla2026()
	out := make([]CategoryInput, len(rows))
	for i, r := range rows {
		out[i] = CategoryInput{
			Category:         r.Category,
			CurrentSharePct:  r.CurrentSharePct,
			OwnRevenueEGP:    r.OwnM * million,
			MarketRevenueEGP: r.MarketM * million,
			OwnUnits:         r.CurrentUnits,
			AvgPriceEGP:      r.AvgPrice,
		}
	}
	return out
}

func TestWorkedExamplePlus5FlatTenMonth(t *testing.T) {
	// Research fixture: +5pt all 8 categories, flat market, 10-month base → 98.89M → 121.43M.
	opt := Options{MarketGrowthPct: 0, MonthsWithData: 10, Annualize: false}
	sum := PlanAllDelta(fixtureInputs(), 5, opt)

	if math.Abs(sum.TotalOwnEGP/million-98.89) > 0.005 {
		t.Fatalf("own total got %.4fM want 98.89M", sum.TotalOwnEGP/million)
	}
	if math.Abs(sum.TotalTargetEGP/million-121.43) > 0.005 {
		t.Fatalf("target total got %.4fM want 121.43M", sum.TotalTargetEGP/million)
	}
	if math.Abs(sum.TotalUpliftEGP/million-22.54) > 0.01 {
		t.Fatalf("uplift total got %.4fM want 22.54M", sum.TotalUpliftEGP/million)
	}
	if sum.HasShareOver100 {
		t.Fatal("fixture must not block on share>100")
	}
	if !sum.CanProceed() {
		t.Fatal("CanProceed")
	}

	rows := WorkedExampleFathalla2026()
	for i, p := range sum.Categories {
		want := rows[i]
		if math.Abs(p.TargetRevenueEGP/million-want.TargetM) > 0.015 {
			t.Errorf("%s target got %.4fM want %.2fM", want.Category, p.TargetRevenueEGP/million, want.TargetM)
		}
		if math.Abs(p.UpliftRevenueEGP/million-want.UpliftM) > 0.015 {
			t.Errorf("%s uplift got %.4fM want %.2fM", want.Category, p.UpliftRevenueEGP/million, want.UpliftM)
		}
		if math.Abs(p.DesiredSharePct-(want.CurrentSharePct+5)) > 0.15 {
			// desired is rounded to 1 decimal of exact current+5
			t.Errorf("%s desired share got %.1f want ~%.1f", want.Category, p.DesiredSharePct, want.CurrentSharePct+5)
		}
	}
}

func TestAnnualizeTwelveOverTen(t *testing.T) {
	opt := Options{MarketGrowthPct: 0, MonthsWithData: 10, Annualize: true}
	if f := AnnualizationFactor(opt); math.Abs(f-1.2) > 1e-12 {
		t.Fatalf("factor got %v want 1.2", f)
	}
	sum := PlanAllDelta(fixtureInputs(), 5, opt)
	// Own and market scale by 12/10; target scales the same → uplift ratio unchanged.
	if math.Abs(sum.TotalOwnEGP/million-98.89*1.2) > 0.01 {
		t.Fatalf("annualized own got %.4fM want %.4fM", sum.TotalOwnEGP/million, 98.89*1.2)
	}
	if math.Abs(sum.TotalTargetEGP/million-121.43*1.2) > 0.02 {
		t.Fatalf("annualized target got %.4fM want %.4fM", sum.TotalTargetEGP/million, 121.43*1.2)
	}
	if !sum.Annualized || sum.AnnualizationFactor != 1.2 {
		t.Fatalf("annualize flags %+v", sum)
	}
}

func TestShareOver100Blocks(t *testing.T) {
	in := []CategoryInput{{
		Category: "x", CurrentSharePct: 40, OwnRevenueEGP: 40, MarketRevenueEGP: 100, AvgPriceEGP: 10, OwnUnits: 4,
	}}
	sum, err := PlanAll(in, []float64{100.1}, Options{})
	if err != nil {
		t.Fatal(err)
	}
	if !sum.HasShareOver100 || sum.CanProceed() {
		t.Fatalf("must block: %+v", sum)
	}
}

func TestBelowCurrentWarnsOnly(t *testing.T) {
	in := []CategoryInput{{
		Category: "x", CurrentSharePct: 40, OwnRevenueEGP: 40, MarketRevenueEGP: 100, AvgPriceEGP: 10, OwnUnits: 4,
	}}
	sum, err := PlanAll(in, []float64{35}, Options{})
	if err != nil {
		t.Fatal(err)
	}
	if !sum.HasBelowCurrent {
		t.Fatal("expected below-current warning")
	}
	if !sum.CanProceed() {
		t.Fatal("below current must not block")
	}
	if sum.Categories[0].TargetRevenueEGP != 35 {
		t.Fatalf("target %v", sum.Categories[0].TargetRevenueEGP)
	}
}

func TestUnitsFromAvgPrice(t *testing.T) {
	p := PlanCategory(CategoryInput{
		Category: "c", CurrentSharePct: 10, OwnRevenueEGP: 1000, MarketRevenueEGP: 10000,
		OwnUnits: 100, AvgPriceEGP: 10,
	}, 20, Options{})
	if p.TargetRevenueEGP != 2000 {
		t.Fatalf("rev %v", p.TargetRevenueEGP)
	}
	if p.TargetUnits != 200 {
		t.Fatalf("units %v", p.TargetUnits)
	}
}

func TestCascadeHistoricalBranchAndEvenMonths(t *testing.T) {
	plan := PlanCategory(CategoryInput{
		Category: "صابون", CurrentSharePct: 39, OwnRevenueEGP: 100, MarketRevenueEGP: 250,
		OwnUnits: 10, AvgPriceEGP: 10,
	}, 44, Options{})
	// Target = 0.44*250 = 110, uplift = 10.
	branches := []BranchWeight{
		{BranchKey: "a", BranchName: "A", OwnRevenue: 70},
		{BranchKey: "b", BranchName: "B", OwnRevenue: 30},
	}
	skus := map[string][]SKUWeight{
		"a": {
			{SKUKey: "s1", SKUName: "S1", OwnRevenue: 50, AvgPrice: 10},
			{SKUKey: "s2", SKUName: "S2", OwnRevenue: 20, AvgPrice: 10},
		},
		"b": {
			{SKUKey: "s3", SKUName: "S3", OwnRevenue: 30, AvgPrice: 10},
		},
	}
	casc := CascadeCategory(plan, branches, skus, nil)
	if len(casc.Branches) != 2 {
		t.Fatalf("branches %d", len(casc.Branches))
	}
	var upliftSum float64
	for _, b := range casc.Branches {
		upliftSum += b.UpliftEGP
	}
	if math.Abs(upliftSum-plan.UpliftRevenueEGP) > 0.02 {
		t.Fatalf("uplift parts %v want %v", upliftSum, plan.UpliftRevenueEGP)
	}
	// A gets 70% of uplift 10 → 7; target 77. B gets 3; target 33.
	byKey := map[string]BranchAllocation{}
	for _, b := range casc.Branches {
		byKey[b.BranchKey] = b
	}
	if math.Abs(byKey["a"].UpliftEGP-7) > 0.02 || math.Abs(byKey["b"].UpliftEGP-3) > 0.02 {
		t.Fatalf("branch uplifts A=%v B=%v", byKey["a"].UpliftEGP, byKey["b"].UpliftEGP)
	}
	if len(byKey["a"].SKUs) != 2 {
		t.Fatalf("skus A %d", len(byKey["a"].SKUs))
	}
	if len(casc.Months) != 12 {
		t.Fatalf("months %d", len(casc.Months))
	}
	var monthSum float64
	for _, m := range casc.Months {
		monthSum += m.TargetEGP
	}
	if math.Abs(monthSum-plan.TargetRevenueEGP) > 0.02 {
		t.Fatalf("month sum %v want %v", monthSum, plan.TargetRevenueEGP)
	}
	// Even split → ~8.3% each
	if math.Abs(casc.Months[0].SharePct-8.3) > 0.1 {
		t.Fatalf("even month share %v", casc.Months[0].SharePct)
	}
}

func TestCascadeSeasonalityWeights(t *testing.T) {
	plan := CategoryPlan{TargetRevenueEGP: 100, TargetUnits: 50, AvgPriceEGP: 2}
	months := []MonthWeight{{Month: 1, Weight: 1}, {Month: 2, Weight: 3}}
	casc := CascadeCategory(plan, nil, nil, months)
	if math.Abs(casc.Months[0].TargetEGP-25) > 0.02 {
		t.Fatalf("jan %v", casc.Months[0].TargetEGP)
	}
	if math.Abs(casc.Months[1].TargetEGP-75) > 0.02 {
		t.Fatalf("feb %v", casc.Months[1].TargetEGP)
	}
	for m := 2; m < 12; m++ {
		if casc.Months[m].TargetEGP != 0 {
			t.Fatalf("month %d should be 0 when only jan/feb weighted", m+1)
		}
	}
}

func TestMarketGrowthRaisesTarget(t *testing.T) {
	in := CategoryInput{Category: "c", CurrentSharePct: 10, OwnRevenueEGP: 10, MarketRevenueEGP: 100, AvgPriceEGP: 1, OwnUnits: 10}
	flat := PlanCategory(in, 15, Options{MarketGrowthPct: 0})
	grown := PlanCategory(in, 15, Options{MarketGrowthPct: 10})
	if flat.TargetRevenueEGP != 15 {
		t.Fatalf("flat %v", flat.TargetRevenueEGP)
	}
	if math.Abs(grown.TargetRevenueEGP-16.5) > 0.01 {
		t.Fatalf("grown %v", grown.TargetRevenueEGP)
	}
}
