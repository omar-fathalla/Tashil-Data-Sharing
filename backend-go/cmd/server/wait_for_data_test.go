package main

import (
	"context"
	"net/http"
	"net/http/httptest"
	"sync/atomic"
	"testing"
	"time"
)

func TestArchiveListServedWhileDataLoads(t *testing.T) {
	ready := make(chan struct{}) // never closed: the dataset replay is still running
	var served atomic.Int32
	h := waitForData(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		served.Add(1)
		w.WriteHeader(http.StatusOK)
	}), ready)

	done := make(chan struct{})
	go func() {
		h.ServeHTTP(httptest.NewRecorder(), httptest.NewRequest("GET", "/api/v1/ingest/archive?file_type=sell_in", nil))
		close(done)
	}()
	select {
	case <-done:
	case <-time.After(time.Second):
		t.Fatal("archive list waited for the dataset replay")
	}
	if served.Load() != 1 {
		t.Fatal("archive list was not served")
	}

	// Dataset endpoints and archive writes still wait for the replay.
	for _, req := range []*http.Request{
		httptest.NewRequest("GET", "/api/v1/analytics/sell-in-records", nil),
		httptest.NewRequest("POST", "/api/v1/ingest/archive", nil),
	} {
		ctx, cancel := context.WithTimeout(context.Background(), 50*time.Millisecond)
		h.ServeHTTP(httptest.NewRecorder(), req.WithContext(ctx))
		cancel()
	}
	if served.Load() != 1 {
		t.Fatalf("data endpoints must keep waiting for the replay, served=%d", served.Load())
	}
}
