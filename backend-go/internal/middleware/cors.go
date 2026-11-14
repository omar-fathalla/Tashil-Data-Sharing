package middleware

import (
	"log"
	"net/http"
)

const (
	corsAllowOrigin  = "*"
	corsAllowMethods = "GET, POST, PUT, PATCH, DELETE, OPTIONS"
	corsAllowHeaders = "Accept, Content-Type, Content-Length, Accept-Encoding, X-CSRF-Token, Authorization, X-Tenant-ID, X-Retail-Chain, X-AI-Tier, X-Period-Date, X-Simulated-Role, X-Assigned-Chain, X-Assigned-Region, X-Tashil-Async, If-None-Match"
	corsExposeHeaders = "Content-Length, Content-Disposition, Content-Type, X-Data-Quality-Version, ETag"
	corsMaxAge        = "86400"
)

// applyCORS stamps the browser CORS policy onto h. Call before every WriteHeader so
// error responses, panics, and handlers that clear headers still remain readable from
// Flutter Web (otherwise the browser surfaces a CORS failure instead of the real status).
func applyCORS(h http.Header) {
	h.Set("Access-Control-Allow-Origin", corsAllowOrigin)
	h.Set("Access-Control-Allow-Methods", corsAllowMethods)
	h.Set("Access-Control-Allow-Headers", corsAllowHeaders)
	h.Set("Access-Control-Expose-Headers", corsExposeHeaders)
	h.Set("Access-Control-Max-Age", corsMaxAge)
}

// corsWriter re-applies CORS headers on every WriteHeader/Write so downstream middleware
// or handlers cannot drop Access-Control-Allow-Origin on 4xx/5xx paths.
type corsWriter struct {
	http.ResponseWriter
	wroteHeader bool
}

func (c *corsWriter) WriteHeader(code int) {
	applyCORS(c.ResponseWriter.Header())
	c.wroteHeader = true
	c.ResponseWriter.WriteHeader(code)
}

func (c *corsWriter) Write(b []byte) (int, error) {
	if !c.wroteHeader {
		applyCORS(c.ResponseWriter.Header())
		c.wroteHeader = true
	}
	return c.ResponseWriter.Write(b)
}

func (c *corsWriter) Flush() {
	if f, ok := c.ResponseWriter.(http.Flusher); ok {
		f.Flush()
	}
}

// CORS handles Cross-Origin Resource Sharing for Flutter Web clients.
// OPTIONS is answered here (no auth / data gate). All other responses — including
// auth errors, 5xx, and recovered panics — keep Access-Control-Allow-Origin.
func CORS(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		cw := &corsWriter{ResponseWriter: w}
		applyCORS(cw.Header())

		if r.Method == http.MethodOptions {
			cw.WriteHeader(http.StatusNoContent)
			return
		}

		defer func() {
			if rec := recover(); rec != nil {
				log.Printf("[cors] panic recovered: %v", rec)
				if !cw.wroteHeader {
					applyCORS(cw.Header())
					cw.Header().Set("Content-Type", "application/json")
					cw.WriteHeader(http.StatusInternalServerError)
					_, _ = cw.Write([]byte(`{"error":"internal server error"}`))
				}
			}
		}()

		next.ServeHTTP(cw, r)
	})
}
