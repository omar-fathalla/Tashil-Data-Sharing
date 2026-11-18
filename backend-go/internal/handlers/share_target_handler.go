package handlers

import (
	"encoding/json"
	"io"
	"net/http"
	"strconv"
	"strings"

	"github.com/tashil/data-sharing/backend/internal/domain"
	"github.com/tashil/data-sharing/backend/internal/middleware"
	"github.com/tashil/data-sharing/backend/internal/service/sharetarget"
)

// HandleShareTargetBaseline serves GET /api/v1/sellout/share-target/baseline?chain=&year=
func (h *AnalyticsHandler) HandleShareTargetBaseline(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet && r.Method != http.MethodHead {
		http.Error(w, `{"error":"method not allowed"}`, http.StatusMethodNotAllowed)
		return
	}
	tenantID, err := middleware.EnforceTenantRLS(r)
	if err != nil {
		http.Error(w, `{"error":"unauthorized tenant context"}`, http.StatusUnauthorized)
		return
	}
	q := r.URL.Query()
	chain := strings.ToLower(strings.TrimSpace(q.Get("chain")))
	if claims, ok := middleware.GetUserClaims(r.Context()); ok && claims != nil &&
		claims.Role == domain.RoleChainKAM && strings.TrimSpace(claims.AssignedChain) != "" {
		chain = strings.ToLower(strings.TrimSpace(claims.AssignedChain))
	}
	year, _ := strconv.Atoi(q.Get("year"))
	baseline, err := h.bqRepo.GetShareTargetBaseline(r.Context(), tenantID, chain, year)
	if err != nil {
		http.Error(w, `{"error":"`+jsonEscape(err.Error())+`"}`, http.StatusBadRequest)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(baseline)
}

type shareTargetPreviewRequest struct {
	RetailerChain   string             `json:"retailer_chain"`
	Year            int                `json:"year"`
	MarketGrowthPct float64            `json:"market_growth_pct"`
	MonthsWithData  int                `json:"months_with_data"`
	Annualize       *bool              `json:"annualize"`
	BranchKeys      []string           `json:"branch_keys"`
	Categories      []shareCatDesired  `json:"categories"`
	DeltaPts        *float64           `json:"delta_pts"` // optional uniform +N points
}

type shareCatDesired struct {
	Category        string   `json:"category"`
	DesiredSharePct *float64 `json:"desired_share_pct"`
}

type shareTargetPreviewResponse struct {
	Plan      sharetarget.PlanSummary          `json:"plan"`
	Cascades  []sharetarget.CategoryCascade    `json:"cascades"`
	CanSave   bool                             `json:"can_save"`
}

// HandleShareTargetPreview serves POST /api/v1/sellout/share-target/preview
func (h *AnalyticsHandler) HandleShareTargetPreview(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, `{"error":"method not allowed"}`, http.StatusMethodNotAllowed)
		return
	}
	tenantID, err := middleware.EnforceTenantRLS(r)
	if err != nil {
		http.Error(w, `{"error":"unauthorized tenant context"}`, http.StatusUnauthorized)
		return
	}
	var req shareTargetPreviewRequest
	body, _ := io.ReadAll(r.Body)
	if err := json.Unmarshal(body, &req); err != nil {
		http.Error(w, `{"error":"invalid JSON payload"}`, http.StatusBadRequest)
		return
	}
	chain := strings.ToLower(strings.TrimSpace(req.RetailerChain))
	if claims, ok := middleware.GetUserClaims(r.Context()); ok && claims != nil &&
		claims.Role == domain.RoleChainKAM && strings.TrimSpace(claims.AssignedChain) != "" {
		chain = strings.ToLower(strings.TrimSpace(claims.AssignedChain))
	}
	year := req.Year
	if year <= 0 {
		year = 2026
	}
	baseline, err := h.bqRepo.GetShareTargetBaseline(r.Context(), tenantID, chain, year)
	if err != nil {
		http.Error(w, `{"error":"`+jsonEscape(err.Error())+`"}`, http.StatusBadRequest)
		return
	}
	months := req.MonthsWithData
	if months <= 0 {
		months = baseline.MonthsWithData
	}
	annualize := true
	if req.Annualize != nil {
		annualize = *req.Annualize
	}
	opt := sharetarget.Options{
		MarketGrowthPct: req.MarketGrowthPct,
		MonthsWithData:  months,
		Annualize:       annualize,
	}

	inputs, desired, err := alignCategories(baseline, req)
	if err != nil {
		http.Error(w, `{"error":"`+jsonEscape(err.Error())+`"}`, http.StatusBadRequest)
		return
	}

	var plan sharetarget.PlanSummary
	if req.DeltaPts != nil {
		plan = sharetarget.PlanAllDelta(inputs, *req.DeltaPts, opt)
	} else {
		plan, err = sharetarget.PlanAll(inputs, desired, opt)
		if err != nil {
			http.Error(w, `{"error":"`+jsonEscape(err.Error())+`"}`, http.StatusBadRequest)
			return
		}
	}

	branchFilter := map[string]bool{}
	for _, k := range req.BranchKeys {
		k = strings.TrimSpace(k)
		if k != "" {
			branchFilter[k] = true
		}
	}

	catNames := make([]string, 0, len(plan.Categories))
	for _, catPlan := range plan.Categories {
		catNames = append(catNames, catPlan.Category)
	}
	// Wizard step-3 only renders SKU samples from the first category; skip SKU
	// mix collection for the rest to cut preview latency/payload.
	skuFor := map[string]bool{}
	if len(catNames) > 0 {
		skuFor[catNames[0]] = true
	}
	batch, _ := h.bqRepo.BuildShareTargetCascadesBatch(
		r.Context(), tenantID, chain, year, catNames, branchFilter, skuFor,
	)

	cascades := make([]sharetarget.CategoryCascade, 0, len(plan.Categories))
	for _, catPlan := range plan.Categories {
		in := batch[catPlan.Category]
		if in.SKUsByBranch == nil {
			in.SKUsByBranch = map[string][]sharetarget.SKUWeight{}
		}
		cascades = append(cascades, sharetarget.CascadeCategory(
			catPlan, in.Branches, in.SKUsByBranch, in.Months,
		))
	}

	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(shareTargetPreviewResponse{
		Plan: plan, Cascades: cascades, CanSave: plan.CanProceed(),
	})
}

