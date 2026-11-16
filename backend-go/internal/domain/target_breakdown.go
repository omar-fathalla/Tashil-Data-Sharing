package domain

// TargetBreakdownBaseline describes the historical Sell-Out window whose branch/SKU shares drive the allocation.
type TargetBreakdownBaseline struct {
	// Kind is "prior_year_month", "prior_year", "trailing_12m" or "none".
	Kind          string  `json:"kind"`
	Year          int     `json:"year,omitempty"`
	StartDate     string  `json:"start_date,omitempty"`
	EndDate       string  `json:"end_date,omitempty"`
	MonthsCovered int     `json:"months_covered"`
	Partial       bool    `json:"partial"`
	FallbackUsed  bool    `json:"fallback_used"`
	TotalEGP      float64 `json:"total_revenue_egp"`
	CaptionAr     string  `json:"caption_ar"`
}

// TargetBreakdownSKU is one SKU inside a branch: its share of the branch target and its actuals.
type TargetBreakdownSKU struct {
	SKUKey             string   `json:"sku_key"`
	SKUName            string   `json:"sku_name"`
	Category           string   `json:"category"`
	UnitsPerCarton     int      `json:"units_per_carton"`
	BaselineRevenueEGP float64  `json:"baseline_revenue_egp"`
	BaselineUnits      int64    `json:"baseline_units"`
	SharePct           float64  `json:"share_pct"`
	AvgUnitPriceEGP    *float64 `json:"avg_unit_price_egp"`
	AllocatedTargetEGP float64  `json:"allocated_target_egp"`
	AllocatedUnits     *int64   `json:"allocated_target_units"`
	AllocatedCartons   *float64 `json:"allocated_target_cartons"`
	ActualRevenueEGP   float64  `json:"actual_revenue_egp"`
	ActualUnits        int64    `json:"actual_units"`
	AchievementPct     *float64 `json:"achievement_pct"`
	GapEGP             float64  `json:"gap_egp"`
}

// TargetBreakdownBranch is one branch's allocated share of the target with its SKUs.
type TargetBreakdownBranch struct {
	BranchKey          string               `json:"branch_key"`
	BranchName         string               `json:"branch_name"`
	BaselineRevenueEGP float64              `json:"baseline_revenue_egp"`
	SharePct           float64              `json:"share_pct"`
	AllocatedTargetEGP float64              `json:"allocated_target_egp"`
	AllocatedUnits     *int64               `json:"allocated_target_units"`
	AllocatedCartons   *float64             `json:"allocated_target_cartons"`
	ActualRevenueEGP   float64              `json:"actual_revenue_egp"`
	ActualUnits        int64                `json:"actual_units"`
	AchievementPct     *float64             `json:"achievement_pct"`
	GapEGP             float64              `json:"gap_egp"`
	SKUs               []TargetBreakdownSKU `json:"skus"`
}

// TargetBreakdownNoHistory lists a branch or a SKU inside a branch that has no baseline sales:
// it gets a 0 allocation and is shown apart so nothing is invented for it.
type TargetBreakdownNoHistory struct {
	Kind             string  `json:"kind"` // "branch" | "sku"
	BranchKey        string  `json:"branch_key"`
	BranchName       string  `json:"branch_name"`
	SKUKey           string  `json:"sku_key,omitempty"`
	SKUName          string  `json:"sku_name,omitempty"`
	ActualRevenueEGP float64 `json:"actual_revenue_egp"`
	ActualUnits      int64   `json:"actual_units"`
}

// TargetBreakdownResponse answers GET /api/v1/sellout/targets/{id}/breakdown.
// Every revenue/unit figure is a BigQuery SUM at (branch, SKU) grain; the server only apportions
// the target with the largest-remainder method so the branch values add up to the target exactly.
type TargetBreakdownResponse struct {
	TargetID         string  `json:"target_id"`
	TargetType       string  `json:"target_type"`
	RetailerChain    string  `json:"retailer_chain"`
	ChainDisplayName string  `json:"chain_display_name"`
	Year             int     `json:"year"`
	Month            int     `json:"month"`
	MonthLabel       string  `json:"month_label"`
	BranchScope      string  `json:"branch_scope"`
	CategoryScope    string  `json:"category_scope"`
	TargetRevenueEGP float64 `json:"target_revenue_egp"`
	TargetUnits      float64 `json:"target_units"`

	Baseline TargetBreakdownBaseline `json:"baseline"`

	ActualStartDate string `json:"actual_start_date"`
	ActualEndDate   string `json:"actual_end_date"`
	// HasActuals is false when the target period has no Sell-Out rows in scope (e.g. a future year):
	// achieved/achievement/gap are then not comparable and must render as "—", never 0.
	HasActuals              bool     `json:"has_actuals"`
	ActualRevenueEGP        float64  `json:"actual_revenue_egp"`
	ActualUnits             int64    `json:"actual_units"`
	AchievementPct          *float64 `json:"achievement_pct"`
	GapEGP                  float64  `json:"gap_egp"`
	AllocatedUnitsTotal     *int64   `json:"allocated_target_units"`
	AllocatedCartonsTotal   *float64 `json:"allocated_target_cartons"`
	UnattributedActualEGP   float64  `json:"unattributed_actual_revenue_egp"`
	NoHistoryActualEGP      float64  `json:"no_history_actual_revenue_egp"`
	AllocationGranularityEG float64  `json:"allocation_granularity_egp"`

	Branches  []TargetBreakdownBranch    `json:"branches"`
	NoHistory []TargetBreakdownNoHistory `json:"no_history"`
	Source    string                     `json:"source"` // "bigquery" | "memory"
}
