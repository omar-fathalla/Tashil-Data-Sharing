package handlers

import (
	"encoding/json"
	"net/http"
	"strings"

	"github.com/tashil/data-sharing/backend/internal/middleware"
	"github.com/tashil/data-sharing/backend/internal/service/arabicqa"
)

// ArabicQAHandler serves Phase C Arabic Q&A over BigQuery (read-only, tenant-scoped).
type ArabicQAHandler struct {
	svc *arabicqa.Service
}

// NewArabicQAHandler wires the Arabic Q&A service.
func NewArabicQAHandler(svc *arabicqa.Service) *ArabicQAHandler {
	return &ArabicQAHandler{svc: svc}
}

type askRequest struct {
	Question string `json:"question"`
}

// HandleAsk serves POST /api/v1/analytics/ask
func (h *ArabicQAHandler) HandleAsk(w http.ResponseWriter, r *http.Request) {
	tenantID, err := middleware.EnforceTenantRLS(r)
	if err != nil {
		writeErr(w, http.StatusUnauthorized, "unauthorized tenant context")
		return
	}
	if h.svc == nil {
		writeErr(w, http.StatusServiceUnavailable, "خدمة الأسئلة العربية مش متاحة")
		return
	}
	var req askRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || strings.TrimSpace(req.Question) == "" {
		writeErr(w, http.StatusBadRequest, "question مطلوب (سؤال بالعربي)")
		return
	}
	ans, err := h.svc.Ask(r.Context(), tenantID, req.Question)
	if err != nil {
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, ans)
}

// HandleCapabilities serves GET /api/v1/analytics/ask/capabilities
func (h *ArabicQAHandler) HandleCapabilities(w http.ResponseWriter, r *http.Request) {
	if _, err := middleware.EnforceTenantRLS(r); err != nil {
		writeErr(w, http.StatusUnauthorized, "unauthorized tenant context")
		return
	}
	caps := arabicqa.Capabilities()
	writeJSON(w, http.StatusOK, map[string]interface{}{
		"capabilities": caps,
		"count":        len(caps),
		"read_only":    true,
		"note_ar":      "الأسئلة مسموحة على بيانات المستأجر فقط — مفيش كتابة على BigQuery ولا SQL حر.",
	})
}
