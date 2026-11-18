package bigquery

import (
	"context"
	"math"
	"sort"
	"strings"

	"github.com/tashil/data-sharing/backend/internal/domain"
	"github.com/tashil/data-sharing/backend/internal/service/sharetarget"
)

// GetShareTargetBaseline builds wizard step-2 inputs for one chain and year from in-memory
// Sell-Out facts. Categories come from that chain's own sheet only (no cross-chain merge).
// Unknown/quarantined customers are never present in sell_out_facts.
func (c *Client) GetShareTargetBaseline(ctx context.Context, tenantID, chain string, year int) (*domain.ShareTargetBaselineResponse, error) {
	_ = ctx
	c.ensureTenantSeeded(tenantID)
	c.mu.RLock()
	defer c.mu.RUnlock()

	ch := strings.ToLower(strings.TrimSpace(chain))
	if ch == "" || ch == "all" || ch == "الكل" {
		return nil, errShareTargetChainRequired
	}
	if year <= 0 {
		year = 2026
	}

	type catAcc struct {
		own, market float64
		ownUnits    float64
		skus        map[string]struct{}
	}
	type brAcc struct {
		name string
		own  float64
	}

	cats := map[string]*catAcc{}
	branches := map[string]*brAcc{}
	months := map[string]struct{}{}
	catNormCache := map[string]string{}

	for _, r := range c.records {
		if !matchTenant(r.TenantID, tenantID) {
			continue
		}
		if !matchChainFilter(r.RetailerChain, ch) {
			continue
		}
		if len(r.TransactionDate) < 7 {
			continue
		}
		yr := 0
		if _, err := parseYearPrefix(r.TransactionDate, &yr); err != nil || yr != year {
			continue
		}
		months[r.TransactionDate[:7]] = struct{}{}

		catName, ok := catNormCache[r.Category]
		if !ok {
			catName = domain.NormalizeProductCategory(r.Category)
			if catName == "" {
				catName = "غير مصنف"
			}
			catNormCache[r.Category] = catName
		}
		acc, exists := cats[catName]
		if !exists {
			acc = &catAcc{skus: map[string]struct{}{}}
			cats[catName] = acc
		}
		acc.market += r.NetRevenue
		isOwn := isOwnRecord(r)
		if isOwn {
			acc.own += r.NetRevenue
			acc.ownUnits += float64(r.QuantitySold)
			skuID := strings.TrimSpace(r.Barcode)
			if skuID == "" {
				skuID = strings.TrimSpace(r.SKUName)
			}
			if skuID != "" {
				acc.skus[skuID] = struct{}{}
			}
			brKey := strings.TrimSpace(r.StoreID)
			if brKey == "" {
				brKey = strings.TrimSpace(r.StoreName)
			}
			if brKey != "" {
				b, ok := branches[brKey]
				if !ok {
					b = &brAcc{name: strings.TrimSpace(r.StoreName)}
					if b.name == "" {
						b.name = brKey
					}
					branches[brKey] = b
				}
				if n := strings.TrimSpace(r.StoreName); n != "" {
					b.name = n
				}
				b.own += r.NetRevenue
			}
		}
	}

	resp := &domain.ShareTargetBaselineResponse{
		TenantID:         normalizeTenantKey(tenantID),
		RetailerChain:    ch,
		ChainDisplayName: getRetailChainDisplayName(ch),
		Year:             year,
		MonthsWithData:   len(months),
		Categories:       []domain.ShareTargetBaselineCategory{},
		Branches:         []domain.ShareTargetBaselineBranch{},
	}
	monthKeys := make([]string, 0, len(months))
	for m := range months {
		monthKeys = append(monthKeys, m)
	}
	sort.Strings(monthKeys)
	resp.MonthKeys = monthKeys

	for name, acc := range cats {
		if acc.market <= 0 && acc.own <= 0 {
			continue
		}
		market := acc.market
		if market < acc.own {
			market = acc.own
		}
		share := 0.0
		if market > 0 {
			share = math.Round((acc.own/market)*1000) / 10
		}
		avg := 0.0
		if acc.ownUnits > 0 {
			avg = acc.own / acc.ownUnits
		}
		resp.Categories = append(resp.Categories, domain.ShareTargetBaselineCategory{
			Category:         name,
			CurrentSharePct:  share,
			OwnRevenueEGP:    math.Round(acc.own*100) / 100,
			MarketRevenueEGP: math.Round(market*100) / 100,
			OwnUnits:         math.Round(acc.ownUnits*100) / 100,
			AvgPriceEGP:      math.Round(avg*100) / 100,
			SKUCount:         len(acc.skus),
		})
		resp.TotalOwnEGP += acc.own
		resp.TotalMarketEGP += market
	}
	sort.Slice(resp.Categories, func(i, j int) bool {
		if resp.Categories[i].OwnRevenueEGP == resp.Categories[j].OwnRevenueEGP {
			return resp.Categories[i].Category < resp.Categories[j].Category
		}
		return resp.Categories[i].OwnRevenueEGP > resp.Categories[j].OwnRevenueEGP
	})
	resp.TotalOwnEGP = math.Round(resp.TotalOwnEGP*100) / 100
	resp.TotalMarketEGP = math.Round(resp.TotalMarketEGP*100) / 100
	if resp.TotalMarketEGP > 0 {
		resp.OverallCurrentPct = math.Round((resp.TotalOwnEGP/resp.TotalMarketEGP)*1000) / 10
	}

	for key, b := range branches {
		resp.Branches = append(resp.Branches, domain.ShareTargetBaselineBranch{
			BranchKey:     key,
			BranchName:    b.name,
			OwnRevenueEGP: math.Round(b.own*100) / 100,
		})
	}
	sort.Slice(resp.Branches, func(i, j int) bool {
		if resp.Branches[i].OwnRevenueEGP == resp.Branches[j].OwnRevenueEGP {
			return resp.Branches[i].BranchName < resp.Branches[j].BranchName
		}
		return resp.Branches[i].OwnRevenueEGP > resp.Branches[j].OwnRevenueEGP
	})

	return resp, nil
}