type shareTargetSaveRequest struct {
	shareTargetPreviewRequest
	Notes string `json:"notes"`
}

// HandleShareTargetSave serves POST /api/v1/sellout/share-target
// Saves one normal sell_out TargetRecord (full year) whose revenue/units equal the share plan total.
func (h *AnalyticsHandler) HandleShareTargetSave(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, `{"error":"method not allowed"}`, http.StatusMethodNotAllowed)
		return
	}
	if _, ok := requireWriteRole(w, r, ingestWriteRoles); !ok {
		return
	}
	tenantID, err := middleware.EnforceTenantRLS(r)
	if err != nil {
		http.Error(w, `{"error":"unauthorized tenant context"}`, http.StatusUnauthorized)
		return
	}
	var req shareTargetSaveRequest
	body, _ := io.ReadAll(r.Body)
	if err := json.Unmarshal(body, &req); err != nil {
		http.Error(w, `{"error":"invalid JSON payload"}`, http.StatusBadRequest)
		return
	}
	chain := strings.ToLower(strings.TrimSpace(req.RetailerChain))
	if claims, ok := middleware.GetUserClaims(r.Context()); ok && claims != nil &&
		claims.Role == domain.RoleChainKAM && strings.TrimSpace(claims.AssignedChain) != "" {
		chain = strings.ToLower(strings.TrimSpace(claims.AssignedChain))
	}
	year := req.Year
	if year <= 0 {
		year = 2026
	}
	baseline, err := h.bqRepo.GetShareTargetBaseline(r.Context(), tenantID, chain, year)
	if err != nil {
		http.Error(w, `{"error":"`+jsonEscape(err.Error())+`"}`, http.StatusBadRequest)
		return
	}
	months := req.MonthsWithData
	if months <= 0 {
		months = baseline.MonthsWithData
	}
	annualize := true
	if req.Annualize != nil {
		annualize = *req.Annualize
	}
	opt := sharetarget.Options{
		MarketGrowthPct: req.MarketGrowthPct,
		MonthsWithData:  months,
		Annualize:       annualize,
	}
	inputs, desired, err := alignCategories(baseline, req.shareTargetPreviewRequest)
	if err != nil {
		http.Error(w, `{"error":"`+jsonEscape(err.Error())+`"}`, http.StatusBadRequest)
		return
	}
	var plan sharetarget.PlanSummary
	if req.DeltaPts != nil {
		plan = sharetarget.PlanAllDelta(inputs, *req.DeltaPts, opt)
	} else {
		plan, err = sharetarget.PlanAll(inputs, desired, opt)
		if err != nil {
			http.Error(w, `{"error":"`+jsonEscape(err.Error())+`"}`, http.StatusBadRequest)
			return
		}
	}
	if !plan.CanProceed() {
		http.Error(w, `{"error":"desired share cannot exceed 100%"}`, http.StatusBadRequest)
		return
	}

	branchName := "كل الفروع"
	if len(req.BranchKeys) == 1 {
		branchName = req.BranchKeys[0]
	} else if len(req.BranchKeys) > 1 {
		branchName = "فروع محددة"
	}

	meta := &domain.ShareTargetMeta{
		MarketGrowthPct:     plan.MarketGrowthPct,
		MonthsWithData:      plan.MonthsWithData,
		Annualized:          plan.Annualized,
		AnnualizationFactor: plan.AnnualizationFactor,
		OverallCurrentPct:   plan.OverallCurrentPct,
		OverallDesiredPct:   plan.OverallDesiredPct,
	}
	for _, c := range plan.Categories {
		meta.Categories = append(meta.Categories, domain.ShareCategoryMeta{
			Category:         c.Category,
			CurrentSharePct:  c.CurrentSharePct,
			DesiredSharePct:  c.DesiredSharePct,
			TargetRevenueEGP: c.TargetRevenueEGP,
			UpliftRevenueEGP: c.UpliftRevenueEGP,
		})
	}

	notes := strings.TrimSpace(req.Notes)
	if notes == "" {
		notes = "مستهدف بالحصة السوقية"
	}

	saved, err := h.bqRepo.UpsertTarget(r.Context(), tenantID, domain.TargetRecord{
		TargetType:       "sell_out",
		RetailerChain:    chain,
		Year:             year,
		Month:            0,
		BranchName:       branchName,
		Category:         "كل الفئات",
		TargetRevenueEGP: plan.TotalTargetEGP,
		TargetUnits:      plan.TotalTargetUnits,
		Notes:            notes,
		Origin:           sharetarget.OriginShare,
		ShareMeta:        meta,
	})
	if err != nil {
		http.Error(w, `{"error":"failed to save target"}`, http.StatusInternalServerError)
		return
	}
	summary, _ := h.bqRepo.GetTargetsSummary(r.Context(), tenantID, "sell_out", chain, year)
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]interface{}{
		"target":  saved,
		"plan":    plan,
		"summary": summary,
	})
}

