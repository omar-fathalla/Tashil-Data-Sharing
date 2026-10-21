package middleware

import (
	"net/http"
)

// CORS handles Cross-Origin Resource Sharing for Flutter Web clients.
func CORS(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
		w.Header().Set("Access-Control-Allow-Headers", "Accept, Content-Type, Content-Length, Accept-Encoding, X-CSRF-Token, Authorization, X-Tenant-ID, X-Retail-Chain, X-AI-Tier, X-Period-Date, X-Simulated-Role, X-Assigned-Chain, X-Assigned-Region")
		w.Header().Set("Access-Control-Expose-Headers", "Content-Length, Content-Disposition, Content-Type")

		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusNoContent)
			return
		}

		next.ServeHTTP(w, r)
	})
}
