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
	ItemCode           string    `json:"item_code,omitempty"`  // كود الصنف المعتمد (e.g. FGCL-0550-0001)
	Barcode            string    `json:"barcode,omitempty"`    // الباركود الدولي EAN-13
	UnitsPerCarton     int       `json:"units_per_carton,omitempty"`
	ItemName           string    `json:"item_name"`            // اسم الصنف
	PromotionType      string    `json:"promotion_type"`       // عادي | عرض
	SalesManager       string    `json:"sales_manager"`        // مدير القطاع (officer mgr)
	KAOfficer          string    `json:"ka_officer"`           // مسؤول الحسابات (officer)
	SalesRep           string    `json:"sales_rep"`            // مندوب المبيعات (عمود 10)
	NetQtyCases        float64   `json:"net_qty_cases"`        // صافي الكمية الفعلية بالكرتونة
	NetValueEGP        float64   `json:"net_value_egp"`        // صافي القيمة الفعلية بالجنيه (بدون ضريبة القيمة المضافة)
	TurnoverEGP        float64   `json:"turnover_egp"`         // إجمالي المسحوبات (t.o)
	WeightTons         float64   `json:"weight_tons"`          // الوزن بالطن
	ExpectedQtyCases   float64   `json:"expected_qty_cases"`   // الكمية المتوقعة بنهاية الشهر (Q EXP.)
	ExpectedValueEGP   float64   `json:"expected_value_egp"`   // القيمة المتوقعة بنهاية الشهر (V EXP.)
	TransactionType    string    `json:"transaction_type"`     // مسحوبات بيع (Sale) | مرتجع (Return) | صفري (Zero)
	IngestedAt         time.Time `json:"ingested_at"`

	// Canonical Product Master & Tax/Discount Enrichment (3-Way Linkage)
	TotalUnitsSupplied       int     `json:"total_units_supplied"`         // NetQtyCases * UnitsPerCarton (الكمية بالقطعة)
	OfficialUnitExclVATEGP   float64 `json:"official_unit_excl_vat_egp"`   // سعر القطعة الرسمي غير شامل الضريبة
	OfficialUnitInclVATEGP   float64 `json:"official_unit_incl_vat_egp"`   // سعر القطعة الرسمي شامل 14% ضريبة
	OfficialCartonExclVATEGP float64 `json:"official_carton_excl_vat_egp"` // سعر الكرتونة الرسمي غير شامل الضريبة
	OfficialCartonInclVATEGP float64 `json:"official_carton_incl_vat_egp"` // سعر الكرتونة الرسمي شامل 14% ضريبة
	NetCartonInvoiceCostEGP  float64 `json:"net_carton_invoice_cost_egp"`  // صافي تكلفة الكرتونة بعد الخصم وشامل الضريبة
	InvoiceDiscountPct       float64 `json:"invoice_discount_pct"`         // نسبة خصم الفاتورة الرسمي (e.g. 10%)
	ExtraDiscountPct         float64 `json:"extra_discount_pct"`           // نسبة الخصم الإضافي/التعاقدي
	VATRate                  float64 `json:"vat_rate"`                     // 0.14 (14% ضريبة القيمة المضافة)
	GrossValueInclVATEGP     float64 `json:"gross_value_incl_vat_egp"`     // NetValueEGP * 1.14 (الإجمالي شامل الضريبة)
	VATAmountEGP             float64 `json:"vat_amount_egp"`               // GrossValueInclVATEGP - NetValueEGP (قيمة الضريبة 14%)
	OfficialListValueExclEGP float64 `json:"official_list_value_excl_egp"` // NetQtyCases * OfficialCartonExclVATEGP (القيمة بالسعر الرسمي قبل الخصم)
	DiscountGrantedEGP       float64 `json:"discount_granted_egp"`         // OfficialListValueExclEGP - NetValueEGP (قيمة الخصم الممنوح)
	EffectiveDiscountPct     float64 `json:"effective_discount_pct"`       // نسبة الخصم الفعلي المحققة %
	ActualCasePriceExclEGP   float64 `json:"actual_case_price_excl_egp"`   // NetValueEGP / NetQtyCases (سعر الكرتونة الفعلي بالبيان)
	PriceVariancePct         float64 `json:"price_variance_pct"`           // نسبة انحراف السعر الفعلي عن الكارتة %
	PricingWaveStatus        string  `json:"pricing_wave_status"`          // "current_list" | "historical_pre_aug" | "promo_discounted" | "unmatched"
	DepartmentAr             string  `json:"department_ar,omitempty"`      // القسم الإنتاجي (منظفات سائلة / بودر / معطر / رابيدو)
	CanonicalFamilyKey       string  `json:"canonical_family_key,omitempty"`

	// SOPQtyConverted / SOPNeedsPackFallback are ingest-only flags (not stored in BigQuery).
	// After official CRT + Each/U of M2 conversion, enrich must not run the pieces heuristic again.
	SOPQtyConverted      bool `json:"-"`
	SOPNeedsPackFallback bool `json:"-"`
	SOPUsedPackFallback  bool `json:"-"`
}

