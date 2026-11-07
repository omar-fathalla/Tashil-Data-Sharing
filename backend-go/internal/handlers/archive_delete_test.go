package handlers

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/tashil/data-sharing/backend/internal/domain"
	"github.com/tashil/data-sharing/backend/internal/middleware"
	"github.com/tashil/data-sharing/backend/internal/service/bigquery"
	"github.com/tashil/data-sharing/backend/internal/service/bqsink"
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
	st, code, _ = archiveDeleteHTTPStatus(&ingestion.ArchiveDeleteError{Stage: "disk", Message: "index write failed"})
	if st != http.StatusInternalServerError || code != "archive_delete_partial" {
		t.Fatalf("disk mapping: %d %s", st, code)
	}
	st, code, _ = archiveDeleteHTTPStatus(&ingestion.ArchiveDeleteError{Stage: "ambiguous", Message: "many"})
	if st != http.StatusConflict || code != "archive_delete_ambiguous" {
		t.Fatalf("ambiguous mapping: %d %s", st, code)
	}
	st, code, _ = archiveDeleteHTTPStatus(errors.New("other"))
	if st != http.StatusInternalServerError || code != "delete_failed" {
		t.Fatalf("default mapping: %d %s", st, code)
	}
}

// Stale archive ID + file_name must 404 and must NOT delete a newer same-named upload.
func TestDeleteStaleArchiveIDDoesNotFallbackToFileName(t *testing.T) {
	proc, h, mw := archiveDeleteTestEnv(t)
	// SaveArchivedFile reuses one id per sell-out name; plant two distinct ids sharing FileName.
	older := &ingestion.ArchivedFile{
		ID: "arch_stale_old", BatchID: "batch_old", FileType: "sell_out", TenantID: "tenant-adeco",
		FileName: "same.xlsx", RetailChain: "fathalla", TargetYear: "2026", TargetMonth: "01",
		RowsIngested: 1, UploadedAt: "2026-01-01T00:00:00Z",
	}
	newer := &ingestion.ArchivedFile{
		ID: "arch_stale_new", BatchID: "batch_new", FileType: "sell_out", TenantID: "tenant-adeco",
		FileName: "same.xlsx", RetailChain: "fathalla", TargetYear: "2026", TargetMonth: "02",
		RowsIngested: 1, UploadedAt: "2026-02-01T00:00:00Z",
	}
	proc.InsertArchivedFileEntry(older, []byte("old"))
	proc.InsertArchivedFileEntry(newer, []byte("new"))
	if _, err := proc.DeleteArchivedFile(context.Background(), "tenant-adeco", older.ID); err != nil {
		t.Fatal(err)
	}

	tok := tokenWithTenant(t, mw, domain.RoleVendorAdmin, "tenant-adeco")
	req := httptest.NewRequest(http.MethodDelete, "/api/v1/ingest/archive/"+older.ID+"?file_name=same.xlsx", nil)
	req.Header.Set("Authorization", "Bearer "+tok)
	req.Header.Set("X-Tenant-ID", "tenant-adeco")
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	if rec.Code != http.StatusNotFound {
		t.Fatalf("stale id delete: want 404, got %d %s", rec.Code, rec.Body.String())
	}

	list := proc.ListArchivedFiles(req.Context(), "tenant-adeco", "", "", "", "sell_out")
	foundNewer := false
	for _, f := range list.Files {
		if f.ID == newer.ID {
			foundNewer = true
		}
		if f.ID == older.ID {
			t.Fatal("older archive must stay deleted")
		}
	}
	if !foundNewer {
		t.Fatal("newer same-named upload must survive stale-id + file_name delete")
	}
}

// Repeated delete of an already-removed archive id is an idempotent 404 (no-op).
func TestDeleteArchiveRepeatedIsIdempotentNotFound(t *testing.T) {
	proc, h, mw := archiveDeleteTestEnv(t)
	entry := proc.SaveArchivedFile("tenant-adeco", "batch_1", "once.xlsx", []byte("x"), "fathalla", "2026", "01", 1, 1, 1)
	tok := tokenWithTenant(t, mw, domain.RoleVendorAdmin, "tenant-adeco")

	del := func() *httptest.ResponseRecorder {
		req := httptest.NewRequest(http.MethodDelete, "/api/v1/ingest/archive/"+entry.ID, nil)
		req.Header.Set("Authorization", "Bearer "+tok)
		req.Header.Set("X-Tenant-ID", "tenant-adeco")
		rec := httptest.NewRecorder()
		h.ServeHTTP(rec, req)
		return rec
	}
	if rec := del(); rec.Code != http.StatusOK {
		t.Fatalf("first delete: want 200, got %d %s", rec.Code, rec.Body.String())
	}
	if rec := del(); rec.Code != http.StatusNotFound {
		t.Fatalf("second delete: want 404 idempotent no-op, got %d %s", rec.Code, rec.Body.String())
	}
}

