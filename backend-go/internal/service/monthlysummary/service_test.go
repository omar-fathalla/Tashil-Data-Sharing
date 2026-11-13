package monthlysummary

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/tashil/data-sharing/backend/internal/domain"
)

func fixtureKPIs() *domain.ExecutiveKPIs {
	return &domain.ExecutiveKPIs{
		TotalRevenue:         1_250_000,
		TenantMarketSharePct: 18.5,
		RevenueMoMPct:        12.4,
		RevenueYoYPct:        8.0,
		YoYAvailable:         true,
		TotalUnitsSold:       42000,
		UnitsMoMPct:          6.5,
		ActiveStoresCount:    37,
		OOSRatePct:           11.2,
		EstimatedLostRevenue: 15000,
		Currency:             "EGP",
		ReportingPeriod:      "CUSTOM",
		ChainShares: []domain.ChainShareSummary{
			{RetailerChain: "fathalla", DisplayName: "فتح الله", TotalRevenue: 700000, TotalUnits: 22000, MarketShare: 56},
			{RetailerChain: "carrefour", DisplayName: "كارفور", TotalRevenue: 350000, TotalUnits: 12000, MarketShare: 28},
			{RetailerChain: "gomla", DisplayName: "جملة ماركت", TotalRevenue: 200000, TotalUnits: 8000, MarketShare: 16},
		},
		ParetoSKUs: []domain.ParetoSKUItem{
			{SKUName: "Adeco Oil 1L", Barcode: "622100", TotalRevenue: 180000, TotalUnits: 9000, RevenueSharePct: 14.4},
			{SKUName: "Adeco Ghee", Barcode: "622101", TotalRevenue: 120000, TotalUnits: 4000, RevenueSharePct: 9.6},
		},
		CategoryContributions: []domain.CategoryContribution{
			{Category: "زيوت", TotalRevenue: 500000, TotalUnits: 15000, SharePct: 40},
			{Category: "ألبان", TotalRevenue: 300000, TotalUnits: 10000, SharePct: 24},
		},
		DailyTrends: []domain.DailyTrendPoint{
			{MonthKey: "2026-09", Revenue: 1_100_000, Units: 39000},
			{MonthKey: "2026-10", Revenue: 1_250_000, Units: 42000},
		},
	}
}

func TestBuildAggregatesFromFixture(t *testing.T) {
	agg := BuildAggregates(fixtureKPIs())
	if agg.TotalRevenue != 1_250_000 {
		t.Fatalf("total revenue: got %v", agg.TotalRevenue)
	}
	if agg.TotalUnits != 42000 {
		t.Fatalf("units: got %d", agg.TotalUnits)
	}
	if agg.RevenueMoMPct != 12.4 {
		t.Fatalf("mom: got %v", agg.RevenueMoMPct)
	}
	if agg.CurrentMonthKey != "2026-10" || agg.PriorMonthKey != "2026-09" {
		t.Fatalf("month keys: %+v / %+v", agg.CurrentMonthKey, agg.PriorMonthKey)
	}
	if agg.PriorMonthRevenue != 1_100_000 {
		t.Fatalf("prior revenue: got %v", agg.PriorMonthRevenue)
	}
	if len(agg.TopChains) == 0 || agg.TopChains[0].Name != "فتح الله" {
		t.Fatalf("top chain: %+v", agg.TopChains)
	}
	if len(agg.TopProducts) == 0 || agg.TopProducts[0].Name != "Adeco Oil 1L" {
		t.Fatalf("top product: %+v", agg.TopProducts)
	}
	if len(agg.TopCategories) == 0 || agg.TopCategories[0].Name != "زيوت" {
		t.Fatalf("top category: %+v", agg.TopCategories)
	}
	codes := map[string]bool{}
	for _, d := range agg.NotableDeltas {
		codes[d.Code] = true
	}
	for _, want := range []string{"revenue_mom", "units_mom", "oos_rate", "chain_concentration"} {
		if !codes[want] {
			t.Fatalf("missing notable delta %q in %+v", want, agg.NotableDeltas)
		}
	}
}

