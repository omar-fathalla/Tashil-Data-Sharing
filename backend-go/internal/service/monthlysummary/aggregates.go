// Package monthlysummary builds a deterministic monthly fact sheet and an Arabic
// narrative grounded only in those facts (Gemini Phase C). It never invents figures.
package monthlysummary

import (
	"math"
	"sort"
	"strings"

	"github.com/tashil/data-sharing/backend/internal/domain"
)

const (
	SourceDeterministic = "deterministic"
	SourceAI            = "ai"
	SourceMock          = "mock"

	deltaThresholdPct = 5.0
	topN              = 3
)

// BuildAggregates derives monthly facts from already-computed executive KPIs.
// Returns a zero-value Aggregates when kpis is nil.
func BuildAggregates(kpis *domain.ExecutiveKPIs) domain.MonthlySummaryAggregates {
	if kpis == nil {
		return domain.MonthlySummaryAggregates{}
	}
	currency := strings.TrimSpace(kpis.Currency)
	if currency == "" {
		currency = "EGP"
	}
	period := strings.TrimSpace(kpis.ReportingPeriod)
	if period == "" {
		period = "MTD"
	}

	agg := domain.MonthlySummaryAggregates{
		Period:         period,
		Currency:       currency,
		TotalRevenue:   round2(kpis.TotalRevenue),
		TotalUnits:     kpis.TotalUnitsSold,
		RevenueMoMPct:  round1(kpis.RevenueMoMPct),
		UnitsMoMPct:    round1(kpis.UnitsMoMPct),
		RevenueYoYPct:  round1(kpis.RevenueYoYPct),
		ActiveStores:   kpis.ActiveStoresCount,
		MarketSharePct: round1(kpis.TenantMarketSharePct),
	}

	fillMonthKeysFromTrends(&agg, kpis.DailyTrends)

	agg.TopChains = topChains(kpis.ChainShares, topN)
	agg.TopProducts = topProducts(kpis.ParetoSKUs, topN)
	agg.TopCategories = topCategories(kpis.CategoryContributions, topN)
	agg.NotableDeltas = notableDeltas(agg, kpis)
	return agg
}

func fillMonthKeysFromTrends(agg *domain.MonthlySummaryAggregates, trends []domain.DailyTrendPoint) {
	if len(trends) == 0 {
		return
	}
	type pt struct {
		key string
		rev float64
	}
	pts := make([]pt, 0, len(trends))
	for _, t := range trends {
		key := strings.TrimSpace(t.MonthKey)
		if key == "" {
			key = strings.TrimSpace(t.Date)
			if len(key) >= 7 {
				key = key[:7]
			}
		}
		if key == "" {
			continue
		}
		pts = append(pts, pt{key: key, rev: t.Revenue})
	}
	if len(pts) == 0 {
		return
	}
	sort.Slice(pts, func(i, j int) bool { return pts[i].key < pts[j].key })
	last := pts[len(pts)-1]
	agg.CurrentMonthKey = last.key
	if len(pts) >= 2 {
		prior := pts[len(pts)-2]
		agg.PriorMonthKey = prior.key
		agg.PriorMonthRevenue = round2(prior.rev)
		// Prefer explicit KPI MoM; otherwise derive from the last two trend points.
		if agg.RevenueMoMPct == 0 && prior.rev > 0 {
			agg.RevenueMoMPct = round1(((last.rev - prior.rev) / prior.rev) * 100)
		}
	}
}

func topChains(shares []domain.ChainShareSummary, n int) []domain.MonthlySummaryNamedValue {
	if len(shares) == 0 {
		return nil
	}
	cp := append([]domain.ChainShareSummary(nil), shares...)
	sort.Slice(cp, func(i, j int) bool { return cp[i].TotalRevenue > cp[j].TotalRevenue })
	out := make([]domain.MonthlySummaryNamedValue, 0, n)
	for _, s := range cp {
		if len(out) >= n {
			break
		}
		name := strings.TrimSpace(s.DisplayName)
		if name == "" || strings.EqualFold(s.RetailerChain, "nda_redacted") {
			name = strings.TrimSpace(s.RetailerChain)
		}
		if name == "" || strings.EqualFold(name, "nda_redacted") {
			continue
		}
		out = append(out, domain.MonthlySummaryNamedValue{
			Name:     name,
			Revenue:  round2(s.TotalRevenue),
			Units:    s.TotalUnits,
			SharePct: round1(s.MarketShare),
		})
	}
	return out
}

