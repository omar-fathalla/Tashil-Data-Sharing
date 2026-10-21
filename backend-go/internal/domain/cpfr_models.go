package domain

import (
	"strings"
	"time"
)

// SellInRecord represents an atomic row from a Supplier Sell-In & Forecasting Plan workbook
// (such as Adco_Fathalla_Sell_In_Plan_2026_Clean.xlsx or plan 10 aswak.xlsx).
type SellInRecord struct {
	RecordID           string    `json:"record_id"`
	BatchID            string    `json:"batch_id,omitempty"`
	SourceFilename     string    `json:"source_filename,omitempty"`
	TenantID           string    `json:"tenant_id"`
	RetailerChain      string    `json:"retailer_chain"`       // e.g. fathalla
	Year               int       `json:"year"`                 // e.g. 2026
	MonthNum           int       `json:"month_num"`            // 1..12
	MonthEN            string    `json:"month_en"`             // Jan..Dec
	MonthAR            string    `json:"month_ar"`             // يناير..ديسمبر
	PeriodWeek         string    `json:"period_week"`          // Full Month, W1, W2
	RegionCode         string    `json:"region_code"`          // ALX, CIR, TNT, BHR, MNS
	Governorate        string    `json:"governorate"`          // الاسكندرية, القاهرة, الغربية, البحيرة, المنصورة, مطروح
	Sector             string    `json:"sector"`               // MT (المنظفات), CC (العناية بالسيارات - رابيدو)
	SubSector          string    `json:"sub_sector"`           // KA, CC-KA
	Division           string    `json:"division"`             // Detergents, Special market CC
	ParentAccountCode  string    `json:"parent_account_code"`  // ALX-08940, ALX-08959
	ParentCustomer     string    `json:"parent_customer"`      // الحساب الأب
	CustomerName       string    `json:"customer_name"`        // عائله فتح الله ماركت...
	CustomerBranchCode string    `json:"customer_branch_code"` // كود فرع العميل أو مجمع الإقليم
	Brand              string    `json:"brand"`                // فيبا, ديفا, فلفيتا, كلوريل, ماكسيل ماجيك, رابيدو, جلاسي, سبيد...
	ProductFamily      string    `json:"product_family"`       // عائلة المنتج
	SubCategory        string    `json:"sub_category"`         // الفئة الفرعية
	ItemGroup          string    `json:"item_group"`           // مجموعة الصنف
	ItemName           string    `json:"item_name"`            // اسم الصنف
	PromotionType      string    `json:"promotion_type"`       // عادي | عرض
	SalesManager       string    `json:"sales_manager"`        // مدير القطاع (officer mgr)
	KAOfficer          string    `json:"ka_officer"`           // مسؤول الحسابات (officer)
	SalesRep           string    `json:"sales_rep"`            // مندوب المبيعات (عمود 10)
	NetQtyCases        float64   `json:"net_qty_cases"`        // صافي الكمية الفعلية بالكرتونة
	NetValueEGP        float64   `json:"net_value_egp"`        // صافي القيمة الفعلية بالجنيه
	TurnoverEGP        float64   `json:"turnover_egp"`         // إجمالي المسحوبات (t.o)
	WeightTons         float64   `json:"weight_tons"`          // الوزن بالطن
	ExpectedQtyCases   float64   `json:"expected_qty_cases"`   // الكمية المتوقعة بنهاية الشهر (Q EXP.)
	ExpectedValueEGP   float64   `json:"expected_value_egp"`   // القيمة المتوقعة بنهاية الشهر (V EXP.)
	TransactionType    string    `json:"transaction_type"`     // مسحوبات بيع (Sale) | مرتجع (Return) | صفري (Zero)
	IngestedAt         time.Time `json:"ingested_at"`
}

