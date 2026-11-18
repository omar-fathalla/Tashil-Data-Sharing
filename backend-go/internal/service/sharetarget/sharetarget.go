// Package sharetarget computes market-share based Sell-Out targets («مستهدف بالحصة السوقية»).
//
// Core formulas (Mohamed decisions):
//   ProjectedMarket = Market(base) × (1 + g/100) × annualization
//   TargetRevenue   = DesiredSharePct/100 × ProjectedMarket
//   Units           = TargetRevenue ÷ AvgPrice
//   Uplift          = TargetRevenue − CurrentOwn (same annualization)
//
// Cascade: uplift across branches by historical Adeco weight in the category;
// SKUs by share within branch/category; months by historical seasonality else even.
// Share > 100% is a hard block; desired share below current is a warning only.
package sharetarget

import (
	"fmt"
	"math"
	"sort"

	"github.com/tashil/data-sharing/backend/internal/service/targetalloc"
)

const (
	// OriginShare marks a TargetRecord created from the share wizard.
	OriginShare = "market_share"
	// OriginValue is the classic revenue/units entry.
	OriginValue = "value"
)

// CategoryInput is one category's base-year snapshot for a single chain (no cross-chain merge).
type CategoryInput struct {
	Category       string
	CurrentSharePct float64 // Adeco ÷ category market, 0–100
	OwnRevenueEGP  float64
	MarketRevenueEGP float64
	OwnUnits       float64
	AvgPriceEGP    float64 // OwnRevenue ÷ OwnUnits when known
}

// CategoryPlan is the live computation for one category after the user picks a desired share.
type CategoryPlan struct {
	Category            string  `json:"category"`
	CurrentSharePct     float64 `json:"current_share_pct"`
	DesiredSharePct     float64 `json:"desired_share_pct"`
	OwnRevenueEGP       float64 `json:"own_revenue_egp"`
	MarketRevenueEGP    float64 `json:"market_revenue_egp"`
	ProjectedMarketEGP  float64 `json:"projected_market_egp"`
	TargetRevenueEGP    float64 `json:"target_revenue_egp"`
	UpliftRevenueEGP    float64 `json:"uplift_revenue_egp"`
	UpliftPct           float64 `json:"uplift_pct"`
	AvgPriceEGP         float64 `json:"avg_price_egp"`
	CurrentUnits        float64 `json:"current_units"`
	TargetUnits         float64 `json:"target_units"`
	UpliftUnits         float64 `json:"uplift_units"`
	BelowCurrent        bool    `json:"below_current"`
	ExceedsMarket       bool    `json:"exceeds_market"` // desired > 100
}

// Options control market growth and annualization of a partial base year.
type Options struct {
	MarketGrowthPct float64 // g; default 0 (flat)
	// MonthsWithData is how many months the base year actually has (e.g. 10 for Jan–Oct 2026).
	// When Annualize is true and MonthsWithData is in 1..11, revenues are scaled by 12/MonthsWithData.
	MonthsWithData int
	Annualize      bool
}

// AnnualizationFactor returns the multiplier applied to base revenues.
func AnnualizationFactor(opt Options) float64 {
	if !opt.Annualize || opt.MonthsWithData <= 0 || opt.MonthsWithData >= 12 {
		return 1
	}
	return 12.0 / float64(opt.MonthsWithData)
}

func round2(v float64) float64 { return math.Round(v*100) / 100 }

func round1(v float64) float64 { return math.Round(v*10) / 10 }

// ExactCurrentSharePct returns Adeco ÷ market × 100 (unrounded). Falls back to CurrentSharePct.
func ExactCurrentSharePct(in CategoryInput) float64 {
	if in.MarketRevenueEGP > 0 {
		return in.OwnRevenueEGP / in.MarketRevenueEGP * 100
	}
	return in.CurrentSharePct
}

// PlanCategory applies the share formulas to one category for an absolute desired share %.
func PlanCategory(in CategoryInput, desiredSharePct float64, opt Options) CategoryPlan {
	return planCategory(in, desiredSharePct, opt, false)
}

// PlanCategoryDelta applies +deltaPts to the exact current share (own÷market).
// Used by the «+X نقط لكل الفئات» quick action so +5pt matches the research fixture.
func PlanCategoryDelta(in CategoryInput, deltaPts float64, opt Options) CategoryPlan {
	return planCategory(in, ExactCurrentSharePct(in)+deltaPts, opt, true)
}

