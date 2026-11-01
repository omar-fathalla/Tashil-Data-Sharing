package handlers

import (
	"encoding/json"
	"fmt"
	"math"
	"net/http"
	"sort"
	"strconv"
	"strings"

	"github.com/tashil/data-sharing/backend/internal/domain"
	"github.com/tashil/data-sharing/backend/internal/middleware"
	"github.com/tashil/data-sharing/backend/internal/service/bigquery"
)

// SellInMonthlyChainPoint is one month's net Sell-In value (EGP, excl. VAT) for one retail chain.
type SellInMonthlyChainPoint struct {
	MonthKey      string  `json:"month_key"` // YYYY-MM
	RetailerChain string  `json:"retailer_chain"`
	NetValueEGP   float64 `json:"net_value_egp"`
}

// SellInMonthlyResponse is the payload of GET /api/v1/analytics/sell-in-monthly.
type SellInMonthlyResponse struct {
	Points []SellInMonthlyChainPoint `json:"points"`
}

// HandleSellInMonthly serves GET /api/v1/analytics/sell-in-monthly: net Sell-In totals per month and
// chain, used to draw Sell-In next to Sell-Out in the monthly trend chart. Optional filters: year, chain.
// Chain KAM users are restricted to their assigned chain.
func (h *AnalyticsHandler) HandleSellInMonthly(w http.ResponseWriter, r *http.Request) {
	tenantID, err := middleware.EnforceTenantRLS(r)
	if err != nil {
		http.Error(w, `{"error":"unauthorized tenant context"}`, http.StatusUnauthorized)
		return
	}
	q := r.URL.Query()
	year, _ := strconv.Atoi(q.Get("year"))
	filter := bigquery.SellInRecordFilter{RetailerChain: q.Get("chain"), Year: year}
	if claims, ok := middleware.GetUserClaims(r.Context()); ok && claims != nil {
		if claims.Role == domain.RoleChainKAM && strings.TrimSpace(claims.AssignedChain) != "" {
			filter.RetailerChain = strings.TrimSpace(claims.AssignedChain)
		}
	}
	records, _, err := h.bqRepo.GetSellInRecords(r.Context(), tenantID, filter)
	if err != nil {
		http.Error(w, `{"error":"failed to query sell-in records"}`, http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(SellInMonthlyResponse{Points: aggregateSellInMonthly(records)})
}

func aggregateSellInMonthly(records []domain.SellInRecord) []SellInMonthlyChainPoint {
	type key struct{ month, chain string }
	sums := make(map[key]float64)
	for _, rec := range records {
		if rec.Year <= 0 || rec.MonthNum < 1 || rec.MonthNum > 12 {
			continue
		}
		chain := strings.ToLower(strings.TrimSpace(rec.RetailerChain))
		if chain == "" {
			continue
		}
		sums[key{fmt.Sprintf("%04d-%02d", rec.Year, rec.MonthNum), chain}] += rec.NetValueEGP
	}
	points := make([]SellInMonthlyChainPoint, 0, len(sums))
	for k, v := range sums {
		points = append(points, SellInMonthlyChainPoint{MonthKey: k.month, RetailerChain: k.chain, NetValueEGP: math.Round(v*100) / 100})
	}
	sort.Slice(points, func(i, j int) bool {
		if points[i].MonthKey != points[j].MonthKey {
			return points[i].MonthKey < points[j].MonthKey
		}
		return points[i].RetailerChain < points[j].RetailerChain
	})
	return points
}
