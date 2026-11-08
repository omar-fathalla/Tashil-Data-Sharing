package handlers

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/tashil/data-sharing/backend/internal/domain"
	"github.com/tashil/data-sharing/backend/internal/middleware"
	"github.com/tashil/data-sharing/backend/internal/service/bigquery"
	"github.com/tashil/data-sharing/backend/internal/service/firestore"
	"github.com/tashil/data-sharing/backend/internal/service/ingestion"
)

// stubTotalsExplainAgent returns a payload that already carries explanation_ar,
// so POST /ingest/upload can prove the field reaches the web JSON contract.
type stubTotalsExplainAgent struct{}

func (stubTotalsExplainAgent) AnalyzeAndNormalize(ctx context.Context, filename string, rawContent []byte) (*domain.NormalizedRetailIngestionPayload, error) {
	_ = ctx
	_ = filename
	_ = rawContent
	return &domain.NormalizedRetailIngestionPayload{
		RetailerDetected:  "fathalla",
		ConfidenceScore:   0.91,
		MappingSource:     "ai",
		MappingConfidence: 0.91,
		AiModelUsed:       "gemini-3.8-flash",
		AiTierUsed:        "tier1",
		SheetsProcessed:   []string{"مبيعات يناير"},
		NormalizedRecords: []domain.NormalizedRecord{
			{
				Barcode:         "6221000000001",
				SKUName:         "منتج تجريبي",
				RawStoreName:    "سموحة",
				ResolvedStoreID: "fathalla-smouha",
				QuantitySold:    10,
				NetRevenue:      500,
				TransactionDate: "2026-01-15",
				Category:        "oils",
				Supplier:        "adeco",
				IsOwnBrand:      true,
			},
		},
		Validation: &domain.IngestionValidation{
			Status:          "flagged",
			RecordCount:     1,
			ExtractedUnits:  10,
			ExtractedValue:  500,
			SourceUnits:     10,
			SourceValue:     500,
			SheetTotalUnits: 9,
			SheetTotalValue: 450,
			MonthsDetected:  []string{"2026-01"},
			Issues:          []string{"value total 500.00 is 11.1% off the sheet total column 450.00"},
			ExplanationAR:   "الموضع: الورقة «مبيعات يناير»، صفوف البيانات 2–2. فرق القيمة بسبب مرتجعات.",
			DiffReasons:     []string{"returns", "sheet_column_gap"},
		},
	}, nil
}

func TestUploadIngestJSONIncludesExplanationAR(t *testing.T) {
	tmpDir := t.TempDir()
	bqRepo := bigquery.NewClient("test-proj", "test-dataset", true)
	fsRepo := firestore.NewClient("test-db", true)
	processor := ingestion.NewProcessor(stubTotalsExplainAgent{}, bqRepo, fsRepo).WithArchiveDir(tmpDir)

	uploadHandler := NewUploadHandler(processor)
	authMiddleware := middleware.NewAuthMiddleware("test-secret", true)

	mux := http.NewServeMux()
	mux.HandleFunc("POST /api/v1/ingest/upload", uploadHandler.HandleUpload)
	handler := authMiddleware.Handler(mux)

	csvBody := []byte("Barcode,Qty,Value\n6221000000001,10,500\n")
	req := httptest.NewRequest(
		http.MethodPost,
		"/api/v1/ingest/upload?filename=jan_sales.csv&chain=fathalla&dry_run=true",
		bytes.NewReader(csvBody),
	)
	req.Header.Set("Authorization", "Bearer demo-adeco-token")
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", rec.Code, rec.Body.String())
	}

	var raw map[string]any
	if err := json.Unmarshal(rec.Body.Bytes(), &raw); err != nil {
		t.Fatalf("json: %v body=%s", err, rec.Body.String())
	}

	// Top-level validation (IngestionResult.Validation) for web clients.
	top, _ := raw["validation"].(map[string]any)
	if top == nil {
		t.Fatalf("missing top-level validation in upload JSON: keys=%v", keysOf(raw))
	}
	ar, _ := top["explanation_ar"].(string)
	if ar == "" || !strings.Contains(ar, "مبيعات يناير") {
		t.Fatalf("top-level explanation_ar missing/wrong: %#v", top)
	}
	reasons, _ := top["diff_reasons"].([]any)
	if len(reasons) == 0 {
		t.Fatalf("expected diff_reasons on top-level validation: %#v", top)
	}

	// Nested payload.validation must also carry the same field (Flutter reads either).
	payload, _ := raw["payload"].(map[string]any)
	if payload == nil {
		t.Fatal("missing payload in upload JSON")
	}
	nested, _ := payload["validation"].(map[string]any)
	if nested == nil {
		t.Fatalf("missing payload.validation: %#v", payload["validation"])
	}
	nestedAR, _ := nested["explanation_ar"].(string)
	if nestedAR != ar {
		t.Fatalf("payload.validation.explanation_ar=%q top=%q", nestedAR, ar)
	}
}

func keysOf(m map[string]any) []string {
	out := make([]string, 0, len(m))
	for k := range m {
		out = append(out, k)
	}
	return out
}
