package handlers

import (
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"net/http"
	"sort"
	"strings"
	"sync"
	"time"

	"github.com/tashil/data-sharing/backend/internal/domain"
	"github.com/tashil/data-sharing/backend/internal/service/bigquery"
	"github.com/tashil/data-sharing/backend/internal/service/competitorsuggest"
	"github.com/tashil/data-sharing/backend/internal/service/firestore"
)

// Owner-only for run / sku / approve / reject (company manager + super admin).
var competitorSuggestOwnerRoles = map[domain.UserRole]bool{
	domain.RoleSuperAdmin:  true,
	domain.RoleVendorAdmin: true,
}

const (
	competitorSuggestDefaultBatch = 10
	competitorSuggestMaxBatch     = 10 // hard cap matches owner batch-size spec
	competitorSuggestMinInterval  = 30 * time.Second
	competitorSuggestSkuInterval  = 10 * time.Second // per-SKU generate (cache hits skip)
	// HOLD: AI picks must NOT feed Compare KPI averages until owner confirms.
	competitorSuggestIncludeInKPIAverages = false
)

// CompetitiveCatalogSource supplies Sell-Out barcode catalogue for suggestions.
type CompetitiveCatalogSource interface {
	CompetitiveMonthly(tenantID string, filter bigquery.RecordFilter) bigquery.CompetitiveMonthlyResult
}

// CompetitorSuggestionsHandler serves the AI competitor-suggestion quarantine APIs.
// Pending suggestions NEVER feed Compare KPIs or mappings until owner approve
// (and KPI averages stay owner-pinned while competitorSuggestIncludeInKPIAverages is false).
type CompetitorSuggestionsHandler struct {
	repo    firestore.CompetitorSkuRepository
	audit   firestore.Repository
	catalog CompetitiveCatalogSource
	ranker  competitorsuggest.Ranker
	eq      competitorsuggest.CategoryEquivalence
	rateMu  sync.Mutex
	lastRun map[string]time.Time // tenant|chain → last batch run
	lastSku map[string]time.Time // tenant|chain|barcode → last generate
}

// NewCompetitorSuggestionsHandler wires quarantine + ranking. ranker may be a mock.
func NewCompetitorSuggestionsHandler(
	repo firestore.CompetitorSkuRepository,
	audit firestore.Repository,
	catalog CompetitiveCatalogSource,
	ranker competitorsuggest.Ranker,
) *CompetitorSuggestionsHandler {
	if ranker == nil {
		ranker = &competitorsuggest.GeminiRanker{UseMock: true}
	}
	return &CompetitorSuggestionsHandler{
		repo:    repo,
		audit:   audit,
		catalog: catalog,
		ranker:  ranker,
		eq:      competitorsuggest.DefaultCategoryEquivalence(),
		lastRun: make(map[string]time.Time),
		lastSku: make(map[string]time.Time),
	}
}

type suggestRunPayload struct {
	Chain   string   `json:"chain"`
	OwnSKUs []string `json:"own_skus"`
	Limit   int      `json:"limit"`
	Year    int      `json:"year"`
}

type suggestSkuPayload struct {
	Barcode string `json:"barcode"`
	Chain   string `json:"chain"`
	Year    int    `json:"year"`
}

type suggestDecidePayload struct {
	ID string `json:"id"`
}

type skipInfo struct {
	Barcode string `json:"barcode"`
	Reason  string `json:"reason_ar"`
}

func (h *CompetitorSuggestionsHandler) ownerClaims(w http.ResponseWriter, r *http.Request) (*domain.UserClaims, bool) {
	c, ok := tmWriteClaims(w, r)
	if !ok {
		return nil, false
	}
	if !competitorSuggestOwnerRoles[c.Role] {
		writeErr(w, http.StatusForbidden, "owner-only: super_admin or vendor_admin required")
		return nil, false
	}
	return c, true
}