// ReconciliationMonthItem compares Supplier Sell-In vs Retailer Cashier Sell-Out for a given month.
type ReconciliationMonthItem struct {
	Year                 int     `json:"year"`
	MonthNum             int     `json:"month_num"`
	MonthEN              string  `json:"month_en"`
	MonthAR              string  `json:"month_ar"`
	PeriodStatus         string  `json:"period_status"`           // مغلق (Full Month) | قيد الإغلاق (W1+W2 Run-Rate)
	HasActualSellOut     bool    `json:"has_actual_sell_out"`     // true فقط للأشهر التي يتوفر لها شيت كاشير فعلي (Jan..Aug)
	ActiveSKUsCount      int     `json:"active_skus_count"`
	OpeningStockCases    float64 `json:"opening_stock_cases"`     // رصيد أول المدة بالكرتونة
	OpeningStockValueEGP float64 `json:"opening_stock_value_egp"` // رصيد أول المدة بالجنيه
	SellInCases          float64 `json:"sell_in_cases"`           // التوريد بالكرتونة
	SellInUnits          int     `json:"sell_in_units"`           // التوريد بالقطعة
	SellInValueEGP       float64 `json:"sell_in_value_egp"`       // قيمة التوريد الفعلي صافي بدون ضريبة (Sell-In Excl. VAT)
	SellInGrossInclVATEGP float64 `json:"sell_in_gross_incl_vat_egp"` // قيمة التوريد الفعلي شامل 14% ضريبة
	SellInVATAmountEGP   float64 `json:"sell_in_vat_amount_egp"`  // ضريبة القيمة المضافة على التوريد (14%)
	SellOutUnits         int     `json:"sell_out_units"`          // مبيعات الكاشير بالقطعة
	SellOutEstCases      float64 `json:"sell_out_est_cases"`      // مبيعات الكاشير المعادلة بالكرتونة (باستخدام شد الكارتة الفعلي)
	SellOutValueEGP      float64 `json:"sell_out_value_egp"`      // مبيعات الكاشير بسعر المستهلك بالجنيه (POS Sell-Out)
	SellOutFactoryCostExclVATEGP float64 `json:"sell_out_factory_cost_excl_vat_egp"` // تكلفة مبيعات الكاشير بسعر المصنع صافي بدون ضريبة
	SellOutFactoryCostInclVATEGP float64 `json:"sell_out_factory_cost_incl_vat_egp"` // تكلفة مبيعات الكاشير بسعر المصنع شامل الضريبة والخصم
	ChainGrossMarginEGP  float64 `json:"chain_gross_margin_egp"`  // ربح السلسلة المحقق (SellOutValueEGP - SellOutFactoryCostInclVATEGP)
	ChainGrossMarginPct  float64 `json:"chain_gross_margin_pct"`  // هامش ربح السلسلة %
	SellOutValueWithCostEGP    float64 `json:"sell_out_value_with_cost_egp"`     // مبيعات الكاشير التي لها تكلفة مصنع حقيقية (أساس حساب الربح)
	SellOutMissingCostValueEGP float64 `json:"sell_out_missing_cost_value_egp"`  // مبيعات بدون تكلفة حقيقية (مستبعدة من الربح)
	SellOutMissingCostUnits    int     `json:"sell_out_missing_cost_units"`      // قطع مباعة بدون تكلفة حقيقية
	MonthlyNetCases      float64 `json:"monthly_net_cases"`       // صافي حركة الشهر بالكرتونة (Sell-In - Sell-Out)
	MonthlyNetValueEGP   float64 `json:"monthly_net_value_egp"`   // صافي حركة الشهر بالجنيه (Sell-In - Sell-Out)
	ClosingStockCases    float64 `json:"closing_stock_cases"`     // الرصيد المتبقي التراكمي آخر الشهر بالكرتونة
	ClosingStockValueEGP float64 `json:"closing_stock_value_egp"` // الرصيد المتبقي التراكمي آخر الشهر بالجنيه
	InventoryGapEGP      float64 `json:"inventory_gap_egp"`       // الفجوة المخزنية (Sell-In - Sell-Out)
	SellThroughRatePct   float64 `json:"sell_through_rate_pct"`   // معدل تصريف المخزون بالكرتونة (Sell-Out Cases / Sell-In Cases %)
	WeightTons           float64 `json:"weight_tons"`             // الوزن بالطن
	ExpectedCases        float64 `json:"expected_cases"`          // الكمية المتوقعة بنهاية الشهر (EXP)
	ExpectedValueEGP     float64 `json:"expected_value_egp"`      // القيمة المتوقعة بنهاية الشهر (EXP)
	PrevYearSellOutUnits int     `json:"prev_year_sell_out_units"`// مبيعات الكاشير لنفس الشهر من العام السابق 2025 (قطعة)
	PrevYearSellOutValueEGP float64 `json:"prev_year_sell_out_value_egp"` // مبيعات الكاشير لنفس الشهر من العام السابق 2025 (ج.م)
	YoYSellOutGrowthPct  float64 `json:"yoy_sell_out_growth_pct"` // نسبة النمو السنوي في السحب الفعلي (2026 مقابل 2025)
	StockHealthStatus    string  `json:"stock_health_status"`     // accumulation | balanced | drawdown | awaiting_sell_out | awaiting_sell_in
	StockHealthLabelAr   string  `json:"stock_health_label_ar"`   // توصية الشهر بالعربية
}

