package middleware

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func TestIngestRateLimitExemptsOPTIONS(t *testing.T) {
	lim := NewIngestRateLimiter()
	lim.max = 1
	nextHits := 0
	h := lim.Handler(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		nextHits++
		w.WriteHeader(http.StatusNoContent)
	}))

	// Exhaust the budget with a real ingest GET.
	rr := httptest.NewRecorder()
	h.ServeHTTP(rr, httptest.NewRequest(http.MethodGet, "/api/v1/ingest/archive?file_type=sell_in", nil))
	if rr.Code != http.StatusNoContent {
		t.Fatalf("first GET: want 204, got %d", rr.Code)
	}

	// OPTIONS must still pass (and not consume further budget).
	for i := 0; i < 5; i++ {
		req := httptest.NewRequest(http.MethodOptions, "/api/v1/ingest/load-sell-in-plan?chain=fathalla", nil)
		req.Header.Set("Origin", "https://www.data.sw-point.com")
		req.Header.Set("Access-Control-Request-Method", "POST")
		rr = httptest.NewRecorder()
		h.ServeHTTP(rr, req)
		if rr.Code != http.StatusNoContent {
			t.Fatalf("OPTIONS #%d: want 204, got %d body=%s", i, rr.Code, rr.Body.String())
		}
	}
	if nextHits != 6 { // 1 GET + 5 OPTIONS
		t.Fatalf("nextHits=%d want 6", nextHits)
	}
}

func TestIngestRateLimit429HasCORSAndArabic(t *testing.T) {
	lim := NewIngestRateLimiter()
	lim.max = 2
	inner := lim.Handler(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte(`{"ok":true}`))
	}))
	h := CORS(inner)

	for i := 0; i < 2; i++ {
		rr := httptest.NewRecorder()
		h.ServeHTTP(rr, httptest.NewRequest(http.MethodGet, "/api/v1/ingest/archive", nil))
		if rr.Code != http.StatusOK {
			t.Fatalf("hit %d: want 200, got %d", i, rr.Code)
		}
	}

	rr := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/api/v1/ingest/archive?file_type=sell_in", nil)
	req.Header.Set("Origin", "https://www.data.sw-point.com")
	h.ServeHTTP(rr, req)
	if rr.Code != http.StatusTooManyRequests {
		t.Fatalf("want 429, got %d body=%s", rr.Code, rr.Body.String())
	}
	assertCORS(t, rr.Header())
	if rr.Header().Get("Retry-After") == "" {
		t.Fatal("Retry-After missing on 429")
	}
	if !strings.Contains(rr.Body.String(), IngestRateLimitMsg) {
		t.Fatalf("Arabic rate-limit message missing: %s", rr.Body.String())
	}
	if !strings.Contains(rr.Body.String(), `"error":"rate_limited"`) {
		t.Fatalf("error code missing: %s", rr.Body.String())
	}
}

func TestIngestRateLimitIgnoresNonIngestPaths(t *testing.T) {
	lim := NewIngestRateLimiter()
	lim.max = 1
	h := lim.Handler(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	}))
	// Exhaust ingest budget.
	rr := httptest.NewRecorder()
	h.ServeHTTP(rr, httptest.NewRequest(http.MethodGet, "/api/v1/ingest/archive", nil))
	rr = httptest.NewRecorder()
	h.ServeHTTP(rr, httptest.NewRequest(http.MethodGet, "/api/v1/ingest/archive", nil))
	if rr.Code != http.StatusTooManyRequests {
		t.Fatalf("want ingest 429, got %d", rr.Code)
	}
	// Analytics / jobs stay unlimited by this middleware.
	rr = httptest.NewRecorder()
	h.ServeHTTP(rr, httptest.NewRequest(http.MethodGet, "/api/v1/analytics/records", nil))
	if rr.Code != http.StatusOK {
		t.Fatalf("non-ingest should pass, got %d", rr.Code)
	}
	rr = httptest.NewRecorder()
	h.ServeHTTP(rr, httptest.NewRequest(http.MethodGet, "/api/v1/jobs/job_0123456789abcdef0123456789abcdef", nil))
	if rr.Code != http.StatusOK {
		t.Fatalf("job poll should pass, got %d", rr.Code)
	}
}

func TestIngestRateLimitWindowResets(t *testing.T) {
	lim := NewIngestRateLimiter()
	lim.max = 1
	now := time.Now()
	lim.nowFunc = func() time.Time { return now }

	h := lim.Handler(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	}))
	rr := httptest.NewRecorder()
	h.ServeHTTP(rr, httptest.NewRequest(http.MethodGet, "/api/v1/ingest/archive", nil))
	rr = httptest.NewRecorder()
	h.ServeHTTP(rr, httptest.NewRequest(http.MethodGet, "/api/v1/ingest/archive", nil))
	if rr.Code != http.StatusTooManyRequests {
		t.Fatalf("want 429 inside window, got %d", rr.Code)
	}

	now = now.Add(IngestRateLimitWindow + time.Second)
	rr = httptest.NewRecorder()
	h.ServeHTTP(rr, httptest.NewRequest(http.MethodGet, "/api/v1/ingest/archive", nil))
	if rr.Code != http.StatusOK {
		t.Fatalf("want 200 after window, got %d", rr.Code)
	}
}

func TestIngestRateLimitSizedForUploadSession(t *testing.T) {
	// A normal upload session fires dozens of ingest calls; the default budget
	// must absorb that without 429.
	lim := NewIngestRateLimiter()
	h := lim.Handler(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	}))
	for i := 0; i < 100; i++ {
		rr := httptest.NewRecorder()
		path := "/api/v1/ingest/archive"
		if i%10 == 0 {
			path = "/api/v1/ingest/precheck"
		}
		h.ServeHTTP(rr, httptest.NewRequest(http.MethodGet, path, nil))
		if rr.Code != http.StatusOK {
			t.Fatalf("request %d of normal session hit %d (budget too tight)", i, rr.Code)
		}
	}
}
