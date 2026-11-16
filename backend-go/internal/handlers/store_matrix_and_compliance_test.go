package handlers

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/tashil/data-sharing/backend/internal/domain"
	"github.com/tashil/data-sharing/backend/internal/middleware"
	"github.com/tashil/data-sharing/backend/internal/service/bigquery"
)

func setupTestAnalyticsHandler() (*AnalyticsHandler, *bigquery.Client) {
	bqClient := bigquery.NewClient("test-project", "test-dataset", true)
	handler := NewAnalyticsHandler(bqClient)
	return handler, bqClient
}

func authenticatedRequest(method, target string, tenantID string) *http.Request {
	req := httptest.NewRequest(method, target, nil)
	claims := &domain.UserClaims{
		UserID:   "test-user",
		TenantID: tenantID,
		Email:    "analyst@adeco.com",
		Role:     domain.RoleAnalyst,
		Name:     "Adeco Analyst",
	}
	ctx := context.WithValue(req.Context(), middleware.UserClaimsContextKey, claims)
	return req.WithContext(ctx)
}

func TestStoreMatrixHandlerAndFilters(t *testing.T) {
	handler, _ := setupTestAnalyticsHandler()

	// 1. Unfiltered GET /api/v1/analytics/store-matrix
	req := authenticatedRequest(http.MethodGet, "/api/v1/analytics/store-matrix", "tenant-adeco")
	rec := httptest.NewRecorder()
	handler.HandleStoreMatrix(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected HTTP 200, got %d", rec.Code)
	}

	var allStores []domain.StoreBenchmarkItem
	if err := json.NewDecoder(rec.Body).Decode(&allStores); err != nil {
		t.Fatalf("failed to decode response: %v", err)
	}

	if len(allStores) == 0 {
		t.Fatal("expected store benchmark items, got 0")
	}

	// Verify ranking is monotonic (Rank 1, 2, 3...) and sorted by TotalRevenue descending
	for i := 0; i < len(allStores); i++ {
		if allStores[i].Rank != i+1 {
			t.Errorf("expected store at index %d to have rank %d, got %d", i, i+1, allStores[i].Rank)
		}
		if i > 0 && allStores[i].TotalRevenue > allStores[i-1].TotalRevenue {
			t.Errorf("stores not sorted descending by revenue: %f > %f", allStores[i].TotalRevenue, allStores[i-1].TotalRevenue)
		}
		if allStores[i].Tier == "" {
			t.Errorf("store %s has empty tier", allStores[i].StoreID)
		}
		if allStores[i].VelocityUnitsPerDay <= 0 {
			t.Errorf("store %s has invalid velocity: %f", allStores[i].StoreID, allStores[i].VelocityUnitsPerDay)
		}
	}

	// 2. Filter by region: شرق الإسكندرية
	reqRegion := authenticatedRequest(http.MethodGet, "/api/v1/analytics/store-matrix?region=شرق+الإسكندرية", "tenant-adeco")
	recRegion := httptest.NewRecorder()
	handler.HandleStoreMatrix(recRegion, reqRegion)

	if recRegion.Code != http.StatusOK {
		t.Fatalf("expected HTTP 200, got %d", recRegion.Code)
	}

	var eastAlexStores []domain.StoreBenchmarkItem
	if err := json.NewDecoder(recRegion.Body).Decode(&eastAlexStores); err != nil {
		t.Fatalf("failed to decode response: %v", err)
	}

	for _, s := range eastAlexStores {
		if s.Region != "شرق الإسكندرية" {
			t.Errorf("expected region شرق الإسكندرية, got %s", s.Region)
		}
	}

	// 3. Filter by tier: Tier A
	reqTier := authenticatedRequest(http.MethodGet, "/api/v1/analytics/store-matrix?tier=Tier+A", "tenant-adeco")
	recTier := httptest.NewRecorder()
	handler.HandleStoreMatrix(recTier, reqTier)

	var tierAStores []domain.StoreBenchmarkItem
	if err := json.NewDecoder(recTier.Body).Decode(&tierAStores); err != nil {
		t.Fatalf("failed to decode response: %v", err)
	}

	for _, s := range tierAStores {
		if s.Tier != "Tier A" {
			t.Errorf("expected Tier A, got %s", s.Tier)
		}
	}

	// 4. Filter by chain: carrefour
	reqChain := authenticatedRequest(http.MethodGet, "/api/v1/analytics/store-matrix?chain=carrefour", "tenant-adeco")
	recChain := httptest.NewRecorder()
	handler.HandleStoreMatrix(recChain, reqChain)

	var carrefourStores []domain.StoreBenchmarkItem
	if err := json.NewDecoder(recChain.Body).Decode(&carrefourStores); err != nil {
		t.Fatalf("failed to decode response: %v", err)
	}

	for _, s := range carrefourStores {
		if s.RetailerChain != "carrefour" {
			t.Errorf("expected retailer_chain carrefour, got %s", s.RetailerChain)
		}
	}

	// 5. Unauthorized request without RLS
	unauthReq := httptest.NewRequest(http.MethodGet, "/api/v1/analytics/store-matrix", nil)
	unauthRec := httptest.NewRecorder()
	handler.HandleStoreMatrix(unauthRec, unauthReq)
	if unauthRec.Code != http.StatusUnauthorized {
		t.Errorf("expected HTTP 401 for unauthenticated request, got %d", unauthRec.Code)
	}

	// 6. Normalized tenant "adeco" (without tenant- prefix) matches same stores
	reqNorm := authenticatedRequest(http.MethodGet, "/api/v1/analytics/store-matrix", "adeco")
	recNorm := httptest.NewRecorder()
	handler.HandleStoreMatrix(recNorm, reqNorm)
	if recNorm.Code != http.StatusOK {
		t.Fatalf("expected HTTP 200, got %d", recNorm.Code)
	}
	var normStores []domain.StoreBenchmarkItem
	if err := json.NewDecoder(recNorm.Body).Decode(&normStores); err != nil {
		t.Fatalf("failed to decode: %v", err)
	}
	if len(normStores) != len(allStores) {
		t.Errorf("expected %d stores for normalized adeco, got %d", len(allStores), len(normStores))
	}

	// 7. Cross-tenant isolation: Unilever gets Unilever stores, unknown foreign tenant gets 0 stores
	reqUnilever := authenticatedRequest(http.MethodGet, "/api/v1/analytics/store-matrix", "tenant-unilever")
	recUnilever := httptest.NewRecorder()
	handler.HandleStoreMatrix(recUnilever, reqUnilever)
	if recUnilever.Code != http.StatusOK {
		t.Fatalf("expected HTTP 200, got %d", recUnilever.Code)
	}
	var unileverStores []domain.StoreBenchmarkItem
	if err := json.NewDecoder(recUnilever.Body).Decode(&unileverStores); err != nil {
		t.Fatalf("failed to decode: %v", err)
	}
	if len(unileverStores) == 0 {
		t.Errorf("expected seeded stores for tenant-unilever, got 0")
	}

	reqUnknown := authenticatedRequest(http.MethodGet, "/api/v1/analytics/store-matrix", "tenant-unknown-foreign")
	recUnknown := httptest.NewRecorder()
	handler.HandleStoreMatrix(recUnknown, reqUnknown)
	if recUnknown.Code != http.StatusOK {
		t.Fatalf("expected HTTP 200, got %d", recUnknown.Code)
	}
	var unknownStores []domain.StoreBenchmarkItem
	if err := json.NewDecoder(recUnknown.Body).Decode(&unknownStores); err != nil {
		t.Fatalf("failed to decode: %v", err)
	}
	if len(unknownStores) != 0 {
		t.Errorf("expected 0 stores for unknown foreign tenant, got %d", len(unknownStores))
	}
}

