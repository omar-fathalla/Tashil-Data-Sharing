package monthlysummary

import (
	"encoding/json"
	"fmt"
	"math"
	"regexp"
	"strconv"
	"strings"

	"github.com/tashil/data-sharing/backend/internal/domain"
)

// Allowed claim keys that can be checked against aggregates evidence.
const (
	ClaimTotalRevenue      = "total_revenue"
	ClaimTotalUnits        = "total_units"
	ClaimRevenueMoMPct     = "revenue_mom_pct"
	ClaimUnitsMoMPct       = "units_mom_pct"
	ClaimRevenueYoYPct     = "revenue_yoy_pct"
	ClaimMarketSharePct    = "market_share_pct"
	ClaimActiveStores      = "active_stores"
	ClaimTopChain          = "top_chain"
	ClaimTopProduct        = "top_product"
	ClaimTopCategory       = "top_category"
	ClaimPriorMonthKey     = "prior_month_key"
	ClaimCurrentMonthKey   = "current_month_key"
	ClaimPriorMonthRevenue = "prior_month_revenue"
)

// Claim is one structured assertion checked against the fact sheet.
// Number is used for numeric keys; Name for entity keys.
type Claim struct {
	Key    string  `json:"key"`
	Number float64 `json:"number,omitempty"`
	Name   string  `json:"name,omitempty"`
}

// AINarrativePayload is the only accepted AI response shape.
// Free-form prose without this envelope is treated as ungrounded (deterministic fallback).
// narrative_ar is inspected for fabricated numbers but is NEVER shipped — the
// response narrative is rebuilt only from validated claims.
type AINarrativePayload struct {
	NarrativeAR string  `json:"narrative_ar"`
	Claims      []Claim `json:"claims"`
}

var narrativeNumberPattern = regexp.MustCompile(`[-+]?\d{1,3}(?:,\d{3})+(?:\.\d+)?|[-+]?\d+(?:\.\d+)?`)

// ParseAIPayload accepts raw model output (optionally fenced) as structured claims JSON.
func ParseAIPayload(raw string) (AINarrativePayload, error) {
	raw = sanitizeNarrative(raw)
	if raw == "" {
		return AINarrativePayload{}, fmt.Errorf("empty ai payload")
	}
	if strings.HasPrefix(raw, "```") {
		raw = strings.TrimPrefix(raw, "```json")
		raw = strings.TrimPrefix(raw, "```JSON")
		raw = strings.TrimPrefix(raw, "```")
		raw = strings.TrimSuffix(raw, "```")
		raw = strings.TrimSpace(raw)
	}
	var p AINarrativePayload
	if err := json.Unmarshal([]byte(raw), &p); err != nil {
		return AINarrativePayload{}, fmt.Errorf("ai payload must be structured claims JSON: %w", err)
	}
	p.NarrativeAR = strings.TrimSpace(p.NarrativeAR)
	if len(p.Claims) == 0 {
		return AINarrativePayload{}, fmt.Errorf("ai payload missing claims")
	}
	return p, nil
}

// ValidateClaims checks every structured claim against aggregates evidence.
// Unknown keys, wrong numbers/names, or empty claims → false.
func ValidateClaims(claims []Claim, agg domain.MonthlySummaryAggregates) bool {
	if len(claims) == 0 {
		return false
	}
	seenRequired := map[string]bool{}
	for _, c := range claims {
		key := strings.TrimSpace(c.Key)
		if key == "" {
			return false
		}
		ok, required := matchClaim(key, c, agg)
		if !ok {
			return false
		}
		if required {
			seenRequired[key] = true
		}
	}
	if agg.TotalRevenue != 0 && !seenRequired[ClaimTotalRevenue] {
		return false
	}
	if agg.TotalUnits != 0 && !seenRequired[ClaimTotalUnits] {
		return false
	}
	if len(agg.TopChains) > 0 && !seenRequired[ClaimTopChain] {
		return false
	}
	return true
}

