package firestore

import (
	"context"
	"fmt"
	"sync"
	"time"

	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"

	"github.com/tashil/data-sharing/backend/internal/service/matcher"
)

const productMatchCollection = "product_match_reviews"

// productMatchMem is the mock/fallback store when Cloud Firestore is not configured.
// It lives on Client so Get/Save share one map across Queue instances (restart simulation
// still uses matcher.MemoryStore directly in unit tests).
type productMatchMem struct {
	mu sync.Mutex
	m  map[string]matcher.State
}

func (c *Client) pmMem() *productMatchMem {
	// Lazy init under dqMu reuse is awkward; use dedicated field via sync.Once pattern on first call.
	c.pmOnce.Do(func() {
		c.pmStates = &productMatchMem{m: map[string]matcher.State{}}
	})
	return c.pmStates
}

// GetProductMatchState returns the tenant's durable product-match review queue.
func (c *Client) GetProductMatchState(ctx context.Context, tenantID string) (*matcher.State, error) {
	slug := normalizeFirestoreTenantSlug(tenantID)
	if c.fsClient != nil {
		snap, err := c.fsClient.Collection(productMatchCollection).Doc(slug).Get(ctx)
		if err != nil {
			if status.Code(err) == codes.NotFound {
				return &matcher.State{TenantID: slug, Metrics: matcher.Metrics{TenantID: slug}}, nil
			}
			return nil, fmt.Errorf("firestore get product match: %w", err)
		}
		var st matcher.State
		if err := snap.DataTo(&st); err != nil {
			return nil, fmt.Errorf("decode product match: %w", err)
		}
		if st.TenantID != "" && normalizeFirestoreTenantSlug(st.TenantID) != slug {
			return nil, fmt.Errorf("tenant mismatch: store=%s request=%s", st.TenantID, slug)
		}
		st.TenantID = slug
		st.Metrics.TenantID = slug
		return &st, nil
	}
	mem := c.pmMem()
	mem.mu.Lock()
	defer mem.mu.Unlock()
	st, ok := mem.m[slug]
	if !ok {
		return &matcher.State{TenantID: slug, Metrics: matcher.Metrics{TenantID: slug}}, nil
	}
	if st.TenantID != "" && normalizeFirestoreTenantSlug(st.TenantID) != slug {
		return nil, fmt.Errorf("tenant mismatch: store=%s request=%s", st.TenantID, slug)
	}
	cp := st
	cp.Items = append([]matcher.ReviewItem(nil), st.Items...)
	cp.TenantID = slug
	cp.Metrics.TenantID = slug
	return &cp, nil
}

// SaveProductMatchState replaces the tenant's product-match review document.
func (c *Client) SaveProductMatchState(ctx context.Context, st *matcher.State) error {
	if st == nil {
		return fmt.Errorf("state cannot be nil")
	}
	slug := normalizeFirestoreTenantSlug(st.TenantID)
	if slug == "" {
		return fmt.Errorf("tenant_id required")
	}
	if st.TenantID != "" && normalizeFirestoreTenantSlug(st.TenantID) != slug {
		return fmt.Errorf("tenant mismatch on save")
	}
	st.TenantID = slug
	st.Metrics.TenantID = slug
	st.UpdatedAt = time.Now().UTC()
	if c.fsClient != nil {
		if _, err := c.fsClient.Collection(productMatchCollection).Doc(slug).Set(ctx, *st); err != nil {
			return fmt.Errorf("firestore save product match: %w", err)
		}
		return nil
	}
	mem := c.pmMem()
	mem.mu.Lock()
	defer mem.mu.Unlock()
	if mem.m == nil {
		mem.m = map[string]matcher.State{}
	}
	cp := *st
	cp.Items = append([]matcher.ReviewItem(nil), st.Items...)
	mem.m[slug] = cp
	return nil
}
