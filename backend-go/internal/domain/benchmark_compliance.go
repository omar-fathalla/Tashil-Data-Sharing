package domain

import "math"

// StoreBenchmarkItem represents comparative matrix benchmarking for a retail branch.
type StoreBenchmarkItem struct {
	StoreID             string  `json:"store_id"`
	StoreName           string  `json:"store_name"`
	RetailerChain       string  `json:"retailer_chain"`
	Region              string  `json:"region"` // شرق الإسكندرية, غرب الإسكندرية, القاهرة الكبرى
	Tier                string  `json:"tier"`   // 'Tier A', 'Tier B', 'Tier C'
	TotalRevenue        float64 `json:"total_revenue"`
	TotalUnits          int     `json:"total_units"`
	VelocityUnitsPerDay float64 `json:"velocity_units_per_day"`
	Rank                int     `json:"rank"`
}

// PricingComplianceItem represents SKU-level price monitoring and promotional uplift.
type PricingComplianceItem struct {
	TenantID          string  `json:"tenant_id,omitempty"`
	ItemCode          string  `json:"item_code,omitempty"`
	SKUName           string  `json:"sku_name"`
	Barcode           string  `json:"barcode"`
	Category          string  `json:"category"`
	RetailerChain     string  `json:"retailer_chain"`
	StoreName         string  `json:"store_name"`
	ActualPrice       float64 `json:"actual_price"`
	RecommendedPrice  float64 `json:"recommended_price"` // RRP
	FactoryUnitCost   float64 `json:"factory_unit_cost,omitempty"`
	RetailerMarginPct float64 `json:"retailer_margin_pct,omitempty"`
	UnitsPerCarton    int     `json:"units_per_carton,omitempty"`
	ItemType          string  `json:"item_type,omitempty"`
	PriceDeltaPct     float64 `json:"price_delta_pct"`
	ViolationType     string  `json:"violation_type"` // 'compliant', 'under_cutting', 'price_gouging'
	IsPromoActive     bool    `json:"is_promo_active"`
	PromoUpliftPct    float64 `json:"promo_uplift_pct"`
	TransactionDate   string  `json:"transaction_date,omitempty"`
}

// MonthlyPriceElasticityPoint represents monthly average price vs. revenue and volume performance.
type MonthlyPriceElasticityPoint struct {
	MonthKey         string  `json:"month_key"`          // e.g. "2026-01"
	MonthLabel       string  `json:"month_label"`        // e.g. "يناير 2026"
	AveragePrice     float64 `json:"average_price"`      // Average actual selling price in EGP
	RecommendedPrice float64 `json:"recommended_price"`  // Average RRP in EGP
	TotalRevenue     float64 `json:"total_revenue"`      // Total sales revenue in EGP
	TotalUnits       int     `json:"total_units"`        // Total units sold
	PriceChangePct   float64 `json:"price_change_pct"`   // MoM price change %
	RevenueChangePct float64 `json:"revenue_change_pct"` // MoM revenue change %
	UnitsChangePct   float64 `json:"units_change_pct"`   // MoM volume change %
	ElasticityVerdict string `json:"elasticity_verdict"` // Strategic analytical verdict
}

// PriceElasticitySummary provides an executive overview of the price-to-revenue correlation.
type PriceElasticitySummary struct {
	OverallVerdict     string  `json:"overall_verdict"`
	AvgPriceCurrent    float64 `json:"avg_price_current"`
	AvgPriceBaseline   float64 `json:"avg_price_baseline"`
	NetPriceChangePct  float64 `json:"net_price_change_pct"`
	NetRevenueGrowthPct float64 `json:"net_revenue_growth_pct"`
}

// DetermineStoreTier classifies a store into Tier A, Tier B, or Tier C based on revenue.
func DetermineStoreTier(revenue float64) string {
	if revenue >= 600000.0 {
		return "Tier A"
	} else if revenue >= 300000.0 {
		return "Tier B"
	}
	return "Tier C"
}

