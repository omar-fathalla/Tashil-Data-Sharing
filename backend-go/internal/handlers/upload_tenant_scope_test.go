package handlers

import (
	"context"
	"encoding/json"
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

const pmCSVHeader = "م,كود الصنف,اسم الصنف,الباركود,التعبئة,عدد الوحدات بالكرتونة,سعر الوحدة قبل الضريبة,قيمة الضريبة,سعر الوحدة شامل الضريبة,سعر الكرتونة شامل الضريبة\n"
const pmCSVv1 = pmCSVHeader + "1,FGCL-0550-0001,كلوريل أبيض 550 جم,6223000231227,عبوة,20,10.00,14%,11.40,228.00\n"
const pmCSVv2 = pmCSVHeader + "1,FGDG-0600-0002,فيبا أطباق 600 مل,6223000231228,عبوة,12,20.00,14%,22.80,273.60\n"

type scopeEnv struct {
	h    http.Handler
	mw   *middleware.AuthMiddleware
	proc *ingestion.Processor
	fs   *firestore.Client
}

func newScopeEnv(t *testing.T) *scopeEnv {
	t.Helper()
	setupIsolatedProductMasterDir(t)
	bq := bigquery.NewClient("test-project", "test-dataset", true)
	fs := firestore.NewClient("test-db", true)
	proc := ingestion.NewProcessor(gemini.NewAgent("", "gemini-2.5-flash", true), bq, fs).WithArchiveDir(t.TempDir())
	mw := middleware.NewAuthMiddleware("test-secret", false)
	up := NewUploadHandler(proc)
	mux := http.NewServeMux()
	mux.HandleFunc("POST /api/v1/ingest/load-sell-in-plan", up.HandleLoadSellInPlan)
	mux.HandleFunc("POST /api/v1/product-master/upload", up.HandleUploadProductMaster)
	return &scopeEnv{h: mw.Handler(mux), mw: mw, proc: proc, fs: fs}
}

func (e *scopeEnv) token(t *testing.T, role domain.UserRole, tenant string) string {
	t.Helper()
	tok, err := e.mw.GenerateToken(domain.UserClaims{UserID: "u-" + string(role), Email: "u@example.test", TenantID: tenant, Role: role}, time.Hour)
	if err != nil {
		t.Fatal(err)
	}
	return tok
}

func (e *scopeEnv) post(path, tok, body string) *httptest.ResponseRecorder {
	req := httptest.NewRequest(http.MethodPost, path, strings.NewReader(body))
	req.Header.Set("Authorization", "Bearer "+tok)
	req.Header.Set("Content-Type", "text/csv")
	rec := httptest.NewRecorder()
	e.h.ServeHTTP(rec, req)
	return rec
}

func (e *scopeEnv) archiveCount(tenant, fileType string) int {
	return e.proc.ListArchivedFiles(context.Background(), tenant, "", "", "", fileType).TotalCount
}

func (e *scopeEnv) uploadPM(t *testing.T, tok, tenant, name, body string) string {
	t.Helper()
	rec := e.post("/api/v1/product-master/upload?filename="+name, tok, body)
	if rec.Code != http.StatusOK {
		t.Fatalf("seed upload %s: %d %s", name, rec.Code, rec.Body.String())
	}
	var res ingestion.IngestionResult
	_ = json.Unmarshal(rec.Body.Bytes(), &res)
	if res.ArchiveID == "" {
		t.Fatalf("seed upload %s: no archive id", name)
	}
	return res.ArchiveID
}

// P1: a vendor_admin naming another tenant gets 403 on both uploads and nothing lands in that tenant.
func TestUploadRejectsForeignTenantForVendorAdmin(t *testing.T) {
	e := newScopeEnv(t)
	tok := e.token(t, domain.RoleVendorAdmin, "tenant-adeco")
	for _, path := range []string{
		"/api/v1/product-master/upload?filename=pm.csv&tenant_id=tenant-other",
		"/api/v1/ingest/load-sell-in-plan?filename=si.csv&chain=fathalla&tenant_id=tenant-other",
	} {
		if rec := e.post(path, tok, pmCSVv1); rec.Code != http.StatusForbidden {
			t.Fatalf("%s: want 403, got %d %s", path, rec.Code, rec.Body.String())
		}
	}
	if n := e.archiveCount("tenant-other", "product_master") + e.archiveCount("tenant-other", "sell_in"); n != 0 {
		t.Fatalf("foreign tenant got %d archives", n)
	}
	// A matching tenant_id is fine and uses the token's tenant.
	if rec := e.post("/api/v1/product-master/upload?filename=pm.csv&tenant_id=tenant-adeco", tok, pmCSVv1); rec.Code != http.StatusOK {
		t.Fatalf("matching tenant_id: want 200, got %d %s", rec.Code, rec.Body.String())
	}
}

// P1: a verified super_admin may target another tenant.
func TestUploadAllowsForeignTenantForSuperAdmin(t *testing.T) {
	e := newScopeEnv(t)
	tok := e.token(t, domain.RoleSuperAdmin, "system")
	rec := e.post("/api/v1/product-master/upload?filename=pm.csv&tenant_id=tenant-other", tok, pmCSVv1)
	if rec.Code != http.StatusOK {
		t.Fatalf("super_admin: want 200, got %d %s", rec.Code, rec.Body.String())
	}
	var res ingestion.IngestionResult
	_ = json.Unmarshal(rec.Body.Bytes(), &res)
	if a, _, err := e.proc.GetArchivedFile(context.Background(), "tenant-other", res.ArchiveID); err != nil || a.TenantID != "tenant-other" {
		t.Fatalf("archive not written to tenant-other: %v", err)
	}
}

// P2: replace_archive_id needs a super_admin; a vendor_admin gets 403 and the archive survives.
func TestReplaceArchiveRequiresSuperAdmin(t *testing.T) {
	e := newScopeEnv(t)
	tok := e.token(t, domain.RoleVendorAdmin, "tenant-adeco")
	id := e.uploadPM(t, tok, "tenant-adeco", "pm_v1.csv", pmCSVv1)
	for _, path := range []string{
		"/api/v1/product-master/upload?filename=pm_v2.csv&replace_archive_id=" + id,
		"/api/v1/ingest/load-sell-in-plan?filename=si.csv&chain=fathalla&replace_archive_id=" + id,
	} {
		if rec := e.post(path, tok, pmCSVv2); rec.Code != http.StatusForbidden {
			t.Fatalf("%s: want 403, got %d %s", path, rec.Code, rec.Body.String())
		}
	}
	if _, _, err := e.proc.GetArchivedFile(context.Background(), "tenant-adeco", id); err != nil {
		t.Fatalf("archive deleted by a refused replace: %v", err)
	}
}

// P2: a dry run and a failed upload never delete the archive being replaced; a real super_admin replace does.
func TestReplaceArchiveDeletesOnlyAfterSuccessfulRealUpload(t *testing.T) {
	e := newScopeEnv(t)
	tok := e.token(t, domain.RoleSuperAdmin, "tenant-adeco")
	id := e.uploadPM(t, tok, "tenant-adeco", "pm_v1.csv", pmCSVv1)
	alive := func() bool {
		_, _, err := e.proc.GetArchivedFile(context.Background(), "tenant-adeco", id)
		return err == nil
	}

	if rec := e.post("/api/v1/product-master/upload?filename=pm_v2.csv&dry_run=true&replace_archive_id="+id, tok, pmCSVv2); rec.Code != http.StatusOK {
		t.Fatalf("dry run: %d %s", rec.Code, rec.Body.String())
	}
	if !alive() {
		t.Fatal("dry run deleted the replaced archive")
	}
	if rec := e.post("/api/v1/product-master/upload?filename=bad.csv&replace_archive_id="+id, tok, "not,a,product,master\n1,2,3,4\n"); rec.Code == http.StatusOK {
		t.Fatalf("bad product master accepted: %s", rec.Body.String())
	}
	if !alive() {
		t.Fatal("failed product master upload deleted the replaced archive")
	}
	if rec := e.post("/api/v1/ingest/load-sell-in-plan?filename=bad_si.csv&chain=fathalla&replace_archive_id="+id, tok, "x,y\n1,2\n"); rec.Code == http.StatusOK {
		t.Fatalf("bad sell-in accepted: %s", rec.Body.String())
	}
	if !alive() {
		t.Fatal("failed sell-in upload deleted the replaced archive")
	}

	rec := e.post("/api/v1/product-master/upload?filename=pm_v2.csv&replace_archive_id="+id, tok, pmCSVv2)
	if rec.Code != http.StatusOK {
		t.Fatalf("super replace: %d %s", rec.Code, rec.Body.String())
	}
	var res ingestion.IngestionResult
	_ = json.Unmarshal(rec.Body.Bytes(), &res)
	if alive() {
		t.Fatal("successful replace kept the old archive")
	}
	if _, _, err := e.proc.GetArchivedFile(context.Background(), "tenant-adeco", res.ArchiveID); err != nil {
		t.Fatalf("new archive missing after replace: %v", err)
	}
}

// Minor: a rejected file must not clear its deleted (tombstone) flag.
func TestRejectedUploadKeepsDeletedFlag(t *testing.T) {
	e := newScopeEnv(t)
	ctx := context.Background()
	_ = e.fs.MarkArchiveDeleted(ctx, "tenant-adeco", "", "gone_si.csv")
	_ = e.fs.MarkArchiveDeleted(ctx, "tenant-adeco", "", "gone_pm.csv")
	if _, err := e.proc.ProcessSellInPlan(ctx, "tenant-adeco", "gone_si.csv", []byte("x,y\n1,2\n"), false, "fathalla"); err == nil {
		t.Fatal("junk sell-in accepted")
	}
	if _, err := e.proc.ProcessProductMaster(ctx, "tenant-adeco", "gone_pm.csv", []byte("x,y\n1,2\n"), false); err == nil {
		t.Fatal("junk product master accepted")
	}
	for _, f := range []string{"gone_si.csv", "gone_pm.csv"} {
		if !e.fs.IsArchiveDeleted("tenant-adeco", "", f) {
			t.Fatalf("%s: rejected upload cleared the deleted flag", f)
		}
	}
	// A successful upload still clears it.
	if _, err := e.proc.ProcessProductMaster(ctx, "tenant-adeco", "gone_pm.csv", []byte(pmCSVv1), false); err != nil {
		t.Fatalf("valid product master: %v", err)
	}
	if e.fs.IsArchiveDeleted("tenant-adeco", "", "gone_pm.csv") {
		t.Fatal("successful upload kept the deleted flag")
	}
}
