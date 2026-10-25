package domain

import "time"

// Data-quality issue severities and statuses (Arabic values are what the UI shows).
const (
	DQSeverityCritical = "حرجة"
	DQSeverityWarning  = "تحذير"

	DQStatusOpen     = "مفتوحة"
	DQStatusResolved = "اتصلّحت"
	DQStatusIgnored  = "متجاهلة"

	DQSourceProductMaster = "product_master"
)

// Product Master issue types.
const (
	DQTypeDuplicateBarcode      = "duplicate_barcode"
	DQTypeMissingCode           = "missing_code"
	DQTypeMissingBarcode        = "missing_barcode"
	DQTypeInvalidPrice          = "invalid_price"
	DQTypeCartonPriceMismatch   = "carton_price_mismatch"
	DQTypeVATNot14              = "vat_not_14"
	DQTypeInvoiceDiscountRange  = "invoice_discount_out_of_range"
	DQTypeMissingPackType       = "missing_pack_type"
	DQTypeMissingUnitsPerCarton = "missing_units_per_carton"
	DQTypeNACell                = "na_cell"
	DQTypeMalformedBarcode      = "malformed_barcode"
)

// DataQualityIssue is one problem found in an uploaded source sheet.
type DataQualityIssue struct {
	ID            string    `json:"id" firestore:"id"`
	Source        string    `json:"source" firestore:"source"`
	Type          string    `json:"type" firestore:"type"`
	TypeLabel     string    `json:"type_label" firestore:"type_label"`
	Severity      string    `json:"severity" firestore:"severity"`
	Sheet         string    `json:"sheet" firestore:"sheet"`
	Row           int       `json:"row" firestore:"row"`       // Excel row number (1-based)
	Column        string    `json:"column" firestore:"column"` // header of the offending column
	ItemCode      string    `json:"item_code" firestore:"item_code"`
	Barcode       string    `json:"barcode" firestore:"barcode"`
	SKUName       string    `json:"sku_name" firestore:"sku_name"`
	FoundValue    string    `json:"found_value" firestore:"found_value"`
	ExpectedValue string    `json:"expected_value" firestore:"expected_value"`
	ImpactEGP     *float64  `json:"impact_egp" firestore:"impact_egp"` // nil = not computable
	ImpactBasis   string    `json:"impact_basis,omitempty" firestore:"impact_basis"`
	Status        string    `json:"status" firestore:"status"`
	StatusReason  string    `json:"status_reason,omitempty" firestore:"status_reason"`
	StatusBy      string    `json:"status_by,omitempty" firestore:"status_by"`
	AutoClosed    bool       `json:"auto_closed,omitempty" firestore:"auto_closed"`
	ResolvedAt    *time.Time `json:"resolved_at,omitempty" firestore:"resolved_at"`
	SourceFile    string    `json:"source_file,omitempty" firestore:"source_file"`
	FirstSeen     time.Time `json:"first_seen" firestore:"first_seen"`
	LastSeen      time.Time `json:"last_seen" firestore:"last_seen"`
	UpdatedAt     time.Time `json:"updated_at" firestore:"updated_at"`
}

// DataQualityRun records the size of the last checked file per source.
type DataQualityRun struct {
	Source       string    `json:"source" firestore:"source"`
	SourceFile   string    `json:"source_file" firestore:"source_file"`
	Sheet        string    `json:"sheet" firestore:"sheet"`
	TotalRows    int       `json:"total_rows" firestore:"total_rows"`
	CriticalRows int       `json:"critical_rows" firestore:"critical_rows"`
	RanAt        time.Time `json:"ran_at" firestore:"ran_at"`
}

// DataQualityState is everything persisted per tenant.
type DataQualityState struct {
	TenantID  string             `json:"tenant_id" firestore:"tenant_id"`
	Issues    []DataQualityIssue `json:"issues" firestore:"issues"`
	Runs      []DataQualityRun   `json:"runs" firestore:"runs"`
	UpdatedAt time.Time          `json:"updated_at" firestore:"updated_at"`
}
