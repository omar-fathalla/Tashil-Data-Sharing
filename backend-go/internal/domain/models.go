package domain

import (
	"strings"
	"sync"
	"time"
)

var (
	customChainNamesMu sync.RWMutex
	customChainNames   = map[string]string{
		"chain-1080314": "الوكالة (El Wakala)",
		"el-wakala":     "الوكالة (El Wakala)",
		"wakala":        "الوكالة (El Wakala)",
		"الوكالة":       "الوكالة (El Wakala)",
		"الوكاله":       "الوكالة (El Wakala)",
	}
)

// RegisterCustomChainDisplayName registers a custom retail chain code -> display name mapping in memory.
func RegisterCustomChainDisplayName(code, displayName string) {
	c := strings.ToLower(strings.TrimSpace(code))
	d := strings.TrimSpace(displayName)
	if c == "" || d == "" {
		return
	}
	customChainNamesMu.Lock()
	customChainNames[c] = d
	customChainNamesMu.Unlock()
}

// GetCustomChainDisplayName looks up a custom retail chain's display name by its code.
func GetCustomChainDisplayName(code string) (string, bool) {
	c := strings.ToLower(strings.TrimSpace(code))
	if c == "" {
		return "", false
	}
	customChainNamesMu.RLock()
	name, ok := customChainNames[c]
	customChainNamesMu.RUnlock()
	return name, ok
}

// UserRole defines permission levels within the multi-tenant platform.
type UserRole string

const (
	RoleSuperAdmin           UserRole = "super_admin"            // مدير المنصة (Super Admin)
	RoleVendorAdmin          UserRole = "vendor_admin"           // مدير الشركة (Vendor Admin)
	RoleNationalSalesManager UserRole = "national_sales_manager" // مدير المبيعات الوطني
	RoleChainKAM             UserRole = "chain_kam"              // مدير حسابات السلاسل (KAM)
	RoleFieldSupervisor      UserRole = "field_supervisor"       // المشرف الميداني
	RoleSalesUser            UserRole = "sales_user"             // مستخدم مبيعات
	RoleAdmin                UserRole = "admin"                  // Backward compatibility
	RoleExecutive            UserRole = "executive"
	RoleAnalyst              UserRole = "analyst"
	RoleViewer               UserRole = "viewer"
)

// Tenant represents an enterprise client (Adeco, Unilever, PepsiCo, etc.).
type Tenant struct {
	ID           string    `json:"id"`
	Name         string    `json:"name"`
	Code         string    `json:"code"`
	SeedColorHex string    `json:"seed_color_hex"`
	Currency     string    `json:"currency"`
	CreatedAt    time.Time `json:"created_at"`
}

// UserClaims represents the JWT payload used for Row-Level Security.
type UserClaims struct {
	UserID         string   `json:"user_id"`
	TenantID       string   `json:"tenant_id"`
	Email          string   `json:"email"`
	Role           UserRole `json:"role"`
	Name           string   `json:"name"`
	RoleDisplayAr  string   `json:"role_display_ar,omitempty"`
	AssignedChain  string   `json:"assigned_chain,omitempty"`
	AssignedRegion string   `json:"assigned_region,omitempty"`
}

// Store represents a retail outlet / branch.
type Store struct {
	ID          string `json:"id"`
	TenantID    string `json:"tenant_id"`
	Chain       string `json:"chain"` // carrefour, fathalla, gomla, spinneys
	BranchName  string `json:"branch_name"`
	Governorate string `json:"governorate"`
	City        string `json:"city"`
	IsActive    bool   `json:"is_active"`
}

// SKU represents a stock keeping unit (product catalog).
type SKU struct {
	ID        string  `json:"id"`
	TenantID  string  `json:"tenant_id"`
	Barcode   string  `json:"barcode"` // GTIN-13/14
	SKUName   string  `json:"sku_name"`
	Category  string  `json:"category"`
	Brand     string  `json:"brand"`
	BasePrice float64 `json:"base_price"`
}

