package firestore

import (
	"context"
	"fmt"
	"time"

	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"

	"github.com/tashil/data-sharing/backend/internal/domain"
)

const dataQualityCollection = "data_quality_issues"

// GetDataQualityState returns the tenant's persisted data-quality issues (empty when none).
func (c *Client) GetDataQualityState(ctx context.Context, tenantID string) (*domain.DataQualityState, error) {
	slug := normalizeFirestoreTenantSlug(tenantID)
	if c.fsClient != nil {
		snap, err := c.fsClient.Collection(dataQualityCollection).Doc(slug).Get(ctx)
		if err != nil {
			if status.Code(err) == codes.NotFound {
				return &domain.DataQualityState{TenantID: slug}, nil
			}
			return nil, fmt.Errorf("firestore get data quality: %w", err)
		}
		var d domain.DataQualityState
		if err := snap.DataTo(&d); err != nil {
			return nil, fmt.Errorf("decode data quality: %w", err)
		}
		d.TenantID = slug
		return &d, nil
	}
	c.dqMu.RLock()
	defer c.dqMu.RUnlock()
	d, ok := c.dqStates[slug]
	if !ok {
		return &domain.DataQualityState{TenantID: slug}, nil
	}
	cp := d
	cp.Issues = append([]domain.DataQualityIssue(nil), d.Issues...)
	cp.Runs = append([]domain.DataQualityRun(nil), d.Runs...)
	return &cp, nil
}

// SaveDataQualityState replaces the tenant's data-quality state.
func (c *Client) SaveDataQualityState(ctx context.Context, d *domain.DataQualityState) error {
	if d == nil {
		return fmt.Errorf("state cannot be nil")
	}
	slug := normalizeFirestoreTenantSlug(d.TenantID)
	d.TenantID = slug
	d.UpdatedAt = time.Now().UTC()
	if c.fsClient != nil {
		if _, err := c.fsClient.Collection(dataQualityCollection).Doc(slug).Set(ctx, *d); err != nil {
			return fmt.Errorf("firestore save data quality: %w", err)
		}
		return nil
	}
	c.dqMu.Lock()
	defer c.dqMu.Unlock()
	if c.dqStates == nil {
		c.dqStates = map[string]domain.DataQualityState{}
	}
	cp := *d
	cp.Issues = append([]domain.DataQualityIssue(nil), d.Issues...)
	cp.Runs = append([]domain.DataQualityRun(nil), d.Runs...)
	c.dqStates[slug] = cp
	return nil
}
