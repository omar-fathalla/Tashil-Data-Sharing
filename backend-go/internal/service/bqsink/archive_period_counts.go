package bqsink

import (
	"context"
	"fmt"
	"strings"

	"cloud.google.com/go/bigquery"
	"google.golang.org/api/iterator"
)

// PeriodMonthCount is the row count and net TO for one period_month of one archive.
type PeriodMonthCount struct {
	PeriodMonth string  // YYYY-MM
	Rows        int
	Net         float64 // SUM(net_value_egp)
}

// SellInArchivePeriodCounter reads per-period_month totals for one archived Sell-In file.
type SellInArchivePeriodCounter interface {
	SellInArchivePeriodCounts(ctx context.Context, tenantID, archiveID string) ([]PeriodMonthCount, error)
}

// SellInArchivePeriodCountsSQL groups sell_in_records by period_month for one archive_id.
func SellInArchivePeriodCountsSQL(tableRef string) string {
	return "SELECT IFNULL(period_month, '') period_month, COUNT(*) n, IFNULL(SUM(IFNULL(net_value_egp, 0)), 0) net" +
		" FROM " + tableRef +
		" WHERE tenant_id = @tenant_id AND archive_id = @archive_id" +
		" GROUP BY 1 ORDER BY 1"
}

// SellInArchivePeriodCounts returns BEFORE totals for one Sell-In archive (read-only).
func (s *BigQuerySink) SellInArchivePeriodCounts(ctx context.Context, tenantID, archiveID string) ([]PeriodMonthCount, error) {
	archiveID = strings.TrimSpace(archiveID)
	if archiveID == "" {
		return nil, fmt.Errorf("archive_id is required")
	}
	q := s.client.Query(SellInArchivePeriodCountsSQL(s.ref(TableSellIn)))
	q.Parameters = []bigquery.QueryParameter{
		{Name: "tenant_id", Value: NormalizeTenant(tenantID)},
		{Name: "archive_id", Value: archiveID},
	}
	it, err := q.Read(ctx)
	if err != nil {
		if strings.Contains(err.Error(), "notFound") || strings.Contains(err.Error(), "Not found: Table") {
			return nil, nil
		}
		return nil, fmt.Errorf("count sell-in archive periods: %w", err)
	}
	var out []PeriodMonthCount
	for {
		var row struct {
			PeriodMonth string  `bigquery:"period_month"`
			N           int64   `bigquery:"n"`
			Net         float64 `bigquery:"net"`
		}
		err := it.Next(&row)
		if err == iterator.Done {
			break
		}
		if err != nil {
			return nil, fmt.Errorf("count sell-in archive periods: %w", err)
		}
		out = append(out, PeriodMonthCount{PeriodMonth: row.PeriodMonth, Rows: int(row.N), Net: row.Net})
	}
	return out, nil
}
