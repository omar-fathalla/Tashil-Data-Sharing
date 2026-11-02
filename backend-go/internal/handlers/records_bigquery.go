package handlers

import (
	"context"
	"log"
	"math"
	"net/http"
	"sort"
	"strings"
	"time"

	"github.com/tashil/data-sharing/backend/internal/domain"
	"github.com/tashil/data-sharing/backend/internal/service/bigquery"
	"github.com/tashil/data-sharing/backend/internal/service/bqsink"
)

// recordsBQTimeout bounds the BigQuery path; past it the request falls back to the in-memory path.
const recordsBQTimeout = 8 * time.Second

// WithRecordsQuerier lets /analytics/records compute totals, SKU summaries and the page in BigQuery.
// A nil querier keeps the in-memory path.
func (h *AnalyticsHandler) WithRecordsQuerier(q bqsink.RecordsQuerier) *AnalyticsHandler {
	h.records = q
	return h
}

func filterIsAll(s string) bool {
	s = strings.TrimSpace(s)
	return s == "" || strings.EqualFold(s, "all") || s == "الكل"
}

// recordsFromBigQuery answers the explorer from BigQuery. ok=false means "use the in-memory path":
// no querier, a filter that needs Go-side normalisation (search text, category), a BigQuery error
// or timeout, or an empty BigQuery result (memory may still hold rows, e.g. right after an upload).
func (h *AnalyticsHandler) recordsFromBigQuery(ctx context.Context, tenantID string, f bigquery.RecordFilter, limit, offset int) (*PaginatedRecordsResponse, bool) {
	if h.records == nil || strings.TrimSpace(f.SearchQuery) != "" || !filterIsAll(f.Category) {
		return nil, false
	}
	c, cancel := context.WithTimeout(ctx, recordsBQTimeout)
	defer cancel()
	res, err := h.records.QuerySellOutRecords(c, bqsink.RecordsQuery{
		TenantID: tenantID, Chain: f.RetailerChain, Store: f.StoreID, Supplier: f.Supplier,
		StartDate: f.StartDate, EndDate: f.EndDate, Limit: limit, Offset: offset,
	})
	if err != nil {
		log.Printf("WARN [records] BigQuery path failed, serving from memory: %v", err)
		return nil, false
	}
	if res.Totals.TotalCount == 0 {
		return nil, false
	}
	return buildRecordsResponseFromBQ(res, limit, offset), true
}

