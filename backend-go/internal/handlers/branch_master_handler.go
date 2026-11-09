package handlers

import (
	"encoding/json"
	"net/http"
	"strings"

	"github.com/tashil/data-sharing/backend/internal/middleware"
	"github.com/tashil/data-sharing/backend/internal/service/branchmaster"
)

// BranchMasterHandler serves branch / alias / pending management APIs.
type BranchMasterHandler struct {
	svc *branchmaster.Service
}

// NewBranchMasterHandler constructs the handler.
func NewBranchMasterHandler(svc *branchmaster.Service) *BranchMasterHandler {
	return &BranchMasterHandler{svc: svc}
}

// HandleGet serves GET /api/v1/branches/master — full state (chains, branches, aliases, pending, notices).
func (h *BranchMasterHandler) HandleGet(w http.ResponseWriter, r *http.Request) {
	tenantID, err := middleware.EnforceTenantRLS(r)
	if err != nil {
		http.Error(w, `{"error":"unauthorized tenant context"}`, http.StatusUnauthorized)
		return
	}
	if h.svc == nil {
		writeErr(w, http.StatusServiceUnavailable, "branch master unavailable")
		return
	}
	st, err := h.svc.Get(r.Context(), tenantID)
	if err != nil {
		writeErr(w, http.StatusInternalServerError, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, st)
}

// HandleListBranches serves GET /api/v1/branches?chain_code=
func (h *BranchMasterHandler) HandleListBranches(w http.ResponseWriter, r *http.Request) {
	tenantID, err := middleware.EnforceTenantRLS(r)
	if err != nil {
		http.Error(w, `{"error":"unauthorized tenant context"}`, http.StatusUnauthorized)
		return
	}
	list, err := h.svc.ListBranches(r.Context(), tenantID, r.URL.Query().Get("chain_code"))
	if err != nil {
		writeErr(w, http.StatusInternalServerError, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, map[string]interface{}{"branches": list, "count": len(list)})
}

// HandleListAliases serves GET /api/v1/branches/aliases?branch_code=
func (h *BranchMasterHandler) HandleListAliases(w http.ResponseWriter, r *http.Request) {
	tenantID, err := middleware.EnforceTenantRLS(r)
	if err != nil {
		http.Error(w, `{"error":"unauthorized tenant context"}`, http.StatusUnauthorized)
		return
	}
	list, err := h.svc.ListAliases(r.Context(), tenantID, r.URL.Query().Get("branch_code"))
	if err != nil {
		writeErr(w, http.StatusInternalServerError, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, map[string]interface{}{"aliases": list, "count": len(list)})
}

// HandleListPending serves GET /api/v1/branches/pending
func (h *BranchMasterHandler) HandleListPending(w http.ResponseWriter, r *http.Request) {
	tenantID, err := middleware.EnforceTenantRLS(r)
	if err != nil {
		http.Error(w, `{"error":"unauthorized tenant context"}`, http.StatusUnauthorized)
		return
	}
	list, err := h.svc.ListPending(r.Context(), tenantID)
	if err != nil {
		writeErr(w, http.StatusInternalServerError, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, map[string]interface{}{"pending": list, "count": len(list)})
}

type updateBranchRequest struct {
	BranchCode  string `json:"branch_code"`
	DisplayName string `json:"display_name"`
}

// HandleUpdateBranch serves PUT /api/v1/branches — edit display name.
func (h *BranchMasterHandler) HandleUpdateBranch(w http.ResponseWriter, r *http.Request) {
	c, ok := requireWriteRole(w, r, ingestWriteRoles)
	if !ok {
		return
	}
	var req updateBranchRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || strings.TrimSpace(req.BranchCode) == "" {
		writeErr(w, http.StatusBadRequest, "branch_code and display_name required")
		return
	}
	br, err := h.svc.UpdateDisplayName(r.Context(), c.TenantID, req.BranchCode, req.DisplayName, c.Email)
	if err != nil {
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, br)
}

type confirmPendingRequest struct {
	PendingID      string `json:"pending_id"`
	BranchCode     string `json:"branch_code"` // existing code, or "new"
	NewDisplayName string `json:"new_display_name,omitempty"`
}

// HandleConfirmPending serves POST /api/v1/branches/pending/confirm
func (h *BranchMasterHandler) HandleConfirmPending(w http.ResponseWriter, r *http.Request) {
	c, ok := requireWriteRole(w, r, ingestWriteRoles)
	if !ok {
		return
	}
	var req confirmPendingRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || strings.TrimSpace(req.PendingID) == "" {
		writeErr(w, http.StatusBadRequest, "pending_id required")
		return
	}
	p, err := h.svc.ConfirmPending(r.Context(), c.TenantID, req.PendingID, req.BranchCode, req.NewDisplayName, c.Email)
	if err != nil {
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, p)
}

// HandleRejectPending serves POST /api/v1/branches/pending/reject
func (h *BranchMasterHandler) HandleRejectPending(w http.ResponseWriter, r *http.Request) {
	c, ok := requireWriteRole(w, r, ingestWriteRoles)
	if !ok {
		return
	}
	var req confirmPendingRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || strings.TrimSpace(req.PendingID) == "" {
		writeErr(w, http.StatusBadRequest, "pending_id required")
		return
	}
	p, err := h.svc.RejectPending(r.Context(), c.TenantID, req.PendingID, c.Email)
	if err != nil {
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, p)
}

type bootstrapConfirmRequest struct {
	Report branchmaster.DryRunReport `json:"report"`
}

// HandleConfirmBootstrap serves POST /api/v1/branches/bootstrap/confirm
// Writes master tables only after explicit owner approval of a dry-run proposal.
func (h *BranchMasterHandler) HandleConfirmBootstrap(w http.ResponseWriter, r *http.Request) {
	c, ok := requireWriteRole(w, r, ingestWriteRoles)
	if !ok {
		return
	}
	var req bootstrapConfirmRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || len(req.Report.Rows) == 0 {
		writeErr(w, http.StatusBadRequest, "report.rows required")
		return
	}
	st, err := h.svc.ConfirmBootstrap(r.Context(), c.TenantID, req.Report, c.Email)
	if err != nil {
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, st)
}

// HandleDryRun serves POST /api/v1/branches/dry-run — proposal only, no writes.
func (h *BranchMasterHandler) HandleDryRun(w http.ResponseWriter, r *http.Request) {
	tenantID, err := middleware.EnforceTenantRLS(r)
	if err != nil {
		http.Error(w, `{"error":"unauthorized tenant context"}`, http.StatusUnauthorized)
		return
	}
	var body struct {
		Occurrences []branchmaster.RawOccurrence `json:"occurrences"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeErr(w, http.StatusBadRequest, "invalid json")
		return
	}
	report := branchmaster.BuildDryRunProposal(tenantID, body.Occurrences)
	writeJSON(w, http.StatusOK, report)
}
