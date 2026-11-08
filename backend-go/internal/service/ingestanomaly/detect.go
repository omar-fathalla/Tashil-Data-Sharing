// Package ingestanomaly implements Gemini Phase B post-parse anomaly detection
// (negatives, duplicates, unit-price outliers, MoM spikes) on normalized records.
// It only appends advisory IngestionAnomaly rows; it never writes durable state.
package ingestanomaly

import (
	"fmt"
	"math"
	"sort"
	"strings"

	"github.com/tashil/data-sharing/backend/internal/domain"
)

// Issue types emitted by Phase B (must stay aligned with guardrails.allowedAnomalyTypes).
const (
	TypeNegativeSales    = "negative_sales"
	TypeDuplicateRow     = "duplicate_row"
	TypeUnitPriceOutlier = "unit_price_outlier"
	TypeMomSpike         = "mom_spike"
)

const (
	maxAnomalies         = 250
	momSpikeUpRatio      = 3.0  // MoM increase ≥ 300% (4× prior) for same barcode+store
	momSpikeDownRatio    = 0.75 // MoM drop ≥ 75% vs prior month (non-negative revenue)
	outlierMADMultiplier = 5.0  // unit price beyond median ± 5×MAD
	minOutlierSamples    = 8    // need enough prices before MAD is meaningful
)

// Detect appends Phase B anomalies for records onto existing (deduped by row+type).
// Row numbers are 1-based indexes into records (same convention as the ingestion processor).
func Detect(records []domain.NormalizedRecord, existing []domain.IngestionAnomaly) []domain.IngestionAnomaly {
	out := append([]domain.IngestionAnomaly(nil), existing...)
	if len(records) == 0 {
		return out
	}
	appendAnomaly := func(a domain.IngestionAnomaly) {
		if len(out) >= maxAnomalies {
			return
		}
		for _, e := range out {
			if e.RowNumber == a.RowNumber && e.IssueType == a.IssueType {
				return
			}
		}
		out = append(out, a)
	}

	detectNegatives(records, appendAnomaly)
	detectDuplicates(records, appendAnomaly)
	detectUnitPriceOutliers(records, appendAnomaly)
	detectMomSpikes(records, appendAnomaly)
	return out
}

func detectNegatives(records []domain.NormalizedRecord, appendAnomaly func(domain.IngestionAnomaly)) {
	for i, rec := range records {
		if rec.NetRevenue >= 0 && rec.QuantitySold >= 0 {
			continue
		}
		row := i + 1
		appendAnomaly(domain.IngestionAnomaly{
			RowNumber:   row,
			IssueType:   TypeNegativeSales,
			Description: fmt.Sprintf("Negative sales detected in row %d (Qty: %d, Rev: %.2f)", row, rec.QuantitySold, rec.NetRevenue),
		})
	}
}

func detectDuplicates(records []domain.NormalizedRecord, appendAnomaly func(domain.IngestionAnomaly)) {
	seen := make(map[string]int, len(records)) // key → first 1-based row
	for i, rec := range records {
		key := duplicateKey(rec)
		row := i + 1
		if first, ok := seen[key]; ok {
			appendAnomaly(domain.IngestionAnomaly{
				RowNumber:   row,
				IssueType:   TypeDuplicateRow,
				Description: fmt.Sprintf("Duplicate of row %d: same barcode/store/date/qty/revenue in row %d", first, row),
			})
			continue
		}
		seen[key] = row
	}
}

func duplicateKey(rec domain.NormalizedRecord) string {
	store := strings.TrimSpace(rec.ResolvedStoreID)
	if store == "" {
		store = strings.TrimSpace(rec.RawStoreName)
	}
	return strings.Join([]string{
		strings.TrimSpace(rec.Barcode),
		store,
		strings.TrimSpace(rec.TransactionDate),
		fmt.Sprintf("%d", rec.QuantitySold),
		fmt.Sprintf("%.4f", rec.NetRevenue),
	}, "|")
}

type pricedSample struct {
	idx   int
	price float64
}

func detectUnitPriceOutliers(records []domain.NormalizedRecord, appendAnomaly func(domain.IngestionAnomaly)) {
	// Group by barcode so products with different normal prices do not flag each other.
	byProduct := map[string][]pricedSample{}
	for i, rec := range records {
		bc := strings.TrimSpace(rec.Barcode)
		if bc == "" {
			continue
		}
		p := unitPrice(rec)
		if p <= 0 || math.IsNaN(p) || math.IsInf(p, 0) {
			continue
		}
		byProduct[bc] = append(byProduct[bc], pricedSample{idx: i, price: p})
	}
	for _, samples := range byProduct {
		flagProductPriceOutliers(samples, appendAnomaly)
	}
}