// ReconciliationMonthItem compares Supplier Sell-In vs Retailer Cashier Sell-Out for a given month.
type ReconciliationMonthItem struct {
	Year                 int     `json:"year"`
	MonthNum             int     `json:"month_num"`
	MonthEN              string  `json:"month_en"`
	MonthAR              string  `json:"month_ar"`
	PeriodStatus         string  `json:"period_status"`           // مغلق (Full Month) | قيد الإغلاق (W1+W2 Run-Rate)
	ActiveSKUsCount      int     `json:"active_skus_count"`
	OpeningStockCases    float64 `json:"opening_stock_cases"`     // رصيد أول المدة بالكرتونة
	OpeningStockValueEGP float64 `json:"opening_stock_value_egp"` // رصيد أول المدة بالجنيه
	SellInCases          float64 `json:"sell_in_cases"`           // التوريد بالكرتونة
	SellInValueEGP       float64 `json:"sell_in_value_egp"`       // قيمة التوريد الفعلي (Sell-In)
	SellOutUnits         int     `json:"sell_out_units"`          // مبيعات الكاشير بالقطعة
	SellOutEstCases      float64 `json:"sell_out_est_cases"`      // مبيعات الكاشير المعادلة بالكرتونة
	SellOutValueEGP      float64 `json:"sell_out_value_egp"`      // مبيعات الكاشير بالجنيه (Sell-Out)
	MonthlyNetCases      float64 `json:"monthly_net_cases"`       // صافي حركة الشهر بالكرتونة (Sell-In - Sell-Out)
	MonthlyNetValueEGP   float64 `json:"monthly_net_value_egp"`   // صافي حركة الشهر بالجنيه (Sell-In - Sell-Out)
	ClosingStockCases    float64 `json:"closing_stock_cases"`     // الرصيد المتبقي التراكمي آخر الشهر بالكرتونة
	ClosingStockValueEGP float64 `json:"closing_stock_value_egp"` // الرصيد المتبقي التراكمي آخر الشهر بالجنيه
	InventoryGapEGP      float64 `json:"inventory_gap_egp"`       // الفجوة المخزنية (Sell-In - Sell-Out)
	SellThroughRatePct   float64 `json:"sell_through_rate_pct"`   // معدل تصريف المخزون (Sell-Out / Sell-In %)
	WeightTons           float64 `json:"weight_tons"`             // الوزن بالطن
	ExpectedCases        float64 `json:"expected_cases"`          // الكمية المتوقعة بنهاية الشهر (EXP)
	ExpectedValueEGP     float64 `json:"expected_value_egp"`      // القيمة المتوقعة بنهاية الشهر (EXP)
	StockHealthStatus    string  `json:"stock_health_status"`     // accumulation | balanced | drawdown | awaiting_sell_out | awaiting_sell_in
	StockHealthLabelAr   string  `json:"stock_health_label_ar"`   // توصية الشهر بالعربية
}

// SKUBranchInventoryItem represents the estimated stock balance and smart replenishment PO per SKU/Brand/Region.
type SKUBranchInventoryItem struct {
	SKUName                string  `json:"sku_name"`
	Brand                  string  `json:"brand"`
	Sector                 string  `json:"sector"`      // MT | CC
	SubCategory            string  `json:"sub_category"`
	RegionCode             string  `json:"region_code"` // ALX, CIR, TNT, BHR, MNS
	Governorate            string  `json:"governorate"`
	SalesRep               string  `json:"sales_rep"`
	SellInCases            float64 `json:"sell_in_cases"`             // إجمالي التوريد بالكرتونة
	SellInValueEGP         float64 `json:"sell_in_value_egp"`         // إجمالي قيمة التوريد
	SellOutEstCases        float64 `json:"sell_out_est_cases"`        // المبيعات الفعلية المعادلة بالكرتونة
	SellOutValueEGP        float64 `json:"sell_out_value_egp"`        // قيمة المبيعات الفعلية للكاشير
	ReturnCases            float64 `json:"return_cases"`              // المرتجعات بالكرتونة
	ReturnValueEGP         float64 `json:"return_value_egp"`          // قيمة المرتجعات
	EstimatedStockCases    float64 `json:"estimated_stock_cases"`     // الرصيد التقديري الحالي بالكرتونة
	EstimatedStockValueEGP float64 `json:"estimated_stock_value_egp"` // قيمة الرصيد التقديري الحالي بالجنيه
	DailyRunRateCases      float64 `json:"daily_run_rate_cases"`      // معدل السحب اليومي بالكرتونة (ADR)
	DaysOfInventory        float64 `json:"days_of_inventory"`         // أيام تغطية المخزون (DOI)
	StockStatus            string  `json:"stock_status"`              // urgent_replenishment | optimal | overstock
	StockStatusAr          string  `json:"stock_status_ar"`           // خطر نفاد عاجل | رصيد آمن | تكدس مخزني
	CasePriceEGP           float64 `json:"case_price_egp"`            // متوسط سعر الكرتونة
	WeightTons             float64 `json:"weight_tons"`
	SuggestedPOCases       int     `json:"suggested_po_cases"`        // أمر التوريد المقترح (مقرب لكرتونة كاملة)
	SuggestedPOValueEGP    float64 `json:"suggested_po_value_egp"`    // قيمة أمر التوريد المقترح بالجنيه
	SuggestedPOTons        float64 `json:"suggested_po_tons"`         // وزن أمر التوريد المقترح بالطن
}