func (h *CompetitorSuggestionsHandler) recordAudit(r *http.Request, c *domain.UserClaims, action, details string) {
	if h.audit == nil {
		return
	}
	_ = h.audit.SaveAuditLog(r.Context(), &domain.AuditLogEntry{
		TenantID: normalizeAuditTenantID(c.TenantID), UserID: c.UserID, UserEmail: c.Email,
		UserRole: string(c.Role), Action: action, Resource: "competitor_suggestion",
		Details: details, IPAddress: extractRequestIP(r),
	})
}

// HandleListSuggestions serves GET /api/v1/competitors/suggestions?chain=&status=&own_barcode=
func (h *CompetitorSuggestionsHandler) HandleListSuggestions(w http.ResponseWriter, r *http.Request) {
	c, ok := tmClaims(w, r)
	if !ok {
		return
	}
	q := r.URL.Query()
	chain := q.Get("chain")
	if k := kamChain(c); k != "" {
		chain = k
	}
	items, err := h.repo.ListCompetitorSuggestions(r.Context(), c.TenantID, domain.CompetitorSuggestionFilter{
		Chain: chain, Status: q.Get("status"), OwnBarcode: q.Get("own_barcode"),
	})
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "failed to list competitor suggestions")
		return
	}
	writeJSON(w, http.StatusOK, map[string]interface{}{
		"suggestions":                  items,
		"count":                        len(items),
		"include_in_kpi_averages":      competitorSuggestIncludeInKPIAverages,
		"pending_category_equivalence": competitorsuggest.PendingCategoryEquivalencePairs,
	})
}

// HandleSuggestForSku serves POST /api/v1/competitors/suggestions/sku (owner-only).
// Returns cached pending suggestions for the own barcode, or generates up to 3.
// Viewing/compare does not require approve; mappings still require explicit approve (batch tab).
func (h *CompetitorSuggestionsHandler) HandleSuggestForSku(w http.ResponseWriter, r *http.Request) {
	c, ok := h.ownerClaims(w, r)
	if !ok {
		return
	}
	var p suggestSkuPayload
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 1<<20)).Decode(&p); err != nil {
		writeErr(w, http.StatusBadRequest, "invalid JSON body")
		return
	}
	p.Barcode = strings.TrimSpace(p.Barcode)
	p.Chain = strings.TrimSpace(p.Chain)
	if p.Barcode == "" {
		writeErr(w, http.StatusBadRequest, "barcode is required")
		return
	}
	if p.Chain == "" {
		writeErr(w, http.StatusBadRequest, "chain is required")
		return
	}
	if k := kamChain(c); k != "" && !strings.EqualFold(k, p.Chain) {
		writeErr(w, http.StatusForbidden, "chain KAM can only request suggestions for the assigned chain")
		return
	}
	year := p.Year
	if year <= 0 {
		year = time.Now().Year()
	}

	// Cache hit: return pending rows without regenerating or rate-limiting.
	cached, err := h.repo.ListCompetitorSuggestions(r.Context(), c.TenantID, domain.CompetitorSuggestionFilter{
		Chain: p.Chain, Status: domain.CompetitorSuggestionPending, OwnBarcode: p.Barcode,
	})
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "failed to load cached suggestions")
		return
	}
	if len(cached) > 0 {
		writeJSON(w, http.StatusOK, map[string]interface{}{
			"suggestions":             cached,
			"count":                   len(cached),
			"cached":                  true,
			"barcode":                 p.Barcode,
			"chain":                   p.Chain,
			"include_in_kpi_averages": competitorSuggestIncludeInKPIAverages,
		})
		return
	}

	rateKey := strings.ToLower(normalizeAuditTenantID(c.TenantID) + "|" + p.Chain + "|" + p.Barcode)
	h.rateMu.Lock()
	if last, ok := h.lastSku[rateKey]; ok && time.Since(last) < competitorSuggestSkuInterval {
		h.rateMu.Unlock()
		writeErr(w, http.StatusTooManyRequests, "تم تجاوز حد الطلبات — انتظر قليلاً قبل إعادة توليد اقتراحات هذا الصنف")
		return
	}
	h.lastSku[rateKey] = time.Now()
	h.rateMu.Unlock()

	if h.catalog == nil {
		writeErr(w, http.StatusServiceUnavailable, "كتالوج المنافسة غير متاح حالياً")
		return
	}

	ctx := suggestContext{
		tenantID: c.TenantID,
		chain:    p.Chain,
		year:     year,
		email:    c.Email,
		// On-demand view: still suggest alongside owner pins; exclude already-mapped pairs.
		skipOwnWithAnyMapping: false,
	}
	pool, err := h.loadSuggestPools(r, c.TenantID, p.Chain, year)
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "تعذر تحميل بيانات المنافسة")
		return
	}

	var own *competitorsuggest.SkuCandidate
	for i := range pool.own {
		if normBarcode(pool.own[i].Barcode) == normBarcode(p.Barcode) {
			o := pool.own[i]
			own = &o
			break
		}
	}
	if own == nil {
		writeErr(w, http.StatusNotFound, "الصنف غير موجود في بيانات البيع لهذا التسلسل")
		return
	}

	created, skip, usage, genErr := h.generateForOwn(r, ctx, pool, *own)
	if genErr != nil {
		log.Printf("[competitor-suggest] sku generate failed own=%s: %v", p.Barcode, genErr)
		writeErr(w, http.StatusBadGateway, "تعذر ترتيب المرشحين عبر الذكاء الاصطناعي")
		return
	}

	h.recordAudit(r, c, "SUGGEST_COMPETITOR_SKU",
		fmt.Sprintf("chain=%s barcode=%s created=%d cached=false tokens=%d/%d skip=%s",
			p.Chain, p.Barcode, len(created), usage.PromptTokens, usage.CompletionTokens, skip))

	writeJSON(w, http.StatusOK, map[string]interface{}{
		"suggestions":             created,
		"count":                   len(created),
		"cached":                  false,
		"barcode":                 p.Barcode,
		"chain":                   p.Chain,
		"skipped_reason_ar":       skip,
		"prompt_tokens":           usage.PromptTokens,
		"completion_tokens":       usage.CompletionTokens,
		"include_in_kpi_averages": competitorSuggestIncludeInKPIAverages,
	})
}