func TestPricingComplianceHandlerAndFilters(t *testing.T) {
	handler, _ := setupTestAnalyticsHandler()

	// 1. Unfiltered GET /api/v1/analytics/pricing-compliance
	req := authenticatedRequest(http.MethodGet, "/api/v1/analytics/pricing-compliance", "tenant-adeco")
	rec := httptest.NewRecorder()
	handler.HandlePricingCompliance(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected HTTP 200, got %d", rec.Code)
	}

	var allItems []domain.PricingComplianceItem
	if err := json.NewDecoder(rec.Body).Decode(&allItems); err != nil {
		t.Fatalf("failed to decode response: %v", err)
	}

	if len(allItems) == 0 {
		t.Fatal("expected pricing compliance items, got 0")
	}

	// Verify price delta formulas on all items
	hasCompliant := false
	hasUnderCutting := false
	hasPriceGouging := false
	hasActivePromo := false

	for _, item := range allItems {
		expectedDelta := domain.CalculatePriceDeltaPct(item.ActualPrice, item.RecommendedPrice)
		if item.PriceDeltaPct != expectedDelta {
			t.Errorf("item %s: expected delta %f, got %f", item.SKUName, expectedDelta, item.PriceDeltaPct)
		}
		expectedType := domain.ClassifyPriceViolation(item.PriceDeltaPct)
		if item.ViolationType != expectedType {
			t.Errorf("item %s: expected violation %s, got %s", item.SKUName, expectedType, item.ViolationType)
		}

		if item.ViolationType == "compliant" {
			hasCompliant = true
		}
		if item.ViolationType == "under_cutting" {
			hasUnderCutting = true
		}
		if item.ViolationType == "price_gouging" {
			hasPriceGouging = true
		}
		if item.IsPromoActive && item.PromoUpliftPct > 0 {
			hasActivePromo = true
		}
	}

	if !hasCompliant || !hasUnderCutting || !hasPriceGouging {
		t.Errorf("missing diverse violation types: compliant=%v, under_cutting=%v, price_gouging=%v", hasCompliant, hasUnderCutting, hasPriceGouging)
	}
	if !hasActivePromo {
		t.Error("expected at least one active promo with positive uplift")
	}

	// 2. Filter by violation_only=true
	reqViolations := authenticatedRequest(http.MethodGet, "/api/v1/analytics/pricing-compliance?violation_only=true", "tenant-adeco")
	recViolations := httptest.NewRecorder()
	handler.HandlePricingCompliance(recViolations, reqViolations)

	var violationItems []domain.PricingComplianceItem
	if err := json.NewDecoder(recViolations.Body).Decode(&violationItems); err != nil {
		t.Fatalf("failed to decode response: %v", err)
	}

	for _, v := range violationItems {
		if v.ViolationType == "compliant" {
			t.Errorf("expected only violations, but found compliant item: %s", v.SKUName)
		}
	}

	// 3. Filter by category: زيوت طعام
	reqCat := authenticatedRequest(http.MethodGet, "/api/v1/analytics/pricing-compliance?category=زيوت+طعام", "tenant-adeco")
	recCat := httptest.NewRecorder()
	handler.HandlePricingCompliance(recCat, reqCat)

	var catItems []domain.PricingComplianceItem
	if err := json.NewDecoder(recCat.Body).Decode(&catItems); err != nil {
		t.Fatalf("failed to decode response: %v", err)
	}

	for _, c := range catItems {
		if c.Category != "زيوت طعام" {
			t.Errorf("expected category زيوت طعام, got %s", c.Category)
		}
	}

	// 4. Filter by chain: carrefour
	reqChain := authenticatedRequest(http.MethodGet, "/api/v1/analytics/pricing-compliance?chain=carrefour", "tenant-adeco")
	recChain := httptest.NewRecorder()
	handler.HandlePricingCompliance(recChain, reqChain)

	var chainItems []domain.PricingComplianceItem
	if err := json.NewDecoder(recChain.Body).Decode(&chainItems); err != nil {
		t.Fatalf("failed to decode response: %v", err)
	}

	for _, ch := range chainItems {
		if ch.RetailerChain != "carrefour" {
			t.Errorf("expected retailer_chain carrefour, got %s", ch.RetailerChain)
		}
	}

	// 5. Unauthorized request without RLS
	unauthReq := httptest.NewRequest(http.MethodGet, "/api/v1/analytics/pricing-compliance", nil)
	unauthRec := httptest.NewRecorder()
	handler.HandlePricingCompliance(unauthRec, unauthReq)
	if unauthRec.Code != http.StatusUnauthorized {
		t.Errorf("expected HTTP 401 for unauthenticated request, got %d", unauthRec.Code)
	}

	// 6. Cross-tenant isolation: Unilever gets only Unilever items, unknown foreign tenant gets 0 items
	reqUnilever := authenticatedRequest(http.MethodGet, "/api/v1/analytics/pricing-compliance", "tenant-unilever")
	recUnilever := httptest.NewRecorder()
	handler.HandlePricingCompliance(recUnilever, reqUnilever)
	if recUnilever.Code != http.StatusOK {
		t.Fatalf("expected HTTP 200, got %d", recUnilever.Code)
	}
	var unileverItems []domain.PricingComplianceItem
	if err := json.NewDecoder(recUnilever.Body).Decode(&unileverItems); err != nil {
		t.Fatalf("failed to decode: %v", err)
	}
	if len(unileverItems) == 0 {
		t.Errorf("expected Unilever pricing items, got 0")
	}
	for _, u := range unileverItems {
		if u.TenantID != "tenant-unilever" {
			t.Errorf("expected tenant-unilever item, got %s", u.TenantID)
		}
	}

	reqUnknown := authenticatedRequest(http.MethodGet, "/api/v1/analytics/pricing-compliance", "tenant-unknown-foreign")
	recUnknown := httptest.NewRecorder()
	handler.HandlePricingCompliance(recUnknown, reqUnknown)
	if recUnknown.Code != http.StatusOK {
		t.Fatalf("expected HTTP 200, got %d", recUnknown.Code)
	}
	var unknownItems []domain.PricingComplianceItem
	if err := json.NewDecoder(recUnknown.Body).Decode(&unknownItems); err != nil {
		t.Fatalf("failed to decode: %v", err)
	}
	if len(unknownItems) != 0 {
		t.Errorf("expected 0 items for unknown foreign tenant, got %d", len(unknownItems))
	}
}

