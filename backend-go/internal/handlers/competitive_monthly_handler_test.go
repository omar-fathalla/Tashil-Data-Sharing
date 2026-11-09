package handlers

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/tashil/data-sharing/backend/internal/domain"
	"github.com/tashil/data-sharing/backend/internal/service/bigquery"
)

func TestHandleCompetitiveMonthlyJanThroughOct(t *testing.T) {
	bqRepo := bigquery.NewClient("tashil-test", "retail", true)
	_ = bqRepo.ClearTenantData(context.Background(), "all")
	var facts []domain.SellOutFact
	for m := 1; m <= 10; m++ {
		facts = append(facts, domain.SellOutFact{
			RecordID:        fmt.Sprintf("r-%d", m),
			TenantID:        "tenant-adeco",
			RetailerChain:   "fathalla",
			Barcode:         "6223000239438",
			SKUName:         "فيبا 3 كجم",
			QuantitySold:    10,
			UnitPrice:       float64(100 + m),
			NetRevenue:      10 * float64(100+m),
			TransactionDate: fmt.Sprintf("2026-%02d-15", m),
			IsOwnBrand:      true,
		})
	}
	if err := bqRepo.ReplaceTenantFacts(context.Background(), "tenant-adeco", facts); err != nil {
		t.Fatal(err)
	}

	h := NewAnalyticsHandler(bqRepo)
	w := httptest.NewRecorder()
	h.HandleCompetitiveMonthly(w, authenticatedRequest(
		http.MethodGet,
		"/api/v1/analytics/competitive-monthly?year=2026&chain=fathalla&supplier=all_market",
		"tenant-adeco",
	))
	if w.Code != http.StatusOK {
		t.Fatalf("status %d: %s", w.Code, w.Body.String())
	}
	var resp bigquery.CompetitiveMonthlyResult
	if err := json.Unmarshal(w.Body.Bytes(), &resp); err != nil {
		t.Fatal(err)
	}
	if len(resp.Months) != 10 {
		t.Fatalf("months=%v want Jan–Oct", resp.Months)
	}
	for i, want := range []int{1, 2, 3, 4, 5, 6, 7, 8, 9, 10} {
		if resp.Months[i] != want {
			t.Fatalf("month[%d]=%d want %d", i, resp.Months[i], want)
		}
	}
	if len(resp.Items) != 1 || resp.Items[0].Barcode != "6223000239438" {
		t.Fatalf("items=%+v", resp.Items)
	}
	if len(resp.Items[0].Months) != 10 {
		t.Fatalf("series len=%d", len(resp.Items[0].Months))
	}
	if resp.Source != "memory" {
		t.Fatalf("source=%s", resp.Source)
	}
}

func TestMergeMonthListsUnionsMemoryAndBQ(t *testing.T) {
	got := mergeMonthLists([]int{1, 2, 3, 4}, []int{4, 5, 6, 7, 8, 9, 10})
	want := []int{1, 2, 3, 4, 5, 6, 7, 8, 9, 10}
	if len(got) != len(want) {
		t.Fatalf("got %v", got)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("got %v want %v", got, want)
		}
	}
}
