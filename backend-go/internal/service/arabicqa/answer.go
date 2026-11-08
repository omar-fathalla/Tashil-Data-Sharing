package arabicqa

import (
	"fmt"
	"strings"

	"github.com/tashil/data-sharing/backend/internal/domain"
)

func answerExecutive(kpis *domain.ExecutiveKPIs, period string) (string, map[string]interface{}) {
	if kpis == nil {
		return "مفيش بيانات أداء متاحة للمستأجر ده في الفترة المطلوبة.", map[string]interface{}{"period": period, "claims": []Claim{}}
	}
	claims := []Claim{
		{Metric: "total_revenue", Entity: "tenant", Value: kpis.TotalRevenue, Display: claimDisplayEGP(kpis.TotalRevenue)},
		{Metric: "total_units_sold", Entity: "tenant", Value: float64(kpis.TotalUnitsSold), Display: claimDisplayInt(float64(kpis.TotalUnitsSold))},
		{Metric: "active_stores_count", Entity: "tenant", Value: float64(kpis.ActiveStoresCount), Display: claimDisplayInt(float64(kpis.ActiveStoresCount))},
		{Metric: "tenant_market_share_pct", Entity: "tenant", Value: kpis.TenantMarketSharePct, Display: claimDisplayPct(kpis.TenantMarketSharePct)},
		{Metric: "revenue_mom_pct", Entity: "tenant", Value: kpis.RevenueMoMPct, Display: claimDisplayPct(kpis.RevenueMoMPct)},
	}
	text := narrativeFromClaims(period, "ملخص الأداء", claims)
	return text, claimsToEvidence(period, claims, map[string]interface{}{
		"currency": nonzero(kpis.Currency, "EGP"),
	})
}

func answerChainShares(shares []domain.ChainShareSummary, period string) (string, map[string]interface{}) {
	if len(shares) == 0 {
		return "مفيش حصص سلاسل متاحة للمستأجر ده في الفترة دي.", map[string]interface{}{"period": period, "claims": []Claim{}}
	}
	limit := len(shares)
	if limit > 5 {
		limit = 5
	}
	claims := make([]Claim, 0, limit)
	list := make([]map[string]interface{}, 0, limit)
	for i := 0; i < limit; i++ {
		s := shares[i]
		name := s.DisplayName
		if name == "" {
			name = s.RetailerChain
		}
		entity := "chain:" + name
		claims = append(claims, Claim{
			Metric: "total_revenue", Entity: entity, Value: s.TotalRevenue, Display: claimDisplayEGP(s.TotalRevenue),
		})
		claims = append(claims, Claim{
			Metric: "total_units", Entity: entity, Value: float64(s.TotalUnits), Display: claimDisplayInt(float64(s.TotalUnits)),
		})
		list = append(list, map[string]interface{}{
			"retailer_chain": s.RetailerChain,
			"display_name":   name,
			"total_revenue":  s.TotalRevenue,
			"total_units":    s.TotalUnits,
		})
	}
	topName := shares[0].DisplayName
	if topName == "" {
		topName = shares[0].RetailerChain
	}
	text := narrativeFromClaims(period, "حصص السلاسل — أكبر سلسلة «"+topName+"»", claims)
	return text, claimsToEvidence(period, claims, map[string]interface{}{
		"chains":    list,
		"top_chain": topName,
	})
}

func answerTopSKUs(kpis *domain.ExecutiveKPIs, period string) (string, map[string]interface{}) {
	if kpis == nil || len(kpis.ParetoSKUs) == 0 {
		return "مفيش قائمة منتجات (باريتو) متاحة للمستأجر ده.", map[string]interface{}{"period": period, "claims": []Claim{}}
	}
	limit := len(kpis.ParetoSKUs)
	if limit > 5 {
		limit = 5
	}
	claims := make([]Claim, 0, limit)
	list := make([]map[string]interface{}, 0, limit)
	for i := 0; i < limit; i++ {
		sku := kpis.ParetoSKUs[i]
		entity := "sku:" + sku.SKUName
		claims = append(claims, Claim{
			Metric: "total_revenue", Entity: entity, Value: sku.TotalRevenue, Display: claimDisplayEGP(sku.TotalRevenue),
		})
		list = append(list, map[string]interface{}{
			"sku_name":      sku.SKUName,
			"barcode":       sku.Barcode,
			"total_revenue": sku.TotalRevenue,
			"total_units":   sku.TotalUnits,
		})
	}
	text := narrativeFromClaims(period, "أعلى المنتجات", claims)
	return text, claimsToEvidence(period, claims, map[string]interface{}{"top_skus": list})
}

