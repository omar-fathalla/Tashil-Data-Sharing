package handlers

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/tashil/data-sharing/backend/internal/domain"
)

func TestYearMonthRange(t *testing.T) {
	if s, e, ok := yearMonthRange(2025, 0); !ok || s != "2025-01-01" || e != "2025-12-31" {
		t.Fatalf("year range wrong: %s %s %v", s, e, ok)
	}
	if s, e, ok := yearMonthRange(2026, 3); !ok || s != "2026-03-01" || e != "2026-03-31" {
		t.Fatalf("month range wrong: %s %s %v", s, e, ok)
	}
	if _, _, ok := yearMonthRange(0, 3); ok {
		t.Fatal("no year must not produce a range")
	}
}

func TestExecutiveSummaryHonoursYear(t *testing.T) {
	handler, bqClient := setupTestAnalyticsHandler()
	tenantID := "tenant-year-filter-test"
	_ = bqClient.InsertSellOutFacts(context.Background(), []domain.SellOutFact{
		{RecordID: "y25", TenantID: tenantID, RetailerChain: "fathalla", StoreID: "s1", StoreName: "فرع 1", Barcode: "1", SKUName: "A", QuantitySold: 10, NetRevenue: 1000, UnitPrice: 100, TransactionDate: "2025-02-28"},
		{RecordID: "y26", TenantID: tenantID, RetailerChain: "fathalla", StoreID: "s1", StoreName: "فرع 1", Barcode: "1", SKUName: "A", QuantitySold: 30, NetRevenue: 3000, UnitPrice: 100, TransactionDate: "2026-02-28"},
	})
	for yr, want := range map[string]float64{"2025": 1000, "2026": 3000} {
		rec := httptest.NewRecorder()
		handler.HandleExecutiveSummary(rec, authenticatedRequest(http.MethodGet, "/api/v1/analytics/executive?year="+yr, tenantID))
		if rec.Code != http.StatusOK {
			t.Fatalf("year %s: HTTP %d", yr, rec.Code)
		}
		var kpis domain.ExecutiveKPIs
		if err := json.NewDecoder(rec.Body).Decode(&kpis); err != nil {
			t.Fatalf("decode: %v", err)
		}
		if kpis.TotalRevenue != want {
			t.Errorf("year %s: revenue %v, want %v", yr, kpis.TotalRevenue, want)
		}
	}
}
