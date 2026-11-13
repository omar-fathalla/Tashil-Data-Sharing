package handlers

import (
	"encoding/json"
	"net/http"
	"time"
)

// HealthResponse indicates service status on Cloud Run.
type HealthResponse struct {
	Status    string    `json:"status"`
	Service   string    `json:"service"`
	Version   string    `json:"version"`
	Timestamp time.Time `json:"timestamp"`
	Detail    string    `json:"detail,omitempty"`
}

// AuthReadiness is the readiness dependency for public health probes (auth user snapshot).
type AuthReadiness interface {
	AuthReady() error
}

// Healthz serves a liveness-style probe without auth gating (kept for unit tests).
func Healthz(w http.ResponseWriter, r *http.Request) {
	writeHealth(w, http.StatusOK, "healthy", "")
}

// HealthzWithAuth fails readiness (503) when auth users are not safely loaded.
// Mounted at GET /livez and GET /api/v1/health (Cloud Run-safe; do not rely on /healthz ingress).
func HealthzWithAuth(auth AuthReadiness) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if auth != nil {
			if err := auth.AuthReady(); err != nil {
				writeHealth(w, http.StatusServiceUnavailable, "not_ready", err.Error())
				return
			}
		}
		writeHealth(w, http.StatusOK, "healthy", "")
	}
}

// Readyz is the Cloud Run startup probe: 503 "loading" until the startup data load has
// finished (dataReady closed), then the same auth readiness check as /livez. Cloud Run only
// routes traffic to a new revision once this passes, so the old revision keeps serving while
// the new one loads (~3 min). Mounted at GET /readyz; /livez stays the cheap liveness check.
func Readyz(auth AuthReadiness, dataReady <-chan struct{}) http.HandlerFunc {
	health := HealthzWithAuth(auth)
	return func(w http.ResponseWriter, r *http.Request) {
		select {
		case <-dataReady:
		default:
			w.Header().Set("Retry-After", "10")
			writeHealth(w, http.StatusServiceUnavailable, "loading", "startup data load in progress")
			return
		}
		health(w, r)
	}
}

func writeHealth(w http.ResponseWriter, code int, status, detail string) {
	resp := HealthResponse{
		Status:    status,
		Service:   "tashil-data-sharing-backend",
		Version:   "1.0.0",
		Timestamp: time.Now(),
		Detail:    detail,
	}
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(code)
	_ = json.NewEncoder(w).Encode(resp)
}
