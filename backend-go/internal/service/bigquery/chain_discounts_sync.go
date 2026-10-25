package bigquery

import (
	"context"
	"fmt"
	"log"
	"sort"
	"strings"
	"time"

	"github.com/tashil/data-sharing/backend/internal/domain"
)

// ChainDiscountSource is the shared store of chain discount profiles (Firestore).
type ChainDiscountSource interface {
	GetChainDiscountProfiles(ctx context.Context, tenantID string) (*domain.ChainDiscountProfiles, error)
}

// DefaultChainDiscountSyncTTL bounds how stale one Cloud Run instance can be after
// another instance saves chain discounts.
const DefaultChainDiscountSyncTTL = 30 * time.Second

// WithChainDiscountSource makes every analytics read re-check the shared store at most once
// per ttl per tenant. When the stored list differs from the applied one it is applied, which
// bumps the source version, so cached / precomputed results are recomputed on this instance.
func (c *Client) WithChainDiscountSource(src ChainDiscountSource, ttl time.Duration) *Client {
	s := c.chainDiscounts()
	s.syncMu.Lock()
	s.src = src
	s.ttl = ttl
	s.checked = map[string]time.Time{}
	s.syncMu.Unlock()
	return c
}

func chainProfilesFingerprint(profiles []domain.ChainDiscountProfile) string {
	parts := make([]string, 0, len(profiles))
	for _, p := range profiles {
		if k := normChainKey(p.Chain); k != "" {
			parts = append(parts, fmt.Sprintf("%s|%g|%g", k, p.InvoiceDiscountPct, p.AdditionalDiscountPct))
		}
	}
	sort.Strings(parts)
	return strings.Join(parts, ";")
}

// syncChainDiscounts pulls the tenant's profiles from the shared store when the TTL expired.
// Errors keep the current profiles (logged) and retry after the next TTL.
func (c *Client) syncChainDiscounts(ctx context.Context, tenantID string) {
	s := c.chainDiscounts()
	norm := normalizeTenantKey(tenantID)
	s.syncMu.Lock()
	if s.src == nil {
		s.syncMu.Unlock()
		return
	}
	if last, ok := s.checked[norm]; ok && time.Since(last) < s.ttl {
		s.syncMu.Unlock()
		return
	}
	s.checked[norm] = time.Now()
	src := s.src
	s.syncMu.Unlock()

	d, err := src.GetChainDiscountProfiles(ctx, tenantID)
	if err != nil {
		log.Printf("WARN [chain-discounts] tenant=%s sync failed: %v", tenantID, err)
		return
	}
	var remote []domain.ChainDiscountProfile
	if d != nil {
		remote = d.Profiles
	}
	fp := chainProfilesFingerprint(remote)
	s.mu.RLock()
	cur, applied := s.fp[norm]
	s.mu.RUnlock()
	if !applied && fp == "" {
		return // nothing saved anywhere; keep defaults without invalidating
	}
	if applied && cur == fp {
		return
	}
	c.SetChainDiscountProfiles(tenantID, remote)
	log.Printf("[chain-discounts] tenant=%s re-synced %d profile(s) from shared store", tenantID, len(remote))
}
