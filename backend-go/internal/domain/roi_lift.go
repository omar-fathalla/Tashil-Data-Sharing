package domain

import "strconv"

// Incremental-lift / ROMI calculation used by GET /trade-marketing/roi
// and mirrored in the Flutter computeRoiLift helper. No MoM/YoY cherry-pick.

const (
	RoiOrganicLookbackMonths = 12
	RoiOrganicWindow         = 3

	RoiBaselineMethodYoyTrend        = "yoy_trend"
	RoiBaselineMethodPriorOrganicAvg = "prior_organic_avg"
	RoiBaselineMethodUnavailable     = "unavailable"

	RoiBaselineUnavailableAR = "لا يمكن حساب العائد: لا توجد بيانات أساس كافية"
	RoiLiftMethodExplainerAR = "العائد = الزيادة عن المبيعات المتوقعة بدون الحملة ÷ المصروف. المبيعات المتوقعة = مبيعات نفس الشهر العام السابق × متوسط النمو العضوي للسلسلة في الأشهر بدون حملات، أو متوسط تلك الأشهر إذا لم تتوفر بيانات العام السابق."
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

// YoyTrendMethodAR is the Arabic method line when last-year sales exist.
func YoyTrendMethodAR(monthsUsed int) string {
	if monthsUsed <= 0 {
		return "الأساس = مبيعات نفس الشهر العام السابق (لا يوجد أشهر عضوية كافية لحساب الاتجاه)"
	}
	return "الأساس = مبيعات نفس الشهر العام السابق × متوسط النمو العضوي لآخر " + strconv.Itoa(monthsUsed) + " أشهر بدون حملات"
}

// PriorOrganicMethodAR is the Arabic method line when last-year sales are missing.
func PriorOrganicMethodAR(monthsUsed int) string {
	return "الأساس = متوسط مبيعات آخر " + strconv.Itoa(monthsUsed) + " أشهر بدون حملات (لا توجد بيانات للعام السابق)"
}

func ptrFloat(v float64) *float64 { return &v }

// ComputeRoiLift returns expected sales without the campaign, incremental
// lift (which may be negative), ROMI = lift/spend and Net ROI%.
//
// When last-year same-month sales exist, baseline = that figure times the
// average YoY ratio of up to 3 prior non-campaign months (lookback 12).
// If no organic months are available the ratio is 1 (raw seasonal baseline).
// When last-year sales are missing, baseline is the average of up to 3
// prior non-campaign months. Otherwise the baseline is unavailable.
func ComputeRoiLift(currentSales, lastYearSameMonth, spend float64, target RoiMonthKey, salesByMonth map[RoiMonthKey]float64, campaignMonths map[RoiMonthKey]bool) RoiLiftResult {
	finish := func(method string, baseline float64, organicRatio float64, monthsUsed int, methodAR string) RoiLiftResult {
		lift := currentSales - baseline
		var liftPct float64
		if baseline > 0 {
			liftPct = lift / baseline * 100
		}
		out := RoiLiftResult{
			Available:          true,
			Method:             method,
			BaselineSalesEGP:   baseline,
			OrganicYoYRatio:    organicRatio,
			OrganicMonthsUsed:  monthsUsed,
			IncrementalLiftEGP: lift,
			LiftVsBaselinePct:  liftPct,
			MethodAR:           methodAR,
		}
		if spend > 0 {
			romi := lift / spend
			net := (lift - spend) / spend * 100
			out.RomiMultiple = &romi
			out.NetRoiPct = &net
		}
		return out
	}

	unavailable := RoiLiftResult{
		Available:            false,
		Method:               RoiBaselineMethodUnavailable,
		MethodAR:             RoiBaselineUnavailableAR,
		UnavailableMessageAR: RoiBaselineUnavailableAR,
	}

	if lastYearSameMonth > 0 {
		ratios := make([]float64, 0, RoiOrganicWindow)
		cursor := target.Prev()
		for i := 0; i < RoiOrganicLookbackMonths && len(ratios) < RoiOrganicWindow; i++ {
			if !campaignMonths[cursor] {
				sales := salesByMonth[cursor]
				ly := salesByMonth[cursor.LastYear()]
				if sales > 0 && ly > 0 {
					ratios = append(ratios, sales/ly)
				}
			}
			cursor = cursor.Prev()
		}
		monthsUsed := len(ratios)
		ratio := 1.0
		if monthsUsed > 0 {
			var sum float64
			for _, r := range ratios {
				sum += r
			}
			ratio = sum / float64(monthsUsed)
		}
		return finish(RoiBaselineMethodYoyTrend, lastYearSameMonth*ratio, ratio, monthsUsed, YoyTrendMethodAR(monthsUsed))
	}

	organic := make([]float64, 0, RoiOrganicWindow)
	cursor := target.Prev()
	for i := 0; i < RoiOrganicLookbackMonths && len(organic) < RoiOrganicWindow; i++ {
		if !campaignMonths[cursor] {
			if sales := salesByMonth[cursor]; sales > 0 {
				organic = append(organic, sales)
			}
		}
		cursor = cursor.Prev()
	}
	if len(organic) == 0 {
		return unavailable
	}
	var sum float64
	for _, s := range organic {
		sum += s
	}
	monthsUsed := len(organic)
	return finish(RoiBaselineMethodPriorOrganicAvg, sum/float64(monthsUsed), 0, monthsUsed, PriorOrganicMethodAR(monthsUsed))
}
