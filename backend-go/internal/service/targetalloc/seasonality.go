package targetalloc

import "math"

// SeasonalShares turns prior-year monthly sales into 12 shares that sum to 1.
//
// Rule (approved):
//  1. M_avail = months with sales[m] > 0
//  2. If empty → equal 1/12
//  3. Else avg = sum(M_avail) / len(M_avail);
//     w[m] = sales[m]/avg for available months, else w[m] = 1;
//     share[m] = w[m] / 12  (sum(w) = 12 → shares sum to 1)
func SeasonalShares(sales [12]float64) [12]float64 {
	var avail []int
	var sum float64
	for i, v := range sales {
		if v > 0 {
			avail = append(avail, i)
			sum += v
		}
	}
	var out [12]float64
	if len(avail) == 0 {
		for i := range out {
			out[i] = 1.0 / 12.0
		}
		return out
	}
	avg := sum / float64(len(avail))
	if avg <= 0 {
		for i := range out {
			out[i] = 1.0 / 12.0
		}
		return out
	}
	var weights [12]float64
	for i := 0; i < 12; i++ {
		weights[i] = 1.0
	}
	for _, i := range avail {
		weights[i] = sales[i] / avg
	}
	for i := 0; i < 12; i++ {
		out[i] = weights[i] / 12.0
	}
	return out
}

// PickSeasonalShares prefers primary (e.g. units) when any month is positive, else fallback (e.g. revenue).
func PickSeasonalShares(primary, fallback [12]float64) [12]float64 {
	for _, v := range primary {
		if v > 0 {
			return SeasonalShares(primary)
		}
	}
	return SeasonalShares(fallback)
}

// ApportionByShare splits total across 12 months by share using largest-remainder on cents
// so the parts sum to total exactly (after /100).
func ApportionByShare(total float64, shares [12]float64) [12]float64 {
	weights := make([]int64, 12)
	for i, s := range shares {
		if s > 0 {
			weights[i] = centsOf(s * 1000) // extra precision before cents
		}
	}
	parts := Apportion(centsOf(total), weights)
	var out [12]float64
	for i, p := range parts {
		out[i] = float64(p) / 100
	}
	return out
}

// SharePct returns seasonality as a percentage with one decimal (e.g. 8.3).
func SharePct(share float64) float64 {
	return math.Round(share*1000) / 10
}
