package ingestion

import (
	"context"
	"strings"

	"github.com/tashil/data-sharing/backend/internal/domain"
	"github.com/tashil/data-sharing/backend/internal/service/bigquery"
)

// maxPeriodYM returns the latest YYYY-MM among facts, optionally limited to one retail chain.
// Empty chain matches all chains. Facts without a usable TransactionDate are ignored.
func maxPeriodYM(facts []domain.SellOutFact, chain string) string {
	chain = strings.ToLower(strings.TrimSpace(chain))
	max := ""
	for _, f := range facts {
		if chain != "" && !strings.EqualFold(strings.TrimSpace(f.RetailerChain), chain) {
			continue
		}
		if len(f.TransactionDate) < 7 {
			continue
		}
		ym := f.TransactionDate[:7]
		if ym > max {
			max = ym
		}
	}
	return max
}

// shouldReplaceOOSAlerts is true when the upload's latest period is at least as new as
// the latest period already stored for the tenant/chain. OOS alerts must always reflect
// the latest available period — a historical file must not wipe newer alerts.
//
// Rules:
//   - no stored period → replace (first data or empty tenant/chain)
//   - upload period unknown → keep existing alerts (do not risk stale replace)
//   - uploadPeriod >= storedPeriod → replace (string compare works for YYYY-MM)
func shouldReplaceOOSAlerts(uploadPeriod, storedPeriod string) bool {
	if storedPeriod == "" {
		return true
	}
	if uploadPeriod == "" {
		return false
	}
	return uploadPeriod >= storedPeriod
}

// latestStoredSellOutPeriod returns YYYY-MM of the newest Sell-Out fact for tenant/chain.
func (p *Processor) latestStoredSellOutPeriod(ctx context.Context, tenantID, chain string) string {
	if p.bqRepo == nil {
		return ""
	}
	// Sorted newest-first; Limit 1 is enough for the max period key.
	recs, _, err := p.bqRepo.GetSellOutRecords(ctx, tenantID, bigquery.RecordFilter{
		RetailerChain: chain,
		Limit:         1,
	})
	if err != nil || len(recs) == 0 {
		return ""
	}
	return maxPeriodYM(recs[:1], chain)
}