// SKUBranchInventoryItem represents the estimated stock balance and smart replenishment PO per SKU/Brand/Region.
type SKUBranchInventoryItem struct {
	ItemCode               string  `json:"item_code,omitempty"`
	Barcode                string  `json:"barcode,omitempty"`
	UnitsPerCarton         int     `json:"units_per_carton,omitempty"`
	ItemType               string  `json:"item_type,omitempty"`
	DepartmentAr           string  `json:"department_ar,omitempty"`
	FactoryCartonCost      float64 `json:"factory_carton_cost,omitempty"`
	OfficialCartonExclVATEGP float64 `json:"official_carton_excl_vat_egp,omitempty"`
	OfficialCartonInclVATEGP float64 `json:"official_carton_incl_vat_egp,omitempty"`
	OfficialUnitInclVATEGP float64 `json:"official_unit_incl_vat_egp,omitempty"`
	AvgRetailPOSPriceEGP   float64 `json:"avg_retail_pos_price_egp,omitempty"`
	RetailerMarginPct      float64 `json:"retailer_margin_pct,omitempty"`
	SKUName                string  `json:"sku_name"`
	Brand                  string  `json:"brand"`
	Sector                 string  `json:"sector"`      // MT | CC
	SubCategory            string  `json:"sub_category"`
	RegionCode             string  `json:"region_code"` // ALX, CIR, TNT, BHR, MNS
	Governorate            string  `json:"governorate"`
	SalesRep               string  `json:"sales_rep"`
	SellInCases            float64 `json:"sell_in_cases"`             // إجمالي التوريد بالكرتونة (Full YTD)
	SellInUnits            int     `json:"sell_in_units"`             // إجمالي التوريد بالقطعة
	SellInValueEGP         float64 `json:"sell_in_value_egp"`         // إجمالي قيمة التوريد (صافي بدون ضريبة)
	SellInGrossInclVATEGP  float64 `json:"sell_in_gross_incl_vat_egp"`// إجمالي قيمة التوريد شامل 14% ضريبة
	MatchedSellInCases     float64 `json:"matched_sell_in_cases"`     // التوريد خلال الفترة المتطابقة (يناير-أغسطس) بالكرتونة
	MatchedSellInValueEGP  float64 `json:"matched_sell_in_value_egp"` // قيمة التوريد خلال الفترة المتطابقة (يناير-أغسطس)
	PendingSellInCases     float64 `json:"pending_sell_in_cases"`     // توريد بانتظار شيتات الكاشير (سبتمبر-أكتوبر) بالكرتونة
	PendingSellInValueEGP  float64 `json:"pending_sell_in_value_egp"` // قيمة توريد بانتظار شيتات الكاشير (سبتمبر-أكتوبر)
	SellOutUnits           int     `json:"sell_out_units"`            // المبيعات الفعلية للكاشير بالقطعة
	SellOutEstCases        float64 `json:"sell_out_est_cases"`        // المبيعات الفعلية المعادلة بالكرتونة (SellOutUnits / UnitsPerCarton)
	SellOutValueEGP        float64 `json:"sell_out_value_egp"`        // قيمة المبيعات الفعلية للكاشير بسعر المستهلك
	SellOutFactoryCostEGP  float64 `json:"sell_out_factory_cost_egp"` // تكلفة المبيعات الفعلية بسعر المصنع
	ChainGrossMarginEGP    float64 `json:"chain_gross_margin_egp"`    // ربح السلسلة على الصنف بالجنيه
	FactoryCostMissing     bool    `json:"factory_cost_missing"`      // لا توجد تكلفة مصنع حقيقية: التكلفة والربح فارغان
	SellOutMissingCostValueEGP float64 `json:"sell_out_missing_cost_value_egp"` // جزء المبيعات بدون تكلفة حقيقية
	ReturnCases            float64 `json:"return_cases"`              // المرتجعات بالكرتونة
	ReturnValueEGP         float64 `json:"return_value_egp"`          // قيمة المرتجعات
	EstimatedStockCases    float64 `json:"estimated_stock_cases"`     // الرصيد الدفتري الحقيقي بالكرتونة
	EstimatedStockUnits    int     `json:"estimated_stock_units"`     // الرصيد الدفتري الحقيقي بالقطعة
	EstimatedStockValueEGP float64 `json:"estimated_stock_value_egp"` // قيمة الرصيد الدفتري الحقيقي بالجنيه (بسعر كارتة الأصناف)
	MatchedRemainingCases  float64 `json:"matched_remaining_cases"`   // الرصيد الدفتري بنهاية الفترة المتطابقة (أغسطس) بالكرتونة
	MatchedRemainingValueEGP float64 `json:"matched_remaining_value_egp"` // قيمة الرصيد بنهاية الفترة المتطابقة (أغسطس)
	SellThroughPct         float64 `json:"sell_through_pct"`          // نسبة التصريف الحقيقية للصنف %
	DailyRunRateCases      float64 `json:"daily_run_rate_cases"`      // معدل السحب اليومي الحقيقي بالكرتونة (ADR)
	DaysOfInventory        float64 `json:"days_of_inventory"`         // أيام تغطية المخزون (DOI)
	StockStatus            string  `json:"stock_status"`              // urgent_replenishment | optimal | overstock
	StockStatusAr          string  `json:"stock_status_ar"`           // خطر نفاد عاجل | رصيد آمن | تكدس مخزني
	CasePriceEGP           float64 `json:"case_price_egp"`            // سعر الكرتونة المعتمد لحساب أوامر التوريد
	WeightTons             float64 `json:"weight_tons"`
	SuggestedPOCases       int     `json:"suggested_po_cases"`        // أمر التوريد المقترح (مقرب لكرتونة كاملة)
	SuggestedPOValueEGP    float64 `json:"suggested_po_value_egp"`    // قيمة أمر التوريد المقترح بالجنيه (صافي الفاتورة)
	SuggestedPOGrossInclVATEGP float64 `json:"suggested_po_gross_incl_vat_egp"` // قيمة أمر التوريد المقترح شامل 14% ضريبة
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

	// Dynamic Matched Period (Sell-In × Sell-Out × Product Master) KPIs
	MatchedMonthsCount              int     `json:"matched_months_count"`                 // عدد الأشهر المتطابقة فعلياً (e.g. 8: Jan-Aug)
	MatchedPeriodLabel              string  `json:"matched_period_label"`                 // "يناير - أغسطس 2026 (8 أشهر متطابقة)"
	MatchedSellInCases              float64 `json:"matched_sell_in_cases"`                // إجمالي التوريد في الأشهر المتطابقة بالكرتونة
	MatchedSellInValueExclVATEGP    float64 `json:"matched_sell_in_value_excl_vat_egp"`   // إجمالي التوريد صافي بدون ضريبة في الأشهر المتطابقة
	MatchedSellInGrossInclVATEGP    float64 `json:"matched_sell_in_gross_incl_vat_egp"`   // إجمالي التوريد شامل الضريبة 14% في الأشهر المتطابقة
	MatchedSellOutUnits             int     `json:"matched_sell_out_units"`               // إجمالي مبيعات الكاشير بالقطعة في الأشهر المتطابقة
	MatchedSellOutCases             float64 `json:"matched_sell_out_cases"`               // إجمالي مبيعات الكاشير بالكرتونة (بشد الكارتة الحقيقي)
	MatchedSellOutPOSValueEGP       float64 `json:"matched_sell_out_pos_value_egp"`       // إجمالي مبيعات الكاشير بسعر المستهلك بالجنيه
	MatchedSellOutFactoryCostEGP    float64 `json:"matched_sell_out_factory_cost_egp"`    // تكلفة مبيعات الكاشير بسعر فاتورة المصنع (شامل الضريبة)
	MatchedSellOutFactoryCostExclVATEGP float64 `json:"matched_sell_out_factory_cost_excl_vat_egp"` // نفس التكلفة بدون ضريبة السلسلة (أساس هامش السلسلة)
	MatchedRemainingCases           float64 `json:"matched_remaining_cases"`              // الرصيد الدفتري الفعلي المتبقي بنهاية الفترة المتطابقة (كرتونة)
	MatchedRemainingFactoryValueEGP float64 `json:"matched_remaining_factory_value_egp"`  // قيمة الرصيد الدفتري المتبقي بسعر المصنع (ج.م)
	MatchedSellThroughPct           float64 `json:"matched_sell_through_pct"`             // نسبة التصريف الحقيقية بالكرتونة %
	MatchedChainGrossMarginEGP      float64 `json:"matched_chain_gross_margin_egp"`       // إجمالي ربح السلسلة المحقق (POS - Factory Cost)
	MatchedChainGrossMarginPct      float64 `json:"matched_chain_gross_margin_pct"`       // متوسط هامش ربح السلسلة المحقق %
	MatchedSellOutValueWithCostEGP  float64 `json:"matched_sell_out_value_with_cost_egp"` // مبيعات الكاشير التي لها تكلفة حقيقية (أساس الربح)
	MatchedMissingCostSellOutEGP    float64 `json:"matched_missing_cost_sell_out_egp"`    // مبيعات مستبعدة من الربح لعدم وجود تكلفة حقيقية
	MatchedMissingCostSellOutUnits  int     `json:"matched_missing_cost_sell_out_units"`
	MissingCostItems                []MissingCostItem `json:"missing_cost_items"`    // أصناف بدون سعر/تكلفة حقيقية مطلوبة من ادكو
	MatchedYoYUnitsGrowthPct        float64 `json:"matched_yoy_units_growth_pct"`         // نمو مبيعات القطع 2026 مقابل 2025 لنفس الأشهر %
	MatchedYoYValueGrowthPct        float64 `json:"matched_yoy_value_growth_pct"`         // نمو مبيعات القيمة 2026 مقابل 2025 لنفس الأشهر %
	MatchedYoYAvailable             bool    `json:"matched_yoy_available"`                // false = no matched month has last-year Sell-Out (show "—")
	PendingSellOutMonthsCount       int     `json:"pending_sell_out_months_count"`        // عدد أشهر التوريد بانتظار شيت الكاشير (e.g. 2: Sep-Oct)
	PendingSellOutPeriodLabel       string  `json:"pending_sell_out_period_label"`        // "سبتمبر - أكتوبر 2026"
	PendingSellOutCases             float64 `json:"pending_sell_out_cases"`               // كراتين موردة في سبتمبر وأكتوبر بانتظار شيت الكاشير
	PendingSellOutValueEGP          float64 `json:"pending_sell_out_value_egp"`            // قيمة التوريد في سبتمبر وأكتوبر بانتظار شيت الكاشير
	YTD2026GrossInclVATEGP          float64 `json:"ytd_2026_gross_incl_vat_egp"`          // إجمالي التوريد السنوي شامل الضريبة 14%
	YTD2026VATAmountEGP             float64 `json:"ytd_2026_vat_amount_egp"`              // إجمالي ضريبة القيمة المضافة 14% السنوية
	YTD2026TotalUnits               int     `json:"ytd_2026_total_units"`                 // إجمالي الوحدات (القطع) الموردة سنوياً

	MonthlyReconciliation    []ReconciliationMonthItem `json:"monthly_reconciliation"`
	InventoryAndPOItems      []SKUBranchInventoryItem  `json:"inventory_and_po_items"`
	BrandForecasts           []BrandForecastItem       `json:"brand_forecasts"`
	RegionPerformances       []RegionPerformanceItem   `json:"region_performances"`
	SalesRepScorecards       []SalesRepScorecard       `json:"sales_rep_scorecards"`
	PromoAndReturns          PromoAndReturnSummary     `json:"promo_and_returns"`
}

