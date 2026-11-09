package arabicqa

import (
	"strings"
	"time"

	"github.com/tashil/data-sharing/backend/internal/service/bigquery"
)

// sellInFilterForPeriod builds a Sell-In filter for full period-scoped aggregation.
// Limit=0 means "all matching rows" (see bigquery.Client.GetSellInRecords).
// TODAY is not handled here — Sell-In has month grain only; callers must mark it unsupported.
func sellInFilterForPeriod(period string, now time.Time) (bigquery.SellInRecordFilter, bool) {
	f := bigquery.SellInRecordFilter{Limit: 0, Offset: 0}
	switch strings.ToUpper(strings.TrimSpace(period)) {
	case "TODAY":
		return f, false
	case "ALL":
		// no year/month — entire tenant Sell-In history
	case "YTD":
		f.Year = now.Year()
	case "MTD":
		f.Year = now.Year()
		f.Month = int(now.Month())
	default:
		f.Year = now.Year()
		f.Month = int(now.Month())
	}
	return f, true
}
