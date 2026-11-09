package bqsink

import (
	"context"
	"fmt"
	"math"
	"sort"
	"strconv"
	"strings"
	"time"

	"cloud.google.com/go/bigquery"
	"google.golang.org/api/iterator"

	bqsvc "github.com/tashil/data-sharing/backend/internal/service/bigquery"
)

// CompetitiveMonthlyRow is one barcode × month aggregate from BigQuery.
type CompetitiveMonthlyRow struct {
	Barcode  string  `bigquery:"barcode"`
	MonthKey string  `bigquery:"month_key"`
	Revenue  float64 `bigquery:"revenue"`
	Units    int64   `bigquery:"units"`
}

// CompetitiveMonthlyQuerier aggregates Compare series in BigQuery (no raw row paging).
type CompetitiveMonthlyQuerier interface {
	QueryCompetitiveMonthly(ctx context.Context, q RecordsQuery) (*bqsvc.CompetitiveMonthlyResult, error)
	QuerySellOutMonths(ctx context.Context, tenantID string, year int) ([]int, error)
}

// CompetitiveMonthlySQL groups filtered sell-out rows by barcode and YYYY-MM.
func CompetitiveMonthlySQL(tableRef, where string) string {
	base := "WITH m AS (SELECT * FROM (" + servingView(tableRef) + ") WHERE " + where + ")"
	return base + " SELECT TRIM(IFNULL(barcode, '')) barcode," +
		" SUBSTR(transaction_date, 1, 7) month_key," +
		" IFNULL(SUM(IF(unit_price > 0, unit_price * quantity_sold, net_revenue)), 0) revenue," +
		" IFNULL(SUM(quantity_sold), 0) units" +
		" FROM m WHERE TRIM(IFNULL(barcode, '')) != '' AND LENGTH(IFNULL(transaction_date, '')) >= 7" +
		" GROUP BY 1, 2 ORDER BY 1, 2"
}

// SellOutMonthsSQL returns distinct calendar months (1..12) for a tenant/year from durable facts.
func SellOutMonthsSQL(tableRef string) string {
	base := "WITH m AS (SELECT * FROM (" + servingView(tableRef) + ") WHERE TRUE)"
	return base + " SELECT DISTINCT CAST(SUBSTR(transaction_date, 6, 2) AS INT64) month_num" +
		" FROM m WHERE LENGTH(IFNULL(transaction_date, '')) >= 7" +
		" AND (@year <= 0 OR STARTS_WITH(transaction_date, @year_prefix))" +
		" AND CAST(SUBSTR(transaction_date, 6, 2) AS INT64) BETWEEN 1 AND 12" +
		" ORDER BY 1"
}

// QueryCompetitiveMonthly runs the Compare aggregate in BigQuery.
func (s *BigQuerySink) QueryCompetitiveMonthly(ctx context.Context, rq RecordsQuery) (*bqsvc.CompetitiveMonthlyResult, error) {
	start := time.Now()
	where, params := RecordsFilterSQL(rq)
	sql := CompetitiveMonthlySQL(s.ref(TableSellOut), where)
	q := s.client.Query(sql)
	q.Parameters = params
	it, err := q.Read(ctx)
	if err != nil {
		return nil, err
	}
	byBarcode := map[string][]bqsvc.CompetitiveMonthPoint{}
	monthSet := map[int]bool{}
	for {
		var row CompetitiveMonthlyRow
		e := it.Next(&row)
		if e == iterator.Done {
			break
		}
		if e != nil {
			return nil, e
		}
		barcode := strings.TrimSpace(row.Barcode)
		if barcode == "" || len(row.MonthKey) < 7 {
			continue
		}
		mo, err := strconv.Atoi(row.MonthKey[5:7])
		if err != nil || mo < 1 || mo > 12 {
			continue
		}
		units := int(row.Units)
		price := 0.0
		if units > 0 {
			price = math.Round((row.Revenue/float64(units))*100) / 100
		} else {
			price = math.Round(row.Revenue*100) / 100
		}
		if price <= 0 && units <= 0 {
			continue
		}
		monthSet[mo] = true
		byBarcode[barcode] = append(byBarcode[barcode], bqsvc.CompetitiveMonthPoint{
			MonthKey:   row.MonthKey,
			Month:      mo,
			UnitPrice:  price,
			Units:      units,
			NetRevenue: math.Round(row.Revenue*100) / 100,
		})
	}
	months := make([]int, 0, len(monthSet))
	for m := range monthSet {
		months = append(months, m)
	}
	sort.Ints(months)
	barcodes := make([]string, 0, len(byBarcode))
	for b := range byBarcode {
		barcodes = append(barcodes, b)
	}
	sort.Strings(barcodes)
	items := make([]bqsvc.CompetitiveMonthlyItem, 0, len(barcodes))
	for _, b := range barcodes {
		items = append(items, bqsvc.CompetitiveMonthlyItem{Barcode: b, Months: byBarcode[b]})
	}
	year := 0
	if len(rq.StartDate) >= 4 {
		year, _ = strconv.Atoi(rq.StartDate[:4])
	}
	_ = start
	return &bqsvc.CompetitiveMonthlyResult{Year: year, Months: months, Items: items, Source: "bigquery"}, nil
}

// QuerySellOutMonths returns distinct Sell-Out months for tenant/year from BigQuery.
func (s *BigQuerySink) QuerySellOutMonths(ctx context.Context, tenantID string, year int) ([]int, error) {
	sql := SellOutMonthsSQL(s.ref(TableSellOut))
	q := s.client.Query(sql)
	prefix := ""
	if year > 0 {
		prefix = fmt.Sprintf("%04d-", year)
	}
	q.Parameters = []bigquery.QueryParameter{
		{Name: "tenant_id", Value: NormalizeTenant(tenantID)},
		{Name: "year", Value: year},
		{Name: "year_prefix", Value: prefix},
	}
	it, err := q.Read(ctx)
	if err != nil {
		return nil, err
	}
	var months []int
	for {
		var row struct {
			MonthNum int64 `bigquery:"month_num"`
		}
		e := it.Next(&row)
		if e == iterator.Done {
			break
		}
		if e != nil {
			return nil, e
		}
		m := int(row.MonthNum)
		if m >= 1 && m <= 12 {
			months = append(months, m)
		}
	}
	return months, nil
}
