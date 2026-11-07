package handlers

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/tashil/data-sharing/backend/internal/domain"
	"github.com/tashil/data-sharing/backend/internal/middleware"
	"github.com/tashil/data-sharing/backend/internal/service/bigquery"
	"github.com/tashil/data-sharing/backend/internal/service/firestore"
	"github.com/tashil/data-sharing/backend/internal/service/gemini"
	"github.com/tashil/data-sharing/backend/internal/service/ingestion"
)

func TestVendorAdminWildcardClearRejected(t *testing.T) {
	setupIsolatedProductMasterDir(t)
	bq := bigquery.NewClient("test-project", "test-dataset", true)
	fs := firestore.NewClient("test-db", true)
	proc := ingestion.NewProcessor(gemini.NewAgent("", "gemini-2.5-flash", true), bq, fs).WithArchiveDir(t.TempDir())
	mw := middleware.NewAuthMiddleware("test-secret", false)
	up := NewUploadHandler(proc)
	mux := http.NewServeMux()
	mux.HandleFunc("POST /api/v1/ingest/clear", up.HandleClearData)
	mux.HandleFunc("DELETE /api/v1/ingest/clear", up.HandleClearData)
	h := mw.Handler(mux)

	va := tokenWithTenant(t, mw, domain.RoleVendorAdmin, "tenant-adeco")
	for _, path := range []string{
		"/api/v1/ingest/clear?scope=all",
		"/api/v1/ingest/clear?scope=%2A",
		"/api/v1/ingest/clear?scope=*",
	} {
		for _, method := range []string{http.MethodPost, http.MethodDelete} {
			req := httptest.NewRequest(method, path, nil)
			req.Header.Set("Authorization", "Bearer "+va)
			req.Header.Set("X-Tenant-ID", "tenant-adeco")
			rec := httptest.NewRecorder()
			h.ServeHTTP(rec, req)
			if rec.Code != http.StatusForbidden {
				t.Fatalf("vendor_admin %s %s: want 403, got %d %s", method, path, rec.Code, rec.Body.String())
			}
			if !strings.Contains(strings.ToLower(rec.Body.String()), "super_admin") {
				t.Fatalf("403 body should require super_admin for wildcard clear: %s", rec.Body.String())
			}
		}
	}

	// Own-tenant clear (no wildcard) still allowed for company manager.
	req := httptest.NewRequest(http.MethodPost, "/api/v1/ingest/clear", nil)
	req.Header.Set("Authorization", "Bearer "+va)
	req.Header.Set("X-Tenant-ID", "tenant-adeco")
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	if rec.Code == http.StatusForbidden || rec.Code == http.StatusUnauthorized {
		t.Fatalf("vendor_admin own-tenant clear must pass gate, got %d %s", rec.Code, rec.Body.String())
	}

	// Super admin may use scope=all.
	su := tokenWithTenant(t, mw, domain.RoleSuperAdmin, "system")
	reqSU := httptest.NewRequest(http.MethodPost, "/api/v1/ingest/clear?scope=all", nil)
	reqSU.Header.Set("Authorization", "Bearer "+su)
	reqSU.Header.Set("X-Tenant-ID", "system")
	recSU := httptest.NewRecorder()
	h.ServeHTTP(recSU, reqSU)
	if recSU.Code == http.StatusForbidden || recSU.Code == http.StatusUnauthorized {
		t.Fatalf("super_admin scope=all must pass gate, got %d %s", recSU.Code, recSU.Body.String())
	}
}