// BrandForecastItem summarizes actual vs projected month-end (EXP) performance per Brand & Sector.
type BrandForecastItem struct {
	Sector             string  `json:"sector"`      // MT | CC
	SectorNameAr       string  `json:"sector_name_ar"`
	Brand              string  `json:"brand"`
	ActiveSKUsCount    int     `json:"active_skus_count"`
	ActualCases        float64 `json:"actual_cases"`
	ActualValueEGP     float64 `json:"actual_value_egp"`
	ExpectedCases      float64 `json:"expected_cases"`
	ExpectedValueEGP   float64 `json:"expected_value_egp"`
	ForecastUpliftEGP  float64 `json:"forecast_uplift_egp"`
	AchievementRatePct float64 `json:"achievement_rate_pct"`
	WeightTons         float64 `json:"weight_tons"`
	ShareOfTotalPct    float64 `json:"share_of_total_pct"`
}

// RegionPerformanceItem summarizes Sell-In, Expected, and Tonnage across Egyptian governorates/regions.
type RegionPerformanceItem struct {
	RegionCode       string  `json:"region_code"`
	Governorate      string  `json:"governorate"`
	RecordsCount     int     `json:"records_count"`
	ActualCases      float64 `json:"actual_cases"`
	ActualValueEGP   float64 `json:"actual_value_egp"`
	ExpectedCases    float64 `json:"expected_cases"`
	ExpectedValueEGP float64 `json:"expected_value_egp"`
	WeightTons       float64 `json:"weight_tons"`
	SharePct         float64 `json:"share_pct"`
}

// SalesRepScorecard tracks field sales rep & KA officer performance across assigned branches.
type SalesRepScorecard struct {
	SalesRep            string  `json:"sales_rep"`
	KAOfficer           string  `json:"ka_officer"`
	SalesManager        string  `json:"sales_manager"`
	RegionCode          string  `json:"region_code"`
	Governorate         string  `json:"governorate"`
	ServedBranchesCount int     `json:"served_branches_count"`
	ActiveSKUsCount     int     `json:"active_skus_count"`
	RecordsCount        int     `json:"records_count"`
	ActualCases         float64 `json:"actual_cases"`
	ActualValueEGP      float64 `json:"actual_value_egp"`
	ExpectedCases       float64 `json:"expected_cases"`
	ExpectedValueEGP    float64 `json:"expected_value_egp"`
	AchievementPct      float64 `json:"achievement_pct"`
	WeightTons          float64 `json:"weight_tons"`
	PromoValueEGP       float64 `json:"promo_value_egp"`
	PromoSharePct       float64 `json:"promo_share_pct"`
	ReturnCases         float64 `json:"return_cases"`
	ReturnValueEGP      float64 `json:"return_value_egp"`
	ReturnRatePct       float64 `json:"return_rate_pct"`
	MTValueEGP          float64 `json:"mt_value_egp"` // قطاع المنظفات
	CCValueEGP          float64 `json:"cc_value_egp"` // قطاع العناية بالسيارات - رابيدو
}

