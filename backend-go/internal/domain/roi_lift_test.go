package domain

import (
	"math"
	"testing"
)

func near(a, b float64) bool { return math.Abs(a-b) < 1e-6 }

func TestComputeRoiLiftYoyTrendWithOrganicRatio(t *testing.T) {
	// Target Feb 2026. Trailing organic months: Jan, Dec, Nov with YoY 1.10, 1.00, 1.20 → avg 1.10.
	// Campaign month Oct 2025 is skipped. Baseline = 800k * 1.10 = 880k.
	// Actual 1,000,000 → lift 120,000, ROMI 120k/50k = 2.4, Net ROI = (120-50)/50 = 140%.
	target := RoiMonthKey{Year: 2026, Month: 2}
	sales := map[RoiMonthKey]float64{
		{2026, 1}: 110000, {2025, 1}: 100000, // 1.10
		{2025, 12}: 200000, {2024, 12}: 200000, // 1.00
		{2025, 11}: 120000, {2024, 11}: 100000, // 1.20
		{2025, 10}: 999999, {2024, 10}: 100000, // campaign — skipped
	}
	campaigns := map[RoiMonthKey]bool{{2025, 10}: true, target: true}
	res := ComputeRoiLift(1000000, 800000, 50000, target, sales, campaigns)
	if !res.Available || res.Method != RoiBaselineMethodYoyTrend {
		t.Fatalf("want yoy_trend available, got %+v", res)
	}
	if res.OrganicMonthsUsed != 3 || !near(res.OrganicYoYRatio, 1.10) {
		t.Fatalf("ratio: used=%d ratio=%v", res.OrganicMonthsUsed, res.OrganicYoYRatio)
	}
	if !near(res.BaselineSalesEGP, 880000) || !near(res.IncrementalLiftEGP, 120000) {
		t.Fatalf("baseline/lift: %+v", res)
	}
	if res.RomiMultiple == nil || !near(*res.RomiMultiple, 2.4) {
		t.Fatalf("romi: %v", res.RomiMultiple)
	}
	if res.NetRoiPct == nil || !near(*res.NetRoiPct, 140) {
		t.Fatalf("net roi: %v", res.NetRoiPct)
	}
}

func TestComputeRoiLiftYoyTrendNoOrganicMonthsUsesRatioOne(t *testing.T) {
	target := RoiMonthKey{Year: 2026, Month: 2}
	res := ComputeRoiLift(1200000, 800000, 50000, target, nil, nil)
	if res.Method != RoiBaselineMethodYoyTrend || res.OrganicMonthsUsed != 0 || !near(res.OrganicYoYRatio, 1) {
		t.Fatalf("want ratio 1: %+v", res)
	}
	if !near(res.BaselineSalesEGP, 800000) || !near(res.IncrementalLiftEGP, 400000) {
		t.Fatalf("baseline/lift: %+v", res)
	}
	if res.RomiMultiple == nil || !near(*res.RomiMultiple, 8) {
		t.Fatalf("romi want 8 got %v", res.RomiMultiple)
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
	if res.NetRoiPct == nil || !near(*res.NetRoiPct, -300) { // (-100k-50k)/50k
		t.Fatalf("net roi: %v", res.NetRoiPct)
	}
}

func TestComputeRoiLiftPriorOrganicAverageWhenNoLastYear(t *testing.T) {
	// No LY. Prev 3 non-campaign months average (90+100+110)/3 = 100.
	target := RoiMonthKey{Year: 2026, Month: 4}
	sales := map[RoiMonthKey]float64{
		{2026, 3}:  110000,
		{2026, 2}:  999999, // campaign, skipped
		{2026, 1}:  100000,
		{2025, 12}: 90000,
	}
	campaigns := map[RoiMonthKey]bool{{2026, 2}: true}
	res := ComputeRoiLift(130000, 0, 10000, target, sales, campaigns)
	if res.Method != RoiBaselineMethodPriorOrganicAvg || res.OrganicMonthsUsed != 3 {
		t.Fatalf("want prior organic: %+v", res)
	}
	if !near(res.BaselineSalesEGP, 100000) || !near(res.IncrementalLiftEGP, 30000) {
		t.Fatalf("baseline/lift: %+v", res)
	}
	if res.RomiMultiple == nil || !near(*res.RomiMultiple, 3) {
		t.Fatalf("romi: %v", res.RomiMultiple)
	}
}

func TestComputeRoiLiftUnavailableWithoutHistory(t *testing.T) {
	res := ComputeRoiLift(300000, 0, 15000, RoiMonthKey{Year: 2026, Month: 2}, nil, nil)
	if res.Available || res.Method != RoiBaselineMethodUnavailable || res.RomiMultiple != nil {
		t.Fatalf("want unavailable: %+v", res)
	}
	if res.UnavailableMessageAR != RoiBaselineUnavailableAR {
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
