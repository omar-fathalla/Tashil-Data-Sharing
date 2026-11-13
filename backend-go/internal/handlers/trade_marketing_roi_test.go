package handlers

import (
	"bytes"
	"context"
	"encoding/json"
	"math"
	"mime/multipart"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/tashil/data-sharing/backend/internal/domain"
	"github.com/tashil/data-sharing/backend/internal/middleware"
	"github.com/tashil/data-sharing/backend/internal/service/bigquery"
	"github.com/tashil/data-sharing/backend/internal/service/firestore"
	"github.com/tashil/data-sharing/backend/internal/service/gemini"
)

type fakeSales struct {
	out []domain.SellOutFact
	in  []domain.SellInRecord
}

func (f *fakeSales) GetSellOutRecords(_ context.Context, tenant string, flt bigquery.RecordFilter) ([]domain.SellOutFact, int, error) {
	var res []domain.SellOutFact
	for _, r := range f.out {
		if r.TenantID != tenant || (flt.StartDate != "" && r.TransactionDate < flt.StartDate) || (flt.EndDate != "" && r.TransactionDate > flt.EndDate) {
			continue
		}
		res = append(res, r)
	}
	return res, len(res), nil
}

func (f *fakeSales) GetSellInRecords(_ context.Context, tenant string, flt bigquery.SellInRecordFilter) ([]domain.SellInRecord, int, error) {
	var res []domain.SellInRecord
	for _, r := range f.in {
		if r.TenantID == tenant && r.Year == flt.Year && r.MonthNum == flt.Month {
			res = append(res, r)
		}
	}
	return res, len(res), nil
}

func roiFixture() *fakeSales {
	so := func(t, ch, d string, v float64) domain.SellOutFact {
		return domain.SellOutFact{TenantID: t, RetailerChain: ch, TransactionDate: d, NetRevenue: v}
	}
	return &fakeSales{
		out: []domain.SellOutFact{
			so("adeco", "fathalla", "2026-02-01", 700000),
			so("adeco", "fathalla", "2026-02-28", 500000), // last real day of Feb 2026
			so("adeco", "fathalla", "2026-03-01", 999999), // must not leak into February
			so("adeco", "fathalla", "2026-01-31", 1000000),
			so("adeco", "fathalla", "2025-02-15", 800000),
			so("adeco", "beet-elgomla", "2026-02-10", 300000),
			so("unilever", "fathalla", "2026-02-10", 50000000), // other tenant
		},
		in: []domain.SellInRecord{
			{TenantID: "adeco", RetailerChain: "fathalla", Year: 2026, MonthNum: 2, NetValueEGP: 1500000},
			{TenantID: "unilever", RetailerChain: "fathalla", Year: 2026, MonthNum: 2, NetValueEGP: 9e9},
		},
	}
}

func roiMux(h *TradeMarketingHandler) *http.ServeMux {
	mux := tmMux(h)
	mux.HandleFunc("GET /api/v1/trade-marketing/roi", h.HandleGetROI)
	mux.HandleFunc("POST /api/v1/trade-marketing/expenses/upload", h.HandleUploadExpenses)
	return mux
}

func near(a, b float64) bool { return math.Abs(a-b) < 1e-6 }

