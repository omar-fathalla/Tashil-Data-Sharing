package handlers

import (
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/tashil/data-sharing/backend/internal/domain"
	"github.com/tashil/data-sharing/backend/internal/middleware"
	"github.com/tashil/data-sharing/backend/internal/service/bigquery"
	"github.com/tashil/data-sharing/backend/internal/service/firestore"
	"github.com/tashil/data-sharing/backend/internal/service/gemini"
	"github.com/tashil/data-sharing/backend/internal/service/ingestion"
)

func TestArchiveDeleteHTTPStatusMapping(t *testing.T) {
	st, code, _ := archiveDeleteHTTPStatus(ingestion.ErrArchivedFileNotFound)
	if st != http.StatusNotFound || code != "archived_file_not_found" {
		t.Fatalf("not found mapping: %d %s", st, code)
	}
	st, code, _ = archiveDeleteHTTPStatus(&ingestion.ArchiveDeleteError{Stage: "bigquery", Message: "failed"})
	if st != http.StatusBadGateway || code != "archive_delete_analytics_failed" {
		t.Fatalf("bigquery mapping: %d %s", st, code)
	}
	st, code, _ = archiveDeleteHTTPStatus(&ingestion.ArchiveDeleteError{Stage: "firestore", Message: "partial"})
	if st != http.StatusInternalServerError || code != "archive_delete_partial" {
		t.Fatalf("firestore mapping: %d %s", st, code)
	}
	st, code, _ = archiveDeleteHTTPStatus(errors.New("other"))
	if st != http.StatusInternalServerError || code != "delete_failed" {
		t.Fatalf("default mapping: %d %s", st, code)
	}
}

func archiveDeleteTestEnv(t *testing.T) (*ingestion.Processor, http.Handler, *middleware.AuthMiddleware) {
	t.Helper()
	setupIsolatedProductMasterDir(t)
	bq := bigquery.NewClient("test-project", "test-dataset", true)
	fs := firestore.NewClient("test-db", true)
	proc := ingestion.NewProcessor(gemini.NewAgent("", "gemini-2.5-flash", true), bq, fs).WithArchiveDir(t.TempDir())
	mw := middleware.NewAuthMiddleware("test-secret", false)
	up := NewUploadHandler(proc)
	mux := http.NewServeMux()
	mux.HandleFunc("DELETE /api/v1/ingest/archive/{id}", up.HandleDeleteArchive)
	mux.HandleFunc("GET /api/v1/ingest/archive", up.HandleListArchive)
	return proc, mw.Handler(mux), mw
}

func tokenWithTenant(t *testing.T, mw *middleware.AuthMiddleware, role domain.UserRole, tenant string) string {
	t.Helper()
	tok, err := mw.GenerateToken(domain.UserClaims{
		UserID: "u-" + string(role), TenantID: tenant, Role: role,
	}, time.Hour)
	if err != nil {
		t.Fatal(err)
	}
	return tok
}

// Mohamed 7 Nov 2026: company manager (vendor_admin) must delete files inside its own tenant.
func TestCompanyManagerCanDeleteOwnTenantArchive(t *testing.T) {
	proc, h, mw := archiveDeleteTestEnv(t)
	entry := proc.SaveArchivedFile("tenant-adeco", "batch_1", "2026 out.xlsx", []byte("x"), "fathalla", "2026", "01", 1, 1, 1)
	tok := tokenWithTenant(t, mw, domain.RoleVendorAdmin, "tenant-adeco")

	req := httptest.NewRequest(http.MethodDelete, "/api/v1/ingest/archive/"+entry.ID+"?file_name=2026+out.xlsx", nil)
	req.Header.Set("Authorization", "Bearer "+tok)
	req.Header.Set("X-Tenant-ID", "tenant-adeco")
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("company manager delete own file: want 200, got %d %s", rec.Code, rec.Body.String())
	}

	listReq := httptest.NewRequest(http.MethodGet, "/api/v1/ingest/archive?file_type=sell_out", nil)
	listReq.Header.Set("Authorization", "Bearer "+tok)
	listReq.Header.Set("X-Tenant-ID", "tenant-adeco")
	listRec := httptest.NewRecorder()
	h.ServeHTTP(listRec, listReq)
	if listRec.Code != http.StatusOK {
		t.Fatalf("list after delete: want 200, got %d %s", listRec.Code, listRec.Body.String())
	}
	var payload map[string]interface{}
	if err := json.Unmarshal(listRec.Body.Bytes(), &payload); err != nil {
		t.Fatal(err)
	}
	files, _ := payload["files"].([]interface{})
	if len(files) != 0 {
		t.Fatalf("successful company-manager delete must clear the file from the list, got %d: %s", len(files), listRec.Body.String())
	}
}

