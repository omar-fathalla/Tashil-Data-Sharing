package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/tashil/data-sharing/backend/internal/domain"
	"github.com/tashil/data-sharing/backend/internal/handlers"
	"github.com/tashil/data-sharing/backend/internal/middleware"
	"github.com/tashil/data-sharing/backend/internal/service/bigquery"
	"github.com/tashil/data-sharing/backend/internal/service/firestore"
	"github.com/tashil/data-sharing/backend/internal/service/gemini"
	"github.com/tashil/data-sharing/backend/internal/service/ingestion"
)

// Hotfix regression (prod job_702b…): the web app runs Sell-In uploads as async jobs with
// tenant_id=tenant-adeco while the token carries "adeco". The job must no longer record http_status 403;
// a foreign tenant still does.
func TestSellInJobTenantCanonical(t *testing.T) {
	t.Setenv("TASHIL_PRODUCT_MASTER_DIR", t.TempDir())
	proc := ingestion.NewProcessor(gemini.NewAgent("", "gemini-2.5-flash", true),
		bigquery.NewClient("test-project", "test-dataset", true), firestore.NewClient("test-db", true)).WithArchiveDir(t.TempDir())
	mux := http.NewServeMux()
	mux.HandleFunc("POST /api/v1/ingest/load-sell-in-plan", handlers.NewUploadHandler(proc).HandleLoadSellInPlan)
	mw := middleware.NewAuthMiddleware("test-secret", false)
	h := mw.Handler(newAsyncJobs(t.TempDir()).wrap(mux))
	tok, err := mw.GenerateToken(domain.UserClaims{UserID: "u1", Email: "u@example.test", TenantID: "adeco", Role: domain.RoleVendorAdmin}, time.Hour)
	if err != nil {
		t.Fatal(err)
	}
	runJob := func(tenant string) jobRecord {
		req := httptest.NewRequest(http.MethodPost, "/api/v1/ingest/load-sell-in-plan?filename=si.csv&chain=qa_test&tenant_id="+tenant, strings.NewReader("x,y\n1,2\n"))
		req.Header.Set("Authorization", "Bearer "+tok)
		req.Header.Set("Content-Type", "text/csv")
		req.Header.Set(asyncJobHeader, "1")
		rr := httptest.NewRecorder()
		h.ServeHTTP(rr, req)
		if rr.Code != http.StatusAccepted {
			t.Fatalf("want 202, got %d %s", rr.Code, rr.Body.String())
		}
		var started map[string]string
		_ = json.Unmarshal(rr.Body.Bytes(), &started)
		deadline := time.Now().Add(10 * time.Second)
		for time.Now().Before(deadline) {
			p := httptest.NewRequest(http.MethodGet, "/api/v1/jobs/"+started["job_id"], nil)
			p.Header.Set("Authorization", "Bearer "+tok)
			pr := httptest.NewRecorder()
			h.ServeHTTP(pr, p)
			var rec jobRecord
			_ = json.Unmarshal(pr.Body.Bytes(), &rec)
			if rec.Status != "running" {
				return rec
			}
			time.Sleep(20 * time.Millisecond)
		}
		t.Fatal("job did not finish")
		return jobRecord{}
	}
	for _, own := range []string{"tenant-adeco", "adeco"} {
		if rec := runJob(own); rec.HTTPStatus == http.StatusForbidden {
			t.Fatalf("own tenant %q: job recorded 403: %s", own, rec.Body)
		}
	}
	if rec := runJob("tenant-other"); rec.HTTPStatus != http.StatusForbidden {
		t.Fatalf("foreign tenant: want job http_status 403, got %d", rec.HTTPStatus)
	}
}
