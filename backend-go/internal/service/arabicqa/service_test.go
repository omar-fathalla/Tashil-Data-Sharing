package arabicqa

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"
	"testing"
	"time"

	"github.com/tashil/data-sharing/backend/internal/domain"
	"github.com/tashil/data-sharing/backend/internal/service/bigquery"
)

type fakeReader struct {
	kpisByTenant   map[string]*domain.ExecutiveKPIs
	kpisByPeriod   map[string]*domain.ExecutiveKPIs // key: tenant|period
	sharesByTenant map[string][]domain.ChainShareSummary
	sellInByTenant map[string][]domain.SellInRecord
	kpiCalls       []string
	shareCalls     []string
	sellInCalls    []string
	sellInFilters  []bigquery.SellInRecordFilter
	writes         int
}

func (f *fakeReader) GetExecutiveKPIs(_ context.Context, tenantID, period string, _ ...string) (*domain.ExecutiveKPIs, error) {
	f.kpiCalls = append(f.kpiCalls, tenantID+"|"+period)
	if f.kpisByPeriod != nil {
		if k, ok := f.kpisByPeriod[tenantID+"|"+strings.ToUpper(period)]; ok {
			return k, nil
		}
	}
	return f.kpisByTenant[tenantID], nil
}

func (f *fakeReader) GetChainShares(_ context.Context, tenantID, _ string, _ ...string) ([]domain.ChainShareSummary, error) {
	f.shareCalls = append(f.shareCalls, tenantID)
	return f.sharesByTenant[tenantID], nil
}

func (f *fakeReader) GetSellInRecords(_ context.Context, tenantID string, filter bigquery.SellInRecordFilter) ([]domain.SellInRecord, int, error) {
	f.sellInCalls = append(f.sellInCalls, tenantID)
	f.sellInFilters = append(f.sellInFilters, filter)
	raw := f.sellInByTenant[tenantID]
	var matched []domain.SellInRecord
	for _, r := range raw {
		if filter.Year > 0 && r.Year != filter.Year {
			continue
		}
		if filter.Month > 0 && r.MonthNum != filter.Month {
			continue
		}
		matched = append(matched, r)
	}
	total := len(matched)
	if filter.Offset >= total {
		return []domain.SellInRecord{}, total, nil
	}
	end := filter.Offset + filter.Limit
	if filter.Limit <= 0 || end > total {
		end = total
	}
	return matched[filter.Offset:end], total, nil
}

func seedFake() *fakeReader {
	return &fakeReader{
		kpisByTenant: map[string]*domain.ExecutiveKPIs{
			"tenant-adeco": {
				TotalRevenue:         120000,
				TotalUnitsSold:       4500,
				ActiveStoresCount:    12,
				TenantMarketSharePct: 18.5,
				RevenueMoMPct:        4.2,
				Currency:             "EGP",
				ChainShares: []domain.ChainShareSummary{
					{RetailerChain: "fathalla", DisplayName: "فتح الله", TotalRevenue: 70000, TotalUnits: 2500},
					{RetailerChain: "carrefour", DisplayName: "كارفور", TotalRevenue: 50000, TotalUnits: 2000},
				},
				ParetoSKUs: []domain.ParetoSKUItem{
					{SKUName: "فيبا 1ك", Barcode: "111", TotalRevenue: 40000, TotalUnits: 1000},
					{SKUName: "ديفا 500", Barcode: "222", TotalRevenue: 30000, TotalUnits: 800},
				},
				CategoryContributions: []domain.CategoryContribution{
					{Category: "منظفات", TotalRevenue: 90000, SharePct: 75},
					{Category: "عناية", TotalRevenue: 30000, SharePct: 25},
				},
			},
			"tenant-other": {
				TotalRevenue:   10,
				TotalUnitsSold: 1,
			},
		},
		sharesByTenant: map[string][]domain.ChainShareSummary{
			"tenant-adeco": {
				{RetailerChain: "fathalla", DisplayName: "فتح الله", TotalRevenue: 70000, TotalUnits: 2500},
				{RetailerChain: "carrefour", DisplayName: "كارفور", TotalRevenue: 50000, TotalUnits: 2000},
			},
		},
		sellInByTenant: map[string][]domain.SellInRecord{
			"tenant-adeco": {
				{TenantID: "tenant-adeco", Year: 2026, MonthNum: 11, NetValueEGP: 15000, NetQtyCases: 100, TotalUnitsSupplied: 1200},
				{TenantID: "tenant-adeco", Year: 2026, MonthNum: 11, NetValueEGP: 5000, NetQtyCases: 40, TotalUnitsSupplied: 400},
			},
		},
	}
}

