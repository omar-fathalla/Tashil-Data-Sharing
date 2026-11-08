package handlers

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/tashil/data-sharing/backend/internal/domain"
	"github.com/tashil/data-sharing/backend/internal/service/monthlysummary"
)

func TestExecutiveSummaryIncludesMonthlyNarrative(t *testing.T) {
	handler, bqClient := setupTestAnalyticsHandler()
	handler.WithMonthlySummary(monthlysummary.Options{UseMock: true})

	tenantID := "tenant-monthly-summary"
	_ = bqClient.InsertSellOutFacts(context.Background(), []domain.SellOutFact{
		{
			RecordID: "ms1", TenantID: tenantID, RetailerChain: "fathalla", StoreID: "s1", StoreName: "سموحة",
			Barcode: "100", SKUName: "Oil", QuantitySold: 100, NetRevenue: 50000, UnitPrice: 500,
			TransactionDate: "2026-10-15",
		},
		{
			RecordID: "ms2", TenantID: tenantID, RetailerChain: "fathalla", StoreID: "s1", StoreName: "سموحة",
			Barcode: "101", SKUName: "Ghee", QuantitySold: 40, NetRevenue: 25000, UnitPrice: 625,
			TransactionDate: "2026-10-16",
		},
	})

	req := authenticatedRequest(http.MethodGet, "/api/v1/analytics/executive-summary?year=2026&month=10", tenantID)
	rec := httptest.NewRecorder()
	handler.HandleExecutiveSummary(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("status %d body %s", rec.Code, rec.Body.String())
	}

	var kpis domain.ExecutiveKPIs
	if err := json.Unmarshal(rec.Body.Bytes(), &kpis); err != nil {
		t.Fatal(err)
	}
	if kpis.MonthlySummary == nil {
		t.Fatal("expected monthly_summary in executive-summary JSON")
	}
	ms := kpis.MonthlySummary
	if ms.MappingSource != monthlysummary.SourceDeterministic {
		t.Fatalf("mapping_source=%s", ms.MappingSource)
	}
	if !ms.Grounded || ms.NarrativeAR == "" {
		t.Fatalf("narrative not grounded: %+v", ms)
	}
	if ms.Aggregates.TotalRevenue <= 0 {
		t.Fatalf("aggregates empty: %+v", ms.Aggregates)
	}
	if ms.Confidence <= 0 {
		t.Fatalf("confidence=%v", ms.Confidence)
	}
}

func TestExecutiveSummaryMonthlyNarrativeTenantScoped(t *testing.T) {
	handler, bqClient := setupTestAnalyticsHandler()
	handler.WithMonthlySummary(monthlysummary.Options{UseMock: true})

	_ = bqClient.InsertSellOutFacts(context.Background(), []domain.SellOutFact{
		{RecordID: "ta1", TenantID: "tenant-ms-a", RetailerChain: "fathalla", StoreID: "s1", StoreName: "A",
			Barcode: "1", SKUName: "A", QuantitySold: 9, NetRevenue: 90000, UnitPrice: 10000, TransactionDate: "2026-10-01"},
		{RecordID: "tb1", TenantID: "tenant-ms-b", RetailerChain: "carrefour", StoreID: "s2", StoreName: "B",
			Barcode: "2", SKUName: "B", QuantitySold: 1, NetRevenue: 1000, UnitPrice: 1000, TransactionDate: "2026-10-01"},
	})

	reqA := authenticatedRequest(http.MethodGet, "/api/v1/analytics/executive-summary?year=2026&month=10", "tenant-ms-a")
	recA := httptest.NewRecorder()
	handler.HandleExecutiveSummary(recA, reqA)
	var kpisA domain.ExecutiveKPIs
	_ = json.Unmarshal(recA.Body.Bytes(), &kpisA)

	reqB := authenticatedRequest(http.MethodGet, "/api/v1/analytics/executive-summary?year=2026&month=10", "tenant-ms-b")
	recB := httptest.NewRecorder()
	handler.HandleExecutiveSummary(recB, reqB)
	var kpisB domain.ExecutiveKPIs
	_ = json.Unmarshal(recB.Body.Bytes(), &kpisB)

	if kpisA.MonthlySummary == nil || kpisB.MonthlySummary == nil {
		t.Fatal("both tenants need monthly_summary")
	}
	if kpisA.MonthlySummary.Aggregates.TotalRevenue == kpisB.MonthlySummary.Aggregates.TotalRevenue {
		t.Fatalf("tenant leakage: A=%v B=%v",
			kpisA.MonthlySummary.Aggregates.TotalRevenue,
			kpisB.MonthlySummary.Aggregates.TotalRevenue)
	}
}
