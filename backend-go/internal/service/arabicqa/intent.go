package arabicqa

import (
	"strings"
	"unicode"
)

// classifyIntent maps an Arabic (or mixed) question to an allowlisted intent.
// Keyword matching only — never trusts the model to invent query plans.
func classifyIntent(question string) Intent {
	q := normalizeQuestion(question)
	if q == "" {
		return IntentUnsupported
	}
	// Destructive / write-shaped asks are never answered as analytics.
	for _, bad := range []string{
		"احذف", "امسح", "امسحي", "حذف", "مسح", "عدل", "عدّل", "حدث", "حدّث",
		"اكتب", "insert", "update", "delete", "drop", "truncate", "write",
	} {
		if strings.Contains(q, bad) {
			return IntentUnsupported
		}
	}

	type rule struct {
		intent Intent
		need   []string // any match
	}
	rules := []rule{
		{IntentSellIn, []string{
			"سيل ان", "سيل-ان", "sell in", "sell-in", "sellin",
			"توريد", "التوريد", "مبيعات التوريد", "خطه التوريد",
		}},
		{IntentChainShares, []string{
			"حصه السلسل", "حصص السلسل", "توزيع السلسل", "حصه كل سلسل",
			"اكبر سلسل", "افضل سلسل", "سلسله", "سلاسل",
			"chain share", "chain shares",
		}},
		{IntentTopSKUs, []string{
			"افضل منتج", "اعلى منتج", "افضل منتجات", "اعلى منتجات",
			"منتجات مبيع", "افضل sku", "اعلى sku", "pareto", "باريتو",
			"اعلى مبيعات منتج", "اكثر منتج", "top sku", "top product",
		}},
		{IntentCategories, []string{
			"فئه", "فئات", "تصنيف", "تصنيفات", "category", "categories",
			"مساهمه الفئه", "حصه الفئه", "مساهمه كل فئه",
		}},
		{IntentExecutiveKPIs, []string{
			"ايراد", "ايرادات", "مبيعات", "المبيعات",
			"اجمالي", "وحدات", "الوحدات", "متجر", "المتاجر",
			"حصه السوق", "نمو", "kpi", "ملخص", "خلاصه", "اداء",
			"executive", "revenue", "units",
		}},
	}

	for _, r := range rules {
		for _, needle := range r.need {
			if strings.Contains(q, normalizeQuestion(needle)) {
				return r.intent
			}
		}
	}
	return IntentUnsupported
}

// detectPeriod extracts a reporting period hint from the question.
func detectPeriod(question string) string {
	q := normalizeQuestion(question)
	switch {
	case strings.Contains(q, "اليوم") || strings.Contains(q, "today"):
		return "TODAY"
	case strings.Contains(q, "الكل") || strings.Contains(q, "كل الفتر") ||
		strings.Contains(q, "all time") || strings.Contains(q, "كل البيانات"):
		return "ALL"
	case strings.Contains(q, "ytd") || strings.Contains(q, "من اول السنه") ||
		strings.Contains(q, "من أول السنة") || strings.Contains(q, "خلال السنه") ||
		strings.Contains(q, "خلال السنة"):
		return "YTD"
	default:
		return "MTD"
	}
}

func normalizeQuestion(s string) string {
	s = strings.TrimSpace(strings.ToLower(s))
	if s == "" {
		return ""
	}
	var b strings.Builder
	b.Grow(len(s))
	for _, r := range s {
		// Strip Arabic tashkeel / tatweel so «مبيعًا» matches «مبيعا».
		if r == '\u0640' || (r >= '\u064B' && r <= '\u065F') || r == '\u0670' {
			continue
		}
		switch r {
		case 'أ', 'إ', 'آ':
			b.WriteRune('ا')
		case 'ة':
			b.WriteRune('ه')
		case 'ى':
			b.WriteRune('ي')
		default:
			if unicode.IsSpace(r) {
				b.WriteRune(' ')
			} else {
				b.WriteRune(r)
			}
		}
	}
	return strings.Join(strings.Fields(b.String()), " ")
}

// Capabilities returns the allowlisted Arabic question families.
func Capabilities() []Capability {
	return []Capability{
		{
			Intent:      IntentExecutiveKPIs,
			TitleAR:     "ملخص الأداء والإيرادات",
			ExamplesAR:  []string{"كام إجمالي المبيعات الشهر ده؟", "إيه عدد الوحدات المباعة؟"},
			DataSources: []string{"bigquery.executive_kpis"},
		},
		{
			Intent:      IntentChainShares,
			TitleAR:     "حصص السلاسل",
			ExamplesAR:  []string{"إيه أكبر سلسلة في المبيعات؟", "وزّع حصص السلاسل"},
			DataSources: []string{"bigquery.chain_shares"},
		},
		{
			Intent:      IntentTopSKUs,
			TitleAR:     "أفضل المنتجات",
			ExamplesAR:  []string{"إيه أعلى منتجات مبيعًا؟", "ورّيني باريتو المنتجات"},
			DataSources: []string{"bigquery.pareto_skus"},
		},
		{
			Intent:      IntentCategories,
			TitleAR:     "مساهمة الفئات",
			ExamplesAR:  []string{"إيه مساهمة كل فئة؟", "أعلى تصنيف في الإيراد"},
			DataSources: []string{"bigquery.category_contributions"},
		},
		{
			Intent:      IntentSellIn,
			TitleAR:     "ملخص التوريد (Sell-In)",
			ExamplesAR:  []string{"كام إجمالي التوريد؟", "ملخص سيل إن"},
			DataSources: []string{"bigquery.sell_in_records"},
		},
	}
}
