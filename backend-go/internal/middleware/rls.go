package middleware

import (
	"context"
	"errors"
	"fmt"
	"net/http"

	"github.com/tashil/data-sharing/backend/internal/domain"
)

var (
	ErrNoTenantContext = errors.New("no tenant context present in request")
	ErrTenantForbidden = errors.New("insufficient privileges to access tenant data")
)

// EnforceTenantRLS ensures the authenticated request has a valid tenant ID
// and returns that tenant ID for filtering queries.
func EnforceTenantRLS(r *http.Request) (string, error) {
	claims, ok := GetUserClaims(r.Context())
	if !ok || claims == nil || claims.TenantID == "" {
		return "", ErrNoTenantContext
	}
	return claims.TenantID, nil
}

// AssertTenantMatch checks if an entity's TenantID strictly matches the caller's TenantID.
func AssertTenantMatch(ctx context.Context, targetTenantID string) error {
	claims, ok := GetUserClaims(ctx)
	if !ok || claims == nil {
		return ErrNoTenantContext
	}
	// Only SuperAdmin can access any tenant, others must match their own
	if claims.Role != domain.RoleSuperAdmin {
		if !SameTenant(claims.TenantID, targetTenantID) {
			return fmt.Errorf("%w: user tenant '%s' cannot access '%s'", ErrTenantForbidden, claims.TenantID, targetTenantID)
		}
	}
	return nil
}
