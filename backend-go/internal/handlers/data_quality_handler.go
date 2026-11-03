package handlers

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"strconv"
	"strings"

	"github.com/tashil/data-sharing/backend/internal/domain"
	"github.com/tashil/data-sharing/backend/internal/service/dataquality"
	"github.com/tashil/data-sharing/backend/internal/service/firestore"
)

// dataQualityService is the part of dataquality.Service the handler uses.
type dataQualityService interface {
	ListIssues(ctx context.Context, tenantID string, f dataquality.IssueFilter) ([]domain.DataQualityIssue, error)
	UpdateStatus(ctx context.Context, tenantID, id, status, reason, by string) (*domain.DataQualityIssue, error)
	Summary(ctx context.Context, tenantID string) (*dataquality.Summary, error)
}

// DataQualityHandler serves the Errors ("الأخطاء") page.
type DataQualityHandler struct {
	svc   dataQualityService
	audit firestore.Repository
}

func NewDataQualityHandler(svc dataQualityService, audit firestore.Repository) *DataQualityHandler {
	return &DataQualityHandler{svc: svc, audit: audit}
}

var dataQualityWriteRoles = map[domain.UserRole]bool{
	domain.RoleSuperAdmin: true, domain.RoleVendorAdmin: true, domain.RoleAdmin: true,
	domain.RoleNationalSalesManager: true, domain.RoleExecutive: true,
}

func (h *DataQualityHandler) setVersion(w http.ResponseWriter, s *dataquality.Summary) {
	if s != nil && !s.UpdatedAt.IsZero() {
		w.Header().Set("X-Data-Quality-Version", strconv.FormatInt(s.UpdatedAt.UnixMilli(), 10))
	}
}

// HandleListIssues serves GET /api/v1/data-quality/issues?source=&type=&severity=&status=
// status defaults to open ("مفتوحة"); status=all returns every status.
func (h *DataQualityHandler) HandleListIssues(w http.ResponseWriter, r *http.Request) {
	c, ok := tmClaims(w, r)
	if !ok {
		return
	}
	q := r.URL.Query()
	f := dataquality.IssueFilter{Source: q.Get("source"), Type: q.Get("type"), Severity: q.Get("severity"), Status: q.Get("status")}
	if f.Status == "" {
		f.Status = domain.DQStatusOpen
	} else if f.Status == "all" {
		f.Status = ""
	}
	issues, err := h.svc.ListIssues(r.Context(), c.TenantID, f)
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "failed to load data-quality issues")
		return
	}
	sum, _ := h.svc.Summary(r.Context(), c.TenantID)
	h.setVersion(w, sum)
	writeJSON(w, http.StatusOK, map[string]interface{}{"issues": issues, "count": len(issues)})
}

// HandleSummary serves GET /api/v1/data-quality/summary.
func (h *DataQualityHandler) HandleSummary(w http.ResponseWriter, r *http.Request) {
	c, ok := tmClaims(w, r)
	if !ok {
		return
	}
	sum, err := h.svc.Summary(r.Context(), c.TenantID)
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "failed to load data-quality summary")
		return
	}
	h.setVersion(w, sum)
	writeJSON(w, http.StatusOK, sum)
}

// HandlePatchStatus serves PATCH /api/v1/data-quality/issues/{id} with {"status": "...", "reason": "..."}.
func (h *DataQualityHandler) HandlePatchStatus(w http.ResponseWriter, r *http.Request) {
	c, ok := tmWriteClaims(w, r)
	if !ok {
		return
	}
	if !dataQualityWriteRoles[c.Role] {
		writeErr(w, http.StatusForbidden, "role not allowed to change issue status")
		return
	}
	id := strings.TrimSpace(r.PathValue("id"))
	var body struct {
		Status string `json:"status"`
		Reason string `json:"reason"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeErr(w, http.StatusBadRequest, "invalid JSON body")
		return
	}
	iss, err := h.svc.UpdateStatus(r.Context(), c.TenantID, id, body.Status, body.Reason, c.Email)
	if errors.Is(err, dataquality.ErrNotFound) {
		writeErr(w, http.StatusNotFound, "issue not found")
		return
	}
	if err != nil {
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	if h.audit != nil {
		_ = h.audit.SaveAuditLog(r.Context(), &domain.AuditLogEntry{
			TenantID: normalizeAuditTenantID(c.TenantID), UserID: c.UserID, UserEmail: c.Email,
			UserRole: string(c.Role), Action: "data_quality_status_update", Resource: "data_quality_issues",
			Details: iss.ID + " " + iss.Type + " " + iss.ItemCode + " → " + iss.Status + " (" + iss.StatusReason + ")",
			IPAddress: extractRequestIP(r),
		})
	}
	writeJSON(w, http.StatusOK, iss)
}
