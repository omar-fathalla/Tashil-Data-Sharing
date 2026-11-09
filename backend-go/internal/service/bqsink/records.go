package bqsink

import (
	"context"
	"fmt"
	"strings"
	"sync"
	"time"

	"cloud.google.com/go/bigquery"
	"google.golang.org/api/iterator"

	"github.com/tashil/data-sharing/backend/internal/domain"
)

// RecordsQuery is the SQL-expressible subset of the Sell-Out explorer filter. Search text still
// needs Go-side matching and is served from memory; category uses NormalizeProductCategory aliases.
type RecordsQuery struct {
	TenantID  string
	Chain     string
	Store     string
	Category  string
	Supplier  string
	StartDate string
	EndDate   string
	Limit     int
	Offset    int
}

// RecordsTotals are the KPI totals over every matched row.
type RecordsTotals struct {
	TotalCount          int     `bigquery:"total_count"`
	NetRevenue          float64 `bigquery:"net_revenue"`
	UnitsSold           int64   `bigquery:"units_sold"`
	CartonsSold         float64 `bigquery:"cartons_sold"`
	FactoryCost         float64 `bigquery:"factory_cost"`
	GrossProfit         float64 `bigquery:"gross_profit"`
	MatchedRevForMargin float64 `bigquery:"matched_rev"`
	Stores              int     `bigquery:"stores"`
	SKUs                int     `bigquery:"skus"`
	MatchedSKUs         int     `bigquery:"matched_skus"`
	MinDate             string  `bigquery:"min_date"`
	MaxDate             string  `bigquery:"max_date"`
	TopBranchName       string  `bigquery:"top_branch_name"`
	TopBranchRevenue    float64 `bigquery:"top_branch_revenue"`
}

// RecordsSKU is one SKU bucket (grouped by item code, else barcode, else name) before Go post-processing.
type RecordsSKU struct {
	ItemCode             string  `bigquery:"item_code"`
	Barcode              string  `bigquery:"barcode"`
	SKUName              string  `bigquery:"sku_name"`
	RetailerRawSKUName   string  `bigquery:"raw_name"`
	Category             string  `bigquery:"category"`
	ItemType             string  `bigquery:"item_type"`
	UnitsPerCarton       int     `bigquery:"units_per_carton"`
	RecommendedPrice     float64 `bigquery:"rsp"`
	CartonPriceInclVAT   float64 `bigquery:"carton_price"`
	FactoryUnitCost      float64 `bigquery:"factory_unit_cost"`
	NetCartonInvoiceCost float64 `bigquery:"net_carton_cost"`
	InvoiceDiscountPct   float64 `bigquery:"invoice_discount_pct"`
	UnitsSold            int64   `bigquery:"units_sold"`
	CartonsSold          float64 `bigquery:"cartons_sold"`
	NetRevenue           float64 `bigquery:"net_revenue"`
	FactoryCost          float64 `bigquery:"factory_cost"`
	GrossProfit          float64 `bigquery:"gross_profit"`
	Stores               int     `bigquery:"stores"`
}

// RecordsResult is the BigQuery answer for one explorer request.
type RecordsResult struct {
	Totals   RecordsTotals
	SKUs     []RecordsSKU
	Page     []domain.SellOutFact
	Duration time.Duration
}

// RecordsQuerier is implemented by sinks that can aggregate Sell-Out records in BigQuery.
type RecordsQuerier interface {
	QuerySellOutRecords(ctx context.Context, q RecordsQuery) (*RecordsResult, error)
}

func isAllValue(s string) bool {
	s = strings.TrimSpace(s)
	return s == "" || strings.EqualFold(s, "all") || s == "الكل"
}

