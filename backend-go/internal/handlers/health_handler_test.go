package handlers

import (
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"testing"
)

type stubAuthReady struct{ err error }

func (s stubAuthReady) AuthReady() error { return s.err }

func TestHealthzWithAuthReady(t *testing.T) {
	for _, path := range []string{"/livez", "/api/v1/health", "/healthz"} {
		t.Run(path, func(t *testing.T) {
			req := httptest.NewRequest(http.MethodGet, path, nil)
			rec := httptest.NewRecorder()
			HealthzWithAuth(stubAuthReady{}).ServeHTTP(rec, req)
			if rec.Code != http.StatusOK {
				t.Fatalf("want 200, got %d", rec.Code)
			}
			var body HealthResponse
			if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
				t.Fatal(err)
			}
			if body.Status != "healthy" {
				t.Fatalf("status=%q", body.Status)
			}
		})
	}
}

func TestHealthzWithAuthNotReady(t *testing.T) {
	req := httptest.NewRequest(http.MethodGet, "/livez", nil)
	rec := httptest.NewRecorder()
	HealthzWithAuth(stubAuthReady{err: errors.New("auth load failed")}).ServeHTTP(rec, req)
	if rec.Code != http.StatusServiceUnavailable {
		t.Fatalf("want 503, got %d body=%s", rec.Code, rec.Body.String())
	}
	var body HealthResponse
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatal(err)
	}
	if body.Status != "not_ready" {
		t.Fatalf("status=%q", body.Status)
	}
}
