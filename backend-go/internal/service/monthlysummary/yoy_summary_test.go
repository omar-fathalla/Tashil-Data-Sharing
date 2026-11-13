package monthlysummary

import (
	"context"
	"encoding/json"
	"strings"
	"testing"
)

const noLastYearAR = "لا توجد بيانات للعام السابق"

// v125: with no comparable last-year data the auto summary must not quote
// "التغير السنوي للإيراد +0.0%" (deterministic or AI claim path).
func TestMonthlySummaryNoLastYearDeterministic(t *testing.T) {
	kpis := fixtureKPIs()
	kpis.RevenueYoYPct = 0
	kpis.YoYAvailable = false
	sum := Build(context.Background(), kpis, Options{UseMock: true})
	if strings.Contains(sum.NarrativeAR, "التغير السنوي للإيراد") || strings.Contains(sum.NarrativeAR, "+0.0%") {
		t.Fatalf("no last-year data must not quote a YoY %%: %s", sum.NarrativeAR)
	}
	if !strings.Contains(sum.NarrativeAR, noLastYearAR) {
		t.Fatalf("want no-last-year sentence, got: %s", sum.NarrativeAR)
	}
	if !sum.Grounded {
		t.Fatal("deterministic narrative must stay grounded")
	}
	for _, d := range sum.Aggregates.NotableDeltas {
		if d.Code == "revenue_yoy" {
			t.Fatalf("revenue_yoy delta must be dropped when unavailable: %+v", d)
		}
	}
	b, _ := json.Marshal(sum.Aggregates)
	if !strings.Contains(string(b), `"yoy_available":false`) {
		t.Fatalf("aggregates must expose yoy_available=false: %s", b)
	}
}

func TestMonthlySummaryNoLastYearAIClaim(t *testing.T) {
	kpis := fixtureKPIs()
	kpis.RevenueYoYPct = 0
	kpis.YoYAvailable = false
	agg := BuildAggregates(kpis)
	payload := AINarrativePayload{
		NarrativeAR: "ملخص تجريبي.",
		Claims: []Claim{
			{Key: ClaimTotalRevenue, Number: agg.TotalRevenue},
			{Key: ClaimTotalUnits, Number: float64(agg.TotalUnits)},
			{Key: ClaimRevenueYoYPct, Number: 0},
			{Key: ClaimTopChain, Name: agg.TopChains[0].Name},
		},
	}
	raw, _ := json.Marshal(payload)
	var prompt string
	gen := func(ctx context.Context, model, p string) (string, error) {
		prompt = p
		return string(raw), nil
	}
	sum := Build(context.Background(), kpis, Options{Generator: gen, Model: "gemini-test"})
	if strings.Contains(sum.NarrativeAR, "التغير السنوي للإيراد") || strings.Contains(sum.NarrativeAR, "+0.0%") {
		t.Fatalf("AI path must not ship a 0%% YoY claim: %s", sum.NarrativeAR)
	}
	if !strings.Contains(sum.NarrativeAR, noLastYearAR) {
		t.Fatalf("want no-last-year sentence, got: %s", sum.NarrativeAR)
	}
	if !strings.Contains(prompt, `"yoy_available": false`) {
		t.Fatalf("prompt facts must carry yoy_available: %s", prompt)
	}
}

func TestMonthlySummaryYoYAvailableStillQuoted(t *testing.T) {
	sum := Build(context.Background(), fixtureKPIs(), Options{UseMock: true})
	if !strings.Contains(sum.NarrativeAR, "التغير السنوي للإيراد +8.0%") {
		t.Fatalf("available YoY must still be quoted: %s", sum.NarrativeAR)
	}
	if strings.Contains(sum.NarrativeAR, noLastYearAR) {
		t.Fatalf("unexpected no-data sentence: %s", sum.NarrativeAR)
	}
}
