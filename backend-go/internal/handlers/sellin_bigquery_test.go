package handlers

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/tashil/data-sharing/backend/internal/domain"
	"github.com/tashil/data-sharing/backend/internal/service/bigquery"
	"github.com/tashil/data-sharing/backend/internal/service/bqsink"
)

type fakeSellInQuerier struct {
	res  *bqsink.SellInTotalsResult
	err  error
	got  bqsink.SellInTotalsQuery
	hits int
}

func (f *fakeSellInQuerier) QuerySellInTotals(_ context.Context, q bqsink.SellInTotalsQuery) (*bqsink.SellInTotalsResult, error) {
	f.hits++
	f.got = q
	return f.res, f.err
}

func TestSellInRecordsBigQueryPathAndFallback(t *testing.T) {
	repo := bigquery.NewClient("tashil-test", "retail", true)
	_ = repo.ClearTenantData(context.Background(), "all")
	repo.ReplaceSellInRecords("tenant-adeco", []domain.SellInRecord{
		{RecordID: "m1", RetailerChain: "fathalla", Year: 2026, MonthNum: 3, NetValueEGP: 1000, NetQtyCases: 2},
	})
	fake := &fakeSellInQuerier{res: &bqsink.SellInTotalsResult{
		Totals: bqsink.SellInTotals{Count: 3, NetValue: 900, ListExcl: 1000, NetWithList: 800},
		Groups: []bqsink.SellInGroupRow{{Year: 2026, Month: 3, Chain: "gomla", Brand: "فيبا", NetValue: 900, Count: 3}},
		Page:   []domain.SellInRecord{{RecordID: "b1", RetailerChain: "", Year: 2026, MonthNum: 3, NetValueEGP: 900}},
	}}
	h := NewAnalyticsHandler(repo).WithSellInTotalsQuerier(fake)

	w := httptest.NewRecorder()
	h.HandleSellInRecords(w, authenticatedRequest(http.MethodGet, "/api/v1/analytics/sell-in-records?year=2026&limit=25", "tenant-adeco"))
	if got := w.Header().Get("X-Records-Source"); got != "bigquery" {
		t.Fatalf("source %q: %s", got, w.Body.String())
	}
	var resp PaginatedSellInRecordsResponse
	_ = json.Unmarshal(w.Body.Bytes(), &resp)
	if resp.TotalCount != 3 || resp.TotalValueEGP != 900 || resp.EffectiveDiscountPct != 20 || len(resp.Records) != 1 ||
		resp.Records[0].RetailerChain != "fathalla" || len(resp.ByChain) != 1 || resp.ByChain[0].Key != "gomla" {
		t.Fatalf("unexpected BigQuery response: %+v", resp)
	}
	if fake.got.Year != 2026 || fake.got.Limit != 25 || len(fake.got.Rules) == 0 {
		t.Fatalf("query not forwarded: %+v", fake.got)
	}

	// Search text stays in memory; a BigQuery error falls back to memory too.
	for _, url := range []string{"/api/v1/analytics/sell-in-records?year=2026&q=x", "/api/v1/analytics/sell-in-records?year=2026"} {
		fake.err = errors.New("boom")
		w = httptest.NewRecorder()
		h.HandleSellInRecords(w, authenticatedRequest(http.MethodGet, url, "tenant-adeco"))
		if got := w.Header().Get("X-Records-Source"); got != "memory" {
			t.Fatalf("%s: source %q", url, got)
		}
	}

	fake.err = nil
	w = httptest.NewRecorder()
	h.HandleSellInMonthly(w, authenticatedRequest(http.MethodGet, "/api/v1/analytics/sell-in-monthly?year=2026", "tenant-adeco"))
	var monthly SellInMonthlyResponse
	_ = json.Unmarshal(w.Body.Bytes(), &monthly)
	if w.Header().Get("X-Records-Source") != "bigquery" || len(monthly.Points) != 1 || monthly.Points[0].RetailerChain != "gomla" || monthly.Points[0].NetValueEGP != 900 {
		t.Fatalf("monthly: %s %+v", w.Header().Get("X-Records-Source"), monthly)
	}
}

func TestSellInTotalsFromRecordsNoDefaultDiscount(t *testing.T) {
	tot := sellInTotalsFromRecords([]domain.SellInRecord{
		{NetValueEGP: 900, OfficialListValueExclEGP: 1000, ItemCode: "A", ItemName: "a"},
		{NetValueEGP: 500}, // no list price: contributes nothing to list / discount
	})
	if tot.ListExcl != 1000 || tot.NetWithList != 900 || sellInEffectiveDiscountPct(tot) != 10 || tot.MatchedSKUs != 1 {
		t.Fatalf("%+v", tot)
	}
	if sellInEffectiveDiscountPct(sellInTotalsFromRecords([]domain.SellInRecord{{NetValueEGP: 5}})) != 0 {
		t.Fatal("no list price must give 0%, not a default 10%")
	}
}

func TestSellInTotalsSQLStageB(t *testing.T) {
	totals, groups, page, params := bqsink.SellInTotalsSQL("`p.d.sell_in_records`", bqsink.SellInTotalsQuery{
		TenantID: "tenant-adeco", Chain: "gomla", Year: 2026, Month: 3,
		Rules: []bqsink.SellInChainRule{{Needle: "كيه اتش", Chain: "gomla"}, {Needle: "بيت الجمله", Chain: "beet-elgomla"}},
	})
	for _, want := range []string{"ARRAY_AGG(batch_id ORDER BY ingested_at DESC", "TRANSLATE(", "@cn0", "@cn1", "LN(ABS(net0 / q0) / unit_px)", "chain_r = LOWER(TRIM(@chain))", "year = @year", "month_num = @month"} {
		if !strings.Contains(totals, want) {
			t.Fatalf("totals SQL missing %q", want)
		}
	}
	if strings.Contains(totals, "0.9") || !strings.Contains(groups, "GROUP BY 1, 2, 3, 4") || !strings.Contains(page, "LIMIT @limit OFFSET @offset") {
		t.Fatal("unexpected SQL shape")
	}
	if len(params) != 8 || params[1].Name != "cn0" || params[1].Value != "كيه اتش" {
		t.Fatalf("params %+v", params)
	}
}
