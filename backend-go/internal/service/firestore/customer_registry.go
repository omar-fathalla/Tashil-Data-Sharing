package firestore

import (
	"context"
	"fmt"

	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"

	"github.com/tashil/data-sharing/backend/internal/service/customers"
)

const customerRegistryCollection = "sellin_customer_registry"

// GetCustomerRegistry returns the tenant's Sell-In customer registry (seed names are embedded, not stored).
func (c *Client) GetCustomerRegistry(ctx context.Context, tenantID string) (*customers.State, error) {
	slug := normalizeFirestoreTenantSlug(tenantID)
	if c.fsClient == nil {
		st, err := c.crMem.GetCustomerRegistry(ctx, slug)
		if st != nil {
			st.TenantID = tenantID
		}
		return st, err
	}
	snap, err := c.fsClient.Collection(customerRegistryCollection).Doc(slug).Get(ctx)
	if err != nil {
		if status.Code(err) == codes.NotFound {
			return &customers.State{TenantID: tenantID}, nil
		}
		return nil, fmt.Errorf("firestore get customer registry: %w", err)
	}
	var st customers.State
	if err := snap.DataTo(&st); err != nil {
		return nil, fmt.Errorf("decode customer registry: %w", err)
	}
	st.TenantID = tenantID
	return &st, nil
}

// SaveCustomerRegistry replaces the tenant's registry document.
func (c *Client) SaveCustomerRegistry(ctx context.Context, st *customers.State) error {
	if st == nil {
		return fmt.Errorf("registry cannot be nil")
	}
	slug := normalizeFirestoreTenantSlug(st.TenantID)
	if c.fsClient == nil {
		cp := *st
		cp.TenantID = slug
		return c.crMem.SaveCustomerRegistry(ctx, &cp)
	}
	if _, err := c.fsClient.Collection(customerRegistryCollection).Doc(slug).Set(ctx, *st); err != nil {
		return fmt.Errorf("firestore save customer registry: %w", err)
	}
	return nil
}