// BuildShareTargetCascadeInputs collects historical branch / SKU / month weights for one
// category inside a chain/year so the wizard can preview the cascade.
func (c *Client) BuildShareTargetCascadeInputs(ctx context.Context, tenantID, chain, category string, year int, branchFilter map[string]bool) (
	branches []sharetarget.BranchWeight,
	skusByBranch map[string][]sharetarget.SKUWeight,
	months []sharetarget.MonthWeight,
	err error,
) {
	_ = ctx
	c.mu.RLock()
	defer c.mu.RUnlock()

	ch := strings.ToLower(strings.TrimSpace(chain))
	wantCat := domain.NormalizeProductCategory(category)
	type skuAcc struct {
		name, key string
		rev       float64
		units     float64
	}
	type brAcc struct {
		name string
		own  float64
		skus map[string]*skuAcc
	}
	brMap := map[string]*brAcc{}
	monthRev := map[int]float64{}

	for _, r := range c.records {
		if !matchTenant(r.TenantID, tenantID) || !matchChainFilter(r.RetailerChain, ch) {
			continue
		}
		if len(r.TransactionDate) < 7 {
			continue
		}
		yr := 0
		if _, err := parseYearPrefix(r.TransactionDate, &yr); err != nil || yr != year {
			continue
		}
		catName := domain.NormalizeProductCategory(r.Category)
		if catName == "" {
			catName = "غير مصنف"
		}
		if wantCat != "" && catName != wantCat {
			continue
		}
		if !isOwnRecord(r) {
			// Seasonality can use market; for Mohamed decision we use Adeco history when available.
			continue
		}
		brKey := strings.TrimSpace(r.StoreID)
		if brKey == "" {
			brKey = strings.TrimSpace(r.StoreName)
		}
		if brKey == "" {
			continue
		}
		if len(branchFilter) > 0 && !branchFilter[brKey] && !branchFilter[strings.TrimSpace(r.StoreName)] {
			continue
		}
		b, ok := brMap[brKey]
		if !ok {
			b = &brAcc{name: strings.TrimSpace(r.StoreName), skus: map[string]*skuAcc{}}
			if b.name == "" {
				b.name = brKey
			}
			brMap[brKey] = b
		}
		if n := strings.TrimSpace(r.StoreName); n != "" {
			b.name = n
		}
		b.own += r.NetRevenue
		skuKey := strings.TrimSpace(r.Barcode)
		if skuKey == "" {
			skuKey = strings.TrimSpace(r.SKUName)
		}
		if skuKey != "" {
			s, ok := b.skus[skuKey]
			if !ok {
				s = &skuAcc{key: skuKey, name: strings.TrimSpace(r.SKUName)}
				b.skus[skuKey] = s
			}
			if n := strings.TrimSpace(r.SKUName); n != "" {
				s.name = n
			}
			s.rev += r.NetRevenue
			s.units += float64(r.QuantitySold)
		}
		if mo := monthNum(r.TransactionDate); mo >= 1 && mo <= 12 {
			monthRev[mo] += r.NetRevenue
		}
	}

	skusByBranch = map[string][]sharetarget.SKUWeight{}
	for key, b := range brMap {
		branches = append(branches, sharetarget.BranchWeight{
			BranchKey: key, BranchName: b.name, OwnRevenue: b.own,
		})
		list := make([]sharetarget.SKUWeight, 0, len(b.skus))
		for _, s := range b.skus {
			avg := 0.0
			if s.units > 0 {
				avg = s.rev / s.units
			}
			list = append(list, sharetarget.SKUWeight{
				SKUKey: s.key, SKUName: s.name, OwnRevenue: s.rev, AvgPrice: avg,
			})
		}
		skusByBranch[key] = list
	}
	sort.Slice(branches, func(i, j int) bool {
		return branches[i].OwnRevenue > branches[j].OwnRevenue
	})
	for m, w := range monthRev {
		months = append(months, sharetarget.MonthWeight{Month: m, Weight: w})
	}
	sort.Slice(months, func(i, j int) bool { return months[i].Month < months[j].Month })
	return branches, skusByBranch, months, nil
}

var errShareTargetChainRequired = errString("retailer_chain is required (one chain; no cross-chain merge)")

type errString string

func (e errString) Error() string { return string(e) }

func parseYearPrefix(date string, year *int) (bool, error) {
	if len(date) < 4 {
		return false, errString("bad date")
	}
	y := 0
	for i := 0; i < 4; i++ {
		c := date[i]
		if c < '0' || c > '9' {
			return false, errString("bad year")
		}
		y = y*10 + int(c-'0')
	}
	*year = y
	return true, nil
}

func monthNum(date string) int {
	if len(date) < 7 || date[4] != '-' {
		return 0
	}
	m := int(date[5]-'0')*10 + int(date[6]-'0')
	if m < 1 || m > 12 {
		return 0
	}
	return m
}
