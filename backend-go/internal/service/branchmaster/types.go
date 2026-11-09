package branchmaster

import "time"

// Status values for pending proposals and alias confirmation.
const (
	StatusConfirmed = "confirmed"
	StatusPending   = "pending"
	StatusRejected  = "rejected"
)

// Match kinds returned by Resolve.
const (
	KindExact       = "exact"
	KindAlias       = "alias"
	KindNormalized  = "normalized"
	KindHigh        = "high"      // auto-linked via AI/similarity
	KindAmbiguous   = "ambiguous" // close to two+ → pending
	KindLow         = "low"       // low confidence → pending
	KindNew         = "new"       // genuinely new branch
	KindUnallocated = "unallocated"
	KindIdentity    = "identity" // no master yet / unmapped raw passthrough
)

// Alias sources.
const (
	SourceUpload    = "upload"
	SourceBootstrap = "bootstrap"
	SourceAuto      = "auto"
	SourceOwner     = "owner"
	SourceAI        = "ai"
)

// Chain is one retail banner under a tenant (internal chain code, e.g. FTH).
type Chain struct {
	Code      string    `json:"code" firestore:"code"`
	Slug      string    `json:"slug" firestore:"slug"` // fathalla / carrefour / …
	NameAR    string    `json:"name_ar" firestore:"name_ar"`
	NameEN    string    `json:"name_en,omitempty" firestore:"name_en,omitempty"`
	CreatedAt time.Time `json:"created_at" firestore:"created_at"`
}

// Branch is one physical/logical store under a chain (e.g. FTH-001).
type Branch struct {
	Code        string    `json:"code" firestore:"code"`
	ChainCode   string    `json:"chain_code" firestore:"chain_code"`
	DisplayName string    `json:"display_name" firestore:"display_name"` // short Arabic name
	Active      bool      `json:"active" firestore:"active"`
	Unallocated bool      `json:"unallocated,omitempty" firestore:"unallocated,omitempty"`
	CreatedAt   time.Time `json:"created_at" firestore:"created_at"`
	UpdatedAt   time.Time `json:"updated_at" firestore:"updated_at"`
}

// Alias maps a raw store/customer name → branch code.
type Alias struct {
	RawName       string     `json:"raw_name" firestore:"raw_name"`
	NormalizedKey string     `json:"normalized_key" firestore:"normalized_key"`
	BranchCode    string     `json:"branch_code" firestore:"branch_code"`
	Source        string     `json:"source" firestore:"source"`
	Confidence    float64    `json:"confidence" firestore:"confidence"`
	ConfirmedBy   string     `json:"confirmed_by,omitempty" firestore:"confirmed_by,omitempty"`
	ConfirmedAt   *time.Time `json:"confirmed_at,omitempty" firestore:"confirmed_at,omitempty"`
	CreatedAt     time.Time  `json:"created_at" firestore:"created_at"`
}

// Pending is an unresolved raw name awaiting owner confirmation.
type Pending struct {
	ID               string    `json:"id" firestore:"id"`
	RawName          string    `json:"raw_name" firestore:"raw_name"`
	NormalizedKey    string    `json:"normalized_key" firestore:"normalized_key"`
	ChainSlug        string    `json:"chain_slug" firestore:"chain_slug"`
	SuggestedCode    string    `json:"suggested_code,omitempty" firestore:"suggested_code,omitempty"`
	SuggestedName    string    `json:"suggested_name,omitempty" firestore:"suggested_name,omitempty"`
	AltSuggestedCode string    `json:"alt_suggested_code,omitempty" firestore:"alt_suggested_code,omitempty"`
	AltSuggestedName string    `json:"alt_suggested_name,omitempty" firestore:"alt_suggested_name,omitempty"`
	Confidence       float64   `json:"confidence" firestore:"confidence"`
	AltConfidence    float64   `json:"alt_confidence,omitempty" firestore:"alt_confidence,omitempty"`
	ReasonAR         string    `json:"reason_ar" firestore:"reason_ar"`
	Kind             string    `json:"kind" firestore:"kind"` // ambiguous | low | new
	Status           string    `json:"status" firestore:"status"`
	CreatedAt        time.Time `json:"created_at" firestore:"created_at"`
	UpdatedAt        time.Time `json:"updated_at" firestore:"updated_at"`
	DecidedBy        string    `json:"decided_by,omitempty" firestore:"decided_by,omitempty"`
}

