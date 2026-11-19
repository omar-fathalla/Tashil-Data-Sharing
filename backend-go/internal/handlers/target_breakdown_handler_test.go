package handlers

import (
	"context"
	"encoding/json"
	"errors"
	"math"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/tashil/data-sharing/backend/internal/domain"
	"github.com/tashil/data-sharing/backend/internal/middleware"
	"github.com/tashil/data-sharing/backend/internal/service/targetalloc"
)

func fact(id, tenant, chain, store, storeName, sku, skuName, date string, units int, rev float64) domain.SellOutFact {
	return domain.SellOutFact{
		RecordID: id, TenantID: tenant, RetailerChain: chain, StoreID: store, StoreName: storeName,
		ItemCode: sku, Barcode: "bc-" + sku, SKUName: skuName, Category: "عناية", UnitsPerCarton: 12,
		QuantitySold: units, NetRevenue: rev, TransactionDate: date,
	}
}

func seedBreakdown(t *testing.T, tenant string) (*AnalyticsHandler, string, string) {
	t.Helper()
	t.Setenv("TASHIL_TARGETS_DIR", t.TempDir())
	h, bq := setupTestAnalyticsHandler()
	ctx := context.Background()
	facts := []domain.SellOutFact{
		// 2025 baseline: branch 1 = 60%, branch 2 = 40%
		fact("a1", tenant, "fathalla", "s1", "فتح الله - الرحاب", "k1", "صنف 1", "2025-03-10", 60, 600),
		fact("a2", tenant, "fathalla", "s2", "فتح الله - سموحة", "k1", "صنف 1", "2025-03-11", 20, 200),
		fact("a3", tenant, "fathalla", "s2", "فتح الله - سموحة", "k2", "صنف 2", "2025-04-11", 20, 200),
		// 2026 actuals
		fact("b1", tenant, "fathalla", "s1", "فتح الله - الرحاب", "k1", "صنف 1", "2026-02-10", 50, 500),
		fact("b2", tenant, "fathalla", "s2", "فتح الله - سموحة", "k2", "صنف 2", "2026-02-11", 10, 100),
		fact("b3", tenant, "fathalla", "s3", "فتح الله - جديد", "k1", "صنف 1", "2026-03-11", 5, 50),
		// another chain and another tenant must never be mixed in
		fact("c1", tenant, "gomla", "g1", "جملة", "k1", "صنف 1", "2025-05-01", 999, 99999),
		fact("d1", "tenant-other", "fathalla", "s1", "فتح الله - الرحاب", "k1", "صنف 1", "2025-05-01", 999, 88888),
		fact("d2", "tenant-other", "fathalla", "s1", "فتح الله - الرحاب", "k1", "صنف 1", "2026-05-01", 999, 77777),
	}
	if err := bq.InsertSellOutFacts(ctx, facts); err != nil {
		t.Fatal(err)
	}
	t26, err := bq.UpsertTarget(ctx, tenant, domain.TargetRecord{TargetType: "sell_out", RetailerChain: "fathalla", Year: 2026, TargetRevenueEGP: 1000, TargetUnits: 100})
	if err != nil {
		t.Fatal(err)
	}
	t27, err := bq.UpsertTarget(ctx, tenant, domain.TargetRecord{TargetType: "sell_out", RetailerChain: "fathalla", Year: 2027, TargetRevenueEGP: 3000, TargetUnits: 300})
	if err != nil {
		t.Fatal(err)
	}
	return h, t26.ID, t27.ID
}

func getBreakdown(h *AnalyticsHandler, tenant, id string) *httptest.ResponseRecorder {
	return getBreakdownQuery(h, tenant, id, "")
}

func getBreakdownQuery(h *AnalyticsHandler, tenant, id, rawQuery string) *httptest.ResponseRecorder {
	url := "/api/v1/sellout/targets/" + id + "/breakdown"
	if rawQuery != "" {
		url += "?" + rawQuery
	}
	req := authenticatedRequest(http.MethodGet, url, tenant)
	req.SetPathValue("id", id)
	rec := httptest.NewRecorder()
	h.HandleTargetBreakdown(rec, req)
	return rec
}