// TargetSKUBreakdown represents the SKU-level target allocation inside a specific branch or rolled up across an entire chain.
type TargetSKUBreakdown struct {
	ItemCode                 string  `json:"item_code,omitempty"`
	Barcode                  string  `json:"barcode,omitempty"`
	UnitsPerCarton           int     `json:"units_per_carton,omitempty"`
	DepartmentAr             string  `json:"department_ar,omitempty"`
	OfficialCartonExclVATEGP float64 `json:"official_carton_excl_vat_egp,omitempty"`
	OfficialCartonInclVATEGP float64 `json:"official_carton_incl_vat_egp,omitempty"`
	TargetPieces             int     `json:"target_pieces,omitempty"`
	ActualPieces             int     `json:"actual_pieces,omitempty"`
	SKUName                  string  `json:"sku_name"`
	Brand                    string  `json:"brand"`
	Sector                   string  `json:"sector"` // "MT" | "CC"
	SubCategory              string  `json:"sub_category"`
	SharePct                 float64 `json:"share_pct"`
	CasePriceEGP             float64 `json:"case_price_egp"`
	TargetRevenueEGP         float64 `json:"target_revenue_egp"`
	TargetUnits              float64 `json:"target_units"` // Cases for Sell-In
	TargetWeightTons         float64 `json:"target_weight_tons"`
	ActualRevenueEGP         float64 `json:"actual_revenue_egp"`
	ActualUnits              float64 `json:"actual_units"`
	ActualWeightTons         float64 `json:"actual_weight_tons"`
	ExpectedRevenueEGP       float64 `json:"expected_revenue_egp"`
	ExpectedUnits            float64 `json:"expected_units"`
	VarianceRevenueEGP       float64 `json:"variance_revenue_egp"`
	VarianceUnits            float64 `json:"variance_units"`
	AchievementPct           float64 `json:"achievement_pct"`
	RemainingStockCases      float64 `json:"remaining_stock_cases"`
	StockStatus              string  `json:"stock_status"`    // "urgent_replenishment" | "optimal" | "overstock"
	StockStatusAr            string  `json:"stock_status_ar"` // "سحب عالي / أولوية توريد" | "رصيد آمن ومتوازن" | "تكدس مخزني - تهدئة توريد"
	PromoSharePct            float64 `json:"promo_share_pct"`
}

