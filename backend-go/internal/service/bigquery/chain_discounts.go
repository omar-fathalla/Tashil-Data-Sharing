package bigquery

import (
	"context"
	"sort"
	"strings"
	"sync"
	"time"

	"github.com/tashil/data-sharing/backend/internal/domain"
)

const costSourceMasterListChainProfile = "master_list_chain_profile"

// chainDiscountStore keeps per-tenant chain discount profiles used by CPFR cost.
// It has its own lock so it can be read while c.mu is held.
type chainDiscountStore struct {
	mu       sync.RWMutex
	byTenant map[string]map[string]domain.ChainDiscountProfile
	fp       map[string]string // normTenant -> content fingerprint of the applied list

	// Cross-instance sync (chain_discounts_sync.go).
	syncMu  sync.Mutex
	src     ChainDiscountSource
	ttl     time.Duration
	checked map[string]time.Time
}

func (c *Client) chainDiscounts() *chainDiscountStore { return &c.chainDisc }

func normChainKey(s string) string { return strings.ToLower(strings.TrimSpace(s)) }

// SetChainDiscountProfiles replaces the tenant's profiles used by CPFR cost and the Sell-In
// waterfall, re-prices the tenant's in-memory Sell-In rows with the new terms and invalidates any
// cached / precomputed analytics for that tenant.
func (c *Client) SetChainDiscountProfiles(tenantID string, profiles []domain.ChainDiscountProfile) {
	m := make(map[string]domain.ChainDiscountProfile, len(profiles))
	for _, p := range profiles {
		if k := normChainKey(p.Chain); k != "" {
			m[k] = p
		}
	}
	norm := normalizeTenantKey(tenantID)
	s := c.chainDiscounts()
	s.mu.Lock()
	if s.byTenant == nil {
		s.byTenant = map[string]map[string]domain.ChainDiscountProfile{}
	}
	if s.fp == nil {
		s.fp = map[string]string{}
	}
	s.byTenant[norm] = m
	s.fp[norm] = chainProfilesFingerprint(profiles)
	s.mu.Unlock()

	// Stored Sell-In rows carry VAT / discount fields derived at enrichment time; refresh them so
	// the new terms apply on the next load without a re-upload.
	c.mu.Lock()
	recs := c.sellInRecords[norm]
	for i := range recs {
		c.enrichSellInRecordLocked(&recs[i])
	}
	c.mu.Unlock()
	c.invalidateKPICache() // also bumps the precomputed-layer source version
}

// ChainDiscountProfilesSnapshot returns the tenant's applied profiles (after syncing the shared store).
func (c *Client) ChainDiscountProfilesSnapshot(ctx context.Context, tenantID string) []domain.ChainDiscountProfile {
	c.syncChainDiscounts(ctx, tenantID)
	s := c.chainDiscounts()
	s.mu.RLock()
	defer s.mu.RUnlock()
	m := s.byTenant[normalizeTenantKey(tenantID)]
	out := make([]domain.ChainDiscountProfile, 0, len(m))
	for _, p := range m {
		out = append(out, p)
	}
	sort.Slice(out, func(i, j int) bool { return normChainKey(out[i].Chain) < normChainKey(out[j].Chain) })
	return out
}

// chainDiscountProfile returns the profile for a chain, if one is saved.
func (c *Client) chainDiscountProfile(normTenant, chain string) (domain.ChainDiscountProfile, bool) {
	s := c.chainDiscounts()
	s.mu.RLock()
	defer s.mu.RUnlock()
	p, ok := s.byTenant[normTenant][normChainKey(chain)]
	return p, ok
}

// defaultVATRate is the VAT used when neither the chain profile nor the Product Master sets one.
const defaultVATRate = domain.DefaultChainVATRatePct / 100.0

// productMasterVATRate is the Product Master "نسبة الضريبة" column as a fraction (14% when unset).
func productMasterVATRate(pm domain.ProductMasterItem, pmOk bool) float64 {
	if pmOk && pm.VATRate > 0 {
		if pm.VATRate > 1.0 {
			return pm.VATRate / 100.0
		}
		return pm.VATRate
	}
	return defaultVATRate
}

// chainVATRate resolves the VAT fraction. Precedence: the chain's saved rate, else the Product
// Master column, else 14%.
func chainVATRate(prof domain.ChainDiscountProfile, hasProf bool, pm domain.ProductMasterItem, pmOk bool) float64 {
	if hasProf {
		if v, ok := prof.VATRate(); ok {
			return v
		}
	}
	return productMasterVATRate(pm, pmOk)
}

// chainTerms are the effective commercial terms applied to one Sell-In row (percent numbers).
type chainTerms struct {
	VATRate            float64 // fraction, 0.14
	InvoiceDiscountPct float64
	ExtraDiscountPct   float64
}

// sellInChainTerms resolves the Sell-In waterfall terms for a chain: its saved profile, else the flat
// defaults (invoice 10%, extra 0%, VAT 14%). The Product Master per-item discount and VAT columns are
// not used, so the in-memory path and the BigQuery totals (bqsink.SellInTotalsSQL) agree.
func sellInChainTerms(prof domain.ChainDiscountProfile, hasProf bool) chainTerms {
	t := chainTerms{
		VATRate:            defaultVATRate,
		InvoiceDiscountPct: domain.DefaultChainInvoiceDiscountPct,
		ExtraDiscountPct:   domain.DefaultChainAdditionalDiscountPct,
	}
	if !hasProf {
		return t
	}
	t.InvoiceDiscountPct, t.ExtraDiscountPct = prof.InvoiceDiscountPct, prof.AdditionalDiscountPct
	if v, ok := prof.VATRate(); ok {
		t.VATRate = v
	}
	return t
}

// resolveFactoryUnitCostForChain applies a saved chain profile:
// cost = master list price × (1 − invoice%) × (1 − additional%), incl. the chain's VAT.
// Without a profile (or without a master list price) it falls back to
// resolveRealFactoryUnitCost, i.e. the default 10% invoice / 0% additional numbers.
func resolveFactoryUnitCostForChain(sheetCost float64, pm domain.ProductMasterItem, pmOk bool, prof domain.ChainDiscountProfile, hasProf bool) (float64, string, string) {
	if hasProf && pmOk && pm.UnitPriceInclVAT > 0 {
		list := pm.UnitPriceInclVAT
		if vat, pmVat := chainVATRate(prof, hasProf, pm, pmOk), productMasterVATRate(pm, pmOk); vat != pmVat {
			list = list / (1.0 + pmVat) * (1.0 + vat)
		}
		return list * (1.0 - prof.InvoiceDiscountPct/100.0) * (1.0 - prof.AdditionalDiscountPct/100.0), costSourceMasterListChainProfile, ""
	}
	return resolveRealFactoryUnitCost(sheetCost, pm, pmOk)
}
