package middleware

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func assertCORS(t *testing.T, h http.Header) {
	t.Helper()
	if got := h.Get("Access-Control-Allow-Origin"); got != "*" {
		t.Fatalf("Allow-Origin: got %q want *", got)
	}
	if !strings.Contains(h.Get("Access-Control-Allow-Methods"), "OPTIONS") {
		t.Fatalf("Allow-Methods missing OPTIONS: %q", h.Get("Access-Control-Allow-Methods"))
	}
	for _, want := range []string{"Authorization", "X-Tenant-ID", "Content-Type", "X-Tashil-Async"} {
		if !strings.Contains(h.Get("Access-Control-Allow-Headers"), want) {
			t.Fatalf("Allow-Headers missing %s: %q", want, h.Get("Access-Control-Allow-Headers"))
		}
	}
	if h.Get("Access-Control-Max-Age") == "" {
		t.Fatal("Max-Age missing")
	}
}

func TestCORSOptionsPreflight(t *testing.T) {
	h := CORS(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		t.Fatal("OPTIONS must not reach next handler")
	}))
	req := httptest.NewRequest(http.MethodOptions, "/api/v1/customers/registry/approve", nil)
	req.Header.Set("Origin", "https://www.data.sw-point.com")
	req.Header.Set("Access-Control-Request-Method", "POST")
	req.Header.Set("Access-Control-Request-Headers", "authorization,content-type,x-tenant-id")
	rr := httptest.NewRecorder()
	h.ServeHTTP(rr, req)
	if rr.Code != http.StatusNoContent {
		t.Fatalf("code=%d want 204", rr.Code)
	}
	assertCORS(t, rr.Header())
}

func TestCORSErrorResponseKeepsAllowOrigin(t *testing.T) {
	h := CORS(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		http.Error(w, `{"error":"unauthorized: valid JWT bearer token required"}`, http.StatusUnauthorized)
	}))
	req := httptest.NewRequest(http.MethodGet, "/api/v1/data-quality/summary", nil)
	req.Header.Set("Origin", "https://www.data.sw-point.com")
	rr := httptest.NewRecorder()
	h.ServeHTTP(rr, req)
	if rr.Code != http.StatusUnauthorized {
		t.Fatalf("code=%d want 401", rr.Code)
	}
	assertCORS(t, rr.Header())
}

func TestCORSHandlerClearingHeadersStillExposesOrigin(t *testing.T) {
	h := CORS(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		// Simulate a buggy/partial handler that wipes response headers before writing.
		for k := range w.Header() {
			w.Header().Del(k)
		}
		w.WriteHeader(http.StatusServiceUnavailable)
		_, _ = w.Write([]byte(`{"status":"loading"}`))
	}))
	rr := httptest.NewRecorder()
	h.ServeHTTP(rr, httptest.NewRequest(http.MethodGet, "/api/v1/data-quality/summary", nil))
	if rr.Code != http.StatusServiceUnavailable {
		t.Fatalf("code=%d want 503", rr.Code)
	}
	assertCORS(t, rr.Header())
}

func TestCORSPanicRecoveredWithCORS(t *testing.T) {
	h := CORS(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		panic("boom")
	}))
	rr := httptest.NewRecorder()
	h.ServeHTTP(rr, httptest.NewRequest(http.MethodPost, "/api/v1/customers/registry/approve", nil))
	if rr.Code != http.StatusInternalServerError {
		t.Fatalf("code=%d want 500", rr.Code)
	}
	assertCORS(t, rr.Header())
	if !strings.Contains(rr.Body.String(), "internal server error") {
		t.Fatalf("body=%q", rr.Body.String())
	}
}

func TestCORSSuccessPassthrough(t *testing.T) {
	h := CORS(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.Header().Set("X-Data-Quality-Version", "1")
		_, _ = w.Write([]byte(`{"ok":true}`))
	}))
	rr := httptest.NewRecorder()
	h.ServeHTTP(rr, httptest.NewRequest(http.MethodGet, "/api/v1/data-quality/summary", nil))
	if rr.Code != http.StatusOK {
		t.Fatalf("code=%d", rr.Code)
	}
	assertCORS(t, rr.Header())
	if rr.Header().Get("X-Data-Quality-Version") != "1" {
		t.Fatal("custom response header dropped")
	}
	if !strings.Contains(rr.Header().Get("Access-Control-Expose-Headers"), "X-Data-Quality-Version") {
		t.Fatal("Expose-Headers missing X-Data-Quality-Version")
	}
}
