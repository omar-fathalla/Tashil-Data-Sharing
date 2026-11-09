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

const competitorSuggestionsCollection = "competitor_suggestions"

// ErrCompetitorSuggestionNotFound is returned when a quarantine row is missing.
var ErrCompetitorSuggestionNotFound = errors.New("competitor suggestion not found")

// CompetitorSuggestionRepository persists AI suggestions in quarantine only.
// Pending rows must never feed Compare KPIs or competitor_mappings until approved.
type CompetitorSuggestionRepository interface {
	SaveCompetitorSuggestion(ctx context.Context, s *domain.CompetitorSuggestion) error
	ListCompetitorSuggestions(ctx context.Context, tenantID string, f domain.CompetitorSuggestionFilter) ([]domain.CompetitorSuggestion, error)
	GetCompetitorSuggestion(ctx context.Context, tenantID, id string) (*domain.CompetitorSuggestion, error)
	UpdateCompetitorSuggestionStatus(ctx context.Context, tenantID, id, status, reviewedBy string) (*domain.CompetitorSuggestion, error)
}

// CompetitorSuggestionID is deterministic: tenant|own|competitor|chain.
func CompetitorSuggestionID(s *domain.CompetitorSuggestion) string {
	key := strings.Join([]string{
		normalizeFirestoreTenantSlug(s.TenantID),
		normKey(s.OwnBarcode),
		normKey(s.CompetitorBarcode),
		normKey(s.RetailerChain),
	}, "|")
	sum := sha1.Sum([]byte(key))
	return "csug_" + hex.EncodeToString(sum[:])[:20]
}

// RejectedPairKey identifies a remembered rejected own→competitor pair for a chain.
func RejectedPairKey(ownBarcode, competitorBarcode, chain string) string {
	return strings.Join([]string{normKey(ownBarcode), normKey(competitorBarcode), normKey(chain)}, "|")
}

// SaveCompetitorSuggestion upserts a quarantine row. Idempotent on the same pair key:
// re-running suggestions refreshes reason/confidence but does not revive rejected rows
// (caller should skip rejected pairs) and does not touch approved mappings.
func (c *Client) SaveCompetitorSuggestion(ctx context.Context, s *domain.CompetitorSuggestion) error {
	if s == nil {
		return fmt.Errorf("competitor suggestion cannot be nil")
	}
	slug := normalizeFirestoreTenantSlug(s.TenantID)
	s.TenantID = slug
	s.OwnBarcode = strings.TrimSpace(s.OwnBarcode)
	s.CompetitorBarcode = strings.TrimSpace(s.CompetitorBarcode)
	s.RetailerChain = strings.TrimSpace(s.RetailerChain)
	if s.OwnBarcode == "" || s.CompetitorBarcode == "" || s.RetailerChain == "" {
		return fmt.Errorf("own_barcode, competitor_barcode, and retailer_chain are required")
	}
	if s.Status == "" {
		s.Status = domain.CompetitorSuggestionPending
	}
	s.ID = CompetitorSuggestionID(s)
	now := time.Now().UTC()

	c.csugMu.Lock()
	if c.csugs == nil {
		c.csugs = make(map[string]domain.CompetitorSuggestion)
	}
	if prev, ok := c.csugs[s.ID]; ok && prev.TenantID == slug {
		// Never overwrite a terminal reject/approve via Save — use UpdateStatus.
		if prev.Status == domain.CompetitorSuggestionRejected || prev.Status == domain.CompetitorSuggestionApproved {
			c.csugMu.Unlock()
			*s = prev
			return nil
		}
		s.CreatedAt, s.CreatedBy = prev.CreatedAt, prev.CreatedBy
	}
	c.csugMu.Unlock()

	if c.fsClient != nil {
		doc := c.fsClient.Collection(competitorSuggestionsCollection).Doc(s.ID)
		if snap, err := doc.Get(ctx); err == nil {
			var existing domain.CompetitorSuggestion
			if snap.DataTo(&existing) == nil && existing.TenantID == slug {
				if existing.Status == domain.CompetitorSuggestionRejected || existing.Status == domain.CompetitorSuggestionApproved {
					*s = existing
					return nil
				}
				if !existing.CreatedAt.IsZero() {
					s.CreatedAt, s.CreatedBy = existing.CreatedAt, existing.CreatedBy
				}
			}
		}
	}
	if s.CreatedAt.IsZero() {
		s.CreatedAt = now
	}
	s.UpdatedAt = now

	if c.fsClient != nil {
		if _, err := c.fsClient.Collection(competitorSuggestionsCollection).Doc(s.ID).Set(ctx, *s); err != nil {
			return fmt.Errorf("firestore save competitor suggestion: %w", err)
		}
	}
	c.csugMu.Lock()
	c.csugs[s.ID] = *s
	c.csugMu.Unlock()
	return nil
}

