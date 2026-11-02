package middleware

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"net/http"
	"strings"
)

// etagMaxBody is the largest response body the ETag middleware buffers. Larger
// responses are streamed straight through without an ETag, so a heavy read can
// never hold a second full copy of itself in memory.
const etagMaxBody = 5 << 20

// etagVary lists the request headers that change a response body. Responses are
// per user/tenant/role/chain/region, so shared caches must never mix them.
const etagVary = "Authorization, X-Tenant-ID, X-Simulated-Role, X-Assigned-Chain, X-Assigned-Region"

// ETag adds a content hash ETag to successful GET /api/v1/ JSON reads and answers
// If-None-Match with 304 Not Modified, so clients can cheaply revalidate cached data.
// Responses are marked private, no-store with Vary on the identity headers: the
// browser must not keep its own copy (the app's in-memory cache owns revalidation).
// File downloads, job polling and very large endpoints are passed through untouched.
func ETag(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if !etagEligible(r) {
			next.ServeHTTP(w, r)
			return
		}
		rec := &etagRecorder{dst: w, header: http.Header{}, status: http.StatusOK}
		next.ServeHTTP(rec, r)
		if rec.streaming {
			return
		}

		dst := w.Header()
		for k, v := range rec.header {
			dst[k] = v
		}
		if rec.status != http.StatusOK || !isJSON(rec.header.Get("Content-Type")) {
			w.WriteHeader(rec.status)
			_, _ = w.Write(rec.body.Bytes())
			return
		}
		sum := sha256.Sum256(rec.body.Bytes())
		tag := `"` + hex.EncodeToString(sum[:16]) + `"`
		dst.Set("ETag", tag)
		dst.Set("Cache-Control", "private, no-store")
		dst.Add("Vary", etagVary)
		if etagMatches(r.Header.Get("If-None-Match"), tag) {
			dst.Del("Content-Length")
			w.WriteHeader(http.StatusNotModified)
			return
		}
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write(rec.body.Bytes())
	})
}

func isJSON(ct string) bool {
	return strings.Contains(strings.ToLower(ct), "json")
}

func etagEligible(r *http.Request) bool {
	if r.Method != http.MethodGet {
		return false
	}
	p := r.URL.Path
	if !strings.HasPrefix(p, "/api/v1/") {
		return false
	}
	// Heavy row dumps: buffering them doubles peak memory, so they are never tagged.
	if p == "/api/v1/analytics/records" {
		return false
	}
	return !strings.HasSuffix(p, "/download") && !strings.HasPrefix(p, "/api/v1/jobs/")
}

// etagMatches compares If-None-Match against tag. "*" is deliberately not honoured:
// it would turn any read into an empty 304.
func etagMatches(header, tag string) bool {
	if header == "" {
		return false
	}
	for _, part := range strings.Split(header, ",") {
		part = strings.TrimSpace(strings.TrimPrefix(strings.TrimSpace(part), "W/"))
		if part == tag {
			return true
		}
	}
	return false
}

// etagRecorder buffers up to etagMaxBody bytes; beyond that it switches to
// streaming the response directly to dst without an ETag.
type etagRecorder struct {
	dst       http.ResponseWriter
	header    http.Header
	status    int
	body      bytes.Buffer
	wrote     bool
	streaming bool
}

func (e *etagRecorder) Header() http.Header {
	if e.streaming {
		return e.dst.Header()
	}
	return e.header
}

func (e *etagRecorder) WriteHeader(code int) {
	if !e.wrote {
		e.status = code
		e.wrote = true
	}
}

func (e *etagRecorder) Write(b []byte) (int, error) {
	e.wrote = true
	if e.streaming {
		return e.dst.Write(b)
	}
	if e.body.Len()+len(b) <= etagMaxBody {
		return e.body.Write(b)
	}
	e.streaming = true
	dst := e.dst.Header()
	for k, v := range e.header {
		dst[k] = v
	}
	dst.Del("ETag")
	e.dst.WriteHeader(e.status)
	if _, err := e.dst.Write(e.body.Bytes()); err != nil {
		return 0, err
	}
	e.body = bytes.Buffer{}
	return e.dst.Write(b)
}

// Flush lets streaming handlers flush once the recorder has switched to pass-through.
func (e *etagRecorder) Flush() {
	if f, ok := e.dst.(http.Flusher); ok && e.streaming {
		f.Flush()
	}
}
