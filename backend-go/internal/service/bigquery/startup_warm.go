package bigquery

import (
	"context"
	"log"
	"time"
)

// WarmCommonTenantAnalytics precomputes hot paths after durable-store load so the
// first user requests after a cold Cloud Run start do not rebuild empty caches
// on the request path (a single instance can be starved by sell-in-returns).
//
// Call from startup loadData / OnRebuilt after SyncDurableFromStore — off the
// HTTP request path. Safe to call repeatedly; cache keys include source version.
func (c *Client) WarmCommonTenantAnalytics(ctx context.Context, tenants []string) {
	if len(tenants) == 0 {
		return
	}
	start := time.Now()
	year := time.Now().Year()
	years := []int{year}
	// Early in the calendar year, also warm prior year (common explorer default).
	if time.Now().Month() <= 3 {
		years = append(years, year-1)
	}

	for _, tenant := range tenants {
		for _, period := range []string{"YTD", "MTD"} {
			if _, err := c.GetExecutiveKPIs(ctx, tenant, period); err != nil {
				log.Printf("WARN [startup-warm] executive KPIs tenant=%s period=%s: %v", tenant, period, err)
			}
		}
		for _, y := range years {
			_ = c.GetSellInReturnsCached(ctx, tenant, SellInReturnsFilter{Year: y})
		}
	}
	log.Printf("[startup-warm] tenants=%v years=%v done in %s", tenants, years, time.Since(start).Round(time.Millisecond))
}