func decodeBreakdown(t *testing.T, rec *httptest.ResponseRecorder) domain.TargetBreakdownResponse {
	t.Helper()
	if rec.Code != http.StatusOK {
		t.Fatalf("HTTP %d: %s", rec.Code, rec.Body.String())
	}
	var resp domain.TargetBreakdownResponse
	if err := json.NewDecoder(rec.Body).Decode(&resp); err != nil {
		t.Fatal(err)
	}
	return resp
}

func TestTargetBreakdownDistributesByPriorYearShare(t *testing.T) {
	h, id26, _ := seedBreakdown(t, "tenant-bd")
	resp := decodeBreakdown(t, getBreakdown(h, "tenant-bd", id26))
	if resp.Baseline.Kind != targetalloc.KindPriorYear || resp.Baseline.Year != 2025 {
		t.Fatalf("baseline %+v", resp.Baseline)
	}
	if len(resp.Branches) != 2 {
		t.Fatalf("branches %+v", resp.Branches)
	}
	var sum float64
	for _, b := range resp.Branches {
		sum += b.AllocatedTargetEGP
	}
	if sum != 1000 {
		t.Errorf("branch allocations sum to %v, want exactly 1000", sum)
	}
	first := resp.Branches[0]
	if first.BranchKey != "s1" || first.AllocatedTargetEGP != 600 || first.SharePct != 60 {
		t.Errorf("first branch %+v", first)
	}
	if first.ActualRevenueEGP != 500 || first.AchievementPct == nil || math.Abs(*first.AchievementPct-83.3) > 0.05 || first.GapEGP != -100 {
		t.Errorf("first branch actuals %+v", first)
	}
	if len(first.SKUs) != 1 || first.SKUs[0].AvgUnitPriceEGP == nil || *first.SKUs[0].AvgUnitPriceEGP != 10 ||
		first.SKUs[0].AllocatedUnits == nil || *first.SKUs[0].AllocatedUnits != 60 {
		t.Errorf("sku quantity must come from the baseline unit price: %+v", first.SKUs)
	}
	if first.SKUs[0].AllocatedCartons == nil || *first.SKUs[0].AllocatedCartons != 5 {
		t.Errorf("cartons %+v", first.SKUs[0].AllocatedCartons)
	}
	if !resp.HasActuals || resp.ActualRevenueEGP != 650 {
		t.Errorf("only this tenant's and this chain's rows count: actual %v", resp.ActualRevenueEGP)
	}
	if len(resp.NoHistory) != 1 || resp.NoHistory[0].BranchKey != "s3" || resp.NoHistory[0].Kind != "branch" {
		t.Errorf("a branch without prior sales belongs in the no-history list: %+v", resp.NoHistory)
	}
	if resp.Source != "memory" {
		t.Errorf("source %q", resp.Source)
	}
}

func TestTargetBreakdownFutureYearShowsNoActuals(t *testing.T) {
	h, _, id27 := seedBreakdown(t, "tenant-bd")
	resp := decodeBreakdown(t, getBreakdown(h, "tenant-bd", id27))
	if resp.HasActuals || resp.AchievementPct != nil {
		t.Fatalf("a future year is not comparable: %+v", resp)
	}
	if resp.Baseline.Year != 2026 || resp.Baseline.Kind != targetalloc.KindPriorYear {
		t.Errorf("a 2027 target is based on 2026: %+v", resp.Baseline)
	}
	var sum float64
	for _, b := range resp.Branches {
		sum += b.AllocatedTargetEGP
		if b.AchievementPct != nil {
			t.Errorf("achievement must be absent: %+v", b)
		}
	}
	if sum != 3000 {
		t.Errorf("sum %v", sum)
	}
}

