package domain

import "time"

// ChainDiscountProfile holds the discounts Adeco gives one retail chain.
// Percentages are whole numbers (10 = 10%).
type ChainDiscountProfile struct {
	Chain                 string    `json:"chain" firestore:"chain"`
	InvoiceDiscountPct    float64   `json:"invoice_discount_pct" firestore:"invoice_discount_pct"`
	AdditionalDiscountPct float64   `json:"additional_discount_pct" firestore:"additional_discount_pct"`
	UpdatedAt             time.Time `json:"updated_at" firestore:"updated_at"`
	UpdatedBy             string    `json:"updated_by,omitempty" firestore:"updated_by"`
}

// ChainDiscountProfiles is the per-tenant document (one doc per tenant).
type ChainDiscountProfiles struct {
	TenantID  string                 `json:"tenant_id" firestore:"tenant_id"`
	Profiles  []ChainDiscountProfile `json:"profiles" firestore:"profiles"`
	UpdatedAt time.Time              `json:"updated_at" firestore:"updated_at"`
	UpdatedBy string                 `json:"updated_by,omitempty" firestore:"updated_by"`
}
