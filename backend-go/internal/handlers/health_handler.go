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

// AuthReadiness is the readiness dependency for /healthz (auth user snapshot).
type AuthReadiness interface {
	AuthReady() error
}

// Healthz serves a liveness-style probe without auth gating (kept for unit tests).
func Healthz(w http.ResponseWriter, r *http.Request) {
	writeHealth(w, http.StatusOK, "healthy", "")
}

// HealthzWithAuth fails readiness (503) when auth users are not safely loaded.
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