func TestTradeMarketingROIMathTenantAndKAM(t *testing.T) {
	fs := firestore.NewClient("test-db", true)
	mux := roiMux(NewTradeMarketingHandler(fs, fs).WithSalesSource(roiFixture()))
	admin := &domain.UserClaims{UserID: "u1", TenantID: "adeco", Email: "a@adeco.com", Role: domain.RoleVendorAdmin}
	for _, amt := range []float64{30000, 20000} {
		e := validExpense("Fathalla")
		e["amount_egp"] = amt
		if rec, _ := tmDo(t, mux, admin, "POST", "/api/v1/trade-marketing/expenses", e); rec.Code != http.StatusCreated {
			t.Fatalf("create: %d %s", rec.Code, rec.Body.String())
		}
	}
	if rec, _ := tmDo(t, mux, admin, "POST", "/api/v1/trade-marketing/expenses", validExpense("Beet El Gomla")); rec.Code != http.StatusCreated {
		t.Fatalf("create beet: %d", rec.Code)
	}

	rec, out := tmDo(t, mux, admin, "GET", "/api/v1/trade-marketing/roi?year=2026&month=2", nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("roi: %d %s", rec.Code, rec.Body.String())
	}
	sums := out["summaries"].([]interface{})
	if len(sums) != 2 {
		t.Fatalf("want 2 summaries, got %d", len(sums))
	}
	var fath map[string]interface{}
	for _, s := range sums {
		m := s.(map[string]interface{})
		if m["chain_name"] == "Fathalla" {
			fath = m
		} else if !near(m["current_month_sales_egp"].(float64), 300000) {
			t.Fatalf("Beet El Gomla should match beet-elgomla sales: %v", m)
		}
	}
	checks := map[string]float64{
		"marketing_spend_egp": 50000, "activities_count": 2, "current_month_sales_egp": 1200000,
		"previous_month_sales_egp": 1000000, "last_year_same_month_sales_egp": 800000,
		"current_month_sell_in_egp": 1500000, "mom_growth_pct": 20, "yoy_growth_pct": 50, "romi_multiple": 4,
	}
	for k, want := range checks {
		if got, _ := fath[k].(float64); !near(got, want) {
			t.Errorf("%s: want %v got %v", k, want, fath[k])
		}
	}

	// Tenant isolation: another tenant sees no adeco expenses and no adeco sales.
	other := &domain.UserClaims{UserID: "u2", TenantID: "unilever", Email: "b@uni.com", Role: domain.RoleVendorAdmin}
	_, out = tmDo(t, mux, other, "GET", "/api/v1/trade-marketing/roi?year=2026&month=2", nil)
	if n := out["count"].(float64); n != 0 {
		t.Fatalf("other tenant should see 0 summaries, got %v", n)
	}

	// KAM restricted to own chain even when asking for another.
	kam := &domain.UserClaims{UserID: "u3", TenantID: "adeco", Email: "k@adeco.com", Role: domain.RoleChainKAM, AssignedChain: "Beet El Gomla"}
	_, out = tmDo(t, mux, kam, "GET", "/api/v1/trade-marketing/roi?year=2026&month=2&chain=Fathalla", nil)
	sums = out["summaries"].([]interface{})
	if len(sums) != 1 || sums[0].(map[string]interface{})["chain_name"] != "Beet El Gomla" {
		t.Fatalf("KAM should only see own chain: %v", sums)
	}

	if rec, _ := tmDo(t, mux, nil, "GET", "/api/v1/trade-marketing/roi", nil); rec.Code != http.StatusUnauthorized {
		t.Fatalf("no claims: want 401 got %d", rec.Code)
	}
}

func TestMonthBoundsRealLengths(t *testing.T) {
	cases := map[[2]int]string{{2026, 2}: "2026-02-28", {2028, 2}: "2028-02-29", {2026, 4}: "2026-04-30", {2026, 12}: "2026-12-31"}
	for in, want := range cases {
		if _, end := monthBounds(in[0], in[1]); end != want {
			t.Errorf("%v: want %s got %s", in, want, end)
		}
	}
}

func uploadReq(t *testing.T, claims *domain.UserClaims, filename string, content []byte) *http.Request {
	t.Helper()
	var buf bytes.Buffer
	mw := multipart.NewWriter(&buf)
	fw, _ := mw.CreateFormFile("file", filename)
	_, _ = fw.Write(content)
	_ = mw.Close()
	req := httptest.NewRequest("POST", "/api/v1/trade-marketing/expenses/upload", &buf)
	req.Header.Set("Content-Type", mw.FormDataContentType())
	return req.WithContext(context.WithValue(req.Context(), middleware.UserClaimsContextKey, claims))
}

