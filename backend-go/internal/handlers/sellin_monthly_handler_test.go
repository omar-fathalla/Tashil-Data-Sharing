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

func TestAggregateSellInMonthly(t *testing.T) {
	got := aggregateSellInMonthly([]domain.SellInRecord{
		{RetailerChain: "Fathalla", Year: 2026, MonthNum: 2, NetValueEGP: 100.004},
		{RetailerChain: "fathalla", Year: 2026, MonthNum: 2, NetValueEGP: 50},
		{RetailerChain: "fathalla", Year: 2026, MonthNum: 1, NetValueEGP: -10},
		{RetailerChain: "gomla", Year: 2026, MonthNum: 1, NetValueEGP: 7},
		{RetailerChain: "", Year: 2026, MonthNum: 1, NetValueEGP: 99},
		{RetailerChain: "gomla", Year: 2026, MonthNum: 0, NetValueEGP: 99},
	})
	want := []SellInMonthlyChainPoint{
		{"2026-01", "fathalla", -10},
		{"2026-01", "gomla", 7},
		{"2026-02", "fathalla", 150},
	}
	if len(got) != len(want) {
		t.Fatalf("got %+v", got)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("point %d: got %+v want %+v", i, got[i], want[i])
		}
	}
}

func TestHandleSellInMonthly(t *testing.T) {
	bqRepo := bigquery.NewClient("tashil-test", "retail", true)
	_ = bqRepo.ClearTenantData(context.Background(), "all")
	bqRepo.ReplaceSellInRecords("tenant-adeco", []domain.SellInRecord{
		{RetailerChain: "fathalla", Year: 2026, MonthNum: 3, NetValueEGP: 1000},
		{RetailerChain: "fathalla", Year: 2025, MonthNum: 3, NetValueEGP: 500},
	})
	h := NewAnalyticsHandler(bqRepo)
	w := httptest.NewRecorder()
	h.HandleSellInMonthly(w, authenticatedRequest(http.MethodGet, "/api/v1/analytics/sell-in-monthly?year=2026", "tenant-adeco"))
	if w.Code != http.StatusOK {
		t.Fatalf("status %d: %s", w.Code, w.Body.String())
	}
	var resp SellInMonthlyResponse
	if err := json.Unmarshal(w.Body.Bytes(), &resp); err != nil {
		t.Fatal(err)
	}
	if len(resp.Points) != 1 || resp.Points[0].MonthKey != "2026-03" || resp.Points[0].NetValueEGP != 1000 {
		t.Fatalf("unexpected points: %+v", resp.Points)
	}
}