// TargetBranchBreakdown represents the Branch-level target allocation inside a chain, along with all SKUs allocated to that branch.
type TargetBranchBreakdown struct {
	BranchCode          string               `json:"branch_code"`
	BranchName          string               `json:"branch_name"`
	RegionCode          string               `json:"region_code"`
	Governorate         string               `json:"governorate"`
	SalesRep            string               `json:"sales_rep"`
	KAOfficer           string               `json:"ka_officer"`
	ShareOfChainPct     float64              `json:"share_of_chain_pct"`
	ActiveSKUsCount     int                  `json:"active_skus_count"`
	TargetRevenueEGP    float64              `json:"target_revenue_egp"`
	TargetUnits         float64              `json:"target_units"`
	TargetWeightTons    float64              `json:"target_weight_tons"`
	GrossTargetUnits    float64              `json:"gross_target_units"`
	ActualRevenueEGP    float64              `json:"actual_revenue_egp"`
	ActualUnits         float64              `json:"actual_units"`
	ActualWeightTons    float64              `json:"actual_weight_tons"`
	ExpectedRevenueEGP  float64              `json:"expected_revenue_egp"`
	ExpectedUnits       float64              `json:"expected_units"`
	VarianceRevenueEGP  float64              `json:"variance_revenue_egp"`
	VarianceUnits       float64              `json:"variance_units"`
	AchievementRevPct   float64              `json:"achievement_rev_pct"`
	AchievementUnitsPct float64              `json:"achievement_units_pct"`
	Status              string               `json:"status"`
	StatusAr            string               `json:"status_ar"`
	SKUs                []TargetSKUBreakdown `json:"skus"`
}

