package ingestion

import (
	"context"
	"fmt"
	"strings"

	"github.com/tashil/data-sharing/backend/internal/domain"
	"github.com/tashil/data-sharing/backend/internal/service/bqsink"
)

type tenantLister interface {
	ListTenants(ctx context.Context) ([]domain.Tenant, error)
}

// ErrWildcardPurgeRefused is returned when PurgeTenantData is called with tenantID "all"/"*".
// Global wipes must go through PurgeAllTenants, which is only invoked from the super_admin-gated
// clear handler (HandleClearData). The service layer does not see JWT roles, so this hard-refuse
// prevents accidental escalation from other callers.
var ErrWildcardPurgeRefused = fmt.Errorf("wildcard tenant purge refused: use PurgeAllTenants from a super_admin-gated caller")

// PurgeTenantData is the clear-tenant endpoint for a single tenant: it clears memory like
// ClearTenantData and also deletes the tenant's durable Sell-In / Sell-Out rows in BigQuery and
// bumps their versions, so other instances clear too and a restart does not bring the data back.
//
// tenantID "all" / "*" is refused here — call PurgeAllTenants after a super_admin role check.
// Startup and tooling must keep using ClearTenantData (memory only).
func (p *Processor) PurgeTenantData(ctx context.Context, tenantID string) error {
	clean := strings.ToLower(strings.TrimSpace(tenantID))
	if clean == "all" || clean == "*" {
		return ErrWildcardPurgeRefused
	}
	return p.purgeTenantData(ctx, tenantID)
}

// PurgeAllTenants wipes every known tenant's memory + durable Sell-In/Sell-Out rows.
// Callers MUST enforce super_admin (see HandleClearData); this method does not check roles.
func (p *Processor) PurgeAllTenants(ctx context.Context) error {
	return p.purgeTenantData(ctx, "all")
}

func (p *Processor) purgeTenantData(ctx context.Context, tenantID string) error {
	if err := p.ClearTenantData(ctx, tenantID); err != nil {
		return err
	}
	if !p.sinkActive() {
		return nil
	}
	tenants := []string{tenantID}
	clean := strings.ToLower(strings.TrimSpace(tenantID))
	if clean == "all" || clean == "*" {
		seen := map[string]bool{"tenant-adeco": true}
		tenants = []string{"tenant-adeco"}
		if tl, ok := p.fsRepo.(tenantLister); ok {
			if list, err := tl.ListTenants(ctx); err == nil {
				for _, t := range list {
					n := bqsink.NormalizeTenant(t.ID)
					if !seen[n] {
						seen[n] = true
						tenants = append(tenants, n)
					}
				}
			}
		}
	}
	var failures []string
	for _, t := range tenants {
		c, cancel := sinkCtx(ctx)
		for _, kind := range []bqsink.Kind{bqsink.KindSellIn, bqsink.KindSellOut} {
			res := p.sink.DeleteTenant(c, kind, t)
			if res.Failed() {
				failures = append(failures, fmt.Sprintf("%s/%s: %s", t, kind, res.Error))
				continue
			}
			if kind == bqsink.KindSellIn {
				p.noteSellInWritten(ctx, t, res)
			} else {
				p.noteSellOutWritten(ctx, t, res)
			}
		}
		cancel()
	}
	if len(failures) > 0 {
		return fmt.Errorf("cleared in memory but BigQuery delete failed (data may return after restart): %s", strings.Join(failures, "; "))
	}
	return nil
}
