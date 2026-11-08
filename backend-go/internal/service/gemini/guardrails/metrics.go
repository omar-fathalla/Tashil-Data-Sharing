package guardrails

import "strings"

// Events records real guardrail outcomes for one ingest (not hardcoded constants).
type Events struct {
	// SchemaChecked is true when Gemini JSON was validated against the schema.
	SchemaChecked bool
	// SchemaValid is meaningful only when SchemaChecked is true.
	SchemaValid bool
	// GeminiCallLogged is true only when a real Gemini HTTP call was logged (not cache).
	GeminiCallLogged bool
	// SampleSanitized is true when the prompt sample went through SanitizeSampleRows*.
	SampleSanitized bool
	// MockRefused is true when production refused invented mock samples on this path.
	MockRefused bool
}

// EventsFromMappingSource derives events from the honesty mapping_source outcome.
// Cache hits reuse a previously schema-validated plan but did not make a new Gemini call.
func EventsFromMappingSource(mappingSource string) Events {
	src := strings.ToLower(strings.TrimSpace(mappingSource))
	switch src {
	case "ai":
		return Events{SchemaChecked: true, SchemaValid: true, GeminiCallLogged: true, SampleSanitized: true}
	case "cache":
		return Events{SchemaChecked: true, SchemaValid: true, GeminiCallLogged: false, SampleSanitized: true}
	case "mock":
		return Events{SchemaChecked: false, SchemaValid: false, GeminiCallLogged: false, SampleSanitized: false}
	default: // deterministic / empty
		return Events{SchemaChecked: false, SchemaValid: false, GeminiCallLogged: false, SampleSanitized: false}
	}
}

// SuccessMetrics are the Phase-A guardrail KPIs surfaced in API/UI (Arabic labels in UI).
type SuccessMetrics struct {
	SchemaValid           bool    `json:"schema_valid"`
	SchemaChecked         bool    `json:"schema_checked"`
	MockBlockedInProd     bool    `json:"mock_blocked_in_prod"`
	HumanApprovalRequired bool    `json:"human_approval_required"`
	PIIMinimized          bool    `json:"pii_minimized"`
	PerCallLogged         bool    `json:"per_call_logged"`
	MappingSource         string  `json:"mapping_source,omitempty"`
	MappingConfidence     float64 `json:"mapping_confidence,omitempty"`
	// ArabicSummary is a single short sentence for the review card.
	ArabicSummary string `json:"arabic_summary,omitempty"`
}

// BuildSuccessMetrics assembles the metrics snapshot from real Events (never forces schema_valid=true).
func BuildSuccessMetrics(ev Events, mappingSource string, mappingConfidence float64, approval Decision) SuccessMetrics {
	src := strings.ToLower(strings.TrimSpace(mappingSource))
	schemaValid := ev.SchemaChecked && ev.SchemaValid
	m := SuccessMetrics{
		SchemaValid:           schemaValid,
		SchemaChecked:         ev.SchemaChecked,
		MockBlockedInProd:     IsProduction() || ev.MockRefused,
		HumanApprovalRequired: approval.RequiresHumanApproval,
		PIIMinimized:          ev.SampleSanitized,
		PerCallLogged:         ev.GeminiCallLogged, // cache hit ≠ call
		MappingSource:         src,
		MappingConfidence:     mappingConfidence,
	}
	switch {
	case ev.SchemaChecked && !ev.SchemaValid:
		m.ArabicSummary = "فشل التحقق من مخطط الاستجابة — لا يمكن الاعتماد"
	case approval.RequiresHumanApproval:
		m.ArabicSummary = "جاهز للمراجعة البشرية قبل الحفظ"
	default:
		m.ArabicSummary = "اجتاز الحواجز الوقائية"
	}
	return m
}
