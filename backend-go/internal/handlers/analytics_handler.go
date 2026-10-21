package handlers

import (
	"encoding/json"
	"math"
	"net/http"
	"strconv"
	"strings"

	"github.com/tashil/data-sharing/backend/internal/domain"
	"github.com/tashil/data-sharing/backend/internal/middleware"
	"github.com/tashil/data-sharing/backend/internal/service/bigquery"
)

// AnalyticsHandler serves high-speed OLAP aggregates to Flutter Web.
type AnalyticsHandler struct {
	bqRepo bigquery.Repository
}

// NewAnalyticsHandler creates a new AnalyticsHandler.
func NewAnalyticsHandler(bqRepo bigquery.Repository) *AnalyticsHandler {
	return &AnalyticsHandler{bqRepo: bqRepo}
}

// HandleExecutiveSummary serves GET /api/v1/analytics/executive-summary (and /api/v1/analytics/executive).
func (h *AnalyticsHandler) HandleExecutiveSummary(w http.ResponseWriter, r *http.Request) {
	tenantID, err := middleware.EnforceTenantRLS(r)
	if err != nil {
		http.Error(w, `{"error":"unauthorized tenant context"}`, http.StatusUnauthorized)
		return
	}

	q := r.URL.Query()
	period := q.Get("period")
	if period == "" {
		period = "MTD"
	}
	startDate := q.Get("start_date")
	endDate := q.Get("end_date")
	chain := q.Get("chain")

	kpis, err := h.bqRepo.GetExecutiveKPIs(r.Context(), tenantID, period, startDate, endDate, chain)
	if err != nil {
		http.Error(w, `{"error":"failed to compute executive KPIs"}`, http.StatusInternalServerError)
		return
	}

	// Enforce Chain KAM NDA Protection on competitor chain shares
	if claims, ok := middleware.GetUserClaims(r.Context()); ok && claims != nil {
		if claims.Role == domain.RoleChainKAM && strings.TrimSpace(claims.AssignedChain) != "" {
			assigned := strings.TrimSpace(claims.AssignedChain)
			for i := range kpis.ChainShares {
				if !strings.EqualFold(kpis.ChainShares[i].RetailerChain, assigned) {
					kpis.ChainShares[i].RetailerChain = "nda_redacted"
					kpis.ChainShares[i].DisplayName = "سلسلة تجزئة منافسة (محمي بـ NDA)"
				}
			}
		}
	}

	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(kpis)
}

// PaginatedRecordsResponse formats data table payload.
type PaginatedRecordsResponse struct {
	Records    interface{} `json:"records"`
	TotalCount int         `json:"total_count"`
	Limit      int         `json:"limit"`
	Offset     int         `json:"offset"`
}

// HandleRecords serves GET /api/v1/analytics/records.
func (h *AnalyticsHandler) HandleRecords(w http.ResponseWriter, r *http.Request) {
	tenantID, err := middleware.EnforceTenantRLS(r)
	if err != nil {
		http.Error(w, `{"error":"unauthorized tenant context"}`, http.StatusUnauthorized)
		return
	}

	q := r.URL.Query()
	limit, _ := strconv.Atoi(q.Get("limit"))
	if limit <= 0 || limit > 500 {
		limit = 50
	}
	offset, _ := strconv.Atoi(q.Get("offset"))
	if offset < 0 {
		offset = 0
	}

	filter := bigquery.RecordFilter{
		RetailerChain: q.Get("chain"),
		StoreID:       q.Get("store_id"),
		Category:      q.Get("category"),
		Supplier:      q.Get("supplier"),
		SearchQuery:   q.Get("q"),
		StartDate:     q.Get("start_date"),
		EndDate:       q.Get("end_date"),
		Limit:         limit,
		Offset:        offset,
	}

	if claims, ok := middleware.GetUserClaims(r.Context()); ok && claims != nil {
		if claims.Role == domain.RoleChainKAM && strings.TrimSpace(claims.AssignedChain) != "" {
			filter.RetailerChain = strings.TrimSpace(claims.AssignedChain)
		}
	}

	records, total, err := h.bqRepo.GetSellOutRecords(r.Context(), tenantID, filter)
	if err != nil {
		http.Error(w, `{"error":"failed to query sell out records"}`, http.StatusInternalServerError)
		return
	}

	resp := PaginatedRecordsResponse{
		Records:    records,
		TotalCount: total,
		Limit:      limit,
		Offset:     offset,
	}

	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(resp)
}

