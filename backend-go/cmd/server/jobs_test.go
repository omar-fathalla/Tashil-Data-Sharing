package main

import (
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync"
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
	if !isValidJobID(id) {
		t.Fatalf("invalid job_id in 202 body: %q (%s)", id, rr.Body.String())
	}

	poll := func(h http.Handler) (jobRecord, int, string) {
		rr := httptest.NewRecorder()
		h.ServeHTTP(rr, httptest.NewRequest(http.MethodGet, "/api/v1/jobs/"+id, nil))
		var rec jobRecord
		_ = json.Unmarshal(rr.Body.Bytes(), &rec)
		return rec, rr.Code, rr.Body.String()
	}
	if rec, code, body := poll(h); code != http.StatusOK || rec.Status != "running" {
		t.Fatalf("expected running, got code=%d rec=%+v body=%s", code, rec, body)
	}
	close(release)
	deadline := time.Now().Add(3 * time.Second)
	var rec jobRecord
	var code int
	var body string
	for time.Now().Before(deadline) {
		if rec, code, body = poll(h); rec.Status != "running" {
			break
		}
		time.Sleep(20 * time.Millisecond)
	}
	if code != http.StatusOK || rec.Status != "failed" || rec.HTTPStatus != 422 || !strings.Contains(string(rec.Body), `"got":"abc"`) {
		t.Fatalf("unexpected job result code=%d rec=%+v body=%s", code, rec, body)
	}
	// Another instance sharing the mount can answer the poll (disk, not memory).
	other, otherCode, otherBody := poll(newAsyncJobs(dir).wrap(next))
	if otherCode != http.StatusOK || other.Status != "failed" || other.HTTPStatus != 422 {
		t.Fatalf("job not visible from another instance: code=%d rec=%+v body=%s", otherCode, other, otherBody)
	}
	// Requests without the header stay synchronous.
	rr = httptest.NewRecorder()
	syncNext := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { w.WriteHeader(201) })
	newAsyncJobs("").wrap(syncNext).ServeHTTP(rr, httptest.NewRequest(http.MethodPost, "/api/v1/ingest/upload", nil))
	if rr.Code != 201 {
		t.Fatalf("expected synchronous passthrough, got %d", rr.Code)
	}
}

// Regression for Deploy production #50 / run 42548854796: memory used to update before
// disk, so a peer instance sharing the archive mount could 404 (or read a truncated
// WriteFile) after the owning instance already reported a terminal status.
func TestAsyncJobSharedMountVisibleToPeerInstance(t *testing.T) {
	dir := t.TempDir()
	owner := newAsyncJobs(dir)
	rec := &jobRecord{
		ID:        newJobID(),
		Path:      "/api/v1/ingest/upload",
		Status:    "running",
		CreatedAt: time.Now().UTC(),
	}
	owner.save(rec)

	peer := newAsyncJobs(dir)
	got := peer.load(rec.ID)
	if got == nil || got.Status != "running" || got.ID != rec.ID {
		t.Fatalf("peer cannot load running job from shared mount: %+v", got)
	}

	rec.Status = "failed"
	rec.HTTPStatus = http.StatusUnprocessableEntity
	rec.Body = json.RawMessage(`{"message":"rejected","got":"abc"}`)
	owner.save(rec)

	got = peer.load(rec.ID)
	if got == nil || got.Status != "failed" || got.HTTPStatus != 422 || !strings.Contains(string(got.Body), `"got":"abc"`) {
		t.Fatalf("peer cannot load terminal job from shared mount: %+v", got)
	}

	// On-disk file must be the final JSON (no leftover .tmp); a third instance agrees.
	entries, err := os.ReadDir(filepath.Join(dir, "_jobs"))
	if err != nil {
		t.Fatal(err)
	}
	for _, e := range entries {
		if strings.HasSuffix(e.Name(), ".tmp") {
			t.Fatalf("leftover temp file after save: %s", e.Name())
		}
	}
	third := newAsyncJobs(dir).load(rec.ID)
	if third == nil || third.Status != "failed" {
		t.Fatalf("third instance miss: %+v", third)
	}
}

func TestAsyncJobSharedMountConcurrentReadersSeeConsistentJSON(t *testing.T) {
	dir := t.TempDir()
	owner := newAsyncJobs(dir)
	id := newJobID()
	rec := &jobRecord{ID: id, Path: "/api/v1/ingest/upload", Status: "running", CreatedAt: time.Now().UTC()}
	owner.save(rec)

	var wg sync.WaitGroup
	errCh := make(chan string, 64)
	for i := 0; i < 8; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			peer := newAsyncJobs(dir)
			for n := 0; n < 40; n++ {
				got := peer.load(id)
				if got == nil {
					errCh <- "nil load from peer"
					return
				}
				if got.ID != id {
					errCh <- "wrong id"
					return
				}
				if got.Status != "running" && got.Status != "failed" && got.Status != "done" {
					errCh <- "corrupt status=" + got.Status
					return
				}
			}
		}()
	}
	for i := 0; i < 30; i++ {
		rec.Status = "running"
		rec.HTTPStatus = 0
		rec.Body = nil
		owner.save(rec)
		rec.Status = "failed"
		rec.HTTPStatus = 422
		rec.Body = json.RawMessage(`{"message":"rejected"}`)
		owner.save(rec)
	}
	wg.Wait()
	close(errCh)
	for msg := range errCh {
		t.Fatal(msg)
	}
	if got := newAsyncJobs(dir).load(id); got == nil || got.Status != "failed" {
		t.Fatalf("final peer load: %+v", got)
	}
}
