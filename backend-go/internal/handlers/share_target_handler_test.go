package handlers

import (
	"bytes"
	"context"
	"encoding/json"
	"math"
	"net/http"
	"net/http/httptest"
	"strconv"
	"testing"

	"github.com/tashil/data-sharing/backend/internal/domain"
	"github.com/tashil/data-sharing/backend/internal/middleware"
	"github.com/tashil/data-sharing/backend/internal/service/sharetarget"
)

func shareFact(id, tenant, chain, store, storeName, cat, sku, date string, units int, rev float64, own bool, supplier string) domain.SellOutFact {
	return domain.SellOutFact{
		RecordID: id, TenantID: tenant, RetailerChain: chain,
		StoreID: store, StoreName: storeName, Category: cat,
		Barcode: "bc-" + sku, SKUName: sku, QuantitySold: units, NetRevenue: rev,
		TransactionDate: date, IsOwnBrand: own, Supplier: supplier,
	}
}

func seedShareTarget(t *testing.T) (*AnalyticsHandler, string) {
	t.Helper()
	t.Setenv("TASHIL_TARGETS_DIR", t.TempDir())
	h, bq := setupTestAnalyticsHandler()
	tenant := "tenant-share"
	ctx := context.Background()
	// Category A: own 40, market 100 → 40%. Category B: own 10, market 50 → 20%.
	// Two months of 2026 so MonthsWithData=2. Two branches for historical split.
	facts := []domain.SellOutFact{
		shareFact("o1", tenant, "fathalla", "s1", "الرحاب", "صابون", "sku1", "2026-01-10", 20, 28, true, ""),
		shareFact("o2", tenant, "fathalla", "s2", "سموحة", "صابون", "sku1", "2026-01-11", 10, 12, true, ""),
		shareFact("c1", tenant, "fathalla", "s1", "الرحاب", "صابون", "comp1", "2026-01-12", 30, 60, false, "Competitor"),
		shareFact("o3", tenant, "fathalla", "s1", "الرحاب", "شاور", "sku2", "2026-02-10", 5, 7, true, ""),
		shareFact("o4", tenant, "fathalla", "s2", "سموحة", "شاور", "sku2", "2026-02-11", 3, 3, true, ""),
		shareFact("c2", tenant, "fathalla", "s1", "الرحاب", "شاور", "comp2", "2026-02-12", 20, 40, false, "Competitor"),
		// Other chain must not merge into fathalla baseline.
		shareFact("x1", tenant, "gomla", "g1", "جملة", "صابون", "sku1", "2026-01-15", 100, 9999, true, ""),
	}
	if err := bq.InsertSellOutFacts(ctx, facts); err != nil {
		t.Fatal(err)
	}
	return h, tenant
}

func TestShareTargetBaselinePerChain(t *testing.T) {
	h, tenant := seedShareTarget(t)
	req := authenticatedRequest(http.MethodGet, "/api/v1/sellout/share-target/baseline?chain=fathalla&year=2026", tenant)
	rec := httptest.NewRecorder()
	h.HandleShareTargetBaseline(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("HTTP %d: %s", rec.Code, rec.Body.String())
	}
	var resp domain.ShareTargetBaselineResponse
	if err := json.NewDecoder(rec.Body).Decode(&resp); err != nil {
		t.Fatal(err)
	}
	if resp.MonthsWithData != 2 {
		t.Fatalf("months %d", resp.MonthsWithData)
	}
	if len(resp.Categories) != 2 {
		t.Fatalf("categories %+v", resp.Categories)
	}
	if math.Abs(resp.TotalOwnEGP-50) > 0.01 {
		t.Fatalf("own %v", resp.TotalOwnEGP)
	}
	if math.Abs(resp.TotalMarketEGP-150) > 0.01 {
		t.Fatalf("market %v want 150", resp.TotalMarketEGP)
	}
	// gomla row must not inflate fathalla
	for _, c := range resp.Categories {
		if c.OwnRevenueEGP > 100 {
			t.Fatalf("cross-chain leak: %+v", c)
		}
	}
	if len(resp.Branches) < 2 {
		t.Fatalf("branches %+v", resp.Branches)
	}
}

