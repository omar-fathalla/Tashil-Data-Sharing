package handlers

import (
	"fmt"
	"net/http"
	"strings"

	"github.com/tashil/data-sharing/backend/internal/domain"
	"github.com/tashil/data-sharing/backend/internal/middleware"
)

// Write gates. Every write uses the token's own (verified) role via middleware.WriteClaims, never the
// X-Simulated-Role / X-Assigned-* headers. Changing who may write is a one-line change here.

// ingestWriteRoles may upload, dry-run, commit, discard, reapply, and write targets / product master
// (Mohamed, 3 Nov 2026: super_admin + vendor_admin only).
var ingestWriteRoles = map[domain.UserRole]bool{
	domain.RoleSuperAdmin:  true,
	domain.RoleVendorAdmin: true,
}

// destructiveWriteRoles may clear data (any scope) and delete archive entries (Sell-Out and Sell-In
// share HandleDeleteArchive, so both use this same gate).
//
// Policy (Mohamed, 7 Nov 2026):
//   - Allowed: super_admin + vendor_admin (مدير الشركة / company manager / tenant admin)
//   - Refused: national_sales_manager, chain_kam, and every other role
//
// The company-manager account is the only tenant role used in tests and must have full in-tenant
// permissions (upload, add, delete Sell-Out/Sell-In, clear). Cross-tenant deletes remain blocked by
// EnforceTenantRLS / SameTenant — vendor_admin may only act inside its own tenant token.
var destructiveWriteRoles = map[domain.UserRole]bool{
	domain.RoleSuperAdmin:  true,
	domain.RoleVendorAdmin: true,
}

// chainWriteRoles may create / update / delete retail chains (legacy "admin" dropped).
var chainWriteRoles = map[domain.UserRole]bool{
	domain.RoleSuperAdmin:  true,
	domain.RoleVendorAdmin: true,
}

// requireWriteRole returns the verified write claims when their role is in roles; otherwise it writes
// 401 (no claims / tenant) or 403 and returns false.
func requireWriteRole(w http.ResponseWriter, r *http.Request, roles map[domain.UserRole]bool) (*domain.UserClaims, bool) {
	c, ok := middleware.WriteClaims(r.Context())
	if !ok || c == nil || strings.TrimSpace(c.TenantID) == "" {
		writeErr(w, http.StatusUnauthorized, "unauthorized tenant context")
		return nil, false
	}
	if !roles[c.Role] {
		writeErr(w, http.StatusForbidden, fmt.Sprintf(
			"Forbidden: your role cannot perform this action (role=%s; archive delete and clear require super_admin or vendor_admin)",
			c.Role,
		))
		return nil, false
	}
	return c, true
}

// tmWriteClaims is tmClaims for write handlers: verified role, never header-simulated.
func tmWriteClaims(w http.ResponseWriter, r *http.Request) (*domain.UserClaims, bool) {
	c, ok := middleware.WriteClaims(r.Context())
	if !ok || c == nil || strings.TrimSpace(c.TenantID) == "" {
		writeErr(w, http.StatusUnauthorized, "unauthorized tenant context")
		return nil, false
	}
	return c, true
}
