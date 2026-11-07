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
// Current rule (keep until Mohamed decides otherwise):
//   - Allowed: super_admin only
//   - Refused: vendor_admin, national_sales_manager, chain_kam, and every other role
//
// Why adeco tenant accounts get 403 on DELETE /api/v1/ingest/archive/{id}:
// they authenticate as vendor_admin (or another non-super_admin role). The gate runs before any
// BigQuery/Firestore mutation. This is an application role check, not Google IAM.
//
// Policy note: upload already allows vendor_admin (ingestWriteRoles). Whether archive delete
// should match upload (vendor_admin too) is Mohamed's decision — do not loosen here casually.
var destructiveWriteRoles = map[domain.UserRole]bool{
	domain.RoleSuperAdmin: true,
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
			"Forbidden: your role cannot perform this action (role=%s; archive delete and clear require super_admin)",
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
