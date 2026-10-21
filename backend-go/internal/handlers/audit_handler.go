package handlers

import (
	"encoding/json"
	"fmt"
	"net"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/tashil/data-sharing/backend/internal/domain"
	"github.com/tashil/data-sharing/backend/internal/middleware"
	"github.com/tashil/data-sharing/backend/internal/service/firestore"
)

// AuditHandler manages enterprise security audit logs with strict tenant RLS isolation.
type AuditHandler struct {
	fsRepo firestore.Repository
}

// NewAuditHandler constructs an AuditHandler.
func NewAuditHandler(fsRepo firestore.Repository) *AuditHandler {
	return &AuditHandler{fsRepo: fsRepo}
}

func extractRequestIP(r *http.Request) string {
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

func normalizeAuditTenantID(tenantID string) string {
	clean := strings.TrimSpace(strings.ToLower(tenantID))
	if clean == "" || clean == "system" || clean == "all" {
		return "system"
	}
	slug := strings.TrimPrefix(strings.TrimPrefix(clean, "tenant-"), "tenant_")
	if slug == "" {
		return "system"
	}
	return "tenant-" + slug
}

// HandleGetAuditLogs serves GET /api/v1/audit/logs.
func (h *AuditHandler) HandleGetAuditLogs(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, `{"error":"method not allowed"}`, http.StatusMethodNotAllowed)
		return
	}

	claims, ok := middleware.GetUserClaims(r.Context())
	if !ok || claims == nil || strings.TrimSpace(claims.TenantID) == "" {
		http.Error(w, `{"error":"unauthorized tenant context"}`, http.StatusUnauthorized)
		return
	}

	q := r.URL.Query()
	actionFilter := strings.TrimSpace(q.Get("action"))
	limit, _ := strconv.Atoi(q.Get("limit"))
	if limit <= 0 || limit > 500 {
		limit = 100
	}

	targetTenant := claims.TenantID
	if claims.Role == domain.RoleSuperAdmin {
		if reqTenant := strings.TrimSpace(q.Get("tenant_id")); reqTenant != "" {
			targetTenant = reqTenant
		}
	}

	logs, err := h.fsRepo.GetAuditLogs(r.Context(), targetTenant, actionFilter, limit)
	if err != nil {
		http.Error(w, `{"error":"failed to retrieve audit logs"}`, http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(logs)
}

// HandleCreateAuditLog serves POST /api/v1/audit/logs.
func (h *AuditHandler) HandleCreateAuditLog(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, `{"error":"method not allowed"}`, http.StatusMethodNotAllowed)
		return
	}

	claims, ok := middleware.GetUserClaims(r.Context())
	if !ok || claims == nil || strings.TrimSpace(claims.TenantID) == "" {
		http.Error(w, `{"error":"unauthorized tenant context"}`, http.StatusUnauthorized)
		return
	}

	var req domain.CreateAuditLogRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, `{"error":"invalid request body"}`, http.StatusBadRequest)
		return
	}

	action := strings.TrimSpace(req.Action)
	if action == "" {
		http.Error(w, `{"error":"action is required"}`, http.StatusBadRequest)
		return
	}

	resource := strings.TrimSpace(req.Resource)
	if resource == "" {
		resource = "portal"
	}

	now := time.Now()
	entry := domain.AuditLogEntry{
		LogID:     fmt.Sprintf("audit_%s_%s", now.Format("20060102150405"), uuid.New().String()[:8]),
		TenantID:  normalizeAuditTenantID(claims.TenantID),
		UserID:    claims.UserID,
		UserEmail: claims.Email,
		UserRole:  string(claims.Role),
		Action:    action,
		Resource:  resource,
		Details:   strings.TrimSpace(req.Details),
		IPAddress: extractRequestIP(r),
		Status:    "SUCCESS",
		CreatedAt: now,
	}

	if err := h.fsRepo.SaveAuditLog(r.Context(), &entry); err != nil {
		http.Error(w, `{"error":"failed to save audit log"}`, http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusCreated)
	_ = json.NewEncoder(w).Encode(entry)
}
