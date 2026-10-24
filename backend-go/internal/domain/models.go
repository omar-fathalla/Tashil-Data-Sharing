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

// ProductMasterItem represents an authoritative factory SKU and pricing definition from the company's Product Master sheet (كارتة الأصناف والأسعار).
type ProductMasterItem struct {
	SerialNo              int      `json:"serial_no"`
	TenantID              string   `json:"tenant_id,omitempty"`
	ItemCode              string   `json:"item_code"`                         // كود الصنف (e.g., FGCL-0550-0001)
	ItemCodePrefix        string   `json:"item_code_prefix"`                  // FGCL, FGDG, FGDW, FGGC, FGHC, FGLC, FGPC, PRGC, PRHC, PRLC, PRPC
	ERPPrefix             string   `json:"erp_prefix,omitempty"`              // Alias for ItemCodePrefix
	DepartmentAr          string   `json:"department_ar,omitempty"`           // القسم بالعربية حسب البادئة
	Barcode               string   `json:"barcode"`                           // الباركود الدولي EAN-13
	OfficialName          string   `json:"official_name"`                     // اسم الصنف الرسمي المعتمد
	Brand                 string   `json:"brand"`                             // العلامة التجارية المستنتجة
	Category              string   `json:"category"`                          // الفئة المستنتجة من البادئة والاسم
	ItemType              string   `json:"item_type"`                         // "عادي" | "عرض"
	PackagingType         string   `json:"packaging_type"`                    // "زجاجة" | "جركن" | "عبوة" | "مجموعة" | "كرتونة"
	UnitsPerCarton        int      `json:"units_per_carton"`                  // عدد الوحدات بالكرتونة
	VATRate               float64  `json:"vat_rate"`                          // 0.14 (14%)
	UnitPriceExclVAT      float64  `json:"unit_price_excl_vat"`               // سعر العبوة غير شامل الضريبة
	UnitPriceInclVAT      float64  `json:"unit_price_incl_vat"`               // سعر العبوة شامل الضريبة
	CartonPriceExclVAT    float64  `json:"carton_price_excl_vat"`             // سعر الكرتونة غير شامل الضريبة
	CartonPriceInclVAT    float64  `json:"carton_price_incl_vat"`             // سعر الكرتونة شامل الضريبة
	InvoiceDiscountPct    float64  `json:"invoice_discount_pct"`              // نسبة خصم الفاتورة (default 0.10)
	ExtraDiscountPct      float64  `json:"extra_discount_pct"`                // نسبة الخصم الإضافية
	NetUnitInvoiceCost    float64  `json:"net_unit_invoice_cost"`             // سعر القطعة بعد خصم الفاتورة
	NetCartonInvoiceCost  float64  `json:"net_carton_invoice_cost"`           // سعر الكرتونة بعد خصم الفاتورة
	IsPrimaryForBarcode   bool     `json:"is_primary_for_barcode"`            // True for the primary regular pack of a shared barcode
	IsActiveInChains      bool     `json:"is_active_in_chains"`               // True if pulled/sold in any retail chain
	TotalPOSUnitsSold     int      `json:"total_pos_units_sold"`              // إجمالي القطع المباعة فعلياً بالسلاسل
	TotalPOSCartonsSold   float64  `json:"total_pos_cartons_sold"`            // إجمالي الكراتين المباعة فعلياً بالسلاسل
	TotalPOSRevenue       float64  `json:"total_pos_revenue"`                 // إجمالي مبيعات الكاشير بالسلاسل بالجنيه
	AvgRetailSellingPrice float64  `json:"avg_retail_selling_price,omitempty"` // متوسط سعر بيع المستهلك الفعلي بالسلاسل
	ActiveChains          []string `json:"active_chains"`                     // السلاسل النشطة التي تسحب الصنف
	SourceFilename             string   `json:"source_filename,omitempty"`
	SheetName                  string   `json:"sheet_name,omitempty"`
	UpdatedAt                  string   `json:"updated_at"`
	PrevUnitPriceExclVAT       float64  `json:"prev_unit_price_excl_vat,omitempty"`
	PrevUnitPriceInclVAT       float64  `json:"prev_unit_price_incl_vat,omitempty"`
	PrevCartonPriceInclVAT     float64  `json:"prev_carton_price_incl_vat,omitempty"`
	PrevNetUnitInvoiceCost     float64  `json:"prev_net_unit_invoice_cost,omitempty"`
	PrevNetCartonInvoiceCost   float64  `json:"prev_net_carton_invoice_cost,omitempty"`
	PriceChangeDirection       string   `json:"price_change_direction,omitempty"` // "up" | "down" | "new" | "same"
	PriceChangeDiffEGP         float64  `json:"price_change_diff_egp,omitempty"`
	PriceChangePct             float64  `json:"price_change_pct,omitempty"`
}