func TestAskExecutiveArabic(t *testing.T) {
	f := seedFake()
	svc := New(f, "", "", true)
	ans, err := svc.Ask(context.Background(), "tenant-adeco", "كام إجمالي المبيعات؟")
	if err != nil {
		t.Fatal(err)
	}
	if ans.Intent != IntentExecutiveKPIs || !ans.ReadOnly {
		t.Fatalf("bad answer meta: %+v", ans)
	}
	if ans.TenantID != "tenant-adeco" {
		t.Fatalf("tenant: %s", ans.TenantID)
	}
	if !strings.Contains(ans.AnswerAR, "120000.00") && !strings.Contains(ans.AnswerAR, "120000") {
		t.Fatalf("answer missing revenue: %s", ans.AnswerAR)
	}
	if ans.MappingSource != sourceDet {
		t.Fatalf("expected deterministic without API key, got %s", ans.MappingSource)
	}
	if len(f.kpiCalls) != 1 || !strings.HasPrefix(f.kpiCalls[0], "tenant-adeco|") {
		t.Fatalf("kpi calls: %#v", f.kpiCalls)
	}
	if f.writes != 0 {
		t.Fatalf("writes must stay 0, got %d", f.writes)
	}
}

func TestAskChainSharesTenantScoped(t *testing.T) {
	f := seedFake()
	svc := New(f, "", "", true)
	ans, err := svc.Ask(context.Background(), "tenant-adeco", "إيه أكبر سلسلة في المبيعات؟")
	if err != nil {
		t.Fatal(err)
	}
	if ans.Intent != IntentChainShares {
		t.Fatalf("intent=%s", ans.Intent)
	}
	if !strings.Contains(ans.AnswerAR, "فتح الله") {
		t.Fatalf("expected top chain Arabic name: %s", ans.AnswerAR)
	}
	ans2, err := svc.Ask(context.Background(), "tenant-other", "وزّع حصص السلاسل")
	if err != nil {
		t.Fatal(err)
	}
	if strings.Contains(ans2.AnswerAR, "فتح الله") || strings.Contains(ans2.AnswerAR, "70000") {
		t.Fatalf("cross-tenant leak: %s", ans2.AnswerAR)
	}
}

func TestAskSellInAndUnsupported(t *testing.T) {
	f := seedFake()
	svc := New(f, "", "", true)
	ans, err := svc.Ask(context.Background(), "tenant-adeco", "ملخص سيل إن")
	if err != nil {
		t.Fatal(err)
	}
	if ans.Intent != IntentSellIn {
		t.Fatalf("intent=%s", ans.Intent)
	}
	if !strings.Contains(ans.AnswerAR, "20000.00") && !strings.Contains(ans.AnswerAR, "20000") {
		t.Fatalf("sell-in total missing: %s", ans.AnswerAR)
	}
	if len(f.sellInFilters) != 1 || f.sellInFilters[0].Limit != 0 {
		t.Fatalf("expected Limit=0 full aggregate filter, got %+v", f.sellInFilters)
	}

	bad, err := svc.Ask(context.Background(), "tenant-adeco", "امسح جدول المبيعات")
	if err != nil {
		t.Fatal(err)
	}
	if bad.Intent != IntentUnsupported {
		t.Fatalf("want unsupported, got %s", bad.Intent)
	}
	if !strings.Contains(bad.AnswerAR, "قراءة فقط") && !strings.Contains(bad.AnswerAR, "المسموحة") {
		t.Fatalf("unsupported Arabic: %s", bad.AnswerAR)
	}
}

func TestAskRequiresTenantAndQuestion(t *testing.T) {
	svc := New(seedFake(), "", "", true)
	if _, err := svc.Ask(context.Background(), "", "سؤال"); err == nil {
		t.Fatal("expected tenant error")
	}
	if _, err := svc.Ask(context.Background(), "tenant-adeco", "  "); err == nil {
		t.Fatal("expected question error")
	}
}