func TestTradeMarketingUploadXLSXAndCSV(t *testing.T) {
	fs := firestore.NewClient("test-db", true)
	mux := roiMux(NewTradeMarketingHandler(fs, fs).WithSalesSource(roiFixture()))
	admin := &domain.UserClaims{UserID: "u1", TenantID: "adeco", Email: "a@adeco.com", Role: domain.RoleVendorAdmin}

	xlsx, err := gemini.BuildSampleXLSX([][]string{
		{"Year", "Month", "Chain Name", "Category", "Brand Name", "Campaign Title", "Vendor or Agency", "Amount EGP", "Notes"},
		{"2026", "2", "Fathalla", "floor_rental", "Diva", "Feb floors", "Agency", "45,000", ""},
		{"2026", "13", "Fathalla", "floor_rental", "Diva", "bad month", "", "100", ""},
		{"2026", "2", "Fathalla", "unknown_cat", "Diva", "bad cat", "", "100", ""},
		{"2026", "2", "Fathalla", "advertising", "Diva", "bad amount", "", "abc", ""},
	})
	if err != nil {
		t.Fatal(err)
	}
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, uploadReq(t, admin, "expenses.xlsx", xlsx))
	var out map[string]interface{}
	_ = json.Unmarshal(rec.Body.Bytes(), &out)
	if rec.Code != http.StatusOK || out["saved_count"].(float64) != 1 || out["rejected_count"].(float64) != 3 {
		t.Fatalf("xlsx upload: %d %s", rec.Code, rec.Body.String())
	}

	kam := &domain.UserClaims{UserID: "u3", TenantID: "adeco", Email: "k@adeco.com", Role: domain.RoleChainKAM, AssignedChain: "Gomla"}
	csv := []byte("year,month,chain_name,category,amount_egp\n2026,3,Gomla,advertising,1000\n2026,3,Fathalla,advertising,1000\n")
	rec = httptest.NewRecorder()
	mux.ServeHTTP(rec, uploadReq(t, kam, "expenses.csv", csv))
	out = map[string]interface{}{}
	_ = json.Unmarshal(rec.Body.Bytes(), &out)
	if rec.Code != http.StatusOK || out["saved_count"].(float64) != 1 || out["rejected_count"].(float64) != 1 {
		t.Fatalf("kam csv upload: %d %s", rec.Code, rec.Body.String())
	}

	// Saved rows are tenant-scoped.
	items, _ := fs.ListMarketingExpenses(context.Background(), "adeco", domain.MarketingExpenseFilter{})
	if len(items) != 2 {
		t.Fatalf("want 2 saved adeco expenses, got %d", len(items))
	}
	if items, _ := fs.ListMarketingExpenses(context.Background(), "unilever", domain.MarketingExpenseFilter{}); len(items) != 0 {
		t.Fatalf("other tenant must not see uploads")
	}

	viewer := &domain.UserClaims{UserID: "u4", TenantID: "adeco", Email: "v@adeco.com", Role: domain.RoleViewer}
	rec = httptest.NewRecorder()
	mux.ServeHTTP(rec, uploadReq(t, viewer, "expenses.csv", csv))
	if rec.Code != http.StatusForbidden {
		t.Fatalf("viewer upload: want 403 got %d", rec.Code)
	}
	rec = httptest.NewRecorder()
	mux.ServeHTTP(rec, uploadReq(t, admin, "expenses.pdf", csv))
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("pdf upload: want 400 got %d", rec.Code)
	}
}

func TestTradeMarketingROIYoYAvailableFlag(t *testing.T) {
	fs := firestore.NewClient("test-db", true)
	mux := roiMux(NewTradeMarketingHandler(fs, fs).WithSalesSource(roiFixture()))
	admin := &domain.UserClaims{UserID: "u1", TenantID: "adeco", Email: "a@adeco.com", Role: domain.RoleVendorAdmin}
	for _, ch := range []string{"Fathalla", "Beet El Gomla"} {
		if rec, _ := tmDo(t, mux, admin, "POST", "/api/v1/trade-marketing/expenses", validExpense(ch)); rec.Code != http.StatusCreated {
			t.Fatalf("create %s: %d", ch, rec.Code)
		}
	}
	_, out := tmDo(t, mux, admin, "GET", "/api/v1/trade-marketing/roi?year=2026&month=2", nil)
	for _, s := range out["summaries"].([]interface{}) {
		m := s.(map[string]interface{})
		want := m["chain_name"] == "Fathalla" // only Fathalla has Feb 2025 sales
		if got, ok := m["yoy_available"].(bool); !ok || got != want {
			t.Errorf("%v: yoy_available want %v got %v", m["chain_name"], want, m["yoy_available"])
		}
	}
}