func TestTargetBreakdownErrors(t *testing.T) {
	h, id26, _ := seedBreakdown(t, "tenant-bd")
	if rec := getBreakdown(h, "tenant-bd", "does-not-exist"); rec.Code != http.StatusNotFound {
		t.Errorf("unknown id: HTTP %d", rec.Code)
	}
	if rec := getBreakdown(h, "tenant-other", id26); rec.Code != http.StatusNotFound {
		t.Errorf("another tenant must not see the target: HTTP %d", rec.Code)
	}
	req := httptest.NewRequest(http.MethodGet, "/api/v1/sellout/targets/x/breakdown", nil)
	req.SetPathValue("id", id26)
	rec := httptest.NewRecorder()
	h.HandleTargetBreakdown(rec, req)
	if rec.Code != http.StatusUnauthorized {
		t.Errorf("no tenant context: HTTP %d", rec.Code)
	}
	post := authenticatedRequest(http.MethodPost, "/api/v1/sellout/targets/x/breakdown", "tenant-bd")
	post.SetPathValue("id", id26)
	rec = httptest.NewRecorder()
	h.HandleTargetBreakdown(rec, post)
	if rec.Code != http.StatusMethodNotAllowed {
		t.Errorf("read-only endpoint: HTTP %d", rec.Code)
	}

	bq := h.bqRepo
	in, err := bq.UpsertTarget(context.Background(), "tenant-bd", domain.TargetRecord{TargetType: "sell_in", RetailerChain: "fathalla", Year: 2026, TargetRevenueEGP: 10})
	if err != nil {
		t.Fatal(err)
	}
	if rec := getBreakdown(h, "tenant-bd", in.ID); rec.Code != http.StatusBadRequest {
		t.Errorf("sell-in targets have no sell-out breakdown: HTTP %d", rec.Code)
	}
}

func TestTargetBreakdownChainKAMRestriction(t *testing.T) {
	h, id26, _ := seedBreakdown(t, "tenant-bd")
	req := authenticatedRequest(http.MethodGet, "/x", "tenant-bd")
	claims := &domain.UserClaims{UserID: "kam", TenantID: "tenant-bd", Role: domain.RoleChainKAM, AssignedChain: "gomla"}
	req = req.WithContext(context.WithValue(req.Context(), middleware.UserClaimsContextKey, claims))
	req.SetPathValue("id", id26)
	rec := httptest.NewRecorder()
	h.HandleTargetBreakdown(rec, req)
	if rec.Code != http.StatusForbidden {
		t.Errorf("a gomla KAM must not read a fathalla target: HTTP %d", rec.Code)
	}
}

type stubTargetSource struct {
	cov  []targetalloc.MonthCoverage
	rows []targetalloc.Row
	err  error
}

func (s stubTargetSource) Coverage(context.Context) ([]targetalloc.MonthCoverage, error) {
	return s.cov, s.err
}

func (s stubTargetSource) Rows(context.Context, targetalloc.Window, targetalloc.Window) ([]targetalloc.Row, error) {
	return s.rows, s.err
}

type stubTargetQuerier struct{ src stubTargetSource }

func (q stubTargetQuerier) TargetBreakdownSource(string, string) targetalloc.Source { return q.src }

func TestTargetBreakdownUsesBigQueryThenFallsBack(t *testing.T) {
	h, id26, _ := seedBreakdown(t, "tenant-bd")
	h.WithTargetBreakdownQuerier(stubTargetQuerier{src: stubTargetSource{
		cov: []targetalloc.MonthCoverage{{Month: "2025-03", Rows: 3}},
		rows: []targetalloc.Row{
			{StoreKey: "bq1", StoreName: "فرع BQ", SKUKey: "k", SKUName: "صنف", BaseRev: 10, BaseUnits: 1, ActRev: 5, ActUnits: 1, ActRows: 1},
		},
	}})
	resp := decodeBreakdown(t, getBreakdown(h, "tenant-bd", id26))
	if resp.Source != "bigquery" || len(resp.Branches) != 1 || resp.Branches[0].BranchKey != "bq1" || resp.Branches[0].AllocatedTargetEGP != 1000 {
		t.Fatalf("BigQuery result expected: %+v", resp)
	}

	h.WithTargetBreakdownQuerier(stubTargetQuerier{src: stubTargetSource{err: errors.New("boom")}})
	resp = decodeBreakdown(t, getBreakdown(h, "tenant-bd", id26))
	if resp.Source != "memory" || len(resp.Branches) != 2 {
		t.Fatalf("a BigQuery failure must fall back to memory: %+v", resp)
	}

	h.WithTargetBreakdownQuerier(stubTargetQuerier{src: stubTargetSource{}})
	resp = decodeBreakdown(t, getBreakdown(h, "tenant-bd", id26))
	if resp.Source != "memory" || len(resp.Branches) != 2 {
		t.Fatalf("an empty BigQuery answer must fall back to memory: %+v", resp)
	}
}