// RecordsFilterSQL returns the WHERE clause (over the serving view) and parameters, mirroring the
// in-memory GetSellOutRecords filter: own SKUs by default, chain equality, loose store match, dates.
func RecordsFilterSQL(q RecordsQuery) (string, []bigquery.QueryParameter) {
	conds := []string{"TRUE"}
	params := []bigquery.QueryParameter{{Name: "tenant_id", Value: NormalizeTenant(q.TenantID)}}
	sup := strings.TrimSpace(q.Supplier)
	switch {
	case sup == "" || strings.EqualFold(sup, "own") || sup == "أصناف الشركة فقط":
		conds = append(conds, "(IFNULL(is_own_brand, FALSE) OR TRIM(IFNULL(supplier, '')) = '')")
	case strings.EqualFold(sup, "all") || strings.EqualFold(sup, "all_market") || sup == "الكل" || sup == "السوق الكامل (شامل المنافسين)":
	default:
		conds = append(conds, "LOWER(TRIM(IFNULL(supplier, ''))) = LOWER(@supplier)")
		params = append(params, bigquery.QueryParameter{Name: "supplier", Value: sup})
	}
	if !isAllValue(q.Chain) {
		conds = append(conds, "LOWER(IFNULL(retailer_chain, '')) = LOWER(@chain)")
		params = append(params, bigquery.QueryParameter{Name: "chain", Value: q.Chain})
	}
	if !isAllValue(q.Store) {
		conds = append(conds, "(IFNULL(store_id, '') = @store OR LOWER(IFNULL(store_name, '')) = LOWER(@store)"+
			" OR STRPOS(IFNULL(store_name, ''), @store) > 0 OR STRPOS(@store, IFNULL(store_id, '')) > 0)")
		params = append(params, bigquery.QueryParameter{Name: "store", Value: strings.TrimSpace(q.Store)})
	}
	if !isAllValue(q.Category) {
		cats := domain.ProductCategoryMatchValues(q.Category)
		if len(cats) == 0 {
			cats = []string{strings.TrimSpace(q.Category)}
		}
		conds = append(conds, "REGEXP_REPLACE(TRIM(IFNULL(category, '')), r'\\s+', ' ') IN UNNEST(@categories)")
		params = append(params, bigquery.QueryParameter{Name: "categories", Value: cats})
	}
	if q.StartDate != "" {
		conds = append(conds, "transaction_date >= @start_date")
		params = append(params, bigquery.QueryParameter{Name: "start_date", Value: q.StartDate})
	}
	if q.EndDate != "" {
		conds = append(conds, "transaction_date <= @end_date")
		params = append(params, bigquery.QueryParameter{Name: "end_date", Value: q.EndDate})
	}
	return strings.Join(conds, " AND "), params
}

// servingView is the Sell-Out serving view (SellOutReadSQL without its ORDER BY).
func servingView(tableRef string) string {
	s := SellOutReadSQL(tableRef)
	return s[:strings.LastIndex(s, " ORDER BY ")]
}

const (
	storeKeySQL = "COALESCE(NULLIF(store_id, ''), NULLIF(store_name, ''))"
	skuKeySQL   = "COALESCE(NULLIF(barcode, ''), NULLIF(item_code, ''), NULLIF(sku_name, ''))"
	groupKeySQL = "COALESCE(NULLIF(item_code, ''), NULLIF(barcode, ''), NULLIF(sku_name, ''))"
	recordOrder = "transaction_date DESC, net_revenue DESC"
)

