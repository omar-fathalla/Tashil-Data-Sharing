package handlers

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"net/http"
	"strings"
	"sync"
	"time"

	"github.com/tashil/data-sharing/backend/internal/domain"
	"github.com/tashil/data-sharing/backend/internal/service/firestore"
)

// ChainDiscountApplier receives saved profiles so CPFR cost uses them immediately.
type ChainDiscountApplier interface {
	SetChainDiscountProfiles(tenantID string, profiles []domain.ChainDiscountProfile)
}

// KnownChainLister lists chains that already have counted Sell-In / Sell-Out data.
// Implementations must not take the analytics write lock; KnownChainsWithData on the BigQuery
// client is the production one.
type KnownChainLister interface {
	KnownChainsWithData(ctx context.Context, tenantID string) ([]domain.KnownChain, error)
}

// ChainDiscountHandler serves per-tenant chain discount profiles (Product Master page).
type ChainDiscountHandler struct {
	repo    firestore.ChainDiscountRepository
	audit   firestore.Repository
	applier ChainDiscountApplier
	chains  KnownChainLister

	apply chainApplyQueue
}

// NewChainDiscountHandler constructs the handler. audit and applier may be nil.
func NewChainDiscountHandler(repo firestore.ChainDiscountRepository, audit firestore.Repository, applier ChainDiscountApplier) *ChainDiscountHandler {
	return &ChainDiscountHandler{repo: repo, audit: audit, applier: applier}
}

// WithKnownChains sets the read-only source for GET /api/v1/product-master/chains.
func (h *ChainDiscountHandler) WithKnownChains(l KnownChainLister) *ChainDiscountHandler {
	h.chains = l
	return h
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
// client's 20s GET budget.
var chainDiscountGetTimeout = 5 * time.Second

// knownChainsGetTimeout bounds the in-memory chain scan. The scan never waits on the analytics
// write lock; this cap only covers the case where no cached snapshot exists yet and the lock stays
// busy for the whole wait.
var knownChainsGetTimeout = 5 * time.Second

// HandleGet serves GET /api/v1/product-master/chain-discounts.
//
// It is a pure read: it must not call the applier. Applying re-enriches every Sell-In row under the
// analytics client's global write lock and invalidates all cached analytics, so a read would queue
// behind any long-running analytics request. Instances converge through the TTL sync instead
// (bigquery.WithChainDiscountSource), and PUT applies in the background (see chainApplyQueue).
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

// HandleListChains serves GET /api/v1/product-master/chains.
//
// Read-only. It does not call the applier (that takes the analytics write lock and re-enriches every
// Sell-In row). The list is chains that already have counted data; quarantined unknown customers are
// not in that set. Each item's key/name is the normalized chain Sell-In and Sell-Out enrichment match on.
func (h *ChainDiscountHandler) HandleListChains(w http.ResponseWriter, r *http.Request) {
	c, ok := tmClaims(w, r)
	if !ok {
		return
	}
	if h.chains == nil {
		writeErr(w, http.StatusServiceUnavailable, "known chains are unavailable")
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), knownChainsGetTimeout)
	defer cancel()
	chains, err := h.chains.KnownChainsWithData(ctx, c.TenantID)
	if err != nil {
		if errors.Is(err, context.DeadlineExceeded) || errors.Is(err, context.Canceled) || ctx.Err() != nil {
			writeErr(w, http.StatusGatewayTimeout, "known chains lookup timed out")
			return
		}
		writeErr(w, http.StatusInternalServerError, "failed to load known chains")
		return
	}
	if chains == nil {
		chains = []domain.KnownChain{}
	}
	writeJSON(w, http.StatusOK, struct {
		Chains []domain.KnownChain `json:"chains"`
	}{Chains: chains})
}

// chainApplyQueue hands saved profiles to the applier on one background worker. The applier takes
// the analytics client's locks and can run for tens of seconds, so PUT answers as soon as Firestore
// has the list. A newer save for a tenant replaces a still-pending one (latest list wins).
type chainApplyQueue struct {
	mu      sync.Mutex
	pending map[string][]domain.ChainDiscountProfile
	order   []string
	running bool
	done    chan struct{} // closed when the worker drains the queue; replaced per run
}

func (h *ChainDiscountHandler) enqueueApply(tenantID string, profiles []domain.ChainDiscountProfile) {
	if h.applier == nil {
		return
	}
	q := &h.apply
	q.mu.Lock()
	defer q.mu.Unlock()
	if q.pending == nil {
		q.pending = map[string][]domain.ChainDiscountProfile{}
	}
	if _, queued := q.pending[tenantID]; !queued {
		q.order = append(q.order, tenantID)
	}
	q.pending[tenantID] = append([]domain.ChainDiscountProfile(nil), profiles...)
	if q.running {
		return
	}
	q.running = true
	q.done = make(chan struct{})
	go h.runApplyWorker(q.done)
}

func (h *ChainDiscountHandler) runApplyWorker(done chan struct{}) {
	q := &h.apply
	for {
		q.mu.Lock()
		if len(q.order) == 0 {
			q.running = false
			q.mu.Unlock()
			close(done)
			return
		}
		tenant := q.order[0]
		q.order = q.order[1:]
		profiles := q.pending[tenant]
		delete(q.pending, tenant)
		q.mu.Unlock()
		h.applyOne(tenant, profiles)
	}
}

func (h *ChainDiscountHandler) applyOne(tenant string, profiles []domain.ChainDiscountProfile) {
	defer func() {
		if r := recover(); r != nil {
			log.Printf("ERROR [chain-discounts] tenant=%s background apply panicked: %v", tenant, r)
		}
	}()
	start := time.Now()
	h.applier.SetChainDiscountProfiles(tenant, profiles)
	log.Printf("[chain-discounts] tenant=%s applied %d profile(s) in %s", tenant, len(profiles), time.Since(start).Round(time.Millisecond))
}

// waitApplyIdle blocks until the background worker has drained the queue (tests, graceful stop).
func (h *ChainDiscountHandler) waitApplyIdle(timeout time.Duration) bool {
	q := &h.apply
	q.mu.Lock()
	done := q.done
	running := q.running
	q.mu.Unlock()
	if !running {
		return true
	}
	select {
	case <-done:
		return true
	case <-time.After(timeout):
		return false
	}
}

// HandlePut serves PUT /api/v1/product-master/chain-discounts with body {"profiles":[...]}:
// it replaces the tenant's full list (add / edit / delete are all done by sending the new list).
// It returns once the list is saved; applying it to the analytics client happens in the background.
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
	h.enqueueApply(c.TenantID, doc.Profiles)
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