func TestDeterministicNarrativeGrounded(t *testing.T) {
	agg := BuildAggregates(fixtureKPIs())
	text := DeterministicNarrateAR(agg)
	if !Grounded(text, agg) {
		t.Fatalf("deterministic narrative not grounded:\n%s", text)
	}
	for _, needle := range []string{"1250000", "42000", "فتح الله", "Adeco Oil 1L", "زيوت"} {
		if !strings.Contains(text, needle) {
			t.Fatalf("narrative missing %q:\n%s", needle, text)
		}
	}
	if !strings.Contains(text, "مبني حصراً على أرقام") {
		t.Fatalf("expected honesty preface: %s", text)
	}
}

func TestEmptyKPIsNoInventedFigures(t *testing.T) {
	agg := BuildAggregates(&domain.ExecutiveKPIs{Currency: "EGP", ReportingPeriod: "MTD"})
	text := DeterministicNarrateAR(agg)
	if strings.ContainsAny(text, "123456789") && !strings.Contains(text, "لا تتوفر") {
		// Allow period labels but not fabricated sales totals.
		if strings.Contains(text, "إجمالي المبيعات") {
			t.Fatalf("invented sales narrative on empty KPIs: %s", text)
		}
	}
	if !Grounded(text, agg) {
		t.Fatalf("empty narrative should be grounded: %s", text)
	}
	sum := Build(context.Background(), &domain.ExecutiveKPIs{}, Options{UseMock: true})
	if sum.MappingSource != SourceDeterministic {
		t.Fatalf("empty path source=%s", sum.MappingSource)
	}
	if sum.Confidence != 0 {
		t.Fatalf("empty confidence want 0 got %v", sum.Confidence)
	}
}

func TestAttachMutatesKPIs(t *testing.T) {
	kpis := fixtureKPIs()
	sum := Attach(context.Background(), kpis, Options{UseMock: true})
	if sum == nil || kpis.MonthlySummary == nil {
		t.Fatal("expected monthly summary attached")
	}
	if kpis.MonthlySummary.MappingSource != SourceDeterministic {
		t.Fatalf("source=%s", kpis.MonthlySummary.MappingSource)
	}
	if !kpis.MonthlySummary.Grounded {
		t.Fatal("expected grounded=true")
	}
	if kpis.MonthlySummary.Confidence < 0.9 {
		t.Fatalf("rich fixture should score high confidence, got %v", kpis.MonthlySummary.Confidence)
	}
}

func validAIPayloadJSON(agg domain.MonthlySummaryAggregates) string {
	narrative := fmt.Sprintf(
		"أظهر شهر %s مبيعات %.0f جنيه و%d وحدة. تصدرت سلسلة %s الأداء.",
		agg.CurrentMonthKey, agg.TotalRevenue, agg.TotalUnits, agg.TopChains[0].Name,
	)
	payload := AINarrativePayload{
		NarrativeAR: narrative,
		Claims: []Claim{
			{Key: ClaimTotalRevenue, Number: agg.TotalRevenue},
			{Key: ClaimTotalUnits, Number: float64(agg.TotalUnits)},
			{Key: ClaimTopChain, Name: agg.TopChains[0].Name},
		},
	}
	b, _ := json.Marshal(payload)
	return string(b)
}

func TestAIGroundedAccepted(t *testing.T) {
	kpis := fixtureKPIs()
	agg := BuildAggregates(kpis)
	aiJSON := validAIPayloadJSON(agg)
	gen := func(ctx context.Context, model, prompt string) (string, error) {
		if !strings.Contains(prompt, `"total_revenue"`) {
			t.Fatalf("prompt missing facts: %s", prompt)
		}
		if model != "gemini-test" {
			t.Fatalf("model=%s", model)
		}
		return aiJSON, nil
	}
	sum := Build(context.Background(), kpis, Options{Generator: gen, Model: "gemini-test"})
	if sum.MappingSource != SourceAI {
		t.Fatalf("want ai, got %s / %s", sum.MappingSource, sum.NarrativeAR)
	}
	if sum.ModelUsed != "gemini-test" || !sum.Grounded {
		t.Fatalf("model/grounded: %+v", sum)
	}
	payload, _ := ParseAIPayload(aiJSON)
	want := NarrateFromClaims(payload.Claims, agg)
	if sum.NarrativeAR != want {
		t.Fatalf("shipped narrative must be claim-built\ngot:  %s\nwant: %s", sum.NarrativeAR, want)
	}
	if sum.NarrativeAR == payload.NarrativeAR {
		t.Fatal("must not ship independent AI narrative_ar prose")
	}
}