func alignCategories(baseline *domain.ShareTargetBaselineResponse, req shareTargetPreviewRequest) ([]sharetarget.CategoryInput, []float64, error) {
	byName := map[string]domain.ShareTargetBaselineCategory{}
	for _, c := range baseline.Categories {
		byName[c.Category] = c
	}
	if len(req.Categories) == 0 && req.DeltaPts != nil {
		inputs := make([]sharetarget.CategoryInput, 0, len(baseline.Categories))
		for _, c := range baseline.Categories {
			inputs = append(inputs, sharetarget.CategoryInput{
				Category: c.Category, CurrentSharePct: c.CurrentSharePct,
				OwnRevenueEGP: c.OwnRevenueEGP, MarketRevenueEGP: c.MarketRevenueEGP,
				OwnUnits: c.OwnUnits, AvgPriceEGP: c.AvgPriceEGP,
			})
		}
		return inputs, nil, nil
	}
	if len(req.Categories) == 0 {
		return nil, nil, errString("categories required")
	}
	inputs := make([]sharetarget.CategoryInput, 0, len(req.Categories))
	desired := make([]float64, 0, len(req.Categories))
	for _, rc := range req.Categories {
		base, ok := byName[rc.Category]
		if !ok {
			// Allow planning against baseline-missing names only when numbers are supplied via desired alone — skip unknown.
			continue
		}
		d := base.CurrentSharePct
		if rc.DesiredSharePct != nil {
			d = *rc.DesiredSharePct
		}
		inputs = append(inputs, sharetarget.CategoryInput{
			Category: base.Category, CurrentSharePct: base.CurrentSharePct,
			OwnRevenueEGP: base.OwnRevenueEGP, MarketRevenueEGP: base.MarketRevenueEGP,
			OwnUnits: base.OwnUnits, AvgPriceEGP: base.AvgPriceEGP,
		})
		desired = append(desired, d)
	}
	if len(inputs) == 0 {
		return nil, nil, errString("no matching categories")
	}
	return inputs, desired, nil
}

type errString string

func (e errString) Error() string { return string(e) }

func jsonEscape(s string) string {
	b, _ := json.Marshal(s)
	if len(b) >= 2 {
		return string(b[1 : len(b)-1])
	}
	return s
}