// Legacy name-only delete works when exactly one archive matches; ambiguous when two share a name.
func TestDeleteArchiveByNameUniqueOnly(t *testing.T) {
	proc, h, mw := archiveDeleteTestEnv(t)
	tok := tokenWithTenant(t, mw, domain.RoleVendorAdmin, "tenant-adeco")

	only := proc.SaveArchivedFile("tenant-adeco", "batch_a", "unique.xlsx", []byte("a"), "fathalla", "2026", "01", 1, 1, 1)
	req := httptest.NewRequest(http.MethodDelete, "/api/v1/ingest/archive?file_name=unique.xlsx", nil)
	req.Header.Set("Authorization", "Bearer "+tok)
	req.Header.Set("X-Tenant-ID", "tenant-adeco")
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("unique name delete: want 200, got %d %s", rec.Code, rec.Body.String())
	}
	if _, _, err := proc.GetArchivedFile(req.Context(), "tenant-adeco", only.ID); err == nil {
		t.Fatal("unique name delete must remove the archive")
	}

	proc.InsertArchivedFileEntry(&ingestion.ArchivedFile{
		ID: "arch_dup_a", BatchID: "batch_b", FileType: "sell_out", TenantID: "tenant-adeco",
		FileName: "dup.xlsx", RetailChain: "fathalla", TargetYear: "2026", TargetMonth: "01",
		RowsIngested: 1, UploadedAt: "2026-01-01T00:00:00Z",
	}, []byte("b"))
	proc.InsertArchivedFileEntry(&ingestion.ArchivedFile{
		ID: "arch_dup_b", BatchID: "batch_c", FileType: "sell_out", TenantID: "tenant-adeco",
		FileName: "dup.xlsx", RetailChain: "fathalla", TargetYear: "2026", TargetMonth: "02",
		RowsIngested: 1, UploadedAt: "2026-02-01T00:00:00Z",
	}, []byte("c"))
	req2 := httptest.NewRequest(http.MethodDelete, "/api/v1/ingest/archive?file_name=dup.xlsx", nil)
	req2.Header.Set("Authorization", "Bearer "+tok)
	req2.Header.Set("X-Tenant-ID", "tenant-adeco")
	rec2 := httptest.NewRecorder()
	h.ServeHTTP(rec2, req2)
	if rec2.Code != http.StatusConflict {
		t.Fatalf("ambiguous name delete: want 409, got %d %s", rec2.Code, rec2.Body.String())
	}
	list := proc.ListArchivedFiles(req2.Context(), "tenant-adeco", "", "", "", "sell_out")
	if list.TotalCount < 2 {
		t.Fatalf("ambiguous name must leave both archives, got %d", list.TotalCount)
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
	mux.HandleFunc("DELETE /api/v1/ingest/archive", up.HandleDeleteArchive)
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

// file_name fallback must NOT run after a BigQuery failure — otherwise DeleteArchivedFile's
// newest-by-name match could delete a different (newer) archive with the same file name.
func TestDeleteArchiveFileNameFallbackSkippedAfterAnalyticsFailure(t *testing.T) {
	setupIsolatedProductMasterDir(t)
	bq := bigquery.NewClient("test-project", "test-dataset", true)
	fs := firestore.NewClient("test-db", true)
	proc := ingestion.NewProcessor(gemini.NewAgent("", "gemini-2.5-flash", true), bq, fs).WithArchiveDir(t.TempDir())
	failSink := &failingDeleteSink{err: errors.New("bq down")}
	proc.WithSink(failSink)

	older := proc.SaveArchivedFile("tenant-adeco", "batch_old", "same.xlsx", []byte("old"), "fathalla", "2026", "01", 1, 1, 1)
	newer := proc.SaveArchivedFile("tenant-adeco", "batch_new", "same.xlsx", []byte("new"), "fathalla", "2026", "02", 1, 1, 1)

	mw := middleware.NewAuthMiddleware("test-secret", false)
	up := NewUploadHandler(proc)
	mux := http.NewServeMux()
	mux.HandleFunc("DELETE /api/v1/ingest/archive/{id}", up.HandleDeleteArchive)
	mux.HandleFunc("GET /api/v1/ingest/archive", up.HandleListArchive)
	h := mw.Handler(mux)
	tok := tokenWithTenant(t, mw, domain.RoleVendorAdmin, "tenant-adeco")

	req := httptest.NewRequest(http.MethodDelete, "/api/v1/ingest/archive/"+older.ID+"?file_name=same.xlsx", nil)
	req.Header.Set("Authorization", "Bearer "+tok)
	req.Header.Set("X-Tenant-ID", "tenant-adeco")
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	if rec.Code != http.StatusBadGateway {
		t.Fatalf("analytics failure: want 502, got %d %s", rec.Code, rec.Body.String())
	}

	list := proc.ListArchivedFiles(req.Context(), "tenant-adeco", "", "", "", "sell_out")
	ids := map[string]bool{}
	for _, f := range list.Files {
		ids[f.ID] = true
	}
	if !ids[older.ID] || !ids[newer.ID] {
		t.Fatalf("both archives must remain after failed delete (no name fallback), got %+v", ids)
	}
}

// failingDeleteSink is a minimal sink that fails DeleteBatch (used by archive delete tests).
type failingDeleteSink struct {
	err error
}

func (f *failingDeleteSink) Enabled() bool { return true }
func (f *failingDeleteSink) WriteSellOut(context.Context, bqsink.Meta, []domain.SellOutFact, bqsink.SellOutMode) *bqsink.Result {
	return &bqsink.Result{Status: bqsink.StatusOK}
}
func (f *failingDeleteSink) WriteSellIn(context.Context, bqsink.Meta, []domain.SellInRecord) *bqsink.Result {
	return &bqsink.Result{Status: bqsink.StatusOK}
}
func (f *failingDeleteSink) WriteProductMaster(context.Context, bqsink.Meta, *domain.ProductMasterSummaryResponse) *bqsink.Result {
	return &bqsink.Result{Status: bqsink.StatusOK}
}
func (f *failingDeleteSink) DeleteBatch(_ context.Context, k bqsink.Kind, _ bqsink.Meta) *bqsink.Result {
	return &bqsink.Result{Status: bqsink.StatusFailed, Table: bqsink.TableForKind(k).Name, Error: f.err.Error()}
}
func (f *failingDeleteSink) DeleteTenant(_ context.Context, k bqsink.Kind, _ string) *bqsink.Result {
	return &bqsink.Result{Status: bqsink.StatusOK, Table: bqsink.TableForKind(k).Name}
}