// CalculatePriceDeltaPct calculates the percentage deviation from recommended retail price (RRP).
func CalculatePriceDeltaPct(actualPrice, recommendedPrice float64) float64 {
	if recommendedPrice <= 0 {
		return 0
	}
	delta := ((actualPrice - recommendedPrice) / recommendedPrice) * 100.0
	return math.Round(delta*10) / 10
}

// ClassifyPriceViolation determines if the actual price complies with RRP within tolerance (±2.0%).
func ClassifyPriceViolation(deltaPct float64) string {
	if deltaPct < -2.0 {
		return "under_cutting"
	} else if deltaPct > 2.0 {
		return "price_gouging"
	}
	return "compliant"
}

// CalculatePromoUpliftPct computes the promotional volume uplift relative to baseline sales.
func CalculatePromoUpliftPct(promoQty, baselineQty int) float64 {
	if baselineQty <= 0 {
		return 0
	}
	uplift := (float64(promoQty-baselineQty) / float64(baselineQty)) * 100.0
	return math.Round(uplift*10) / 10
}

// NormalizeProductCategory canonicalizes product category names across different retail Excel sheets
// (e.g. unifying Fathalla and Gomla spelling variations so categories are cleanly deduplicated).
func NormalizeProductCategory(raw string) string {
	// Trim spaces
	clean := ""
	inSpace := false
	for _, r := range raw {
		if r == ' ' || r == '\t' || r == '\n' || r == '\r' {
			if clean != "" && !inSpace {
				clean += " "
				inSpace = true
			}
			continue
		}
		clean += string(r)
		inSpace = false
	}
	if len(clean) > 0 && clean[len(clean)-1] == ' ' {
		clean = clean[:len(clean)-1]
	}
	if clean == "" {
		return ""
	}

	switch clean {
	case "صابون سائل للاطباق", "صابون سائل للأطباق", "سائل اطباق", "سائل أطباق":
		return "صابون سائل اطباق"
	case "كلور الوان", "كلور ألوان":
		return "كلور ألوان"
	case "كلور عادي", "كلور عادى":
		return "كلور عادى"
	case "هاند ووش", "هاند وواش":
		return "هاند وواش"
	case "مطهرعام", "مطهر عام":
		return "مطهر عام"
	case "منظف ارضيات", "كلور ارضيات", "صابون سائل للارضيات", "صابون سائل للأرضيات", "مطهر ارضيات", "منظفات أرضيات وحوائط":
		return "منظف ارضيات"
	case "منعمات ملابس عادية", "منعمات ملابس مركزة", "منعم ملابس":
		return "منعمات ملابس"
	case "مسحوق جيل", "مساحيق جيل اوتوماتيك", "مساحيق جيل اتوماتيك":
		return "مساحيق جيل اتوماتيك"
	case "مسحوق بودر غسالات اطباق", "منظفات غسالات الاطباق", "مسحوق غسالات اطباق":
		return "مسحوق غسالات اطباق"
	case "مسلكات احواض", "مسلك احواض", "مسلك احواض وبالوعات":
		return "مسلك احواض وبالوعات"
	case "ملمع زجاج - نجف", "ملمع زجاج", "ملمع زجاج وكريستال":
		return "ملمع زجاج وكريستال"
	case "ملمع اخشاب - باركيه", "ملمع اخشاب وباركيه":
		return "ملمع اخشاب وباركيه"
	case "منظفات مطابخ", "منظف مطبخ", "منظفات مطبخ":
		return "منظفات مطبخ"
	case "منظفات سجاد", "منظف سجاد", "منظفات سجاد ومفروشات":
		return "منظفات سجاد ومفروشات"
	case "مطهر تواليت", "منظف تواليت", "منظفات التواليت", "منظفات تواليت":
		return "منظفات تواليت"
	case "مزيلات بقع", "مزيل بقع", "مزيلات بقع ملابس":
		return "مزيلات بقع ملابس"
	case "معطر جو سائل", "معطر جو":
		return "معطر جو"
	case "شاور جل", "شاور جيل":
		return "شاور جيل"
	default:
		return clean
	}
}