// HandleRunSuggestions serves POST /api/v1/competitors/suggestions/run (owner-only).
// Optional batch tab — manual trigger only. Idempotent per own+competitor+chain.
func (h *CompetitorSuggestionsHandler) HandleRunSuggestions(w http.ResponseWriter, r *http.Request) {
	c, ok := h.ownerClaims(w, r)
	if !ok {
		return
	}
	var p suggestRunPayload
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 1<<20)).Decode(&p); err != nil {
		writeErr(w, http.StatusBadRequest, "invalid JSON body")
		return
	}
	p.Chain = strings.TrimSpace(p.Chain)
	if p.Chain == "" {
		writeErr(w, http.StatusBadRequest, "chain is required")
		return
	}
	if k := kamChain(c); k != "" && !strings.EqualFold(k, p.Chain) {
		writeErr(w, http.StatusForbidden, "chain KAM can only run suggestions for the assigned chain")
		return
	}
	limit := p.Limit
	if limit <= 0 {
		limit = competitorSuggestDefaultBatch
	}
	if limit > competitorSuggestMaxBatch {
		limit = competitorSuggestMaxBatch
	}
	year := p.Year
	if year <= 0 {
		year = time.Now().Year()
	}

	rateKey := strings.ToLower(normalizeAuditTenantID(c.TenantID) + "|" + p.Chain)
	h.rateMu.Lock()
	if last, ok := h.lastRun[rateKey]; ok && time.Since(last) < competitorSuggestMinInterval {
		h.rateMu.Unlock()
		writeErr(w, http.StatusTooManyRequests, "rate limit: wait before re-running suggestions for this chain")
		return
	}
	h.lastRun[rateKey] = time.Now()
	h.rateMu.Unlock()

	if h.catalog == nil {
		writeErr(w, http.StatusServiceUnavailable, "competitive catalog unavailable")
		return
	}

	pool, err := h.loadSuggestPools(r, c.TenantID, p.Chain, year)
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "failed to load competitive catalog")
		return
	}

	ownFilter := map[string]bool{}
	for _, bc := range p.OwnSKUs {
		bc = strings.TrimSpace(bc)
		if bc != "" {
			ownFilter[normBarcode(bc)] = true
		}
	}

	ctx := suggestContext{
		tenantID:              c.TenantID,
		chain:                 p.Chain,
		year:                  year,
		email:                 c.Email,
		skipOwnWithAnyMapping: true, // batch keeps prior behaviour
	}

	created := make([]domain.CompetitorSuggestion, 0)
	skipped := make([]skipInfo, 0)
	var promptTok, completionTok int
	processed := 0
	rankAttempts := 0
	rankFailures := 0

	for _, own := range pool.own {
		if processed >= limit {
			break
		}
		if len(ownFilter) > 0 && !ownFilter[normBarcode(own.Barcode)] {
			continue
		}
		rows, skip, usage, genErr := h.generateForOwn(r, ctx, pool, own)
		promptTok += usage.PromptTokens
		completionTok += usage.CompletionTokens
		if genErr != nil {
			// Rank was attempted and failed (Gemini key/header/model errors).
			rankAttempts++
			rankFailures++
			log.Printf("[competitor-suggest] rank failed own=%s: %v", own.Barcode, genErr)
			skipped = append(skipped, skipInfo{Barcode: own.Barcode, Reason: "تعذر ترتيب المرشحين"})
			processed++
			continue
		}
		// Match prior batch semantics: approved mapping / missing category do not
		// consume a batch slot; empty-candidate skips do. Neither counts as a rank attempt.
		if skip == "يوجد تعيين معتمد مسبقاً" || skip == "فئة مفقودة في البيانات" {
			skipped = append(skipped, skipInfo{Barcode: own.Barcode, Reason: skip})
			continue
		}
		if skip != "" && len(rows) == 0 {
			skipped = append(skipped, skipInfo{Barcode: own.Barcode, Reason: skip})
			processed++
			continue
		}
		rankAttempts++
		created = append(created, rows...)
		processed++
	}

	log.Printf("[competitor-suggest] run tenant=%s chain=%s processed=%d created=%d prompt_tokens=%d completion_tokens=%d rank_fail=%d/%d",
		normalizeAuditTenantID(c.TenantID), p.Chain, processed, len(created), promptTok, completionTok, rankFailures, rankAttempts)
	h.recordAudit(r, c, "RUN_COMPETITOR_SUGGESTIONS",
		fmt.Sprintf("chain=%s processed=%d created=%d tokens=%d/%d rank_fail=%d/%d", p.Chain, processed, len(created), promptTok, completionTok, rankFailures, rankAttempts))

	reasonCounts := map[string]int{}
	for _, s := range skipped {
		reasonCounts[s.Reason]++
	}
	payload := map[string]interface{}{
		"suggestions":                  created,
		"created_count":                len(created),
		"processed_own":                processed,
		"skipped":                      skipped,
		"skipped_reason_counts":        reasonCounts,
		"rank_attempts":                rankAttempts,
		"rank_failures":                rankFailures,
		"prompt_tokens":                promptTok,
		"completion_tokens":            completionTok,
		"limit":                        limit,
		"include_in_kpi_averages":      competitorSuggestIncludeInKPIAverages,
		"pending_category_equivalence": competitorsuggest.PendingCategoryEquivalencePairs,
	}
	// Prod silence: Gemini key/header failures yielded HTTP 200 + created_count=0.
	// Surface a clear Arabic error when every ranking attempt failed.
	if len(created) == 0 && rankAttempts > 0 && rankFailures == rankAttempts {
		summary := fmt.Sprintf("فشل ترتيب كل الأصناف (%d). %s",
			rankFailures, formatSkippedReasonSummary(reasonCounts))
		payload["error"] = summary
		payload["summary_ar"] = summary
		writeJSON(w, http.StatusBadGateway, payload)
		return
	}
	writeJSON(w, http.StatusOK, payload)
}