// ReturnItemSummary highlights top returned items or brands for quality/expiry action.
type ReturnItemSummary struct {
	ItemName       string  `json:"item_name"`
	Brand          string  `json:"brand"`
	Sector         string  `json:"sector"`
	RegionCode     string  `json:"region_code"`
	Governorate    string  `json:"governorate"`
	SalesRep       string  `json:"sales_rep"`
	ReturnCases    float64 `json:"return_cases"`
	ReturnValueEGP float64 `json:"return_value_egp"`
	ReturnRatePct  float64 `json:"return_rate_pct"`
}

// PromoAndReturnSummary aggregates promotion effectiveness (عادي vs عرض) and negative return records.
type PromoAndReturnSummary struct {
	RegularRecordsCount int                 `json:"regular_records_count"`
	RegularCases        float64             `json:"regular_cases"`
	RegularValueEGP     float64             `json:"regular_value_egp"`
	RegularTons         float64             `json:"regular_tons"`
	PromoRecordsCount   int                 `json:"promo_records_count"`
	PromoCases          float64             `json:"promo_cases"`
	PromoValueEGP       float64             `json:"promo_value_egp"`
	PromoTons           float64             `json:"promo_tons"`
	PromoValueSharePct  float64             `json:"promo_value_share_pct"`
	PromoVolumeSharePct float64             `json:"promo_volume_share_pct"`
	AvgPromoCaseTons    float64             `json:"avg_promo_case_tons"`
	ReturnRecordsCount  int                 `json:"return_records_count"`
	TotalReturnCases    float64             `json:"total_return_cases"`
	TotalReturnValueEGP float64             `json:"total_return_value_egp"`
	OverallReturnPct    float64             `json:"overall_return_pct"`
	TopReturnItems      []ReturnItemSummary `json:"top_return_items"`
}

// CPFRDashboardPayload is the comprehensive response served by GET /api/v1/analytics/cpfr.
type CPFRDashboardPayload struct {
	TenantID                 string                    `json:"tenant_id"`
	RetailerChain            string                    `json:"retailer_chain"`
	SourceFilename           string                    `json:"source_filename"`
	TotalRecords             int                       `json:"total_records"`
	ActiveSKUsCount          int                       `json:"active_skus_count"`
	ActiveRepsCount          int                       `json:"active_reps_count"`
	SalesManagerName         string                    `json:"sales_manager_name"`
	KAOfficerName            string                    `json:"ka_officer_name"`
	Jan2026SellInEGP         float64                   `json:"jan_2026_sell_in_egp"`
	Jan2026SellOutEGP        float64                   `json:"jan_2026_sell_out_egp"`
	Jan2026GapEGP            float64                   `json:"jan_2026_gap_egp"`
	Jan2026SellThroughPct    float64                   `json:"jan_2026_sell_through_pct"`
	YTD2026SellInEGP         float64                   `json:"ytd_2026_sell_in_egp"`
	YTD2026SellInCases       float64                   `json:"ytd_2026_sell_in_cases"`
	YTD2026WeightTons        float64                   `json:"ytd_2026_weight_tons"`
	YTD2026ExpectedEGP       float64                   `json:"ytd_2026_expected_egp"`
	OctW1W2ActualEGP         float64                   `json:"oct_w1w2_actual_egp"`
	OctW1W2ActualCases       float64                   `json:"oct_w1w2_actual_cases"`
	OctProjectedMonthEndEGP  float64                   `json:"oct_projected_month_end_egp"`
	OctProjectedCases        float64                   `json:"oct_projected_cases"`
	MTRevenueEGP             float64                   `json:"mt_revenue_egp"`
	MTSharePct               float64                   `json:"mt_share_pct"`
	CCRevenueEGP             float64                   `json:"cc_revenue_egp"`
	CCSharePct               float64                   `json:"cc_share_pct"`
	TotalEstimatedStockCases float64                   `json:"total_estimated_stock_cases"`
	TotalEstimatedStockEGP   float64                   `json:"total_estimated_stock_egp"`
	TotalSuggestedPOCases    int                       `json:"total_suggested_po_cases"`
	TotalSuggestedPOEGP      float64                   `json:"total_suggested_po_egp"`
	TotalSuggestedPOTons     float64                   `json:"total_suggested_po_tons"`
	UrgentReplenishmentCount int                       `json:"urgent_replenishment_count"`
	OverstockAlertCount      int                       `json:"overstock_alert_count"`
	LeadTimeDays             int                       `json:"lead_time_days"`
	SafetyStockDays          int                       `json:"safety_stock_days"`
	MonthlyReconciliation    []ReconciliationMonthItem `json:"monthly_reconciliation"`
	InventoryAndPOItems      []SKUBranchInventoryItem  `json:"inventory_and_po_items"`
	BrandForecasts           []BrandForecastItem       `json:"brand_forecasts"`
	RegionPerformances       []RegionPerformanceItem   `json:"region_performances"`
	SalesRepScorecards       []SalesRepScorecard       `json:"sales_rep_scorecards"`
	PromoAndReturns          PromoAndReturnSummary     `json:"promo_and_returns"`
}

