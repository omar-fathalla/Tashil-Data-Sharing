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

func (h *AnalyticsHandler) querySellInTotals(ctx context.Context, tenantID string, f bigquery.SellInRecordFilter, profiles []bqsink.SellInChainProfile) (*bqsink.SellInTotalsResult, bool) {
	if h.sellIn == nil || sellInFilterNeedsMemory(f) {
		return nil, false
	}
	c, cancel := context.WithTimeout(ctx, recordsBQTimeout)
	defer cancel()
	res, err := h.sellIn.QuerySellInTotals(c, bqsink.SellInTotalsQuery{
		TenantID: tenantID, Chain: f.RetailerChain, Year: f.Year, Month: f.Month, Rules: sellInRules(),
		Profiles: profiles,
		Limit:    f.Limit, Offset: f.Offset,
	})
	if err != nil {
		log.Printf("WARN [sell-in] BigQuery totals failed, serving from memory: %v", err)
		return nil, false
	}
	if res.Totals.Count == 0 && h.memoryHasSellIn(tenantID, f) {
		return nil, false // memory holds rows not yet in BigQuery (e.g. right after an upload)
	}
	// Count == 0 with nothing local: an empty BigQuery answer (no wait for the in-memory load).
	return res, true
}

// chainProfileSource exposes the saved per-chain terms (VAT, invoice and extra discount).
type chainProfileSource interface {
	ChainDiscountProfilesSnapshot(ctx context.Context, tenantID string) []domain.ChainDiscountProfile
}

// sellInChainProfiles hands the saved chain terms to the BigQuery totals so they match the in-memory rows.
func (h *AnalyticsHandler) sellInChainProfiles(ctx context.Context, tenantID string) []bqsink.SellInChainProfile {
	src, ok := h.bqRepo.(chainProfileSource)
	if !ok {
		return nil
	}
	var out []bqsink.SellInChainProfile
	for _, p := range src.ChainDiscountProfilesSnapshot(ctx, tenantID) {
		cp := bqsink.SellInChainProfile{Chain: p.Chain, InvoiceDiscountPct: p.InvoiceDiscountPct, ExtraDiscountPct: p.AdditionalDiscountPct}
		if v, set := p.VATRate(); set {
			cp.VATRate = &v
		}
		out = append(out, cp)
	}
	return out
}

type sellInSnapshotReader interface {
	SellInRecordsSnapshot(tenantID string) []domain.SellInRecord
}

// memoryHasSellIn checks the current in-memory copy without waiting for the durable load.
func (h *AnalyticsHandler) memoryHasSellIn(tenantID string, f bigquery.SellInRecordFilter) bool {
	snap, ok := h.bqRepo.(sellInSnapshotReader)
	if !ok {
		return false
	}
	for _, r := range snap.SellInRecordsSnapshot(tenantID) {
		if f.Year > 0 && r.Year != f.Year || f.Month > 0 && r.MonthNum != f.Month {
			continue
		}
		if !filterIsAll(f.RetailerChain) && !strings.EqualFold(strings.TrimSpace(bigquery.ResolveSellInChain(r.CustomerName, r.RetailerChain)), strings.TrimSpace(f.RetailerChain)) {
			continue
		}
		return true
	}
	return false
}

// sellInRecordsFromBigQuery answers sell-in-records with BigQuery totals and an in-memory page.
func (h *AnalyticsHandler) sellInRecordsFromBigQuery(ctx context.Context, tenantID string, f bigquery.SellInRecordFilter) (*PaginatedSellInRecordsResponse, bool) {
	enr, canEnrich := h.bqRepo.(sellInEnricher)
	if !canEnrich {
		return nil, false
	}
	profiles := h.sellInChainProfiles(ctx, tenantID)
	res, ok := h.querySellInTotals(ctx, tenantID, f, profiles)
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
	applySellInChainTerms(&resp, res.Groups, profiles)
	return &resp, true
}

// sellInRowWaterfall is one row's official → expected split: invoice discount on the official value,
// the extra discount on what remains, expected = official − invoice − extra. Same as bqsink.SellInTotalsSQL.
func sellInRowWaterfall(rec domain.SellInRecord) (inv, extra, expected float64) {
	list := rec.OfficialListValueExclEGP
	inv = list * rec.InvoiceDiscountPct / 100.0
	extra = (list - inv) * rec.ExtraDiscountPct / 100.0
	return inv, extra, list - inv - extra
}