func formatSkippedReasonSummary(counts map[string]int) string {
	if len(counts) == 0 {
		return ""
	}
	parts := make([]string, 0, len(counts))
	for reason, n := range counts {
		parts = append(parts, fmt.Sprintf("%s: %d", reason, n))
	}
	sort.Strings(parts)
	return strings.Join(parts, "؛ ")
}

// HandleApproveSuggestion serves POST /api/v1/competitors/suggestions/approve
// Writes an owner-approved competitor_mappings row. Never auto-approves.
func (h *CompetitorSuggestionsHandler) HandleApproveSuggestion(w http.ResponseWriter, r *http.Request) {
	c, ok := h.ownerClaims(w, r)
	if !ok {
		return
	}
	var p suggestDecidePayload
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 1<<20)).Decode(&p); err != nil || strings.TrimSpace(p.ID) == "" {
		writeErr(w, http.StatusBadRequest, "id is required")
		return
	}
	s, err := h.repo.UpdateCompetitorSuggestionStatus(r.Context(), c.TenantID, p.ID, domain.CompetitorSuggestionApproved, c.Email)
	if err != nil {
		writeSuggestDecideErr(w, err)
		return
	}
	m := &domain.CompetitorMapping{
		TenantID: c.TenantID, OwnBarcode: s.OwnBarcode, CompetitorBarcode: s.CompetitorBarcode,
		CompetitorSkuName: s.CompetitorSkuName, CompetitorBrand: s.CompetitorBrand,
		CompetitorSupplier: s.CompetitorSupplier, RetailerChain: s.RetailerChain, CreatedBy: c.Email,
	}
	if err := h.repo.SaveCompetitorMapping(r.Context(), m); err != nil {
		writeErr(w, http.StatusInternalServerError, "failed to save competitor mapping")
		return
	}
	h.recordAudit(r, c, "APPROVE_COMPETITOR_SUGGESTION",
		fmt.Sprintf("%s own=%s competitor=%s chain=%s", s.ID, s.OwnBarcode, s.CompetitorBarcode, s.RetailerChain))
	writeJSON(w, http.StatusOK, map[string]interface{}{"suggestion": s, "mapping": m})
}

