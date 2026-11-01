package middleware

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"net/http"
	"strings"
)

// ETag adds a content hash ETag to successful GET /api/v1/ JSON reads and answers
// If-None-Match with 304 Not Modified, so clients can cheaply revalidate cached data.
// The hash is over the exact response body, so it is correct across instances and
// per user/tenant (different bodies give different tags). File downloads and job
// polling are passed through untouched.
func ETag(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if !etagEligible(r) {
			next.ServeHTTP(w, r)
			return
		}
		rec := &etagRecorder{header: http.Header{}, status: http.StatusOK}
		next.ServeHTTP(rec, r)

		dst := w.Header()
		for k, v := range rec.header {
			dst[k] = v
		}
		if rec.status != http.StatusOK {
			w.WriteHeader(rec.status)
			_, _ = w.Write(rec.body.Bytes())
			return
		}
		sum := sha256.Sum256(rec.body.Bytes())
		tag := `"` + hex.EncodeToString(sum[:16]) + `"`
		dst.Set("ETag", tag)
		dst.Set("Cache-Control", "private, no-cache")
		if etagMatches(r.Header.Get("If-None-Match"), tag) {
			dst.Del("Content-Length")
			w.WriteHeader(http.StatusNotModified)
			return
		}
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write(rec.body.Bytes())
	})
}

func etagEligible(r *http.Request) bool {
	if r.Method != http.MethodGet {
		return false
	}
	p := r.URL.Path
	if !strings.HasPrefix(p, "/api/v1/") {
		return false
	}
	return !strings.HasSuffix(p, "/download") && !strings.HasPrefix(p, "/api/v1/jobs/")
}

func etagMatches(header, tag string) bool {
	if header == "" {
		return false
	}
	for _, part := range strings.Split(header, ",") {
		part = strings.TrimSpace(strings.TrimPrefix(strings.TrimSpace(part), "W/"))
		if part == tag || part == "*" {
			return true
		}
	}
	return false
}

type etagRecorder struct {
	header http.Header
	status int
	body   bytes.Buffer
	wrote  bool
}

func (e *etagRecorder) Header() http.Header { return e.header }

func (e *etagRecorder) WriteHeader(code int) {
	if !e.wrote {
		e.status = code
		e.wrote = true
	}
}

func (e *etagRecorder) Write(b []byte) (int, error) {
	e.wrote = true
	return e.body.Write(b)
}
