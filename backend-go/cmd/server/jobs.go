package main

import (
	"bytes"
	"context"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"io"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"
)

// asyncJobHeader asks for a large ingest to run as a background job: the request is
// answered at once with 202 {"job_id"} and the client polls GET /api/v1/jobs/{id}.
// This keeps big workbooks clear of the Cloud Run 300s request limit (504s) and stops
// clients from re-sending the same upload after a timeout.
const asyncJobHeader = "X-Tashil-Async"

const maxAsyncBody = 200 << 20

var asyncJobPaths = map[string]bool{
	"/api/v1/ingest/upload":            true,
	"/api/v1/ingest/commit":            true,
	"/api/v1/ingest/load-sell-in-plan": true,
	"/api/v1/product-master/upload":    true,
}

type jobRecord struct {
	ID         string          `json:"job_id"`
	Path       string          `json:"path"`
	Status     string          `json:"status"` // running, done, failed
	HTTPStatus int             `json:"http_status,omitempty"`
	Body       json.RawMessage `json:"body,omitempty"`
	Error      string          `json:"error,omitempty"`
	CreatedAt  time.Time       `json:"created_at"`
	UpdatedAt  time.Time       `json:"updated_at"`
}

type asyncJobs struct {
	mu   sync.RWMutex
	jobs map[string]*jobRecord
	dir  string // shared mount so any instance can answer a poll; one file per job, no shared writes

	// commitByBatch maps batch_id → running job_id so a retried POST /ingest/commit
	// returns the same 202 instead of starting a duplicate write.
	commitMu      sync.Mutex
	commitByBatch map[string]string
}

func newAsyncJobs(archiveDir string) *asyncJobs {
	j := &asyncJobs{
		jobs:          map[string]*jobRecord{},
		commitByBatch: map[string]string{},
	}
	if archiveDir != "" {
		j.dir = filepath.Join(archiveDir, "_jobs")
		_ = os.MkdirAll(j.dir, 0o755)
	}
	return j
}

func (j *asyncJobs) save(rec *jobRecord) {
	rec.UpdatedAt = time.Now().UTC()
	cp := *rec
	// Persist first, atomically (temp file + rename), so another instance never reads
	// a truncated file or sees a status this instance has not written to disk yet.
	// Memory is updated only after the rename attempt so a peer sharing the mount can
	// load whatever this instance already considers durable (or the prior file).
	if j.dir != "" {
		if data, err := json.Marshal(&cp); err != nil {
			log.Printf("[jobs] cannot marshal job %s: %v", rec.ID, err)
		} else {
			final := filepath.Join(j.dir, rec.ID+".json")
			tmp := final + ".tmp"
			if err := os.WriteFile(tmp, data, 0o644); err != nil {
				log.Printf("[jobs] cannot persist job %s: %v", rec.ID, err)
			} else if err := os.Rename(tmp, final); err != nil {
				log.Printf("[jobs] cannot persist job %s: %v", rec.ID, err)
				_ = os.Remove(tmp)
			}
		}
	}
	j.mu.Lock()
	j.jobs[rec.ID] = &cp
	j.mu.Unlock()
}

func (j *asyncJobs) load(id string) *jobRecord {
	j.mu.RLock()
	rec := j.jobs[id]
	j.mu.RUnlock()
	if rec != nil {
		cp := *rec
		return &cp
	}
	if j.dir == "" {
		return nil
	}
	raw, err := os.ReadFile(filepath.Join(j.dir, id+".json"))
	if err != nil {
		return nil
	}
	var out jobRecord
	if json.Unmarshal(raw, &out) != nil {
		return nil
	}
	return &out
}

type bufferedResponse struct {
	header http.Header
	status int
	buf    bytes.Buffer
}

func (b *bufferedResponse) Header() http.Header { return b.header }
func (b *bufferedResponse) WriteHeader(code int) {
	if b.status == 0 {
		b.status = code
	}
}
func (b *bufferedResponse) Write(p []byte) (int, error) {
	if b.status == 0 {
		b.status = http.StatusOK
	}
	return b.buf.Write(p)
}

func newJobID() string {
	b := make([]byte, 16)
	_, _ = rand.Read(b)
	return "job_" + hex.EncodeToString(b)
}

func isValidJobID(id string) bool {
	if !strings.HasPrefix(id, "job_") || len(id) != 36 {
		return false
	}
	_, err := hex.DecodeString(id[4:])
	return err == nil
}

func writeJobJSON(w http.ResponseWriter, status int, v interface{}) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}

// commitAlwaysAsync: large Sell-Out/Sell-In commits (80k+ rows) exceed the 180s
// WriteTimeout and Cloud Run request budget when run synchronously — the write
// often finishes but the client sees 503. Always answer 202 + job_id so the UI polls.
func commitAlwaysAsync(path string) bool {
	return path == "/api/v1/ingest/commit"
}