// TargetBrandBreakdown summarizes the chain target allocation by Brand & Sector (MT vs CC).
type TargetBrandBreakdown struct {
	Brand              string  `json:"brand"`
	Sector             string  `json:"sector"`
	SectorNameAr       string  `json:"sector_name_ar"`
	SharePct           float64 `json:"share_pct"`
	ActiveSKUsCount    int     `json:"active_skus_count"`
	TargetRevenueEGP   float64 `json:"target_revenue_egp"`
	TargetUnits        float64 `json:"target_units"`
	TargetWeightTons   float64 `json:"target_weight_tons"`
	ActualRevenueEGP   float64 `json:"actual_revenue_egp"`
	ActualUnits        float64 `json:"actual_units"`
	ExpectedRevenueEGP float64 `json:"expected_revenue_egp"`
	VarianceRevenueEGP float64 `json:"variance_revenue_egp"`
	VarianceUnits      float64 `json:"variance_units"`
	AchievementPct     float64 `json:"achievement_pct"`
}

// TargetSalesRepQuota summarizes the automatic target quota assigned to each Field Sales Rep & KA Officer based on their branches/SKUs.
type TargetSalesRepQuota struct {
	SalesRep           string  `json:"sales_rep"`
	KAOfficer          string  `json:"ka_officer"`
	SalesManager       string  `json:"sales_manager"`
	RegionCode         string  `json:"region_code"`
	Governorate        string  `json:"governorate"`
	BranchesCount      int     `json:"branches_count"`
	ActiveSKUsCount    int     `json:"active_skus_count"`
	SharePct           float64 `json:"share_pct"`
	TargetRevenueEGP   float64 `json:"target_revenue_egp"`
	TargetUnits        float64 `json:"target_units"`
	TargetWeightTons   float64 `json:"target_weight_tons"`
	ActualRevenueEGP   float64 `json:"actual_revenue_egp"`
	ActualUnits        float64 `json:"actual_units"`
	ExpectedRevenueEGP float64 `json:"expected_revenue_egp"`
	VarianceRevenueEGP float64 `json:"variance_revenue_egp"`
	AchievementPct     float64 `json:"achievement_pct"`
	MTTargetRevenueEGP float64 `json:"mt_target_revenue_egp"`
	CCTargetRevenueEGP float64 `json:"cc_target_revenue_egp"`
}

// TargetMonthBreakdown breaks down an annual or multi-month target across individual calendar months using historical seasonality.
type TargetMonthBreakdown struct {
	Year                int     `json:"year"`
	Month               int     `json:"month"`
	MonthLabelAr        string  `json:"month_label_ar"`
	MonthLabelEn        string  `json:"month_label_en"`
	SeasonalitySharePct float64 `json:"seasonality_share_pct"`
	TargetRevenueEGP    float64 `json:"target_revenue_egp"`
	TargetUnits         float64 `json:"target_units"`
	TargetWeightTons    float64 `json:"target_weight_tons"`
	ActualRevenueEGP    float64 `json:"actual_revenue_egp"`
	ActualUnits         float64 `json:"actual_units"`
	ExpectedRevenueEGP  float64 `json:"expected_revenue_egp"`
	VarianceRevenueEGP  float64 `json:"variance_revenue_egp"`
	AchievementPct      float64 `json:"achievement_pct"`
	// HasActuals is true when the month has at least one in-scope Sell-Out row (even if revenue is 0).
	HasActuals bool `json:"has_actuals"`
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
	// Origin is "market_share" for share-wizard targets, empty/value for classic entry.
	Origin string `json:"origin,omitempty"`
	// ShareMeta is set when Origin is market_share; detail page still uses revenue/units.
	ShareMeta *ShareTargetMeta `json:"share_meta,omitempty"`
}