func topProducts(pareto []domain.ParetoSKUItem, n int) []domain.MonthlySummaryNamedValue {
	if len(pareto) == 0 {
		return nil
	}
	cp := append([]domain.ParetoSKUItem(nil), pareto...)
	sort.Slice(cp, func(i, j int) bool { return cp[i].TotalRevenue > cp[j].TotalRevenue })
	out := make([]domain.MonthlySummaryNamedValue, 0, n)
	for _, p := range cp {
		if len(out) >= n {
			break
		}
		name := strings.TrimSpace(p.SKUName)
		if name == "" {
			name = strings.TrimSpace(p.Barcode)
		}
		if name == "" {
			name = strings.TrimSpace(p.ItemCode)
		}
		if name == "" {
			continue
		}
		out = append(out, domain.MonthlySummaryNamedValue{
			Name:     name,
			Revenue:  round2(p.TotalRevenue),
			Units:    p.TotalUnits,
			SharePct: round1(p.RevenueSharePct),
		})
	}
	return out
}

func topCategories(cats []domain.CategoryContribution, n int) []domain.MonthlySummaryNamedValue {
	if len(cats) == 0 {
		return nil
	}
	cp := append([]domain.CategoryContribution(nil), cats...)
	sort.Slice(cp, func(i, j int) bool { return cp[i].TotalRevenue > cp[j].TotalRevenue })
	out := make([]domain.MonthlySummaryNamedValue, 0, n)
	for _, c := range cp {
		if len(out) >= n {
			break
		}
		name := strings.TrimSpace(c.Category)
		if name == "" {
			continue
		}
		out = append(out, domain.MonthlySummaryNamedValue{
			Name:     name,
			Revenue:  round2(c.TotalRevenue),
			Units:    c.TotalUnits,
			SharePct: round1(c.SharePct),
		})
	}
	return out
}

func notableDeltas(agg domain.MonthlySummaryAggregates, kpis *domain.ExecutiveKPIs) []domain.MonthlySummaryDelta {
	var out []domain.MonthlySummaryDelta
	addPct := func(code, label string, v float64) {
		if math.Abs(v) < deltaThresholdPct {
			return
		}
		dir := "flat"
		if v > 0 {
			dir = "up"
		} else if v < 0 {
			dir = "down"
		}
		out = append(out, domain.MonthlySummaryDelta{
			Code: code, LabelAR: label, Value: round1(v), Unit: "pct", Direction: dir,
		})
	}
	addPct("revenue_mom", "تغير الإيراد شهرياً", agg.RevenueMoMPct)
	addPct("units_mom", "تغير الوحدات شهرياً", agg.UnitsMoMPct)
	addPct("revenue_yoy", "تغير الإيراد سنوياً", agg.RevenueYoYPct)

	if kpis != nil && kpis.OOSRatePct >= 10 {
		out = append(out, domain.MonthlySummaryDelta{
			Code: "oos_rate", LabelAR: "معدل انعدام المخزون", Value: round1(kpis.OOSRatePct),
			Unit: "pct", Direction: "up",
		})
	}
	if kpis != nil && kpis.EstimatedLostRevenue >= 1000 {
		out = append(out, domain.MonthlySummaryDelta{
			Code: "lost_revenue", LabelAR: "إيراد مفقود مقدّر بسبب انعدام المخزون",
			Value: round2(kpis.EstimatedLostRevenue), Unit: "egp", Direction: "up",
		})
	}
	if len(agg.TopChains) > 0 && agg.TopChains[0].SharePct >= 40 {
		out = append(out, domain.MonthlySummaryDelta{
			Code: "chain_concentration", LabelAR: "تركّز المبيعات في أعلى سلسلة",
			Value: agg.TopChains[0].SharePct, Unit: "pct", Direction: "up",
		})
	}
	return out
}

func round1(v float64) float64 { return math.Round(v*10) / 10 }
func round2(v float64) float64 { return math.Round(v*100) / 100 }