// ListCompetitorSuggestions returns quarantine rows newest-first.
func (c *Client) ListCompetitorSuggestions(ctx context.Context, tenantID string, f domain.CompetitorSuggestionFilter) ([]domain.CompetitorSuggestion, error) {
	slug := normalizeFirestoreTenantSlug(tenantID)
	var all []domain.CompetitorSuggestion
	if c.fsClient != nil {
		it := c.fsClient.Collection(competitorSuggestionsCollection).Where("tenant_id", "==", slug).Documents(ctx)
		defer it.Stop()
		for {
			snap, err := it.Next()
			if err == iterator.Done {
				break
			}
			if err != nil {
				return nil, fmt.Errorf("firestore list competitor suggestions: %w", err)
			}
			var s domain.CompetitorSuggestion
			if snap.DataTo(&s) == nil {
				all = append(all, s)
			}
		}
		c.csugMu.Lock()
		if c.csugs == nil {
			c.csugs = make(map[string]domain.CompetitorSuggestion)
		}
		for _, s := range all {
			c.csugs[s.ID] = s
		}
		c.csugMu.Unlock()
	} else {
		c.csugMu.RLock()
		for _, s := range c.csugs {
			if s.TenantID == slug {
				all = append(all, s)
			}
		}
		c.csugMu.RUnlock()
	}

	chain := normKey(f.Chain)
	if chain == "all" || chain == "الكل" {
		chain = ""
	}
	status := strings.ToLower(strings.TrimSpace(f.Status))
	own := normKey(f.OwnBarcode)
	out := make([]domain.CompetitorSuggestion, 0, len(all))
	for _, s := range all {
		if chain != "" && normKey(s.RetailerChain) != chain {
			continue
		}
		if status != "" && strings.ToLower(s.Status) != status {
			continue
		}
		if own != "" && normKey(s.OwnBarcode) != own {
			continue
		}
		out = append(out, s)
	}
	sort.Slice(out, func(i, j int) bool {
		if out[i].CreatedAt.Equal(out[j].CreatedAt) {
			return out[i].Rank < out[j].Rank
		}
		return out[i].CreatedAt.After(out[j].CreatedAt)
	})
	return out, nil
}

// GetCompetitorSuggestion loads one quarantine row scoped to the tenant.
func (c *Client) GetCompetitorSuggestion(ctx context.Context, tenantID, id string) (*domain.CompetitorSuggestion, error) {
	slug := normalizeFirestoreTenantSlug(tenantID)
	id = strings.TrimSpace(id)
	if id == "" {
		return nil, ErrCompetitorSuggestionNotFound
	}
	c.csugMu.RLock()
	if s, ok := c.csugs[id]; ok && s.TenantID == slug {
		cp := s
		c.csugMu.RUnlock()
		return &cp, nil
	}
	c.csugMu.RUnlock()

	if c.fsClient != nil {
		snap, err := c.fsClient.Collection(competitorSuggestionsCollection).Doc(id).Get(ctx)
		if err != nil {
			return nil, ErrCompetitorSuggestionNotFound
		}
		var s domain.CompetitorSuggestion
		if snap.DataTo(&s) != nil || s.TenantID != slug {
			return nil, ErrCompetitorSuggestionNotFound
		}
		c.csugMu.Lock()
		if c.csugs == nil {
			c.csugs = make(map[string]domain.CompetitorSuggestion)
		}
		c.csugs[s.ID] = s
		c.csugMu.Unlock()
		return &s, nil
	}
	return nil, ErrCompetitorSuggestionNotFound
}

// UpdateCompetitorSuggestionStatus sets approved/rejected. Idempotent for same status.
func (c *Client) UpdateCompetitorSuggestionStatus(ctx context.Context, tenantID, id, status, reviewedBy string) (*domain.CompetitorSuggestion, error) {
	status = strings.ToLower(strings.TrimSpace(status))
	if status != domain.CompetitorSuggestionApproved && status != domain.CompetitorSuggestionRejected {
		return nil, fmt.Errorf("status must be approved or rejected")
	}
	s, err := c.GetCompetitorSuggestion(ctx, tenantID, id)
	if err != nil {
		return nil, err
	}
	if s.Status == status {
		return s, nil
	}
	if s.Status != domain.CompetitorSuggestionPending {
		return nil, fmt.Errorf("suggestion already decided as %s", s.Status)
	}
	now := time.Now().UTC()
	s.Status = status
	s.ReviewedBy = strings.TrimSpace(reviewedBy)
	s.ReviewedAt = now
	s.UpdatedAt = now

	if c.fsClient != nil {
		if _, err := c.fsClient.Collection(competitorSuggestionsCollection).Doc(s.ID).Set(ctx, *s); err != nil {
			return nil, fmt.Errorf("firestore update competitor suggestion: %w", err)
		}
	}
	c.csugMu.Lock()
	if c.csugs == nil {
		c.csugs = make(map[string]domain.CompetitorSuggestion)
	}
	c.csugs[s.ID] = *s
	c.csugMu.Unlock()
	return s, nil
}
