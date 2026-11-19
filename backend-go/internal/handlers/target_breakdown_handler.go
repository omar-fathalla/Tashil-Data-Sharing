package handlers

import (
	"context"
	"encoding/json"
	"log"
	"math"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/tashil/data-sharing/backend/internal/domain"
	"github.com/tashil/data-sharing/backend/internal/middleware"
	"github.com/tashil/data-sharing/backend/internal/service/bqsink"
	"github.com/tashil/data-sharing/backend/internal/service/targetalloc"
)

// targetBreakdownBQTimeout bounds the BigQuery path; past it the request falls back to memory.
const targetBreakdownBQTimeout = 20 * time.Second

// sellOutMonthlyPhaser builds seasonal monthly series from in-memory sell_out_facts (same dedup /
// own-brand rules as target actuals). Optional on the analytics repo.
type sellOutMonthlyPhaser interface {
	BuildSellOutMonthlyPhasing(ctx context.Context, tenantID string, t domain.TargetRecord, yearTargetRev, yearTargetUnits float64, branchKey string) []domain.TargetMonthBreakdown
	PriorYearMonthShare(ctx context.Context, tenantID string, t domain.TargetRecord, branchKey string, month int) (revShare, unitShare float64)
}

// WithTargetBreakdownQuerier lets the target breakdown aggregate in BigQuery. A nil querier keeps the
// in-memory path.
func (h *AnalyticsHandler) WithTargetBreakdownQuerier(q bqsink.TargetBreakdownQuerier) *AnalyticsHandler {
	h.targetBreakdown = q
	return h
}

// HandleTargetBreakdown serves GET /api/v1/sellout/targets/{id}/breakdown (read-only).
//
// Optional query params:
//   - branch: store key — scopes branches/SKUs/KPIs/monthly_phasing to that branch
//   - month: 1..12 — scopes actuals and seasonal target slice to that month (combinable with branch)
//
// It shows how a Sell-Out target is distributed over branches and SKUs, proportionally to the
// historical baseline (see targetalloc.ResolveBaseline), next to the actuals of the target period.
func (h *AnalyticsHandler) HandleTargetBreakdown(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet && r.Method != http.MethodHead {
		http.Error(w, `{"error":"method not allowed"}`, http.StatusMethodNotAllowed)
		return
	}
	tenantID, err := middleware.EnforceTenantRLS(r)
	if err != nil {
		http.Error(w, `{"error":"unauthorized tenant context"}`, http.StatusUnauthorized)
		return
	}
	id := strings.TrimSpace(r.PathValue("id"))
	if id == "" {
		http.Error(w, `{"error":"missing target id"}`, http.StatusBadRequest)
		return
	}
	target, ok := h.bqRepo.GetTarget(r.Context(), tenantID, id)
	if !ok || target == nil {
		http.Error(w, `{"error":"target not found"}`, http.StatusNotFound)
		return
	}
	if target.TargetType == "sell_in" {
		http.Error(w, `{"error":"breakdown is available for sell-out targets only"}`, http.StatusBadRequest)
		return
	}

	chain := targetalloc.ChainFilter(target.RetailerChain)
	if claims, ok := middleware.GetUserClaims(r.Context()); ok && claims != nil &&
		claims.Role == domain.RoleChainKAM && strings.TrimSpace(claims.AssignedChain) != "" {
		assigned := strings.ToLower(strings.TrimSpace(claims.AssignedChain))
		if chain != "" && chain != assigned {
			http.Error(w, `{"error":"target is outside your assigned chain"}`, http.StatusForbidden)
			return
		}
		chain = assigned
	}

	filters := parseBreakdownFilters(r)
	started := time.Now()
	resp, source, err := h.computeTargetBreakdown(r.Context(), tenantID, chain, *target, filters)
	if err != nil {
		log.Printf("[target-breakdown] tenant=%s target=%s failed: %v", tenantID, id, err)
		http.Error(w, `{"error":"failed to compute target breakdown"}`, http.StatusInternalServerError)
		return
	}
	log.Printf("[target-breakdown] tenant=%s target=%s chain=%q year=%d month=%d branch=%q filterMonth=%d source=%s branches=%d took=%s",
		tenantID, id, chain, target.Year, target.Month, filters.BranchKey, filters.Month, source, len(resp.Branches), time.Since(started).Round(time.Millisecond))
	setRecordsSource(w, source)
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(resp)
}

func parseBreakdownFilters(r *http.Request) targetalloc.Filters {
	q := r.URL.Query()
	f := targetalloc.Filters{
		BranchKey: strings.TrimSpace(q.Get("branch")),
	}
	if m, err := strconv.Atoi(strings.TrimSpace(q.Get("month"))); err == nil && m >= 1 && m <= 12 {
		f.Month = m
	}
	return f
}

