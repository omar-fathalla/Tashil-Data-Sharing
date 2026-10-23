package domain

import "time"

// MarketingExpenseCategories lists the accepted trade-marketing spend categories.
var MarketingExpenseCategories = map[string]bool{
	"listing_fees": true, "gondola_ends": true, "promotions": true, "sampling": true,
	"pos_materials": true, "digital": true, "events": true, "rebates": true, "other": true,
	// Category ids used by the Flutter Trade Marketing ROI screen.
	"floor_rental": true, "advertising": true, "gifts_samples": true, "events_agencies": true,
	"promoter_incentives": true, "equipment_rental": true,
}

// MarketingExpense is one trade-marketing spend line for a tenant, chain and month.
type MarketingExpense struct {
	ID             string    `json:"id" firestore:"id"`
	TenantID       string    `json:"tenant_id" firestore:"tenant_id"`
	Year           int       `json:"year" firestore:"year"`
	Month          int       `json:"month" firestore:"month"`
	ChainName      string    `json:"chain_name" firestore:"chain_name"`
	Category       string    `json:"category" firestore:"category"`
	BrandName      string    `json:"brand_name" firestore:"brand_name"`
	CampaignTitle  string    `json:"campaign_title" firestore:"campaign_title"`
	VendorOrAgency string    `json:"vendor_or_agency" firestore:"vendor_or_agency"`
	AmountEGP      float64   `json:"amount_egp" firestore:"amount_egp"`
	Notes          string    `json:"notes" firestore:"notes"`
	CreatedBy      string    `json:"created_by" firestore:"created_by"`
	CreatedAt      time.Time `json:"created_at" firestore:"created_at"`
	UpdatedAt      time.Time `json:"updated_at" firestore:"updated_at"`
}

// MarketingExpenseFilter narrows a list query. Zero values mean "any".
type MarketingExpenseFilter struct {
	Year  int
	Month int
	Chain string
}
