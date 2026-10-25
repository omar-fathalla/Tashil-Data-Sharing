package domain

import "time"

// Precomputed (materialized) analytics rows. They are computed once per source change from the
// same CPFR computation the dashboard uses, kept in memory and mirrored to BigQuery tables
// agg_chain_profit_monthly, agg_sku_cost_margin and agg_sell_through in tashil_analytics.
// Chain "all" holds the all-chains totals.

type AggChainProfitMonthly struct {
	Chain                      string    `json:"chain"`
	Year                       int       `json:"year"`
	Month                      int       `json:"month"`
	HasActualSellOut           bool      `json:"has_actual_sell_out"`
	SellOutUnits               int       `json:"sell_out_units"`
	SellOutValueEGP            float64   `json:"sell_out_value_egp"`
	SellOutValueWithCostEGP    float64   `json:"sell_out_value_with_cost_egp"`
	SellOutMissingCostValueEGP float64   `json:"sell_out_missing_cost_value_egp"`
	SellOutMissingCostUnits    int       `json:"sell_out_missing_cost_units"`
	FactoryCostInclVATEGP      float64   `json:"factory_cost_incl_vat_egp"`
	ChainGrossMarginEGP        float64   `json:"chain_gross_margin_egp"`
	ChainGrossMarginPct        float64   `json:"chain_gross_margin_pct"`
	Version                    int64     `json:"version"`
	ComputedAt                 time.Time `json:"computed_at"`
}

type AggSkuCostMargin struct {
	Chain                      string    `json:"chain"`
	ItemCode                   string    `json:"item_code"`
	Barcode                    string    `json:"barcode"`
	SKUName                    string    `json:"sku_name"`
	Brand                      string    `json:"brand"`
	SellOutUnits               int       `json:"sell_out_units"`
	SellOutValueEGP            float64   `json:"sell_out_value_egp"`
	SellOutFactoryCostEGP      float64   `json:"sell_out_factory_cost_egp"`
	ChainGrossMarginEGP        float64   `json:"chain_gross_margin_egp"`
	FactoryCostMissing         bool      `json:"factory_cost_missing"`
	SellOutMissingCostValueEGP float64   `json:"sell_out_missing_cost_value_egp"`
	Version                    int64     `json:"version"`
	ComputedAt                 time.Time `json:"computed_at"`
}

type AggSellThrough struct {
	Chain                string    `json:"chain"`
	Year                 int       `json:"year"`
	Month                int       `json:"month"`
	SellInCases          float64   `json:"sell_in_cases"`
	SellInValueEGP       float64   `json:"sell_in_value_egp"`
	SellOutEstCases      float64   `json:"sell_out_est_cases"`
	SellThroughRatePct   float64   `json:"sell_through_rate_pct"`
	ClosingStockCases    float64   `json:"closing_stock_cases"`
	ClosingStockValueEGP float64   `json:"closing_stock_value_egp"`
	Version              int64     `json:"version"`
	ComputedAt           time.Time `json:"computed_at"`
}

// AnalyticsAggregates is one tenant's full materialized layer at one source version.
type AnalyticsAggregates struct {
	TenantID           string                  `json:"tenant_id"`
	Version            int64                   `json:"version"`
	UpdatedAt          time.Time               `json:"updated_at"`
	ChainProfitMonthly []AggChainProfitMonthly `json:"agg_chain_profit_monthly"`
	SkuCostMargin      []AggSkuCostMargin      `json:"agg_sku_cost_margin"`
	SellThrough        []AggSellThrough        `json:"agg_sell_through"`
}