func answerCategories(kpis *domain.ExecutiveKPIs, period string) (string, map[string]interface{}) {
	if kpis == nil || len(kpis.CategoryContributions) == 0 {
		return "مفيش مساهمات فئات متاحة للمستأجر ده.", map[string]interface{}{"period": period, "claims": []Claim{}}
	}
	limit := len(kpis.CategoryContributions)
	if limit > 5 {
		limit = 5
	}
	claims := make([]Claim, 0, limit*2)
	list := make([]map[string]interface{}, 0, limit)
	for i := 0; i < limit; i++ {
		c := kpis.CategoryContributions[i]
		entity := "category:" + c.Category
		claims = append(claims,
			Claim{Metric: "total_revenue", Entity: entity, Value: c.TotalRevenue, Display: claimDisplayEGP(c.TotalRevenue)},
			Claim{Metric: "share_pct", Entity: entity, Value: c.SharePct, Display: claimDisplayPct(c.SharePct)},
		)
		list = append(list, map[string]interface{}{
			"category":      c.Category,
			"total_revenue": c.TotalRevenue,
			"share_pct":     c.SharePct,
		})
	}
	text := narrativeFromClaims(period, "مساهمة الفئات", claims)
	return text, claimsToEvidence(period, claims, map[string]interface{}{"categories": list})
}

func answerSellIn(totalRev float64, totalUnits float64, count int, period string) (string, map[string]interface{}) {
	claims := []Claim{
		{Metric: "record_count", Entity: "tenant", Value: float64(count), Display: claimDisplayInt(float64(count))},
		{Metric: "total_net_value", Entity: "tenant", Value: totalRev, Display: claimDisplayEGP(totalRev)},
		{Metric: "total_units", Entity: "tenant", Value: totalUnits, Display: claimDisplayInt(totalUnits)},
	}
	if count == 0 {
		return "مفيش سجلات توريد (Sell-In) للمستأجر ده.", claimsToEvidence(period, claims, nil)
	}
	text := narrativeFromClaims(period, "ملخص التوريد Sell-In", claims)
	return text, claimsToEvidence(period, claims, nil)
}

func unsupportedAnswer() (string, map[string]interface{}) {
	caps := Capabilities()
	var titles []string
	for _, c := range caps {
		titles = append(titles, c.TitleAR)
	}
	text := fmt.Sprintf(
		"السؤال ده مش ضمن الأسئلة المسموحة حاليًا. تقدر تسأل عن: %s. الخدمة قراءة فقط وما بتنفّذش أوامر تعديل ولا SQL حر.",
		strings.Join(titles, "، "),
	)
	return text, map[string]interface{}{"allowed_intents": titles, "claims": []Claim{}}
}

func unsupportedTodaySellIn() (string, map[string]interface{}) {
	text := "سؤال «اليوم» مش مدعوم لملخص التوريد (Sell-In) لأن البيانات شهرية مش يومية. اسأل عن الشهر الحالي (MTD) أو كل البيانات."
	return text, map[string]interface{}{
		"period":    "TODAY",
		"reason":    "sell_in_no_day_grain",
		"claims":    []Claim{},
		"supported": []string{"MTD", "YTD", "ALL"},
	}
}

func periodLabel(period string) string {
	switch strings.ToUpper(strings.TrimSpace(period)) {
	case "TODAY":
		return "اليوم"
	case "YTD":
		return "من أول السنة"
	case "ALL":
		return "كل البيانات"
	default:
		return "الشهر الحالي (MTD)"
	}
}

func nonzero(s, fallback string) string {
	if strings.TrimSpace(s) == "" {
		return fallback
	}
	return s
}