// ProductMasterDiffItem summarizes a single SKU price change or newly added SKU in a sheet comparison.
type ProductMasterDiffItem struct {
	ItemCode           string  `json:"item_code"`
	OfficialName       string  `json:"official_name"`
	Brand              string  `json:"brand,omitempty"`
	OldUnitPriceIncl   float64 `json:"old_unit_price_incl"`
	NewUnitPriceIncl   float64 `json:"new_unit_price_incl"`
	OldCartonPriceIncl float64 `json:"old_carton_price_incl,omitempty"`
	NewCartonPriceIncl float64 `json:"new_carton_price_incl,omitempty"`
	DiffEGP            float64 `json:"diff_egp"`
	DiffPct            float64 `json:"diff_pct"`
	Direction          string  `json:"direction"` // "up" | "down" | "new" | "same"
}

// ProductMasterDiffSummary provides an automated AI/diff report between a newly uploaded Product Master sheet and the previous version.
type ProductMasterDiffSummary struct {
	ComparedAgainstFile string                  `json:"compared_against_file"`
	NewFileName         string                  `json:"new_file_name"`
	ComparedAt          string                  `json:"compared_at"`
	TotalSKUsCompared   int                     `json:"total_skus_compared"`
	PriceIncreasedCount int                     `json:"price_increased_count"`
	PriceDecreasedCount int                     `json:"price_decreased_count"`
	PriceUnchangedCount int                     `json:"price_unchanged_count"`
	NewSKUsCount        int                     `json:"new_skus_count"`
	AvgPriceIncreasePct float64                 `json:"avg_price_increase_pct"`
	AvgPriceDecreasePct float64                 `json:"avg_price_decrease_pct"`
	TopChangedItems     []ProductMasterDiffItem `json:"top_changed_items,omitempty"`
}

// ProductMasterSummaryResponse returns the full product master catalog and summary KPIs.
type ProductMasterSummaryResponse struct {
	TenantID            string                    `json:"tenant_id"`
	CompanyName         string                    `json:"company_name"`
	SheetDateLabel      string                    `json:"sheet_date_label"`
	SourceFilename      string                    `json:"source_filename"`
	DefaultDiscountPct  float64                   `json:"default_discount_pct"`
	DefaultVATRate      float64                   `json:"default_vat_rate"`
	TotalSKUs           int                       `json:"total_skus"`
	RegularSKUsCount    int                       `json:"regular_skus_count"`
	PromoSKUsCount      int                       `json:"promo_skus_count"`
	UniqueBarcodesCount int                       `json:"unique_barcodes_count"`
	ActiveInChainsCount int                       `json:"active_in_chains_count"`
	UnpulledSKUsCount   int                       `json:"unpulled_skus_count"`
	PriceIncreasedCount int                       `json:"price_increased_count"`
	PriceDecreasedCount int                       `json:"price_decreased_count"`
	PriceUnchangedCount int                       `json:"price_unchanged_count"`
	NewSKUsCount        int                       `json:"new_skus_count"`
	AvgUnitsPerCarton   float64                   `json:"avg_units_per_carton"`
	AvailablePrefixes   []string                  `json:"available_prefixes"`
	AvailableBrands     []string                  `json:"available_brands"`
	AvailablePackaging  []string                  `json:"available_packaging"`
	DiffSummary          *ProductMasterDiffSummary `json:"diff_summary,omitempty"`
	Items                []ProductMasterItem       `json:"items"`
	SupplementalPOSItems []ProductMasterItem       `json:"supplemental_pos_items,omitempty"`
}

// NormalizeItemCode canonicalizes an item code to uppercase trimmed format (e.g., "FGLc-0730-0019" -> "FGLC-0730-0019").
func NormalizeItemCode(code string) string {
	return strings.ToUpper(strings.TrimSpace(code))
}

// ExtractItemCodePrefix returns the alphabetic prefix before the first '-' in an item code (e.g. "FGCL-0550-0001" -> "FGCL").
func ExtractItemCodePrefix(code string) string {
	norm := NormalizeItemCode(code)
	if idx := strings.IndexByte(norm, '-'); idx > 0 {
		return norm[:idx]
	}
	return norm
}

