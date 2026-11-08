package guardrails

import "strings"

// Events records observed guardrail outcomes for one ingest.
// Every field is set only by the code path that performed the operation — never inferred
// from mapping_source alone.
type Events struct {
	SchemaChecked    bool
	SchemaValid      bool
	GeminiCallLogged bool
	GeminiCallCount  int
	GeminiLatencyMS  int64
	SampleSanitized  bool
	MockRefused      bool
}

// MarkSampleSanitized records that SanitizeSampleRows* ran on the prompt sample.
func (e *Events) MarkSampleSanitized() {
	if e == nil {
		return
	}
	e.SampleSanitized = true
}

// MarkSchema records a JSON-schema validation attempt (pass or fail).
func (e *Events) MarkSchema(ok bool) {
	if e == nil {
		return
	}
	e.SchemaChecked = true
	if ok {
		e.SchemaValid = true
	}
	// A later failure after a pass keeps SchemaChecked; SchemaValid stays true only if
	// at least one check passed and we treat final success as valid. Callers that fail
	// the ingest should pass ok=false on the failing check before returning.
	if !ok && !e.SchemaValid {
		e.SchemaValid = false
	}
}

// MarkSchemaFailed records a failed schema check (checked, not valid).
func (e *Events) MarkSchemaFailed() {
	if e == nil {
		return
	}
	e.SchemaChecked = true
	// Do not clear a prior pass if a later independent check fails mid-escalation;
	// use ResetSchemaValidity when the accepted plan itself is invalid.
}

// MarkSchemaResult sets checked=true and valid to the outcome of the accepted plan/payload.
func (e *Events) MarkSchemaResult(ok bool) {
	if e == nil {
		return
	}
	e.SchemaChecked = true
	e.SchemaValid = ok
}

// MarkGeminiCall records that a real Gemini HTTP call was logged (not a cache hit).
func (e *Events) MarkGeminiCall(latencyMS int64) {
	if e == nil {
		return
	}
	e.GeminiCallLogged = true
	e.GeminiCallCount++
	if latencyMS > 0 {
		e.GeminiLatencyMS += latencyMS
	}
}

// MarkMockRefused records that production refused inventing mock samples.
func (e *Events) MarkMockRefused() {
	if e == nil {
		return
	}
	e.MockRefused = true
}

// SuccessMetrics are the Phase-A guardrail KPIs surfaced in API/UI (Arabic labels in UI).
type SuccessMetrics struct {
	SchemaValid           bool    `json:"schema_valid"`
	SchemaChecked         bool    `json:"schema_checked"`
	MockBlockedInProd     bool    `json:"mock_blocked_in_prod"`
	HumanApprovalRequired bool    `json:"human_approval_required"`
	PIIMinimized          bool    `json:"pii_minimized"`
	PerCallLogged         bool    `json:"per_call_logged"`
	GeminiCallCount       int     `json:"gemini_call_count,omitempty"`
	GeminiLatencyMS       int64   `json:"gemini_latency_ms,omitempty"`
	MappingSource         string  `json:"mapping_source,omitempty"`
	MappingConfidence     float64 `json:"mapping_confidence,omitempty"`
	// ArabicSummary is a single short sentence for the review card.
	ArabicSummary string `json:"arabic_summary,omitempty"`
}

// BuildSuccessMetrics assembles the metrics snapshot from observed Events only.
func BuildSuccessMetrics(ev Events, mappingSource string, mappingConfidence float64, approval Decision) SuccessMetrics {
	src := strings.ToLower(strings.TrimSpace(mappingSource))
	m := SuccessMetrics{
		SchemaValid:           ev.SchemaChecked && ev.SchemaValid,
		SchemaChecked:         ev.SchemaChecked,
		MockBlockedInProd:     ev.MockRefused, // only when mock refusal actually ran
		HumanApprovalRequired: approval.RequiresHumanApproval,
		PIIMinimized:          ev.SampleSanitized,
		PerCallLogged:         ev.GeminiCallLogged,
		GeminiCallCount:       ev.GeminiCallCount,
		GeminiLatencyMS:       ev.GeminiLatencyMS,
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
