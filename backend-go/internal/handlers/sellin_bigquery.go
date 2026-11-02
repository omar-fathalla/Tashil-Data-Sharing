package handlers

import (
	"context"
	"fmt"
	"log"
	"math"
	"sort"
	"strings"

	"github.com/tashil/data-sharing/backend/internal/domain"
	"github.com/tashil/data-sharing/backend/internal/service/bigquery"
	"github.com/tashil/data-sharing/backend/internal/service/bqsink"
)

// SellInTotalsQuerier computes Sell-In totals and month/chain/brand groups in BigQuery.
type SellInTotalsQuerier interface {
	QuerySellInTotals(ctx context.Context, q bqsink.SellInTotalsQuery) (*bqsink.SellInTotalsResult, error)
}

// WithSellInTotalsQuerier moves /analytics/sell-in-records totals and /analytics/sell-in-monthly to
// BigQuery. A nil querier keeps the in-memory path.
func (h *AnalyticsHandler) WithSellInTotalsQuerier(q SellInTotalsQuerier) *AnalyticsHandler {
	h.sellIn = q
	return h
}

func sellInRules() []bqsink.SellInChainRule {
	rules := bigquery.ActiveSellInChainRules()
	out := make([]bqsink.SellInChainRule, len(rules))
	for i, r := range rules {
		out[i] = bqsink.SellInChainRule{Needle: r[0], Chain: r[1]}
	}
	return out
}

// sellInFilterNeedsMemory is true for filters the BigQuery path does not implement (free-text search,
// region, sector, brand); those stay on the in-memory path.
func sellInFilterNeedsMemory(f bigquery.SellInRecordFilter) bool {
	return strings.TrimSpace(f.SearchQuery) != "" || !filterIsAll(f.RegionCode) || !filterIsAll(f.Sector) || !filterIsAll(f.Brand)
}

// sellInEnricher re-runs the in-memory Sell-In enrichment on rows read from BigQuery.
type sellInEnricher interface {
	EnrichSellInRecords(tenantID string, recs []domain.SellInRecord) []domain.SellInRecord
}

func (h *AnalyticsHandler) querySellInTotals(ctx context.Context, tenantID string, f bigquery.SellInRecordFilter) (*bqsink.SellInTotalsResult, bool) {
	if h.sellIn == nil || sellInFilterNeedsMemory(f) {
		return nil, false
	}
	c, cancel := context.WithTimeout(ctx, recordsBQTimeout)
	defer cancel()
	res, err := h.sellIn.QuerySellInTotals(c, bqsink.SellInTotalsQuery{
		TenantID: tenantID, Chain: f.RetailerChain, Year: f.Year, Month: f.Month, Rules: sellInRules(),
		Limit: f.Limit, Offset: f.Offset,
	})
	if err != nil {
		log.Printf("WARN [sell-in] BigQuery totals failed, serving from memory: %v", err)
		return nil, false
	}
	if res.Totals.Count == 0 {
		return nil, false // memory may hold rows not yet in BigQuery (e.g. right after an upload)
	}
	return res, true
}

// sellInRecordsFromBigQuery answers sell-in-records with BigQuery totals and an in-memory page.
func (h *AnalyticsHandler) sellInRecordsFromBigQuery(ctx context.Context, tenantID string, f bigquery.SellInRecordFilter) (*PaginatedSellInRecordsResponse, bool) {
	enr, canEnrich := h.bqRepo.(sellInEnricher)
	if !canEnrich {
		return nil, false
	}
	res, ok := h.querySellInTotals(ctx, tenantID, f)
	if !ok {
		return nil, false
	}
	// Page rows come from BigQuery in GetSellInRecords order and get the same Go enrichment.
	page := enr.EnrichSellInRecords(tenantID, res.Page)
	if page == nil {
		page = []domain.SellInRecord{}
	}
	resp := buildSellInRecordsResponse(res.Totals, page, int(res.Totals.Count), f.Limit, f.Offset)
	resp.ByChain, resp.ByBrand = sellInBreakdowns(res.Groups)
	return &resp, true
}

// sellInTotalsFromRecords sums in-memory rows with the same rules as the BigQuery query. Rows without
// an official list price contribute 0 to the list value (no invented 10% discount).
func sellInTotalsFromRecords(records []domain.SellInRecord) bqsink.SellInTotals {
	var t bqsink.SellInTotals
	matched := make(map[string]bool)
	for _, rec := range records {
		t.Count++
		t.NetValue += rec.NetValueEGP
		t.Cases += rec.NetQtyCases
		t.Units += int64(rec.TotalUnitsSupplied)
		t.Tons += rec.WeightTons
		t.Expected += rec.ExpectedValueEGP
		vatRate := rec.VATRate
		if vatRate <= 0 {
			vatRate = 0.14
		}
		listExcl := rec.OfficialListValueExclEGP
		gross := rec.GrossValueInclVATEGP
		if gross == 0 && rec.NetValueEGP != 0 {
			gross = rec.NetValueEGP * (1.0 + vatRate)
		}
		vat := rec.VATAmountEGP
		if vat == 0 && gross != 0 {
			vat = gross - rec.NetValueEGP
		}
		disc := rec.DiscountGrantedEGP
		if disc == 0 && listExcl > rec.NetValueEGP && rec.NetValueEGP > 0 {
			disc = listExcl - rec.NetValueEGP
		}
		t.ListExcl += listExcl
		t.ListIncl += listExcl * (1.0 + vatRate)
		if listExcl > 0 {
			t.NetWithList += rec.NetValueEGP
		}
		t.Discount += disc
		t.VAT += vat
		t.Gross += gross
		if rec.ItemCode != "" {
			matched[rec.ItemName] = true
		}
	}
	t.MatchedSKUs = int64(len(matched))
	return t
}

