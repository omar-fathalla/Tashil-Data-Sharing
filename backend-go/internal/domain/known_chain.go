package domain

// KnownChain is one retail chain that already has counted Sell-In and/or Sell-Out rows.
// Key is the normalized chain enrichment matches on (lowercase, trimmed; empty sheet chain → "fathalla").
// Name is the same key — the value the order-calculator dropdown must save. DisplayName is labels only
// and is never used for matching.
type KnownChain struct {
	Key          string `json:"key"`
	Name         string `json:"name"`
	DisplayName  string `json:"display_name"`
	RowCount     int    `json:"row_count"`
	SellInRows   int    `json:"sell_in_rows,omitempty"`
	SellOutRows  int    `json:"sell_out_rows,omitempty"`
	LastDataDate string `json:"last_data_date,omitempty"` // YYYY-MM-DD
}
