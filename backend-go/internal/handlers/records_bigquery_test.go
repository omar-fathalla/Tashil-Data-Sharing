package handlers

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"net/url"
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

func TestHandleRecordsCategoryUsesBigQueryPath(t *testing.T) {
	handler, tenantID := seedRecordsFallbackTenant(t)
	fake := &fakeRecordsQuerier{res: &bqsink.RecordsResult{
		Totals: bqsink.RecordsTotals{
			TotalCount: 28, NetRevenue: 320861, UnitsSold: 6887, CartonsSold: 688.7,
			FactoryCost: 595500, GrossProfit: -274639, MatchedRevForMargin: 320861,
			Stores: 12, SKUs: 28, MatchedSKUs: 28,
		},
		SKUs: []bqsink.RecordsSKU{{
			ItemCode: "RH-DISH", SKUName: "Rahab Dish Liquid", Category: "صابون سائل للاطباق",
			UnitsSold: 100, NetRevenue: 5000, UnitsPerCarton: 12, FactoryUnitCost: 40, Stores: 3,
		}},
		Page: []domain.SellOutFact{{RecordID: "bq_cat_1", Category: "صابون سائل للاطباق", NetRevenue: 5000}},
	}}
	handler.WithRecordsQuerier(fake)

	cat := "صابون سائل اطباق"
	q := url.Values{
		"chain": {"fathalla"}, "category": {cat}, "year": {"2026"}, "month": {"1"}, "supplier": {"own"},
	}
	rec := httptest.NewRecorder()
	handler.HandleRecords(rec, authenticatedRequest(http.MethodGet, "/api/v1/analytics/records?"+q.Encode(), tenantID))
	resp := decodeRecords(t, rec)
	if fake.calls != 1 || rec.Header().Get("X-Records-Source") != "bigquery" {
		t.Fatalf("category must use BigQuery path, calls=%d source=%q", fake.calls, rec.Header().Get("X-Records-Source"))
	}
	if fake.last.Category != cat || fake.last.Chain != "fathalla" || fake.last.TenantID != tenantID {
		t.Errorf("category/chain not forwarded: %+v", fake.last)
	}
	if resp.TotalCount != 28 || resp.TotalCartonsSold != 688.7 {
		t.Errorf("totals mismatch: count=%d cartons=%v", resp.TotalCount, resp.TotalCartonsSold)
	}
	if resp.TotalFactoryCost != 595500 || resp.TotalRetailerGrossProfit != -274639 {
		t.Errorf("factory/margin mismatch: factory=%v margin=%v", resp.TotalFactoryCost, resp.TotalRetailerGrossProfit)
	}
	if len(resp.SKUSummaries) != 1 || resp.SKUSummaries[0].Category != cat {
		t.Errorf("SKU category not normalized: %+v", resp.SKUSummaries)
	}
	if !recordsHaveSingleID(resp.Records, "bq_cat_1") {
		t.Errorf("page not from BQ: %+v", resp.Records)
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