func matchClaim(key string, c Claim, agg domain.MonthlySummaryAggregates) (ok bool, required bool) {
	switch key {
	case ClaimTotalRevenue:
		return nearlyEqual(c.Number, agg.TotalRevenue), true
	case ClaimTotalUnits:
		return nearlyEqual(c.Number, float64(agg.TotalUnits)), true
	case ClaimRevenueMoMPct:
		return nearlyEqual(c.Number, agg.RevenueMoMPct), false
	case ClaimUnitsMoMPct:
		return nearlyEqual(c.Number, agg.UnitsMoMPct), false
	case ClaimRevenueYoYPct:
		return nearlyEqual(c.Number, agg.RevenueYoYPct), false
	case ClaimMarketSharePct:
		return nearlyEqual(c.Number, agg.MarketSharePct), false
	case ClaimActiveStores:
		return nearlyEqual(c.Number, float64(agg.ActiveStores)), false
	case ClaimPriorMonthRevenue:
		return nearlyEqual(c.Number, agg.PriorMonthRevenue), false
	case ClaimPriorMonthKey:
		return strings.TrimSpace(c.Name) == agg.PriorMonthKey && agg.PriorMonthKey != "", false
	case ClaimCurrentMonthKey:
		return strings.TrimSpace(c.Name) == agg.CurrentMonthKey && agg.CurrentMonthKey != "", false
	case ClaimTopChain:
		if len(agg.TopChains) == 0 {
			return false, true
		}
		return strings.TrimSpace(c.Name) == agg.TopChains[0].Name, true
	case ClaimTopProduct:
		if len(agg.TopProducts) == 0 {
			return false, false
		}
		return strings.TrimSpace(c.Name) == agg.TopProducts[0].Name, false
	case ClaimTopCategory:
		if len(agg.TopCategories) == 0 {
			return false, false
		}
		return strings.TrimSpace(c.Name) == agg.TopCategories[0].Name, false
	default:
		return false, false
	}
}

func nearlyEqual(a, b float64) bool {
	return math.Abs(a-b) <= 0.05
}

// allowedEvidenceNumbers are numeric values that may appear in AI narrative_ar.
// Anything else (e.g. a fabricated sales total) causes rejection even if claims are valid.
func allowedEvidenceNumbers(claims []Claim, agg domain.MonthlySummaryAggregates) map[float64]bool {
	allowed := map[float64]bool{}
	add := func(v float64) {
		allowed[v] = true
		allowed[math.Round(v)] = true
		allowed[round1(v)] = true
		allowed[round2(v)] = true
	}
	for _, c := range claims {
		switch strings.TrimSpace(c.Key) {
		case ClaimTopChain, ClaimTopProduct, ClaimTopCategory, ClaimPriorMonthKey, ClaimCurrentMonthKey:
			// names only
		default:
			add(c.Number)
		}
	}
	// Always allow core evidence the claims were validated against.
	add(agg.TotalRevenue)
	add(float64(agg.TotalUnits))
	add(agg.RevenueMoMPct)
	add(agg.UnitsMoMPct)
	add(agg.RevenueYoYPct)
	add(agg.MarketSharePct)
	add(float64(agg.ActiveStores))
	add(agg.PriorMonthRevenue)
	if len(agg.TopChains) > 0 {
		add(agg.TopChains[0].Revenue)
		add(agg.TopChains[0].SharePct)
		add(float64(agg.TopChains[0].Units))
	}
	if len(agg.TopProducts) > 0 {
		add(agg.TopProducts[0].Revenue)
		add(agg.TopProducts[0].SharePct)
	}
	if len(agg.TopCategories) > 0 {
		add(agg.TopCategories[0].Revenue)
		add(agg.TopCategories[0].SharePct)
	}
	// Month keys like 2026-10 contribute year/month fragments — allow small calendar ints.
	for _, frag := range []float64{1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12} {
		allowed[frag] = true
	}
	if y := yearFromMonthKey(agg.CurrentMonthKey); y > 0 {
		add(float64(y))
	}
	if y := yearFromMonthKey(agg.PriorMonthKey); y > 0 {
		add(float64(y))
	}
	return allowed
}

func yearFromMonthKey(key string) int {
	key = strings.TrimSpace(key)
	if len(key) < 4 {
		return 0
	}
	y, err := strconv.Atoi(key[:4])
	if err != nil {
		return 0
	}
	return y
}

// NarrativeHasFabricatedNumbers reports numbers in narrative_ar that are not
// present in validated claims / aggregates evidence.
func NarrativeHasFabricatedNumbers(narrative string, claims []Claim, agg domain.MonthlySummaryAggregates) bool {
	narrative = strings.TrimSpace(narrative)
	if narrative == "" {
		return false
	}
	allowed := allowedEvidenceNumbers(claims, agg)
	for _, m := range narrativeNumberPattern.FindAllString(narrative, -1) {
		norm := strings.ReplaceAll(m, ",", "")
		v, err := strconv.ParseFloat(norm, 64)
		if err != nil {
			continue
		}
		// Ignore pure sign noise / zero placeholders.
		if v == 0 {
			continue
		}
		if !numberAllowed(v, allowed) {
			return true
		}
	}
	return false
}