// sellInTotalsFromRecords sums in-memory rows with the same rules as the BigQuery query. Rows without
// an official list price contribute 0 to the list value (no invented 10% discount) and their file net
// goes to UnpricedNet.
func sellInTotalsFromRecords(records []domain.SellInRecord) bqsink.SellInTotals {
	t, _ := sellInTotalsAndChainsFromRecords(records)
	return t
}

// sellInTotalsAndChainsFromRecords also returns the per-chain waterfall sums (the in-memory
// counterpart of the BigQuery groups query).
func sellInTotalsAndChainsFromRecords(records []domain.SellInRecord) (bqsink.SellInTotals, []bqsink.SellInGroupRow) {
	var t bqsink.SellInTotals
	matched := make(map[string]bool)
	chains := map[string]*bqsink.SellInGroupRow{}
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
		inv, extra, expected := sellInRowWaterfall(rec)
		t.InvDisc += inv
		t.ExtraDisc += extra
		t.ExpectedNet += expected
		unpriced := 0.0
		if listExcl == 0 {
			unpriced = rec.NetValueEGP
		}
		t.UnpricedNet += unpriced
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

		key := sellInChainKey(rec.RetailerChain)
		g := chains[key]
		if g == nil {
			g = &bqsink.SellInGroupRow{Chain: key}
			chains[key] = g
		}
		g.Count++
		g.NetValue += rec.NetValueEGP
		g.Cases += rec.NetQtyCases
		g.ListExcl += listExcl
		g.Discount += disc
		g.InvDisc += inv
		g.ExtraDisc += extra
		g.ExpectedNet += expected
		g.UnpricedNet += unpriced
	}
	t.MatchedSKUs = int64(len(matched))
	groups := make([]bqsink.SellInGroupRow, 0, len(chains))
	for _, g := range chains {
		groups = append(groups, *g)
	}
	return t, groups
}

func sellInChainKey(chain string) string { return strings.ToLower(strings.TrimSpace(chain)) }

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

// sellInEffectiveVATPct is VAT / net as a percent (14 when every row uses 14%); 0 with no net value.
func sellInEffectiveVATPct(t bqsink.SellInTotals) float64 {
	if t.NetValue <= 0 {
		return 0
	}
	return math.Round(t.VAT/t.NetValue*10000) / 100
}

func round2(v float64) float64 { return math.Round(v*100) / 100 }

// sellInCardTotals are the «من السعر الرسمي إلى الفاتورة» card amounts, rounded to piastres so the card
// adds up exactly:
//
//	official − invoice − extra = expected
//	expected − execution + unpriced = net (Excel Net V)
//	net + VAT = invoices
type sellInCardTotals struct {
	official, invoice, extra, expected, execution, unpriced, net, vat, gross float64
}

func sellInCard(t bqsink.SellInTotals) sellInCardTotals {
	c := sellInCardTotals{
		official: round2(t.ListExcl),
		invoice:  round2(t.InvDisc),
		extra:    round2(t.ExtraDisc),
		unpriced: round2(t.UnpricedNet),
		net:      round2(t.NetValue),
		gross:    round2(t.Gross),
	}
	c.expected = round2(c.official - c.invoice - c.extra)
	// Expected net minus the file net of the priced rows; negative when rows were invoiced above it.
	c.execution = round2(c.expected + c.unpriced - c.net)
	c.vat = round2(c.gross - c.net)
	return c
}

func buildSellInRecordsResponse(t bqsink.SellInTotals, page []domain.SellInRecord, total, limit, offset int) PaginatedSellInRecordsResponse {
	card := sellInCard(t)
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
		TotalOfficialListExclVATEGP: card.official,
		TotalOfficialListInclVATEGP: round2(t.ListIncl),
		TotalDiscountGrantedEGP:     round2(t.Discount),
		TotalInvoiceDiscountEGP:     card.invoice,
		TotalExtraChainDiscountEGP:  card.extra,
		TotalExpectedNetEGP:         card.expected,
		TotalExecutionDiffEGP:       card.execution,
		TotalOtherDifferenceEGP:     card.execution,
		TotalUnpricedNetEGP:         card.unpriced,
		InvoiceDiscountPct:          sellInWeightedInvoicePct(t.ListExcl, t.InvDisc),
		ExtraDiscountPct:            sellInWeightedExtraPct(t.ListExcl, t.InvDisc, t.ExtraDisc),
		TermsAveraged:               true,
		VATRatePct:                  sellInEffectiveVATPct(t),
		EffectiveDiscountPct:        sellInEffectiveDiscountPct(t),
		TotalNetExclVATEGP:          card.net,
		TotalVAT14EGP:               card.vat,
		TotalGrossInclVATEGP:        card.gross,
		MatchedCatalogSKUsCount:     int(t.MatchedSKUs),
	}
}

