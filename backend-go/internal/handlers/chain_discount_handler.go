package handlers

import (
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
	"time"

	"github.com/tashil/data-sharing/backend/internal/domain"
	"github.com/tashil/data-sharing/backend/internal/service/firestore"
)

// ChainDiscountApplier receives saved profiles so CPFR cost uses them immediately.
type ChainDiscountApplier interface {
	SetChainDiscountProfiles(tenantID string, profiles []domain.ChainDiscountProfile)
}

// ChainDiscountHandler serves per-tenant chain discount profiles (Product Master page).
type ChainDiscountHandler struct {
	repo    firestore.ChainDiscountRepository
	audit   firestore.Repository
	applier ChainDiscountApplier
}

// NewChainDiscountHandler constructs the handler. audit and applier may be nil.
func NewChainDiscountHandler(repo firestore.ChainDiscountRepository, audit firestore.Repository, applier ChainDiscountApplier) *ChainDiscountHandler {
	return &ChainDiscountHandler{repo: repo, audit: audit, applier: applier}
}

var chainDiscountWriteRoles = map[domain.UserRole]bool{
	domain.RoleSuperAdmin: true, domain.RoleVendorAdmin: true, domain.RoleAdmin: true,
	domain.RoleNationalSalesManager: true, domain.RoleExecutive: true,
}

type chainDiscountResponse struct {
	*domain.ChainDiscountProfiles
	DefaultInvoiceDiscountPct    float64 `json:"default_invoice_discount_pct"`
	DefaultAdditionalDiscountPct float64 `json:"default_additional_discount_pct"`
}

func wrapChainDiscounts(d *domain.ChainDiscountProfiles) chainDiscountResponse {
	return chainDiscountResponse{ChainDiscountProfiles: d, DefaultInvoiceDiscountPct: 10, DefaultAdditionalDiscountPct: 0}
}

// HandleGet serves GET /api/v1/product-master/chain-discounts.
func (h *ChainDiscountHandler) HandleGet(w http.ResponseWriter, r *http.Request) {
	c, ok := tmClaims(w, r)
	if !ok {
		return
	}
	d, err := h.repo.GetChainDiscountProfiles(r.Context(), c.TenantID)
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "failed to load chain discounts")
		return
	}
	if h.applier != nil {
		h.applier.SetChainDiscountProfiles(c.TenantID, d.Profiles)
	}
	writeJSON(w, http.StatusOK, wrapChainDiscounts(d))
}

// HandlePut serves PUT /api/v1/product-master/chain-discounts with body {"profiles":[...]}:
// it replaces the tenant's full list (add / edit / delete are all done by sending the new list).
func (h *ChainDiscountHandler) HandlePut(w http.ResponseWriter, r *http.Request) {
	c, ok := tmWriteClaims(w, r)
	if !ok {
		return
	}
	if !chainDiscountWriteRoles[c.Role] {
		writeErr(w, http.StatusForbidden, "role not allowed to edit chain discounts")
		return
	}
	var body struct {
		Profiles []domain.ChainDiscountProfile `json:"profiles"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeErr(w, http.StatusBadRequest, "invalid json payload")
		return
	}
	if body.Profiles == nil {
		body.Profiles = []domain.ChainDiscountProfile{}
	}
	if err := firestore.ValidateChainDiscountProfiles(body.Profiles); err != nil {
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	prev, _ := h.repo.GetChainDiscountProfiles(r.Context(), c.TenantID)
	prevBy := map[string]domain.ChainDiscountProfile{}
	if prev != nil {
		for _, p := range prev.Profiles {
			prevBy[firestore.NormalizeChainKey(p.Chain)] = p
		}
	}
	for i := range body.Profiles {
		p := &body.Profiles[i]
		old, existed := prevBy[firestore.NormalizeChainKey(p.Chain)]
		if existed && old.InvoiceDiscountPct == p.InvoiceDiscountPct && old.AdditionalDiscountPct == p.AdditionalDiscountPct {
			p.UpdatedAt, p.UpdatedBy = old.UpdatedAt, old.UpdatedBy
			continue
		}
		p.UpdatedBy = c.Email
		p.UpdatedAt = time.Now().UTC()
	}
	doc := &domain.ChainDiscountProfiles{TenantID: c.TenantID, Profiles: body.Profiles, UpdatedBy: c.Email}
	if err := h.repo.SaveChainDiscountProfiles(r.Context(), doc); err != nil {
		writeErr(w, http.StatusInternalServerError, "failed to save chain discounts")
		return
	}
	if h.applier != nil {
		h.applier.SetChainDiscountProfiles(c.TenantID, doc.Profiles)
	}
	h.recordAudit(r, c, describeChainDiscountChange(prevBy, doc.Profiles))
	writeJSON(w, http.StatusOK, wrapChainDiscounts(doc))
}

func describeChainDiscountChange(prev map[string]domain.ChainDiscountProfile, next []domain.ChainDiscountProfile) string {
	var parts []string
	seen := map[string]bool{}
	for _, p := range next {
		k := firestore.NormalizeChainKey(p.Chain)
		seen[k] = true
		old, ok := prev[k]
		switch {
		case !ok:
			parts = append(parts, fmt.Sprintf("added %s invoice=%.2f%% additional=%.2f%%", p.Chain, p.InvoiceDiscountPct, p.AdditionalDiscountPct))
		case old.InvoiceDiscountPct != p.InvoiceDiscountPct || old.AdditionalDiscountPct != p.AdditionalDiscountPct:
			parts = append(parts, fmt.Sprintf("updated %s invoice %.2f%%→%.2f%% additional %.2f%%→%.2f%%", p.Chain, old.InvoiceDiscountPct, p.InvoiceDiscountPct, old.AdditionalDiscountPct, p.AdditionalDiscountPct))
		}
	}
	for k, old := range prev {
		if !seen[k] {
			parts = append(parts, "deleted "+old.Chain)
		}
	}
	if len(parts) == 0 {
		return "no changes"
	}
	return strings.Join(parts, "; ")
}

func (h *ChainDiscountHandler) recordAudit(r *http.Request, c *domain.UserClaims, details string) {
	if h.audit == nil {
		return
	}
	_ = h.audit.SaveAuditLog(r.Context(), &domain.AuditLogEntry{
		TenantID: normalizeAuditTenantID(c.TenantID), UserID: c.UserID, UserEmail: c.Email,
		UserRole: string(c.Role), Action: "chain_discounts_update", Resource: "chain_discount_profiles",
		Details: details, IPAddress: extractRequestIP(r),
	})
}
