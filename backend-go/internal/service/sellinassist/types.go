// Package sellinassist proposes Sell-In layout and customer→chain mappings via Gemini
// (or deterministic heuristics). Suggestions are advisory only: nothing is written to
// production data, env vars, or BigQuery until a human approves — and even then the
// approval only records the decision and the SELLIN_CUSTOMER_CHAIN_MAP fragment for ops.
package sellinassist

import "time"

// Suggestion kinds.
const (
	KindLayout         = "layout"
	KindCustomerChain  = "customer_chain"
)

// Suggestion lifecycle.
const (
	StatusPending  = "pending"
	StatusApproved = "approved"
	StatusRejected = "rejected"
)

// Mapping sources (honest labels; never invent Gemini credit).
const (
	SourceAI            = "ai"
	SourceDeterministic = "deterministic"
	SourceMock          = "mock"
)

// ColumnRole is one suggested Sell-In column mapping.
type ColumnRole struct {
	Index int    `json:"index"`
	Role  string `json:"role"`
	Label string `json:"label,omitempty"`
}

// Suggestion is one pending/approved/rejected assist item.
type Suggestion struct {
	ID            string       `json:"id"`
	TenantID      string       `json:"tenant_id"`
	Kind          string       `json:"kind"`
	Status        string       `json:"status"`
	Confidence    float64      `json:"confidence"`
	MappingSource string       `json:"mapping_source"`
	ModelUsed     string       `json:"model_used,omitempty"`
	AiTierUsed    string       `json:"ai_tier_used,omitempty"`
	ReasonAR      string       `json:"reason_ar"`
	CreatedAt     time.Time    `json:"created_at"`
	DecidedAt     *time.Time   `json:"decided_at,omitempty"`
	DecidedBy     string       `json:"decided_by,omitempty"`

	// Layout fields.
	Filename       string       `json:"filename,omitempty"`
	HeaderRowIndex int          `json:"header_row_index,omitempty"`
	Layout         string       `json:"layout,omitempty"` // gp_sop | raw_plan | guided | long | unknown
	Columns        []ColumnRole `json:"columns,omitempty"`
	MissingRoles   []string     `json:"missing_roles,omitempty"`

	// Customer→chain fields (SELLIN_CUSTOMER_CHAIN_MAP).
	CustomerNeedle   string   `json:"customer_needle,omitempty"`
	SuggestedChain   string   `json:"suggested_chain,omitempty"`
	SampleCustomers  []string `json:"sample_customers,omitempty"`
	UploadChain      string   `json:"upload_chain,omitempty"`
	EnvFragment      string   `json:"env_fragment,omitempty"` // e.g. "كيه اتش=gomla"
	AlreadyMapped    bool     `json:"already_mapped,omitempty"`
}

// Metrics tracks assist funnel success rates (in-process; not persisted).
type Metrics struct {
	Suggested         int     `json:"suggested"`
	Approved          int     `json:"approved"`
	Rejected          int     `json:"rejected"`
	Pending           int     `json:"pending"`
	LayoutSuggested   int     `json:"layout_suggested"`
	LayoutApproved    int     `json:"layout_approved"`
	ChainSuggested    int     `json:"chain_suggested"`
	ChainApproved     int     `json:"chain_approved"`
	ApprovalRate      float64 `json:"approval_rate"`
	LayoutApprovalRate float64 `json:"layout_approval_rate"`
	ChainApprovalRate float64 `json:"chain_approval_rate"`
}