// InferDepartmentArFromPrefix maps an Adeco ERP item code prefix to its canonical Arabic department label.
func InferDepartmentArFromPrefix(prefix string) string {
	p := strings.ToUpper(strings.TrimSpace(prefix))
	switch p {
	case "FGCL":
		return "كلور ومبيضات"
	case "FGDG":
		return "منظفات الأطباق السائلة"
	case "FGDW", "FGLW":
		return "منظفات غسالات الأطباق الأوتوماتيك"
	case "FGLC":
		return "العناية بالملابس والمنسوجات"
	case "FGGC":
		return "منظفات وملمعات الزجاج والأسطح"
	case "FGHC":
		return "العناية المنزلية والمطهرات"
	case "FGPC":
		return "العناية الشخصية"
	default:
		if strings.HasPrefix(p, "PR") {
			return "عروض ترويجية مجمعة"
		}
		return "أصناف أدكو"
	}
}

// InferCategoryFromItemCodeAndName maps Adeco item code prefixes and Arabic product names to canonical categories.
func InferCategoryFromItemCodeAndName(prefix, name string) string {
	p := strings.ToUpper(strings.TrimSpace(prefix))
	n := strings.ToLower(strings.TrimSpace(name))
	switch {
	case strings.Contains(n, "كلور ألوان") || strings.Contains(n, "كلور الوان"):
		return "كلور ألوان"
	case strings.Contains(n, "كلور") || p == "FGCL":
		return "كلور عادى"
	case strings.Contains(n, "غسالات اطباق") || strings.Contains(n, "غسالات أطباق") || p == "FGDW" || p == "FGLW":
		return "مسحوق غسالات اطباق"
	case strings.Contains(n, "أطباق") || strings.Contains(n, "اطباق") || p == "FGDG":
		return "صابون سائل اطباق"
	case strings.Contains(n, "منعم") || strings.Contains(n, "معطر ملابس") || strings.Contains(n, "داوني"):
		return "منعمات ملابس"
	case strings.Contains(n, "زجاج") || strings.Contains(n, "ملمع زجاج") || strings.Contains(n, "جلاسي") || strings.Contains(n, "جلاسى") || p == "FGGC" || p == "PRGC":
		return "ملمع زجاج وكريستال"
	case strings.Contains(n, "بقع"):
		return "مزيلات بقع ملابس"
	case strings.Contains(n, "عباية") || strings.Contains(n, "عبايه") || strings.Contains(n, "جينز") || strings.Contains(n, "ملابس") || strings.Contains(n, "جل غسيل") || strings.Contains(n, "مسحوق") || p == "FGLC" || p == "PRLC":
		return "مساحيق جيل اتوماتيك"
	case strings.Contains(n, "تواليت") || strings.Contains(n, "حمام"):
		return "منظفات تواليت"
	case strings.Contains(n, "مطبخ") || strings.Contains(n, "مطابخ") || strings.Contains(n, "دهون") || strings.Contains(n, "بوتاجاز") || strings.Contains(n, "افران") || strings.Contains(n, "أفران"):
		return "منظفات مطبخ"
	case strings.Contains(n, "أخشاب") || strings.Contains(n, "اخشاب") || strings.Contains(n, "باركيه") || strings.Contains(n, "أثاث") || strings.Contains(n, "اثاث"):
		return "ملمع اخشاب وباركيه"
	case strings.Contains(n, "سجاد") || strings.Contains(n, "مفروشات"):
		return "منظفات سجاد ومفروشات"
	case strings.Contains(n, "مسلك") || strings.Contains(n, "بالوعات") || strings.Contains(n, "احواض") || strings.Contains(n, "أحواض"):
		return "مسلك احواض وبالوعات"
	case strings.Contains(n, "معطر جو") || strings.Contains(n, "معطرات جو"):
		return "معطر جو"
	case strings.Contains(n, "مطهر") || strings.Contains(n, "ديفاتول") || strings.Contains(n, "ديفاسول") || strings.Contains(n, "ديتول") || strings.Contains(n, "فينيك"):
		return "مطهر عام"
	case strings.Contains(n, "أرضيات") || strings.Contains(n, "ارضيات") || strings.Contains(n, "جنرال"):
		return "منظف ارضيات"
	case strings.Contains(n, "شاور") || strings.Contains(n, "استحمام"):
		return "شاور جيل"
	case strings.Contains(n, "هاند") || strings.Contains(n, "غسول يد") || strings.Contains(n, "صابون يد") || strings.Contains(n, "فوم"):
		return "هاند وواش"
	case strings.Contains(n, "شامبو") || strings.Contains(n, "بلسم") || strings.Contains(n, "شعر") || strings.Contains(n, "كريم") || strings.Contains(n, "لوشن") || strings.Contains(n, "بشرة") || strings.Contains(n, "وجه") || p == "FGPC" || p == "PRPC":
		return "عناية شخصية"
	case strings.Contains(n, "سيارات") || strings.Contains(n, "ردياتير") || strings.Contains(n, "تابلوه") || strings.Contains(n, "إطارات") || strings.Contains(n, "اطارات") || strings.Contains(n, "موتور") || strings.Contains(n, "رابيدو"):
		return "عناية بالسيارات"
	case p == "FGHC" || p == "PRHC":
		return "منظف ارضيات"
	default:
		return "منظفات منزلية"
	}
}

