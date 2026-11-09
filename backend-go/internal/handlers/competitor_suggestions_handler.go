package handlers

import (
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"net/http"
	"strings"
	"sync"
	"time"

	"github.com/tashil/data-sharing/backend/internal/domain"
	"github.com/tashil/data-sharing/backend/internal/service/bigquery"
	"github.com/tashil/data-sharing/backend/internal/service/competitorsuggest"
	"github.com/tashil/data-sharing/backend/internal/service/firestore"
)

// Owner-only for run / approve / reject (company manager + super admin).
var competitorSuggestOwnerRoles = map[domain.UserRole]bool{
	domain.RoleSuperAdmin:  true,
	domain.RoleVendorAdmin: true,
}

const (
	competitorSuggestDefaultBatch = 10
	competitorSuggestMaxBatch     = 10 // hard cap matches owner batch-size spec
	competitorSuggestMinInterval  = 30 * time.Second
)

// CompetitiveCatalogSource supplies Sell-Out barcode catalogue for suggestions.
type CompetitiveCatalogSource interface {
	CompetitiveMonthly(tenantID string, filter bigquery.RecordFilter) bigquery.CompetitiveMonthlyResult
}

// CompetitorSuggestionsHandler serves the AI competitor-suggestion quarantine APIs.
// Pending suggestions NEVER feed Compare KPIs or mappings until owner approve.
type CompetitorSuggestionsHandler struct {
	repo     firestore.CompetitorSkuRepository
	audit    firestore.Repository
	catalog  CompetitiveCatalogSource
	ranker   competitorsuggest.Ranker
	eq       competitorsuggest.CategoryEquivalence
	rateMu   sync.Mutex
	lastRun  map[string]time.Time // tenant|chain → last run
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
	}
}

type suggestRunPayload struct {
	Chain     string   `json:"chain"`
	OwnSKUs   []string `json:"own_skus"`
	Limit     int      `json:"limit"`
	Year      int      `json:"year"`
}

type suggestDecidePayload struct {
	ID string `json:"id"`
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
		"suggestions": items,
		"count":       len(items),
		"pending_category_equivalence": competitorsuggest.PendingCategoryEquivalencePairs,
	})
}