func planCategory(in CategoryInput, desiredSharePct float64, opt Options, fromDelta bool) CategoryPlan {
	factor := AnnualizationFactor(opt)
	g := 1 + opt.MarketGrowthPct/100
	if g < 0 {
		g = 0
	}
	own := in.OwnRevenueEGP * factor
	market := in.MarketRevenueEGP * factor
	projected := market * g
	avg := in.AvgPriceEGP
	units := in.OwnUnits * factor
	if avg <= 0 && units > 0 && own > 0 {
		avg = own / units
	}

	exactCurrent := ExactCurrentSharePct(CategoryInput{
		OwnRevenueEGP: own, MarketRevenueEGP: market, CurrentSharePct: in.CurrentSharePct,
	})
	displayCurrent := in.CurrentSharePct
	if displayCurrent <= 0 {
		displayCurrent = exactCurrent
	}

	desired := desiredSharePct
	exceeds := desired > 100
	target := desired / 100 * projected
	uplift := target - own
	upliftPct := 0.0
	if own > 0 {
		upliftPct = uplift / own * 100
	}
	targetUnits := 0.0
	if avg > 0 {
		targetUnits = target / avg
	}
	upliftUnits := targetUnits - units

	_ = fromDelta
	return CategoryPlan{
		Category:           in.Category,
		CurrentSharePct:    round1(displayCurrent),
		DesiredSharePct:    round1(desired),
		OwnRevenueEGP:      round2(own),
		MarketRevenueEGP:   round2(market),
		ProjectedMarketEGP: round2(projected),
		TargetRevenueEGP:   round2(target),
		UpliftRevenueEGP:   round2(uplift),
		UpliftPct:          round1(upliftPct),
		AvgPriceEGP:        round2(avg),
		CurrentUnits:       round2(units),
		TargetUnits:        round2(targetUnits),
		UpliftUnits:        round2(upliftUnits),
		BelowCurrent:       desired+1e-9 < exactCurrent,
		ExceedsMarket:      exceeds,
	}
}

// PlanCategories plans every category; totals roll up target / own / uplift.
type PlanSummary struct {
	Categories         []CategoryPlan `json:"categories"`
	TotalOwnEGP        float64        `json:"total_own_egp"`
	TotalMarketEGP     float64        `json:"total_market_egp"`
	TotalProjectedEGP  float64        `json:"total_projected_egp"`
	TotalTargetEGP     float64        `json:"total_target_egp"`
	TotalUpliftEGP     float64        `json:"total_uplift_egp"`
	TotalUpliftPct     float64        `json:"total_uplift_pct"`
	TotalCurrentUnits  float64        `json:"total_current_units"`
	TotalTargetUnits   float64        `json:"total_target_units"`
	OverallCurrentPct  float64        `json:"overall_current_share_pct"`
	OverallDesiredPct  float64        `json:"overall_desired_share_pct"`
	HasShareOver100    bool           `json:"has_share_over_100"`
	HasBelowCurrent    bool           `json:"has_below_current"`
	MarketGrowthPct    float64        `json:"market_growth_pct"`
	MonthsWithData     int            `json:"months_with_data"`
	Annualized         bool           `json:"annualized"`
	AnnualizationFactor float64       `json:"annualization_factor"`
}

// PlanAll plans a slice of categories with absolute desired shares (same length / order as inputs).
func PlanAll(inputs []CategoryInput, desired []float64, opt Options) (PlanSummary, error) {
	if len(desired) != len(inputs) {
		return PlanSummary{}, fmt.Errorf("desired shares length %d != categories %d", len(desired), len(inputs))
	}
	plans := make([]CategoryPlan, len(inputs))
	for i, in := range inputs {
		plans[i] = PlanCategory(in, desired[i], opt)
	}
	return summarize(plans, opt), nil
}

// PlanAllDelta applies the same +deltaPts to every category's exact current share.
func PlanAllDelta(inputs []CategoryInput, deltaPts float64, opt Options) PlanSummary {
	plans := make([]CategoryPlan, len(inputs))
	for i, in := range inputs {
		plans[i] = PlanCategoryDelta(in, deltaPts, opt)
	}
	return summarize(plans, opt)
}