func TestExecutiveAndRecordsDateRangeQueryParams(t *testing.T) {
	handler, bqClient := setupTestAnalyticsHandler()
	ctx := context.Background()

	// Insert two known records on distinct dates for an isolated tenant
	tenantID := "tenant-unknown-daterange-test"
	_ = bqClient.InsertSellOutFacts(ctx, []domain.SellOutFact{
		{
			RecordID:        "dr_1",
			TenantID:        tenantID,
			RetailerChain:   "carrefour",
			StoreID:         "crf_cairo_maadi",
			StoreName:       "كارفور المعادي",
			Barcode:         "6221155001234",
			SKUName:         "Adeco Olive Oil 500ml",
			Category:        "زيوت طعام",
			QuantitySold:    10,
			NetRevenue:      2500.0,
			UnitPrice:       250.0,
			TransactionDate: "2026-02-10",
		},
		{
			RecordID:        "dr_2",
			TenantID:        tenantID,
			RetailerChain:   "fathalla",
			StoreID:         "fat_alex_smouha",
			StoreName:       "فتح الله سموحة",
			Barcode:         "6221155001241",
			SKUName:         "Adeco Sunflower Oil 1L",
			Category:        "زيوت طعام",
			QuantitySold:    20,
			NetRevenue:      2200.0,
			UnitPrice:       110.0,
			TransactionDate: "2026-02-20",
		},
	})

	// 1. Test HandleExecutiveSummary with start_date and end_date matching only dr_1
	reqExec := authenticatedRequest(http.MethodGet, "/api/v1/analytics/executive?period=CUSTOM&start_date=2026-02-01&end_date=2026-02-15", tenantID)
	recExec := httptest.NewRecorder()
	handler.HandleExecutiveSummary(recExec, reqExec)

	if recExec.Code != http.StatusOK {
		t.Fatalf("expected HTTP 200, got %d", recExec.Code)
	}
	var kpis domain.ExecutiveKPIs
	if err := json.NewDecoder(recExec.Body).Decode(&kpis); err != nil {
		t.Fatalf("failed to decode executive KPIs: %v", err)
	}
	if kpis.TotalRevenue != 2500.0 || kpis.TotalUnitsSold != 10 {
		t.Errorf("expected custom range KPIs revenue=2500.0, units=10, got rev=%f units=%d", kpis.TotalRevenue, kpis.TotalUnitsSold)
	}

	// 2. Test HandleRecords with start_date and end_date matching only dr_2
	reqRecs := authenticatedRequest(http.MethodGet, "/api/v1/analytics/records?start_date=2026-02-16&end_date=2026-02-28", tenantID)
	recRecs := httptest.NewRecorder()
	handler.HandleRecords(recRecs, reqRecs)

	if recRecs.Code != http.StatusOK {
		t.Fatalf("expected HTTP 200, got %d", recRecs.Code)
	}
	var pageResp struct {
		Records    []domain.SellOutFact `json:"records"`
		TotalCount int                  `json:"total_count"`
	}
	if err := json.NewDecoder(recRecs.Body).Decode(&pageResp); err != nil {
		t.Fatalf("failed to decode records response: %v", err)
	}
	if pageResp.TotalCount != 1 || len(pageResp.Records) != 1 || pageResp.Records[0].RecordID != "dr_2" {
		t.Errorf("expected 1 record (dr_2) in date range, got %+v", pageResp)
	}
}