// HandleRejectSuggestion serves POST /api/v1/competitors/suggestions/reject
// Remembers the pair so it is not re-suggested.
func (h *CompetitorSuggestionsHandler) HandleRejectSuggestion(w http.ResponseWriter, r *http.Request) {
	c, ok := h.ownerClaims(w, r)
	if !ok {
		return
	}
	var p suggestDecidePayload
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 1<<20)).Decode(&p); err != nil || strings.TrimSpace(p.ID) == "" {
		writeErr(w, http.StatusBadRequest, "id is required")
		return
	}
	s, err := h.repo.UpdateCompetitorSuggestionStatus(r.Context(), c.TenantID, p.ID, domain.CompetitorSuggestionRejected, c.Email)
	if err != nil {
		writeSuggestDecideErr(w, err)
		return
	}
	h.recordAudit(r, c, "REJECT_COMPETITOR_SUGGESTION",
		fmt.Sprintf("%s own=%s competitor=%s chain=%s", s.ID, s.OwnBarcode, s.CompetitorBarcode, s.RetailerChain))
	writeJSON(w, http.StatusOK, map[string]interface{}{"suggestion": s})
}

func writeSuggestDecideErr(w http.ResponseWriter, err error) {
	switch {
	case errors.Is(err, firestore.ErrCompetitorSuggestionNotFound):
		writeErr(w, http.StatusNotFound, "suggestion not found")
	case strings.Contains(err.Error(), "already decided"):
		writeErr(w, http.StatusConflict, err.Error())
	case strings.Contains(err.Error(), "status must be"):
		writeErr(w, http.StatusBadRequest, err.Error())
	default:
		writeErr(w, http.StatusInternalServerError, "failed to update suggestion")
	}
}

