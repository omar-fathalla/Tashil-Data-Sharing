package monthlysummary

import (
	"encoding/json"
	"fmt"
	"math"
	"strings"

	"github.com/tashil/data-sharing/backend/internal/domain"
)

// Allowed claim keys that can be checked against aggregates evidence.
const (
	ClaimTotalRevenue   = "total_revenue"
	ClaimTotalUnits     = "total_units"
	ClaimRevenueMoMPct  = "revenue_mom_pct"
	ClaimUnitsMoMPct    = "units_mom_pct"
	ClaimRevenueYoYPct  = "revenue_yoy_pct"
	ClaimMarketSharePct = "market_share_pct"
	ClaimActiveStores   = "active_stores"
	ClaimTopChain       = "top_chain"
	ClaimTopProduct     = "top_product"
	ClaimTopCategory    = "top_category"
	ClaimPriorMonthKey  = "prior_month_key"
	ClaimCurrentMonthKey = "current_month_key"
	ClaimPriorMonthRevenue = "prior_month_revenue"
)

// Claim is one structured assertion the narrative makes about the fact sheet.
// Number is used for numeric keys; Name for entity keys. Exactly one should be set.
type Claim struct {
	Key    string  `json:"key"`
	Number float64 `json:"number,omitempty"`
	Name   string  `json:"name,omitempty"`
}

// AINarrativePayload is the only accepted AI response shape.
// Free-form prose without this envelope is treated as ungrounded (deterministic fallback).
type AINarrativePayload struct {
	NarrativeAR string  `json:"narrative_ar"`
	Claims      []Claim `json:"claims"`
}

// ParseAIPayload accepts raw model output (optionally fenced) as structured claims JSON.
func ParseAIPayload(raw string) (AINarrativePayload, error) {
	raw = sanitizeNarrative(raw)
	if raw == "" {
		return AINarrativePayload{}, fmt.Errorf("empty ai payload")
	}
	// Strip optional ```json fences.
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
	if p.NarrativeAR == "" {
		return AINarrativePayload{}, fmt.Errorf("ai payload missing narrative_ar")
	}
	if len(p.Claims) == 0 {
		return AINarrativePayload{}, fmt.Errorf("ai payload missing claims")
	}
	return p, nil
}

// ValidateClaims checks every structured claim against aggregates evidence.
// Unknown keys, wrong numbers/names, or empty claims → false.
// Correct numbers plus a fabricated claim (unknown key or wrong name) fail.
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
	// Must assert the core revenue/units evidence when those figures exist.
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
		// Fabricated / unknown claim keys are never evidence-backed.
		return false, false
	}
}

func nearlyEqual(a, b float64) bool {
	return math.Abs(a-b) <= 0.05
}

// GroundedStructured is true only when claims match evidence AND the narrative
// still quotes the core aggregate figures (no free-form AI without claims).
func GroundedStructured(narrative string, claims []Claim, agg domain.MonthlySummaryAggregates) bool {
	if !ValidateClaims(claims, agg) {
		return false
	}
	return Grounded(narrative, agg)
}