func (h *AnalyticsHandler) computeTargetBreakdown(ctx context.Context, tenantID, chain string, target domain.TargetRecord, filters targetalloc.Filters) (domain.TargetBreakdownResponse, string, error) {
	work := target
	annualRev := target.TargetRevenueEGP
	annualUnits := target.TargetUnits

	// Month filter on an annual target: scale to that month's seasonal slice before allocation.
	if filters.Month >= 1 && filters.Month <= 12 && (target.Month == 0 || target.Month < 1 || target.Month > 12) {
		revShare, unitShare := 1.0/12.0, 1.0/12.0
		if phaser, ok := h.bqRepo.(sellOutMonthlyPhaser); ok {
			revShare, unitShare = phaser.PriorYearMonthShare(ctx, tenantID, target, filters.BranchKey, filters.Month)
		}
		work.TargetRevenueEGP = roundBreakdown(annualRev * revShare)
		work.TargetUnits = roundBreakdown(annualUnits * unitShare)
		work.Month = filters.Month
		work.MonthLabel = targetalloc.MonthNameAr(filters.Month)
	}

	var resp domain.TargetBreakdownResponse
	var source string
	var err error
	var found bool

	if h.targetBreakdown != nil {
		c, cancel := context.WithTimeout(ctx, targetBreakdownBQTimeout)
		resp, found, err = targetalloc.ComputeFiltered(c, h.targetBreakdown.TargetBreakdownSource(tenantID, chain), work, "bigquery", filters)
		cancel()
		switch {
		case err != nil:
			log.Printf("WARN [target-breakdown] BigQuery path failed, serving from memory: %v", err)
		case found:
			source = "bigquery"
		}
	}
	if source == "" {
		resp, found, err = targetalloc.ComputeFiltered(ctx, h.bqRepo.TargetBreakdownSource(tenantID, chain), work, "memory", filters)
		if err != nil {
			return resp, "memory", err
		}
		source = "memory"
		if !found {
			// No Sell-Out rows at all: still answer, with an empty baseline, so the UI can say so.
			resp = targetalloc.Build(targetalloc.Input{
				Target: work, Baseline: targetalloc.Baseline{Kind: targetalloc.KindNone},
				ActualWindow: targetalloc.ActualWindow(work.Year, work.Month), Source: "memory",
			})
			if filters.BranchKey != "" {
				resp = targetalloc.FilterToBranch(resp, filters.BranchKey)
			}
			resp.AppliedMonth = filters.Month
			resp.AppliedBranch = filters.BranchKey
		}
	}

	// Attach seasonal monthly series for the (branch-scoped) annual target so the detail page
	// can rebuild Monthly / chart when filters change. Uses annual amounts, not the month slice.
	phaser, ok := h.bqRepo.(sellOutMonthlyPhaser)
	if ok {
		phasingAnnual := annualRev
		phasingUnits := annualUnits
		branchKey := filters.BranchKey
		if branchKey != "" && len(resp.Branches) == 1 {
			// Branch annual = that branch's full-year allocation. When month filter scaled the
			// working target, recover annual from share of the filtered branch allocation.
			b := resp.Branches[0]
			if filters.Month >= 1 && filters.Month <= 12 && (target.Month == 0 || target.Month < 1 || target.Month > 12) {
				revShare, _ := phaser.PriorYearMonthShare(ctx, tenantID, target, branchKey, filters.Month)
				if revShare > 0 {
					phasingAnnual = b.AllocatedTargetEGP / revShare
				} else {
					phasingAnnual = b.AllocatedTargetEGP * 12
				}
				_, unitShare := phaser.PriorYearMonthShare(ctx, tenantID, target, branchKey, filters.Month)
				if unitShare > 0 && b.AllocatedUnits != nil {
					phasingUnits = float64(*b.AllocatedUnits) / unitShare
				} else if b.AllocatedUnits != nil {
					phasingUnits = float64(*b.AllocatedUnits) * 12
				}
			} else {
				phasingAnnual = b.AllocatedTargetEGP
				if b.AllocatedUnits != nil {
					phasingUnits = float64(*b.AllocatedUnits)
				}
			}
		}
		// Phasing always uses the original annual target record (month=0) so we get 12 entries.
		phTarget := target
		phTarget.Month = 0
		resp.MonthlyPhasing = phaser.BuildSellOutMonthlyPhasing(ctx, tenantID, phTarget, phasingAnnual, phasingUnits, branchKey)
	}

	resp.AppliedBranch = filters.BranchKey
	resp.AppliedMonth = filters.Month
	return resp, source, nil
}

func roundBreakdown(v float64) float64 { return math.Round(v*100) / 100 }
