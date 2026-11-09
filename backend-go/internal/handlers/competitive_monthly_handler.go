package handlers

import (
	"context"
	"encoding/json"
	"log"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/tashil/data-sharing/backend/internal/domain"
	"github.com/tashil/data-sharing/backend/internal/middleware"
	"github.com/tashil/data-sharing/backend/internal/service/bigquery"
	"github.com/tashil/data-sharing/backend/internal/service/bqsink"
)

// competitiveMonthlyTimeout bounds the BigQuery Compare aggregate; past it we use in-memory facts.
const competitiveMonthlyTimeout = 12 * time.Second

// WithCompetitiveMonthlyQuerier enables the BigQuery path for Compare aggregates.
func (h *AnalyticsHandler) WithCompetitiveMonthlyQuerier(q bqsink.CompetitiveMonthlyQuerier) *AnalyticsHandler {
	h.competitiveMonthly = q
	return h
}

// HandleCompetitiveMonthly serves GET /api/v1/analytics/competitive-monthly:
// per-barcode × month weighted average prices/units for the Compare page in one response
// (replaces client-side paging of /analytics/records).
// Query: year, chain, supplier (default all_market).
func (h *AnalyticsHandler) HandleCompetitiveMonthly(w http.ResponseWriter, r *http.Request) {
	tenantID, err := middleware.EnforceTenantRLS(r)
	if err != nil {
		http.Error(w, `{"error":"unauthorized tenant context"}`, http.StatusUnauthorized)
		return
	}
	q := r.URL.Query()
	year, _ := strconv.Atoi(q.Get("year"))
	if year <= 0 {
		year = time.Now().Year()
	}
	chain := q.Get("chain")
	supplier := q.Get("supplier")
	if strings.TrimSpace(supplier) == "" {
		supplier = "all_market"
	}
	if claims, ok := middleware.GetUserClaims(r.Context()); ok && claims != nil {
		if claims.Role == domain.RoleChainKAM && strings.TrimSpace(claims.AssignedChain) != "" {
			chain = strings.TrimSpace(claims.AssignedChain)
		}
	}
	start, end := bigquery.CompetitiveMonthlyYearWindow(year)

	if h.competitiveMonthly != nil {
		c, cancel := context.WithTimeout(r.Context(), competitiveMonthlyTimeout)
		defer cancel()
		res, err := h.competitiveMonthly.QueryCompetitiveMonthly(c, bqsink.RecordsQuery{
			TenantID: tenantID, Chain: chain, Supplier: supplier, StartDate: start, EndDate: end,
		})
		if err == nil && res != nil && (len(res.Items) > 0 || len(res.Months) > 0) {
			res.Year = year
			if res.Source == "" {
				res.Source = "bigquery"
			}
			setRecordsSource(w, res.Source)
			w.Header().Set("Content-Type", "application/json")
			_ = json.NewEncoder(w).Encode(res)
			return
		}
		if err != nil {
			log.Printf("WARN [competitive-monthly] BigQuery path failed, serving from memory: %v", err)
		}
	}

	filter := bigquery.RecordFilter{
		RetailerChain: chain,
		Supplier:      supplier,
		StartDate:     start,
		EndDate:       end,
	}
	var res bigquery.CompetitiveMonthlyResult
	if c, ok := h.bqRepo.(*bigquery.Client); ok {
		res = c.CompetitiveMonthly(tenantID, filter)
	} else {
		facts, _, err := h.bqRepo.GetSellOutRecords(r.Context(), tenantID, filter)
		if err != nil {
			http.Error(w, `{"error":"failed to query sell out records"}`, http.StatusInternalServerError)
			return
		}
		res = bigquery.AggregateCompetitiveMonthly(facts, tenantID, filter)
		res.Source = "memory"
	}
	res.Year = year
	setRecordsSource(w, "memory")
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(res)
}
