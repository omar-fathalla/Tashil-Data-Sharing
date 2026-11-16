package bqsink

import (
	"context"
	"fmt"
	"strings"

	"cloud.google.com/go/bigquery"
	"google.golang.org/api/iterator"

	"github.com/tashil/data-sharing/backend/internal/service/targetalloc"
)

// TargetBreakdownQuerier hands out BigQuery-backed sources for the target breakdown endpoint.
type TargetBreakdownQuerier interface {
	TargetBreakdownSource(tenantID, chain string) targetalloc.Source
}

type targetBreakdownRow struct {
	StoreKey       string  `bigquery:"store_key"`
	StoreID        string  `bigquery:"store_id"`
	StoreName      string  `bigquery:"store_name"`
	SKUKey         string  `bigquery:"sku_key"`
	SKUName        string  `bigquery:"sku_name"`
	Category       string  `bigquery:"category"`
	UnitsPerCarton int64   `bigquery:"units_per_carton"`
	BaseRev        float64 `bigquery:"base_rev"`
	BaseUnits      int64   `bigquery:"base_units"`
	ActRev         float64 `bigquery:"act_rev"`
	ActUnits       int64   `bigquery:"act_units"`
	ActRows        int64   `bigquery:"act_rows"`
}

// TargetCoverageSQL counts Sell-Out rows per calendar month over the filtered serving view.
func TargetCoverageSQL(tableRef, where string) string {
	base := "WITH m AS (SELECT * FROM (" + servingView(tableRef) + ") WHERE " + where + ")"
	return base + " SELECT SUBSTR(transaction_date, 1, 7) month_key, COUNT(*) n FROM m" +
		" WHERE LENGTH(IFNULL(transaction_date, '')) >= 7 GROUP BY 1 ORDER BY 1"
}

const (
	inBaselineSQL = "transaction_date BETWEEN @b_start AND @b_end"
	inActualSQL   = "transaction_date BETWEEN @a_start AND @a_end"
)

// TargetBreakdownSQL sums net revenue and units per (branch, SKU, category, SKU name) for the baseline
// and the actual window in one pass over the filtered serving view (same dedup key as every Sell-Out read).
// Read-only: no DML, no change to the serving view.
func TargetBreakdownSQL(tableRef, where string) string {
	base := "WITH m AS (SELECT * FROM (" + servingView(tableRef) + ") WHERE " + where +
		" AND LENGTH(IFNULL(transaction_date, '')) >= 10 AND ((" + inBaselineSQL + ") OR (" + inActualSQL + ")))"
	return base + " SELECT IFNULL(" + storeKeySQL + ", '') store_key, IFNULL(MAX(store_id), '') store_id," +
		" IFNULL(ARRAY_AGG(NULLIF(store_name, '') IGNORE NULLS ORDER BY transaction_date DESC LIMIT 1)[SAFE_OFFSET(0)], '') store_name," +
		" IFNULL(" + groupKeySQL + ", '') sku_key, IFNULL(sku_name, '') sku_name, IFNULL(category, '') category," +
		" IFNULL(MAX(IF(units_per_carton > 0, units_per_carton, NULL)), 0) units_per_carton," +
		" IFNULL(SUM(IF(" + inBaselineSQL + ", net_revenue, 0)), 0) base_rev," +
		" IFNULL(SUM(IF(" + inBaselineSQL + ", quantity_sold, 0)), 0) base_units," +
		" IFNULL(SUM(IF(" + inActualSQL + ", net_revenue, 0)), 0) act_rev," +
		" IFNULL(SUM(IF(" + inActualSQL + ", quantity_sold, 0)), 0) act_units," +
		" COUNTIF(" + inActualSQL + ") act_rows" +
		" FROM m GROUP BY 1, 4, 5, 6"
}

type bqTargetSource struct {
	s        *BigQuerySink
	tenantID string
	chain    string
}

// TargetBreakdownSource implements TargetBreakdownQuerier.
func (s *BigQuerySink) TargetBreakdownSource(tenantID, chain string) targetalloc.Source {
	return &bqTargetSource{s: s, tenantID: tenantID, chain: chain}
}

func (b *bqTargetSource) filter() (string, []bigquery.QueryParameter) {
	return RecordsFilterSQL(RecordsQuery{TenantID: b.tenantID, Chain: b.chain})
}

func isMissingTable(err error) bool {
	return err != nil && (strings.Contains(err.Error(), "notFound") || strings.Contains(err.Error(), "Not found: Table"))
}

func (b *bqTargetSource) Coverage(ctx context.Context) ([]targetalloc.MonthCoverage, error) {
	where, params := b.filter()
	q := b.s.client.Query(TargetCoverageSQL(b.s.ref(TableSellOut), where))
	q.Parameters = params
	it, err := q.Read(ctx)
	if err != nil {
		if isMissingTable(err) {
			return nil, nil
		}
		return nil, fmt.Errorf("target coverage: %w", err)
	}
	var out []targetalloc.MonthCoverage
	for {
		var row struct {
			MonthKey string `bigquery:"month_key"`
			N        int64  `bigquery:"n"`
		}
		e := it.Next(&row)
		if e == iterator.Done {
			break
		}
		if e != nil {
			return nil, fmt.Errorf("target coverage: %w", e)
		}
		out = append(out, targetalloc.MonthCoverage{Month: row.MonthKey, Rows: row.N})
	}
	return out, nil
}

func (b *bqTargetSource) Rows(ctx context.Context, baseline, actual targetalloc.Window) ([]targetalloc.Row, error) {
	where, params := b.filter()
	q := b.s.client.Query(TargetBreakdownSQL(b.s.ref(TableSellOut), where))
	q.Parameters = append(params,
		bigquery.QueryParameter{Name: "b_start", Value: baseline.Start},
		bigquery.QueryParameter{Name: "b_end", Value: baseline.End},
		bigquery.QueryParameter{Name: "a_start", Value: actual.Start},
		bigquery.QueryParameter{Name: "a_end", Value: actual.End},
	)
	it, err := q.Read(ctx)
	if err != nil {
		return nil, fmt.Errorf("target breakdown: %w", err)
	}
	var out []targetalloc.Row
	for {
		var row targetBreakdownRow
		e := it.Next(&row)
		if e == iterator.Done {
			break
		}
		if e != nil {
			return nil, fmt.Errorf("target breakdown: %w", e)
		}
		out = append(out, targetalloc.Row(row))
	}
	return out, nil
}
