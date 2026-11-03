package handlers

import (
	"context"
	"net/http"
	"strings"

	"github.com/tashil/data-sharing/backend/internal/domain"
	"github.com/tashil/data-sharing/backend/internal/middleware"
	"github.com/tashil/data-sharing/backend/internal/service/ingestion"
)

// resolveUploadTenant honours a requested tenant_id only for a verified super_admin. Anyone else may
// send an empty tenant_id or one naming their own tenant in any spelling ("adeco", "tenant-adeco",
// "tenant_adeco"; see middleware.SameTenant); the TOKEN's own value is then returned, so a non-super_admin
// is never routed anywhere but its token tenant. A different tenant is refused with 403.
func resolveUploadTenant(w http.ResponseWriter, c *domain.UserClaims, tokenTenant, requested string) (string, bool) {
	requested = strings.TrimSpace(requested)
	if requested == "" || middleware.SameTenant(requested, tokenTenant) {
		return tokenTenant, true
	}
	if c != nil && c.Role == domain.RoleSuperAdmin {
		return requested, true
	}
	writeErr(w, http.StatusForbidden, "forbidden: you cannot upload to another tenant")
	return "", false
}

// applySystemTenantOverride is the ?tenant= / X-Tenant-ID / form "tenant" rule of the general upload,
// commit, archive list and archive download handlers: only a "system"/"all" token tenant (exact legacy
// spellings, see middleware.IsSystemTenant) is replaced by a non-empty override; anyone else keeps its own.
func applySystemTenantOverride(tokenTenant, override string) string {
	if override != "" && middleware.IsSystemTenant(tokenTenant) {
		return override
	}
	return tokenTenant
}

// requireSuperForReplace lets only a verified super_admin replace (delete) an existing archive.
func requireSuperForReplace(w http.ResponseWriter, c *domain.UserClaims) bool {
	if c != nil && c.Role == domain.RoleSuperAdmin {
		return true
	}
	writeErr(w, http.StatusForbidden, "forbidden: only a super admin can replace an archived file")
	return false
}

// deleteReplacedArchive removes the replaced archive only after a successful upload. It never deletes the
// archive just written: a re-upload of the same file and chain already reused or replaced that entry, and
// deleting it by file name would also purge the new rows.
func deleteReplacedArchive(ctx context.Context, p *ingestion.Processor, tenantID, replaceID string, res *ingestion.IngestionResult) {
	if replaceID == "" || res == nil || res.ArchiveID == "" || res.ArchiveID == replaceID {
		return
	}
	old, _, err := p.GetArchivedFile(ctx, tenantID, replaceID)
	if err != nil || old == nil {
		return
	}
	if cur, _, cErr := p.GetArchivedFile(ctx, tenantID, res.ArchiveID); cErr == nil && cur != nil &&
		strings.EqualFold(cur.FileName, old.FileName) && strings.EqualFold(cur.RetailChain, old.RetailChain) {
		return
	}
	_, _ = p.DeleteArchivedFile(ctx, old.TenantID, old.ID)
}
