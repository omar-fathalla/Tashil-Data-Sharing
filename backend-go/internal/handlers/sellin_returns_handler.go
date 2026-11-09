package handlers

import (
	"encoding/json"
	"net/http"
	"strconv"
	"strings"

	"github.com/tashil/data-sharing/backend/internal/domain"
	"github.com/tashil/data-sharing/backend/internal/middleware"
	"github.com/tashil/data-sharing/backend/internal/service/bigquery"
)

// HandleSellInReturns serves GET /api/v1/analytics/sell-in-returns (Phase-1 المرتجعات report).
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

	// Load year-scoped rows (all months) so MoM / chart / advisories stay coherent.
	recs, _, err := h.bqRepo.GetSellInRecords(r.Context(), tenantID, bigquery.SellInRecordFilter{
		RetailerChain: filter.Chain,
		Year:          filter.Year,
		Limit:         0,
	})
	if err != nil {
		http.Error(w, `{"error":"failed to query sell-in records"}`, http.StatusInternalServerError)
		return
	}

	report := bigquery.AggregateSellInReturns(recs, filter)
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(report)
}
