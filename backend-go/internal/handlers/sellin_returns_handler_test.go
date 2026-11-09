package handlers

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/tashil/data-sharing/backend/internal/domain"
	"github.com/tashil/data-sharing/backend/internal/service/bigquery"
)

func TestHandleSellInReturns_SyntheticAggregation(t *testing.T) {
	bqRepo := bigquery.NewClient("tashil-test", "retail", true)
	_ = bqRepo.ClearTenantData(context.Background(), "all")
	bqRepo.ReplaceSellInRecords("tenant-adeco", []domain.SellInRecord{
		{RecordID: "1", TenantID: "tenant-adeco", RetailerChain: "fathalla", Year: 2026, MonthNum: 1, CustomerName: "فرع تجريبي أ", CustomerBranchCode: "qa-a", ItemName: "منظف QA", ItemCode: "QA-1", ItemGroup: "منظفات", NetValueEGP: 200, NetQtyCases: 20},
		{RecordID: "2", TenantID: "tenant-adeco", RetailerChain: "fathalla", Year: 2026, MonthNum: 1, CustomerName: "فرع تجريبي أ", CustomerBranchCode: "qa-a", ItemName: "منظف QA", ItemCode: "QA-1", ItemGroup: "منظفات", NetValueEGP: -50, NetQtyCases: -5, TransactionType: "مرتجع (Return)"},
		{RecordID: "3", TenantID: "tenant-adeco", RetailerChain: "fathalla", Year: 2026, MonthNum: 2, CustomerName: "فرع تجريبي ب", CustomerBranchCode: "qa-b", ItemName: "ملمع QA", ItemCode: "QA-2", ItemGroup: "عناية", NetValueEGP: 100, NetQtyCases: 10},
		{RecordID: "4", TenantID: "tenant-adeco", RetailerChain: "fathalla", Year: 2026, MonthNum: 2, CustomerName: "فرع تجريبي ب", CustomerBranchCode: "qa-b", ItemName: "ملمع QA", ItemCode: "QA-2", ItemGroup: "عناية", NetValueEGP: -120, NetQtyCases: -12, TransactionType: "مرتجع (Return)"},
	})

	h := NewAnalyticsHandler(bqRepo)
	w := httptest.NewRecorder()
	h.HandleSellInReturns(w, authenticatedRequest(http.MethodGet, "/api/v1/analytics/sell-in-returns?year=2026", "tenant-adeco"))
	if w.Code != http.StatusOK {
		t.Fatalf("status %d body %s", w.Code, w.Body.String())
	}
	var rep bigquery.SellInReturnsReport
	if err := json.NewDecoder(w.Body).Decode(&rep); err != nil {
		t.Fatal(err)
	}
	if len(rep.Months) != 2 {
		t.Fatalf("months %v", rep.Months)
	}
	if rep.KPIs.ReturnsValueEGP != 170 {
		t.Fatalf("returns %v", rep.KPIs.ReturnsValueEGP)
	}
	if len(rep.Advisories) == 0 {
		t.Fatal("expected net-negative advisory for branch B Feb (100-120)")
	}
	if len(rep.TopReturnedProducts) == 0 {
		t.Fatal("expected Phase-2 top returned products")
	}
	if rep.TopReturnedProducts[0].ReturnsValueEGP <= 0 {
		t.Fatalf("top product returns: %+v", rep.TopReturnedProducts[0])
	}
	if len(rep.Alerts) == 0 {
		t.Fatal("expected Phase-2 threshold alerts (high return %)")
	}

	w2 := httptest.NewRecorder()
	h.HandleSellInReturns(w2, authenticatedRequest(http.MethodGet, "/api/v1/analytics/sell-in-returns?year=2026", "tenant-other"))
	var empty bigquery.SellInReturnsReport
	_ = json.NewDecoder(w2.Body).Decode(&empty)
	if empty.KPIs.ReturnsValueEGP != 0 || len(empty.Branches) != 0 {
		t.Fatalf("cross-tenant leak: %+v", empty.KPIs)
	}
	if len(empty.TopReturnedProducts) != 0 || len(empty.Alerts) != 0 {
		t.Fatalf("cross-tenant Phase-2 leak: top=%v alerts=%v", empty.TopReturnedProducts, empty.Alerts)
	}
}
