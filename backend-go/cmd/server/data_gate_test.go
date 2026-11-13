package main

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"
)

// After a deploy the startup load (durable sync + cache warm-up) took ~3 minutes; the
// uploaded-files list waited on it and the web client timed out. The list must be served as
// soon as the archive is restored, while other data endpoints still wait for the full load.
func TestWaitForDataServesArchiveListOnceArchiveReady(t *testing.T) {
	dataReady := make(chan struct{}) // never closed in this test
	archiveReady := make(chan struct{})
	close(archiveReady)
	served := map[string]bool{}
	h := waitForData(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		served[r.Method+" "+r.URL.Path] = true
		w.WriteHeader(http.StatusOK)
	}), dataReady, archiveReady)

	do := func(method, path string) {
		ctx, cancel := context.WithTimeout(context.Background(), 50*time.Millisecond)
		defer cancel()
		req := httptest.NewRequest(method, path, nil).WithContext(ctx)
		h.ServeHTTP(httptest.NewRecorder(), req)
	}
	do(http.MethodGet, "/api/v1/ingest/archive")
	do(http.MethodGet, "/api/v1/analytics/records")
	do(http.MethodDelete, "/api/v1/ingest/archive")

	if !served["GET /api/v1/ingest/archive"] {
		t.Fatal("archive list must not wait for the full data load once the archive is ready")
	}
	if served["GET /api/v1/analytics/records"] {
		t.Fatal("analytics must still wait for the full data load")
	}
	if served["DELETE /api/v1/ingest/archive"] {
		t.Fatal("archive writes must still wait for the full data load")
	}
}

func TestWaitForDataArchiveListWaitsForArchiveRestore(t *testing.T) {
	dataReady := make(chan struct{})
	archiveReady := make(chan struct{})
	served := false
	h := waitForData(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { served = true }), dataReady, archiveReady)
	ctx, cancel := context.WithTimeout(context.Background(), 50*time.Millisecond)
	defer cancel()
	h.ServeHTTP(httptest.NewRecorder(), httptest.NewRequest(http.MethodGet, "/api/v1/ingest/archive", nil).WithContext(ctx))
	if served {
		t.Fatal("archive list must wait until the archive is restored")
	}
}
