package handlers

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/tashil/data-sharing/backend/internal/domain"
	"github.com/tashil/data-sharing/backend/internal/middleware"
	"github.com/tashil/data-sharing/backend/internal/service/arabicqa"
	"github.com/tashil/data-sharing/backend/internal/service/bigquery"
)

type qaFakeReader struct {
	kpis *domain.ExecutiveKPIs
}

func (f *qaFakeReader) GetExecutiveKPIs(_ context.Context, tenantID, _ string, _ ...string) (*domain.ExecutiveKPIs, error) {
	if tenantID != "tenant-adeco" {
		return &domain.ExecutiveKPIs{}, nil
	}
	return f.kpis, nil
}

func (f *qaFakeReader) GetChainShares(_ context.Context, tenantID, _ string, _ ...string) ([]domain.ChainShareSummary, error) {
	if tenantID != "tenant-adeco" || f.kpis == nil {
		return nil, nil
	}
	return f.kpis.ChainShares, nil
}

func (f *qaFakeReader) GetSellInRecords(_ context.Context, _ string, _ bigquery.SellInRecordFilter) ([]domain.SellInRecord, int, error) {
	return nil, 0, nil
}

func arabicQAMux(t *testing.T) (http.Handler, *middleware.AuthMiddleware) {
	t.Helper()
	reader := &qaFakeReader{kpis: &domain.ExecutiveKPIs{
		TotalRevenue:         99000,
		TotalUnitsSold:       1200,
		ActiveStoresCount:    8,
		TenantMarketSharePct: 11,
		RevenueMoMPct:        2.5,
		Currency:             "EGP",
		ChainShares: []domain.ChainShareSummary{
			{RetailerChain: "fathalla", DisplayName: "فتح الله", TotalRevenue: 60000},
		},
	}}
	svc := arabicqa.New(reader, "", "", true)
	h := NewArabicQAHandler(svc)
	mw := middleware.NewAuthMiddleware("test-secret", false)
	mux := http.NewServeMux()
	mux.HandleFunc("POST /api/v1/analytics/ask", h.HandleAsk)
	mux.HandleFunc("GET /api/v1/analytics/ask/capabilities", h.HandleCapabilities)
	return mw.Handler(mux), mw
}

func TestArabicQAAskAndCapabilities(t *testing.T) {
	h, mw := arabicQAMux(t)
	tok, err := mw.GenerateToken(domain.UserClaims{
		UserID: "u1", Email: "admin@test", TenantID: "tenant-adeco", Role: domain.RoleVendorAdmin,
	}, time.Hour)
	if err != nil {
		t.Fatal(err)
	}

	req := httptest.NewRequest(http.MethodPost, "/api/v1/analytics/ask", strings.NewReader(`{"question":"كام إجمالي المبيعات؟"}`))
	req.Header.Set("Authorization", "Bearer "+tok)
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("ask status %d %s", rec.Code, rec.Body.String())
	}
	var ans arabicqa.Answer
	if err := json.Unmarshal(rec.Body.Bytes(), &ans); err != nil {
		t.Fatal(err)
	}
	if !ans.ReadOnly || ans.TenantID != "tenant-adeco" || ans.Intent != arabicqa.IntentExecutiveKPIs {
		t.Fatalf("bad answer: %+v", ans)
	}
	if !strings.Contains(ans.AnswerAR, "99000") {
		t.Fatalf("answer missing revenue: %s", ans.AnswerAR)
	}

	req = httptest.NewRequest(http.MethodGet, "/api/v1/analytics/ask/capabilities", nil)
	req.Header.Set("Authorization", "Bearer "+tok)
	rec = httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("capabilities %d %s", rec.Code, rec.Body.String())
	}
	var caps map[string]interface{}
	_ = json.Unmarshal(rec.Body.Bytes(), &caps)
	if caps["read_only"] != true {
		t.Fatalf("caps=%v", caps)
	}

	req = httptest.NewRequest(http.MethodPost, "/api/v1/analytics/ask", strings.NewReader(`{"question":"كام؟"}`))
	rec = httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("want 401, got %d", rec.Code)
	}
}
