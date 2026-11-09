package handlers

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
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

func mappingCorrectionEnv(t *testing.T, planDir string) (http.Handler, *middleware.AuthMiddleware, *ingestion.Processor, *gemini.Client, string) {
	t.Helper()
	bq := bigquery.NewClient("test-proj", "test-dataset", true)
	fs := firestore.NewClient("db", true)
	_, planJSON := aiWideFixtureForHandlers(t)
	agent := gemini.NewAgent("test-key", "tier1-model", false).
		WithTier2Model("tier2-model").
		WithMappingPlanDir(planDir).
		WithColumnMapper(func(_ context.Context, model, prompt string) (string, error) {
			return planJSON, nil
		})
	proc := ingestion.NewProcessor(agent, bq, fs).WithArchiveDir(t.TempDir())
	mw := middleware.NewAuthMiddleware("test-secret", false)
	up := NewUploadHandler(proc)
	mux := http.NewServeMux()
	mux.HandleFunc("POST /api/v1/ingest/mapping-correction", up.HandleSaveMappingCorrection)
	return mw.Handler(mux), mw, proc, agent, planJSON
}

func aiWideFixtureForHandlers(t *testing.T) ([]byte, string) {
	t.Helper()
	rows := [][]string{
		{"Details for Sum of الاجمالى - YEAR: 2026, MONTH: JAN"},
		{""},
		{"المجموعة", "المورد", "الباركود", "الصنف", " سموحة", " ستانلى", "الاجمالى", "MONTH", "كمية سموحة", "كمية ستانلى", "اجمالى كميات", "YEAR"},
		{"منعمات", "ادكو (1)", "6223000299901", "صنف QA", "500", "400", "900", "JAN", "3", "3", "6", "2026"},
	}
	x, err := gemini.BuildSampleXLSX(rows)
	if err != nil {
		t.Fatal(err)
	}
	plan := `{"header_row_index":2,"skip_rows":[0,1],"layout":"wide","confidence":0.95,"columns":[
{"index":0,"role":"category"},{"index":1,"role":"supplier"},{"index":2,"role":"barcode"},{"index":3,"role":"product_name"},
{"index":4,"role":"store_value","branch":"سموحة"},{"index":5,"role":"store_value","branch":"ستانلى"},{"index":6,"role":"total_value"},
{"index":7,"role":"month"},{"index":8,"role":"store_quantity","branch":"سموحة"},{"index":9,"role":"store_quantity","branch":"ستانلى"},
{"index":10,"role":"total_quantity"},{"index":11,"role":"year"}]}`
	return x, plan
}

func TestHandleSaveMappingCorrectionHTTPPersists(t *testing.T) {
	planDir := t.TempDir()
	h, mw, proc, _, planJSON := mappingCorrectionEnv(t, planDir)
	tok, err := mw.GenerateToken(domain.UserClaims{
		UserID: "u1", Email: "a@test", TenantID: "tenant-adeco", Role: domain.RoleVendorAdmin,
	}, time.Hour)
	if err != nil {
		t.Fatal(err)
	}

	x, _ := aiWideFixtureForHandlers(t)
	preview, err := proc.ProcessUploadWithDryRun(context.Background(), "tenant-adeco", "Book3.xlsx", x, true, "fathalla")
	if err != nil {
		t.Fatal(err)
	}

	var plan gemini.ColumnMapPlan
	if err := json.Unmarshal([]byte(planJSON), &plan); err != nil {
		t.Fatal(err)
	}
	for i := range plan.Columns {
		if plan.Columns[i].Branch == "سموحة" {
			plan.Columns[i].Branch = "سموحة-http"
		}
	}
	body, _ := json.Marshal(map[string]any{
		"batch_id": preview.BatchID,
		"plan":     plan,
	})
	req := httptest.NewRequest(http.MethodPost, "/api/v1/ingest/mapping-correction", bytes.NewReader(body))
	req.Header.Set("Authorization", "Bearer "+tok)
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("status=%d body=%s", rec.Code, rec.Body.String())
	}
	var resp map[string]string
	if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
		t.Fatal(err)
	}
	if resp["status"] != "saved" {
		t.Fatalf("resp=%v", resp)
	}

	tenantDir := filepath.Join(planDir, "adeco")
	entries, err := os.ReadDir(tenantDir)
	if err != nil || len(entries) == 0 {
		t.Fatalf("expected persisted cache under %s: %v %v", tenantDir, entries, err)
	}
	raw, err := os.ReadFile(filepath.Join(tenantDir, entries[0].Name()))
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(raw), `"source":"correction"`) || !strings.Contains(string(raw), "سموحة-http") {
		t.Fatalf("disk envelope missing correction: %s", raw)
	}
}

func TestHandleSaveMappingCorrectionDiskWriteFailure(t *testing.T) {
	planDir := t.TempDir()
	// Block tenant namespace so durable write fails.
	if err := os.WriteFile(filepath.Join(planDir, "adeco"), []byte("block"), 0o644); err != nil {
		t.Fatal(err)
	}
	h, mw, proc, _, planJSON := mappingCorrectionEnv(t, planDir)
	tok, err := mw.GenerateToken(domain.UserClaims{
		UserID: "u1", Email: "a@test", TenantID: "tenant-adeco", Role: domain.RoleVendorAdmin,
	}, time.Hour)
	if err != nil {
		t.Fatal(err)
	}

	x, _ := aiWideFixtureForHandlers(t)
	// Stage without shared plan dir write for AI (AI put logs failures); still need staged batch.
	// Use a separate agent dir for staging analyze by temporarily… ProcessUpload will try AI cache write
	// into blocked path — AI put only logs, staging should still succeed.
	preview, err := proc.ProcessUploadWithDryRun(context.Background(), "tenant-adeco", "Book3.xlsx", x, true, "fathalla")
	if err != nil {
		t.Fatal(err)
	}

	var plan gemini.ColumnMapPlan
	_ = json.Unmarshal([]byte(planJSON), &plan)
	body, _ := json.Marshal(map[string]any{"batch_id": preview.BatchID, "plan": plan})
	req := httptest.NewRequest(http.MethodPost, "/api/v1/ingest/mapping-correction", bytes.NewReader(body))
	req.Header.Set("Authorization", "Bearer "+tok)
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)

	if rec.Code != http.StatusUnprocessableEntity {
		t.Fatalf("expected 422 on disk failure, got %d body=%s", rec.Code, rec.Body.String())
	}
	var resp map[string]string
	if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
		t.Fatal(err)
	}
	if resp["error"] != "mapping_correction_failed" {
		t.Fatalf("resp=%v", resp)
	}
	if !strings.Contains(resp["message"], "فشل حفظ تصحيح الربط") {
		t.Fatalf("expected clear Arabic failure message, got %q", resp["message"])
	}
}
