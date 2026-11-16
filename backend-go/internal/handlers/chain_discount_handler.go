package handlers

import (
	"context"
	"encoding/json"
	"errors"
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
	DefaultVATRatePct            float64 `json:"default_vat_rate_pct"`
}

func wrapChainDiscounts(d *domain.ChainDiscountProfiles) chainDiscountResponse {
	return chainDiscountResponse{
		ChainDiscountProfiles:        d,
		DefaultInvoiceDiscountPct:    domain.DefaultChainInvoiceDiscountPct,
		DefaultAdditionalDiscountPct: domain.DefaultChainAdditionalDiscountPct,
		DefaultVATRatePct:            domain.DefaultChainVATRatePct,
	}
}

// chainDiscountGetTimeout bounds the Firestore read so the page gets an answer well inside the
// client's 10s budget.
var chainDiscountGetTimeout = 5 * time.Second

// HandleGet serves GET /api/v1/product-master/chain-discounts.
//
// It is a pure read: it must not call the applier. Applying re-enriches every Sell-In row under the
// analytics client's global write lock and invalidates all cached analytics, so a read would queue
// behind any long-running analytics request. Instances converge through the TTL sync instead
// (bigquery.WithChainDiscountSource), and PUT applies synchronously.
func (h *ChainDiscountHandler) HandleGet(w http.ResponseWriter, r *http.Request) {
	c, ok := tmClaims(w, r)
	if !ok {
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), chainDiscountGetTimeout)
	defer cancel()
	d, err := h.repo.GetChainDiscountProfiles(ctx, c.TenantID)
	if err != nil {
		if errors.Is(err, context.DeadlineExceeded) || ctx.Err() != nil {
			writeErr(w, http.StatusGatewayTimeout, "chain discounts store timed out")
			return
		}
		writeErr(w, http.StatusInternalServerError, "failed to load chain discounts")
		return
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
		if existed && sameChainTerms(old, *p) {
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

func vatLabel(p domain.ChainDiscountProfile) string {
	if p.VATRatePct == nil {
		return "default"
	}
	return fmt.Sprintf("%.2f%%", *p.VATRatePct)
}

func sameChainTerms(a, b domain.ChainDiscountProfile) bool {
	if a.InvoiceDiscountPct != b.InvoiceDiscountPct || a.AdditionalDiscountPct != b.AdditionalDiscountPct {
		return false
	}
	if (a.VATRatePct == nil) != (b.VATRatePct == nil) {
		return false
	}
	return a.VATRatePct == nil || *a.VATRatePct == *b.VATRatePct
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
			parts = append(parts, fmt.Sprintf("added %s invoice=%.2f%% additional=%.2f%% vat=%s", p.Chain, p.InvoiceDiscountPct, p.AdditionalDiscountPct, vatLabel(p)))
		case !sameChainTerms(old, p):
			parts = append(parts, fmt.Sprintf("updated %s invoice %.2f%%→%.2f%% additional %.2f%%→%.2f%% vat %s→%s", p.Chain, old.InvoiceDiscountPct, p.InvoiceDiscountPct, old.AdditionalDiscountPct, p.AdditionalDiscountPct, vatLabel(old), vatLabel(p)))
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