// HandleStoreMatrix serves GET /api/v1/analytics/store-matrix.
func (h *AnalyticsHandler) HandleStoreMatrix(w http.ResponseWriter, r *http.Request) {
	tenantID, err := middleware.EnforceTenantRLS(r)
	if err != nil {
		http.Error(w, `{"error":"unauthorized tenant context"}`, http.StatusUnauthorized)
		return
	}

	q := r.URL.Query()
	yr, _ := strconv.Atoi(q.Get("year"))
	mo, _ := strconv.Atoi(q.Get("month"))

	filter := bigquery.StoreMatrixFilter{
		Region:        q.Get("region"),
		Tier:          q.Get("tier"),
		RetailerChain: q.Get("chain"),
		Year:          yr,
		Month:         mo,
		StartDate:     q.Get("start_date"),
		EndDate:       q.Get("end_date"),
	}

	if claims, ok := middleware.GetUserClaims(r.Context()); ok && claims != nil {
		if claims.Role == domain.RoleChainKAM && strings.TrimSpace(claims.AssignedChain) != "" {
			filter.RetailerChain = strings.TrimSpace(claims.AssignedChain)
		}
		if claims.Role == domain.RoleFieldSupervisor && strings.TrimSpace(claims.AssignedRegion) != "" {
			filter.Region = strings.TrimSpace(claims.AssignedRegion)
		}
	}

	stores, err := h.bqRepo.GetStoreBenchmarkMatrix(r.Context(), tenantID, filter)
	if err != nil {
		http.Error(w, `{"error":"failed to compute store matrix"}`, http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(stores)
}

// PaginatedPricingComplianceResponse formats paginated pricing compliance items with summary KPIs, available categories, and monthly price elasticity points.
type PaginatedPricingComplianceResponse struct {
	Items               []domain.PricingComplianceItem       `json:"items"`
	TotalCount          int                                  `json:"total_count"`
	SummaryTotalCount   int                                  `json:"summary_total_count"`
	Limit               int                                  `json:"limit"`
	Offset              int                                  `json:"offset"`
	CompliantCount      int                                  `json:"compliant_count"`
	ViolationCount      int                                  `json:"violation_count"`
	ComplianceRatePct   float64                              `json:"compliance_rate_pct"`
	AvgPromoUpliftPct   float64                              `json:"avg_promo_uplift_pct"`
	AvailableCategories []string                             `json:"available_categories"`
	MonthlyElasticity   []domain.MonthlyPriceElasticityPoint `json:"monthly_elasticity,omitempty"`
	ElasticitySummary   *domain.PriceElasticitySummary       `json:"elasticity_summary,omitempty"`
}

// HandlePricingCompliance serves GET /api/v1/analytics/pricing-compliance.
func (h *AnalyticsHandler) HandlePricingCompliance(w http.ResponseWriter, r *http.Request) {
	tenantID, err := middleware.EnforceTenantRLS(r)
	if err != nil {
		http.Error(w, `{"error":"unauthorized tenant context"}`, http.StatusUnauthorized)
		return
	}

	q := r.URL.Query()
	violationOnlyStr := q.Get("violation_only")
	violationOnly := violationOnlyStr == "true" || violationOnlyStr == "1"
	promoOnlyStr := q.Get("promo_only")
	promoOnly := promoOnlyStr == "true" || promoOnlyStr == "1"

	year, _ := strconv.Atoi(q.Get("year"))
	month, _ := strconv.Atoi(q.Get("month"))
	startDate := q.Get("start_date")
	endDate := q.Get("end_date")

	effectiveChain := q.Get("chain")
	if claims, ok := middleware.GetUserClaims(r.Context()); ok && claims != nil {
		if claims.Role == domain.RoleChainKAM && strings.TrimSpace(claims.AssignedChain) != "" {
			effectiveChain = strings.TrimSpace(claims.AssignedChain)
		}
	}

	limitStr := q.Get("limit")
	offsetStr := q.Get("offset")
	isPaginatedRequest := limitStr != "" || offsetStr != ""

	if !isPaginatedRequest {
		filter := bigquery.PricingComplianceFilter{
			RetailerChain: effectiveChain,
			Category:      q.Get("category"),
			ViolationOnly: violationOnly,
			PromoOnly:     promoOnly,
			Year:          year,
			Month:         month,
			StartDate:     startDate,
			EndDate:       endDate,
		}
		items, err := h.bqRepo.GetPricingCompliance(r.Context(), tenantID, filter)
		if err != nil {
			http.Error(w, `{"error":"failed to compute pricing compliance"}`, http.StatusInternalServerError)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(items)
		return
	}

	limit, _ := strconv.Atoi(limitStr)
	if limit <= 0 || limit > 500 {
		limit = 25
	}
	offset, _ := strconv.Atoi(offsetStr)
	if offset < 0 {
		offset = 0
	}

	allChainItems, err := h.bqRepo.GetPricingCompliance(r.Context(), tenantID, bigquery.PricingComplianceFilter{
		RetailerChain: effectiveChain,
		Year:          year,
		Month:         month,
		StartDate:     startDate,
		EndDate:       endDate,
	})
	if err != nil {
		http.Error(w, `{"error":"failed to compute pricing compliance"}`, http.StatusInternalServerError)
		return
	}

	catSeen := make(map[string]bool)
	availableCategories := make([]string, 0)
	for _, item := range allChainItems {
		normCat := domain.NormalizeProductCategory(item.Category)
		if normCat != "" && !catSeen[normCat] {
			catSeen[normCat] = true
			availableCategories = append(availableCategories, normCat)
		}
	}

	targetCat := domain.NormalizeProductCategory(q.Get("category"))
	hasCatFilter := targetCat != "" && targetCat != "all" && targetCat != "الكل"

	categoryItems := make([]domain.PricingComplianceItem, 0, len(allChainItems))
	for _, item := range allChainItems {
		item.Category = domain.NormalizeProductCategory(item.Category)
		if hasCatFilter && item.Category != targetCat {
			continue
		}
		categoryItems = append(categoryItems, item)
	}

	summaryTotal := len(categoryItems)
	compliantCount := 0
	violationCount := 0
	promoSum := 0.0
	promoCount := 0
	for _, item := range categoryItems {
		if item.ViolationType == "compliant" {
			compliantCount++
		} else {
			violationCount++
		}
		if item.IsPromoActive && item.PromoUpliftPct > 0 {
			promoSum += item.PromoUpliftPct
			promoCount++
		}
	}
	complianceRate := 100.0
	if summaryTotal > 0 {
		complianceRate = math.Round((float64(compliantCount)/float64(summaryTotal))*1000.0) / 10.0
	}
	avgPromoUplift := 0.0
	if promoCount > 0 {
		avgPromoUplift = math.Round((promoSum/float64(promoCount))*10.0) / 10.0
	}

	filteredItems := make([]domain.PricingComplianceItem, 0, len(categoryItems))
	for _, item := range categoryItems {
		if violationOnly && item.ViolationType == "compliant" {
			continue
		}
		if promoOnly && !item.IsPromoActive {
			continue
		}
		filteredItems = append(filteredItems, item)
	}

	totalCount := len(filteredItems)
	pageItems := make([]domain.PricingComplianceItem, 0)
	if offset < totalCount {
		end := offset + limit
		if end > totalCount {
			end = totalCount
		}
		pageItems = filteredItems[offset:end]
	}

	elasticityPoints, elasticitySummary, _ := h.bqRepo.GetMonthlyPriceElasticity(r.Context(), tenantID, bigquery.PricingComplianceFilter{
		RetailerChain: effectiveChain,
		Category:      targetCat,
		Year:          year,
		Month:         month,
		StartDate:     startDate,
		EndDate:       endDate,
	})

	resp := PaginatedPricingComplianceResponse{
		Items:               pageItems,
		TotalCount:          totalCount,
		SummaryTotalCount:   summaryTotal,
		Limit:               limit,
		Offset:              offset,
		CompliantCount:      compliantCount,
		ViolationCount:      violationCount,
		ComplianceRatePct:   complianceRate,
		AvgPromoUpliftPct:   avgPromoUplift,
		AvailableCategories: availableCategories,
		MonthlyElasticity:   elasticityPoints,
		ElasticitySummary:   &elasticitySummary,
	}

	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(resp)
}

// HandleCPFRDashboard serves GET /api/v1/analytics/cpfr for Sell-In vs. Sell-Out reconciliation,
// estimated inventory balances, smart replenishment PO generation, W1+W2 -> EXP forecasting,
// promotions & returns analytics, and field sales rep scorecards.
func (h *AnalyticsHandler) HandleCPFRDashboard(w http.ResponseWriter, r *http.Request) {
	tenantID, err := middleware.EnforceTenantRLS(r)
	if err != nil {
		http.Error(w, `{"error":"unauthorized tenant context"}`, http.StatusUnauthorized)
		return
	}

	q := r.URL.Query()
	leadTime, _ := strconv.Atoi(q.Get("lead_time_days"))
	safetyDays, _ := strconv.Atoi(q.Get("safety_stock_days"))
	yearParam, _ := strconv.Atoi(q.Get("year"))
	chainParam := strings.TrimSpace(q.Get("chain"))
	if chainParam == "" {
		chainParam = strings.TrimSpace(q.Get("retailer_chain"))
	}

	filter := bigquery.CPFRFilter{
		RetailerChain:   chainParam,
		Year:            yearParam,
		Sector:          q.Get("sector"),
		RegionCode:      q.Get("region"),
		Brand:           q.Get("brand"),
		SalesRep:        q.Get("rep"),
		StockStatus:     q.Get("stock_status"),
		LeadTimeDays:    leadTime,
		SafetyStockDays: safetyDays,
	}

	payload, err := h.bqRepo.GetCPFRDashboard(r.Context(), tenantID, filter)
	if err != nil {
		http.Error(w, `{"error":"failed to compute CPFR dashboard"}`, http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(payload)
}