// MatchesProductSearchQuery checks if a user search query matches an item by ItemCode (including prefixes and FGSL phonetic alias),
// Barcode, SKUName, OfficialName, Category, or Brand.
func MatchesProductSearchQuery(rawQuery, itemCode, barcode, skuName, officialName, category, brand string) bool {
	q := strings.ToLower(strings.TrimSpace(rawQuery))
	if q == "" {
		return true
	}
	codeLower := strings.ToLower(strings.TrimSpace(itemCode))
	codeCompact := strings.ReplaceAll(codeLower, "-", "")
	qCompact := strings.ReplaceAll(q, "-", "")

	if codeLower != "" {
		if strings.Contains(codeLower, q) || strings.Contains(codeCompact, qCompact) {
			return true
		}
		// Phonetic alias: users typing "fgsl" (إف جي إس إل) should match "fgcl" (Clorel) and "fglc" (Laundry Care)
		if strings.HasPrefix(qCompact, "fgsl") {
			alt1 := "fgcl" + strings.TrimPrefix(qCompact, "fgsl")
			alt2 := "fglc" + strings.TrimPrefix(qCompact, "fgsl")
			if strings.Contains(codeCompact, alt1) || strings.Contains(codeCompact, alt2) {
				return true
			}
		}
	}
	if barcode != "" && strings.Contains(strings.ToLower(barcode), q) {
		return true
	}
	if skuName != "" && strings.Contains(strings.ToLower(skuName), q) {
		return true
	}
	if officialName != "" && strings.Contains(strings.ToLower(officialName), q) {
		return true
	}
	if category != "" && strings.Contains(strings.ToLower(category), q) {
		return true
	}
	if brand != "" && strings.Contains(strings.ToLower(brand), q) {
		return true
	}
	return false
}

// SellOutFact represents an atomic sell-out transaction loaded into Google BigQuery.
type SellOutFact struct {
	RecordID             string    `json:"record_id" bigquery:"record_id"`
	TenantID             string    `json:"tenant_id" bigquery:"tenant_id"`
	RetailerChain        string    `json:"retailer_chain" bigquery:"retailer_chain"`
	StoreID              string    `json:"store_id" bigquery:"store_id"`
	StoreName            string    `json:"store_name" bigquery:"store_name"`
	ItemCode             string    `json:"item_code,omitempty" bigquery:"item_code"`
	Barcode              string    `json:"barcode" bigquery:"barcode"`
	SKUName              string    `json:"sku_name" bigquery:"sku_name"`
	RetailerRawSKUName   string    `json:"retailer_raw_sku_name,omitempty" bigquery:"retailer_raw_sku_name"`
	Category             string    `json:"category" bigquery:"category"`
	Supplier             string    `json:"supplier,omitempty" bigquery:"supplier"`
	IsOwnBrand           bool      `json:"is_own_brand" bigquery:"is_own_brand"`
	UnitsPerCarton       int       `json:"units_per_carton,omitempty" bigquery:"units_per_carton"`
	ItemType             string    `json:"item_type,omitempty" bigquery:"item_type"`
	FactoryUnitCost      float64   `json:"factory_unit_cost,omitempty" bigquery:"factory_unit_cost"`
	CartonPriceInclVAT   float64   `json:"carton_price_incl_vat,omitempty" bigquery:"carton_price_incl_vat"`
	NetCartonInvoiceCost float64   `json:"net_carton_invoice_cost,omitempty" bigquery:"net_carton_invoice_cost"`
	InvoiceDiscountPct   float64   `json:"invoice_discount_pct,omitempty" bigquery:"invoice_discount_pct"`
	QuantitySold         int       `json:"quantity_sold" bigquery:"quantity_sold"`
	CartonsSold          float64   `json:"cartons_sold,omitempty" bigquery:"cartons_sold"`
	NetRevenue           float64   `json:"net_revenue" bigquery:"net_revenue"`
	UnitPrice            float64   `json:"unit_price" bigquery:"unit_price"`
	RecommendedPrice     float64   `json:"recommended_price,omitempty" bigquery:"recommended_price"`
	TotalFactoryCost     float64   `json:"total_factory_cost,omitempty" bigquery:"total_factory_cost"`
	RetailerGrossProfit  float64   `json:"retailer_gross_profit,omitempty" bigquery:"retailer_gross_profit"`
	RetailerMarginPct    float64   `json:"retailer_margin_pct,omitempty" bigquery:"retailer_margin_pct"`
	PriceDeltaPct        float64   `json:"price_delta_pct,omitempty" bigquery:"price_delta_pct"`
	TransactionDate      string    `json:"transaction_date" bigquery:"transaction_date"` // YYYY-MM-DD
	IngestionBatchID     string    `json:"ingestion_batch_id" bigquery:"ingestion_batch_id"`
	IngestedAt           time.Time `json:"ingested_at" bigquery:"ingested_at"`
}