// HandleRunSuggestions serves POST /api/v1/competitors/suggestions/run (owner-only).
// Manual trigger only — no background auto-run. Idempotent per own+competitor+chain.
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
	start, end := bigquery.CompetitiveMonthlyYearWindow(year)
	res := h.catalog.CompetitiveMonthly(c.TenantID, bigquery.RecordFilter{
		RetailerChain: p.Chain,
		Supplier:      "all_market",
		StartDate:     start,
		EndDate:       end,
	})

	ownPool, compPool := splitCatalog(res)
	customs, _ := h.repo.ListCustomCompetitorSkus(r.Context(), c.TenantID, domain.CustomCompetitorSkuFilter{Chain: p.Chain})
	compPool = append(compPool, customAsCandidates(customs)...)

	mappings, _ := h.repo.ListCompetitorMappings(r.Context(), c.TenantID, domain.CompetitorMappingFilter{Chain: p.Chain})
	approvedOwn := map[string]bool{}
	for _, m := range mappings {
		approvedOwn[normBarcode(m.OwnBarcode)] = true
	}
	existing, _ := h.repo.ListCompetitorSuggestions(r.Context(), c.TenantID, domain.CompetitorSuggestionFilter{Chain: p.Chain})
	rejectedPairs := map[string]bool{}
	for _, s := range existing {
		if s.Status == domain.CompetitorSuggestionRejected {
			rejectedPairs[firestore.RejectedPairKey(s.OwnBarcode, s.CompetitorBarcode, s.RetailerChain)] = true
		}
	}

	ownFilter := map[string]bool{}
	for _, bc := range p.OwnSKUs {
		bc = strings.TrimSpace(bc)
		if bc != "" {
			ownFilter[normBarcode(bc)] = true
		}
	}

	type skipInfo struct {
		Barcode string `json:"barcode"`
		Reason  string `json:"reason_ar"`
	}
	created := make([]domain.CompetitorSuggestion, 0)
	skipped := make([]skipInfo, 0)
	var promptTok, completionTok int
	processed := 0

	for _, own := range ownPool {
		if processed >= limit {
			break
		}
		if len(ownFilter) > 0 && !ownFilter[normBarcode(own.Barcode)] {
			continue
		}
		if approvedOwn[normBarcode(own.Barcode)] {
			skipped = append(skipped, skipInfo{Barcode: own.Barcode, Reason: "يوجد تعيين معتمد مسبقاً"})
			continue
		}
		if strings.TrimSpace(own.Category) == "" {
			skipped = append(skipped, skipInfo{Barcode: own.Barcode, Reason: "فئة مفقودة في البيانات"})
			continue
		}
		cands := competitorsuggest.PreFilterCandidates(own, compPool, h.eq)
		// Drop remembered rejected pairs.
		filtered := make([]competitorsuggest.PrefScore, 0, len(cands))
		for _, cand := range cands {
			key := firestore.RejectedPairKey(own.Barcode, cand.Candidate.Barcode, p.Chain)
			if rejectedPairs[key] {
				continue
			}
			filtered = append(filtered, cand)
		}
		if len(filtered) == 0 {
			skipped = append(skipped, skipInfo{Barcode: own.Barcode, Reason: "لا يوجد منافسين في البيانات"})
			processed++
			continue
		}
		ranked, usage, err := h.ranker.Rank(r.Context(), own, filtered)
		promptTok += usage.PromptTokens
		completionTok += usage.CompletionTokens
		if err != nil {
			log.Printf("[competitor-suggest] rank failed own=%s: %v", own.Barcode, err)
			skipped = append(skipped, skipInfo{Barcode: own.Barcode, Reason: "تعذر ترتيب المرشحين"})
			processed++
			continue
		}
		byBC := map[string]competitorsuggest.PrefScore{}
		for _, f := range filtered {
			byBC[f.Candidate.Barcode] = f
		}
		for _, sug := range ranked {
			ps := byBC[sug.CompetitorBarcode]
			row := &domain.CompetitorSuggestion{
				TenantID:            c.TenantID,
				OwnBarcode:          own.Barcode,
				OwnSkuName:          own.SKUName,
				OwnCategory:         own.Category,
				CompetitorBarcode:   sug.CompetitorBarcode,
				CompetitorSkuName:   ps.Candidate.SKUName,
				CompetitorBrand:     ps.Candidate.Brand,
				CompetitorSupplier:  ps.Candidate.Supplier,
				Category:            ps.Candidate.Category,
				RetailerChain:       p.Chain,
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
				CreatedBy:           c.Email,
			}
			if err := h.repo.SaveCompetitorSuggestion(r.Context(), row); err != nil {
				log.Printf("[competitor-suggest] save failed: %v", err)
				continue
			}
			if row.Status == domain.CompetitorSuggestionPending {
				created = append(created, *row)
			}
		}
		processed++
	}

	log.Printf("[competitor-suggest] run tenant=%s chain=%s processed=%d created=%d prompt_tokens=%d completion_tokens=%d",
		normalizeAuditTenantID(c.TenantID), p.Chain, processed, len(created), promptTok, completionTok)
	h.recordAudit(r, c, "RUN_COMPETITOR_SUGGESTIONS",
		fmt.Sprintf("chain=%s processed=%d created=%d tokens=%d/%d", p.Chain, processed, len(created), promptTok, completionTok))

	writeJSON(w, http.StatusOK, map[string]interface{}{
		"suggestions":      created,
		"created_count":    len(created),
		"processed_own":    processed,
		"skipped":          skipped,
		"prompt_tokens":    promptTok,
		"completion_tokens": completionTok,
		"limit":            limit,
		"pending_category_equivalence": competitorsuggest.PendingCategoryEquivalencePairs,
	})
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
