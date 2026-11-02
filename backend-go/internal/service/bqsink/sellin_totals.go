package bqsink

import (
	"context"
	"fmt"
	"strconv"
	"strings"
	"sync"
	"time"

	"cloud.google.com/go/bigquery"
	"github.com/tashil/data-sharing/backend/internal/domain"
	"google.golang.org/api/iterator"
)

// SellInChainRule maps a normalized customer-name needle to a chain key (Stage B resolver).
type SellInChainRule struct {
	Needle string
	Chain  string
}

// SellInTotalsQuery filters the Sell-In serving view (latest batch per chain/month).
type SellInTotalsQuery struct {
	TenantID string
	Chain    string
	Year     int
	Month    int
	// Limit > 0 also returns that page of raw rows (ordered like GetSellInRecords) for Go-side enrichment.
	Limit  int
	Offset int
	// Rules are the active customer->chain rules, env rules first (same order as the Go resolver).
	Rules []SellInChainRule
}

// SellInTotals are the Sell-In KPI/waterfall sums, before the handler's rounding.
type SellInTotals struct {
	Count       int64   `bigquery:"cnt"`
	NetValue    float64 `bigquery:"net"`
	Cases       float64 `bigquery:"cases"`
	Units       int64   `bigquery:"units"`
	Tons        float64 `bigquery:"tons"`
	Expected    float64 `bigquery:"expected"`
	ListExcl    float64 `bigquery:"list_excl"`
	ListIncl    float64 `bigquery:"list_incl"`
	NetWithList float64 `bigquery:"net_with_list"`
	Discount    float64 `bigquery:"disc"`
	VAT         float64 `bigquery:"vat"`
	Gross       float64 `bigquery:"gross"`
	MatchedSKUs int64   `bigquery:"matched_skus"`
}

// SellInGroupRow is one (year, month, chain, brand) bucket of the same sums.
type SellInGroupRow struct {
	Year     int64   `bigquery:"year"`
	Month    int64   `bigquery:"month_num"`
	Chain    string  `bigquery:"chain"`
	Brand    string  `bigquery:"brand"`
	Count    int64   `bigquery:"cnt"`
	NetValue float64 `bigquery:"net"`
	Cases    float64 `bigquery:"cases"`
	Units    int64   `bigquery:"units"`
	ListExcl float64 `bigquery:"list_excl"`
	Discount float64 `bigquery:"disc"`
}

// SellInTotalsResult carries the totals, the grouped breakdown and the per-job stats.
type SellInTotalsResult struct {
	Totals   SellInTotals
	Groups   []SellInGroupRow
	Page     []domain.SellInRecord
	Duration time.Duration
	Jobs     []SellInJobStat
}

// SellInJobStat records BigQuery-side timing for one query.
type SellInJobStat struct {
	Name      string
	JobID     string
	CacheHit  bool
	ElapsedMS int64 // job end - job creation, from job statistics
	BytesProc int64
}

// sellInChainSQL resolves the chain like resolveSellInChainFromCustomer: only rows whose chain is
// empty or fathalla are remapped, by the first rule whose needle occurs in the normalized name.
func sellInChainSQL(rules []SellInChainRule) (string, []bigquery.QueryParameter) {
	norm := "REGEXP_REPLACE(TRIM(TRANSLATE(IFNULL(customer_name, ''), 'أإآةى', 'اااهي')), r'\\s+', ' ')"
	cur := "LOWER(TRIM(IFNULL(retailer_chain, '')))"
	var b strings.Builder
	var params []bigquery.QueryParameter
	b.WriteString("CASE WHEN " + cur + " IN ('', 'fathalla') THEN CASE")
	n := 0
	for _, r := range rules {
		if strings.TrimSpace(r.Needle) == "" || strings.TrimSpace(r.Chain) == "" {
			continue
		}
		nn, cn := "cn"+strconv.Itoa(n), "cc"+strconv.Itoa(n)
		b.WriteString(" WHEN STRPOS(" + norm + ", @" + nn + ") > 0 THEN @" + cn)
		params = append(params, bigquery.QueryParameter{Name: nn, Value: r.Needle},
			bigquery.QueryParameter{Name: cn, Value: strings.ToLower(strings.TrimSpace(r.Chain))})
		n++
	}
	b.WriteString(" ELSE NULLIF(" + cur + ", '') END ELSE " + cur + " END")
	return "IFNULL(" + b.String() + ", 'fathalla')", params
}