func numberAllowed(v float64, allowed map[float64]bool) bool {
	if allowed[v] || allowed[math.Abs(v)] {
		return true
	}
	for a := range allowed {
		if nearlyEqual(v, a) || nearlyEqual(math.Abs(v), math.Abs(a)) {
			return true
		}
	}
	return false
}

// NarrateFromClaims builds the shipped Arabic narrative exclusively from
// validated claims (never from AI narrative_ar prose).
func NarrateFromClaims(claims []Claim, agg domain.MonthlySummaryAggregates) string {
	byKey := map[string]Claim{}
	for _, c := range claims {
		byKey[strings.TrimSpace(c.Key)] = c
	}
	var b strings.Builder
	b.WriteString("ملخص شهري (مبني حصراً على ادعاءات موثّقة من أرقام اللوحة): ")

	if c, ok := byKey[ClaimTotalRevenue]; ok {
		units := ""
		if u, ok := byKey[ClaimTotalUnits]; ok {
			units = fmt.Sprintf(" والوحدات %.0f", u.Number)
		}
		period := agg.Period
		if mk, ok := byKey[ClaimCurrentMonthKey]; ok && strings.TrimSpace(mk.Name) != "" {
			period = strings.TrimSpace(mk.Name)
		} else if agg.CurrentMonthKey != "" {
			period = agg.CurrentMonthKey
		}
		b.WriteString(fmt.Sprintf("إجمالي المبيعات %.0f %s خلال %s%s.",
			c.Number, agg.Currency, period, units))
	}

	if c, ok := byKey[ClaimRevenueMoMPct]; ok {
		uMom := ""
		if u, ok := byKey[ClaimUnitsMoMPct]; ok {
			uMom = fmt.Sprintf(" والوحدات %+.1f%%", u.Number)
		}
		b.WriteString(fmt.Sprintf(" التغير الشهري للإيراد %+.1f%%%s.", c.Number, uMom))
	} else if c, ok := byKey[ClaimUnitsMoMPct]; ok {
		b.WriteString(fmt.Sprintf(" التغير الشهري للوحدات %+.1f%%.", c.Number))
	}

	if !agg.YoYAvailable {
		// No comparable last-year data: never ship a YoY claim (it would read
		// as a real 0% change).
		if _, ok := byKey[ClaimTotalRevenue]; ok {
			b.WriteString(NoLastYearSentenceAR)
		}
	} else if c, ok := byKey[ClaimRevenueYoYPct]; ok {
		b.WriteString(fmt.Sprintf(" التغير السنوي للإيراد %+.1f%%.", c.Number))
	}
	if c, ok := byKey[ClaimMarketSharePct]; ok {
		b.WriteString(fmt.Sprintf(" الحصة السوقية %.1f%%.", c.Number))
	}
	if c, ok := byKey[ClaimActiveStores]; ok {
		b.WriteString(fmt.Sprintf(" الفروع النشطة %.0f.", c.Number))
	}
	if c, ok := byKey[ClaimTopChain]; ok {
		b.WriteString(fmt.Sprintf(" أعلى سلسلة: %s.", strings.TrimSpace(c.Name)))
	}
	if c, ok := byKey[ClaimTopProduct]; ok {
		b.WriteString(fmt.Sprintf(" أعلى منتج: %s.", strings.TrimSpace(c.Name)))
	}
	if c, ok := byKey[ClaimTopCategory]; ok {
		b.WriteString(fmt.Sprintf(" أعلى فئة: %s.", strings.TrimSpace(c.Name)))
	}

	out := strings.TrimSpace(b.String())
	if out == "ملخص شهري (مبني حصراً على ادعاءات موثّقة من أرقام اللوحة):" {
		return DeterministicNarrateAR(agg)
	}
	return out
}

// AcceptAIClaims is the single gate for the AI path: claims must match evidence,
// and any AI narrative_ar must not introduce fabricated numbers. The shipped
// narrative is always NarrateFromClaims — never the model prose.
func AcceptAIClaims(narrativeAR string, claims []Claim, agg domain.MonthlySummaryAggregates) bool {
	if !ValidateClaims(claims, agg) {
		return false
	}
	if NarrativeHasFabricatedNumbers(narrativeAR, claims, agg) {
		return false
	}
	built := NarrateFromClaims(claims, agg)
	return Grounded(built, agg)
}

// GroundedStructured keeps the prior name for tests; delegates to AcceptAIClaims.
func GroundedStructured(narrative string, claims []Claim, agg domain.MonthlySummaryAggregates) bool {
	return AcceptAIClaims(narrative, claims, agg)
}
