package guardrails

import "strings"

// Decision is the human-approval gate for an ingest preview/commit.
type Decision struct {
	RequiresHumanApproval bool     `json:"requires_human_approval"`
	Reasons               []string `json:"reasons,omitempty"`
	// ArabicReasons are short UI strings shown next to the review CTA.
	ArabicReasons []string `json:"arabic_reasons,omitempty"`
}

// Input feeds EvaluateApproval. Keep it free of full record payloads (PII).
type Input struct {
	MappingSource     string
	MappingConfidence float64
	IsStaged          bool
	IsCommitted       bool
	ValidationStatus  string // ok | flagged | rejected
	AnomalyCount      int
	ChainMismatch     bool
}

// EvaluateApproval decides whether a human must explicitly approve before durable write.
// Dry-run / staged previews always require approval. AI/mock/flagged paths also force review.
func EvaluateApproval(in Input) Decision {
	var d Decision
	add := func(en, ar string) {
		d.RequiresHumanApproval = true
		d.Reasons = append(d.Reasons, en)
		d.ArabicReasons = append(d.ArabicReasons, ar)
	}

	if in.IsCommitted {
		return d
	}
	if in.IsStaged {
		add("staged_preview", "المعاينة قيد المراجعة — الاعتماد البشري مطلوب قبل الحفظ")
	}

	src := strings.ToLower(strings.TrimSpace(in.MappingSource))
	switch src {
	case "ai":
		add("ai_mapping", "تم الاستخراج بالذكاء الاصطناعي — راجع التخطيط قبل الاعتماد")
		if in.MappingConfidence > 0 && in.MappingConfidence < 0.85 {
			add("ai_confidence_borderline", "درجة ثقة الذكاء الاصطناعي أقل من 85٪")
		}
	case "mock":
		add("mock_sample", "معاينة تجريبية ببيانات محاكاة — لا تُحفظ في الإنتاج")
	case "cache":
		add("cached_plan", "خطة أعمدة محفوظة — أكّد أنها ما زالت مناسبة لهذا الملف")
	}

	switch strings.ToLower(strings.TrimSpace(in.ValidationStatus)) {
	case "flagged":
		add("validation_flagged", "تم رصد ملاحظات تحقق — راجع الإجماليات قبل الاعتماد")
	case "rejected":
		add("validation_rejected", "فشل التحقق — لا يمكن الاعتماد حتى يُصحَّح الملف")
	}

	if in.AnomalyCount > 0 {
		add("anomalies_present", "توجد ملاحظات شذوذ في الملف — راجعها قبل الاعتماد")
	}
	if in.ChainMismatch {
		add("chain_mismatch", "السلسلة المكتشفة تختلف عن السلسلة المختارة")
	}

	// Deduplicate while preserving order.
	d.Reasons = uniq(d.Reasons)
	d.ArabicReasons = uniq(d.ArabicReasons)
	return d
}

func uniq(in []string) []string {
	seen := map[string]bool{}
	out := make([]string, 0, len(in))
	for _, s := range in {
		if seen[s] {
			continue
		}
		seen[s] = true
		out = append(out, s)
	}
	return out
}