func TestTargetBreakdownBranchAndMonthFilters(t *testing.T) {
	h, id26, _ := seedBreakdown(t, "tenant-bd-filt")

	// Branch filter: only s1 (60% of 1000 = 600), KPIs scoped, monthly phasing present.
	resp := decodeBreakdown(t, getBreakdownQuery(h, "tenant-bd-filt", id26, "branch=s1"))
	if resp.AppliedBranch != "s1" {
		t.Fatalf("applied_branch %q", resp.AppliedBranch)
	}
	if len(resp.Branches) != 1 || resp.Branches[0].BranchKey != "s1" {
		t.Fatalf("branches %+v", resp.Branches)
	}
	if resp.TargetRevenueEGP != 600 {
		t.Errorf("branch target want 600 got %v", resp.TargetRevenueEGP)
	}
	if resp.ActualRevenueEGP != 500 {
		t.Errorf("branch actual want 500 got %v", resp.ActualRevenueEGP)
	}
	if len(resp.MonthlyPhasing) != 12 {
		t.Fatalf("monthly_phasing len %d", len(resp.MonthlyPhasing))
	}
	var phSum float64
	for _, m := range resp.MonthlyPhasing {
		phSum += m.TargetRevenueEGP
	}
	if math.Abs(phSum-600) > 0.05 {
		t.Errorf("branch monthly targets sum %v want 600", phSum)
	}

	// Month filter: February actuals only (500+100=600 in seed), seasonal target slice.
	respM := decodeBreakdown(t, getBreakdownQuery(h, "tenant-bd-filt", id26, "month=2"))
	if respM.AppliedMonth != 2 {
		t.Fatalf("applied_month %d", respM.AppliedMonth)
	}
	if respM.Month != 2 {
		t.Errorf("response month %d", respM.Month)
	}
	if !respM.HasActuals || respM.ActualRevenueEGP != 600 {
		t.Errorf("feb actuals want 600 got has=%v actual=%v", respM.HasActuals, respM.ActualRevenueEGP)
	}
	// Baseline Mar+Apr 2025: s1=600, s2=400 → same shares; month target ≈ annual/12 when no strong seasonality
	// (seed prior year is Mar+Apr only → partial with neutral fill). Target should be < annual.
	if respM.TargetRevenueEGP <= 0 || respM.TargetRevenueEGP >= 1000 {
		t.Errorf("month target should be a seasonal slice, got %v", respM.TargetRevenueEGP)
	}
	if len(respM.MonthlyPhasing) != 12 {
		t.Fatalf("month filter still returns 12-month phasing, got %d", len(respM.MonthlyPhasing))
	}

	// Combined branch + month.
	respBM := decodeBreakdown(t, getBreakdownQuery(h, "tenant-bd-filt", id26, "branch=s1&month=2"))
	if respBM.AppliedBranch != "s1" || respBM.AppliedMonth != 2 {
		t.Fatalf("applied %+v/%d", respBM.AppliedBranch, respBM.AppliedMonth)
	}
	if len(respBM.Branches) != 1 || respBM.Branches[0].BranchKey != "s1" {
		t.Fatalf("combined branches %+v", respBM.Branches)
	}
	if respBM.ActualRevenueEGP != 500 {
		t.Errorf("s1 feb actual want 500 got %v", respBM.ActualRevenueEGP)
	}
}

func TestTargetBreakdownEmptyTenantExplainsMissingBaseline(t *testing.T) {
	t.Setenv("TASHIL_TARGETS_DIR", t.TempDir())
	h, bq := setupTestAnalyticsHandler()
	tg, err := bq.UpsertTarget(context.Background(), "tenant-empty", domain.TargetRecord{TargetType: "sell_out", RetailerChain: "fathalla", Year: 2026, TargetRevenueEGP: 500})
	if err != nil {
		t.Fatal(err)
	}
	resp := decodeBreakdown(t, getBreakdown(h, "tenant-empty", tg.ID))
	if resp.Baseline.Kind != targetalloc.KindNone || resp.Baseline.CaptionAr == "" || len(resp.Branches) != 0 || resp.HasActuals {
		t.Fatalf("%+v", resp)
	}
}