// TargetRecord represents a saved Sell-Out or Sell-In target for a tenant, chain, period (year/month), and optional branch/category.
type TargetRecord struct {
	ID               string  `json:"id"`
	TenantID         string  `json:"tenant_id"`
	TargetType       string  `json:"target_type"` // "sell_out" | "sell_in"
	RetailerChain    string  `json:"retailer_chain"`
	ChainDisplayName string  `json:"chain_display_name"`
	Year             int     `json:"year"`
	Month            int     `json:"month"` // 0 = Full Year, 1..12 = specific month
	MonthLabel       string  `json:"month_label"`
	BranchName       string  `json:"branch_name"`
	Category         string  `json:"category"`
	TargetRevenueEGP float64 `json:"target_revenue_egp"`
	TargetUnits      float64 `json:"target_units"` // Units for Sell-Out, Cases for Sell-In
	Notes            string  `json:"notes"`
	UpdatedAt        string  `json:"updated_at"`
}

// TargetComparisonItem combines a saved TargetRecord with real-time Actual performance from Sell-Out or Sell-In records.
type TargetComparisonItem struct {
	ID                  string  `json:"id"`
	TenantID            string  `json:"tenant_id"`
	TargetType          string  `json:"target_type"`
	RetailerChain       string  `json:"retailer_chain"`
	ChainDisplayName    string  `json:"chain_display_name"`
	Year                int     `json:"year"`
	Month               int     `json:"month"`
	MonthLabel          string  `json:"month_label"`
	BranchName          string  `json:"branch_name"`
	Category            string  `json:"category"`
	TargetRevenueEGP    float64 `json:"target_revenue_egp"`
	ActualRevenueEGP    float64 `json:"actual_revenue_egp"`
	VarianceRevenueEGP  float64 `json:"variance_revenue_egp"`
	AchievementRevPct   float64 `json:"achievement_rev_pct"`
	TargetUnits         float64 `json:"target_units"`
	ActualUnits         float64 `json:"actual_units"`
	VarianceUnits       float64 `json:"variance_units"`
	AchievementUnitsPct float64 `json:"achievement_units_pct"`
	Status              string  `json:"status"`    // "exceeded" | "on_track" | "at_risk"
	StatusAr            string  `json:"status_ar"` // "تجاوز المستهدف" | "قيد التحقيق" | "أقل من المستهدف"
	Notes               string  `json:"notes"`
	UpdatedAt           string  `json:"updated_at"`
}

// TargetsSummaryResponse returns the list of target comparisons along with rolled-up totals.
type TargetsSummaryResponse struct {
	TenantID              string                 `json:"tenant_id"`
	TargetType            string                 `json:"target_type"`
	TotalTargetRevenueEGP float64                `json:"total_target_revenue_egp"`
	TotalActualRevenueEGP float64                `json:"total_actual_revenue_egp"`
	TotalVarianceEGP      float64                `json:"total_variance_egp"`
	OverallAchievementPct float64                `json:"overall_achievement_pct"`
	TotalTargetUnits      float64                `json:"total_target_units"`
	TotalActualUnits      float64                `json:"total_actual_units"`
	Items                 []TargetComparisonItem `json:"items"`
}