func summarize(plans []CategoryPlan, opt Options) PlanSummary {
	out := PlanSummary{
		Categories:          plans,
		MarketGrowthPct:     opt.MarketGrowthPct,
		MonthsWithData:      opt.MonthsWithData,
		Annualized:          opt.Annualize && opt.MonthsWithData > 0 && opt.MonthsWithData < 12,
		AnnualizationFactor: AnnualizationFactor(opt),
	}
	for _, p := range plans {
		out.TotalOwnEGP += p.OwnRevenueEGP
		out.TotalMarketEGP += p.MarketRevenueEGP
		out.TotalProjectedEGP += p.ProjectedMarketEGP
		out.TotalTargetEGP += p.TargetRevenueEGP
		out.TotalUpliftEGP += p.UpliftRevenueEGP
		out.TotalCurrentUnits += p.CurrentUnits
		out.TotalTargetUnits += p.TargetUnits
		if p.ExceedsMarket {
			out.HasShareOver100 = true
		}
		if p.BelowCurrent {
			out.HasBelowCurrent = true
		}
	}
	out.TotalOwnEGP = round2(out.TotalOwnEGP)
	out.TotalMarketEGP = round2(out.TotalMarketEGP)
	out.TotalProjectedEGP = round2(out.TotalProjectedEGP)
	out.TotalTargetEGP = round2(out.TotalTargetEGP)
	out.TotalUpliftEGP = round2(out.TotalUpliftEGP)
	out.TotalCurrentUnits = round2(out.TotalCurrentUnits)
	out.TotalTargetUnits = round2(out.TotalTargetUnits)
	if out.TotalOwnEGP > 0 {
		out.TotalUpliftPct = round1(out.TotalUpliftEGP / out.TotalOwnEGP * 100)
	}
	if out.TotalMarketEGP > 0 {
		out.OverallCurrentPct = round1(out.TotalOwnEGP / out.TotalMarketEGP * 100)
	}
	if out.TotalProjectedEGP > 0 {
		out.OverallDesiredPct = round1(out.TotalTargetEGP / out.TotalProjectedEGP * 100)
	}
	return out
}

// CanProceed is false when any desired share exceeds 100%.
func (p PlanSummary) CanProceed() bool { return !p.HasShareOver100 }

// BranchWeight is a branch's historical Adeco sales in a category (for uplift split).
type BranchWeight struct {
	BranchKey  string
	BranchName string
	OwnRevenue float64
}

// SKUWeight is a SKU's share of Adeco sales inside a branch/category.
type SKUWeight struct {
	SKUKey    string
	SKUName   string
	OwnRevenue float64
	AvgPrice  float64
}

// MonthWeight is one month's historical weight (own or market seasonality).
type MonthWeight struct {
	Month  int // 1..12
	Weight float64
}

// BranchAllocation is uplift + target for one branch after historical split.
type BranchAllocation struct {
	BranchKey        string  `json:"branch_key"`
	BranchName       string  `json:"branch_name"`
	HistoricalSharePct float64 `json:"historical_share_pct"`
	CurrentOwnEGP    float64 `json:"current_own_egp"`
	UpliftEGP        float64 `json:"uplift_egp"`
	TargetEGP        float64 `json:"target_egp"`
	TargetUnits      float64 `json:"target_units,omitempty"`
	SKUs             []SKUAllocation `json:"skus,omitempty"`
}

// SKUAllocation is target revenue/units for one SKU inside a branch.
type SKUAllocation struct {
	SKUKey      string  `json:"sku_key"`
	SKUName     string  `json:"sku_name"`
	SharePct    float64 `json:"share_pct"`
	TargetEGP   float64 `json:"target_egp"`
	TargetUnits float64 `json:"target_units,omitempty"`
}

// MonthAllocation is one month of the annual target.
type MonthAllocation struct {
	Month      int     `json:"month"`
	SharePct   float64 `json:"share_pct"`
	TargetEGP  float64 `json:"target_egp"`
	TargetUnits float64 `json:"target_units,omitempty"`
}

// CategoryCascade is the full branch → SKU → month cascade for one category plan.
type CategoryCascade struct {
	Category PlanCategoryResult `json:"category"`
	Branches []BranchAllocation `json:"branches"`
	Months   []MonthAllocation  `json:"months"`
}

