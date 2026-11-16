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

// The waterfall splits list − net into invoice discount, the chain's extra discount and the remainder,
// and VAT follows each row's (chain) rate.
func TestSellInTotalsWaterfallSplitsExtraChainDiscount(t *testing.T) {
	// List 1000, invoice 10% (=100), extra 20% of the remaining 900 (=180) → expected net 720; billed net 700.
	tot := sellInTotalsFromRecords([]domain.SellInRecord{{
		ItemCode: "A", ItemName: "a", NetValueEGP: 700, OfficialListValueExclEGP: 1000, DiscountGrantedEGP: 300,
		InvoiceDiscountPct: 10, ExtraDiscountPct: 20, VATRate: 0.05, GrossValueInclVATEGP: 735, VATAmountEGP: 35,
	}})
	resp := buildSellInRecordsResponse(tot, nil, 1, 10, 0)
	if resp.TotalInvoiceDiscountEGP != 100 || resp.TotalExtraChainDiscountEGP != 180 || resp.TotalOtherDifferenceEGP != 20 {
		t.Fatalf("waterfall split: inv=%v extra=%v other=%v", resp.TotalInvoiceDiscountEGP, resp.TotalExtraChainDiscountEGP, resp.TotalOtherDifferenceEGP)
	}
	if resp.TotalDiscountGrantedEGP != 300 || resp.TotalVAT14EGP != 35 || resp.VATRatePct != 5 {
		t.Fatalf("totals: disc=%v vat=%v vat%%=%v", resp.TotalDiscountGrantedEGP, resp.TotalVAT14EGP, resp.VATRatePct)
	}
	// Legacy rows store 0.10 for 10%.
	legacy := sellInTotalsFromRecords([]domain.SellInRecord{{ItemCode: "A", NetValueEGP: 900, OfficialListValueExclEGP: 1000, InvoiceDiscountPct: 0.10}})
	if legacy.InvDisc != 100 || legacy.ExtraDisc != 0 {
		t.Fatalf("legacy fraction: %+v", legacy)
	}
}

func TestSellInTotalsSQLCarriesChainProfiles(t *testing.T) {
	vat := 0.05
	totals, _, page, params := bqsink.SellInTotalsSQL("`p.d.sell_in_records`", bqsink.SellInTotalsQuery{
		TenantID: "tenant-adeco", Chain: "fathalla",
		Profiles: []bqsink.SellInChainProfile{
			{Chain: " Fathalla ", InvoiceDiscountPct: 10, ExtraDiscountPct: 20, VATRate: &vat},
			{Chain: "kazyon", InvoiceDiscountPct: 12},
		},
	})
	for _, want := range []string{"WHEN chain_r = @pc0 THEN @pv0", "WHEN chain_r = @pc0 THEN @pi0", "WHEN chain_r = @pc0 THEN @pe0", "WHEN chain_r = @pc1 THEN @pi1", "AS inv_disc", "AS extra_disc"} {
		if !strings.Contains(totals, want) {
			t.Fatalf("totals SQL missing %q", want)
		}
	}
	if strings.Contains(totals, "@pv1") {
		t.Fatal("a profile without VAT must not override the row VAT")
	}
	if !strings.Contains(page, "ipct, epct") {
		t.Fatal("page must not leak the derived discount columns")
	}
	got := map[string]interface{}{}
	for _, p := range params {
		got[p.Name] = p.Value
	}
	if got["pc0"] != "fathalla" || got["pv0"] != 0.05 || got["pi0"] != 10.0 || got["pe0"] != 20.0 || got["pc1"] != "kazyon" {
		t.Fatalf("params %+v", got)
	}
	// Without profiles the SQL keeps the stored per-row VAT.
	plain, _, _, _ := bqsink.SellInTotalsSQL("`p.d.t`", bqsink.SellInTotalsQuery{TenantID: "tenant-adeco"})
	if strings.Contains(plain, "@pc0") || !strings.Contains(plain, "IF(matched AND IFNULL(vat_rate, 0) > 0, vat_rate, 0.14) AS vr") {
		t.Fatal("no-profile SQL changed")
	}
}
