package arabicqa

import (
	"context"
	"encoding/json"
	"strings"
	"testing"

	"github.com/tashil/data-sharing/backend/internal/domain"
	"github.com/tashil/data-sharing/backend/internal/service/bigquery"
)

type fakeReader struct {
	kpisByTenant   map[string]*domain.ExecutiveKPIs
	sharesByTenant map[string][]domain.ChainShareSummary
	sellInByTenant map[string][]domain.SellInRecord
	kpiCalls       []string
	shareCalls     []string
	sellInCalls    []string
	writes         int
}

func (f *fakeReader) GetExecutiveKPIs(_ context.Context, tenantID, _ string, _ ...string) (*domain.ExecutiveKPIs, error) {
	f.kpiCalls = append(f.kpiCalls, tenantID)
	return f.kpisByTenant[tenantID], nil
}

func (f *fakeReader) GetChainShares(_ context.Context, tenantID, _ string, _ ...string) ([]domain.ChainShareSummary, error) {
	f.shareCalls = append(f.shareCalls, tenantID)
	return f.sharesByTenant[tenantID], nil
}

func (f *fakeReader) GetSellInRecords(_ context.Context, tenantID string, _ bigquery.SellInRecordFilter) ([]domain.SellInRecord, int, error) {
	f.sellInCalls = append(f.sellInCalls, tenantID)
	recs := f.sellInByTenant[tenantID]
	return recs, len(recs), nil
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
				{TenantID: "tenant-adeco", NetValueEGP: 15000, NetQtyCases: 100, TotalUnitsSupplied: 1200},
				{TenantID: "tenant-adeco", NetValueEGP: 5000, NetQtyCases: 40, TotalUnitsSupplied: 400},
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
	if len(f.kpiCalls) != 1 || f.kpiCalls[0] != "tenant-adeco" {
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
	// Asking as another tenant must not see adeco chains.
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
		if !strings.Contains(prompt, "120000") && !strings.Contains(prompt, "الأدلة") {
			t.Fatalf("prompt missing grounded evidence: %s", prompt)
		}
		if strings.Contains(prompt, "test-key") {
			t.Fatal("api key leaked into prompt")
		}
		b, _ := json.Marshal(map[string]string{"answer_ar": "إيراد المستأجر 120000.00 ج.م هذا الشهر (قراءة فقط)."})
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