// Notice is a lightweight owner notification (auto-link / new branch).
type Notice struct {
	ID         string    `json:"id" firestore:"id"`
	Kind       string    `json:"kind" firestore:"kind"` // auto_link | new_branch | pending
	MessageAR  string    `json:"message_ar" firestore:"message_ar"`
	RawName    string    `json:"raw_name,omitempty" firestore:"raw_name,omitempty"`
	BranchCode string    `json:"branch_code,omitempty" firestore:"branch_code,omitempty"`
	CreatedAt  time.Time `json:"created_at" firestore:"created_at"`
	Read       bool      `json:"read" firestore:"read"`
}

// State is the persisted master for one tenant.
type State struct {
	TenantID  string    `json:"tenant_id" firestore:"tenant_id"`
	Chains    []Chain   `json:"chains" firestore:"chains"`
	Branches  []Branch  `json:"branches" firestore:"branches"`
	Aliases   []Alias   `json:"aliases" firestore:"aliases"`
	Pending   []Pending `json:"pending" firestore:"pending"`
	Notices   []Notice  `json:"notices,omitempty" firestore:"notices,omitempty"`
	UpdatedAt time.Time `json:"updated_at" firestore:"updated_at"`
	// BootstrapDone is true after the owner confirmed the first proposal sheet.
	BootstrapDone bool `json:"bootstrap_done" firestore:"bootstrap_done"`
}

// Resolution is the outcome of resolving one raw name against the master.
type Resolution struct {
	RawName       string  `json:"raw_name"`
	NormalizedKey string  `json:"normalized_key"`
	BranchCode    string  `json:"branch_code,omitempty"`
	DisplayName   string  `json:"display_name,omitempty"`
	ChainCode     string  `json:"chain_code,omitempty"`
	Kind          string  `json:"kind"`
	Confidence    float64 `json:"confidence"`
	ReasonAR      string  `json:"reason_ar"`
	PendingID     string  `json:"pending_id,omitempty"`
	AutoLinked    bool    `json:"auto_linked,omitempty"`
	AltCode       string  `json:"alt_code,omitempty"`
	AltName       string  `json:"alt_name,omitempty"`
	AltConfidence float64 `json:"alt_confidence,omitempty"`
}

// ProposalRow is one row in a bootstrap / dry-run proposal (not written until owner approves).
type ProposalRow struct {
	RawNames       []string        `json:"raw_names"`
	RawSourceCites []RawSourceCite `json:"raw_source_cites,omitempty"`
	NormalizedKey  string          `json:"normalized_key"`
	ChainSlug      string          `json:"chain_slug"`
	ChainCode      string          `json:"chain_code"`
	BranchCode     string          `json:"branch_code"`
	DisplayName    string          `json:"display_name"`
	Unallocated    bool            `json:"unallocated,omitempty"`
	SourceHint     string          `json:"source_hint,omitempty"`   // sell_in+sell_out+returns style
	HasCareLine    bool            `json:"has_care_line,omitempty"` // مواد عناية spellings present
	HasGroceryLine bool            `json:"has_grocery_line,omitempty"`
	HasKHBanner    bool            `json:"has_kh_banner,omitempty"` // كيه اتش جمله ماركت
	MultiSpelling  bool            `json:"multi_spelling,omitempty"`
	AmbiguousNote  string          `json:"ambiguous_note,omitempty"`
	// LocationType: store (POS) | warehouse (Sell-In may include warehouses; Sell-Out is POS-only).
	LocationType string `json:"location_type,omitempty"`
}

// DryRunChainSummary is per-chain counts for the dry-run top summary.
type DryRunChainSummary struct {
	ChainSlug   string `json:"chain_slug"`
	ChainCode   string `json:"chain_code"`
	Branches    int    `json:"branches"`
	SellInOut   int    `json:"sell_in_and_sell_out"`
	SellInOnly  int    `json:"sell_in_only"`
	SellOutOnly int    `json:"sell_out_only"`
	ReturnsHit  int    `json:"with_returns"`
}

