package domain

import "time"

// CustomCompetitorSku is a field-captured competitor SKU pinned under one of the
// tenant's own SKUs for the Competitor Comparison screen.
type CustomCompetitorSku struct {
	ID                    string    `json:"id" firestore:"id"`
	TenantID              string    `json:"tenant_id" firestore:"tenant_id"`
	OwnBarcode            string    `json:"own_barcode" firestore:"own_barcode"`
	OwnSkuName            string    `json:"own_sku_name" firestore:"own_sku_name"`
	OwnUnitPrice          float64   `json:"own_unit_price" firestore:"own_unit_price"`
	OwnVolumeUnits        float64   `json:"own_volume_units" firestore:"own_volume_units"`
	OwnVolumeUnitLabel    string    `json:"own_volume_unit_label" firestore:"own_volume_unit_label"`
	CompetitorSkuName     string    `json:"competitor_sku_name" firestore:"competitor_sku_name"`
	CompetitorBrand       string    `json:"competitor_brand" firestore:"competitor_brand"`
	CompetitorSupplier    string    `json:"competitor_supplier" firestore:"competitor_supplier"`
	Category              string    `json:"category" firestore:"category"`
	PackSizeLabel         string    `json:"pack_size_label" firestore:"pack_size_label"`
	PackVolumeUnits       float64   `json:"pack_volume_units" firestore:"pack_volume_units"`
	CompetitorPrice       float64   `json:"competitor_price" firestore:"competitor_price"`
	RetailerChain         string    `json:"retailer_chain" firestore:"retailer_chain"`
	EstimatedMonthlyUnits int       `json:"estimated_monthly_units" firestore:"estimated_monthly_units"`
	IsPromoActive         bool      `json:"is_promo_active" firestore:"is_promo_active"`
	CreatedBy             string    `json:"created_by" firestore:"created_by"`
	CreatedAt             time.Time `json:"created_at" firestore:"created_at"`
	UpdatedAt             time.Time `json:"updated_at" firestore:"updated_at"`
}

// CustomCompetitorSkuFilter narrows list results. Empty fields match everything.
type CustomCompetitorSkuFilter struct {
	Chain    string
	Category string
}