// InferBrandFromItemName uses AI-grade heuristic brand extraction across Arabic & English FMCG and retail goods.
// It recognizes established brands and dynamically extracts novel brand tokens for any company.
func InferBrandFromItemName(itemName, subCategory string) string {
	s := strings.ToLower(itemName + " " + subCategory)
	switch {
	case strings.Contains(s, "ماكسيل") || strings.Contains(s, "maxel"):
		return "ماكسيل (Maxell)"
	case strings.Contains(s, "ديفا") || strings.Contains(s, "diva"):
		return "ديفا (Diva)"
	case strings.Contains(s, "فلفيتا") || strings.Contains(s, "فلڤيتا") || strings.Contains(s, "velveta"):
		return "فلڤيتا (Velveta)"
	case strings.Contains(s, "فيبا") || strings.Contains(s, "feba"):
		return "فيبا (Feba)"
	case strings.Contains(s, "فيفا") || strings.Contains(s, "viva"):
		return "فيفا (Viva)"
	case strings.Contains(s, "نيفيا") || strings.Contains(s, "nivea"):
		return "نيفيا (Nivea)"
	case strings.Contains(s, "دوف") || strings.Contains(s, "dove"):
		return "دوف (Dove)"
	case strings.Contains(s, "رابيدو") || strings.Contains(s, "rapido") || strings.Contains(s, "جلاسي") || strings.Contains(s, "سبيد"):
		return "رابيدو (Rapido)"
	case strings.Contains(s, "كلوريل") || strings.Contains(s, "clorel"):
		return "كلوريل (Clorel)"
	case strings.Contains(s, "جنرال") || strings.Contains(s, "general"):
		return "جنرال (General)"
	case strings.Contains(s, "أريال") || strings.Contains(s, "اريال") || strings.Contains(s, "ariel"):
		return "أريال (Ariel)"
	case strings.Contains(s, "برسيل") || strings.Contains(s, "persil"):
		return "برسيل (Persil)"
	case strings.Contains(s, "كلوركس") || strings.Contains(s, "clorox"):
		return "كلوركس (Clorox)"
	case strings.Contains(s, "ديتول") || strings.Contains(s, "dettol"):
		return "ديتول (Dettol)"
	case strings.Contains(s, "فاين") || strings.Contains(s, "fine"):
		return "فاين (Fine)"
	case strings.Contains(s, "زينة") || strings.Contains(s, "zeina"):
		return "زينة (Zeina)"
	case strings.Contains(s, "بامبرز") || strings.Contains(s, "pampers"):
		return "بامبرز (Pampers)"
	case strings.Contains(s, "مولفيكس") || strings.Contains(s, "molfix"):
		return "مولفيكس (Molfix)"
	case strings.Contains(s, "جهينة") || strings.Contains(s, "juhayna"):
		return "جهينة (Juhayna)"
	case strings.Contains(s, "المراعي") || strings.Contains(s, "almarai"):
		return "المراعي (Almarai)"
	case strings.Contains(s, "ليبتون") || strings.Contains(s, "lipton"):
		return "ليبتون (Lipton)"
	case strings.Contains(s, "نسكافيه") || strings.Contains(s, "nescafe"):
		return "نسكافيه (Nescafe)"
	case strings.Contains(s, "بيبسي") || strings.Contains(s, "pepsi"):
		return "بيبسي (Pepsi)"
	case strings.Contains(s, "كوكاكولا") || strings.Contains(s, "coca"):
		return "كوكاكولا (Coca-Cola)"
	default:
		clean := strings.TrimSpace(itemName)
		if clean == "" {
			if subCategory != "" {
				return subCategory
			}
			return "أصناف عامة"
		}
		parts := strings.Fields(clean)
		if len(parts) > 0 {
			first := parts[0]
			if len([]rune(first)) >= 2 {
				if len(parts) > 1 && (parts[1] == "ماجيك" || parts[1] == "جولد" || parts[1] == "بلس" || strings.EqualFold(parts[1], "Magic") || strings.EqualFold(parts[1], "Gold") || strings.EqualFold(parts[1], "Plus")) {
					return first + " " + parts[1]
				}
				return first
			}
		}
		return "أصناف عامة"
	}
}


