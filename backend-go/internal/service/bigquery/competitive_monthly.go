package bigquery

import (
	"fmt"
	"math"
	"sort"
	"strconv"
	"strings"

	"github.com/tashil/data-sharing/backend/internal/domain"
)

// CompetitiveMonthPoint is one barcode's weighted average shelf price for one calendar month.
type CompetitiveMonthPoint struct {
	MonthKey   string  `json:"month_key"` // YYYY-MM
	Month      int     `json:"month"`     // 1..12
	UnitPrice  float64 `json:"unit_price"`
	Units      int     `json:"units"`
	NetRevenue float64 `json:"net_revenue"`
}

// CompetitiveMonthlyItem is the per-barcode series used by the Compare page.
type CompetitiveMonthlyItem struct {
	Barcode string                  `json:"barcode"`
	Months  []CompetitiveMonthPoint `json:"months"`
}

// CompetitiveMonthlyResult is the server-side aggregate for Compare (no raw row paging).
type CompetitiveMonthlyResult struct {
	Year   int                      `json:"year"`
	Months []int                    `json:"months"` // distinct months 1..12 with data, ascending
	Items  []CompetitiveMonthlyItem `json:"items"`
	Source string                   `json:"source,omitempty"` // memory | bigquery
}

// AggregateCompetitiveMonthly builds barcode × month average unit prices from Sell-Out facts.
// Matches Flutter aggregateLiveMonthlyByBarcode: revenue = unit_price*qty (or net_revenue),
// unit_price = revenue/units. Filters mirror GetSellOutRecords (tenant, chain, supplier, dates).
func AggregateCompetitiveMonthly(facts []domain.SellOutFact, tenantID string, filter RecordFilter) CompetitiveMonthlyResult {
	type agg struct {
		rev   float64
		units int
	}
	byBarcode := map[string]map[string]*agg{} // barcode -> YYYY-MM -> agg
	monthSet := map[int]bool{}

	supFilter := strings.TrimSpace(filter.Supplier)
	start := strings.TrimSpace(filter.StartDate)
	end := strings.TrimSpace(filter.EndDate)
	chain := strings.TrimSpace(filter.RetailerChain)

	for i := range facts {
		r := facts[i]
		if !matchTenant(r.TenantID, tenantID) {
			continue
		}
		if supFilter == "" || strings.EqualFold(supFilter, "own") || supFilter == "أصناف الشركة فقط" {
			if !isOwnRecord(r) {
				continue
			}
		} else if !strings.EqualFold(supFilter, "all") && !strings.EqualFold(supFilter, "all_market") &&
			supFilter != "الكل" && supFilter != "السوق الكامل (شامل المنافسين)" {
			if !strings.EqualFold(strings.TrimSpace(r.Supplier), supFilter) {
				continue
			}
		}
		if chain != "" && chain != "all" && chain != "الكل" {
			if !strings.EqualFold(r.RetailerChain, chain) {
				continue
			}
		}
		if start != "" && r.TransactionDate < start {
			continue
		}
		if end != "" && r.TransactionDate > end {
			continue
		}
		barcode := strings.TrimSpace(r.Barcode)
		if barcode == "" || len(r.TransactionDate) < 7 {
			continue
		}
		qty := r.QuantitySold
		if qty <= 0 && r.UnitPrice <= 0 {
			continue
		}
		monthKey := r.TransactionDate[:7]
		mo, err := strconv.Atoi(r.TransactionDate[5:7])
		if err != nil || mo < 1 || mo > 12 {
			continue
		}
		monthSet[mo] = true
		revAdd := r.NetRevenue
		if r.UnitPrice > 0 {
			revAdd = r.UnitPrice * float64(qty)
		}
		bm := byBarcode[barcode]
		if bm == nil {
			bm = map[string]*agg{}
			byBarcode[barcode] = bm
		}
		a := bm[monthKey]
		if a == nil {
			a = &agg{}
			bm[monthKey] = a
		}
		a.rev += revAdd
		a.units += qty
	}

	months := make([]int, 0, len(monthSet))
	for m := range monthSet {
		months = append(months, m)
	}
	sort.Ints(months)

	barcodes := make([]string, 0, len(byBarcode))
	for b := range byBarcode {
		barcodes = append(barcodes, b)
	}
	sort.Strings(barcodes)

	items := make([]CompetitiveMonthlyItem, 0, len(barcodes))
	for _, barcode := range barcodes {
		keys := make([]string, 0, len(byBarcode[barcode]))
		for k := range byBarcode[barcode] {
			keys = append(keys, k)
		}
		sort.Strings(keys)
		pts := make([]CompetitiveMonthPoint, 0, len(keys))
		for _, mk := range keys {
			a := byBarcode[barcode][mk]
			mo, _ := strconv.Atoi(mk[5:7])
			price := 0.0
			if a.units > 0 {
				price = math.Round((a.rev/float64(a.units))*100) / 100
			} else {
				price = math.Round(a.rev*100) / 100
			}
			if price <= 0 && a.units <= 0 {
				continue
			}
			pts = append(pts, CompetitiveMonthPoint{
				MonthKey:   mk,
				Month:      mo,
				UnitPrice:  price,
				Units:      a.units,
				NetRevenue: math.Round(a.rev*100) / 100,
			})
		}
		if len(pts) == 0 {
			continue
		}
		items = append(items, CompetitiveMonthlyItem{Barcode: barcode, Months: pts})
	}

	year := 0
	if len(start) >= 4 {
		year, _ = strconv.Atoi(start[:4])
	}
	return CompetitiveMonthlyResult{Year: year, Months: months, Items: items, Source: "memory"}
}

// CompetitiveMonthlyYearWindow returns the inclusive date window for a calendar year
// (month=0 → full year). year<=0 uses an open window (no date filter).
func CompetitiveMonthlyYearWindow(year int) (start, end string) {
	if year <= 0 {
		return "", ""
	}
	return fmt.Sprintf("%04d-01-01", year), fmt.Sprintf("%04d-12-31", year)
}

// CompetitiveMonthly aggregates Compare series from the in-memory fact set (single pass, no paging).
func (c *Client) CompetitiveMonthly(tenantID string, filter RecordFilter) CompetitiveMonthlyResult {
	c.ensureTenantSeeded(tenantID)
	c.mu.RLock()
	defer c.mu.RUnlock()
	res := AggregateCompetitiveMonthly(c.records, tenantID, filter)
	res.Source = "memory"
	return res
}