func TestValidClaimsFabricatedNarrativeNumberRejected(t *testing.T) {
	kpis := fixtureKPIs()
	agg := BuildAggregates(kpis)
	// Claims are fully valid, but narrative_ar sneaks in a fabricated figure.
	payload := AINarrativePayload{
		NarrativeAR: fmt.Sprintf(
			"المبيعات %.0f والوحدات %d و%s لكن الربح السري 7777777 جنيه.",
			agg.TotalRevenue, agg.TotalUnits, agg.TopChains[0].Name,
		),
		Claims: []Claim{
			{Key: ClaimTotalRevenue, Number: agg.TotalRevenue},
			{Key: ClaimTotalUnits, Number: float64(agg.TotalUnits)},
			{Key: ClaimTopChain, Name: agg.TopChains[0].Name},
		},
	}
	if !ValidateClaims(payload.Claims, agg) {
		t.Fatal("precondition: claims must be valid")
	}
	if !NarrativeHasFabricatedNumbers(payload.NarrativeAR, payload.Claims, agg) {
		t.Fatal("precondition: narrative must contain fabricated number")
	}
	if AcceptAIClaims(payload.NarrativeAR, payload.Claims, agg) {
		t.Fatal("valid claims + fabricated narrative number must be rejected")
	}
	b, _ := json.Marshal(payload)
	gen := func(ctx context.Context, model, prompt string) (string, error) {
		return string(b), nil
	}
	sum := Build(context.Background(), kpis, Options{Generator: gen, Model: "gemini-test"})
	if sum.MappingSource != SourceDeterministic {
		t.Fatalf("want deterministic fallback, got %s", sum.MappingSource)
	}
	if strings.Contains(sum.NarrativeAR, "7777777") {
		t.Fatal("fabricated narrative number leaked into shipped text")
	}
}

func TestCorrectNumbersFabricatedClaimFails(t *testing.T) {
	kpis := fixtureKPIs()
	agg := BuildAggregates(kpis)
	narrative := fmt.Sprintf(
		"المبيعات %.0f والوحدات %d وسلسلة %s، مع إطلاق منتج مفبرك جديد.",
		agg.TotalRevenue, agg.TotalUnits, agg.TopChains[0].Name,
	)
	// Correct core numbers + fabricated claim key / wrong product name must fail grounding.
	payload := AINarrativePayload{
		NarrativeAR: narrative,
		Claims: []Claim{
			{Key: ClaimTotalRevenue, Number: agg.TotalRevenue},
			{Key: ClaimTotalUnits, Number: float64(agg.TotalUnits)},
			{Key: ClaimTopChain, Name: agg.TopChains[0].Name},
			{Key: "new_product_launch", Name: "SuperFakeSKU"},
		},
	}
	if GroundedStructured(narrative, payload.Claims, agg) {
		t.Fatal("fabricated claim must not be grounded even with correct numbers")
	}
	b, _ := json.Marshal(payload)
	gen := func(ctx context.Context, model, prompt string) (string, error) {
		return string(b), nil
	}
	sum := Build(context.Background(), kpis, Options{Generator: gen, Model: "gemini-test"})
	if sum.MappingSource != SourceDeterministic {
		t.Fatalf("fabricated claim must fall back, got %s", sum.MappingSource)
	}
	if strings.Contains(sum.NarrativeAR, "SuperFakeSKU") {
		t.Fatal("fabricated claim leaked into shipped narrative")
	}

	// Same numbers but wrong top_chain name also fails.
	wrongName := AINarrativePayload{
		NarrativeAR: narrative,
		Claims: []Claim{
			{Key: ClaimTotalRevenue, Number: agg.TotalRevenue},
			{Key: ClaimTotalUnits, Number: float64(agg.TotalUnits)},
			{Key: ClaimTopChain, Name: "سلسلة مفبركة"},
		},
	}
	if ValidateClaims(wrongName.Claims, agg) {
		t.Fatal("wrong entity name must fail ValidateClaims")
	}
}