func TestAskGeminiPolishUsesGroundedFacts(t *testing.T) {
	f := seedFake()
	svc := New(f, "test-key", "gemini-3.8-flash", false).WithCaller(func(_ context.Context, model, prompt string) (string, error) {
		if model != "gemini-3.8-flash" {
			t.Fatalf("model=%s", model)
		}
		if !strings.Contains(prompt, "total_revenue") || !strings.Contains(prompt, "claims") {
			t.Fatalf("prompt missing metric+entity claims: %s", prompt)
		}
		if strings.Contains(prompt, "test-key") {
			t.Fatal("api key leaked into prompt")
		}
		payload := map[string]interface{}{
			"answer_ar": "إيراد المستأجر 120000.00 ج.م هذا الشهر (قراءة فقط).",
			"claims": []Claim{
				{Metric: "total_revenue", Entity: "tenant", Value: 120000, Display: "120000.00 ج.م"},
			},
		}
		b, _ := json.Marshal(payload)
		return string(b), nil
	})
	ans, err := svc.Ask(context.Background(), "tenant-adeco", "كام الإيراد؟")
	if err != nil {
		t.Fatal(err)
	}
	if ans.MappingSource != sourceAI {
		t.Fatalf("expected ai polish, got %s", ans.MappingSource)
	}
	if !strings.Contains(ans.AnswerAR, "120000.00") {
		t.Fatalf("polished answer lost number: %s", ans.AnswerAR)
	}
	if !ans.ReadOnly {
		t.Fatal("read_only must stay true")
	}
}

func TestAskRejectsFabricatedGeminiAnswer(t *testing.T) {
	f := seedFake()
	svc := New(f, "test-key", "gemini-3.8-flash", false).WithCaller(func(_ context.Context, _, _ string) (string, error) {
		payload := map[string]interface{}{
			"answer_ar": "إجمالي الإيراد 999999 ج.م فقط.",
			"claims": []Claim{
				{Metric: "total_revenue", Entity: "tenant", Value: 999999, Display: "999999 ج.م"},
			},
		}
		b, _ := json.Marshal(payload)
		return string(b), nil
	})
	ans, err := svc.Ask(context.Background(), "tenant-adeco", "كام الإيراد؟")
	if err != nil {
		t.Fatal(err)
	}
	if ans.MappingSource != sourceDet {
		t.Fatalf("fabricated polish must fall back to deterministic, got %s", ans.MappingSource)
	}
	if strings.Contains(ans.AnswerAR, "999999") {
		t.Fatalf("fabricated number leaked: %s", ans.AnswerAR)
	}
	if !strings.Contains(ans.AnswerAR, "120000") {
		t.Fatalf("deterministic revenue missing: %s", ans.AnswerAR)
	}
}

func TestAskRejectsEntityValueSwap(t *testing.T) {
	f := seedFake()
	svc := New(f, "test-key", "gemini-3.8-flash", false).WithCaller(func(_ context.Context, _, _ string) (string, error) {
		// Swap: attribute Carrefour's 50000 to Fathalla entity.
		payload := map[string]interface{}{
			"answer_ar": "فتح الله: 50000.00 ج.م؛ كارفور: 70000.00 ج.م",
			"claims": []Claim{
				{Metric: "total_revenue", Entity: "chain:فتح الله", Value: 50000, Display: "50000.00 ج.م"},
				{Metric: "total_revenue", Entity: "chain:كارفور", Value: 70000, Display: "70000.00 ج.م"},
			},
		}
		b, _ := json.Marshal(payload)
		return string(b), nil
	})
	ans, err := svc.Ask(context.Background(), "tenant-adeco", "وزّع حصص السلاسل")
	if err != nil {
		t.Fatal(err)
	}
	if ans.MappingSource != sourceDet {
		t.Fatalf("entity/value swap must fall back to deterministic, got %s answer=%s", ans.MappingSource, ans.AnswerAR)
	}
	if !strings.Contains(ans.AnswerAR, "فتح الله") || !strings.Contains(ans.AnswerAR, "70000.00") {
		t.Fatalf("deterministic chain binding broken: %s", ans.AnswerAR)
	}
}

