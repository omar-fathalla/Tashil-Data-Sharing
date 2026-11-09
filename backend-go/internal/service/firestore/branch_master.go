package firestore

import (
	"context"
	"fmt"

	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"

	"github.com/tashil/data-sharing/backend/internal/service/branchmaster"
)

const branchMasterCollection = "branch_master"

// GetBranchMaster returns the tenant's branch/chain/alias master (empty when missing).
func (c *Client) GetBranchMaster(ctx context.Context, tenantID string) (*branchmaster.State, error) {
	slug := normalizeFirestoreTenantSlug(tenantID)
	if c.fsClient == nil {
		st, err := c.bmMem.GetBranchMaster(ctx, slug)
		if st != nil {
			st.TenantID = tenantID
		}
		return st, err
	}
	snap, err := c.fsClient.Collection(branchMasterCollection).Doc(slug).Get(ctx)
	if err != nil {
		if status.Code(err) == codes.NotFound {
			return &branchmaster.State{TenantID: tenantID}, nil
		}
		return nil, fmt.Errorf("firestore get branch master: %w", err)
	}
	var st branchmaster.State
	if err := snap.DataTo(&st); err != nil {
		return nil, fmt.Errorf("decode branch master: %w", err)
	}
	st.TenantID = tenantID
	return &st, nil
}

// SaveBranchMaster replaces the tenant's branch master document.
func (c *Client) SaveBranchMaster(ctx context.Context, st *branchmaster.State) error {
	if st == nil {
		return fmt.Errorf("branch master cannot be nil")
	}
	slug := normalizeFirestoreTenantSlug(st.TenantID)
	if c.fsClient == nil {
		cp := *st
		cp.TenantID = slug
		return c.bmMem.SaveBranchMaster(ctx, &cp)
	}
	if _, err := c.fsClient.Collection(branchMasterCollection).Doc(slug).Set(ctx, *st); err != nil {
		return fmt.Errorf("firestore save branch master: %w", err)
	}
	return nil
}