func TestAIFreeFormWithoutClaimsFallsBack(t *testing.T) {
	kpis := fixtureKPIs()
	agg := BuildAggregates(kpis)
	// Free-form prose that happens to include correct numbers — still ungrounded without claims.
	free := fmt.Sprintf("المبيعات %.0f والوحدات %d و%s", agg.TotalRevenue, agg.TotalUnits, agg.TopChains[0].Name)
	gen := func(ctx context.Context, model, prompt string) (string, error) {
		return free, nil
	}
	sum := Build(context.Background(), kpis, Options{Generator: gen, Model: "gemini-test"})
	if sum.MappingSource != SourceDeterministic {
		t.Fatalf("free-form AI must be deterministic-only, got %s", sum.MappingSource)
	}
}

func TestAIUngroundedFallsBack(t *testing.T) {
	kpis := fixtureKPIs()
	gen := func(ctx context.Context, model, prompt string) (string, error) {
		return `{"narrative_ar":"المبيعات تضاعفت إلى 999999999 جنيه.","claims":[{"key":"total_revenue","number":999999999},{"key":"total_units","number":42000},{"key":"top_chain","name":"فتح الله"}]}`, nil
	}
	sum := Build(context.Background(), kpis, Options{Generator: gen, Model: "gemini-test"})
	if sum.MappingSource != SourceDeterministic {
		t.Fatalf("ungrounded AI must fall back, got %s", sum.MappingSource)
	}
	if !Grounded(sum.NarrativeAR, sum.Aggregates) {
		t.Fatal("fallback must be grounded")
	}
	if strings.Contains(sum.NarrativeAR, "999999999") {
		t.Fatal("invented figure leaked into narrative")
	}
}

func TestAIErrorFallsBack(t *testing.T) {
	kpis := fixtureKPIs()
	gen := func(ctx context.Context, model, prompt string) (string, error) {
		return "", fmt.Errorf("boom")
	}
	sum := Build(context.Background(), kpis, Options{Generator: gen, Model: "gemini-test"})
	if sum.MappingSource != SourceDeterministic {
		t.Fatalf("got %s", sum.MappingSource)
	}
}

func TestNDARedactedChainsSkipped(t *testing.T) {
	kpis := &domain.ExecutiveKPIs{
		TotalRevenue: 100, TotalUnitsSold: 10, Currency: "EGP",
		ChainShares: []domain.ChainShareSummary{
			{RetailerChain: "nda_redacted", DisplayName: "سلسلة تجزئة منافسة (محمي بـ NDA)", TotalRevenue: 90, MarketShare: 90},
			{RetailerChain: "fathalla", DisplayName: "فتح الله", TotalRevenue: 10, MarketShare: 10},
		},
	}
	agg := BuildAggregates(kpis)
	if len(agg.TopChains) == 0 || agg.TopChains[0].Name != "فتح الله" {
		t.Fatalf("expected NDA skip, got %+v", agg.TopChains)
	}
}

func TestGeminiGeneratorHTTP(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("x-goog-api-key") != "test-key" {
			t.Errorf("missing api key header")
		}
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"candidates":[{"content":{"parts":[{"text":"ملخص تجريبي 1250000"}]}}]}`))
	}))
	defer srv.Close()

	gen := NewGeminiGenerator("test-key", srv.URL, srv.Client())
	if gen == nil {
		t.Fatal("expected generator")
	}
	text, err := gen(context.Background(), "gemini-flash", "prompt")
	if err != nil {
		t.Fatal(err)
	}
	if text != "ملخص تجريبي 1250000" {
		t.Fatalf("got %q", text)
	}
	if NewGeminiGenerator("", srv.URL, nil) != nil {
		t.Fatal("empty key must yield nil generator")
	}
}

func TestNilAttachSafe(t *testing.T) {
	if Attach(context.Background(), nil, Options{}) != nil {
		t.Fatal("nil kpis")
	}
}