func TestShareTargetBaselineRequiresChain(t *testing.T) {
	h, tenant := seedShareTarget(t)
	req := authenticatedRequest(http.MethodGet, "/api/v1/sellout/share-target/baseline?year=2026", tenant)
	rec := httptest.NewRecorder()
	h.HandleShareTargetBaseline(rec, req)
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("want 400 got %d", rec.Code)
	}
}

func TestShareTargetPreviewAndSave(t *testing.T) {
	h, tenant := seedShareTarget(t)
	delta := 5.0
	annualize := false
	body, _ := json.Marshal(map[string]interface{}{
		"retailer_chain":    "fathalla",
		"year":              2026,
		"market_growth_pct": 0,
		"months_with_data":  2,
		"annualize":         annualize,
		"delta_pts":         delta,
	})
	req := authenticatedRequest(http.MethodPost, "/api/v1/sellout/share-target/preview", tenant)
	req.Body = httptest.NewRecorder().Result().Body // placeholder
	req = req.WithContext(req.Context())
	req.Body = ioNopCloser(bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	// elevate to company manager for save later
	claims := &domain.UserClaims{
		UserID: "u", TenantID: tenant, Email: "m@adeco.com",
		Role: domain.RoleVendorAdmin, Name: "Mgr",
	}
	req = req.WithContext(context.WithValue(req.Context(), middleware.UserClaimsContextKey, claims))

	rec := httptest.NewRecorder()
	h.HandleShareTargetPreview(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("preview HTTP %d: %s", rec.Code, rec.Body.String())
	}
	var preview shareTargetPreviewResponse
	if err := json.NewDecoder(rec.Body).Decode(&preview); err != nil {
		t.Fatal(err)
	}
	if !preview.CanSave || preview.Plan.HasShareOver100 {
		t.Fatalf("plan %+v", preview.Plan)
	}
	if len(preview.Cascades) != 2 {
		t.Fatalf("cascades %d", len(preview.Cascades))
	}
	if preview.Plan.TotalTargetEGP <= preview.Plan.TotalOwnEGP {
		t.Fatalf("target should rise with +5pt: own=%v target=%v", preview.Plan.TotalOwnEGP, preview.Plan.TotalTargetEGP)
	}

	saveBody, _ := json.Marshal(map[string]interface{}{
		"retailer_chain":    "fathalla",
		"year":              2026,
		"market_growth_pct": 0,
		"months_with_data":  2,
		"annualize":         annualize,
		"delta_pts":         delta,
		"notes":             "اختبار حصة",
	})
	saveReq := authenticatedRequest(http.MethodPost, "/api/v1/sellout/share-target", tenant)
	saveReq = saveReq.WithContext(context.WithValue(saveReq.Context(), middleware.UserClaimsContextKey, claims))
	saveReq.Body = ioNopCloser(bytes.NewReader(saveBody))
	saveReq.Header.Set("Content-Type", "application/json")
	saveRec := httptest.NewRecorder()
	h.HandleShareTargetSave(saveRec, saveReq)
	if saveRec.Code != http.StatusOK {
		t.Fatalf("save HTTP %d: %s", saveRec.Code, saveRec.Body.String())
	}
	var saved map[string]json.RawMessage
	if err := json.NewDecoder(saveRec.Body).Decode(&saved); err != nil {
		t.Fatal(err)
	}
	var target domain.TargetRecord
	if err := json.Unmarshal(saved["target"], &target); err != nil {
		t.Fatal(err)
	}
	if target.Origin != sharetarget.OriginShare {
		t.Fatalf("origin %q", target.Origin)
	}
	if target.ShareMeta == nil || len(target.ShareMeta.Categories) != 2 {
		t.Fatalf("share meta %+v", target.ShareMeta)
	}
	if target.TargetType != "sell_out" || target.Month != 0 {
		t.Fatalf("must behave as normal full-year sell_out: %+v", target)
	}
	if math.Abs(target.TargetRevenueEGP-preview.Plan.TotalTargetEGP) > 0.02 {
		t.Fatalf("saved rev %v vs plan %v", target.TargetRevenueEGP, preview.Plan.TotalTargetEGP)
	}

	// Detail breakdown must work like a normal target.
	bdReq := authenticatedRequest(http.MethodGet, "/api/v1/sellout/targets/"+target.ID+"/breakdown", tenant)
	bdReq.SetPathValue("id", target.ID)
	bdRec := httptest.NewRecorder()
	h.HandleTargetBreakdown(bdRec, bdReq)
	if bdRec.Code != http.StatusOK {
		t.Fatalf("breakdown HTTP %d: %s", bdRec.Code, bdRec.Body.String())
	}
}

func TestShareTargetBaselineListsEveryCategory(t *testing.T) {
	t.Setenv("TASHIL_TARGETS_DIR", t.TempDir())
	h, bq := setupTestAnalyticsHandler()
	tenant := "tenant-share-many"
	ctx := context.Background()
	var facts []domain.SellOutFact
	for i := 0; i < 12; i++ {
		cat := "فئة-" + strconv.Itoa(i+1)
		facts = append(facts,
			shareFact("o"+strconv.Itoa(i), tenant, "fathalla", "s1", "الرحاب", cat, "sku"+strconv.Itoa(i), "2026-05-01", 5, 10+float64(i), true, ""),
			shareFact("c"+strconv.Itoa(i), tenant, "fathalla", "s1", "الرحاب", cat, "comp"+strconv.Itoa(i), "2026-05-01", 5, 20+float64(i), false, "Comp"),
		)
	}
	if err := bq.InsertSellOutFacts(ctx, facts); err != nil {
		t.Fatal(err)
	}
	req := authenticatedRequest(http.MethodGet, "/api/v1/sellout/share-target/baseline?chain=fathalla&year=2026", tenant)
	rec := httptest.NewRecorder()
	h.HandleShareTargetBaseline(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("HTTP %d: %s", rec.Code, rec.Body.String())
	}
	var resp domain.ShareTargetBaselineResponse
	if err := json.NewDecoder(rec.Body).Decode(&resp); err != nil {
		t.Fatal(err)
	}
	if len(resp.Categories) != 12 {
		t.Fatalf("step2 must list all categories, got %d", len(resp.Categories))
	}

	annualize := false
	body, _ := json.Marshal(map[string]interface{}{
		"retailer_chain": "fathalla",
		"year":           2026,
		"annualize":      annualize,
		"delta_pts":      1.0,
	})
	claims := &domain.UserClaims{
		UserID: "u", TenantID: tenant, Role: domain.RoleVendorAdmin, Email: "m@x.com",
	}
	prevReq := authenticatedRequest(http.MethodPost, "/api/v1/sellout/share-target/preview", tenant)
	prevReq = prevReq.WithContext(context.WithValue(prevReq.Context(), middleware.UserClaimsContextKey, claims))
	prevReq.Body = ioNopCloser(bytes.NewReader(body))
	prevReq.Header.Set("Content-Type", "application/json")
	prevRec := httptest.NewRecorder()
	h.HandleShareTargetPreview(prevRec, prevReq)
	if prevRec.Code != http.StatusOK {
		t.Fatalf("preview HTTP %d: %s", prevRec.Code, prevRec.Body.String())
	}
	var preview shareTargetPreviewResponse
	if err := json.NewDecoder(prevRec.Body).Decode(&preview); err != nil {
		t.Fatal(err)
	}
	if len(preview.Plan.Categories) != 12 || len(preview.Cascades) != 12 {
		t.Fatalf("step3 must list same categories: plan=%d cascades=%d", len(preview.Plan.Categories), len(preview.Cascades))
	}
}

func TestShareTargetSaveBlocksOver100(t *testing.T) {
	h, tenant := seedShareTarget(t)
	annualize := false
	over := 100.5
	body, _ := json.Marshal(map[string]interface{}{
		"retailer_chain": "fathalla",
		"year":           2026,
		"annualize":      annualize,
		"categories": []map[string]interface{}{
			{"category": "صابون", "desired_share_pct": over},
		},
	})
	claims := &domain.UserClaims{
		UserID: "u", TenantID: tenant, Role: domain.RoleVendorAdmin, Email: "m@x.com",
	}
	req := authenticatedRequest(http.MethodPost, "/api/v1/sellout/share-target", tenant)
	req = req.WithContext(context.WithValue(req.Context(), middleware.UserClaimsContextKey, claims))
	req.Body = ioNopCloser(bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	h.HandleShareTargetSave(rec, req)
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("want 400 got %d %s", rec.Code, rec.Body.String())
	}
}

type nopCloser struct{ *bytes.Reader }

func (nopCloser) Close() error { return nil }

func ioNopCloser(r *bytes.Reader) nopCloser { return nopCloser{r} }