func TestTargetsSummaryComparesOnlyPeriodsWithActuals(t *testing.T) {
	h, _, _ := seedBreakdown(t, "tenant-bd")
	req := authenticatedRequest(http.MethodGet, "/api/v1/analytics/targets?target_type=sell_out&chain=fathalla", "tenant-bd")
	rec := httptest.NewRecorder()
	h.HandleTargets(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("HTTP %d", rec.Code)
	}
	var s domain.TargetsSummaryResponse
	if err := json.NewDecoder(rec.Body).Decode(&s); err != nil {
		t.Fatal(err)
	}
	if s.TotalTargetRevenueEGP != 4000 {
		t.Errorf("the target card keeps every target: %v", s.TotalTargetRevenueEGP)
	}
	if s.TotalActualRevenueEGP != 650 {
		t.Errorf("actual %v", s.TotalActualRevenueEGP)
	}
	if s.ComparableTargetRevenueEGP != 1000 || s.ComparableActualRevenueEGP != 650 || s.ComparableTargetsCount != 1 {
		t.Errorf("comparable subset %+v", s)
	}
	if s.OverallAchievementPct != 65 {
		t.Errorf("achievement must ignore the future year: %v", s.OverallAchievementPct)
	}
	if s.TotalVarianceEGP != -350 {
		t.Errorf("variance must ignore the future year: %v", s.TotalVarianceEGP)
	}
	if s.NoDataTargetsCount != 1 || s.NoDataTargetRevenueEGP != 3000 {
		t.Errorf("future targets reported separately: %+v", s)
	}
	for _, it := range s.Items {
		switch it.Year {
		case 2027:
			if it.HasActuals || it.Status != "no_data" || it.VarianceRevenueEGP != 0 || it.AchievementRevPct != 0 {
				t.Errorf("2027 item must be non-comparable: %+v", it)
			}
		case 2026:
			if !it.HasActuals || it.AchievementRevPct != 65 || it.VarianceRevenueEGP != -350 {
				t.Errorf("2026 item: %+v", it)
			}
		}
	}

	yearOnly := authenticatedRequest(http.MethodGet, "/api/v1/analytics/targets?target_type=sell_out&chain=fathalla&year=2026", "tenant-bd")
	rec = httptest.NewRecorder()
	h.HandleTargets(rec, yearOnly)
	var s26 domain.TargetsSummaryResponse
	_ = json.NewDecoder(rec.Body).Decode(&s26)
	if s26.TotalTargetRevenueEGP != 1000 || s26.OverallAchievementPct != 65 || s26.TotalVarianceEGP != -350 || s26.NoDataTargetsCount != 0 {
		t.Errorf("year filter: %+v", s26)
	}
}

func TestFutureYearTargetCanBeCreatedThroughTheAPI(t *testing.T) {
	t.Setenv("TASHIL_TARGETS_DIR", t.TempDir())
	h, _ := setupTestAnalyticsHandler()
	body := `{"target_type":"sell_out","retailer_chain":"fathalla","year":2028,"month":0,"target_revenue_egp":180000000,"target_units":250000}`
	req := httptest.NewRequest(http.MethodPost, "/api/v1/analytics/targets?target_type=sell_out", strings.NewReader(body))
	claims := &domain.UserClaims{UserID: "owner", TenantID: "tenant-fy", Role: domain.RoleVendorAdmin}
	ctx := context.WithValue(req.Context(), middleware.UserClaimsContextKey, claims)
	req = req.WithContext(context.WithValue(ctx, middleware.VerifiedClaimsContextKey, claims))
	rec := httptest.NewRecorder()
	h.HandleTargets(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("HTTP %d: %s", rec.Code, rec.Body.String())
	}
	var s domain.TargetsSummaryResponse
	if err := json.NewDecoder(rec.Body).Decode(&s); err != nil {
		t.Fatal(err)
	}
	if len(s.Items) != 1 || s.Items[0].Year != 2028 || s.Items[0].HasActuals {
		t.Fatalf("a 2028 target must be accepted and marked as having no sales yet: %+v", s.Items)
	}
}