// PlanCategoryResult embeds CategoryPlan under a stable JSON name for cascades.
type PlanCategoryResult = CategoryPlan

// CascadeCategory splits one category's uplift across branches by historical weight,
// SKUs by share within each branch, and months by seasonality (else even 12).
func CascadeCategory(plan CategoryPlan, branches []BranchWeight, skusByBranch map[string][]SKUWeight, months []MonthWeight) CategoryCascade {
	out := CategoryCascade{Category: plan, Branches: []BranchAllocation{}, Months: []MonthAllocation{}}

	var totalHist float64
	weights := make([]int64, len(branches))
	for i, b := range branches {
		if b.OwnRevenue > 0 {
			totalHist += b.OwnRevenue
			weights[i] = centsOf(b.OwnRevenue)
		}
	}

	// Allocate uplift (may be negative) in cents so parts sum exactly; then add to current.
	upliftCents := int64(math.Round(plan.UpliftRevenueEGP * 100))
	parts := targetalloc.Apportion(abs64(upliftCents), weights)
	sign := int64(1)
	if upliftCents < 0 {
		sign = -1
	}

	avg := plan.AvgPriceEGP
	for i, b := range branches {
		uplift := float64(sign*parts[i]) / 100
		sharePct := 0.0
		if totalHist > 0 && b.OwnRevenue > 0 {
			sharePct = b.OwnRevenue / totalHist * 100
		}
		target := b.OwnRevenue + uplift
		if target < 0 {
			target = 0
		}
		ba := BranchAllocation{
			BranchKey:          b.BranchKey,
			BranchName:         b.BranchName,
			HistoricalSharePct: round1(sharePct),
			CurrentOwnEGP:      round2(b.OwnRevenue),
			UpliftEGP:          round2(uplift),
			TargetEGP:          round2(target),
			SKUs:               []SKUAllocation{},
		}
		if avg > 0 {
			ba.TargetUnits = round2(ba.TargetEGP / avg)
		}
		skuList := skusByBranch[b.BranchKey]
		ba.SKUs = allocateSKUs(ba.TargetEGP, skuList)
		out.Branches = append(out.Branches, ba)
	}
	sort.SliceStable(out.Branches, func(i, j int) bool {
		if out.Branches[i].TargetEGP != out.Branches[j].TargetEGP {
			return out.Branches[i].TargetEGP > out.Branches[j].TargetEGP
		}
		return out.Branches[i].BranchName < out.Branches[j].BranchName
	})

	out.Months = allocateMonths(plan.TargetRevenueEGP, plan.TargetUnits, months)
	return out
}

func allocateSKUs(branchTarget float64, skus []SKUWeight) []SKUAllocation {
	if len(skus) == 0 || branchTarget <= 0 {
		return []SKUAllocation{}
	}
	var total float64
	weights := make([]int64, len(skus))
	for i, s := range skus {
		if s.OwnRevenue > 0 {
			total += s.OwnRevenue
			weights[i] = centsOf(s.OwnRevenue)
		}
	}
	steps := targetalloc.Apportion(centsOf(branchTarget), weights)
	out := make([]SKUAllocation, 0, len(skus))
	for i, s := range skus {
		alloc := float64(steps[i]) / 100
		share := 0.0
		if total > 0 && s.OwnRevenue > 0 {
			share = s.OwnRevenue / total * 100
		}
		row := SKUAllocation{
			SKUKey:    s.SKUKey,
			SKUName:   s.SKUName,
			SharePct:  round1(share),
			TargetEGP: round2(alloc),
		}
		price := s.AvgPrice
		if price > 0 {
			row.TargetUnits = round2(alloc / price)
		}
		out = append(out, row)
	}
	sort.SliceStable(out, func(i, j int) bool {
		if out[i].TargetEGP != out[j].TargetEGP {
			return out[i].TargetEGP > out[j].TargetEGP
		}
		return out[i].SKUName < out[j].SKUName
	})
	return out
}

