package firestore

import (
	"context"
	"crypto/sha1"
	"encoding/hex"
	"errors"
	"fmt"
	"sort"
	"strings"
	"time"

	"google.golang.org/api/iterator"

	"github.com/tashil/data-sharing/backend/internal/domain"
)

const customCompetitorSkusCollection = "custom_competitor_skus"

// ErrCustomSkuNotFound is returned when a custom competitor SKU does not exist for the tenant.
var ErrCustomSkuNotFound = errors.New("custom competitor sku not found")

// CompetitorSkuRepository persists custom competitor SKUs, always scoped by tenant.
type CompetitorSkuRepository interface {
	SaveCustomCompetitorSku(ctx context.Context, s *domain.CustomCompetitorSku) error
	ListCustomCompetitorSkus(ctx context.Context, tenantID string, f domain.CustomCompetitorSkuFilter) ([]domain.CustomCompetitorSku, error)
	DeleteCustomCompetitorSku(ctx context.Context, tenantID, id string) error
}

var _ CompetitorSkuRepository = (*Client)(nil)

func normKey(s string) string { return strings.ToLower(strings.Join(strings.Fields(s), " ")) }

// CustomCompetitorSkuID derives the deterministic document id from the dedupe key:
// tenant + own barcode (or own sku name) + competitor sku name + chain.
func CustomCompetitorSkuID(s *domain.CustomCompetitorSku) string {
	own := strings.TrimSpace(s.OwnBarcode)
	if own == "" {
		own = s.OwnSkuName
	}
	key := strings.Join([]string{normalizeFirestoreTenantSlug(s.TenantID), normKey(own), normKey(s.CompetitorSkuName), normKey(s.RetailerChain)}, "|")
	sum := sha1.Sum([]byte(key))
	return "ccsku_" + hex.EncodeToString(sum[:])[:20]
}

// SaveCustomCompetitorSku upserts by dedupe key; saving the same key again updates the record.
func (c *Client) SaveCustomCompetitorSku(ctx context.Context, s *domain.CustomCompetitorSku) error {
	if s == nil {
		return fmt.Errorf("custom sku cannot be nil")
	}
	slug := normalizeFirestoreTenantSlug(s.TenantID)
	s.TenantID = slug
	s.ID = CustomCompetitorSkuID(s)
	now := time.Now().UTC()

	c.ccMu.Lock()
	if c.ccSkus == nil {
		c.ccSkus = make(map[string]domain.CustomCompetitorSku)
	}
	if prev, ok := c.ccSkus[s.ID]; ok && prev.TenantID == slug {
		s.CreatedAt, s.CreatedBy = prev.CreatedAt, prev.CreatedBy
	}
	c.ccMu.Unlock()

	if c.fsClient != nil {
		doc := c.fsClient.Collection(customCompetitorSkusCollection).Doc(s.ID)
		if snap, err := doc.Get(ctx); err == nil {
			var existing domain.CustomCompetitorSku
			if snap.DataTo(&existing) == nil && existing.TenantID == slug && !existing.CreatedAt.IsZero() {
				s.CreatedAt, s.CreatedBy = existing.CreatedAt, existing.CreatedBy
			}
		}
	}
	if s.CreatedAt.IsZero() {
		s.CreatedAt = now
	}
	s.UpdatedAt = now

	if c.fsClient != nil {
		if _, err := c.fsClient.Collection(customCompetitorSkusCollection).Doc(s.ID).Set(ctx, *s); err != nil {
			return fmt.Errorf("firestore save custom sku: %w", err)
		}
	}
	c.ccMu.Lock()
	c.ccSkus[s.ID] = *s
	c.ccMu.Unlock()
	return nil
}

// ListCustomCompetitorSkus returns the tenant's custom competitor SKUs, newest first.
func (c *Client) ListCustomCompetitorSkus(ctx context.Context, tenantID string, f domain.CustomCompetitorSkuFilter) ([]domain.CustomCompetitorSku, error) {
	slug := normalizeFirestoreTenantSlug(tenantID)
	var all []domain.CustomCompetitorSku
	if c.fsClient != nil {
		it := c.fsClient.Collection(customCompetitorSkusCollection).Where("tenant_id", "==", slug).Documents(ctx)
		defer it.Stop()
		for {
			snap, err := it.Next()
			if err == iterator.Done {
				break
			}
			if err != nil {
				return nil, fmt.Errorf("firestore list custom skus: %w", err)
			}
			var s domain.CustomCompetitorSku
			if snap.DataTo(&s) == nil {
				all = append(all, s)
			}
		}
		c.ccMu.Lock()
		if c.ccSkus == nil {
			c.ccSkus = make(map[string]domain.CustomCompetitorSku)
		}
		for _, s := range all {
			c.ccSkus[s.ID] = s
		}
		c.ccMu.Unlock()
	} else {
		c.ccMu.RLock()
		for _, s := range c.ccSkus {
			if s.TenantID == slug {
				all = append(all, s)
			}
		}
		c.ccMu.RUnlock()
	}

	chain := normKey(f.Chain)
	if chain == "all" || chain == "الكل" {
		chain = ""
	}
	cat := normKey(f.Category)
	if cat == "all" || cat == "الكل" {
		cat = ""
	}
	out := make([]domain.CustomCompetitorSku, 0, len(all))
	for _, s := range all {
		if chain != "" && normKey(s.RetailerChain) != chain {
			continue
		}
		if cat != "" && normKey(s.Category) != cat {
			continue
		}
		out = append(out, s)
	}
	sort.Slice(out, func(i, j int) bool { return out[i].CreatedAt.After(out[j].CreatedAt) })
	return out, nil
}

// DeleteCustomCompetitorSku removes a custom SKU only if it belongs to tenantID.
func (c *Client) DeleteCustomCompetitorSku(ctx context.Context, tenantID, id string) error {
	slug := normalizeFirestoreTenantSlug(tenantID)
	id = strings.TrimSpace(id)
	if id == "" {
		return ErrCustomSkuNotFound
	}
	found := false
	c.ccMu.Lock()
	if s, ok := c.ccSkus[id]; ok {
		if s.TenantID != slug {
			c.ccMu.Unlock()
			return ErrCustomSkuNotFound
		}
		delete(c.ccSkus, id)
		found = true
	}
	c.ccMu.Unlock()

	if c.fsClient != nil {
		doc := c.fsClient.Collection(customCompetitorSkusCollection).Doc(id)
		snap, err := doc.Get(ctx)
		if err != nil {
			if found {
				return nil
			}
			return ErrCustomSkuNotFound
		}
		var s domain.CustomCompetitorSku
		if snap.DataTo(&s) != nil || s.TenantID != slug {
			return ErrCustomSkuNotFound
		}
		if _, err := doc.Delete(ctx); err != nil {
			return fmt.Errorf("firestore delete custom sku: %w", err)
		}
		return nil
	}
	if !found {
		return ErrCustomSkuNotFound
	}
	return nil
}
