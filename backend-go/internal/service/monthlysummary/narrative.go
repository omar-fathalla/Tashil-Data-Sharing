package monthlysummary

import (
	"fmt"
	"strconv"
	"strings"

	"github.com/tashil/data-sharing/backend/internal/domain"
)

// DeterministicNarrateAR builds an Arabic summary that quotes only agg figures.
func DeterministicNarrateAR(agg domain.MonthlySummaryAggregates) string {
	if agg.TotalRevenue == 0 && agg.TotalUnits == 0 && len(agg.TopChains) == 0 {
		return "ملخص شهري: لا تتوفر أرقام مبيعات محسوبة لهذه الفترة في اللوحة التنفيذية؛ لم تُختلق أي قيم."
	}

	var b strings.Builder
	b.WriteString("ملخص شهري (مبني حصراً على أرقام اللوحة التنفيذية المحسوبة): ")

	periodLabel := agg.Period
	if agg.CurrentMonthKey != "" {
		periodLabel = agg.CurrentMonthKey
	}
	b.WriteString(fmt.Sprintf(
		"إجمالي المبيعات %.0f %s خلال %s، والوحدات %d، عبر %d فرع/نقطة بيع نشطة.",
		agg.TotalRevenue, agg.Currency, periodLabel, agg.TotalUnits, agg.ActiveStores,
	))

	if agg.PriorMonthKey != "" && agg.PriorMonthRevenue > 0 {
		b.WriteString(fmt.Sprintf(
			" مقارنةً بـ %s (%.0f %s) يبلغ التغير الشهري في الإيراد %+.1f%% والوحدات %+.1f%%.",
			agg.PriorMonthKey, agg.PriorMonthRevenue, agg.Currency, agg.RevenueMoMPct, agg.UnitsMoMPct,
		))
	} else if agg.RevenueMoMPct != 0 || agg.UnitsMoMPct != 0 {
		b.WriteString(fmt.Sprintf(
			" التغير الشهري (MoM): إيراد %+.1f%% ووحدات %+.1f%%.",
			agg.RevenueMoMPct, agg.UnitsMoMPct,
		))
	}

	if agg.MarketSharePct > 0 {
		b.WriteString(fmt.Sprintf(" الحصة السوقية للمستأجر %.1f%%.", agg.MarketSharePct))
	}
	if agg.RevenueYoYPct != 0 {
		b.WriteString(fmt.Sprintf(" التغير السنوي للإيراد %+.1f%%.", agg.RevenueYoYPct))
	}

	if len(agg.TopChains) > 0 {
		c := agg.TopChains[0]
		b.WriteString(fmt.Sprintf(
			" أعلى سلسلة: %s بإيراد %.0f %s (حصة %.1f%%).",
			c.Name, c.Revenue, agg.Currency, c.SharePct,
		))
	}
	if len(agg.TopProducts) > 0 {
		p := agg.TopProducts[0]
		b.WriteString(fmt.Sprintf(
			" أعلى منتج: %s بإيراد %.0f %s.",
			p.Name, p.Revenue, agg.Currency,
		))
	}
	if len(agg.TopCategories) > 0 {
		c := agg.TopCategories[0]
		b.WriteString(fmt.Sprintf(
			" أعلى فئة: %s بإيراد %.0f %s.",
			c.Name, c.Revenue, agg.Currency,
		))
	}

	if len(agg.NotableDeltas) > 0 {
		parts := make([]string, 0, len(agg.NotableDeltas))
		for _, d := range agg.NotableDeltas {
			switch d.Unit {
			case "pct":
				parts = append(parts, fmt.Sprintf("%s %+.1f%%", d.LabelAR, d.Value))
			case "egp":
				parts = append(parts, fmt.Sprintf("%s %.0f %s", d.LabelAR, d.Value, agg.Currency))
			default:
				parts = append(parts, fmt.Sprintf("%s %.1f", d.LabelAR, d.Value))
			}
		}
		b.WriteString(" أبرز التغيّرات: ")
		b.WriteString(strings.Join(parts, "؛ "))
		b.WriteString(".")
	}

	return b.String()
}

// Grounded reports whether narrative quotes the key computed figures from agg.
// For AI paths, callers must also ValidateClaims / GroundedStructured — number
// presence alone is not enough (correct numbers + fabricated claim must fail).
func Grounded(narrative string, agg domain.MonthlySummaryAggregates) bool {
	n := strings.TrimSpace(narrative)
	if n == "" {
		return false
	}
	if agg.TotalRevenue == 0 && agg.TotalUnits == 0 {
		// Empty-data path: accept the explicit no-data sentence.
		return strings.Contains(n, "لا تتوفر") || strings.Contains(n, "لا توجد")
	}
	revOK := containsFormattedNumber(n, agg.TotalRevenue)
	unitsOK := agg.TotalUnits == 0 || containsInt(n, agg.TotalUnits)
	if !revOK || !unitsOK {
		return false
	}
	if len(agg.TopChains) > 0 {
		if !strings.Contains(n, agg.TopChains[0].Name) {
			return false
		}
	}
	return true
}

func containsFormattedNumber(text string, v float64) bool {
	candidates := []string{
		fmt.Sprintf("%.0f", v),
		fmt.Sprintf("%.1f", v),
		fmt.Sprintf("%.2f", v),
		formatWithCommas(v),
	}
	for _, c := range candidates {
		if c != "" && strings.Contains(text, c) {
			return true
		}
	}
	return false
}

func containsInt(text string, v int) bool {
	s := strconv.Itoa(v)
	return s != "" && strings.Contains(text, s)
}

func formatWithCommas(v float64) string {
	s := fmt.Sprintf("%.0f", v)
	if len(s) <= 3 {
		return s
	}
	neg := false
	if strings.HasPrefix(s, "-") {
		neg = true
		s = s[1:]
	}
	var b strings.Builder
	for i, r := range s {
		if i > 0 && (len(s)-i)%3 == 0 {
			b.WriteByte(',')
		}
		b.WriteRune(r)
	}
	if neg {
		return "-" + b.String()
	}
	return b.String()
}

// Confidence scores how complete the fact sheet is (0–0.99). Never invents data.
func Confidence(agg domain.MonthlySummaryAggregates) float64 {
	var c float64
	if agg.TotalRevenue > 0 || agg.TotalUnits > 0 {
		c += 0.4
	}
	if agg.RevenueMoMPct != 0 || agg.PriorMonthKey != "" {
		c += 0.2
	}
	if len(agg.TopChains) > 0 {
		c += 0.15
	}
	if len(agg.TopProducts) > 0 {
		c += 0.15
	}
	if len(agg.TopCategories) > 0 {
		c += 0.1
	}
	if c > 0.99 {
		c = 0.99
	}
	return round2(c)
}
