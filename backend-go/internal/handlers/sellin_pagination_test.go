package handlers

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/tashil/data-sharing/backend/internal/domain"
	"github.com/tashil/data-sharing/backend/internal/service/bigquery"
	"github.com/tashil/data-sharing/backend/internal/service/bqsink"
)

const pageTenant = "tenant-sellin-paging"

func pageFetch(t *testing.T, h *AnalyticsHandler, query string) PaginatedSellInRecordsResponse {
	t.Helper()
	w := httptest.NewRecorder()
	h.HandleSellInRecords(w, authenticatedRequest(http.MethodGet, "/api/v1/analytics/sell-in-records?"+query, pageTenant))
	if w.Code != http.StatusOK {
		t.Fatalf("%s: status %d: %s", query, w.Code, w.Body.String())
	}
	var r PaginatedSellInRecordsResponse
	if err := json.Unmarshal(w.Body.Bytes(), &r); err != nil {
		t.Fatal(err)
	}
	return r
}

// Paging the in-memory path by limit/offset reaches total_count in ceil(total/limit) requests, with
// disjoint pages even when most rows tie on every sort key except record_id.
func TestSellInRecordsOffsetPagingTerminatesAndCoversTotal(t *testing.T) {
	repo := bigquery.NewClient("tashil-test", "retail", true)
	_ = repo.ClearTenantData(context.Background(), "all")
	const n = 53
	rows := make([]domain.SellInRecord, 0, n)
	for i := n - 1; i >= 0; i-- { // reverse id order so the tie-break must reorder
		rows = append(rows, domain.SellInRecord{
			RecordID: fmt.Sprintf("r%03d", i), TenantID: pageTenant, RetailerChain: "fathalla",
			Year: 2026, MonthNum: 10, ItemName: "SKU", NetQtyCases: 1, NetValueEGP: float64(100 * (i % 3)),
		})
	}
	repo.ReplaceSellInRecords(pageTenant, rows)
	h := NewAnalyticsHandler(repo)

	const limit = 20
	seen := map[string]bool{}
	var sizes []int
	offset, requests := 0, 0
	for {
		requests++
		if requests > n/limit+2 {
			t.Fatalf("paging did not terminate after %d requests (offset %d)", requests, offset)
		}
		// The in-memory copy may be reloaded in another order between page requests.
		rotated := append(append([]domain.SellInRecord{}, rows[requests*7%n:]...), rows[:requests*7%n]...)
		repo.ReplaceSellInRecords(pageTenant, rotated)
		r := pageFetch(t, h, fmt.Sprintf("year=2026&limit=%d&offset=%d", limit, offset))
		if r.TotalCount != n || r.Limit != limit || r.Offset != offset {
			t.Fatalf("offset %d: total=%d limit=%d offset=%d", offset, r.TotalCount, r.Limit, r.Offset)
		}
		sizes = append(sizes, len(r.Records))
		for _, rec := range r.Records {
			if seen[rec.RecordID] {
				t.Fatalf("offset %d: %s already returned by an earlier page", offset, rec.RecordID)
			}
			seen[rec.RecordID] = true
		}
		offset += len(r.Records)
		if len(r.Records) < limit || offset >= r.TotalCount {
			break
		}
	}
	if len(seen) != n || fmt.Sprint(sizes) != "[20 20 13]" {
		t.Fatalf("pages %v covered %d of %d rows", sizes, len(seen), n)
	}

	// Past the end: no rows, same total, so a client loop stops.
	if r := pageFetch(t, h, "year=2026&limit=20&offset=60"); len(r.Records) != 0 || r.TotalCount != n {
		t.Fatalf("past end: %d rows, total %d", len(r.Records), r.TotalCount)
	}
	// An oversized limit is clamped to the max (and echoed), not silently reset to 250.
	if r := pageFetch(t, h, "year=2026&limit=5000"); r.Limit != maxSellInRecordsLimit || len(r.Records) != n {
		t.Fatalf("limit clamp: limit=%d rows=%d", r.Limit, len(r.Records))
	}
	// KPI totals cover the whole filter on every page, not just the page rows.
	first, last := pageFetch(t, h, "year=2026&limit=20&offset=0"), pageFetch(t, h, "year=2026&limit=20&offset=40")
	if first.TotalValueEGP != last.TotalValueEGP || first.TotalCases != n {
		t.Fatalf("totals differ by page: %v vs %v (cases %v)", first.TotalValueEGP, last.TotalValueEGP, first.TotalCases)
	}
}

// The BigQuery path forwards limit/offset to the page query and reports total_count from the totals query.
func TestSellInRecordsBigQueryPathForwardsOffset(t *testing.T) {
	repo := bigquery.NewClient("tashil-test", "retail", true)
	_ = repo.ClearTenantData(context.Background(), "all")
	fake := &fakeSellInQuerier{res: &bqsink.SellInTotalsResult{
		Totals: bqsink.SellInTotals{Count: 41, NetValue: 4100},
		Page:   []domain.SellInRecord{{RecordID: "b21", Year: 2026, MonthNum: 3, NetValueEGP: 100}},
	}}
	h := NewAnalyticsHandler(repo).WithSellInTotalsQuerier(fake)
	r := pageFetch(t, h, "year=2026&limit=20&offset=40")
	if fake.got.Limit != 20 || fake.got.Offset != 40 {
		t.Fatalf("page query got limit=%d offset=%d", fake.got.Limit, fake.got.Offset)
	}
	if r.TotalCount != 41 || r.Offset != 40 || r.Limit != 20 || len(r.Records) != 1 {
		t.Fatalf("response total=%d offset=%d limit=%d rows=%d", r.TotalCount, r.Offset, r.Limit, len(r.Records))
	}
	if _, _, page, _ := bqsink.SellInTotalsSQL("`p.d.t`", bqsink.SellInTotalsQuery{TenantID: pageTenant, Limit: 20, Offset: 40}); !strings.Contains(page, "record_id LIMIT @limit OFFSET @offset") {
		t.Fatal("BigQuery page must end on the unique record_id before LIMIT/OFFSET")
	}
}
