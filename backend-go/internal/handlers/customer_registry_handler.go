package handlers

import (
	"context"
	"encoding/json"
	"fmt"
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

// HandleList serves GET /api/v1/customers/registry?status=pending|approved|rejected|live&include_seed=true.
// status=live returns distinct counted Sell-In customers (plus registry aliases with no
// remaining rows, so a merge can be undone) rather than only explicit approvals.
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
	stats := h.liveStats(c.TenantID)
	if status == "live" {
		out := h.listLiveEntries(r.Context(), c.TenantID, reg, stats)
		writeJSON(w, http.StatusOK, map[string]interface{}{"entries": out, "count": len(out)})
		return
	}
	entries := reg.List(r.Context(), c.TenantID, status, r.URL.Query().Get("include_seed") == "true")
	out := make([]registryListEntry, 0, len(entries))
	for _, e := range entries {
		out = append(out, decorateRegistryEntry(e, reg, stats))
	}
	writeJSON(w, http.StatusOK, map[string]interface{}{"entries": out, "count": len(out)})
}

func decorateRegistryEntry(e customers.Entry, reg *customers.Registry, stats map[string]ingestion.CustomerLiveStat) registryListEntry {
	item := registryListEntry{Entry: e}
	if st, ok := stats[e.Key]; ok {
		item.LiveRows = st.Rows
		item.LiveValue = st.Value
		item.LiveChain = st.Chain
		item.LiveFiles = st.Files
	}
	if item.LiveChain == "" && reg != nil {
		item.LiveChain = reg.EntryChain(e)
	}
	return item
}

func (h *CustomerRegistryHandler) listLiveEntries(ctx context.Context, tenantID string, reg *customers.Registry, stats map[string]ingestion.CustomerLiveStat) []registryListEntry {
	byKey := map[string]registryListEntry{}
	if reg != nil {
		for _, e := range reg.List(ctx, tenantID, "", false) {
			item := decorateRegistryEntry(e, reg, stats)
			byKey[e.Key] = item
		}
	}
	for key, st := range stats {
		if key == "" {
			continue
		}
		if item, ok := byKey[key]; ok {
			item.LiveRows = st.Rows
			item.LiveValue = st.Value
			if item.LiveChain == "" {
				item.LiveChain = st.Chain
			}
			if len(item.LiveFiles) == 0 {
				item.LiveFiles = st.Files
			}
			if item.Name == "" {
				item.Name = st.Name
			}
			byKey[key] = item
			continue
		}
		byKey[key] = registryListEntry{
			Entry: customers.Entry{
				Name:   st.Name,
				Key:    key,
				Status: "live",
				Chain:  st.Chain,
			},
			LiveRows:  st.Rows,
			LiveValue: st.Value,
			LiveChain: st.Chain,
			LiveFiles: st.Files,
		}
	}
	out := make([]registryListEntry, 0, len(byKey))
	for _, item := range byKey {
		// Keep counted names, plus registry rows that still need a decision or an undo.
		if item.LiveRows == 0 && item.Status != customers.StatusPending && item.Status != customers.StatusRejected && strings.TrimSpace(item.AliasOf) == "" {
			continue
		}
		out = append(out, item)
	}
	sort.SliceStable(out, func(i, j int) bool {
		return out[i].Name < out[j].Name
	})
	return out
}

// registryListEntry adds counted (in-totals) Sell-In stats to a stored registry entry.
type registryListEntry struct {
	customers.Entry
	LiveRows  int      `json:"live_rows,omitempty"`
	LiveValue float64  `json:"live_value,omitempty"`
	LiveChain string   `json:"live_chain,omitempty"`
	LiveFiles []string `json:"live_files,omitempty"`
}

type sellInLiveStatter interface {
	SellInCustomerLiveStats(tenantID string) map[string]ingestion.CustomerLiveStat
}

