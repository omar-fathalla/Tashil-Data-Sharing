package guardrails

import (
	"errors"
	"fmt"
	"strings"
)

// ErrHumanApprovalRequired is returned when a durable write is attempted for an
// AI/cache/mock/flagged ingest without an explicit human approval (staged commit).
var ErrHumanApprovalRequired = errors.New("human approval required before durable write")

// Decision is the human-approval gate for an ingest preview/commit.
type Decision struct {
	RequiresHumanApproval bool     `json:"requires_human_approval"`
	Reasons               []string `json:"reasons,omitempty"`
	// ArabicReasons are short UI strings shown next to the review CTA.
	ArabicReasons []string `json:"arabic_reasons,omitempty"`
}

// Input feeds EvaluateApproval / BlockDurableWrite. Keep it free of full record payloads (PII).
type Input struct {
	MappingSource     string
	MappingConfidence float64
	IsStaged          bool
	IsCommitted       bool
	// HumanApproved is true only after an explicit review action (CommitStagedUpload).
	HumanApproved    bool
	ValidationStatus string // ok | flagged | rejected
	AnomalyCount     int
	ChainMismatch    bool
}

// NeedsWriteApproval reports whether durable persistence requires explicit human approval.
// Gates: AI / cache / mock mapping, or flagged|rejected validation. Independent of IsCommitted.
func NeedsWriteApproval(in Input) bool {
	src := strings.ToLower(strings.TrimSpace(in.MappingSource))
	switch src {
	case "ai", "cache", "mock":
		return true
	}
	switch strings.ToLower(strings.TrimSpace(in.ValidationStatus)) {
	case "flagged", "rejected":
		return true
	}
	return false
}

// EvaluateApproval decides UI / API approval state and always records reasons —
// including for committed results (never short-circuits on IsCommitted).
func EvaluateApproval(in Input) Decision {
	var d Decision
	add := func(en, ar string) {
		d.Reasons = append(d.Reasons, en)
		d.ArabicReasons = append(d.ArabicReasons, ar)
	}

	if in.IsStaged && !in.IsCommitted {
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

	d.Reasons = uniq(d.Reasons)
	d.ArabicReasons = uniq(d.ArabicReasons)

	// Still pending only when a gate applies and the human has not approved yet.
	gate := NeedsWriteApproval(in) || (in.IsStaged && !in.IsCommitted)
	d.RequiresHumanApproval = gate && !in.HumanApproved && !in.IsCommitted
	return d
}

// BlockDurableWrite returns ErrHumanApprovalRequired when AI/cache/mock/flagged
// (or other gate) would persist without HumanApproved.
func BlockDurableWrite(in Input) error {
	if in.HumanApproved {
		return nil
	}
	if !NeedsWriteApproval(in) {
		return nil
	}
	d := EvaluateApproval(in)
	reason := "ai_or_flagged"
	if len(d.Reasons) > 0 {
		reason = d.Reasons[0]
	}
	return fmt.Errorf("%w: %s — يجب اعتماد المعاينة قبل الحفظ", ErrHumanApprovalRequired, reason)
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