func allocateMonths(totalEGP, totalUnits float64, months []MonthWeight) []MonthAllocation {
	weights := make([]float64, 12)
	hasHist := false
	for _, m := range months {
		if m.Month >= 1 && m.Month <= 12 && m.Weight > 0 {
			weights[m.Month-1] += m.Weight
			hasHist = true
		}
	}
	if !hasHist {
		for i := range weights {
			weights[i] = 1
		}
	}
	wInt := make([]int64, 12)
	for i, w := range weights {
		wInt[i] = centsOf(w)
	}
	revParts := targetalloc.Apportion(centsOf(totalEGP), wInt)
	unitParts := targetalloc.Apportion(centsOf(totalUnits), wInt)
	var wSum float64
	for _, w := range weights {
		wSum += w
	}
	out := make([]MonthAllocation, 0, 12)
	for m := 1; m <= 12; m++ {
		share := 0.0
		if wSum > 0 {
			share = weights[m-1] / wSum * 100
		}
		out = append(out, MonthAllocation{
			Month:       m,
			SharePct:    round1(share),
			TargetEGP:   float64(revParts[m-1]) / 100,
			TargetUnits: float64(unitParts[m-1]) / 100,
		})
	}
	return out
}

func centsOf(v float64) int64 {
	c := int64(math.Round(v * 100))
	if c < 1 && v > 0 {
		return 1
	}
	return c
}

func abs64(v int64) int64 {
	if v < 0 {
		return -v
	}
	return v
}

// FixtureCategory is the research worked example row (amounts in millions EGP).
type FixtureCategory struct {
	Category        string
	CurrentSharePct float64
	DesiredSharePct float64
	OwnM            float64
	MarketM         float64
	TargetM         float64
	UpliftM         float64
	AvgPrice        float64
	CurrentUnits    float64
	TargetUnits     float64
}

// WorkedExampleFathalla2026 is the +5pt / flat / 10-month base table from research
// (8 categories, totals 98.89M → 121.43M). Amounts are millions of EGP.
func WorkedExampleFathalla2026() []FixtureCategory {
	return []FixtureCategory{
		{Category: "صابون سائل اطباق", CurrentSharePct: 39.0, DesiredSharePct: 44.0, OwnM: 43.44, MarketM: 111.24, TargetM: 49.00, UpliftM: 5.56, AvgPrice: 100.4, CurrentUnits: 432526, TargetUnits: 487906},
		{Category: "منعمات ملابس", CurrentSharePct: 30.0, DesiredSharePct: 35.0, OwnM: 14.49, MarketM: 48.35, TargetM: 16.91, UpliftM: 2.42, AvgPrice: 105.6, CurrentUnits: 137212, TargetUnits: 160104},
		{Category: "هاند وواش", CurrentSharePct: 29.9, DesiredSharePct: 34.9, OwnM: 11.91, MarketM: 39.82, TargetM: 13.90, UpliftM: 1.99, AvgPrice: 64.6, CurrentUnits: 184437, TargetUnits: 215269},
		{Category: "كلور ألوان", CurrentSharePct: 30.2, DesiredSharePct: 35.2, OwnM: 7.80, MarketM: 25.80, TargetM: 9.09, UpliftM: 1.29, AvgPrice: 64.7, CurrentUnits: 120464, TargetUnits: 140387},
		{Category: "كلور عادى", CurrentSharePct: 40.1, DesiredSharePct: 45.1, OwnM: 7.31, MarketM: 18.22, TargetM: 8.22, UpliftM: 0.91, AvgPrice: 44.0, CurrentUnits: 166246, TargetUnits: 186964},
		{Category: "شاور جيل", CurrentSharePct: 7.2, DesiredSharePct: 12.2, OwnM: 5.53, MarketM: 76.59, TargetM: 9.36, UpliftM: 3.83, AvgPrice: 132.3, CurrentUnits: 41788, TargetUnits: 70726},
		{Category: "مطهر عام", CurrentSharePct: 29.5, DesiredSharePct: 34.5, OwnM: 4.23, MarketM: 14.35, TargetM: 4.95, UpliftM: 0.72, AvgPrice: 100.1, CurrentUnits: 42267, TargetUnits: 49436},
		{Category: "مساحيق جيل اتوماتيك", CurrentSharePct: 3.6, DesiredSharePct: 8.6, OwnM: 4.18, MarketM: 116.49, TargetM: 10.00, UpliftM: 5.82, AvgPrice: 163.7, CurrentUnits: 25529, TargetUnits: 61102},
	}
}
