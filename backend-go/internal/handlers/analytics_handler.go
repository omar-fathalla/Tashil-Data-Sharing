package handlers

import (
	"encoding/json"
	"fmt"
	"math"
	"net/http"
	"sort"
	"strconv"
	"strings"

	"github.com/tashil/data-sharing/backend/internal/domain"
	"github.com/tashil/data-sharing/backend/internal/middleware"
	"github.com/tashil/data-sharing/backend/internal/service/bigquery"
	"github.com/tashil/data-sharing/backend/internal/service/bqsink"
	"github.com/tashil/data-sharing/backend/internal/service/monthlysummary"
)

// AnalyticsHandler serves high-speed OLAP aggregates to Flutter Web.
type AnalyticsHandler struct {
	bqRepo             bigquery.Repository
	records            bqsink.RecordsQuerier
	sellIn             SellInTotalsQuerier
	monthlySummaryOpts monthlysummary.Options
}

// NewAnalyticsHandler creates a new AnalyticsHandler.
func NewAnalyticsHandler(bqRepo bigquery.Repository) *AnalyticsHandler {
	return &AnalyticsHandler{bqRepo: bqRepo}
}

// WithMonthlySummary configures Phase C automatic monthly narrative generation.
func (h *AnalyticsHandler) WithMonthlySummary(opts monthlysummary.Options) *AnalyticsHandler {
	h.monthlySummaryOpts = opts
	return h
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
	if startDate == "" && endDate == "" {
		yr, _ := strconv.Atoi(q.Get("year"))
		mo, _ := strconv.Atoi(q.Get("month"))
		if s, e, ok := yearMonthRange(yr, mo); ok {
			startDate, endDate, period = s, e, "CUSTOM"
		}
	}

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

	// Phase C: attach Arabic monthly narrative grounded only in the KPI numbers above.
	// Runs after NDA masking so competitor chain names are not narrated for Chain KAM.
	monthlysummary.Attach(r.Context(), kpis, h.monthlySummaryOpts)

	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(kpis)
}

