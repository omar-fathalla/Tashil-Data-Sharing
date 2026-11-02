package handlers

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/tashil/data-sharing/backend/internal/domain"
	"github.com/tashil/data-sharing/backend/internal/service/bqsink"
)

type fakeRecordsQuerier struct {
	res   *bqsink.RecordsResult
	err   error
	calls int
	last  bqsink.RecordsQuery
}

func (f *fakeRecordsQuerier) QuerySellOutRecords(_ context.Context, q bqsink.RecordsQuery) (*bqsink.RecordsResult, error) {
	f.calls++
	f.last = q
	return f.res, f.err
}

func seedRecordsFallbackTenant(t *testing.T) (*AnalyticsHandler, string) {
	handler, bqClient := setupTestAnalyticsHandler()
	tenantID := "tenant-records-bq-fallback-test"
	if err := bqClient.InsertSellOutFacts(context.Background(), []domain.SellOutFact{{
		RecordID: "fb_1", TenantID: tenantID, RetailerChain: "fathalla", StoreID: "s1", StoreName: "فرع 1",
		Barcode: "6221155009999", SKUName: "Adeco Test 1L", QuantitySold: 4, NetRevenue: 400, UnitPrice: 100,
		TransactionDate: "2026-03-10",
	}}); err != nil {
		t.Fatalf("seed: %v", err)
	}
	return handler, tenantID
}

func decodeRecords(t *testing.T, rec *httptest.ResponseRecorder) PaginatedRecordsResponse {
	t.Helper()
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", rec.Code)
	}
	var resp PaginatedRecordsResponse
	if err := json.NewDecoder(rec.Body).Decode(&resp); err != nil {
		t.Fatalf("decode: %v", err)
	}
	return resp
}

func TestHandleRecordsFallsBackToMemoryOnBigQueryError(t *testing.T) {
	handler, tenantID := seedRecordsFallbackTenant(t)
	fake := &fakeRecordsQuerier{err: errors.New("bq down")}
	handler.WithRecordsQuerier(fake)
	rec := httptest.NewRecorder()
	handler.HandleRecords(rec, authenticatedRequest(http.MethodGet, "/api/v1/analytics/records?supplier=all", tenantID))
	resp := decodeRecords(t, rec)
	if fake.calls != 1 || rec.Header().Get("X-Records-Source") != "memory" {
		t.Fatalf("expected one BQ attempt then memory, calls=%d source=%q", fake.calls, rec.Header().Get("X-Records-Source"))
	}
	if resp.TotalCount != 1 || resp.TotalNetRevenue != 400 {
		t.Errorf("memory fallback wrong: %+v", resp)
	}
}

func TestHandleRecordsSkipsBigQueryForSearchAndEmptyResults(t *testing.T) {
	handler, tenantID := seedRecordsFallbackTenant(t)
	fake := &fakeRecordsQuerier{res: &bqsink.RecordsResult{}}
	handler.WithRecordsQuerier(fake)

	rec := httptest.NewRecorder()
	handler.HandleRecords(rec, authenticatedRequest(http.MethodGet, "/api/v1/analytics/records?supplier=all&q=Adeco", tenantID))
	decodeRecords(t, rec)
	if fake.calls != 0 || rec.Header().Get("X-Records-Source") != "memory" {
		t.Fatalf("search must bypass BigQuery, calls=%d", fake.calls)
	}

	rec = httptest.NewRecorder()
	handler.HandleRecords(rec, authenticatedRequest(http.MethodGet, "/api/v1/analytics/records?supplier=all", tenantID))
	resp := decodeRecords(t, rec)
	if fake.calls != 1 || rec.Header().Get("X-Records-Source") != "memory" || resp.TotalCount != 1 {
		t.Fatalf("empty BQ result must fall back to memory, calls=%d resp=%+v", fake.calls, resp)
	}
}

func recordsHaveSingleID(records interface{}, id string) bool {
	raw, _ := json.Marshal(records)
	var rows []domain.SellOutFact
	_ = json.Unmarshal(raw, &rows)
	return len(rows) == 1 && rows[0].RecordID == id
}

func TestHandleRecordsServesBigQueryResult(t *testing.T) {
	handler, tenantID := seedRecordsFallbackTenant(t)
	fake := &fakeRecordsQuerier{res: &bqsink.RecordsResult{
		Totals: bqsink.RecordsTotals{TotalCount: 2, NetRevenue: 1000, UnitsSold: 10, Stores: 1, SKUs: 1},
		SKUs:   []bqsink.RecordsSKU{{ItemCode: "A1", SKUName: "Adeco X", UnitsSold: 10, NetRevenue: 1000, UnitsPerCarton: 5, FactoryUnitCost: 50, Stores: 1}},
		Page:   []domain.SellOutFact{{RecordID: "bq_1", NetRevenue: 500}},
	}}
	handler.WithRecordsQuerier(fake)
	rec := httptest.NewRecorder()
	handler.HandleRecords(rec, authenticatedRequest(http.MethodGet, "/api/v1/analytics/records?chain=fathalla&limit=1&offset=1", tenantID))
	resp := decodeRecords(t, rec)
	if rec.Header().Get("X-Records-Source") != "bigquery" || resp.TotalCount != 2 || !recordsHaveSingleID(resp.Records, "bq_1") {
		t.Fatalf("unexpected BQ response: %+v", resp)
	}
	if fake.last.Chain != "fathalla" || fake.last.Limit != 1 || fake.last.Offset != 1 || fake.last.TenantID != tenantID {
		t.Errorf("query not forwarded: %+v", fake.last)
	}
	s := resp.SKUSummaries[0]
	if s.TotalCartonsSold != 2 || s.TotalFactoryCost != 500 || s.RetailerMarginPct != 50 || s.AvgSellingPrice != 100 {
		t.Errorf("SKU finalize wrong: %+v", s)
	}
}
