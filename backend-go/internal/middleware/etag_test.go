package middleware

import (
	"bytes"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestETagRoundTrip(t *testing.T) {
	body := `{"ok":true}`
	h := ETag(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(body))
	}))

	rr := httptest.NewRecorder()
	h.ServeHTTP(rr, httptest.NewRequest(http.MethodGet, "/api/v1/analytics/summary", nil))
	tag := rr.Header().Get("ETag")
	if rr.Code != 200 || tag == "" || rr.Body.String() != body {
		t.Fatalf("first: code=%d tag=%q body=%q", rr.Code, tag, rr.Body.String())
	}

	req := httptest.NewRequest(http.MethodGet, "/api/v1/analytics/summary", nil)
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

func jsonHandler(body *string) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(*body))
	})
}

func TestETagNoStoreAndVary(t *testing.T) {
	body := `{"a":1}`
	rr := httptest.NewRecorder()
	ETag(jsonHandler(&body)).ServeHTTP(rr, httptest.NewRequest(http.MethodGet, "/api/v1/stores", nil))
	if cc := rr.Header().Get("Cache-Control"); cc != "private, no-store" {
		t.Fatalf("cache-control=%q", cc)
	}
	v := rr.Header().Get("Vary")
	for _, h := range []string{"Authorization", "X-Tenant-ID", "X-Simulated-Role", "X-Assigned-Chain"} {
		if !strings.Contains(v, h) {
			t.Fatalf("Vary %q missing %s", v, h)
		}
	}
}

func TestETagStarDoesNotMatch(t *testing.T) {
	body := `{"a":1}`
	req := httptest.NewRequest(http.MethodGet, "/api/v1/stores", nil)
	req.Header.Set("If-None-Match", "*")
	rr := httptest.NewRecorder()
	ETag(jsonHandler(&body)).ServeHTTP(rr, req)
	if rr.Code != 200 || rr.Body.String() != body {
		t.Fatalf("code=%d body=%q", rr.Code, rr.Body.String())
	}
}

func TestETagSkipsRecordsAndNonJSON(t *testing.T) {
	body := `{"a":1}`
	rr := httptest.NewRecorder()
	ETag(jsonHandler(&body)).ServeHTTP(rr, httptest.NewRequest(http.MethodGet, "/api/v1/analytics/records", nil))
	if rr.Header().Get("ETag") != "" || rr.Body.String() != body {
		t.Fatal("records endpoint must bypass ETag")
	}
	h := ETag(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "text/plain")
		_, _ = w.Write([]byte("hi"))
	}))
	rr = httptest.NewRecorder()
	h.ServeHTTP(rr, httptest.NewRequest(http.MethodGet, "/api/v1/x", nil))
	if rr.Header().Get("ETag") != "" || rr.Body.String() != "hi" {
		t.Fatal("non-JSON must bypass ETag")
	}
}

func TestETagLargeResponseStreamsWithoutTag(t *testing.T) {
	chunk := bytes.Repeat([]byte("a"), 1<<20)
	h := ETag(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		for i := 0; i < 7; i++ {
			_, _ = w.Write(chunk)
		}
	}))
	req := httptest.NewRequest(http.MethodGet, "/api/v1/big", nil)
	req.Header.Set("If-None-Match", `"x"`)
	rr := httptest.NewRecorder()
	h.ServeHTTP(rr, req)
	if rr.Code != 200 || rr.Body.Len() != 7<<20 || rr.Header().Get("ETag") != "" {
		t.Fatalf("code=%d len=%d etag=%q", rr.Code, rr.Body.Len(), rr.Header().Get("ETag"))
	}
	if rr.Header().Get("Content-Type") != "application/json" {
		t.Fatal("headers lost when streaming")
	}
}