func TestPricingCompliancePaginationAndCategoryNormalization(t *testing.T) {
	// 1. Verify NormalizeProductCategory merges Arabic spelling variants into canonical categories
	cases := map[string]string{
		"صابون سائل للاطباق":     "صابون سائل اطباق",
		"صابون سائل اطباق":      "صابون سائل اطباق",
		"كلور ألوان":            "كلور ألوان",
		"كلور الوان":            "كلور ألوان",
		"كلور ارضيات":           "منظف ارضيات",
		"صابون سائل للارضيات":    "منظف ارضيات",
		"مطهر ارضيات":           "منظف ارضيات",
		"منظف ارضيات":           "منظف ارضيات",
		"هاند وواش":             "هاند وواش",
		"هاند ووش":              "هاند وواش",
		"مطهرعام":               "مطهر عام",
		"مطهر عام":              "مطهر عام",
		"مسحوق بودر غسالات اطباق": "مسحوق غسالات اطباق",
	}
	for raw, expected := range cases {
		got := domain.NormalizeProductCategory(raw)
		if got != expected {
			t.Errorf("NormalizeProductCategory(%q) = %q, want %q", raw, got, expected)
		}
	}

	// 2. Seed 60 items for tenant-adeco via SetTenantWorkbookAnalytics with variant category names
	handler, bqClient := setupTestAnalyticsHandler()
	var items []domain.PricingComplianceItem
	rawCategories := []string{
		"صابون سائل للاطباق",
		"صابون سائل اطباق",
		"كلور ألوان",
		"كلور الوان",
		"كلور ارضيات",
		"منظف ارضيات",
		"هاند وواش",
		"هاند ووش",
	}
	for i := 0; i < 60; i++ {
		violationType := "compliant"
		delta := 0.0
		actual := 100.0
		if i%3 == 0 {
			violationType = "under_cutting"
			delta = -10.0
			actual = 90.0
		}
		isPromo := i%4 == 0
		uplift := 0.0
		if isPromo {
			uplift = 20.0
		}
		items = append(items, domain.PricingComplianceItem{
			TenantID:         "tenant-adeco",
			Barcode:          "622300139000" + string(rune('0'+(i%10))),
			SKUName:          "منتج أدكو " + string(rune('A'+(i%26))),
			Category:         rawCategories[i%len(rawCategories)],
			RetailerChain:    "fathalla",
			StoreName:        "فتح الله سموحة",
			RecommendedPrice: 100.0,
			ActualPrice:      actual,
			PriceDeltaPct:    delta,
			ViolationType:    violationType,
			IsPromoActive:    isPromo,
			PromoUpliftPct:   uplift,
		})
	}
	_ = bqClient.SetTenantWorkbookAnalytics(context.Background(), "tenant-adeco", bigquery.TenantWorkbookAnalytics{
		PricingItems: items,
	})

	// 3. Test Page 1 with limit=25&offset=0
	reqPage1 := authenticatedRequest(http.MethodGet, "/api/v1/analytics/pricing-compliance?limit=25&offset=0", "tenant-adeco")
	recPage1 := httptest.NewRecorder()
	handler.HandlePricingCompliance(recPage1, reqPage1)

	if recPage1.Code != http.StatusOK {
		t.Fatalf("expected HTTP 200, got %d", recPage1.Code)
	}
	var respPage1 PaginatedPricingComplianceResponse
	if err := json.NewDecoder(recPage1.Body).Decode(&respPage1); err != nil {
		t.Fatalf("failed to decode paginated response: %v", err)
	}
	if respPage1.TotalCount != 60 {
		t.Errorf("expected total_count=60, got %d", respPage1.TotalCount)
	}
	if len(respPage1.Items) != 25 {
		t.Errorf("expected 25 items on page 1, got %d", len(respPage1.Items))
	}
	if respPage1.ViolationCount != 20 || respPage1.CompliantCount != 40 {
		t.Errorf("expected violation_count=20, compliant_count=40, got violations=%d compliant=%d", respPage1.ViolationCount, respPage1.CompliantCount)
	}

	// Verify available_categories are deduplicated into exact 4 canonical categories and do NOT contain unapproved seed categories
	if len(respPage1.AvailableCategories) != 4 {
		t.Errorf("expected 4 deduplicated canonical categories, got %d: %v", len(respPage1.AvailableCategories), respPage1.AvailableCategories)
	}
	for _, cat := range respPage1.AvailableCategories {
		if cat == "زيوت طعام" || cat == "صلصة ومعلبات" || cat == "بقوليات ومعلبات" {
			t.Errorf("unexpected unapproved seed category %q in available_categories", cat)
		}
	}

	// 4. Test switching to limit=50&offset=0
	reqPage50 := authenticatedRequest(http.MethodGet, "/api/v1/analytics/pricing-compliance?limit=50&offset=0", "tenant-adeco")
	recPage50 := httptest.NewRecorder()
	handler.HandlePricingCompliance(recPage50, reqPage50)

	var respPage50 PaginatedPricingComplianceResponse
	if err := json.NewDecoder(recPage50.Body).Decode(&respPage50); err != nil {
		t.Fatalf("failed to decode limit=50 response: %v", err)
	}
	if len(respPage50.Items) != 50 || respPage50.TotalCount != 60 {
		t.Errorf("expected 50 items and total_count=60, got len=%d total=%d", len(respPage50.Items), respPage50.TotalCount)
	}

	// 5. Test last page limit=25&offset=50 (should return remaining 10 items)
	reqLastPage := authenticatedRequest(http.MethodGet, "/api/v1/analytics/pricing-compliance?limit=25&offset=50", "tenant-adeco")
	recLastPage := httptest.NewRecorder()
	handler.HandlePricingCompliance(recLastPage, reqLastPage)

	var respLastPage PaginatedPricingComplianceResponse
	if err := json.NewDecoder(recLastPage.Body).Decode(&respLastPage); err != nil {
		t.Fatalf("failed to decode offset=50 response: %v", err)
	}
	if len(respLastPage.Items) != 10 {
		t.Errorf("expected 10 items on last page (offset=50), got %d", len(respLastPage.Items))
	}

	// 6. Test promo_only=true&limit=25&offset=0 (15 items have IsPromoActive=true)
	reqPromo := authenticatedRequest(http.MethodGet, "/api/v1/analytics/pricing-compliance?promo_only=true&limit=25&offset=0", "tenant-adeco")
	recPromo := httptest.NewRecorder()
	handler.HandlePricingCompliance(recPromo, reqPromo)

	var respPromo PaginatedPricingComplianceResponse
	if err := json.NewDecoder(recPromo.Body).Decode(&respPromo); err != nil {
		t.Fatalf("failed to decode promo_only response: %v", err)
	}
	if respPromo.TotalCount != 15 || len(respPromo.Items) != 15 {
		t.Errorf("expected 15 promo items, got total=%d len=%d", respPromo.TotalCount, len(respPromo.Items))
	}
}




