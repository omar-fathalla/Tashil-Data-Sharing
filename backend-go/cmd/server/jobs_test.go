package main

import (
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func TestAsyncJobRunsInBackgroundAndIsPollable(t *testing.T) {
	release := make(chan struct{})
	next := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		b, _ := io.ReadAll(r.Body)
		<-release
		w.WriteHeader(http.StatusUnprocessableEntity)
		_, _ = w.Write([]byte(`{"message":"rejected","got":"` + string(b) + `"}`))
	})
	dir := t.TempDir()
	h := newAsyncJobs(dir).wrap(next)

	req := httptest.NewRequest(http.MethodPost, "/api/v1/ingest/upload", strings.NewReader("abc"))
	req.Header.Set(asyncJobHeader, "1")
	rr := httptest.NewRecorder()
	h.ServeHTTP(rr, req)
	if rr.Code != http.StatusAccepted {
		t.Fatalf("expected 202, got %d", rr.Code)
	}
	var started map[string]string
	_ = json.Unmarshal(rr.Body.Bytes(), &started)
	id := started["job_id"]

	poll := func(h http.Handler) jobRecord {
		rr := httptest.NewRecorder()
		h.ServeHTTP(rr, httptest.NewRequest(http.MethodGet, "/api/v1/jobs/"+id, nil))
		var rec jobRecord
		_ = json.Unmarshal(rr.Body.Bytes(), &rec)
		return rec
	}
	if rec := poll(h); rec.Status != "running" {
		t.Fatalf("expected running, got %+v", rec)
	}
	close(release)
	deadline := time.Now().Add(3 * time.Second)
	var rec jobRecord
	for time.Now().Before(deadline) {
		if rec = poll(h); rec.Status != "running" {
			break
		}
		time.Sleep(20 * time.Millisecond)
	}
	if rec.Status != "failed" || rec.HTTPStatus != 422 || !strings.Contains(string(rec.Body), `"got":"abc"`) {
		t.Fatalf("unexpected job result %+v", rec)
	}
	// Another instance sharing the mount can answer the poll.
	if other := poll(newAsyncJobs(dir).wrap(next)); other.Status != "failed" {
		t.Fatalf("job not visible from another instance: %+v", other)
	}
	// Requests without the header stay synchronous.
	rr = httptest.NewRecorder()
	syncNext := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { w.WriteHeader(201) })
	newAsyncJobs("").wrap(syncNext).ServeHTTP(rr, httptest.NewRequest(http.MethodPost, "/api/v1/ingest/upload", nil))
	if rr.Code != 201 {
		t.Fatalf("expected synchronous passthrough, got %d", rr.Code)
	}
}