// TargetComparisonItem combines a saved TargetRecord with real-time Actual performance and comprehensive hierarchical drill-down (Chain -> Branch -> SKU).
type TargetComparisonItem struct {
	ID                      string                  `json:"id"`
	TenantID                string                  `json:"tenant_id"`
	TargetType              string                  `json:"target_type"`
	RetailerChain           string                  `json:"retailer_chain"`
	ChainDisplayName        string                  `json:"chain_display_name"`
	Year                    int                     `json:"year"`
	Month                   int                     `json:"month"`
	MonthLabel              string                  `json:"month_label"`
	BranchName              string                  `json:"branch_name"`
	Category                string                  `json:"category"`
	TargetRevenueEGP        float64                 `json:"target_revenue_egp"`
	ActualRevenueEGP        float64                 `json:"actual_revenue_egp"`
	VarianceRevenueEGP      float64                 `json:"variance_revenue_egp"`
	AchievementRevPct       float64                 `json:"achievement_rev_pct"`
	TargetUnits             float64                 `json:"target_units"`
	ActualUnits             float64                 `json:"actual_units"`
	VarianceUnits           float64                 `json:"variance_units"`
	AchievementUnitsPct     float64                 `json:"achievement_units_pct"`
	TargetWeightTons        float64                 `json:"target_weight_tons"`
	ActualWeightTons        float64                 `json:"actual_weight_tons"`
	ExpectedRevenueEGP      float64                 `json:"expected_revenue_egp"`
	ExpectedUnits           float64                 `json:"expected_units"`
	ExpectedAchievementPct  float64                 `json:"expected_achievement_pct"`
	AvgCasePriceEGP         float64                 `json:"avg_case_price_egp"`
	HistoricalReturnRatePct float64                 `json:"historical_return_rate_pct"`
	GrossTargetRevenueEGP   float64                 `json:"gross_target_revenue_egp"`
	GrossTargetUnits        float64                 `json:"gross_target_units"`
	PromoSharePct           float64                 `json:"promo_share_pct"`
	PromoTargetRevenueEGP   float64                 `json:"promo_target_revenue_egp"`
	RegularTargetRevenueEGP float64                 `json:"regular_target_revenue_egp"`
	MTTargetRevenueEGP      float64                 `json:"mt_target_revenue_egp"`
	CCTargetRevenueEGP      float64                 `json:"cc_target_revenue_egp"`
	BranchesCount           int                     `json:"branches_count"`
	ActiveSKUsCount         int                     `json:"active_skus_count"`
	// HasActuals is false when the target period has no actual rows in scope (e.g. a future year).
	// Such a target is not comparable: achieved / achievement / gap must read "—", never 0.
	HasActuals              bool                    `json:"has_actuals"`
	Status                  string                  `json:"status"`    // "exceeded" | "on_track" | "at_risk" | "no_data"
	StatusAr                string                  `json:"status_ar"` // "تجاوز المستهدف" | "قيد التحقيق" | "أقل من المستهدف"
	Notes                   string                  `json:"notes"`
	UpdatedAt               string                  `json:"updated_at"`
	Origin                  string                  `json:"origin,omitempty"`
	ShareMeta               *ShareTargetMeta        `json:"share_meta,omitempty"`
	Branches                []TargetBranchBreakdown `json:"branches"`
	ChainSKUTotals          []TargetSKUBreakdown    `json:"chain_sku_totals"`
	Brands                  []TargetBrandBreakdown  `json:"brands"`
	SalesRepQuotas          []TargetSalesRepQuota   `json:"sales_rep_quotas"`
	MonthlyPhasing          []TargetMonthBreakdown  `json:"monthly_phasing"`
}

// TargetsSummaryResponse returns the list of target comparisons along with rolled-up totals.
type TargetsSummaryResponse struct {
	TenantID                  string                 `json:"tenant_id"`
	TargetType                string                 `json:"target_type"`
	TotalTargetRevenueEGP     float64                `json:"total_target_revenue_egp"`
	TotalActualRevenueEGP     float64                `json:"total_actual_revenue_egp"`
	TotalVarianceEGP          float64                `json:"total_variance_egp"`
	OverallAchievementPct     float64                `json:"overall_achievement_pct"`
	TotalTargetUnits          float64                `json:"total_target_units"`
	TotalActualUnits          float64                `json:"total_actual_units"`
	TotalTargetWeightTons     float64                `json:"total_target_weight_tons"`
	TotalActualWeightTons     float64                `json:"total_actual_weight_tons"`
	TotalExpectedRevenueEGP   float64                `json:"total_expected_revenue_egp"`
	TotalExpectedUnits        float64                `json:"total_expected_units"`
	TotalGrossTargetRevenueEGP float64               `json:"total_gross_target_revenue_egp"`
	TotalGrossTargetUnits     float64                `json:"total_gross_target_units"`
	AvgCasePriceEGP           float64                `json:"avg_case_price_egp"`
	TotalBranchesCovered      int                    `json:"total_branches_covered"`
	TotalSKUsCovered          int                    `json:"total_skus_covered"`
	// Comparable* cover only targets whose period has actual data. Total*Revenue/Units above keep every
	// target (a future-year target counts in TotalTarget*), while achievement and variance are computed
	// on the comparable subset so a future year cannot drag them down.
	ComparableTargetRevenueEGP float64 `json:"comparable_target_revenue_egp"`
	ComparableActualRevenueEGP float64 `json:"comparable_actual_revenue_egp"`
	ComparableTargetsCount     int     `json:"comparable_targets_count"`
	NoDataTargetsCount         int     `json:"no_data_targets_count"`
	NoDataTargetRevenueEGP     float64 `json:"no_data_target_revenue_egp"`
	NoDataTargetUnits          float64 `json:"no_data_target_units"`
	Items                     []TargetComparisonItem `json:"items"`
}

// NormalizeBrandKey lowercases and folds Arabic letter variants so
// "فلفيتا" and "فلڤيتا" compare equal.
func NormalizeBrandKey(s string) string {
	s = strings.ToLower(strings.TrimSpace(s))
	s = strings.ReplaceAll(s, "ڤ", "ف")
	s = strings.ReplaceAll(s, "ى", "ي")
	s = strings.ReplaceAll(s, "ة", "ه")
	return s
}