func commitBatchID(body []byte) string {
	var req struct {
		BatchID string `json:"batch_id"`
	}
	if json.Unmarshal(body, &req) != nil {
		return ""
	}
	return strings.TrimSpace(req.BatchID)
}

// wrap runs opted-in ingest requests in the background and serves job status.
func (j *asyncJobs) wrap(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method == http.MethodGet && strings.HasPrefix(r.URL.Path, "/api/v1/jobs/") {
			id := strings.TrimPrefix(r.URL.Path, "/api/v1/jobs/")
			if !isValidJobID(id) {
				writeJobJSON(w, http.StatusNotFound, map[string]string{"message": "job not found"})
				return
			}
			rec := j.load(id)
			if rec == nil {
				writeJobJSON(w, http.StatusNotFound, map[string]string{"message": "job not found"})
				return
			}
			writeJobJSON(w, http.StatusOK, rec)
			return
		}
		wantAsync := r.Header.Get(asyncJobHeader) == "1" || commitAlwaysAsync(r.URL.Path)
		if r.Method != http.MethodPost || !asyncJobPaths[r.URL.Path] || !wantAsync {
			next.ServeHTTP(w, r)
			return
		}
		body, err := io.ReadAll(http.MaxBytesReader(w, r.Body, maxAsyncBody))
		if err != nil {
			writeJobJSON(w, http.StatusRequestEntityTooLarge, map[string]string{"message": "file too large or upload interrupted"})
			return
		}

		// Idempotent commit: a retry while the first job is still running reuses it
		// so the same batch is not written twice in parallel.
		var batchKey string
		if commitAlwaysAsync(r.URL.Path) {
			if batchKey = commitBatchID(body); batchKey != "" {
				j.commitMu.Lock()
				if existing := j.commitByBatch[batchKey]; existing != "" {
					if rec := j.load(existing); rec != nil && rec.Status == "running" {
						j.commitMu.Unlock()
						log.Printf("[jobs] commit retry for batch %s reuses %s", batchKey, existing)
						writeJobJSON(w, http.StatusAccepted, map[string]string{"job_id": existing, "status": "running"})
						return
					}
					delete(j.commitByBatch, batchKey)
				}
				j.commitMu.Unlock()
			}
		}

		rec := &jobRecord{ID: newJobID(), Path: r.URL.Path, Status: "running", CreatedAt: time.Now().UTC()}
		if batchKey != "" {
			j.commitMu.Lock()
			j.commitByBatch[batchKey] = rec.ID
			j.commitMu.Unlock()
		}
		j.save(rec)

		bg := r.Clone(context.WithoutCancel(r.Context()))
		bg.Body = io.NopCloser(bytes.NewReader(body))
		bg.ContentLength = int64(len(body))
		bg.Header.Del(asyncJobHeader)
		go j.run(next, bg, rec, batchKey)

		log.Printf("[jobs] %s started for %s (%d bytes)", rec.ID, rec.Path, len(body))
		writeJobJSON(w, http.StatusAccepted, map[string]string{"job_id": rec.ID, "status": "running"})
	})
}

func (j *asyncJobs) clearCommitBatch(batchKey, jobID string) {
	if batchKey == "" {
		return
	}
	j.commitMu.Lock()
	defer j.commitMu.Unlock()
	if j.commitByBatch[batchKey] == jobID {
		delete(j.commitByBatch, batchKey)
	}
}

func (j *asyncJobs) run(next http.Handler, r *http.Request, rec *jobRecord, batchKey string) {
	start := time.Now()
	defer func() {
		if p := recover(); p != nil {
			rec.Status = "failed"
			rec.HTTPStatus = http.StatusInternalServerError
			rec.Error = "internal error while processing the file"
			log.Printf("[jobs] %s panicked: %v", rec.ID, p)
			j.save(rec)
		}
		j.clearCommitBatch(batchKey, rec.ID)
	}()
	resp := &bufferedResponse{header: http.Header{}}
	next.ServeHTTP(resp, r)
	if resp.status == 0 {
		resp.status = http.StatusOK
	}
	rec.HTTPStatus = resp.status
	raw := resp.buf.Bytes()
	if json.Valid(raw) {
		rec.Body = append(json.RawMessage(nil), raw...)
	} else {
		quoted, _ := json.Marshal(map[string]string{"message": strings.TrimSpace(string(raw))})
		rec.Body = quoted
	}
	if resp.status >= 200 && resp.status < 300 {
		rec.Status = "done"
	} else {
		rec.Status = "failed"
	}
	j.save(rec)
	log.Printf("[jobs] %s %s status=%d in %s", rec.ID, rec.Status, resp.status, time.Since(start).Round(time.Millisecond))
}
