package middleware

import (
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestETagRoundTrip(t *testing.T) {
	body := `{"ok":true}`
	h := ETag(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(body))
	}))

	rr := httptest.NewRecorder()
	h.ServeHTTP(rr, httptest.NewRequest(http.MethodGet, "/api/v1/analytics/records", nil))
	tag := rr.Header().Get("ETag")
	if rr.Code != 200 || tag == "" || rr.Body.String() != body {
		t.Fatalf("first: code=%d tag=%q body=%q", rr.Code, tag, rr.Body.String())
	}

	req := httptest.NewRequest(http.MethodGet, "/api/v1/analytics/records", nil)
	req.Header.Set("If-None-Match", tag)
	rr2 := httptest.NewRecorder()
	h.ServeHTTP(rr2, req)
	if rr2.Code != http.StatusNotModified || rr2.Body.Len() != 0 {
		t.Fatalf("revalidate: code=%d len=%d", rr2.Code, rr2.Body.Len())
	}

	body = `{"ok":false}`
	rr3 := httptest.NewRecorder()
	h.ServeHTTP(rr3, req)
	if rr3.Code != 200 || rr3.Header().Get("ETag") == tag {
		t.Fatalf("changed: code=%d", rr3.Code)
	}
}

func TestETagSkipsDownloadsAndErrors(t *testing.T) {
	h := ETag(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/api/v1/x" {
			w.WriteHeader(http.StatusInternalServerError)
		}
		_, _ = w.Write([]byte("x"))
	}))
	for _, p := range []string{"/api/v1/ingest/archive/a/download", "/api/v1/x"} {
		rr := httptest.NewRecorder()
		h.ServeHTTP(rr, httptest.NewRequest(http.MethodGet, p, nil))
		if rr.Header().Get("ETag") != "" {
			t.Fatalf("%s should have no ETag", p)
		}
	}
}