func TestAskTodaySellInUnsupportedExecutiveOK(t *testing.T) {
	f := seedFake()
	f.kpisByPeriod = map[string]*domain.ExecutiveKPIs{
		"tenant-adeco|TODAY": {
			TotalRevenue: 321, TotalUnitsSold: 3, ActiveStoresCount: 1,
			TenantMarketSharePct: 2, RevenueMoMPct: 0, Currency: "EGP",
		},
	}
	svc := New(f, "", "", true)

	si, err := svc.Ask(context.Background(), "tenant-adeco", "ملخص سيل إن اليوم")
	if err != nil {
		t.Fatal(err)
	}
	if si.Intent != IntentUnsupported {
		t.Fatalf("TODAY sell-in must be unsupported, got %s", si.Intent)
	}
	if !strings.Contains(si.AnswerAR, "شهرية") && !strings.Contains(si.AnswerAR, "مش مدعوم") {
		t.Fatalf("TODAY sell-in message: %s", si.AnswerAR)
	}
	if len(f.sellInCalls) != 0 {
		t.Fatalf("TODAY sell-in must not query BQ: %#v", f.sellInCalls)
	}

	exec, err := svc.Ask(context.Background(), "tenant-adeco", "كام إجمالي المبيعات اليوم؟")
	if err != nil {
		t.Fatal(err)
	}
	if exec.Period != "TODAY" || exec.Intent != IntentExecutiveKPIs {
		t.Fatalf("executive TODAY: period=%s intent=%s", exec.Period, exec.Intent)
	}
	if !strings.Contains(exec.AnswerAR, "321") {
		t.Fatalf("TODAY must use real day-filtered KPIs: %s calls=%v", exec.AnswerAR, f.kpiCalls)
	}
	foundToday := false
	for _, c := range f.kpiCalls {
		if strings.HasSuffix(c, "|TODAY") {
			foundToday = true
		}
	}
	if !foundToday {
		t.Fatalf("expected GetExecutiveKPIs(..., TODAY), got %#v", f.kpiCalls)
	}
}

func TestAskSellInAggregatesBeyond5000(t *testing.T) {
	now := time.Now()
	recs := make([]domain.SellInRecord, 0, 6001)
	const head = 5000
	const headVal = 1.0
	const tailVal = 100.0
	for i := 0; i < head; i++ {
		recs = append(recs, domain.SellInRecord{
			TenantID: "tenant-adeco", Year: now.Year(), MonthNum: int(now.Month()),
			NetValueEGP: headVal, TotalUnitsSupplied: 1,
		})
	}
	recs = append(recs, domain.SellInRecord{
		TenantID: "tenant-adeco", Year: now.Year(), MonthNum: int(now.Month()),
		NetValueEGP: tailVal, TotalUnitsSupplied: 1,
	})
	f := seedFake()
	f.sellInByTenant["tenant-adeco"] = recs
	svc := New(f, "", "", true)
	ans, err := svc.Ask(context.Background(), "tenant-adeco", "كام إجمالي التوريد؟")
	if err != nil {
		t.Fatal(err)
	}
	want := float64(head)*headVal + tailVal // 5100
	if fmt.Sprintf("%.2f", want) != "5100.00" {
		t.Fatalf("fixture math: %v", want)
	}
	if !strings.Contains(ans.AnswerAR, "5100.00") {
		t.Fatalf("must aggregate all %d rows (not first 5000 only): %s; evidence=%v",
			len(recs), ans.AnswerAR, ans.Evidence)
	}
	if len(f.sellInFilters) != 1 || f.sellInFilters[0].Limit != 0 {
		t.Fatalf("Limit must be 0 for full scan: %+v", f.sellInFilters)
	}
	if got, _ := ans.Evidence["aggregated_rows"].(int); got != len(recs) {
		// JSON numbers may be int; also accept float64 from map
		if gf, ok := ans.Evidence["aggregated_rows"].(float64); !ok || int(gf) != len(recs) {
			if got != len(recs) {
				t.Fatalf("aggregated_rows=%v want %d", ans.Evidence["aggregated_rows"], len(recs))
			}
		}
	}
}

