package handlers

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/tashil/data-sharing/backend/internal/domain"
	"github.com/tashil/data-sharing/backend/internal/middleware"
	"github.com/tashil/data-sharing/backend/internal/service/gemini"
	"github.com/tashil/data-sharing/backend/internal/service/ingestion"
	"github.com/tashil/data-sharing/backend/internal/service/preupload"
)

func precheckEnv(t *testing.T) (http.Handler, *middleware.AuthMiddleware, *ingestion.Processor) {
	t.Helper()
	proc := ingestion.NewProcessor(gemini.NewAgent("", "gemini-3.8-flash", true), nil, nil).WithArchiveDir(t.TempDir())
	mw := middleware.NewAuthMiddleware("test-secret", false)
	up := NewUploadHandler(proc)
	mux := http.NewServeMux()
	mux.HandleFunc("POST /api/v1/ingest/precheck", up.HandlePrecheck)
	mux.HandleFunc("POST /api/v1/ingest/upload", up.HandleUpload)
	return mw.Handler(mux), mw, proc
}

func TestHandlePrecheckMissingColumnNoWrite(t *testing.T) {
	h, mw, proc := precheckEnv(t)
	tok, err := mw.GenerateToken(domain.UserClaims{
		UserID: "u1", Email: "a@test", TenantID: "tenant-adeco", Role: domain.RoleVendorAdmin,
	}, time.Hour)
	if err != nil {
		t.Fatal(err)
	}

	body := []byte("Customer,Item 1,Month,Year,net Q\nQA,ItemA,3,2026,2\n")
	req := httptest.NewRequest(http.MethodPost, "/api/v1/ingest/precheck?filename=raw.csv&chain=fathalla", bytes.NewReader(body))
	req.Header.Set("Authorization", "Bearer "+tok)
	req.Header.Set("Content-Type", "application/octet-stream")
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("status=%d body=%s", rec.Code, rec.Body.String())
	}
	var report preupload.Report
	if err := json.Unmarshal(rec.Body.Bytes(), &report); err != nil {
		t.Fatal(err)
	}
	if report.OK || !report.WroteNothing || report.Blocking < 1 {
		t.Fatalf("expected blocking Arabic fix list: %+v", report)
	}
	found := false
	for _, f := range report.Fixes {
		if f.Code == preupload.CodeMissingColumn {
			found = true
			if f.MessageAR == "" || f.HowToFixAR == "" {
				t.Fatalf("Arabic fields required: %+v", f)
			}
		}
	}
	if !found {
		t.Fatalf("missing_column not in %+v", report.Fixes)
	}
	if list := proc.ListArchivedFiles(req.Context(), "tenant-adeco", "", "", ""); list != nil && len(list.Files) != 0 {
		t.Fatalf("precheck must not archive, got %d", len(list.Files))
	}
}

func TestHandleUploadPrecheckOnlyHook(t *testing.T) {
	h, mw, proc := precheckEnv(t)
	tok, err := mw.GenerateToken(domain.UserClaims{
		UserID: "u1", Email: "a@test", TenantID: "tenant-adeco", Role: domain.RoleVendorAdmin,
	}, time.Hour)
	if err != nil {
		t.Fatal(err)
	}

	body := []byte("Barcode,Store Name,Item,Qty,Net Amount,Month,Year\n1,سموحة,صنف,1,10,3,2026\n")
	req := httptest.NewRequest(http.MethodPost, "/api/v1/ingest/upload?filename=ok.csv&chain=fathalla&precheck_only=true", bytes.NewReader(body))
	req.Header.Set("Authorization", "Bearer "+tok)
	req.Header.Set("Content-Type", "application/octet-stream")
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("status=%d body=%s", rec.Code, rec.Body.String())
	}
	var report preupload.Report
	if err := json.Unmarshal(rec.Body.Bytes(), &report); err != nil {
		t.Fatal(err)
	}
	if !report.OK || !report.WroteNothing {
		t.Fatalf("clean precheck_only must pass with no writes: %+v", report)
	}
	if list := proc.ListArchivedFiles(req.Context(), "tenant-adeco", "", "", ""); list != nil && len(list.Files) != 0 {
		t.Fatalf("precheck_only must not archive, got %d", len(list.Files))
	}
}
