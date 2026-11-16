package handlers

import (
	"context"
	"encoding/json"
	"log"
	"net/http"
	"strings"
	"time"

	"github.com/tashil/data-sharing/backend/internal/domain"
	"github.com/tashil/data-sharing/backend/internal/middleware"
	"github.com/tashil/data-sharing/backend/internal/service/bqsink"
	"github.com/tashil/data-sharing/backend/internal/service/targetalloc"
)

// targetBreakdownBQTimeout bounds the BigQuery path; past it the request falls back to memory.
const targetBreakdownBQTimeout = 20 * time.Second

// WithTargetBreakdownQuerier lets the target breakdown aggregate in BigQuery. A nil querier keeps the
// in-memory path.
func (h *AnalyticsHandler) WithTargetBreakdownQuerier(q bqsink.TargetBreakdownQuerier) *AnalyticsHandler {
	h.targetBreakdown = q
	return h
}

// HandleTargetBreakdown serves GET /api/v1/sellout/targets/{id}/breakdown (read-only).
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

	started := time.Now()
	resp, source, err := h.computeTargetBreakdown(r.Context(), tenantID, chain, *target)
	if err != nil {
		log.Printf("[target-breakdown] tenant=%s target=%s failed: %v", tenantID, id, err)
		http.Error(w, `{"error":"failed to compute target breakdown"}`, http.StatusInternalServerError)
		return
	}
	log.Printf("[target-breakdown] tenant=%s target=%s chain=%q year=%d month=%d source=%s branches=%d took=%s",
		tenantID, id, chain, target.Year, target.Month, source, len(resp.Branches), time.Since(started).Round(time.Millisecond))
	setRecordsSource(w, source)
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(resp)
}

func (h *AnalyticsHandler) computeTargetBreakdown(ctx context.Context, tenantID, chain string, target domain.TargetRecord) (domain.TargetBreakdownResponse, string, error) {
	if h.targetBreakdown != nil {
		c, cancel := context.WithTimeout(ctx, targetBreakdownBQTimeout)
		resp, found, err := targetalloc.Compute(c, h.targetBreakdown.TargetBreakdownSource(tenantID, chain), target, "bigquery")
		cancel()
		switch {
		case err != nil:
			log.Printf("WARN [target-breakdown] BigQuery path failed, serving from memory: %v", err)
		case found:
			return resp, "bigquery", nil
		}
	}
	resp, found, err := targetalloc.Compute(ctx, h.bqRepo.TargetBreakdownSource(tenantID, chain), target, "memory")
	if err != nil {
		return resp, "memory", err
	}
	if !found {
		// No Sell-Out rows at all: still answer, with an empty baseline, so the UI can say so.
		resp = targetalloc.Build(targetalloc.Input{
			Target: target, Baseline: targetalloc.Baseline{Kind: targetalloc.KindNone},
			ActualWindow: targetalloc.ActualWindow(target.Year, target.Month), Source: "memory",
		})
	}
	return resp, "memory", nil
}