// PaginatedRecordsResponse formats data table payload along with full-dataset KPI aggregations.
type PaginatedRecordsResponse struct {
	Records                  interface{}                `json:"records"`
	TotalCount               int                        `json:"total_count"`
	Limit                    int                        `json:"limit"`
	Offset                   int                        `json:"offset"`
	TotalNetRevenue          float64                    `json:"total_net_revenue"`
	TotalUnitsSold           int                        `json:"total_units_sold"`
	TotalCartonsSold         float64                    `json:"total_cartons_sold"`
	TotalFactoryCost         float64                    `json:"total_factory_cost"`
	TotalRetailerGrossProfit float64                    `json:"total_retailer_gross_profit"`
	AvgRetailerMarginPct     float64                    `json:"avg_retailer_margin_pct"`
	ActiveStoresCount        int                        `json:"active_stores_count"`
	ActiveSKUsCount          int                        `json:"active_skus_count"`
	MatchedSKUsCount         int                        `json:"matched_skus_count"`
	MinDate                  string                     `json:"min_date"`
	MaxDate                  string                     `json:"max_date"`
	TopBranchName            string                     `json:"top_branch_name"`
	TopBranchRevenue         float64                    `json:"top_branch_revenue"`
	SKUSummaries             []domain.SellOutSKUSummary `json:"sku_summaries"`
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

	startDate := q.Get("start_date")
	endDate := q.Get("end_date")
	yr, _ := strconv.Atoi(q.Get("year"))
	mo, _ := strconv.Atoi(q.Get("month"))
	if startDate == "" && endDate == "" {
		if s, e, ok := yearMonthRange(yr, mo); ok {
			startDate, endDate = s, e
		}
	}

	filter := bigquery.RecordFilter{
		RetailerChain: q.Get("chain"),
		StoreID:       q.Get("store_id"),
		Category:      q.Get("category"),
		Supplier:      q.Get("supplier"),
		SearchQuery:   q.Get("q"),
		StartDate:     startDate,
		EndDate:       endDate,
		Limit:         0, // Fetch full matched set to compute accurate KPI totals before slicing
		Offset:        0,
	}

	if claims, ok := middleware.GetUserClaims(r.Context()); ok && claims != nil {
		if claims.Role == domain.RoleChainKAM && strings.TrimSpace(claims.AssignedChain) != "" {
			filter.RetailerChain = strings.TrimSpace(claims.AssignedChain)
		}
	}

	if resp, ok := h.recordsFromBigQuery(r.Context(), tenantID, filter, limit, offset); ok {
		setRecordsSource(w, "bigquery")
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(resp)
		return
	}
	setRecordsSource(w, "memory")

	allMatched, total, err := h.bqRepo.GetSellOutRecords(r.Context(), tenantID, filter)
	if err != nil {
		http.Error(w, `{"error":"failed to query sell out records"}`, http.StatusInternalServerError)
		return
	}

	type skuAggBucket struct {
		summary domain.SellOutSKUSummary
		stores  map[string]bool
	}

	var totalRev float64
	var totalUnits int
	var totalCartons float64
	var totalFactoryCost float64
	var totalGrossProfit float64
	var matchedRevForMargin float64
	storesSet := make(map[string]bool)
	skusSet := make(map[string]bool)
	matchedSKUsSet := make(map[string]bool)
	branchRev := make(map[string]float64)
	branchNames := make(map[string]string)
	skuBuckets := make(map[string]*skuAggBucket)
	minDate := ""
	maxDate := ""

	for _, rec := range allMatched {
		totalRev += rec.NetRevenue
		totalUnits += rec.QuantitySold
		totalCartons += rec.CartonsSold
		if rec.TotalFactoryCost > 0 {
			totalFactoryCost += rec.TotalFactoryCost
			totalGrossProfit += rec.RetailerGrossProfit
			matchedRevForMargin += rec.NetRevenue
		}

		storeKey := rec.StoreID
		if storeKey == "" {
			storeKey = rec.StoreName
		}
		if storeKey != "" {
			storesSet[storeKey] = true
			branchRev[storeKey] += rec.NetRevenue
			if rec.StoreName != "" {
				branchNames[storeKey] = rec.StoreName
			} else {
				branchNames[storeKey] = storeKey
			}
		}
		skuKey := rec.Barcode
		if skuKey == "" {
			skuKey = rec.ItemCode
		}
		if skuKey == "" {
			skuKey = rec.SKUName
		}
		if skuKey != "" {
			skusSet[skuKey] = true
			if rec.ItemCode != "" {
				matchedSKUsSet[skuKey] = true
			}
		}
		if rec.TransactionDate != "" {
			if minDate == "" || rec.TransactionDate < minDate {
				minDate = rec.TransactionDate
			}
			if maxDate == "" || rec.TransactionDate > maxDate {
				maxDate = rec.TransactionDate
			}
		}

		groupKey := rec.ItemCode
		if groupKey == "" {
			groupKey = rec.Barcode
		}
		if groupKey == "" {
			groupKey = rec.SKUName
		}
		if groupKey != "" {
			b, exists := skuBuckets[groupKey]
			if !exists {
				rawName := rec.RetailerRawSKUName
				if rawName == "" {
					rawName = rec.SKUName
				}
				b = &skuAggBucket{
					summary: domain.SellOutSKUSummary{
						ItemCode:             rec.ItemCode,
						Barcode:              rec.Barcode,
						SKUName:              rec.SKUName,
						RetailerRawSKUName:   rawName,
						Brand:                domain.InferBrandFromItemName(rec.SKUName, rec.Category),
						Category:             rec.Category,
						ItemType:             rec.ItemType,
						UnitsPerCarton:       rec.UnitsPerCarton,
						OfficialConsumerRSP:  rec.RecommendedPrice,
						CartonPriceInclVAT:   rec.CartonPriceInclVAT,
						FactoryUnitCost:      rec.FactoryUnitCost,
						NetCartonInvoiceCost: rec.NetCartonInvoiceCost,
						InvoiceDiscountPct:   rec.InvoiceDiscountPct,
					},
					stores: make(map[string]bool),
				}
				skuBuckets[groupKey] = b
			} else {
				if b.summary.ItemCode == "" && rec.ItemCode != "" {
					b.summary.ItemCode = rec.ItemCode
				}
				if b.summary.Barcode == "" && rec.Barcode != "" {
					b.summary.Barcode = rec.Barcode
				}
				if b.summary.OfficialConsumerRSP <= 0 && rec.RecommendedPrice > 0 {
					b.summary.OfficialConsumerRSP = rec.RecommendedPrice
				}
				if b.summary.FactoryUnitCost <= 0 && rec.FactoryUnitCost > 0 {
					b.summary.FactoryUnitCost = rec.FactoryUnitCost
				}
				if b.summary.CartonPriceInclVAT <= 0 && rec.CartonPriceInclVAT > 0 {
					b.summary.CartonPriceInclVAT = rec.CartonPriceInclVAT
				}
				if b.summary.NetCartonInvoiceCost <= 0 && rec.NetCartonInvoiceCost > 0 {
					b.summary.NetCartonInvoiceCost = rec.NetCartonInvoiceCost
				}
				if b.summary.UnitsPerCarton <= 0 && rec.UnitsPerCarton > 0 {
					b.summary.UnitsPerCarton = rec.UnitsPerCarton
				}
			}
			b.summary.TotalUnitsSold += rec.QuantitySold
			b.summary.TotalCartonsSold += rec.CartonsSold
			b.summary.TotalNetRevenue += rec.NetRevenue
			b.summary.TotalFactoryCost += rec.TotalFactoryCost
			b.summary.RetailerGrossProfit += rec.RetailerGrossProfit
			if storeKey != "" {
				b.stores[storeKey] = true
			}
		}
	}

	skuSummaries := make([]domain.SellOutSKUSummary, 0, len(skuBuckets))
	for _, b := range skuBuckets {
		s := b.summary
		s.ActiveStoresCount = len(b.stores)
		finalizeSKUSummary(&s)
		skuSummaries = append(skuSummaries, s)
	}

	sort.Slice(skuSummaries, func(i, j int) bool {
		if skuSummaries[i].TotalNetRevenue != skuSummaries[j].TotalNetRevenue {
			return skuSummaries[i].TotalNetRevenue > skuSummaries[j].TotalNetRevenue
		}
		return skuSummaries[i].SKUName < skuSummaries[j].SKUName
	})

	avgMarginPct := 0.0
	if matchedRevForMargin > 0 {
		avgMarginPct = math.Round(((totalGrossProfit/matchedRevForMargin)*100)*100) / 100
	}

	topBranchName := ""
	topBranchRev := 0.0
	for k, rev := range branchRev {
		if rev > topBranchRev {
			topBranchRev = rev
			topBranchName = branchNames[k]
		}
	}

	pageRecords := make([]domain.SellOutFact, 0)
	if offset < len(allMatched) {
		end := offset + limit
		if end > len(allMatched) {
			end = len(allMatched)
		}
		pageRecords = allMatched[offset:end]
	}

	resp := PaginatedRecordsResponse{
		Records:                  pageRecords,
		TotalCount:               total,
		Limit:                    limit,
		Offset:                   offset,
		TotalNetRevenue:          math.Round(totalRev*100) / 100,
		TotalUnitsSold:           totalUnits,
		TotalCartonsSold:         math.Round(totalCartons*100) / 100,
		TotalFactoryCost:         math.Round(totalFactoryCost*100) / 100,
		TotalRetailerGrossProfit: math.Round(totalGrossProfit*100) / 100,
		AvgRetailerMarginPct:     avgMarginPct,
		ActiveStoresCount:        len(storesSet),
		ActiveSKUsCount:          len(skusSet),
		MatchedSKUsCount:         len(matchedSKUsSet),
		MinDate:                  minDate,
		MaxDate:                  maxDate,
		TopBranchName:            topBranchName,
		TopBranchRevenue:         math.Round(topBranchRev*100) / 100,
		SKUSummaries:             skuSummaries,
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
	searchQuery := strings.TrimSpace(q.Get("q"))
	if searchQuery == "" {
		searchQuery = strings.TrimSpace(q.Get("search"))
	}
	isPaginatedRequest := limitStr != "" || offsetStr != ""

	if !isPaginatedRequest {
		filter := bigquery.PricingComplianceFilter{
			RetailerChain: effectiveChain,
			Category:      q.Get("category"),
			SearchQuery:   searchQuery,
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
		if searchQuery != "" {
			if !domain.MatchesProductSearchQuery(searchQuery, item.ItemCode, item.Barcode, item.SKUName, "", item.Category, "") {
				continue
			}
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

// HandleGetProductMaster serves GET /api/v1/product-master to return the canonical Adeco Product Master & Price List.
func (h *AnalyticsHandler) HandleGetProductMaster(w http.ResponseWriter, r *http.Request) {
	tenantID, err := middleware.EnforceTenantRLS(r)
	if err != nil {
		http.Error(w, `{"error":"unauthorized tenant context"}`, http.StatusUnauthorized)
		return
	}

	q := r.URL.Query()
	prefix := strings.TrimSpace(q.Get("prefix"))
	if prefix == "" {
		prefix = strings.TrimSpace(q.Get("category"))
	}
	itemType := strings.TrimSpace(q.Get("item_type"))
	if itemType == "" {
		itemType = strings.TrimSpace(q.Get("type"))
	}
	searchQuery := strings.TrimSpace(q.Get("q"))
	if searchQuery == "" {
		searchQuery = strings.TrimSpace(q.Get("search"))
	}

	pullStatus := strings.TrimSpace(q.Get("pull_status"))
	if pullStatus == "" {
		pullStatus = strings.TrimSpace(q.Get("status"))
	}
	priceChange := strings.TrimSpace(q.Get("price_change"))

	summary, err := h.bqRepo.GetProductMaster(r.Context(), tenantID, bigquery.ProductMasterFilter{
		Prefix:        prefix,
		Brand:         strings.TrimSpace(q.Get("brand")),
		ItemType:      itemType,
		PackagingType: strings.TrimSpace(q.Get("packaging")),
		PullStatus:    pullStatus,
		PriceChange:   priceChange,
		SearchQuery:   searchQuery,
	})
	if err != nil {
		http.Error(w, `{"error":"failed to query product master"}`, http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(summary)
}

// HandleUpdateProductMasterItem serves PUT /api/v1/product-master/item to upsert a single SKU in the Product Master.
func (h *AnalyticsHandler) HandleUpdateProductMasterItem(w http.ResponseWriter, r *http.Request) {
	if _, ok := requireWriteRole(w, r, ingestWriteRoles); !ok {
		return
	}
	if r.Method != http.MethodPut && r.Method != http.MethodPost {
		http.Error(w, `{"error":"method not allowed"}`, http.StatusMethodNotAllowed)
		return
	}

	tenantID, err := middleware.EnforceTenantRLS(r)
	if err != nil {
		http.Error(w, `{"error":"unauthorized tenant context"}`, http.StatusUnauthorized)
		return
	}

	var item domain.ProductMasterItem
	if err := json.NewDecoder(r.Body).Decode(&item); err != nil {
		http.Error(w, `{"error":"invalid json payload"}`, http.StatusBadRequest)
		return
	}

	if _, err := h.bqRepo.UpsertProductMasterItem(r.Context(), tenantID, item); err != nil {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusBadRequest)
		_ = json.NewEncoder(w).Encode(map[string]string{
			"error":   "upsert_failed",
			"message": err.Error(),
		})
		return
	}

	summary, err := h.bqRepo.GetProductMaster(r.Context(), tenantID, bigquery.ProductMasterFilter{})
	if err != nil {
		http.Error(w, `{"error":"failed to reload product master"}`, http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(summary)
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
	searchQ := strings.TrimSpace(q.Get("q"))
	if searchQ == "" {
		searchQ = strings.TrimSpace(q.Get("search"))
	}

	filter := bigquery.CPFRFilter{
		RetailerChain:   chainParam,
		Year:            yearParam,
		Sector:          q.Get("sector"),
		RegionCode:      q.Get("region"),
		Brand:           q.Get("brand"),
		SalesRep:        q.Get("rep"),
		StockStatus:     q.Get("stock_status"),
		SearchQuery:     searchQ,
		LeadTimeDays:    leadTime,
		SafetyStockDays: safetyDays,
	}

	var payload *domain.CPFRDashboardPayload
	if cached, ok := h.bqRepo.(precomputedAnalytics); ok {
		// Served from the precomputed layer; recomputed only when a source changed.
		var version int64
		payload, version, err = cached.GetCPFRDashboardCached(r.Context(), tenantID, filter)
		w.Header().Set("X-Analytics-Version", strconv.FormatInt(version, 10))
	} else {
		payload, err = h.bqRepo.GetCPFRDashboard(r.Context(), tenantID, filter)
	}
	if err != nil {
		http.Error(w, `{"error":"failed to compute CPFR dashboard"}`, http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(payload)
}




// yearMonthRange turns ?year=&month= into an inclusive YYYY-MM-DD range (string-compared dates).
func yearMonthRange(yr, mo int) (string, string, bool) {
	if yr <= 0 {
		return "", "", false
	}
	if mo > 0 && mo <= 12 {
		return fmt.Sprintf("%04d-%02d-01", yr, mo), fmt.Sprintf("%04d-%02d-31", yr, mo), true
	}
	return fmt.Sprintf("%04d-01-01", yr), fmt.Sprintf("%04d-12-31", yr), true
}
