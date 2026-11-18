package bigquery

import (
	"context"
	"sort"
	"strings"
	"sync"
	"sync/atomic"
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
	// applyMu serializes SetChainDiscountProfiles; dataGen counts in-place Sell-In / Product Master
	// changes so a background re-enrichment can detect that its copy went stale.
	applyMu sync.Mutex
	dataGen atomic.Uint64

	syncMu  sync.Mutex
	src     ChainDiscountSource
	ttl     time.Duration
	checked map[string]time.Time
}

func (c *Client) chainDiscounts() *chainDiscountStore { return &c.chainDisc }

func normChainKey(s string) string { return strings.ToLower(strings.TrimSpace(s)) }

// SetChainDiscountProfiles replaces the tenant's profiles used by CPFR cost and the Sell-In
// waterfall, re-prices the tenant's in-memory Sell-In rows whose chain terms changed and invalidates
// any cached / precomputed analytics for that tenant.
//
// The new profiles are published first (own lock), so concurrent enrichment already sees them. Only
// rows of chains whose terms differ from the previous list are re-enriched, on a copy taken under the
// read lock; the result is swapped in under a short write lock, and discarded and recomputed when an
// upload or Product Master change landed in between.
func (c *Client) SetChainDiscountProfiles(tenantID string, profiles []domain.ChainDiscountProfile) {
	m := make(map[string]domain.ChainDiscountProfile, len(profiles))
	for _, p := range profiles {
		if k := normChainKey(p.Chain); k != "" {
			m[k] = p
		}
	}
	norm := normalizeTenantKey(tenantID)
	s := c.chainDiscounts()
	// Serializes appliers so a slower, older apply can never overwrite a newer one.
	s.applyMu.Lock()
	defer s.applyMu.Unlock()
	s.mu.Lock()
	if s.byTenant == nil {
		s.byTenant = map[string]map[string]domain.ChainDiscountProfile{}
	}
	if s.fp == nil {
		s.fp = map[string]string{}
	}
	old := s.byTenant[norm]
	s.byTenant[norm] = m
	s.fp[norm] = chainProfilesFingerprint(profiles)
	s.mu.Unlock()

	changed := changedChainKeys(old, m)
	if len(changed) == 0 {
		return
	}
	// Stored Sell-In rows carry VAT / discount fields derived at enrichment time; refresh them so
	// the new terms apply on the next load without a re-upload.
	c.reenrichSellInChains(norm, changed)
	c.invalidateKPICache() // also bumps the precomputed-layer source version
}

func sameProfileTerms(a, b domain.ChainDiscountProfile) bool {
	if a.InvoiceDiscountPct != b.InvoiceDiscountPct || a.AdditionalDiscountPct != b.AdditionalDiscountPct {
		return false
	}
	if (a.VATRatePct == nil) != (b.VATRatePct == nil) {
		return false
	}
	return a.VATRatePct == nil || *a.VATRatePct == *b.VATRatePct
}

// changedChainKeys returns the normalized chain keys that were added, removed or whose terms differ.
func changedChainKeys(old, next map[string]domain.ChainDiscountProfile) map[string]struct{} {
	changed := map[string]struct{}{}
	for k, n := range next {
		if o, ok := old[k]; !ok || !sameProfileTerms(o, n) {
			changed[k] = struct{}{}
		}
	}
	for k := range old {
		if _, ok := next[k]; !ok {
			changed[k] = struct{}{}
		}
	}
	return changed
}

// sellInRowChainKey is the key enrichSellInRecordLocked looks the row's profile up by.
func sellInRowChainKey(rules []customerChainRule, r *domain.SellInRecord) string {
	k := normChainKey(resolveSellInChainFromCustomer(rules, r.CustomerName, r.RetailerChain))
	if k == "" {
		return "fathalla"
	}
	return k
}

const reenrichMaxAttempts = 3

// reenrichBeforeSwapHook runs between the lock-free compute and the swap. Tests use it to let an
// upload or a reader land in that window.
var reenrichBeforeSwapHook func()

// noteSellInDataChanged marks that stored Sell-In rows or the Product Master lookups were changed in
// place. Callers hold c.mu for writing.
func (c *Client) noteSellInDataChanged() { c.chainDisc.dataGen.Add(1) }

func sameSellInBacking(a, b []domain.SellInRecord) bool {
	return len(a) == len(b) && (len(a) == 0 || &a[0] == &b[0])
}

// reenrichSellInChains re-prices the tenant's Sell-In rows belonging to the given chains. The work is
// done on copies under the read lock and swapped in under a short write lock when nothing else
// changed the Sell-In rows meanwhile; after repeated conflicts it re-enriches in place.
func (c *Client) reenrichSellInChains(norm string, changed map[string]struct{}) {
	rules := activeCustomerChainRules()
	for attempt := 0; attempt < reenrichMaxAttempts; attempt++ {
		c.mu.RLock()
		gen, ver := c.chainDisc.dataGen.Load(), c.precompute.sourceVersion.Load()
		base := c.sellInRecords[norm]
		var idx []int
		var rows []domain.SellInRecord
		for i := range base {
			if _, ok := changed[sellInRowChainKey(rules, &base[i])]; ok {
				idx = append(idx, i)
				rows = append(rows, base[i])
			}
		}
		for i := range rows {
			c.enrichSellInRecordLocked(&rows[i])
		}
		c.mu.RUnlock()
		if len(idx) == 0 {
			return
		}
		if reenrichBeforeSwapHook != nil {
			reenrichBeforeSwapHook()
		}

		c.mu.Lock()
		cur := c.sellInRecords[norm]
		if c.chainDisc.dataGen.Load() == gen && c.precompute.sourceVersion.Load() == ver && sameSellInBacking(cur, base) {
			for k, i := range idx {
				cur[i] = rows[k]
			}
			c.mu.Unlock()
			return
		}
		c.mu.Unlock()
	}

	c.mu.Lock()
	cur := c.sellInRecords[norm]
	for i := range cur {
		if _, ok := changed[sellInRowChainKey(rules, &cur[i])]; ok {
			c.enrichSellInRecordLocked(&cur[i])
		}
	}
	c.mu.Unlock()
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