func sellInWeightedInvoicePct(list, inv float64) float64 {
	if list == 0 {
		return 0
	}
	return math.Round(inv/list*10000) / 100
}

func sellInWeightedExtraPct(list, inv, extra float64) float64 {
	if list-inv == 0 {
		return 0
	}
	return math.Round(extra/(list-inv)*10000) / 100
}

// SellInChainTermsItem is one chain's terms and waterfall amounts (the «متوسط» tooltip breakdown).
type SellInChainTermsItem struct {
	Chain                  string  `json:"chain"`
	Saved                  bool    `json:"saved"` // false: the flat defaults apply
	InvoiceDiscountPct     float64 `json:"invoice_discount_pct"`
	ExtraDiscountPct       float64 `json:"extra_discount_pct"`
	VATRatePct             float64 `json:"vat_rate_pct"`
	OfficialListExclVATEGP float64 `json:"official_list_excl_vat_egp"`
	InvoiceDiscountEGP     float64 `json:"invoice_discount_egp"`
	ExtraDiscountEGP       float64 `json:"extra_discount_egp"`
	ExpectedNetEGP         float64 `json:"expected_net_egp"`
	UnpricedNetEGP         float64 `json:"unpriced_net_egp"`
	NetExclVATEGP          float64 `json:"net_excl_vat_egp"`
}

// sellInTermsFor resolves a chain's terms like bigquery.sellInChainTerms: saved profile, else defaults.
func sellInTermsFor(chain string, profiles []bqsink.SellInChainProfile) (inv, extra, vatPct float64, saved bool) {
	for _, p := range profiles {
		if sellInChainKey(p.Chain) != chain {
			continue
		}
		vatPct = domain.DefaultChainVATRatePct
		if p.VATRate != nil {
			vatPct = *p.VATRate * 100
		}
		return p.InvoiceDiscountPct, p.ExtraDiscountPct, math.Round(vatPct*100) / 100, true
	}
	return domain.DefaultChainInvoiceDiscountPct, domain.DefaultChainAdditionalDiscountPct, domain.DefaultChainVATRatePct, false
}

// applySellInChainTerms adds the per-chain breakdown. With one chain in the selection the badges show
// that chain's saved percentages exactly; with several they stay the official-weighted averages.
func applySellInChainTerms(resp *PaginatedSellInRecordsResponse, groups []bqsink.SellInGroupRow, profiles []bqsink.SellInChainProfile) {
	byChain := map[string]*SellInChainTermsItem{}
	for _, g := range groups {
		key := sellInChainKey(g.Chain)
		it := byChain[key]
		if it == nil {
			it = &SellInChainTermsItem{Chain: key}
			it.InvoiceDiscountPct, it.ExtraDiscountPct, it.VATRatePct, it.Saved = sellInTermsFor(key, profiles)
			byChain[key] = it
		}
		it.OfficialListExclVATEGP += g.ListExcl
		it.InvoiceDiscountEGP += g.InvDisc
		it.ExtraDiscountEGP += g.ExtraDisc
		it.ExpectedNetEGP += g.ExpectedNet
		it.UnpricedNetEGP += g.UnpricedNet
		it.NetExclVATEGP += g.NetValue
	}
	items := make([]SellInChainTermsItem, 0, len(byChain))
	for _, it := range byChain {
		it.OfficialListExclVATEGP, it.InvoiceDiscountEGP, it.ExtraDiscountEGP = round2(it.OfficialListExclVATEGP), round2(it.InvoiceDiscountEGP), round2(it.ExtraDiscountEGP)
		it.ExpectedNetEGP, it.UnpricedNetEGP, it.NetExclVATEGP = round2(it.ExpectedNetEGP), round2(it.UnpricedNetEGP), round2(it.NetExclVATEGP)
		items = append(items, *it)
	}
	sort.Slice(items, func(i, j int) bool {
		if items[i].OfficialListExclVATEGP != items[j].OfficialListExclVATEGP {
			return items[i].OfficialListExclVATEGP > items[j].OfficialListExclVATEGP
		}
		return items[i].Chain < items[j].Chain
	})
	resp.ChainTerms = items
	if len(items) == 1 {
		resp.InvoiceDiscountPct, resp.ExtraDiscountPct, resp.VATRatePct = items[0].InvoiceDiscountPct, items[0].ExtraDiscountPct, items[0].VATRatePct
		resp.TermsAveraged = false
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
