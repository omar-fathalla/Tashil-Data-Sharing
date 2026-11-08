package arabicqa

import (
	"fmt"
	"strings"

	"github.com/tashil/data-sharing/backend/internal/domain"
)

func formatEGP(v float64) string {
	return fmt.Sprintf("%.2f ج.م", v)
}

func formatPct(v float64) string {
	return fmt.Sprintf("%.1f%%", v)
}

func answerExecutive(kpis *domain.ExecutiveKPIs, period string) (string, map[string]interface{}) {
	if kpis == nil {
		return "مفيش بيانات أداء متاحة للمستأجر ده في الفترة المطلوبة.", map[string]interface{}{}
	}
	ev := map[string]interface{}{
		"total_revenue":         kpis.TotalRevenue,
		"total_units_sold":      kpis.TotalUnitsSold,
		"active_stores_count":   kpis.ActiveStoresCount,
		"tenant_market_share_pct": kpis.TenantMarketSharePct,
		"revenue_mom_pct":       kpis.RevenueMoMPct,
		"period":                period,
		"currency":              nonzero(kpis.Currency, "EGP"),
	}
	text := fmt.Sprintf(
		"ملخص الأداء (فترة %s): إجمالي الإيراد %s، الوحدات المباعة %d، المتاجر النشطة %d، حصة السوق %s، نمو الإيراد شهريًا %s. الإجابة مبنية على بيانات BigQuery للمستأجر فقط (قراءة فقط).",
		periodLabel(period),
		formatEGP(kpis.TotalRevenue),
		kpis.TotalUnitsSold,
		kpis.ActiveStoresCount,
		formatPct(kpis.TenantMarketSharePct),
		formatPct(kpis.RevenueMoMPct),
	)
	return text, ev
}

func answerChainShares(shares []domain.ChainShareSummary, period string) (string, map[string]interface{}) {
	if len(shares) == 0 {
		return "مفيش حصص سلاسل متاحة للمستأجر ده في الفترة دي.", map[string]interface{}{"period": period, "chains": []interface{}{}}
	}
	top := shares[0]
	var parts []string
	list := make([]map[string]interface{}, 0, len(shares))
	limit := len(shares)
	if limit > 5 {
		limit = 5
	}
	for i := 0; i < limit; i++ {
		s := shares[i]
		name := s.DisplayName
		if name == "" {
			name = s.RetailerChain
		}
		parts = append(parts, fmt.Sprintf("%s: %s", name, formatEGP(s.TotalRevenue)))
		list = append(list, map[string]interface{}{
			"retailer_chain": s.RetailerChain,
			"display_name":   name,
			"total_revenue":  s.TotalRevenue,
			"total_units":    s.TotalUnits,
		})
	}
	topName := top.DisplayName
	if topName == "" {
		topName = top.RetailerChain
	}
	text := fmt.Sprintf(
		"حصص السلاسل (فترة %s): أكبر سلسلة هي «%s» بإيراد %s. أعلى السلاسل: %s. قراءة فقط من بيانات المستأجر.",
		periodLabel(period), topName, formatEGP(top.TotalRevenue), strings.Join(parts, "؛ "),
	)
	return text, map[string]interface{}{"period": period, "chains": list, "top_chain": topName}
}

func answerTopSKUs(kpis *domain.ExecutiveKPIs, period string) (string, map[string]interface{}) {
	if kpis == nil || len(kpis.ParetoSKUs) == 0 {
		return "مفيش قائمة منتجات (باريتو) متاحة للمستأجر ده.", map[string]interface{}{"period": period}
	}
	limit := len(kpis.ParetoSKUs)
	if limit > 5 {
		limit = 5
	}
	var parts []string
	list := make([]map[string]interface{}, 0, limit)
	for i := 0; i < limit; i++ {
		sku := kpis.ParetoSKUs[i]
		parts = append(parts, fmt.Sprintf("%s (%s)", sku.SKUName, formatEGP(sku.TotalRevenue)))
		list = append(list, map[string]interface{}{
			"sku_name":       sku.SKUName,
			"barcode":        sku.Barcode,
			"total_revenue":  sku.TotalRevenue,
			"total_units":    sku.TotalUnits,
		})
	}
	text := fmt.Sprintf(
		"أعلى المنتجات (فترة %s): %s. الأرقام من بيانات BigQuery للمستأجر (قراءة فقط).",
		periodLabel(period), strings.Join(parts, "؛ "),
	)
	return text, map[string]interface{}{"period": period, "top_skus": list}
}

func answerCategories(kpis *domain.ExecutiveKPIs, period string) (string, map[string]interface{}) {
	if kpis == nil || len(kpis.CategoryContributions) == 0 {
		return "مفيش مساهمات فئات متاحة للمستأجر ده.", map[string]interface{}{"period": period}
	}
	limit := len(kpis.CategoryContributions)
	if limit > 5 {
		limit = 5
	}
	var parts []string
	list := make([]map[string]interface{}, 0, limit)
	for i := 0; i < limit; i++ {
		c := kpis.CategoryContributions[i]
		parts = append(parts, fmt.Sprintf("%s: %s (%s)", c.Category, formatEGP(c.TotalRevenue), formatPct(c.SharePct)))
		list = append(list, map[string]interface{}{
			"category":      c.Category,
			"total_revenue": c.TotalRevenue,
			"share_pct":     c.SharePct,
		})
	}
	text := fmt.Sprintf(
		"مساهمة الفئات (فترة %s): %s. قراءة فقط من بيانات المستأجر.",
		periodLabel(period), strings.Join(parts, "؛ "),
	)
	return text, map[string]interface{}{"period": period, "categories": list}
}

func answerSellIn(totalRev float64, totalUnits float64, count int, period string) (string, map[string]interface{}) {
	ev := map[string]interface{}{
		"period":           period,
		"record_count":     count,
		"total_net_value":  totalRev,
		"total_units":      totalUnits,
	}
	if count == 0 {
		return "مفيش سجلات توريد (Sell-In) للمستأجر ده.", ev
	}
	text := fmt.Sprintf(
		"ملخص التوريد Sell-In (فترة %s): عدد السجلات %d، إجمالي القيمة %s، إجمالي الوحدات %.0f. قراءة فقط من بيانات المستأجر في BigQuery.",
		periodLabel(period), count, formatEGP(totalRev), totalUnits,
	)
	return text, ev
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
	return text, map[string]interface{}{"allowed_intents": titles}
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