// SellInTotalsSQL builds the derived-row CTE (Stage B per-row math) plus the totals and grouped queries.
func SellInTotalsSQL(tableRef string, q SellInTotalsQuery) (totals, groups, page string, params []bigquery.QueryParameter) {
	s := SellInReadSQL(tableRef)
	view := s[:strings.LastIndex(s, " ORDER BY ")]
	chainExpr, params := sellInChainSQL(q.Rules)
	params = append([]bigquery.QueryParameter{{Name: "tenant_id", Value: NormalizeTenant(q.TenantID)}}, params...)

	// Mirrors enrichSellInRecordLocked over the stored (write-time enriched) prices.
	base := "WITH v AS (" + view + ")," +
		" a AS (SELECT *, " + chainExpr + " AS chain_r," +
		" IF(IFNULL(units_per_carton, 0) > 0, units_per_carton, 12) AS upc," +
		" (IFNULL(item_code, '') != '' AND IFNULL(pricing_wave_status, '') != 'unmatched') AS matched," +
		" IFNULL(net_qty_cases, 0) AS q0, IFNULL(net_value_egp, 0) AS net0," +
		" IFNULL(official_unit_excl_vat_egp, 0) AS unit_px, IFNULL(official_carton_excl_vat_egp, 0) AS carton_px FROM v)," +
		" b AS (SELECT *, (matched AND upc > 1 AND unit_px > 0 AND carton_px > 0 AND ABS(q0) >= 0.001 AND ABS(net0) >= 0.01" +
		" AND ABS(LN(ABS(net0 / q0) / unit_px)) < ABS(LN(ABS(net0 / q0) / carton_px))) AS pcs," +
		" IF(matched AND IFNULL(vat_rate, 0) > 0, vat_rate, 0.14) AS vr FROM a)," +
		" c AS (SELECT *, IF(pcs, ROUND(q0 / upc, 4), q0) AS q FROM b)," +
		" d AS (SELECT *, CAST(ROUND(q * upc) AS INT64) AS units_r," +
		" ROUND(net0 * (1 + vr), 2) AS gross_r," +
		" IF(carton_px > 0 AND ABS(q) > 0.001, ROUND(q * carton_px, 2), IFNULL(official_list_value_excl_egp, 0)) AS list_r," +
		" IF(carton_px > 0 AND ABS(q) > 0.001, IF(q > 0 AND ROUND(q * carton_px - net0, 2) < 0, 0, ROUND(ROUND(q * carton_px, 2) - net0, 2))," +
		" IFNULL(discount_granted_egp, 0)) AS disc_r FROM c)," +
		// Handler-level fallback (no default 10%): discount = list - net when missing.
		" e AS (SELECT *, IF(disc_r = 0 AND list_r > net0 AND net0 > 0, list_r - net0, disc_r) AS disc_f FROM d" +
		" WHERE " + sellInWhere(q, &params) + ")"
	sums := "COUNT(*) AS cnt, SUM(net0) AS net, SUM(q) AS cases, SUM(units_r) AS units," +
		" SUM(list_r) AS list_excl, SUM(disc_f) AS disc"
	totals = base + " SELECT " + sums + ", SUM(IFNULL(weight_tons, 0)) AS tons, SUM(IFNULL(expected_value_egp, 0)) AS expected," +
		" SUM(list_r * (1 + vr)) AS list_incl, SUM(IF(list_r > 0, net0, 0)) AS net_with_list," +
		" SUM(ROUND(gross_r - net0, 2)) AS vat, SUM(gross_r) AS gross," +
		" COUNT(DISTINCT IF(IFNULL(item_code, '') != '', IFNULL(item_name, ''), NULL)) AS matched_skus FROM e"
	groups = base + " SELECT IFNULL(year, 0) AS year, IFNULL(month_num, 0) AS month_num, chain_r AS chain, IFNULL(brand, '') AS brand, " +
		sums + " FROM e GROUP BY 1, 2, 3, 4 ORDER BY 1, 2, 3, 4"
	page = base + " SELECT * EXCEPT(chain_r, upc, matched, q0, net0, unit_px, carton_px, pcs, vr, q, units_r, gross_r, list_r, disc_r, disc_f)" +
		" FROM e ORDER BY year DESC, month_num DESC, net_value_egp DESC, record_id LIMIT @limit OFFSET @offset"
	return totals, groups, page, params
}