// SellOutFact represents an atomic sell-out transaction loaded into Google BigQuery.
type SellOutFact struct {
	RecordID         string    `json:"record_id" bigquery:"record_id"`
	TenantID         string    `json:"tenant_id" bigquery:"tenant_id"`
	RetailerChain    string    `json:"retailer_chain" bigquery:"retailer_chain"`
	StoreID          string    `json:"store_id" bigquery:"store_id"`
	StoreName        string    `json:"store_name" bigquery:"store_name"`
	Barcode          string    `json:"barcode" bigquery:"barcode"`
	SKUName          string    `json:"sku_name" bigquery:"sku_name"`
	Category         string    `json:"category" bigquery:"category"`
	Supplier         string    `json:"supplier,omitempty" bigquery:"supplier"`
	IsOwnBrand       bool      `json:"is_own_brand" bigquery:"is_own_brand"`
	QuantitySold     int       `json:"quantity_sold" bigquery:"quantity_sold"`
	NetRevenue       float64   `json:"net_revenue" bigquery:"net_revenue"`
	UnitPrice        float64   `json:"unit_price" bigquery:"unit_price"`
	RecommendedPrice float64   `json:"recommended_price,omitempty" bigquery:"recommended_price"`
	TransactionDate  string    `json:"transaction_date" bigquery:"transaction_date"` // YYYY-MM-DD
	IngestionBatchID string    `json:"ingestion_batch_id" bigquery:"ingestion_batch_id"`
	IngestedAt       time.Time `json:"ingested_at" bigquery:"ingested_at"`
}

// IngestionBatch records metadata for an uploaded Excel or CSV file.
type IngestionBatch struct {
	BatchID          string    `json:"batch_id"`
	TenantID         string    `json:"tenant_id"`
	Filename         string    `json:"filename"`
	RetailerDetected string    `json:"retailer_detected"`
	TotalRows        int       `json:"total_rows"`
	ValidRows        int       `json:"valid_rows"`
	AnomalyRows      int       `json:"anomaly_rows"`
	TotalRevenue     float64   `json:"total_revenue"`
	TotalQuantity    int       `json:"total_quantity"`
	ConfidenceScore  float64   `json:"confidence_score"`
	Status           string    `json:"status"` // pending, processing, completed, failed
	ProcessedAt      time.Time `json:"processed_at"`
}

// OOSAlert identifies critical out-of-stock conditions detected across chains.
type OOSAlert struct {
	AlertID                string    `json:"alert_id"`
	TenantID               string    `json:"tenant_id"`
	RetailerChain          string    `json:"retailer_chain"`
	StoreID                string    `json:"store_id"`
	StoreName              string    `json:"store_name"`
	Barcode                string    `json:"barcode"`
	SKUName                string    `json:"sku_name"`
	Brand                  string    `json:"brand,omitempty"`
	Category               string    `json:"category"`
	EstimatedLostDailyCost float64   `json:"estimated_lost_daily_cost"`
	ConsecutiveDaysOOS     int       `json:"consecutive_days_oos"`
	Severity               string    `json:"severity"` // critical, high, medium
	DetectedAt             time.Time `json:"detected_at"`
}

// OOSBrandSummary summarizes out-of-stock incidents for a specific brand.
type OOSBrandSummary struct {
	Brand              string   `json:"brand"`
	OOSItemsCount      int      `json:"oos_items_count"`
	ImpactedBranches   []string `json:"impacted_branches"`
	BranchesCount      int      `json:"branches_count"`
	TotalLostDailyCost float64  `json:"total_lost_daily_cost"`
	MaxDaysOOS         int      `json:"max_days_oos"`
}

// OOSBranchSummary summarizes out-of-stock incidents for a retail branch.
type OOSBranchSummary struct {
	BranchName         string   `json:"branch_name"`
	RetailerChain      string   `json:"retailer_chain"`
	OOSItemsCount      int      `json:"oos_items_count"`
	BrandsAffected     []string `json:"brands_affected"`
	TotalLostDailyCost float64  `json:"total_lost_daily_cost"`
}

// OOSAIAnalysis contains Gemini AI generated root cause analysis and emergency actions.
type OOSAIAnalysis struct {
	ModelUsed               string   `json:"model_used"`
	GeneratedAt             string   `json:"generated_at"`
	ExecutiveSummaryAr      string   `json:"executive_summary_ar"`
	ExecutiveSummaryEn      string   `json:"executive_summary_en"`
	RootCausesAr            []string `json:"root_causes_ar"`
	ImmediateActionsAr      []string `json:"immediate_actions_ar"`
	CriticalSKUsCount       int      `json:"critical_skus_count"`
	TopImpactedBranch       string   `json:"top_impacted_branch"`
	TopImpactedBrand        string   `json:"top_impacted_brand"`
	ProjectedMonthlyLossEGP float64  `json:"projected_monthly_loss_egp"`
}

// ChainShareSummary gives revenue breakdown by retailer chain.
type ChainShareSummary struct {
	RetailerChain string  `json:"retailer_chain"`
	DisplayName   string  `json:"display_name"`
	TotalRevenue  float64 `json:"total_revenue"`
	TotalUnits    int     `json:"total_units"`
	MarketShare   float64 `json:"market_share"` // percentage 0 - 100
}