// Company manager of tenant A must not delete tenant B's archive, even with a foreign X-Tenant-ID header.
func TestCompanyManagerCannotDeleteCrossTenantArchive(t *testing.T) {
	proc, h, mw := archiveDeleteTestEnv(t)
	other := proc.SaveArchivedFile("tenant-other", "batch_other", "other out.xlsx", []byte("y"), "fathalla", "2026", "01", 1, 1, 1)
	tok := tokenWithTenant(t, mw, domain.RoleVendorAdmin, "tenant-adeco")

	// Attempt 1: spoof X-Tenant-ID to the foreign tenant (ignored for non-super_admin).
	req := httptest.NewRequest(http.MethodDelete, "/api/v1/ingest/archive/"+other.ID, nil)
	req.Header.Set("Authorization", "Bearer "+tok)
	req.Header.Set("X-Tenant-ID", "tenant-other")
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	if rec.Code == http.StatusOK {
		t.Fatalf("cross-tenant delete via X-Tenant-ID must not succeed, got %d %s", rec.Code, rec.Body.String())
	}

	// Archive must still exist for the foreign tenant.
	if _, _, err := proc.GetArchivedFile(req.Context(), "tenant-other", other.ID); err != nil {
		t.Fatalf("foreign archive must survive refused cross-tenant delete: %v", err)
	}

	// Attempt 2: same-token tenant context, foreign archive id — lookup fails / unauthorized.
	req2 := httptest.NewRequest(http.MethodDelete, "/api/v1/ingest/archive/"+other.ID, nil)
	req2.Header.Set("Authorization", "Bearer "+tok)
	req2.Header.Set("X-Tenant-ID", "tenant-adeco")
	rec2 := httptest.NewRecorder()
	h.ServeHTTP(rec2, req2)
	if rec2.Code == http.StatusOK {
		t.Fatalf("deleting another tenant's archive id under own tenant must not succeed, got %d %s", rec2.Code, rec2.Body.String())
	}
	if _, _, err := proc.GetArchivedFile(req2.Context(), "tenant-other", other.ID); err != nil {
		t.Fatalf("foreign archive must still exist: %v", err)
	}
}

// NSM (and other non-manager roles) still cannot delete; company manager and super_admin can.
func TestArchiveDeleteRoleGateMatchesCompanyManagerPolicy(t *testing.T) {
	if !destructiveWriteRoles[domain.RoleSuperAdmin] || !destructiveWriteRoles[domain.RoleVendorAdmin] {
		t.Fatal("super_admin and vendor_admin (company manager) must be allowed to delete archives")
	}
	for _, role := range []domain.UserRole{
		domain.RoleNationalSalesManager, domain.RoleChainKAM, domain.RoleFieldSupervisor, domain.RoleSalesUser,
	} {
		if destructiveWriteRoles[role] {
			t.Fatalf("%s must not be allowed to delete archives", role)
		}
	}
	// Sell-Out and Sell-In share HandleDeleteArchive + the same gate.
	if !ingestWriteRoles[domain.RoleVendorAdmin] {
		t.Fatal("upload and delete should both allow company manager (vendor_admin)")
	}
}
