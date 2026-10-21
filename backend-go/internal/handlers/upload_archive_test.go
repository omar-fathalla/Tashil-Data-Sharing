package handlers

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/tashil/data-sharing/backend/internal/middleware"
	"github.com/tashil/data-sharing/backend/internal/service/bigquery"
	"github.com/tashil/data-sharing/backend/internal/service/firestore"
	"github.com/tashil/data-sharing/backend/internal/service/gemini"
	"github.com/tashil/data-sharing/backend/internal/service/ingestion"
)

func TestUploadHandlerArchiveListAndDownload(t *testing.T) {
	tmpDir := t.TempDir()
	agent := gemini.NewAgent("", "gemini-3.8-flash", true)
	bqRepo := bigquery.NewClient("test-proj", "test-dataset", true)
	fsRepo := firestore.NewClient("test-db", true)
	processor := ingestion.NewProcessor(agent, bqRepo, fsRepo).WithArchiveDir(tmpDir)

	uploadHandler := NewUploadHandler(processor)
	authMiddleware := middleware.NewAuthMiddleware("test-secret", true)

	mux := http.NewServeMux()
	mux.HandleFunc("POST /api/v1/ingest/upload", uploadHandler.HandleUpload)
	mux.HandleFunc("GET /api/v1/ingest/archive", uploadHandler.HandleListArchive)
	mux.HandleFunc("GET /api/v1/ingest/archive/download", uploadHandler.HandleDownloadArchivedFile)
	mux.HandleFunc("GET /api/v1/ingest/archive/{id}/download", uploadHandler.HandleDownloadArchivedFile)

	handler := authMiddleware.Handler(mux)

	// 1. Upload a CSV file for Gomla Market under tenant-unilever
	csvBody := []byte("الباركود,اسم الصنف,الفرع,الكمية,القيمة\n6221155001234,زيت عباد الشمس 1 لتر,فرع الدقي,40,8000\n")
	reqUpload := httptest.NewRequest(http.MethodPost, "/api/v1/ingest/upload?filename=gomla_april_2026.csv&chain=gomla", bytes.NewReader(csvBody))
	reqUpload.Header.Set("Authorization", "Bearer demo-unilever-token")
	recUpload := httptest.NewRecorder()
	handler.ServeHTTP(recUpload, reqUpload)

	if recUpload.Code != http.StatusOK {
		t.Fatalf("expected 200 OK on upload, got %d: %s", recUpload.Code, recUpload.Body.String())
	}

	// 2. List archive for tenant-unilever
	reqList := httptest.NewRequest(http.MethodGet, "/api/v1/ingest/archive?chain=gomla", nil)
	reqList.Header.Set("Authorization", "Bearer demo-unilever-token")
	recList := httptest.NewRecorder()
	handler.ServeHTTP(recList, reqList)

	if recList.Code != http.StatusOK {
		t.Fatalf("expected 200 OK on list archive, got %d: %s", recList.Code, recList.Body.String())
	}

	var listResp ingestion.ArchiveListResponse
	if err := json.Unmarshal(recList.Body.Bytes(), &listResp); err != nil {
		t.Fatalf("failed to unmarshal ArchiveListResponse: %v", err)
	}
	if len(listResp.Files) != 1 {
		t.Fatalf("expected 1 archived file for tenant-unilever, got %d", len(listResp.Files))
	}
	archived := listResp.Files[0]
	if archived.FileName != "gomla_april_2026.csv" || archived.RetailChain != "gomla" {
		t.Errorf("unexpected archived file metadata: %+v", archived)
	}

	// 3. Download archived file via /api/v1/ingest/archive/{id}/download
	reqDownload := httptest.NewRequest(http.MethodGet, "/api/v1/ingest/archive/"+archived.ID+"/download", nil)
	reqDownload.Header.Set("Authorization", "Bearer demo-unilever-token")
	recDownload := httptest.NewRecorder()
	handler.ServeHTTP(recDownload, reqDownload)

	if recDownload.Code != http.StatusOK {
		t.Fatalf("expected 200 OK on download, got %d: %s", recDownload.Code, recDownload.Body.String())
	}
	disp := recDownload.Header().Get("Content-Disposition")
	if !strings.Contains(disp, "gomla_april_2026.csv") {
		t.Errorf("expected Content-Disposition to contain filename, got %s", disp)
	}
	if recDownload.Body.String() != string(csvBody) {
		t.Errorf("downloaded body mismatch: got %q, want %q", recDownload.Body.String(), string(csvBody))
	}

	// 4. Cross-tenant isolation check: tenant-pepsico should not be able to download tenant-unilever's file
	reqCross := httptest.NewRequest(http.MethodGet, "/api/v1/ingest/archive/"+archived.ID+"/download", nil)
	reqCross.Header.Set("Authorization", "Bearer demo-pepsico-token")
	recCross := httptest.NewRecorder()
	handler.ServeHTTP(recCross, reqCross)

	if recCross.Code != http.StatusNotFound {
		t.Errorf("expected 404 Not Found for cross-tenant download attempt, got %d", recCross.Code)
	}
}