func TestAskPeriodSeparation(t *testing.T) {
	f := seedFake()
	f.kpisByPeriod = map[string]*domain.ExecutiveKPIs{
		"tenant-adeco|MTD": {
			TotalRevenue: 11111, TotalUnitsSold: 11, ActiveStoresCount: 2,
			TenantMarketSharePct: 1, RevenueMoMPct: 0, Currency: "EGP",
		},
		"tenant-adeco|ALL": {
			TotalRevenue: 99999, TotalUnitsSold: 99, ActiveStoresCount: 9,
			TenantMarketSharePct: 9, RevenueMoMPct: 0, Currency: "EGP",
		},
	}
	svc := New(f, "", "", true)
	mtd, err := svc.Ask(context.Background(), "tenant-adeco", "كام إجمالي المبيعات؟")
	if err != nil {
		t.Fatal(err)
	}
	all, err := svc.Ask(context.Background(), "tenant-adeco", "كام إجمالي المبيعات كل البيانات؟")
	if err != nil {
		t.Fatal(err)
	}
	if mtd.Period != "MTD" || all.Period != "ALL" {
		t.Fatalf("periods mtd=%s all=%s", mtd.Period, all.Period)
	}
	if !strings.Contains(mtd.AnswerAR, "11111") {
		t.Fatalf("MTD answer: %s", mtd.AnswerAR)
	}
	if !strings.Contains(all.AnswerAR, "99999") {
		t.Fatalf("ALL answer: %s", all.AnswerAR)
	}
	if mtd.AnswerAR == all.AnswerAR {
		t.Fatal("period-filtered answers must differ")
	}

	// Sell-In period filter also separates months.
	now := time.Now()
	f.sellInByTenant["tenant-adeco"] = []domain.SellInRecord{
		{TenantID: "tenant-adeco", Year: now.Year(), MonthNum: int(now.Month()), NetValueEGP: 300, TotalUnitsSupplied: 3},
		{TenantID: "tenant-adeco", Year: now.Year(), MonthNum: int(now.Month())%12 + 1, NetValueEGP: 700, TotalUnitsSupplied: 7},
	}
	siMTD, err := svc.Ask(context.Background(), "tenant-adeco", "ملخص سيل إن")
	if err != nil {
		t.Fatal(err)
	}
	siAll, err := svc.Ask(context.Background(), "tenant-adeco", "ملخص سيل إن كل البيانات")
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(siMTD.AnswerAR, "300.00") {
		t.Fatalf("sell-in MTD should be current month only: %s filter=%+v", siMTD.AnswerAR, f.sellInFilters)
	}
	if !strings.Contains(siAll.AnswerAR, "1000.00") {
		t.Fatalf("sell-in ALL should include both months: %s", siAll.AnswerAR)
	}
}

func TestCapabilitiesList(t *testing.T) {
	caps := Capabilities()
	if len(caps) < 5 {
		t.Fatalf("caps=%d", len(caps))
	}
	for _, c := range caps {
		if c.TitleAR == "" || len(c.ExamplesAR) == 0 || len(c.DataSources) == 0 {
			t.Fatalf("incomplete capability: %+v", c)
		}
	}
}

func TestPolishPreservesClaims(t *testing.T) {
	evidence := []Claim{
		{Metric: "total_revenue", Entity: "tenant", Value: 120000, Display: "120000.00 ج.م"},
		{Metric: "total_revenue", Entity: "chain:فتح الله", Value: 70000, Display: "70000.00 ج.م"},
		{Metric: "total_revenue", Entity: "chain:كارفور", Value: 50000, Display: "50000.00 ج.م"},
	}
	usedOK := []Claim{{Metric: "total_revenue", Entity: "tenant", Value: 120000, Display: "120000.00 ج.م"}}
	if !polishPreservesClaims("الإيراد بلغ 120000.00 ج.م", usedOK, evidence) {
		t.Fatal("valid bound claim rejected")
	}
	usedFab := []Claim{{Metric: "total_revenue", Entity: "tenant", Value: 999999, Display: "999999"}}
	if polishPreservesClaims("الإيراد 999999 ج.م", usedFab, evidence) {
		t.Fatal("fabricated claim value accepted")
	}
	usedSwap := []Claim{
		{Metric: "total_revenue", Entity: "chain:فتح الله", Value: 50000, Display: "50000.00 ج.م"},
	}
	if polishPreservesClaims("فتح الله: 50000.00 ج.م", usedSwap, evidence) {
		t.Fatal("entity/value swap accepted")
	}
	if polishPreservesClaims("مفيش أرقام هنا", usedOK, evidence) {
		t.Fatal("narrative without claim numbers accepted")
	}
}

func TestSellInFilterForPeriod(t *testing.T) {
	now := time.Date(2026, 11, 8, 12, 0, 0, 0, time.UTC)
	all, ok := sellInFilterForPeriod("ALL", now)
	if !ok || all.Limit != 0 || all.Year != 0 || all.Month != 0 {
		t.Fatalf("ALL: %+v ok=%v", all, ok)
	}
	mtd, ok := sellInFilterForPeriod("MTD", now)
	if !ok || mtd.Limit != 0 || mtd.Year != 2026 || mtd.Month != 11 {
		t.Fatalf("MTD: %+v ok=%v", mtd, ok)
	}
	ytd, ok := sellInFilterForPeriod("YTD", now)
	if !ok || ytd.Year != 2026 || ytd.Month != 0 {
		t.Fatalf("YTD: %+v ok=%v", ytd, ok)
	}
	if _, ok := sellInFilterForPeriod("TODAY", now); ok {
		t.Fatal("TODAY sell-in must be unsupported (no day grain)")
	}
}