func (h *CustomerRegistryHandler) liveStats(tenantID string) map[string]ingestion.CustomerLiveStat {
	s, ok := h.p.(sellInLiveStatter)
	if !ok || s == nil {
		return nil
	}
	return s.SellInCustomerLiveStats(tenantID)
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

// HandleUnmerge serves POST /api/v1/customers/registry/unmerge.
// An approved name that was merged (alias_of set) stays approved under its own
// name and Sell-In files on its chain are re-applied so the rows split again.
// Any other decision goes back to pending and every Sell-In file is re-applied.
func (h *CustomerRegistryHandler) HandleUnmerge(w http.ResponseWriter, r *http.Request) {
	c, ok := tmWriteClaims(w, r)
	if !ok {
		return
	}
	if !dataQualityWriteRoles[c.Role] {
		writeErr(w, http.StatusForbidden, "مش مسموح لدورك تعتمد أو ترفض عملاء")
		return
	}
	var req customerDecisionRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || strings.TrimSpace(req.Name) == "" {
		writeErr(w, http.StatusBadRequest, "اسم العميل مطلوب")
		return
	}
	reg := h.p.CustomerRegistry()
	if reg == nil {
		writeErr(w, http.StatusServiceUnavailable, "سجل العملاء مش متاح")
		return
	}
	key := customers.NormalizeName(req.Name)
	for _, e := range reg.List(r.Context(), c.TenantID, "", false) {
		if e.Key == key && e.Status == customers.StatusApproved && strings.TrimSpace(e.AliasOf) != "" {
			// Keep the customer approved; only undo the merge.
			req.Chain = e.Chain
			req.AliasOf = ""
			h.decideWith(w, r, c, req, customers.StatusApproved, "customer_registry_unmerge")
			return
		}
	}
	h.decideWith(w, r, c, req, customers.StatusPending, "customer_registry_unmerge")
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
	var req customerDecisionRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || strings.TrimSpace(req.Name) == "" {
		writeErr(w, http.StatusBadRequest, "اسم العميل مطلوب")
		return
	}
	h.decideWith(w, r, c, req, status, action)
}

func (h *CustomerRegistryHandler) decideWith(w http.ResponseWriter, r *http.Request, c *domain.UserClaims, req customerDecisionRequest, status, action string) {
	reg := h.p.CustomerRegistry()
	if reg == nil {
		writeErr(w, http.StatusServiceUnavailable, "سجل العملاء مش متاح")
		return
	}
	// Files to re-apply: live quarantined files of this name, plus (when merging or
	// already in totals) the archived files that currently hold its counted rows.
	files, chainSet := collectReapplyScope(reg, r.Context(), c.TenantID, req.Name)
	if st := h.liveStats(c.TenantID); len(st) > 0 {
		for _, name := range []string{req.Name, req.AliasOf} {
			if key := customers.NormalizeName(name); key != "" {
				if s, ok := st[key]; ok {
					for _, f := range s.Files {
						files = appendUnique(files, f)
					}
					if s.Chain != "" {
						chainSet[s.Chain] = true
					}
				}
			}
		}
	}
	if status == customers.StatusApproved && strings.TrimSpace(req.AliasOf) != "" {
		if err := h.ensureLiveCanonicalApproved(r.Context(), c, reg, req); err != nil {
			writeErr(w, http.StatusBadRequest, err.Error())
			return
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
		if entry.Chain != "" {
			// An explicit chain on approval moves the rows there; that chain is rewritten too.
			chainSet[reg.ChainOfName(entry.Name, entry.Chain)] = true
		}
		if aliasChain := reg.EntryChain(*entry); aliasChain != "" {
			chainSet[aliasChain] = true
		}
		chains := make([]string, 0, len(chainSet))
		for ch := range chainSet {
			chains = append(chains, ch)
		}
		sort.Strings(chains)
		if len(files) == 0 && strings.TrimSpace(entry.AliasOf) == "" && len(chains) == 0 {
			break
		}
		if len(chains) == 0 {
			errs = append(errs, "مفيش سلسلة متسجلة لصفوف العميل ده، فمااتعادش أي ملف. ارفع الملف تاني")
			break
		}
		// A merge of already-counted names may have no quarantine files; re-apply
		// every archived Sell-In file on the shared chain so attribution updates
		// without a manual re-upload. Dedup / replacement rules stay as at upload.
		runFiles := files
		if len(files) == 0 && strings.TrimSpace(entry.AliasOf) != "" {
			runFiles = nil
		}
		applied, errs = h.p.ReapplySellInFiles(r.Context(), c.TenantID, runFiles, chains)
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

// ensureLiveCanonicalApproved records the merge target as approved when it is
// already counted in Sell-In (exact-match / seed) but has no registry decision yet.
func (h *CustomerRegistryHandler) ensureLiveCanonicalApproved(ctx context.Context, c *domain.UserClaims, reg *customers.Registry, req customerDecisionRequest) error {
	canKey := customers.NormalizeName(req.AliasOf)
	if canKey == "" {
		return fmt.Errorf("اختار العميل اللي هتندمج عليه")
	}
	for _, e := range reg.List(ctx, c.TenantID, "", false) {
		if e.Key == canKey && e.Status == customers.StatusApproved {
			return nil
		}
	}
	st, ok := h.liveStats(c.TenantID)[canKey]
	if !ok || st.Rows <= 0 {
		return fmt.Errorf("العميل المختار مش متأكد، فمقدرش نضمّ عليه")
	}
	chain := strings.TrimSpace(req.Chain)
	if chain == "" {
		chain = st.Chain
	}
	_, err := reg.Decide(ctx, c.TenantID, req.AliasOf, customers.StatusApproved, chain, "", c.Email)
	return err
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

func collectReapplyScope(reg *customers.Registry, ctx context.Context, tenantID, name string) ([]string, map[string]bool) {
	var files []string
	chainSet := map[string]bool{}
	seenFile := map[string]bool{}
	key := customers.NormalizeName(name)
	for _, e := range reg.List(ctx, tenantID, "", false) {
		if e.Key != key {
			continue
		}
		if c := reg.EntryChain(e); c != "" {
			chainSet[c] = true
		}
		for _, q := range e.Quarantine {
			if !q.Live() || seenFile[q.File] {
				continue
			}
			seenFile[q.File] = true
			files = append(files, q.File)
			if q.Chain != "" {
				chainSet[q.Chain] = true
			} else if e.UploadChain != "" {
				chainSet[reg.ChainOfName(e.Name, e.UploadChain)] = true
			}
		}
	}
	return files, chainSet
}

func appendUnique(files []string, file string) []string {
	file = strings.TrimSpace(file)
	if file == "" {
		return files
	}
	for _, f := range files {
		if f == file {
			return files
		}
	}
	return append(files, file)
}
