package middleware

import (
	"net"
	"net/http"
	"strings"
	"sync"
	"time"
)

// Ingest rate limits sized for a normal upload session (precheck + upload +
// commit + archive refreshes + job polls + CORS preflights on other tabs).
// OPTIONS never consumes the budget — browser preflights must not 429.
const (
	IngestRateLimitMax    = 180
	IngestRateLimitWindow = time.Minute
	IngestRateLimitMsg    = "طلبات كتير دلوقتي. حاول تاني بعد شوية."
)

// IngestRateLimiter bounds /api/v1/ingest/* traffic per client IP so a busy
// upload session gets a readable Arabic 429 with CORS instead of an opaque
// Cloud Run rejection. OPTIONS and job polls are exempt.
type IngestRateLimiter struct {
	mu      sync.Mutex
	hits    map[string][]time.Time
	max     int
	window  time.Duration
	nowFunc func() time.Time
}

// NewIngestRateLimiter returns a limiter with production defaults.
func NewIngestRateLimiter() *IngestRateLimiter {
	return &IngestRateLimiter{
		hits:    make(map[string][]time.Time),
		max:     IngestRateLimitMax,
		window:  IngestRateLimitWindow,
		nowFunc: time.Now,
	}
}

func (l *IngestRateLimiter) pruneLocked(key string, now time.Time) int {
	cutoff := now.Add(-l.window)
	kept := l.hits[key][:0]
	for _, t := range l.hits[key] {
		if t.After(cutoff) {
			kept = append(kept, t)
		}
	}
	l.hits[key] = kept
	return len(kept)
}

func (l *IngestRateLimiter) allow(key string) bool {
	l.mu.Lock()
	defer l.mu.Unlock()
	now := l.nowFunc()
	if l.pruneLocked(key, now) >= l.max {
		return false
	}
	l.hits[key] = append(l.hits[key], now)
	return true
}

// clientIP prefers the leftmost X-Forwarded-For hop (Cloud Run / GFE / Hosting).
func clientIP(r *http.Request) string {
	if r == nil {
		return "127.0.0.1"
	}
	if xff := strings.TrimSpace(r.Header.Get("X-Forwarded-For")); xff != "" {
		parts := strings.Split(xff, ",")
		if ip := strings.TrimSpace(parts[0]); ip != "" {
			return ip
		}
	}
	if xri := strings.TrimSpace(r.Header.Get("X-Real-IP")); xri != "" {
		return xri
	}
	if host, _, err := net.SplitHostPort(strings.TrimSpace(r.RemoteAddr)); err == nil && host != "" {
		return host
	}
	if r.RemoteAddr != "" {
		return r.RemoteAddr
	}
	return "127.0.0.1"
}

func ingestRateLimitedPath(path string) bool {
	return strings.HasPrefix(path, "/api/v1/ingest/")
}

// Handler enforces the ingest rate limit. OPTIONS preflights always pass.
func (l *IngestRateLimiter) Handler(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method == http.MethodOptions || !ingestRateLimitedPath(r.URL.Path) {
			next.ServeHTTP(w, r)
			return
		}
		if !l.allow(clientIP(r)) {
			// CORS middleware re-stamps Allow-Origin on WriteHeader; set Retry-After
			// so Flutter can back off instead of showing "file rejected".
			w.Header().Set("Content-Type", "application/json; charset=utf-8")
			w.Header().Set("Retry-After", "15")
			applyCORS(w.Header())
			w.WriteHeader(http.StatusTooManyRequests)
			_, _ = w.Write([]byte(`{"error":"rate_limited","message":"` + IngestRateLimitMsg + `"}`))
			return
		}
		next.ServeHTTP(w, r)
	})
}
