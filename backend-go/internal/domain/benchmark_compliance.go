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
	TenantID           string  `json:"tenant_id,omitempty"`
	ItemCode           string  `json:"item_code,omitempty"`
	SKUName            string  `json:"sku_name"`
	RetailerRawSKUName string  `json:"retailer_raw_sku_name,omitempty"`
	Barcode            string  `json:"barcode"`
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

// productCategoryAliases maps known retail spelling variants to their canonical category.
// Keys and values are whitespace-collapsed (see collapseCategoryWhitespace).
var productCategoryAliases = map[string]string{
	"صابون سائل للاطباق":      "صابون سائل اطباق",
	"صابون سائل للأطباق":      "صابون سائل اطباق",
	"سائل اطباق":              "صابون سائل اطباق",
	"سائل أطباق":              "صابون سائل اطباق",
	"كلور الوان":              "كلور ألوان",
	"كلور ألوان":              "كلور ألوان",
	"كلور عادي":               "كلور عادى",
	"كلور عادى":               "كلور عادى",
	"هاند ووش":                "هاند وواش",
	"هاند وواش":               "هاند وواش",
	"مطهرعام":                 "مطهر عام",
	"مطهر عام":                "مطهر عام",
	"منظف ارضيات":             "منظف ارضيات",
	"كلور ارضيات":             "منظف ارضيات",
	"صابون سائل للارضيات":     "منظف ارضيات",
	"صابون سائل للأرضيات":     "منظف ارضيات",
	"مطهر ارضيات":             "منظف ارضيات",
	"منظفات أرضيات وحوائط":    "منظف ارضيات",
	"منعمات ملابس عادية":      "منعمات ملابس",
	"منعمات ملابس مركزة":      "منعمات ملابس",
	"منعم ملابس":              "منعمات ملابس",
	"مسحوق جيل":               "مساحيق جيل اتوماتيك",
	"مساحيق جيل اوتوماتيك":    "مساحيق جيل اتوماتيك",
	"مساحيق جيل اتوماتيك":     "مساحيق جيل اتوماتيك",
	"مسحوق بودر غسالات اطباق": "مسحوق غسالات اطباق",
	"منظفات غسالات الاطباق":   "مسحوق غسالات اطباق",
	"مسحوق غسالات اطباق":      "مسحوق غسالات اطباق",
	"مسلكات احواض":            "مسلك احواض وبالوعات",
	"مسلك احواض":              "مسلك احواض وبالوعات",
	"مسلك احواض وبالوعات":     "مسلك احواض وبالوعات",
	"ملمع زجاج - نجف":         "ملمع زجاج وكريستال",
	"ملمع زجاج":               "ملمع زجاج وكريستال",
	"ملمع زجاج وكريستال":      "ملمع زجاج وكريستال",
	"ملمع اخشاب - باركيه":     "ملمع اخشاب وباركيه",
	"ملمع اخشاب وباركيه":      "ملمع اخشاب وباركيه",
	"منظفات مطابخ":            "منظفات مطبخ",
	"منظف مطبخ":              "منظفات مطبخ",
	"منظفات مطبخ":            "منظفات مطبخ",
	"منظفات سجاد":             "منظفات سجاد ومفروشات",
	"منظف سجاد":              "منظفات سجاد ومفروشات",
	"منظفات سجاد ومفروشات":   "منظفات سجاد ومفروشات",
	"مطهر تواليت":             "منظفات تواليت",
	"منظف تواليت":            "منظفات تواليت",
	"منظفات التواليت":         "منظفات تواليت",
	"منظفات تواليت":           "منظفات تواليت",
	"مزيلات بقع":              "مزيلات بقع ملابس",
	"مزيل بقع":               "مزيلات بقع ملابس",
	"مزيلات بقع ملابس":        "مزيلات بقع ملابس",
	"معطر جو سائل":            "معطر جو",
	"معطر جو":                "معطر جو",
	"شاور جل":                "شاور جيل",
	"شاور جيل":               "شاور جيل",
}

func collapseCategoryWhitespace(raw string) string {
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
	return clean
}

// NormalizeProductCategory canonicalizes product category names across different retail Excel sheets
// (e.g. unifying Fathalla and Gomla spelling variations so categories are cleanly deduplicated).
func NormalizeProductCategory(raw string) string {
	clean := collapseCategoryWhitespace(raw)
	if clean == "" {
		return ""
	}
	if canon, ok := productCategoryAliases[clean]; ok {
		return canon
	}
	return clean
}

// ProductCategoryMatchValues returns every known raw spelling (plus the canonical form) that
// NormalizeProductCategory maps to the same target as raw. Used by BigQuery IN UNNEST filters.
func ProductCategoryMatchValues(raw string) []string {
	target := NormalizeProductCategory(raw)
	if target == "" {
		return nil
	}
	seen := map[string]struct{}{target: {}}
	out := []string{target}
	for alias, canon := range productCategoryAliases {
		if canon != target {
			continue
		}
		if _, ok := seen[alias]; ok {
			continue
		}
		seen[alias] = struct{}{}
		out = append(out, alias)
	}
	return out
}

