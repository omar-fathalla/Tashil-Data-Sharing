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
	Category           string  `json:"category"`
	RetailerChain      string  `json:"retailer_chain"`
	StoreName          string  `json:"store_name"`
	ActualPrice        float64 `json:"actual_price"`
	RecommendedPrice   float64 `json:"recommended_price"` // RRP
	FactoryUnitCost    float64 `json:"factory_unit_cost,omitempty"`
	RetailerMarginPct  float64 `json:"retailer_margin_pct,omitempty"`
	UnitsPerCarton     int     `json:"units_per_carton,omitempty"`
	ItemType           string  `json:"item_type,omitempty"`
	PriceDeltaPct      float64 `json:"price_delta_pct"`
	ViolationType      string  `json:"violation_type"` // 'compliant', 'under_cutting', 'price_gouging'
	IsPromoActive      bool    `json:"is_promo_active"`
	PromoUpliftPct     float64 `json:"promo_uplift_pct"`
	TransactionDate    string  `json:"transaction_date,omitempty"`
}

// MonthlyPriceElasticityPoint represents monthly average price vs. revenue and volume performance.
type MonthlyPriceElasticityPoint struct {
	MonthKey          string  `json:"month_key"`          // e.g. "2026-01"
	MonthLabel        string  `json:"month_label"`        // e.g. "يناير 2026"
	AveragePrice      float64 `json:"average_price"`      // Average actual selling price in EGP
	RecommendedPrice  float64 `json:"recommended_price"`  // Average RRP in EGP
	TotalRevenue      float64 `json:"total_revenue"`      // Total sales revenue in EGP
	TotalUnits        int     `json:"total_units"`        // Total units sold
	PriceChangePct    float64 `json:"price_change_pct"`   // MoM price change %
	RevenueChangePct  float64 `json:"revenue_change_pct"` // MoM revenue change %
	UnitsChangePct    float64 `json:"units_change_pct"`   // MoM volume change %
	ElasticityVerdict string  `json:"elasticity_verdict"` // Strategic analytical verdict
}

// PriceElasticitySummary provides an executive overview of the price-to-revenue correlation.
type PriceElasticitySummary struct {
	OverallVerdict      string  `json:"overall_verdict"`
	AvgPriceCurrent     float64 `json:"avg_price_current"`
	AvgPriceBaseline    float64 `json:"avg_price_baseline"`
	NetPriceChangePct   float64 `json:"net_price_change_pct"`
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

// spellingCategoryAliases restores a preferred sheet spelling after hamza/yeh
// folding. Keys are already folded (bare alef, alef maqsura). Values differ
// only by hamza or a missing space — never by category type, singular/plural,
// or an added or dropped word.
//
// ة/ه is not folded: no existing alias used that pair.
var spellingCategoryAliases = map[string]string{
	"كلور الوان": "كلور ألوان",
	"مطهرعام":    "مطهر عام",
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

// foldCategorySpelling applies spelling-only folds: hamza seats (أ إ آ ٱ → ا)
// and a word-final yeh (ي → ى). It does not insert or drop words.
func foldCategorySpelling(s string) string {
	rs := []rune(s)
	for i, r := range rs {
		switch r {
		case 'أ', 'إ', 'آ', 'ٱ':
			rs[i] = 'ا'
		}
	}
	for i, r := range rs {
		if r == 'ي' && (i == len(rs)-1 || rs[i+1] == ' ') {
			rs[i] = 'ى'
		}
	}
	return string(rs)
}

// NormalizeProductCategory canonicalizes spelling only (whitespace, hamza, ى/ي,
// and the missing-space aliases above). Different category names stay different,
// including across chains. Singular/plural wording is not merged.
func NormalizeProductCategory(raw string) string {
	clean := collapseCategoryWhitespace(raw)
	if clean == "" {
		return ""
	}
	folded := foldCategorySpelling(clean)
	if canon, ok := spellingCategoryAliases[folded]; ok {
		return canon
	}
	return folded
}

// ProductCategoryMatchValues returns spellings that normalize to the same category
// as raw (canonical form, alias keys, and hamza / ى-ي preimages). Used by BigQuery
// IN UNNEST filters. It does not include a different category name.
func ProductCategoryMatchValues(raw string) []string {
	target := NormalizeProductCategory(raw)
	if target == "" {
		return nil
	}
	seen := map[string]struct{}{}
	var out []string
	add := func(s string) {
		s = collapseCategoryWhitespace(s)
		if s == "" {
			return
		}
		if _, ok := seen[s]; ok {
			return
		}
		if NormalizeProductCategory(s) != target {
			return
		}
		seen[s] = struct{}{}
		out = append(out, s)
	}
	add(target)
	add(raw)
	for alias, canon := range spellingCategoryAliases {
		if canon == target || NormalizeProductCategory(alias) == target {
			add(alias)
		}
	}
	for _, v := range spellingPreimages(target) {
		add(v)
	}
	return out
}

// spellingPreimages lists single-step hamza and word-final yeh variants of s.
// Each result is checked by the caller against NormalizeProductCategory.
func spellingPreimages(s string) []string {
	var out []string
	seen := map[string]bool{s: true}
	cur := []string{s}
	type swap struct{ a, b rune }
	swaps := []swap{{'ا', 'أ'}, {'إ', 'ا'}, {'آ', 'ا'}, {'ى', 'ي'}}
	for _, sw := range swaps {
		var next []string
		for _, item := range cur {
			rs := []rune(item)
			for i, r := range rs {
				if r != sw.a && r != sw.b {
					continue
				}
				if (sw.a == 'ى' || sw.b == 'ي') && !(i == len(rs)-1 || (i+1 < len(rs) && rs[i+1] == ' ')) {
					continue
				}
				cp := append([]rune(nil), rs...)
				if r == sw.a {
					cp[i] = sw.b
				} else {
					cp[i] = sw.a
				}
				v := string(cp)
				if seen[v] {
					continue
				}
				seen[v] = true
				next = append(next, v)
				out = append(out, v)
			}
		}
		cur = append(cur, next...)
	}
	return out
}