// sellInEffectiveDiscountPct is the discount over rows that have an official list price; 0 when none.
func sellInEffectiveDiscountPct(t bqsink.SellInTotals) float64 {
	if t.ListExcl <= 0 {
		return 0
	}
	p := math.Round(((t.ListExcl-t.NetWithList)/t.ListExcl)*1000) / 10
	if p < 0 {
		return 0
	}
	return p
}

func round2(v float64) float64 { return math.Round(v*100) / 100 }

func buildSellInRecordsResponse(t bqsink.SellInTotals, page []domain.SellInRecord, total, limit, offset int) PaginatedSellInRecordsResponse {
	return PaginatedSellInRecordsResponse{
		Records:                     page,
		TotalCount:                  total,
		Limit:                       limit,
		Offset:                      offset,
		TotalValueEGP:               round2(t.NetValue),
		TotalCases:                  round2(t.Cases),
		TotalUnitsPieces:            int(t.Units),
		TotalWeightTons:             math.Round(t.Tons*1000) / 1000,
		TotalExpectedEGP:            round2(t.Expected),
		TotalOfficialListExclVATEGP: round2(t.ListExcl),
		TotalOfficialListInclVATEGP: round2(t.ListIncl),
		TotalDiscountGrantedEGP:     round2(t.Discount),
		EffectiveDiscountPct:        sellInEffectiveDiscountPct(t),
		TotalNetExclVATEGP:          round2(t.NetValue),
		TotalVAT14EGP:               round2(t.VAT),
		TotalGrossInclVATEGP:        round2(t.Gross),
		MatchedCatalogSKUsCount:     int(t.MatchedSKUs),
	}
}

// SellInBreakdownItem is the Sell-In net value / cases for one chain or brand.
type SellInBreakdownItem struct {
	Key         string  `json:"key"`
	NetValueEGP float64 `json:"net_value_egp"`
	Cases       float64 `json:"cases"`
	Rows        int64   `json:"rows"`
}

func sellInBreakdowns(groups []bqsink.SellInGroupRow) (byChain, byBrand []SellInBreakdownItem) {
	sum := func(key func(g bqsink.SellInGroupRow) string) []SellInBreakdownItem {
		m := map[string]*SellInBreakdownItem{}
		for _, g := range groups {
			k := key(g)
			it := m[k]
			if it == nil {
				it = &SellInBreakdownItem{Key: k}
				m[k] = it
			}
			it.NetValueEGP += g.NetValue
			it.Cases += g.Cases
			it.Rows += g.Count
		}
		out := make([]SellInBreakdownItem, 0, len(m))
		for _, it := range m {
			it.NetValueEGP, it.Cases = round2(it.NetValueEGP), round2(it.Cases)
			out = append(out, *it)
		}
		sort.Slice(out, func(i, j int) bool {
			if out[i].NetValueEGP != out[j].NetValueEGP {
				return out[i].NetValueEGP > out[j].NetValueEGP
			}
			return out[i].Key < out[j].Key
		})
		return out
	}
	return sum(func(g bqsink.SellInGroupRow) string { return g.Chain }),
		sum(func(g bqsink.SellInGroupRow) string { return g.Brand })
}

// sellInMonthlyFromGroups folds BigQuery groups into the monthly-by-chain points.
func sellInMonthlyFromGroups(groups []bqsink.SellInGroupRow) []SellInMonthlyChainPoint {
	type key struct{ month, chain string }
	sums := map[key]float64{}
	for _, g := range groups {
		if g.Year <= 0 || g.Month < 1 || g.Month > 12 || g.Chain == "" {
			continue
		}
		sums[key{fmt.Sprintf("%04d-%02d", g.Year, g.Month), g.Chain}] += g.NetValue
	}
	points := make([]SellInMonthlyChainPoint, 0, len(sums))
	for k, v := range sums {
		points = append(points, SellInMonthlyChainPoint{MonthKey: k.month, RetailerChain: k.chain, NetValueEGP: round2(v)})
	}
	sort.Slice(points, func(i, j int) bool {
		if points[i].MonthKey != points[j].MonthKey {
			return points[i].MonthKey < points[j].MonthKey
		}
		return points[i].RetailerChain < points[j].RetailerChain
	})
	return points
}