func TestStoreMatrixMatchedMonthsHandler(t *testing.T) {
	handler, bq := setupTestAnalyticsHandler()
	mk := func(id, date string) domain.SellOutFact {
		return domain.SellOutFact{
			RecordID: id, TenantID: "tenant-mm", RetailerChain: "gomla", StoreID: "s1", StoreName: "s1",
			Barcode: "6220000000001", SKUName: "Item 1", QuantitySold: 1, NetRevenue: 10,
			TransactionDate: date, IsOwnBrand: true,
		}
	}
	if err := bq.ReplaceTenantFacts(context.Background(), "tenant-mm", []domain.SellOutFact{
		mk("a", "2025-01-10"), mk("b", "2025-02-10"),
		mk("c", "2026-01-10"), mk("d", "2026-02-10"), mk("e", "2026-03-10"),
	}); err != nil {
		t.Fatal(err)
	}

	rec := httptest.NewRecorder()
	handler.HandleStoreMatrixMatchedMonths(rec, authenticatedRequest(http.MethodGet,
		"/api/v1/analytics/store-matrix/matched-months?year=2026&comp_year=2025&chain=gomla", "tenant-mm"))
	if rec.Code != http.StatusOK {
		t.Fatalf("want 200 got %d: %s", rec.Code, rec.Body.String())
	}
	var body struct {
		Year     int   `json:"year"`
		CompYear int   `json:"comp_year"`
		Months   []int `json:"months"`
	}
	if err := json.NewDecoder(rec.Body).Decode(&body); err != nil {
		t.Fatal(err)
	}
	if body.Year != 2026 || body.CompYear != 2025 || len(body.Months) != 2 || body.Months[0] != 1 || body.Months[1] != 2 {
		t.Fatalf("unexpected body: %+v", body)
	}

	bad := httptest.NewRecorder()
	handler.HandleStoreMatrixMatchedMonths(bad, authenticatedRequest(http.MethodGet,
		"/api/v1/analytics/store-matrix/matched-months?year=2026", "tenant-mm"))
	if bad.Code != http.StatusBadRequest {
		t.Fatalf("missing comp_year: want 400 got %d", bad.Code)
	}

	empty := httptest.NewRecorder()
	handler.HandleStoreMatrixMatchedMonths(empty, authenticatedRequest(http.MethodGet,
		"/api/v1/analytics/store-matrix/matched-months?year=2026&comp_year=2019&chain=gomla", "tenant-mm"))
	if empty.Code != http.StatusOK || !json.Valid(empty.Body.Bytes()) || !strings.Contains(empty.Body.String(), `"months":[]`) {
		t.Fatalf("no overlap should return months:[]: %d %s", empty.Code, empty.Body.String())
	}
}
