package handlers

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/tashil/data-sharing/backend/internal/domain"
	"github.com/tashil/data-sharing/backend/internal/service/bigquery"
	"github.com/tashil/data-sharing/backend/internal/service/bqsink"
)

// BigQuery answers Count == 0: with nothing in memory for that filter the empty BigQuery answer is
// served (no wait for the in-memory load); with matching rows in memory the memory path is used.
func TestSellInEmptyBigQueryAnswer(t *testing.T) {
	repo := bigquery.NewClient("tashil-test", "retail", true)
	_ = repo.ClearTenantData(context.Background(), "all")
	repo.ReplaceSellInRecords("tenant-adeco", []domain.SellInRecord{
		{RecordID: "m1", RetailerChain: "fathalla", Year: 2026, MonthNum: 3, NetValueEGP: 1000},
	})
	fake := &fakeSellInQuerier{res: &bqsink.SellInTotalsResult{}}
	h := NewAnalyticsHandler(repo).WithSellInTotalsQuerier(fake)
	for url, want := range map[string]string{
		"/api/v1/analytics/sell-in-records?year=2027": "bigquery",
		"/api/v1/analytics/sell-in-records?year=2026": "memory",
	} {
		w := httptest.NewRecorder()
		h.HandleSellInRecords(w, authenticatedRequest(http.MethodGet, url, "tenant-adeco"))
		if got := w.Header().Get("X-Records-Source"); got != want || w.Code != http.StatusOK {
			t.Fatalf("%s: source %q code %d, want %s", url, got, w.Code, want)
		}
	}
}
