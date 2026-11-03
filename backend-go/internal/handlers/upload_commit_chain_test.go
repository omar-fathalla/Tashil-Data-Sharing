package handlers

import (
	"context"
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

func commitReq(query, body string) *http.Request {
	r := httptest.NewRequest(http.MethodPost, "/api/v1/ingest/commit"+query, strings.NewReader(body))
	claims := &domain.UserClaims{UserID: "u", TenantID: "tenant-adeco", Role: domain.RoleVendorAdmin}
	return r.WithContext(context.WithValue(r.Context(), middleware.UserClaimsContextKey, claims))
}

// /ingest/commit takes the chain from ?chain= or the body; both and different -> 400.
// An unknown/expired batch -> 410 with an Arabic message (not a bare 422).
func TestCommitChainQueryOrBody(t *testing.T) {
	proc := ingestion.NewProcessor(gemini.NewAgent("", "gemini-2.5-flash", true),
		bigquery.NewClient("p", "d", true), firestore.NewClient("test-db", true)).WithArchiveDir(t.TempDir())
	h := NewUploadHandler(proc)

	w := httptest.NewRecorder()
	h.HandleCommit(w, commitReq("?chain=qa_test", `{"batch_id":"batch_x","chain":"fathalla"}`))
	if w.Code != http.StatusBadRequest || !strings.Contains(w.Body.String(), "chain_conflict") {
		t.Fatalf("conflict: %d %s", w.Code, w.Body.String())
	}
	for _, c := range []struct{ q, b string }{
		{"?chain=qa_test", `{"batch_id":"batch_x"}`},
		{"", `{"batch_id":"batch_x","chain":"qa_test"}`},
		{"?chain=QA_TEST", `{"batch_id":"batch_x","chain":"qa_test"}`},
	} {
		w = httptest.NewRecorder()
		h.HandleCommit(w, commitReq(c.q, c.b))
		if w.Code != http.StatusGone || !strings.Contains(w.Body.String(), "المعاينة انتهت") {
			t.Fatalf("%q %q: %d %s", c.q, c.b, w.Code, w.Body.String())
		}
	}
}