// DryRunReport is the one-time Adeco (or any tenant) proposal artifact.
type DryRunReport struct {
	TenantID           string               `json:"tenant_id"`
	GeneratedAt        time.Time            `json:"generated_at"`
	RawNameCount       int                  `json:"raw_name_count"`
	UniqueNormCount    int                  `json:"unique_norm_count"`
	ChainCount         int                  `json:"chain_count"`
	BranchCount        int                  `json:"branch_count"`
	SellInAndOut       int                  `json:"sell_in_and_sell_out"`
	SellInOnly         int                  `json:"sell_in_only"`
	SellOutOnly        int                  `json:"sell_out_only"`
	MultiSpelling      int                  `json:"multi_spelling_merges"`
	ReturnsCovered     int                  `json:"branches_with_returns"`
	ChainSummaries     []DryRunChainSummary `json:"chain_summaries,omitempty"`
	OwnerQuestions     []string             `json:"owner_questions,omitempty"`
	UnmatchedSellOut   []string             `json:"unmatched_sell_out,omitempty"` // sell-out names with no Sell-In counterpart
	AmbiguousPending   []string             `json:"ambiguous_pending,omitempty"`
	LikelyMisspellings []string             `json:"likely_misspellings,omitempty"`
	DataProvenance     []string             `json:"data_provenance,omitempty"` // how raw names were sourced
	SourceReconcile    []SourceReconcileRow `json:"source_reconcile,omitempty"`
	ReconcileNotesAR   []string             `json:"reconcile_notes_ar,omitempty"`
	UnmappedPlanCodes  []PlanBranchCodeRow  `json:"unmapped_plan_branch_codes,omitempty"`
	ParentLevelRows    []ParentLevelRow     `json:"parent_level_rows,omitempty"`
	QuarantinedRows    []QuarantinedRow     `json:"quarantined_rows,omitempty"`
	ChainPolicies      []ChainPolicy        `json:"chain_policies,omitempty"`
	Rows               []ProposalRow        `json:"rows"`
	NotesAR            []string             `json:"notes_ar,omitempty"`
}

// ParentLevelRow is a parent-company / regional / legal-entity bucket that is
// NOT a proposed store branch (pending owner decision). Totals kept for reconcile.
type ParentLevelRow struct {
	Kind        string          `json:"kind"` // parent_company | parent_mini | regional
	DisplayName string          `json:"display_name"`
	RawNames    []string        `json:"raw_names"`
	SourceCites []RawSourceCite `json:"raw_source_cites,omitempty"`
	RowCount    int             `json:"row_count,omitempty"`
	ValueEGP    float64         `json:"value_egp,omitempty"`
	SourceFile  string          `json:"source_file,omitempty"`
	ArchiveID   string          `json:"archive_id,omitempty"`
	NoteAR      string          `json:"note_ar,omitempty"`
}

// QuarantinedRow is a raw name that did not match the chain's known banners.
type QuarantinedRow struct {
	RawName     string          `json:"raw_name"`
	ChainSlug   string          `json:"chain_slug,omitempty"`
	SourceCites []RawSourceCite `json:"raw_source_cites,omitempty"`
	ReasonAR    string          `json:"reason_ar"`
}

// SourceReconcileRow is one live source file's raw vs location counts for the dry-run.
type SourceReconcileRow struct {
	SourceFile       string `json:"source_file"`
	SourceTable      string `json:"source_table"`
	ArchiveID        string `json:"archive_id,omitempty"`
	RawSpellings     int    `json:"raw_spellings"`
	CareSpellings    int    `json:"care_spellings,omitempty"`
	GrocerySpellings int    `json:"grocery_spellings,omitempty"`
	UniqueLocations  int    `json:"unique_locations_after_normalize"`
	NoteAR           string `json:"note_ar,omitempty"`
}

// PlanBranchCodeRow is one Customer_Branch_Code from Plan_2026_Clean awaiting owner naming.
type PlanBranchCodeRow struct {
	Code       string  `json:"code"`
	RowCount   int     `json:"row_count"`
	ValueEGP   float64 `json:"value_egp"`
	Status     string  `json:"status"` // regional_bucket | unmapped_owner_to_name
	SourceFile string  `json:"source_file"`
	ArchiveID  string  `json:"archive_id,omitempty"`
}
