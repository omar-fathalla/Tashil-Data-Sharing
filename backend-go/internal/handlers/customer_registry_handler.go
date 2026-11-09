package handlers

import (
	"context"
	"encoding/json"
	"log"
	"net/http"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/tashil/data-sharing/backend/internal/domain"
	"github.com/tashil/data-sharing/backend/internal/service/customers"
	"github.com/tashil/data-sharing/backend/internal/service/ingestion"
)

// CustomerRegistryProcessor is what the registry endpoints need from the ingestion processor.
type CustomerRegistryProcessor interface {
	CustomerRegistry() *customers.Registry
	ReapplySellInFiles(ctx context.Context, tenantID string, files []string, chains []string) ([]ingestion.ReapplyResult, []string)
	SellInYears(tenantID string) []int
	SellOutMonths(tenantID string, year int) []int
}

type customerAuditSink interface {
	SaveAuditLog(ctx context.Context, e *domain.AuditLogEntry) error
}

// SellOutMonthsQuerier loads distinct Sell-Out months from durable storage (BigQuery).
type SellOutMonthsQuerier interface {
	QuerySellOutMonths(ctx context.Context, tenantID string, year int) ([]int, error)
}

// CustomerRegistryHandler serves the Sell-In customer registry (pending names, approve, reject, unmerge)
// and the data-driven year list. Rule: a name is attributed only by exact match or an explicit
// admin decision; suggestions are never applied automatically.
type CustomerRegistryHandler struct {
	p      CustomerRegistryProcessor
	audit  customerAuditSink
	months SellOutMonthsQuerier
	now    func() time.Time
}

func NewCustomerRegistryHandler(p CustomerRegistryProcessor, audit customerAuditSink) *CustomerRegistryHandler {
	return &CustomerRegistryHandler{p: p, audit: audit, now: time.Now}
}

// WithSellOutMonthsQuerier prefers durable BigQuery months when memory is short/stale.
func (h *CustomerRegistryHandler) WithSellOutMonthsQuerier(q SellOutMonthsQuerier) *CustomerRegistryHandler {
	h.months = q
	return h
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
	c, ok := tmWriteClaims(w, r)
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
	// Files to re-apply: the name's quarantined files that were not fully superseded by a later
	// confirmed upload. Chains: where those rows were held (re-apply touches only these chains).
	var files []string
	chainSet := map[string]bool{}
	seenFile := map[string]bool{}
	for _, e := range reg.List(r.Context(), c.TenantID, "", false) {
		if e.Key == customers.NormalizeName(req.Name) {
			for _, q := range e.Quarantine {
				if !q.Live() || seenFile[q.File] {
					continue
				}
				seenFile[q.File] = true
				files = append(files, q.File)
				if q.Chain != "" {
					chainSet[q.Chain] = true
				} else if e.UploadChain != "" {
					// Stats recorded before FileStat.Chain existed: the upload chain + chain rules.
					chainSet[reg.ChainOfName(e.Name, e.UploadChain)] = true
				}
			}
		}
	}
	entry, err := reg.Decide(r.Context(), c.TenantID, req.Name, status, req.Chain, req.AliasOf, c.Email)
	if err != nil {
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	var applied []ingestion.ReapplyResult
	var errs []string
	switch status {
	case customers.StatusApproved:
		if len(files) > 0 {
			if entry.Chain != "" {
				// An explicit chain on approval moves the rows there; that chain is rewritten too.
				chainSet[reg.ChainOfName(entry.Name, entry.Chain)] = true
			}
			chains := make([]string, 0, len(chainSet))
			for ch := range chainSet {
				chains = append(chains, ch)
			}
			sort.Strings(chains)
			if len(chains) == 0 {
				errs = append(errs, "مفيش سلسلة متسجلة لصفوف العميل ده، فمااتعادش أي ملف. ارفع الملف تاني")
				break
			}
			// Order: original upload order (ReapplySellInFiles sorts by uploaded_at), not by name.
			applied, errs = h.p.ReapplySellInFiles(r.Context(), c.TenantID, files, chains)
		}
	case customers.StatusPending:
		applied, errs = h.p.ReapplySellInFiles(r.Context(), c.TenantID, nil, nil)
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
		for _, a := range applied {
			details += " file=" + a.File + " batch=" + a.BatchID
		}
		_ = h.audit.SaveAuditLog(r.Context(), &domain.AuditLogEntry{
			TenantID: normalizeAuditTenantID(c.TenantID), UserID: c.UserID, UserEmail: c.Email,
			UserRole: string(c.Role), Action: action, Resource: "sellin_customer_registry",
			Details: details, IPAddress: extractRequestIP(r), Status: "success", CreatedAt: h.now().UTC(),
		})
	}
	names := make([]string, 0, len(applied))
	for _, a := range applied {
		names = append(names, a.File)
	}
	writeJSON(w, http.StatusOK, map[string]interface{}{"entry": entry, "reapplied_files": names, "reapplied": applied, "errors": errs})
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

// HandleMonths serves GET /api/v1/sell-out/months?year=YYYY: distinct months (1..12) that have
// Sell-Out facts for the year. month=0 on analytics filters means the whole year — this list is
// what the competitor comparison picker uses so it grows as uploads add months.
// Prefers durable BigQuery months when available so a short in-memory window (e.g. Jan–Apr seed)
// cannot truncate the picker while uploaded Sell-Out already has later months.
func (h *CustomerRegistryHandler) HandleMonths(w http.ResponseWriter, r *http.Request) {
	c, ok := tmClaims(w, r)
	if !ok {
		return
	}
	year, _ := strconv.Atoi(strings.TrimSpace(r.URL.Query().Get("year")))
	if year <= 0 {
		year = h.now().Year()
	}
	months := MonthList(h.p.SellOutMonths(c.TenantID, year))
	if h.months != nil {
		ctx, cancel := context.WithTimeout(r.Context(), 8*time.Second)
		defer cancel()
		if bqMonths, err := h.months.QuerySellOutMonths(ctx, c.TenantID, year); err == nil {
			months = MonthList(mergeMonthLists(months, bqMonths))
		} else {
			log.Printf("WARN [sell-out/months] BigQuery path failed, using memory: %v", err)
		}
	}
	writeJSON(w, http.StatusOK, map[string]interface{}{"year": year, "months": months})
}

// mergeMonthLists unions two month lists (1..12).
func mergeMonthLists(a, b []int) []int {
	set := map[int]bool{}
	for _, m := range a {
		if m >= 1 && m <= 12 {
			set[m] = true
		}
	}
	for _, m := range b {
		if m >= 1 && m <= 12 {
			set[m] = true
		}
	}
	out := make([]int, 0, len(set))
	for m := range set {
		out = append(out, m)
	}
	sort.Ints(out)
	return out
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

// MonthList keeps valid calendar months (1..12), sorted ascending. Empty input stays empty
// (callers fall back to series-derived months on the client).
func MonthList(months []int) []int {
	set := map[int]bool{}
	for _, m := range months {
		if m >= 1 && m <= 12 {
			set[m] = true
		}
	}
	out := make([]int, 0, len(set))
	for m := range set {
		out = append(out, m)
	}
	sort.Ints(out)
	return out
}
