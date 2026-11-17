package domain

// ShareTargetMeta is stored on a TargetRecord created from the market-share wizard.
// The saved target still behaves as a normal sell_out target (revenue/units + breakdown).
type ShareTargetMeta struct {
	MarketGrowthPct     float64             `json:"market_growth_pct"`
	MonthsWithData      int                 `json:"months_with_data"`
	Annualized          bool                `json:"annualized"`
	AnnualizationFactor float64             `json:"annualization_factor,omitempty"`
	OverallCurrentPct   float64             `json:"overall_current_share_pct"`
	OverallDesiredPct   float64             `json:"overall_desired_share_pct"`
	Categories          []ShareCategoryMeta `json:"categories,omitempty"`
}

// ShareCategoryMeta remembers per-category shares chosen in the wizard.
type ShareCategoryMeta struct {
	Category        string  `json:"category"`
	CurrentSharePct float64 `json:"current_share_pct"`
	DesiredSharePct float64 `json:"desired_share_pct"`
	TargetRevenueEGP float64 `json:"target_revenue_egp"`
	UpliftRevenueEGP float64 `json:"uplift_revenue_egp"`
}

// ShareTargetBaselineCategory is one category card for wizard step 2.
type ShareTargetBaselineCategory struct {
	Category           string  `json:"category"`
	CurrentSharePct    float64 `json:"current_share_pct"`
	OwnRevenueEGP      float64 `json:"own_revenue_egp"`
	MarketRevenueEGP   float64 `json:"market_revenue_egp"`
	OwnUnits           float64 `json:"own_units"`
	AvgPriceEGP        float64 `json:"avg_price_egp"`
	SKUCount           int     `json:"sku_count"`
}

// ShareTargetBaselineBranch is a selectable branch for wizard step 1.
type ShareTargetBaselineBranch struct {
	BranchKey     string  `json:"branch_key"`
	BranchName    string  `json:"branch_name"`
	OwnRevenueEGP float64 `json:"own_revenue_egp"`
}

// ShareTargetBaselineResponse feeds the share-target wizard (one chain only).
type ShareTargetBaselineResponse struct {
	TenantID           string                         `json:"tenant_id"`
	RetailerChain      string                         `json:"retailer_chain"`
	ChainDisplayName   string                         `json:"chain_display_name"`
	Year               int                            `json:"year"`
	MonthsWithData     int                            `json:"months_with_data"`
	MonthKeys          []string                       `json:"month_keys,omitempty"`
	Categories         []ShareTargetBaselineCategory  `json:"categories"`
	Branches           []ShareTargetBaselineBranch    `json:"branches"`
	TotalOwnEGP        float64                        `json:"total_own_egp"`
	TotalMarketEGP     float64                        `json:"total_market_egp"`
	OverallCurrentPct  float64                        `json:"overall_current_share_pct"`
}
