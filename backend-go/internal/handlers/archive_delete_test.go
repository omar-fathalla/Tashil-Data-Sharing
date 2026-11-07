package handlers

import (
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
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

func TestVendorAdminDeleteArchiveReturns403AndLeavesListIntact(t *testing.T) {
	setupIsolatedProductMasterDir(t)
	bq := bigquery.NewClient("test-project", "test-dataset", true)
	fs := firestore.NewClient("test-db", true)
	proc := ingestion.NewProcessor(gemini.NewAgent("", "gemini-2.5-flash", true), bq, fs).WithArchiveDir(t.TempDir())
	entry := proc.SaveArchivedFile("tenant-adeco", "batch_1", "2026 out.xlsx", []byte("x"), "fathalla", "2026", "01", 1, 1, 1)

	mw := middleware.NewAuthMiddleware("test-secret", false)
	up := NewUploadHandler(proc)
	mux := http.NewServeMux()
	mux.HandleFunc("DELETE /api/v1/ingest/archive/{id}", up.HandleDeleteArchive)
	mux.HandleFunc("GET /api/v1/ingest/archive", up.HandleListArchive)
	h := mw.Handler(mux)

	tok, err := mw.GenerateToken(domain.UserClaims{
		UserID: "va", TenantID: "tenant-adeco", Role: domain.RoleVendorAdmin,
	}, time.Hour)
	if err != nil {
		t.Fatal(err)
	}

	req := httptest.NewRequest(http.MethodDelete, "/api/v1/ingest/archive/"+entry.ID+"?file_name=2026+out.xlsx", nil)
	req.Header.Set("Authorization", "Bearer "+tok)
	req.Header.Set("X-Tenant-ID", "tenant-adeco")
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	if rec.Code != http.StatusForbidden {
		t.Fatalf("vendor_admin delete: want 403, got %d %s", rec.Code, rec.Body.String())
	}
	if !strings.Contains(strings.ToLower(rec.Body.String()), "super_admin") {
		t.Fatalf("403 body should mention super_admin requirement: %s", rec.Body.String())
	}

	listReq := httptest.NewRequest(http.MethodGet, "/api/v1/ingest/archive?file_type=sell_out", nil)
	listReq.Header.Set("Authorization", "Bearer "+tok)
	listReq.Header.Set("X-Tenant-ID", "tenant-adeco")
	listRec := httptest.NewRecorder()
	h.ServeHTTP(listRec, listReq)
	if listRec.Code != http.StatusOK {
		t.Fatalf("list after 403: want 200, got %d %s", listRec.Code, listRec.Body.String())
	}
	var payload map[string]interface{}
	if err := json.Unmarshal(listRec.Body.Bytes(), &payload); err != nil {
		t.Fatal(err)
	}
	files, _ := payload["files"].([]interface{})
	if len(files) != 1 {
		t.Fatalf("file must stay listed after 403, got %d files: %s", len(files), listRec.Body.String())
	}
}

func TestSuperAdminAndVendorAdminShareSameDeleteGateConsistency(t *testing.T) {
	// Sell-Out and Sell-In both use HandleDeleteArchive + destructiveWriteRoles.
	if !destructiveWriteRoles[domain.RoleSuperAdmin] {
		t.Fatal("super_admin must be allowed to delete archives")
	}
	if destructiveWriteRoles[domain.RoleVendorAdmin] {
		t.Fatal("vendor_admin must remain refused until Mohamed changes policy")
	}
	if ingestWriteRoles[domain.RoleVendorAdmin] != true {
		t.Fatal("upload still allows vendor_admin; delete policy is intentionally stricter")
	}
}