type suggestContext struct {
	tenantID              string
	chain                 string
	year                  int
	email                 string
	skipOwnWithAnyMapping bool
}

type suggestPools struct {
	own           []competitorsuggest.SkuCandidate
	comp          []competitorsuggest.SkuCandidate
	mappedPairs   map[string]bool // rejectedPairKey style for own|comp|chain already mapped
	ownHasMapping map[string]bool
	rejectedPairs map[string]bool
}

func (h *CompetitorSuggestionsHandler) loadSuggestPools(r *http.Request, tenantID, chain string, year int) (suggestPools, error) {
	start, end := bigquery.CompetitiveMonthlyYearWindow(year)
	res := h.catalog.CompetitiveMonthly(tenantID, bigquery.RecordFilter{
		RetailerChain: chain,
		Supplier:      "all_market",
		StartDate:     start,
		EndDate:       end,
	})
	ownPool, compPool := splitCatalog(res)
	customs, _ := h.repo.ListCustomCompetitorSkus(r.Context(), tenantID, domain.CustomCompetitorSkuFilter{Chain: chain})
	compPool = append(compPool, customAsCandidates(customs)...)

	mappings, _ := h.repo.ListCompetitorMappings(r.Context(), tenantID, domain.CompetitorMappingFilter{Chain: chain})
	ownHas := map[string]bool{}
	mappedPairs := map[string]bool{}
	for _, m := range mappings {
		ownHas[normBarcode(m.OwnBarcode)] = true
		mappedPairs[firestore.RejectedPairKey(m.OwnBarcode, m.CompetitorBarcode, chain)] = true
	}
	existing, _ := h.repo.ListCompetitorSuggestions(r.Context(), tenantID, domain.CompetitorSuggestionFilter{Chain: chain})
	rejected := map[string]bool{}
	for _, s := range existing {
		if s.Status == domain.CompetitorSuggestionRejected {
			rejected[firestore.RejectedPairKey(s.OwnBarcode, s.CompetitorBarcode, s.RetailerChain)] = true
		}
	}
	return suggestPools{
		own: ownPool, comp: compPool,
		mappedPairs: mappedPairs, ownHasMapping: ownHas, rejectedPairs: rejected,
	}, nil
}

