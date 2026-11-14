package domain

import (
	"math"
	"testing"
)

func near(a, b float64) bool { return math.Abs(a-b) < 1e-6 }

func TestComputeRoiLiftSeasonalYoy(t *testing.T) {
	// Actual 1,200,000 vs LY 800,000 → lift 400,000, ROMI 8x, Net ROI 700%.
	target := RoiMonthKey{Year: 2026, Month: 2}
	res := ComputeRoiLift(1200000, 800000, 50000, target, nil, nil)
	if !res.Available || res.Method != RoiBaselineMethodYoySeasonal {
		t.Fatalf("want yoy_seasonal available, got %+v", res)
	}
	if !near(res.BaselineSalesEGP, 800000) || !near(res.IncrementalLiftEGP, 400000) {
		t.Fatalf("baseline/lift: %+v", res)
	}
	if res.RomiMultiple == nil || !near(*res.RomiMultiple, 8) {
		t.Fatalf("romi want 8 got %v", res.RomiMultiple)
	}
	if res.NetRoiPct == nil || !near(*res.NetRoiPct, 700) {
		t.Fatalf("net roi: %v", res.NetRoiPct)
	}
	if res.MethodAR != RoiYoySeasonalMethodAR {
		t.Fatalf("method ar: %q", res.MethodAR)
	}
}

func TestComputeRoiLiftIgnoresOrganicHistoryAndCampaignMaps(t *testing.T) {
	// Even with rich organic history that would have produced ratio 1.10 under
	// the old method, seasonal YoY keeps baseline = last year only.
	target := RoiMonthKey{Year: 2026, Month: 2}
	sales := map[RoiMonthKey]float64{
		{2026, 1}: 110000, {2025, 1}: 100000,
		{2025, 12}: 200000, {2024, 12}: 200000,
		{2025, 11}: 120000, {2024, 11}: 100000,
	}
	campaigns := map[RoiMonthKey]bool{{2025, 10}: true, target: true}
	res := ComputeRoiLift(1000000, 800000, 50000, target, sales, campaigns)
	if res.Method != RoiBaselineMethodYoySeasonal || !near(res.BaselineSalesEGP, 800000) {
		t.Fatalf("must not apply organic ratio: %+v", res)
	}
	if !near(res.IncrementalLiftEGP, 200000) || res.RomiMultiple == nil || !near(*res.RomiMultiple, 4) {
		t.Fatalf("lift/romi: %+v", res)
	}
}

func TestComputeRoiLiftNegativeLiftIsHonest(t *testing.T) {
	target := RoiMonthKey{Year: 2026, Month: 2}
	res := ComputeRoiLift(700000, 800000, 50000, target, nil, nil)
	if !res.Available || !near(res.IncrementalLiftEGP, -100000) {
		t.Fatalf("want negative lift: %+v", res)
	}
	if res.RomiMultiple == nil || !near(*res.RomiMultiple, -2) {
		t.Fatalf("romi: %v", res.RomiMultiple)
	}
	if res.NetRoiPct == nil || !near(*res.NetRoiPct, -300) {
		t.Fatalf("net roi: %v", res.NetRoiPct)
	}
}

func TestComputeRoiLiftUnavailableWithoutLastYear(t *testing.T) {
	// Prior non-campaign months must NOT become a substitute baseline.
	sales := map[RoiMonthKey]float64{
		{2026, 3}: 110000,
		{2026, 1}: 100000,
		{2025, 12}: 90000,
	}
	res := ComputeRoiLift(130000, 0, 10000, RoiMonthKey{Year: 2026, Month: 4}, sales, nil)
	if res.Available || res.Method != RoiBaselineMethodUnavailable || res.RomiMultiple != nil {
		t.Fatalf("want unavailable without LY: %+v", res)
	}
	if res.UnavailableMessageAR != RoiNoLastYearAR {
		t.Fatalf("message: %q", res.UnavailableMessageAR)
	}
}

func TestComputeRoiLiftNoSpendLeavesRomiNil(t *testing.T) {
	res := ComputeRoiLift(1200000, 800000, 0, RoiMonthKey{Year: 2026, Month: 2}, nil, nil)
	if !res.Available || res.RomiMultiple != nil || res.NetRoiPct != nil {
		t.Fatalf("romi should be nil without spend: %+v", res)
	}
	if !near(res.BaselineSalesEGP, 800000) {
		t.Fatalf("baseline: %v", res.BaselineSalesEGP)
	}
}

func TestComputeRoiLiftDoesNotCherryPickMomOverYoy(t *testing.T) {
	// MoM lift is +400k (current 1.2M vs prev 800k) but last year is 1.5M so
	// seasonal baseline is 1.5M and incremental lift is negative. Old code
	// would have reported the positive MoM lift.
	res := ComputeRoiLift(1200000, 1500000, 50000, RoiMonthKey{Year: 2026, Month: 2}, nil, nil)
	if !near(res.IncrementalLiftEGP, -300000) {
		t.Fatalf("must not cherry-pick MoM: lift=%v", res.IncrementalLiftEGP)
	}
}