func sellInWhere(q SellInTotalsQuery, params *[]bigquery.QueryParameter) string {
	conds := []string{"TRUE"}
	if !isAllValue(q.Chain) {
		conds = append(conds, "chain_r = LOWER(TRIM(@chain))")
		*params = append(*params, bigquery.QueryParameter{Name: "chain", Value: q.Chain})
	}
	if q.Year > 0 {
		conds = append(conds, "year = @year")
		*params = append(*params, bigquery.QueryParameter{Name: "year", Value: q.Year})
	}
	if q.Month > 0 {
		conds = append(conds, "month_num = @month")
		*params = append(*params, bigquery.QueryParameter{Name: "month", Value: q.Month})
	}
	return strings.Join(conds, " AND ")
}

// QuerySellInTotals runs the totals and grouped queries concurrently (read-only).
func (s *BigQuerySink) QuerySellInTotals(ctx context.Context, q SellInTotalsQuery) (*SellInTotalsResult, error) {
	start := time.Now()
	totalsSQL, groupsSQL, pageSQL, params := SellInTotalsSQL(s.ref(TableSellIn), q)
	res := &SellInTotalsResult{Jobs: make([]SellInJobStat, 3)}
	run := func(i int, name, sql string, each func(it *bigquery.RowIterator) error, extra ...bigquery.QueryParameter) error {
		qq := s.client.Query(sql)
		qq.Parameters = append(append([]bigquery.QueryParameter{}, params...), extra...)
		job, err := qq.Run(ctx)
		if err != nil {
			return err
		}
		it, err := job.Read(ctx)
		if err != nil {
			return err
		}
		if err := each(it); err != nil {
			return err
		}
		st := SellInJobStat{Name: name, JobID: job.ID()}
		if js, err := job.Status(ctx); err == nil && js.Statistics != nil {
			st.ElapsedMS = js.Statistics.EndTime.Sub(js.Statistics.CreationTime).Milliseconds()
			st.BytesProc = js.Statistics.TotalBytesProcessed
			if qs, ok := js.Statistics.Details.(*bigquery.QueryStatistics); ok {
				st.CacheHit = qs.CacheHit
			}
		}
		res.Jobs[i] = st
		return nil
	}
	var wg sync.WaitGroup
	errs := make([]error, 3)
	if q.Limit > 0 {
		wg.Add(1)
		go func() {
			defer wg.Done()
			off := q.Offset
			if off < 0 {
				off = 0
			}
			errs[2] = run(2, "page", pageSQL, func(it *bigquery.RowIterator) error {
				for {
					var row map[string]bigquery.Value
					if err := it.Next(&row); err == iterator.Done {
						return nil
					} else if err != nil {
						return err
					}
					rec, err := DecodeSellInRow(row)
					if err != nil {
						return err
					}
					res.Page = append(res.Page, rec)
				}
			}, bigquery.QueryParameter{Name: "limit", Value: q.Limit}, bigquery.QueryParameter{Name: "offset", Value: off})
		}()
	}
	wg.Add(2)
	go func() {
		defer wg.Done()
		errs[0] = run(0, "totals", totalsSQL, func(it *bigquery.RowIterator) error {
			err := it.Next(&res.Totals)
			if err == iterator.Done {
				return nil
			}
			return err
		})
	}()
	go func() {
		defer wg.Done()
		errs[1] = run(1, "groups", groupsSQL, func(it *bigquery.RowIterator) error {
			for {
				var row SellInGroupRow
				if err := it.Next(&row); err == iterator.Done {
					return nil
				} else if err != nil {
					return err
				}
				res.Groups = append(res.Groups, row)
			}
		})
	}()
	wg.Wait()
	for i, err := range errs {
		if err != nil {
			return nil, fmt.Errorf("sell-in totals query %d: %w", i, err)
		}
	}
	res.Duration = time.Since(start)
	return res, nil
}