// BrandLabelParts splits "عربي (English)" into Arabic / English / full keys.
func BrandLabelParts(label string) (ar, en, full string) {
	full = NormalizeBrandKey(label)
	if full == "" {
		return "", "", ""
	}
	open := strings.LastIndex(label, "(")
	close := strings.LastIndex(label, ")")
	if open >= 0 && close > open {
		ar = NormalizeBrandKey(label[:open])
		en = NormalizeBrandKey(label[open+1 : close])
		return ar, en, full
	}
	return full, "", full
}

// BrandLabelMatches reports whether an inferred catalog brand matches a UI/API
// brand filter. Accepts full labels ("ديفا (Diva)"), Arabic-only ("ديفا" /
// "فلفيتا"), or English-only ("Diva" / "Velveta"), with ڤ/ف folding.
func BrandLabelMatches(inferred, filter string) bool {
	filter = strings.TrimSpace(filter)
	if filter == "" || filter == "all" || filter == "الكل" || filter == "كل العلامات التجارية" {
		return true
	}
	aAr, aEn, aFull := BrandLabelParts(inferred)
	bAr, bEn, bFull := BrandLabelParts(filter)
	if aFull == "" || bFull == "" {
		return false
	}
	if aFull == bFull {
		return true
	}
	candidates := func(ar, en, full string) []string {
		out := []string{full}
		if ar != "" {
			out = append(out, ar)
		}
		if en != "" {
			out = append(out, en)
		}
		return out
	}
	for _, a := range candidates(aAr, aEn, aFull) {
		for _, b := range candidates(bAr, bEn, bFull) {
			if a == b {
				return true
			}
		}
	}
	return false
}

// InferBrandFromItemName uses AI-grade heuristic brand extraction across Arabic & English FMCG and retail goods.
// It recognizes established brands and dynamically extracts novel brand tokens for any company.
func InferBrandFromItemName(itemName, subCategory string) string {
	s := strings.ToLower(itemName + " " + subCategory)
	switch {
	case strings.Contains(s, "ماكسيل") || strings.Contains(s, "maxel"):
		return "ماكسيل (Maxell)"
	// Divatol is an Adeco Diva-line SKU; match the longer token before "ديفا".
	case strings.Contains(s, "ديفاتول") || strings.Contains(s, "divatol"):
		return "ديفا (Diva)"
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
	case strings.Contains(s, "جلاسي") || strings.Contains(s, "جلاسى") || strings.Contains(s, "glassy"):
		return "جلاسي (Glassy)"
	case strings.Contains(s, "سبيد") || strings.Contains(s, "speed"):
		return "سبيد (Speed)"
	case strings.Contains(s, "رابيدو") || strings.Contains(s, "rapido"):
		return "رابيدو (Rapido)"
	case strings.Contains(s, "فما") || strings.Contains(s, "فيما") || strings.Contains(s, "fema"):
		return "فيما (Fema)"
	case strings.Contains(s, "كلوريل") || strings.Contains(s, "clorel"):
		return "كلوريل (Clorel)"
	case strings.Contains(s, "جنرال") || strings.Contains(s, "general"):
		return "جنرال (General)"
	case strings.Contains(s, "أريال") || strings.Contains(s, "اريال") || strings.Contains(s, "ariel"):
		return "أريال (Ariel)"
	case strings.Contains(s, "برسيل") || strings.Contains(s, "persil"):
		return "برسيل (Persil)"
	case strings.Contains(s, "أوكسى") || strings.Contains(s, "اوكسى") ||
		strings.Contains(s, "أوكسي") || strings.Contains(s, "اوكسي") ||
		strings.Contains(s, "oxi"):
		return "أوكسي (Oxi)"
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
		clean := strings.TrimSpace(strings.TrimLeft(itemName, "* "))
		if clean == "" {
			if subCategory != "" {
				return subCategory
			}
			return "أصناف عامة"
		}
		parts := strings.Fields(clean)
		if len(parts) > 0 && parts[0] == "عرض" && len(parts) > 1 {
			parts = parts[1:]
		}
		// Skip generic placeholders that are not real brand tokens.
		for len(parts) > 0 && (parts[0] == "منافس" || parts[0] == "المنافس") {
			parts = parts[1:]
		}
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




// MissingCostItem is a Sell-Out item with no real factory cost (not in the Sell-Out sheet
// and not resolvable from the product master). Its cost and margin are left empty.
type MissingCostItem struct {
	ItemCode        string   `json:"item_code"`
	Barcode         string   `json:"barcode"`
	SKUName         string   `json:"sku_name"`
	Chains          []string `json:"chains"`
	UnitsSold       int      `json:"units_sold"`
	SalesValueEGP   float64  `json:"sales_value_egp"`
	Reason          string   `json:"reason"`    // not_in_master | no_price_in_master
	ReasonAr        string   `json:"reason_ar"`
	MasterItemCode  string   `json:"master_item_code,omitempty"`
	MasterName      string   `json:"master_name,omitempty"`
}
