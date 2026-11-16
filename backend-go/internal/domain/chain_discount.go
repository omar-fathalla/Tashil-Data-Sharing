package domain

import "time"

// Defaults for a chain without a saved profile (percent, whole numbers).
const (
	DefaultChainInvoiceDiscountPct    = 10.0
	DefaultChainAdditionalDiscountPct = 0.0
	DefaultChainVATRatePct            = 14.0
)

// ChainDiscountProfile holds the commercial terms Adeco gives one retail chain: they are the single
// source of truth for that chain's Sell-In waterfall, VAT and factory cost.
// Percentages are whole numbers (10 = 10%).
type ChainDiscountProfile struct {
	Chain                 string  `json:"chain" firestore:"chain"`
	InvoiceDiscountPct    float64 `json:"invoice_discount_pct" firestore:"invoice_discount_pct"`
	AdditionalDiscountPct float64 `json:"additional_discount_pct" firestore:"additional_discount_pct"`
	// VATRatePct is the chain's VAT rate (14 = 14%). nil = not set: the Product Master column, then 14%, apply.
	VATRatePct *float64  `json:"vat_rate_pct,omitempty" firestore:"vat_rate_pct,omitempty"`
	UpdatedAt  time.Time `json:"updated_at" firestore:"updated_at"`
	UpdatedBy  string    `json:"updated_by,omitempty" firestore:"updated_by"`
}

// VATRate returns the chain's VAT as a fraction (0.14) and whether the profile sets one.
func (p ChainDiscountProfile) VATRate() (float64, bool) {
	if p.VATRatePct == nil {
		return 0, false
	}
	return *p.VATRatePct / 100.0, true
}

// ChainDiscountProfiles is the per-tenant document (one doc per tenant).
type ChainDiscountProfiles struct {
	TenantID  string                 `json:"tenant_id" firestore:"tenant_id"`
	Profiles  []ChainDiscountProfile `json:"profiles" firestore:"profiles"`
	UpdatedAt time.Time              `json:"updated_at" firestore:"updated_at"`
	UpdatedBy string                 `json:"updated_by,omitempty" firestore:"updated_by"`
}
