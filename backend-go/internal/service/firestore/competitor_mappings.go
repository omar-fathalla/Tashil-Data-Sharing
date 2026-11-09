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

const competitorMappingsCollection = "competitor_mappings"

// ErrCompetitorMappingNotFound is returned when a mapping does not exist for the tenant.
var ErrCompetitorMappingNotFound = errors.New("competitor mapping not found")

// CompetitorMappingRepository persists owner-approved own→competitor barcode pins.
type CompetitorMappingRepository interface {
	SaveCompetitorMapping(ctx context.Context, m *domain.CompetitorMapping) error
	ListCompetitorMappings(ctx context.Context, tenantID string, f domain.CompetitorMappingFilter) ([]domain.CompetitorMapping, error)
	DeleteCompetitorMapping(ctx context.Context, tenantID, id string) error
}

// CompetitorMappingID derives a deterministic id from tenant + own + competitor + chain.
func CompetitorMappingID(m *domain.CompetitorMapping) string {
	key := strings.Join([]string{
		normalizeFirestoreTenantSlug(m.TenantID),
		normKey(m.OwnBarcode),
		normKey(m.CompetitorBarcode),
		normKey(m.RetailerChain),
	}, "|")
	sum := sha1.Sum([]byte(key))
	return "cmap_" + hex.EncodeToString(sum[:])[:20]
}

// SaveCompetitorMapping upserts by dedupe key. Callers must not use this to backfill
// production seed pins in this PR — storage is ready for owner-driven adds only.
func (c *Client) SaveCompetitorMapping(ctx context.Context, m *domain.CompetitorMapping) error {
	if m == nil {
		return fmt.Errorf("competitor mapping cannot be nil")
	}
	slug := normalizeFirestoreTenantSlug(m.TenantID)
	m.TenantID = slug
	m.OwnBarcode = strings.TrimSpace(m.OwnBarcode)
	m.CompetitorBarcode = strings.TrimSpace(m.CompetitorBarcode)
	m.RetailerChain = strings.TrimSpace(m.RetailerChain)
	if m.OwnBarcode == "" || m.CompetitorBarcode == "" || m.RetailerChain == "" {
		return fmt.Errorf("own_barcode, competitor_barcode, and retailer_chain are required")
	}
	m.ID = CompetitorMappingID(m)
	now := time.Now().UTC()

	c.cmapMu.Lock()
	if c.cmaps == nil {
		c.cmaps = make(map[string]domain.CompetitorMapping)
	}
	if prev, ok := c.cmaps[m.ID]; ok && prev.TenantID == slug {
		m.CreatedAt, m.CreatedBy = prev.CreatedAt, prev.CreatedBy
	}
	c.cmapMu.Unlock()

	if c.fsClient != nil {
		doc := c.fsClient.Collection(competitorMappingsCollection).Doc(m.ID)
		if snap, err := doc.Get(ctx); err == nil {
			var existing domain.CompetitorMapping
			if snap.DataTo(&existing) == nil && existing.TenantID == slug && !existing.CreatedAt.IsZero() {
				m.CreatedAt, m.CreatedBy = existing.CreatedAt, existing.CreatedBy
			}
		}
	}
	if m.CreatedAt.IsZero() {
		m.CreatedAt = now
	}
	m.UpdatedAt = now

	if c.fsClient != nil {
		if _, err := c.fsClient.Collection(competitorMappingsCollection).Doc(m.ID).Set(ctx, *m); err != nil {
			return fmt.Errorf("firestore save competitor mapping: %w", err)
		}
	}
	c.cmapMu.Lock()
	c.cmaps[m.ID] = *m
	c.cmapMu.Unlock()
	return nil
}

// ListCompetitorMappings returns the tenant's approved mappings, newest first.
func (c *Client) ListCompetitorMappings(ctx context.Context, tenantID string, f domain.CompetitorMappingFilter) ([]domain.CompetitorMapping, error) {
	slug := normalizeFirestoreTenantSlug(tenantID)
	var all []domain.CompetitorMapping
	if c.fsClient != nil {
		it := c.fsClient.Collection(competitorMappingsCollection).Where("tenant_id", "==", slug).Documents(ctx)
		defer it.Stop()
		for {
			snap, err := it.Next()
			if err == iterator.Done {
				break
			}
			if err != nil {
				return nil, fmt.Errorf("firestore list competitor mappings: %w", err)
			}
			var m domain.CompetitorMapping
			if snap.DataTo(&m) == nil {
				all = append(all, m)
			}
		}
		c.cmapMu.Lock()
		if c.cmaps == nil {
			c.cmaps = make(map[string]domain.CompetitorMapping)
		}
		for _, m := range all {
			c.cmaps[m.ID] = m
		}
		c.cmapMu.Unlock()
	} else {
		c.cmapMu.RLock()
		for _, m := range c.cmaps {
			if m.TenantID == slug {
				all = append(all, m)
			}
		}
		c.cmapMu.RUnlock()
	}

	chain := normKey(f.Chain)
	if chain == "all" || chain == "الكل" {
		chain = ""
	}
	own := normKey(f.OwnBarcode)
	out := make([]domain.CompetitorMapping, 0, len(all))
	for _, m := range all {
		if chain != "" && normKey(m.RetailerChain) != chain {
			continue
		}
		if own != "" && normKey(m.OwnBarcode) != own {
			continue
		}
		out = append(out, m)
	}
	sort.Slice(out, func(i, j int) bool { return out[i].CreatedAt.After(out[j].CreatedAt) })
	return out, nil
}

// DeleteCompetitorMapping removes a mapping only if it belongs to tenantID.
func (c *Client) DeleteCompetitorMapping(ctx context.Context, tenantID, id string) error {
	slug := normalizeFirestoreTenantSlug(tenantID)
	id = strings.TrimSpace(id)
	if id == "" {
		return ErrCompetitorMappingNotFound
	}
	found := false
	c.cmapMu.Lock()
	if m, ok := c.cmaps[id]; ok {
		if m.TenantID != slug {
			c.cmapMu.Unlock()
			return ErrCompetitorMappingNotFound
		}
		delete(c.cmaps, id)
		found = true
	}
	c.cmapMu.Unlock()

	if c.fsClient != nil {
		doc := c.fsClient.Collection(competitorMappingsCollection).Doc(id)
		snap, err := doc.Get(ctx)
		if err != nil {
			if found {
				return nil
			}
			return ErrCompetitorMappingNotFound
		}
		var m domain.CompetitorMapping
		if snap.DataTo(&m) != nil || m.TenantID != slug {
			return ErrCompetitorMappingNotFound
		}
		if _, err := doc.Delete(ctx); err != nil {
			return fmt.Errorf("firestore delete competitor mapping: %w", err)
		}
		return nil
	}
	if !found {
		return ErrCompetitorMappingNotFound
	}
	return nil
}