// SellOutSKUSummary aggregates full-dataset sell-out performance, official factory pricing, and chain margin for a single SKU across the selected filter scope.
type SellOutSKUSummary struct {
	ItemCode             string   `json:"item_code"`
	Barcode              string   `json:"barcode"`
	SKUName              string   `json:"sku_name"`
	RetailerRawSKUName   string   `json:"retailer_raw_sku_name,omitempty"`
	Brand                string   `json:"brand"`
	Category             string   `json:"category"`
	ItemType             string   `json:"item_type"`
	UnitsPerCarton       int      `json:"units_per_carton"`
	TotalUnitsSold       int      `json:"total_units_sold"`
	TotalCartonsSold     float64  `json:"total_cartons_sold"`
	TotalNetRevenue      float64  `json:"total_net_revenue"`
	AvgSellingPrice      float64  `json:"avg_selling_price"`
	OfficialConsumerRSP  float64  `json:"official_consumer_rsp"`
	FactoryUnitCost      float64  `json:"factory_unit_cost"`
	CartonPriceInclVAT   float64  `json:"carton_price_incl_vat"`
	NetCartonInvoiceCost float64  `json:"net_carton_invoice_cost"`
	InvoiceDiscountPct   float64  `json:"invoice_discount_pct"`
	TotalFactoryCost     float64  `json:"total_factory_cost"`
	RetailerGrossProfit  float64  `json:"retailer_gross_profit"`
	RetailerMarginPct    float64  `json:"retailer_margin_pct"`
	PriceDeltaPct        float64  `json:"price_delta_pct"`
	PriceStatus          string   `json:"price_status"`
	ActiveStoresCount    int      `json:"active_stores_count"`
	ActiveChains         []string `json:"active_chains"`
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
	ItemCode               string    `json:"item_code,omitempty"`
	Barcode                string    `json:"barcode"`
	SKUName                string    `json:"sku_name"`
	Brand                  string    `json:"brand,omitempty"`
	Category               string    `json:"category"`
	UnitsPerCarton         int       `json:"units_per_carton,omitempty"`
	ItemType               string    `json:"item_type,omitempty"`
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
	// TenantRank is the tenant's 1-based revenue rank among all suppliers in the category (0 = unknown).
	TenantRank int `json:"tenant_rank,omitempty"`
	// SupplierCount is the number of distinct suppliers selling in the category.
	SupplierCount int `json:"supplier_count,omitempty"`
	// TopCompetitors are the largest named competitor suppliers in the category.
	TopCompetitors []CategoryCompetitor `json:"top_competitors,omitempty"`
}

// CategoryCompetitor is one named competitor supplier's revenue and share in a category.
type CategoryCompetitor struct {
	Name     string  `json:"name"`
	Revenue  float64 `json:"revenue"`
	SharePct float64 `json:"share_pct"`
}

// ParetoSKUItem represents a SKU in the 80/20 Pareto revenue analysis.
type ParetoSKUItem struct {
	ItemCode           string  `json:"item_code,omitempty"`
	Barcode            string  `json:"barcode"`
	SKUName            string  `json:"sku_name"`
	Category           string  `json:"category"`
	UnitsPerCarton     int     `json:"units_per_carton,omitempty"`
	ItemType           string  `json:"item_type,omitempty"`
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
