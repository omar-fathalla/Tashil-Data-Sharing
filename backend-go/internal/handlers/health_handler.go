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
}

// Healthz serves liveness and readiness probes.
func Healthz(w http.ResponseWriter, r *http.Request) {
	resp := HealthResponse{
		Status:    "healthy",
		Service:   "tashil-data-sharing-backend",
		Version:   "1.0.0",
		Timestamp: time.Now(),
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	_ = json.NewEncoder(w).Encode(resp)
}
