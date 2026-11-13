package handlers

import (
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
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

func TestReadyz_LoadingUntilDataReady(t *testing.T) {
	dataReady := make(chan struct{})
	h := Readyz(stubAuthReady{}, dataReady)
	get := func() *httptest.ResponseRecorder {
		rec := httptest.NewRecorder()
		h(rec, httptest.NewRequest(http.MethodGet, "/readyz", nil))
		return rec
	}
	if rec := get(); rec.Code != http.StatusServiceUnavailable || !strings.Contains(rec.Body.String(), `"loading"`) {
		t.Fatalf("before load: want 503 loading, got %d %s", rec.Code, rec.Body.String())
	}
	close(dataReady)
	if rec := get(); rec.Code != http.StatusOK {
		t.Fatalf("after load: want 200, got %d %s", rec.Code, rec.Body.String())
	}
}

func TestReadyz_FailsClosedWhenAuthNotReady(t *testing.T) {
	dataReady := make(chan struct{})
	close(dataReady)
	rec := httptest.NewRecorder()
	Readyz(stubAuthReady{err: errors.New("auth snapshot missing")}, dataReady)(rec, httptest.NewRequest(http.MethodGet, "/readyz", nil))
	if rec.Code != http.StatusServiceUnavailable {
		t.Fatalf("want 503 when auth not ready, got %d", rec.Code)
	}
}
