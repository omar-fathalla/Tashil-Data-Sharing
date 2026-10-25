package bigquery

import (
	"strings"
	"sync"

	"github.com/tashil/data-sharing/backend/internal/domain"
)

const costSourceMasterListChainProfile = "master_list_chain_profile"

// chainDiscountStore keeps per-tenant chain discount profiles used by CPFR cost.
// It has its own lock so it can be read while c.mu is held.
type chainDiscountStore struct {
	mu       sync.RWMutex
	byTenant map[string]map[string]domain.ChainDiscountProfile
}

func (c *Client) chainDiscounts() *chainDiscountStore { return &c.chainDisc }

func normChainKey(s string) string { return strings.ToLower(strings.TrimSpace(s)) }

// SetChainDiscountProfiles replaces the tenant's profiles used by CPFR cost and
// invalidates any cached / precomputed analytics for that tenant.
func (c *Client) SetChainDiscountProfiles(tenantID string, profiles []domain.ChainDiscountProfile) {
	m := make(map[string]domain.ChainDiscountProfile, len(profiles))
	for _, p := range profiles {
		if k := normChainKey(p.Chain); k != "" {
			m[k] = p
		}
	}
	s := c.chainDiscounts()
	s.mu.Lock()
	if s.byTenant == nil {
		s.byTenant = map[string]map[string]domain.ChainDiscountProfile{}
	}
	s.byTenant[normalizeTenantKey(tenantID)] = m
	s.mu.Unlock()
	c.invalidateKPICache() // also bumps the precomputed-layer source version
}

// chainDiscountProfile returns the profile for a chain, if one is saved.
func (c *Client) chainDiscountProfile(normTenant, chain string) (domain.ChainDiscountProfile, bool) {
	s := c.chainDiscounts()
	s.mu.RLock()
	defer s.mu.RUnlock()
	p, ok := s.byTenant[normTenant][normChainKey(chain)]
	return p, ok
}

// resolveFactoryUnitCostForChain applies a saved chain profile:
// cost = master list price incl. VAT × (1 − invoice%) × (1 − additional%).
// Without a profile (or without a master list price) it falls back to
// resolveRealFactoryUnitCost, i.e. the default 10% invoice / 0% additional numbers.
func resolveFactoryUnitCostForChain(sheetCost float64, pm domain.ProductMasterItem, pmOk bool, prof domain.ChainDiscountProfile, hasProf bool) (float64, string, string) {
	if hasProf && pmOk && pm.UnitPriceInclVAT > 0 {
		return pm.UnitPriceInclVAT * (1.0 - prof.InvoiceDiscountPct/100.0) * (1.0 - prof.AdditionalDiscountPct/100.0), costSourceMasterListChainProfile, ""
	}
	return resolveRealFactoryUnitCost(sheetCost, pm, pmOk)
}
