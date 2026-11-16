package firestore

import (
	"context"
	"fmt"
	"log"
	"math"
	"sort"
	"strings"
	"time"

	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"

	"github.com/tashil/data-sharing/backend/internal/domain"
)

const chainDiscountsCollection = "chain_discount_profiles"

// ChainDiscountRepository persists per-tenant chain discount profiles (one document per tenant).
type ChainDiscountRepository interface {
	GetChainDiscountProfiles(ctx context.Context, tenantID string) (*domain.ChainDiscountProfiles, error)
	SaveChainDiscountProfiles(ctx context.Context, doc *domain.ChainDiscountProfiles) error
}

var _ ChainDiscountRepository = (*Client)(nil)

// NormalizeChainKey is the key used to match a profile to a sell-out record chain.
func NormalizeChainKey(s string) string { return strings.ToLower(strings.TrimSpace(s)) }

// ValidateChainDiscountProfiles checks ranges and duplicates and sorts profiles by chain.
func ValidateChainDiscountProfiles(p []domain.ChainDiscountProfile) error {
	seen := map[string]bool{}
	for i := range p {
		p[i].Chain = strings.TrimSpace(p[i].Chain)
		k := NormalizeChainKey(p[i].Chain)
		if k == "" {
			return fmt.Errorf("chain is required")
		}
		if seen[k] {
			return fmt.Errorf("duplicate chain %q", p[i].Chain)
		}
		seen[k] = true
		if p[i].InvoiceDiscountPct < 0 || p[i].InvoiceDiscountPct >= 100 {
			return fmt.Errorf("invoice_discount_pct for %q must be in [0,100)", p[i].Chain)
		}
		if p[i].AdditionalDiscountPct < 0 || p[i].AdditionalDiscountPct >= 100 {
			return fmt.Errorf("additional_discount_pct for %q must be in [0,100)", p[i].Chain)
		}
		if v := p[i].VATRatePct; v != nil && (math.IsNaN(*v) || *v < 0 || *v > 100) {
			return fmt.Errorf("vat_rate_pct for %q must be in [0,100]", p[i].Chain)
		}
	}
	sort.Slice(p, func(i, j int) bool { return NormalizeChainKey(p[i].Chain) < NormalizeChainKey(p[j].Chain) })
	return nil
}

// GetChainDiscountProfiles returns the tenant's profiles (empty list when none saved).
// When Firestore fails or times out and this instance already holds a copy, that copy is returned.
func (c *Client) GetChainDiscountProfiles(ctx context.Context, tenantID string) (*domain.ChainDiscountProfiles, error) {
	slug := normalizeFirestoreTenantSlug(tenantID)
	if c.fsClient != nil {
		snap, err := c.fsClient.Collection(chainDiscountsCollection).Doc(slug).Get(ctx)
		if err != nil {
			if status.Code(err) == codes.NotFound {
				return &domain.ChainDiscountProfiles{TenantID: slug, Profiles: []domain.ChainDiscountProfile{}}, nil
			}
			if cached, ok := c.cachedChainDiscountProfiles(slug); ok {
				log.Printf("WARN [chain-discounts] tenant=%s firestore read failed, serving cached copy: %v", slug, err)
				return cached, nil
			}
			return nil, fmt.Errorf("firestore get chain discounts: %w", err)
		}
		var d domain.ChainDiscountProfiles
		if err := snap.DataTo(&d); err != nil {
			return nil, fmt.Errorf("decode chain discounts: %w", err)
		}
		d.TenantID = slug
		if d.Profiles == nil {
			d.Profiles = []domain.ChainDiscountProfile{}
		}
		c.cdMu.Lock()
		if c.cdProfiles == nil {
			c.cdProfiles = map[string]domain.ChainDiscountProfiles{}
		}
		c.cdProfiles[slug] = d
		c.cdMu.Unlock()
		return &d, nil
	}
	if cached, ok := c.cachedChainDiscountProfiles(slug); ok {
		return cached, nil
	}
	return &domain.ChainDiscountProfiles{TenantID: slug, Profiles: []domain.ChainDiscountProfile{}}, nil
}

func (c *Client) cachedChainDiscountProfiles(slug string) (*domain.ChainDiscountProfiles, bool) {
	c.cdMu.RLock()
	d, ok := c.cdProfiles[slug]
	c.cdMu.RUnlock()
	if !ok {
		return nil, false
	}
	cp := d
	cp.Profiles = append([]domain.ChainDiscountProfile{}, d.Profiles...)
	return &cp, true
}

// SaveChainDiscountProfiles replaces the tenant's full profile list (PUT semantics).
func (c *Client) SaveChainDiscountProfiles(ctx context.Context, doc *domain.ChainDiscountProfiles) error {
	if doc == nil {
		return fmt.Errorf("profiles cannot be nil")
	}
	if doc.Profiles == nil {
		doc.Profiles = []domain.ChainDiscountProfile{}
	}
	if err := ValidateChainDiscountProfiles(doc.Profiles); err != nil {
		return err
	}
	slug := normalizeFirestoreTenantSlug(doc.TenantID)
	doc.TenantID = slug
	doc.UpdatedAt = time.Now().UTC()
	if c.fsClient != nil {
		if _, err := c.fsClient.Collection(chainDiscountsCollection).Doc(slug).Set(ctx, *doc); err != nil {
			return fmt.Errorf("firestore save chain discounts: %w", err)
		}
	}
	c.cdMu.Lock()
	if c.cdProfiles == nil {
		c.cdProfiles = map[string]domain.ChainDiscountProfiles{}
	}
	cp := *doc
	cp.Profiles = append([]domain.ChainDiscountProfile{}, doc.Profiles...)
	c.cdProfiles[slug] = cp
	c.cdMu.Unlock()
	return nil
}
