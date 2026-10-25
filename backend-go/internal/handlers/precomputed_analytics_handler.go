package handlers

import (
	"context"
	"net/http"
	"strconv"
	"strings"

	"github.com/tashil/data-sharing/backend/internal/domain"
	"github.com/tashil/data-sharing/backend/internal/middleware"
	"github.com/tashil/data-sharing/backend/internal/service/bigquery"
)

// precomputedAnalytics is implemented by the in-memory BigQuery client (materialized layer).
type precomputedAnalytics interface {
	GetCPFRDashboardCached(ctx context.Context, tenantID string, filter bigquery.CPFRFilter) (*domain.CPFRDashboardPayload, int64, error)
	GetAnalyticsAggregates(ctx context.Context, tenantID string) (*domain.AnalyticsAggregates, error)
}

// HandleGetAnalyticsAggregates serves GET /api/v1/analytics/aggregates?table=&chain=
// table: agg_chain_profit_monthly | agg_sku_cost_margin | agg_sell_through (empty = all three).
// chain: optional chain key, "all" = all-chains totals rows.
// The response carries version and updated_at of the precomputed layer.
func (h *AnalyticsHandler) HandleGetAnalyticsAggregates(w http.ResponseWriter, r *http.Request) {
	tenantID, err := middleware.EnforceTenantRLS(r)
	if err != nil {
		writeErr(w, http.StatusUnauthorized, "unauthorized tenant context")
		return
	}
	pre, ok := h.bqRepo.(precomputedAnalytics)
	if !ok {
		writeErr(w, http.StatusNotImplemented, "precomputed analytics unavailable")
		return
	}
	agg, err := pre.GetAnalyticsAggregates(r.Context(), tenantID)
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "failed to compute analytics aggregates")
		return
	}
	q := r.URL.Query()
	table := strings.TrimSpace(q.Get("table"))
	chain := strings.ToLower(strings.TrimSpace(q.Get("chain")))
	keep := func(c string) bool { return chain == "" || strings.EqualFold(c, chain) }

	out := map[string]interface{}{
		"tenant_id":  agg.TenantID,
		"version":    agg.Version,
		"updated_at": agg.UpdatedAt,
	}
	if table == "" || table == "agg_chain_profit_monthly" {
		rows := []domain.AggChainProfitMonthly{}
		for _, x := range agg.ChainProfitMonthly {
			if keep(x.Chain) {
				rows = append(rows, x)
			}
		}
		out["agg_chain_profit_monthly"] = rows
	}
	if table == "" || table == "agg_sku_cost_margin" {
		rows := []domain.AggSkuCostMargin{}
		for _, x := range agg.SkuCostMargin {
			if keep(x.Chain) {
				rows = append(rows, x)
			}
		}
		out["agg_sku_cost_margin"] = rows
	}
	if table == "" || table == "agg_sell_through" {
		rows := []domain.AggSellThrough{}
		for _, x := range agg.SellThrough {
			if keep(x.Chain) {
				rows = append(rows, x)
			}
		}
		out["agg_sell_through"] = rows
	}
	if len(out) == 3 {
		writeErr(w, http.StatusBadRequest, "unknown table")
		return
	}
	w.Header().Set("X-Analytics-Version", strconv.FormatInt(agg.Version, 10))
	writeJSON(w, http.StatusOK, out)
}