func buildRecordsResponseFromBQ(res *bqsink.RecordsResult, limit, offset int) *PaginatedRecordsResponse {
	t := res.Totals
	summaries := make([]domain.SellOutSKUSummary, 0, len(res.SKUs))
	for _, b := range res.SKUs {
		s := domain.SellOutSKUSummary{
			ItemCode:             b.ItemCode,
			Barcode:              b.Barcode,
			SKUName:              b.SKUName,
			RetailerRawSKUName:   b.RetailerRawSKUName,
			Brand:                domain.InferBrandFromItemName(b.SKUName, domain.NormalizeProductCategory(b.Category)),
			Category:             domain.NormalizeProductCategory(b.Category),
			ItemType:             b.ItemType,
			UnitsPerCarton:       b.UnitsPerCarton,
			OfficialConsumerRSP:  b.RecommendedPrice,
			CartonPriceInclVAT:   b.CartonPriceInclVAT,
			FactoryUnitCost:      b.FactoryUnitCost,
			NetCartonInvoiceCost: b.NetCartonInvoiceCost,
			InvoiceDiscountPct:   b.InvoiceDiscountPct,
			TotalUnitsSold:       int(b.UnitsSold),
			TotalCartonsSold:     b.CartonsSold,
			TotalNetRevenue:      b.NetRevenue,
			TotalFactoryCost:     b.FactoryCost,
			RetailerGrossProfit:  b.GrossProfit,
			ActiveStoresCount:    b.Stores,
		}
		finalizeSKUSummary(&s)
		summaries = append(summaries, s)
	}
	sort.Slice(summaries, func(i, j int) bool {
		if summaries[i].TotalNetRevenue != summaries[j].TotalNetRevenue {
			return summaries[i].TotalNetRevenue > summaries[j].TotalNetRevenue
		}
		return summaries[i].SKUName < summaries[j].SKUName
	})
	page := res.Page
	if page == nil {
		page = []domain.SellOutFact{}
	}
	for i := range page {
		page[i].Category = domain.NormalizeProductCategory(page[i].Category)
	}
	avgMargin := 0.0
	if t.MatchedRevForMargin > 0 {
		avgMargin = math.Round(((t.GrossProfit/t.MatchedRevForMargin)*100)*100) / 100
	}
	return &PaginatedRecordsResponse{
		Records:                  page,
		TotalCount:               t.TotalCount,
		Limit:                    limit,
		Offset:                   offset,
		TotalNetRevenue:          math.Round(t.NetRevenue*100) / 100,
		TotalUnitsSold:           int(t.UnitsSold),
		TotalCartonsSold:         math.Round(t.CartonsSold*100) / 100,
		TotalFactoryCost:         math.Round(t.FactoryCost*100) / 100,
		TotalRetailerGrossProfit: math.Round(t.GrossProfit*100) / 100,
		AvgRetailerMarginPct:     avgMargin,
		ActiveStoresCount:        t.Stores,
		ActiveSKUsCount:          t.SKUs,
		MatchedSKUsCount:         t.MatchedSKUs,
		MinDate:                  t.MinDate,
		MaxDate:                  t.MaxDate,
		TopBranchName:            t.TopBranchName,
		TopBranchRevenue:         math.Round(t.TopBranchRevenue*100) / 100,
		SKUSummaries:             summaries,
	}
}

func setRecordsSource(w http.ResponseWriter, source string) {
	w.Header().Set("X-Records-Source", source)
}

// finalizeSKUSummary derives averages, cartons, cost, margin and price status from a summed SKU bucket.
func finalizeSKUSummary(s *domain.SellOutSKUSummary) {
	if s.TotalUnitsSold > 0 {
		s.AvgSellingPrice = math.Round((s.TotalNetRevenue/float64(s.TotalUnitsSold))*100) / 100
	}
	if s.UnitsPerCarton > 0 && s.TotalUnitsSold > 0 {
		s.TotalCartonsSold = math.Round((float64(s.TotalUnitsSold)/float64(s.UnitsPerCarton))*100) / 100
	} else {
		s.TotalCartonsSold = math.Round(s.TotalCartonsSold*100) / 100
	}
	s.TotalNetRevenue = math.Round(s.TotalNetRevenue*100) / 100
	if s.FactoryUnitCost > 0 && s.TotalUnitsSold > 0 {
		s.TotalFactoryCost = math.Round((float64(s.TotalUnitsSold)*s.FactoryUnitCost)*100) / 100
		s.RetailerGrossProfit = math.Round((s.TotalNetRevenue-s.TotalFactoryCost)*100) / 100
		if s.TotalNetRevenue > 0 {
			s.RetailerMarginPct = math.Round(((s.RetailerGrossProfit/s.TotalNetRevenue)*100)*100) / 100
		}
	} else {
		s.TotalFactoryCost = math.Round(s.TotalFactoryCost*100) / 100
		s.RetailerGrossProfit = math.Round(s.RetailerGrossProfit*100) / 100
	}
	if s.OfficialConsumerRSP > 0 && s.AvgSellingPrice > 0 {
		s.PriceDeltaPct = math.Round((((s.AvgSellingPrice-s.OfficialConsumerRSP)/s.OfficialConsumerRSP)*100)*100) / 100
	}
	switch {
	case s.FactoryUnitCost > 0 && s.AvgSellingPrice > 0 && s.AvgSellingPrice < s.FactoryUnitCost:
		s.PriceStatus = "below_cost"
	case s.PriceDeltaPct <= -5.0:
		s.PriceStatus = "promo_discount"
	case s.PriceDeltaPct >= 5.0:
		s.PriceStatus = "above_rsp"
	default:
		s.PriceStatus = "compliant"
	}
}
