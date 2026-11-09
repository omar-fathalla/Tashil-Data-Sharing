// Package arabicqa implements Phase C Arabic Q&A over BigQuery.
// Answers are grounded in tenant-scoped read-only analytics; never writes.
package arabicqa

// Intent is an allowlisted question class. Free-form SQL is never generated.
type Intent string

const (
	IntentExecutiveKPIs Intent = "executive_kpis"
	IntentChainShares   Intent = "chain_shares"
	IntentTopSKUs       Intent = "top_skus"
	IntentCategories    Intent = "categories"
	IntentSellIn        Intent = "sell_in"
	IntentUnsupported   Intent = "unsupported"
)

// Answer is the API payload for one Arabic Q&A turn.
type Answer struct {
	QuestionAR    string                 `json:"question_ar"`
	AnswerAR      string                 `json:"answer_ar"`
	Intent        Intent                 `json:"intent"`
	Period        string                 `json:"period"`
	TenantID      string                 `json:"tenant_id"`
	Confidence    float64                `json:"confidence"`
	MappingSource string                 `json:"mapping_source"` // deterministic | ai
	Evidence      map[string]interface{} `json:"evidence"`
	Sources       []string               `json:"sources"`
	ReadOnly      bool                   `json:"read_only"`
	Capabilities  []string               `json:"capabilities,omitempty"`
}

// Capability describes one allowlisted question family (Arabic).
type Capability struct {
	Intent      Intent   `json:"intent"`
	TitleAR     string   `json:"title_ar"`
	ExamplesAR  []string `json:"examples_ar"`
	DataSources []string `json:"data_sources"`
}