// SupplierShareSummary gives market share breakdown across the tenant and competing suppliers.
type SupplierShareSummary struct {
	SupplierName string  `json:"supplier_name"`
	TotalRevenue float64 `json:"total_revenue"`
	TotalUnits   int     `json:"total_units"`
	MarketShare  float64 `json:"market_share_pct"`
	SKUCount     int     `json:"sku_count"`
	IsTenant     bool    `json:"is_tenant"`
}

// ChainTrendValue holds a single retail chain's revenue, units, and growth rate for a given period.
type ChainTrendValue struct {
	RetailerChain string  `json:"retailer_chain"`
	DisplayName   string  `json:"display_name"`
	Revenue       float64 `json:"revenue"`
	Units         int     `json:"units"`
	GrowthPct     float64 `json:"growth_pct"`
}

// DailyTrendPoint represents a time-series point (monthly or daily) with per-chain breakdown.
type DailyTrendPoint struct {
	Date          string             `json:"date"`                  // YYYY-MM-DD (or end of month)
	MonthKey      string             `json:"month_key,omitempty"`   // YYYY-MM
	MonthLabel    string             `json:"month_label,omitempty"` // e.g. يناير 25
	Revenue       float64            `json:"revenue"`
	Units         int                `json:"units"`
	StoreCount    int                `json:"store_count"`
	ChainRevenues map[string]float64 `json:"chain_revenues,omitempty"`
	ChainUnits    map[string]int     `json:"chain_units,omitempty"`
	ChainDetails  []ChainTrendValue  `json:"chain_details,omitempty"`
}

// CategoryContribution summarizes revenue and unit contribution by product category, including category market share vs competitors.
type CategoryContribution struct {
	Category               string  `json:"category"`
	TotalRevenue           float64 `json:"total_revenue"`
	TotalUnits             int     `json:"total_units"`
	SharePct               float64 `json:"share_pct"`
	SKUCount               int     `json:"sku_count"`
	MarketTotalRevenue     float64 `json:"market_total_revenue"`
	TenantCategorySharePct float64 `json:"tenant_category_share_pct"`
}

// ParetoSKUItem represents a SKU in the 80/20 Pareto revenue analysis.
type ParetoSKUItem struct {
	Barcode            string  `json:"barcode"`
	SKUName            string  `json:"sku_name"`
	Category           string  `json:"category"`
	TotalRevenue       float64 `json:"total_revenue"`
	TotalUnits         int     `json:"total_units"`
	UnitPrice          float64 `json:"unit_price,omitempty"`
	RevenueSharePct    float64 `json:"revenue_share_pct"`
	CumulativeSharePct float64 `json:"cumulative_share_pct"`
	IsTop80Contributor bool    `json:"is_top_80_contributor"`
}

// ExecutiveKPIs provides aggregated summary metrics for the executive Bento Grid.
type ExecutiveKPIs struct {
	TotalRevenue          float64                `json:"total_revenue"`
	TotalMarketRevenue    float64                `json:"total_market_revenue"`
	TenantMarketSharePct  float64                `json:"tenant_market_share_pct"`
	TotalSKUsCount        int                    `json:"total_skus_count"`
	TotalMarketSKUsCount  int                    `json:"total_market_skus_count"`
	CompetitorsCount      int                    `json:"competitors_count"`
	RevenueGrowthPct      float64                `json:"revenue_growth_pct"`
	RevenueYoYPct         float64                `json:"revenue_yoy_pct"`
	RevenueMoMPct         float64                `json:"revenue_mom_pct"`
	TotalUnitsSold        int                    `json:"total_units_sold"`
	UnitsGrowthPct        float64                `json:"units_growth_pct"`
	UnitsYoYPct           float64                `json:"units_yoy_pct"`
	UnitsMoMPct           float64                `json:"units_mom_pct"`
	ActiveStoresCount     int                    `json:"active_stores_count"`
	OOSRatePct            float64                `json:"oos_rate_pct"`
	OSARatePct            float64                `json:"osa_rate_pct"`
	TotalOOSIncidents     int                    `json:"total_oos_incidents"`
	EstimatedLostRevenue  float64                `json:"estimated_lost_revenue"`
	Currency              string                 `json:"currency"`
	ReportingPeriod       string                 `json:"reporting_period"`
	ChainShares           []ChainShareSummary    `json:"chain_shares"`
	AvailableChains       []ChainShareSummary    `json:"available_chains"`
	SupplierShares        []SupplierShareSummary `json:"supplier_shares"`
	DailyTrends           []DailyTrendPoint      `json:"daily_trends"`
	CategoryContributions []CategoryContribution `json:"category_contributions"`
	ParetoSKUs            []ParetoSKUItem        `json:"pareto_skus"`
}
