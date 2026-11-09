package handlers

import (
	"context"
	"encoding/json"
	"net/http"
	"strconv"
	"strings"

	"github.com/tashil/data-sharing/backend/internal/domain"
	"github.com/tashil/data-sharing/backend/internal/middleware"
	"github.com/tashil/data-sharing/backend/internal/service/bigquery"
)

// sellInReturnsProvider is implemented by *bigquery.Client (cached + fast path).
type sellInReturnsProvider interface {
	GetSellInReturnsCached(ctx context.Context, tenantID string, filter bigquery.SellInReturnsFilter) bigquery.SellInReturnsReport
}

// HandleSellInReturns serves GET /api/v1/analytics/sell-in-returns (المرتجعات report).
// Phase-1: KPIs, matrix, chart.
// Phase-2: top returned products (Excel is client-side).
// Advisories / threshold alerts are omitted (empty) — UI cards removed; keeps JSON keys.
// Read-only, tenant-scoped. Negatives stay as stored; response returns amounts are positive.
func (h *AnalyticsHandler) HandleSellInReturns(w http.ResponseWriter, r *http.Request) {
	tenantID, err := middleware.EnforceTenantRLS(r)
	if err != nil {
		http.Error(w, `{"error":"unauthorized tenant context"}`, http.StatusUnauthorized)
		return
	}

	q := r.URL.Query()
	year, _ := strconv.Atoi(q.Get("year"))
	month, _ := strconv.Atoi(q.Get("month"))
	filter := bigquery.SellInReturnsFilter{
		Year:         year,
		Month:        month,
		Chain:        q.Get("chain"),
		Branch:       q.Get("branch"),
		Product:      q.Get("product"),
		ProductGroup: q.Get("product_group"),
	}

	if claims, ok := middleware.GetUserClaims(r.Context()); ok && claims != nil {
		if claims.Role == domain.RoleChainKAM && strings.TrimSpace(claims.AssignedChain) != "" {
			filter.Chain = strings.TrimSpace(claims.AssignedChain)
		}
	}

	var report bigquery.SellInReturnsReport
	if cached, ok := h.bqRepo.(sellInReturnsProvider); ok {
		report = cached.GetSellInReturnsCached(r.Context(), tenantID, filter)
	} else {
		// Fallback for non-Client repositories: unsorted year rows + aggregate.
		recs, _, err := h.bqRepo.GetSellInRecords(r.Context(), tenantID, bigquery.SellInRecordFilter{
			RetailerChain: filter.Chain,
			Year:          filter.Year,
			Limit:         0,
		})
		if err != nil {
			http.Error(w, `{"error":"failed to query sell-in records"}`, http.StatusInternalServerError)
			return
		}
		report = bigquery.AggregateSellInReturns(recs, filter)
	}

	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(report)
}