func flagProductPriceOutliers(samples []pricedSample, appendAnomaly func(domain.IngestionAnomaly)) {
	if len(samples) < minOutlierSamples {
		return
	}
	prices := make([]float64, len(samples))
	for i, s := range samples {
		prices[i] = s.price
	}
	med := median(prices)
	mad := medianAbsDev(prices, med)
	// When MAD is 0 (tight cluster), fall back to a relative gate vs median.
	lo, hi := med, med
	if mad > 0 {
		lo = med - outlierMADMultiplier*mad
		hi = med + outlierMADMultiplier*mad
	} else if med > 0 {
		lo = med / 10
		hi = med * 10
	} else {
		return
	}
	for _, s := range samples {
		if s.price >= lo && s.price <= hi {
			continue
		}
		row := s.idx + 1
		appendAnomaly(domain.IngestionAnomaly{
			RowNumber:   row,
			IssueType:   TypeUnitPriceOutlier,
			Description: fmt.Sprintf("Unit price %.2f in row %d is an outlier vs product median %.2f (MAD %.2f)", s.price, row, med, mad),
		})
	}
}

func unitPrice(rec domain.NormalizedRecord) float64 {
	if rec.UnitPrice > 0 {
		return rec.UnitPrice
	}
	if rec.QuantitySold > 0 {
		return rec.NetRevenue / float64(rec.QuantitySold)
	}
	return 0
}

func detectMomSpikes(records []domain.NormalizedRecord, appendAnomaly func(domain.IngestionAnomaly)) {
	type monthAgg struct {
		revenue float64
		rows    []int // 0-based indexes
	}
	// barcode|store → YYYY-MM → agg
	byKey := map[string]map[string]*monthAgg{}
	for i, rec := range records {
		month := yearMonth(rec.TransactionDate)
		if month == "" {
			continue
		}
		store := strings.TrimSpace(rec.ResolvedStoreID)
		if store == "" {
			store = strings.TrimSpace(rec.RawStoreName)
		}
		bc := strings.TrimSpace(rec.Barcode)
		if bc == "" || store == "" {
			continue
		}
		key := bc + "|" + store
		months := byKey[key]
		if months == nil {
			months = map[string]*monthAgg{}
			byKey[key] = months
		}
		agg := months[month]
		if agg == nil {
			agg = &monthAgg{}
			months[month] = agg
		}
		agg.revenue += rec.NetRevenue
		agg.rows = append(agg.rows, i)
	}

	for key, months := range byKey {
		if len(months) < 2 {
			continue
		}
		ordered := make([]string, 0, len(months))
		for m := range months {
			ordered = append(ordered, m)
		}
		sort.Strings(ordered)
		for i := 1; i < len(ordered); i++ {
			prevMonth, curMonth := ordered[i-1], ordered[i]
			if !monthsConsecutive(prevMonth, curMonth) {
				continue // skip gaps (e.g. Jan → Mar with Feb missing)
			}
			prev, cur := months[prevMonth], months[curMonth]
			if prev.revenue <= 0 {
				continue
			}
			change := (cur.revenue - prev.revenue) / prev.revenue
			dir := ""
			var pct float64
			switch {
			case change >= momSpikeUpRatio:
				dir, pct = "up", change*100
			case change <= -momSpikeDownRatio:
				dir, pct = "down", -change*100
			default:
				continue
			}
			// Flag the first contributing row of the spiked month (keeps anomaly count bounded).
			row := cur.rows[0] + 1
			appendAnomaly(domain.IngestionAnomaly{
				RowNumber: row,
				IssueType: TypeMomSpike,
				Description: fmt.Sprintf(
					"MoM spike %s %.0f%% for %s: %s revenue %.2f → %s %.2f",
					dir, pct, key, prevMonth, prev.revenue, curMonth, cur.revenue,
				),
			})
		}
	}
}

func yearMonth(txDate string) string {
	txDate = strings.TrimSpace(txDate)
	if len(txDate) < 7 {
		return ""
	}
	// Expect YYYY-MM-DD (or YYYY-MM…)
	if txDate[4] != '-' {
		return ""
	}
	return txDate[:7]
}

// monthsConsecutive reports whether b is exactly one calendar month after a (YYYY-MM).
func monthsConsecutive(a, b string) bool {
	ay, am, okA := parseYearMonth(a)
	by, bm, okB := parseYearMonth(b)
	if !okA || !okB {
		return false
	}
	am++
	if am > 12 {
		am = 1
		ay++
	}
	return ay == by && am == bm
}

func parseYearMonth(ym string) (year, month int, ok bool) {
	if len(ym) != 7 || ym[4] != '-' {
		return 0, 0, false
	}
	for _, c := range ym[:4] {
		if c < '0' || c > '9' {
			return 0, 0, false
		}
		year = year*10 + int(c-'0')
	}
	for _, c := range ym[5:] {
		if c < '0' || c > '9' {
			return 0, 0, false
		}
		month = month*10 + int(c-'0')
	}
	if month < 1 || month > 12 {
		return 0, 0, false
	}
	return year, month, true
}

func median(vals []float64) float64 {
	if len(vals) == 0 {
		return 0
	}
	cp := append([]float64(nil), vals...)
	sort.Float64s(cp)
	n := len(cp)
	if n%2 == 1 {
		return cp[n/2]
	}
	return (cp[n/2-1] + cp[n/2]) / 2
}

func medianAbsDev(vals []float64, med float64) float64 {
	devs := make([]float64, len(vals))
	for i, v := range vals {
		devs[i] = math.Abs(v - med)
	}
	return median(devs)
}
