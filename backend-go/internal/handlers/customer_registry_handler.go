package handlers

import (
	"context"
	"encoding/json"
	"net/http"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/tashil/data-sharing/backend/internal/domain"
	"github.com/tashil/data-sharing/backend/internal/service/customers"
)

// CustomerRegistryProcessor is what the registry endpoints need from the ingestion processor.
type CustomerRegistryProcessor interface {
	CustomerRegistry() *customers.Registry
	ReapplySellInFiles(ctx context.Context, tenantID string, files []string) ([]string, []string)
	SellInYears(tenantID string) []int
}

type customerAuditSink interface {
	SaveAuditLog(ctx context.Context, e *domain.AuditLogEntry) error
}

// CustomerRegistryHandler serves the Sell-In customer registry (pending names, approve, reject, unmerge)
// and the data-driven year list. Rule: a name is attributed only by exact match or an explicit
// admin decision; suggestions are never applied automatically.
type CustomerRegistryHandler struct {
	p     CustomerRegistryProcessor
	audit customerAuditSink
	now   func() time.Time
}

func NewCustomerRegistryHandler(p CustomerRegistryProcessor, audit customerAuditSink) *CustomerRegistryHandler {
	return &CustomerRegistryHandler{p: p, audit: audit, now: time.Now}
}

// HandleList serves GET /api/v1/customers/registry?status=pending|approved|rejected&include_seed=true.
func (h *CustomerRegistryHandler) HandleList(w http.ResponseWriter, r *http.Request) {
	c, ok := tmClaims(w, r)
	if !ok {
		return
	}
	reg := h.p.CustomerRegistry()
	if reg == nil {
		writeJSON(w, http.StatusOK, map[string]interface{}{"entries": []customers.Entry{}, "count": 0})
		return
	}
	status := strings.TrimSpace(r.URL.Query().Get("status"))
	entries := reg.List(r.Context(), c.TenantID, status, r.URL.Query().Get("include_seed") == "true")
	writeJSON(w, http.StatusOK, map[string]interface{}{"entries": entries, "count": len(entries)})
}

type customerDecisionRequest struct {
	Name    string `json:"name"`
	Chain   string `json:"chain"`
	AliasOf string `json:"alias_of"`
	Reason  string `json:"reason"`
}

// HandleApprove serves POST /api/v1/customers/registry/approve; the name's quarantined files are
// re-applied at once so its rows enter the totals without a re-upload.
func (h *CustomerRegistryHandler) HandleApprove(w http.ResponseWriter, r *http.Request) {
	h.decide(w, r, customers.StatusApproved, "customer_registry_approve")
}

// HandleReject serves POST /api/v1/customers/registry/reject; rows stay quarantined.
func (h *CustomerRegistryHandler) HandleReject(w http.ResponseWriter, r *http.Request) {
	h.decide(w, r, customers.StatusRejected, "customer_registry_reject")
}

// HandleUnmerge serves POST /api/v1/customers/registry/unmerge: an approved name (or alias) goes
// back to pending and every Sell-In file is re-applied, so its rows leave the totals again.
func (h *CustomerRegistryHandler) HandleUnmerge(w http.ResponseWriter, r *http.Request) {
	h.decide(w, r, customers.StatusPending, "customer_registry_unmerge")
}

func (h *CustomerRegistryHandler) decide(w http.ResponseWriter, r *http.Request, status, action string) {
	c, ok := tmClaims(w, r)
	if !ok {
		return
	}
	if !dataQualityWriteRoles[c.Role] {
		writeErr(w, http.StatusForbidden, "مش مسموح لدورك تعتمد أو ترفض عملاء")
		return
	}
	reg := h.p.CustomerRegistry()
	if reg == nil {
		writeErr(w, http.StatusServiceUnavailable, "سجل العملاء مش متاح")
		return
	}
	var req customerDecisionRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || strings.TrimSpace(req.Name) == "" {
		writeErr(w, http.StatusBadRequest, "اسم العميل مطلوب")
		return
	}
	var files []string
	for _, e := range reg.List(r.Context(), c.TenantID, "", false) {
		if e.Key == customers.NormalizeName(req.Name) {
			for _, q := range e.Quarantine {
				files = append(files, q.File)
			}
		}
	}
	entry, err := reg.Decide(r.Context(), c.TenantID, req.Name, status, req.Chain, req.AliasOf, c.Email)
	if err != nil {
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	var applied, errs []string
	switch status {
	case customers.StatusApproved:
		if len(files) > 0 {
			sort.Strings(files)
			applied, errs = h.p.ReapplySellInFiles(r.Context(), c.TenantID, files)
		}
	case customers.StatusPending:
		applied, errs = h.p.ReapplySellInFiles(r.Context(), c.TenantID, nil)
	}
	if h.audit != nil {
		details := "name=" + entry.Name + " status=" + status
		if entry.Chain != "" {
			details += " chain=" + entry.Chain
		}
		if entry.AliasOf != "" {
			details += " alias_of=" + entry.AliasOf
		}
		if req.Reason != "" {
			details += " reason=" + req.Reason
		}
		details += " reapplied=" + strconv.Itoa(len(applied))
		_ = h.audit.SaveAuditLog(r.Context(), &domain.AuditLogEntry{
			TenantID: normalizeAuditTenantID(c.TenantID), UserID: c.UserID, UserEmail: c.Email,
			UserRole: string(c.Role), Action: action, Resource: "sellin_customer_registry",
			Details: details, IPAddress: extractRequestIP(r), Status: "success", CreatedAt: h.now().UTC(),
		})
	}
	writeJSON(w, http.StatusOK, map[string]interface{}{"entry": entry, "reapplied_files": applied, "errors": errs})
}

// HandleYears serves GET /api/v1/sell-in/years: years that have data plus the current year,
// newest first; default_year is the latest year that has data.
func (h *CustomerRegistryHandler) HandleYears(w http.ResponseWriter, r *http.Request) {
	c, ok := tmClaims(w, r)
	if !ok {
		return
	}
	years, def := YearList(h.p.SellInYears(c.TenantID), h.now().Year())
	writeJSON(w, http.StatusOK, map[string]interface{}{"years": years, "default_year": def})
}

// YearList merges data years with the current year (newest first) and picks the latest data year as default.
func YearList(dataYears []int, current int) ([]int, int) {
	set := map[int]bool{current: true}
	def := 0
	for _, y := range dataYears {
		if y < 2000 || y > 2100 {
			continue
		}
		set[y] = true
		if y > def {
			def = y
		}
	}
	if def == 0 {
		def = current
	}
	out := make([]int, 0, len(set))
	for y := range set {
		out = append(out, y)
	}
	sort.Sort(sort.Reverse(sort.IntSlice(out)))
	return out, def
}