// RecordsSQL builds the totals, SKU-summary and page queries over the filtered serving view.
func RecordsSQL(tableRef, where string) (totals, skus, page string) {
	base := "WITH m AS (SELECT * FROM (" + servingView(tableRef) + ") WHERE " + where + ")"
	totals = base + ", br AS (SELECT " + storeKeySQL + " k, SUM(net_revenue) rev," +
		" ARRAY_AGG(NULLIF(store_name, '') IGNORE NULLS LIMIT 1)[SAFE_OFFSET(0)] nm FROM m WHERE " + storeKeySQL + " IS NOT NULL GROUP BY 1)" +
		" SELECT COUNT(*) total_count, IFNULL(SUM(net_revenue), 0) net_revenue, IFNULL(SUM(quantity_sold), 0) units_sold," +
		" IFNULL(SUM(cartons_sold), 0) cartons_sold," +
		" IFNULL(SUM(IF(total_factory_cost > 0, total_factory_cost, 0)), 0) factory_cost," +
		" IFNULL(SUM(IF(total_factory_cost > 0, retailer_gross_profit, 0)), 0) gross_profit," +
		" IFNULL(SUM(IF(total_factory_cost > 0, net_revenue, 0)), 0) matched_rev," +
		" COUNT(DISTINCT " + storeKeySQL + ") stores, COUNT(DISTINCT " + skuKeySQL + ") skus," +
		" COUNT(DISTINCT IF(IFNULL(item_code, '') != '', " + skuKeySQL + ", NULL)) matched_skus," +
		" IFNULL(MIN(NULLIF(transaction_date, '')), '') min_date, IFNULL(MAX(NULLIF(transaction_date, '')), '') max_date," +
		" IFNULL((SELECT IFNULL(nm, k) FROM br WHERE rev > 0 ORDER BY rev DESC LIMIT 1), '') top_branch_name," +
		" IFNULL((SELECT rev FROM br WHERE rev > 0 ORDER BY rev DESC LIMIT 1), 0) top_branch_revenue FROM m"
	first := func(expr string) string {
		return "IFNULL(ARRAY_AGG(" + expr + " IGNORE NULLS ORDER BY " + recordOrder + " LIMIT 1)[SAFE_OFFSET(0)], "
	}
	skus = base + " SELECT " +
		first("NULLIF(item_code, '')") + "'') item_code, " +
		first("NULLIF(barcode, '')") + "'') barcode, " +
		"IFNULL(ARRAY_AGG(IFNULL(sku_name, '') ORDER BY " + recordOrder + " LIMIT 1)[SAFE_OFFSET(0)], '') sku_name, " +
		"IFNULL(ARRAY_AGG(COALESCE(NULLIF(retailer_raw_sku_name, ''), sku_name, '') ORDER BY " + recordOrder + " LIMIT 1)[SAFE_OFFSET(0)], '') raw_name, " +
		"IFNULL(ARRAY_AGG(IFNULL(category, '') ORDER BY " + recordOrder + " LIMIT 1)[SAFE_OFFSET(0)], '') category, " +
		"IFNULL(ARRAY_AGG(IFNULL(item_type, '') ORDER BY " + recordOrder + " LIMIT 1)[SAFE_OFFSET(0)], '') item_type, " +
		first("IF(units_per_carton > 0, units_per_carton, NULL)") + "0) units_per_carton, " +
		first("IF(recommended_price > 0, recommended_price, NULL)") + "0) rsp, " +
		first("IF(carton_price_incl_vat > 0, carton_price_incl_vat, NULL)") + "0) carton_price, " +
		first("IF(factory_unit_cost > 0, factory_unit_cost, NULL)") + "0) factory_unit_cost, " +
		first("IF(net_carton_invoice_cost > 0, net_carton_invoice_cost, NULL)") + "0) net_carton_cost, " +
		"IFNULL(ARRAY_AGG(IFNULL(invoice_discount_pct, 0) ORDER BY " + recordOrder + " LIMIT 1)[SAFE_OFFSET(0)], 0) invoice_discount_pct, " +
		"IFNULL(SUM(quantity_sold), 0) units_sold, IFNULL(SUM(cartons_sold), 0) cartons_sold, IFNULL(SUM(net_revenue), 0) net_revenue, " +
		"IFNULL(SUM(total_factory_cost), 0) factory_cost, IFNULL(SUM(retailer_gross_profit), 0) gross_profit, " +
		"COUNT(DISTINCT " + storeKeySQL + ") stores FROM m WHERE " + groupKeySQL + " IS NOT NULL GROUP BY " + groupKeySQL
	page = base + " SELECT * FROM m ORDER BY " + recordOrder + ", record_id LIMIT @limit OFFSET @offset"
	return totals, skus, page
}

// QuerySellOutRecords runs the three explorer queries in parallel.
func (s *BigQuerySink) QuerySellOutRecords(ctx context.Context, rq RecordsQuery) (*RecordsResult, error) {
	start := time.Now()
	where, params := RecordsFilterSQL(rq)
	totalsSQL, skusSQL, pageSQL := RecordsSQL(s.ref(TableSellOut), where)
	run := func(sql string, extra ...bigquery.QueryParameter) (*bigquery.RowIterator, error) {
		q := s.client.Query(sql)
		q.Parameters = append(append([]bigquery.QueryParameter{}, params...), extra...)
		return q.Read(ctx)
	}
	res := &RecordsResult{}
	var wg sync.WaitGroup
	errs := make([]error, 3)
	wg.Add(3)
	go func() {
		defer wg.Done()
		it, err := run(totalsSQL)
		if err == nil {
			err = it.Next(&res.Totals)
		}
		errs[0] = err
	}()
	go func() {
		defer wg.Done()
		it, err := run(skusSQL)
		for err == nil {
			var row RecordsSKU
			if e := it.Next(&row); e == iterator.Done {
				break
			} else if e != nil {
				err = e
				break
			}
			res.SKUs = append(res.SKUs, row)
		}
		errs[1] = err
	}()
	go func() {
		defer wg.Done()
		limit, offset := rq.Limit, rq.Offset
		if limit <= 0 {
			limit = 50
		}
		if offset < 0 {
			offset = 0
		}
		it, err := run(pageSQL, bigquery.QueryParameter{Name: "limit", Value: limit}, bigquery.QueryParameter{Name: "offset", Value: offset})
		for err == nil {
			var row map[string]bigquery.Value
			if e := it.Next(&row); e == iterator.Done {
				break
			} else if e != nil {
				err = e
				break
			}
			f, derr := DecodeSellOutRow(row)
			if derr != nil {
				err = derr
				break
			}
			res.Page = append(res.Page, f)
		}
		errs[2] = err
	}()
	wg.Wait()
	for i, err := range errs {
		if err != nil {
			return nil, fmt.Errorf("records query %d: %w", i, err)
		}
	}
	res.Duration = time.Since(start)
	return res, nil
}
