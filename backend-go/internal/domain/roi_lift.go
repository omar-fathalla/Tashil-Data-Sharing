package domain

// Incremental-lift / ROMI calculation used by GET /trade-marketing/roi
// and mirrored in the Flutter computeRoiLift helper.
//
// Method: seasonal YoY baseline (same calendar month last year).
// No MoM/YoY cherry-pick, no organic-ratio adjustment across mismatched
// months, and no prior-organic-average substitute when last year is missing.

const (
	RoiBaselineMethodYoySeasonal = "yoy_seasonal"
	RoiBaselineMethodUnavailable = "unavailable"

	// Kept for older clients / mid-deploy responses; new code never emits them.
	RoiBaselineMethodYoyTrend        = "yoy_trend"
	RoiBaselineMethodPriorOrganicAvg = "prior_organic_avg"

	RoiNoLastYearAR = "لا توجد بيانات للعام السابق"
	RoiBaselineUnavailableAR = RoiNoLastYearAR
	RoiYoySeasonalMethodAR = "الأساس = مبيعات نفس الشهر العام السابق (مقارنة موسمية)"
	RoiLiftMethodExplainerAR = "العائد = (مبيعات الشهر الحالي − مبيعات نفس الشهر العام السابق) ÷ المصروف. الزيادة قد تكون سالبة. عند غياب بيانات العام السابق يُعرض —."
)

// RoiMonthKey is a calendar month.
type RoiMonthKey struct {
	Year  int
	Month int
}

// Prev returns the previous calendar month.
func (k RoiMonthKey) Prev() RoiMonthKey {
	if k.Month == 1 {
		return RoiMonthKey{Year: k.Year - 1, Month: 12}
	}
	return RoiMonthKey{Year: k.Year, Month: k.Month - 1}
}

// LastYear is the same month one year earlier.
func (k RoiMonthKey) LastYear() RoiMonthKey {
	return RoiMonthKey{Year: k.Year - 1, Month: k.Month}
}

// RoiLiftResult is the standard baseline, lift and ROMI for one chain-month.
type RoiLiftResult struct {
	Available            bool
	Method               string
	BaselineSalesEGP     float64
	OrganicYoYRatio      float64
	OrganicMonthsUsed    int
	IncrementalLiftEGP   float64
	LiftVsBaselinePct    float64
	RomiMultiple         *float64
	NetRoiPct            *float64
	MethodAR             string
	UnavailableMessageAR string
}

func ptrFloat(v float64) *float64 { return &v }

// ComputeRoiLift returns expected sales without the campaign (seasonal YoY
// baseline), incremental lift (which may be negative), ROMI = lift/spend and
// Net ROI%.
//
// Baseline = last-year same-month Sell-Out when that figure is available.
// When it is missing, ROMI is unavailable and the UI shows «—» with
// «لا توجد بيانات للعام السابق». salesByMonth / campaignMonths are accepted
// for call-site compatibility but are not used by this method.
func ComputeRoiLift(currentSales, lastYearSameMonth, spend float64, target RoiMonthKey, salesByMonth map[RoiMonthKey]float64, campaignMonths map[RoiMonthKey]bool) RoiLiftResult {
	_ = target
	_ = salesByMonth
	_ = campaignMonths

	unavailable := RoiLiftResult{
		Available:            false,
		Method:               RoiBaselineMethodUnavailable,
		MethodAR:             RoiNoLastYearAR,
		UnavailableMessageAR: RoiNoLastYearAR,
	}

	if lastYearSameMonth <= 0 {
		return unavailable
	}

	baseline := lastYearSameMonth
	lift := currentSales - baseline
	var liftPct float64
	if baseline > 0 {
		liftPct = lift / baseline * 100
	}
	out := RoiLiftResult{
		Available:          true,
		Method:             RoiBaselineMethodYoySeasonal,
		BaselineSalesEGP:   baseline,
		OrganicYoYRatio:    1,
		OrganicMonthsUsed:  0,
		IncrementalLiftEGP: lift,
		LiftVsBaselinePct:  liftPct,
		MethodAR:           RoiYoySeasonalMethodAR,
	}
	if spend > 0 {
		romi := lift / spend
		net := (lift - spend) / spend * 100
		out.RomiMultiple = &romi
		out.NetRoiPct = &net
	}
	return out
}