// generateForOwn ranks and persists up to MaxRank pending suggestions for one own SKU.
// Returns Arabic skip reason when nothing is created (empty string on success).
func (h *CompetitorSuggestionsHandler) generateForOwn(
	r *http.Request,
	ctx suggestContext,
	pool suggestPools,
	own competitorsuggest.SkuCandidate,
) ([]domain.CompetitorSuggestion, string, competitorsuggest.TokenUsage, error) {
	var usage competitorsuggest.TokenUsage
	if ctx.skipOwnWithAnyMapping && pool.ownHasMapping[normBarcode(own.Barcode)] {
		return nil, "يوجد تعيين معتمد مسبقاً", usage, nil
	}
	if strings.TrimSpace(own.Category) == "" {
		return nil, "فئة مفقودة في البيانات", usage, nil
	}
	cands := competitorsuggest.PreFilterCandidates(own, pool.comp, h.eq)
	filtered := make([]competitorsuggest.PrefScore, 0, len(cands))
	for _, cand := range cands {
		key := firestore.RejectedPairKey(own.Barcode, cand.Candidate.Barcode, ctx.chain)
		if pool.rejectedPairs[key] {
			continue
		}
		if pool.mappedPairs[key] {
			continue
		}
		filtered = append(filtered, cand)
	}
	if len(filtered) == 0 {
		return nil, "لا يوجد منافسين في البيانات", usage, nil
	}
	ranked, usage, err := h.ranker.Rank(r.Context(), own, filtered)
	if err != nil {
		return nil, "تعذر ترتيب المرشحين", usage, err
	}
	byBC := map[string]competitorsuggest.PrefScore{}
	for _, f := range filtered {
		byBC[f.Candidate.Barcode] = f
	}
	created := make([]domain.CompetitorSuggestion, 0, len(ranked))
	for _, sug := range ranked {
		ps := byBC[sug.CompetitorBarcode]
		row := &domain.CompetitorSuggestion{
			TenantID:            ctx.tenantID,
			OwnBarcode:          own.Barcode,
			OwnSkuName:          own.SKUName,
			OwnCategory:         own.Category,
			CompetitorBarcode:   sug.CompetitorBarcode,
			CompetitorSkuName:   ps.Candidate.SKUName,
			CompetitorBrand:     ps.Candidate.Brand,
			CompetitorSupplier:  ps.Candidate.Supplier,
			Category:            ps.Candidate.Category,
			RetailerChain:       ctx.chain,
			ReasonAR:            sug.ReasonAR,
			Confidence:          sug.Confidence,
			Rank:                sug.Rank,
			Status:              domain.CompetitorSuggestionPending,
			OwnUnitPrice:        own.UnitPrice,
			CompetitorUnitPrice: ps.Candidate.UnitPrice,
			OwnUnits:            own.Units,
			CompetitorUnits:     ps.Candidate.Units,
			SizeLabelOwn:        ps.SizeLabelOwn,
			SizeLabelCompetitor: ps.SizeLabelCand,
			VariantBonus:        ps.VariantBonus,
			PromptTokens:        usage.PromptTokens,
			CompletionTokens:    usage.CompletionTokens,
			CreatedBy:           ctx.email,
		}
		if err := h.repo.SaveCompetitorSuggestion(r.Context(), row); err != nil {
			log.Printf("[competitor-suggest] save failed: %v", err)
			continue
		}
		if row.Status == domain.CompetitorSuggestionPending {
			created = append(created, *row)
		}
	}
	if len(created) == 0 {
		return created, "لا يوجد منافسين في البيانات", usage, nil
	}
	return created, "", usage, nil
}

func normBarcode(s string) string {
	return strings.ToLower(strings.TrimSpace(s))
}

func splitCatalog(res bigquery.CompetitiveMonthlyResult) (own, comp []competitorsuggest.SkuCandidate) {
	for _, item := range res.Items {
		units := 0
		price := 0.0
		rev := 0.0
		for _, m := range item.Months {
			units += m.Units
			rev += m.NetRevenue
		}
		if units > 0 {
			price = rev / float64(units)
		}
		c := competitorsuggest.SkuCandidate{
			Barcode:    item.Barcode,
			SKUName:    item.SKUName,
			Category:   item.Category,
			UnitPrice:  price,
			Units:      units,
			IsOwnBrand: item.IsOwnBrand,
		}
		if item.IsOwnBrand {
			own = append(own, c)
		} else {
			comp = append(comp, c)
		}
	}
	return own, comp
}

func customAsCandidates(customs []domain.CustomCompetitorSku) []competitorsuggest.SkuCandidate {
	out := make([]competitorsuggest.SkuCandidate, 0, len(customs))
	for _, s := range customs {
		bc := "CMP-" + s.ID
		if strings.TrimSpace(s.CompetitorSkuName) == "" {
			continue
		}
		out = append(out, competitorsuggest.SkuCandidate{
			Barcode:   bc,
			SKUName:   s.CompetitorSkuName,
			Category:  s.Category,
			Supplier:  s.CompetitorSupplier,
			Brand:     s.CompetitorBrand,
			UnitPrice: s.CompetitorPrice,
			Units:     s.EstimatedMonthlyUnits,
			IsCustom:  true,
		})
	}
	return out
}
