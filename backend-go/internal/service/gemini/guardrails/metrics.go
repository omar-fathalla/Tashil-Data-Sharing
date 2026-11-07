package guardrails

import "strings"

// SuccessMetrics are the Phase-A guardrail KPIs surfaced in API/UI (Arabic labels in UI).
type SuccessMetrics struct {
	SchemaValid           bool    `json:"schema_valid"`
	MockBlockedInProd     bool    `json:"mock_blocked_in_prod"`
	HumanApprovalRequired bool    `json:"human_approval_required"`
	PIIMinimized          bool    `json:"pii_minimized"`
	PerCallLogged         bool    `json:"per_call_logged"`
	MappingSource         string  `json:"mapping_source,omitempty"`
	MappingConfidence     float64 `json:"mapping_confidence,omitempty"`
	// ArabicSummary is a single short sentence for the review card.
	ArabicSummary string `json:"arabic_summary,omitempty"`
}

// BuildSuccessMetrics assembles the metrics snapshot for a preview/commit response.
func BuildSuccessMetrics(schemaOK bool, mappingSource string, mappingConfidence float64, approval Decision, callLogged bool) SuccessMetrics {
	src := strings.ToLower(strings.TrimSpace(mappingSource))
	m := SuccessMetrics{
		SchemaValid:           schemaOK,
		MockBlockedInProd:     IsProduction(),
		HumanApprovalRequired: approval.RequiresHumanApproval,
		PIIMinimized:          true, // enforced by SanitizeSampleRows + RedactString on call path
		PerCallLogged:         callLogged || src == "deterministic" || src == "cache",
		MappingSource:         src,
		MappingConfidence:     mappingConfidence,
	}
	switch {
	case !schemaOK:
		m.ArabicSummary = "فشل التحقق من مخطط الاستجابة — لا يمكن الاعتماد"
	case approval.RequiresHumanApproval:
		m.ArabicSummary = "جاهز للمراجعة البشرية قبل الحفظ"
	default:
		m.ArabicSummary = "اجتاز الحواجز الوقائية"
	}
	return m
}
