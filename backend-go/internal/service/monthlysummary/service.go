package monthlysummary

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"

	"github.com/tashil/data-sharing/backend/internal/domain"
)

// TextGenerator is an injectable Gemini (or stub) caller: prompt → plain Arabic text.
type TextGenerator func(ctx context.Context, model, prompt string) (string, error)

// Options control narrative generation for Attach.
type Options struct {
	// Generator, when set and UseMock is false, may produce an AI narrative.
	// Failures or ungrounded text fall back to the deterministic narrative.
	Generator TextGenerator
	Model        string
	UseMock      bool // force deterministic path; mapping_source stays "deterministic" (honest)
	ForceMockSrc bool // tests only: label mapping_source as mock while still using deterministic text
}

// Attach builds aggregates from kpis and a grounded Arabic narrative.
// Mutates kpis.MonthlySummary when kpis is non-nil. Safe no-op on nil.
func Attach(ctx context.Context, kpis *domain.ExecutiveKPIs, opts Options) *domain.MonthlySummaryNarrative {
	if kpis == nil {
		return nil
	}
	summary := Build(ctx, kpis, opts)
	kpis.MonthlySummary = summary
	return summary
}

// Build returns a monthly summary without requiring a mutable KPI pointer attach.
func Build(ctx context.Context, kpis *domain.ExecutiveKPIs, opts Options) *domain.MonthlySummaryNarrative {
	agg := BuildAggregates(kpis)
	det := DeterministicNarrateAR(agg)
	conf := Confidence(agg)

	out := &domain.MonthlySummaryNarrative{
		NarrativeAR:   det,
		Aggregates:    agg,
		MappingSource: SourceDeterministic,
		Confidence:    conf,
		Grounded:      Grounded(det, agg),
	}
	if opts.ForceMockSrc {
		out.MappingSource = SourceMock
	}

	if opts.UseMock || opts.Generator == nil || strings.TrimSpace(opts.Model) == "" {
		return out
	}

	prompt := buildGeminiPrompt(agg)
	raw, err := opts.Generator(ctx, opts.Model, prompt)
	if err != nil || strings.TrimSpace(raw) == "" {
		return out
	}
	payload, err := ParseAIPayload(raw)
	if err != nil {
		// Free-form prose without structured claims → deterministic only.
		return out
	}
	if !AcceptAIClaims(payload.NarrativeAR, payload.Claims, agg) {
		// Honesty: fabricated claim keys OR fabricated numbers in narrative_ar
		// (even when claims are valid) → deterministic fallback.
		return out
	}
	// Ship narrative rebuilt ONLY from validated claims — never model prose.
	built := NarrateFromClaims(payload.Claims, agg)
	out.NarrativeAR = built
	out.MappingSource = SourceAI
	out.ModelUsed = opts.Model
	out.Grounded = true
	out.Confidence = conf
	return out
}

func buildGeminiPrompt(agg domain.MonthlySummaryAggregates) string {
	facts, _ := json.MarshalIndent(agg, "", "  ")
	return fmt.Sprintf(`أنت محلل مبيعات تجزئة. أعد JSON فقط (بدون Markdown) بالشكل:
{"narrative_ar":"...","claims":[{"key":"total_revenue","number":0},{"key":"total_units","number":0},{"key":"top_chain","name":"..."}]}

القواعد الصارمة:
1) claims يجب أن تطابق JSON الحقائق حرفياً — لا تختلق مفاتيح أو أرقاماً أو أسماء.
2) المفاتيح المسموحة فقط: total_revenue, total_units, revenue_mom_pct, units_mom_pct, revenue_yoy_pct, market_share_pct, active_stores, top_chain, top_product, top_category, prior_month_key, current_month_key, prior_month_revenue.
3) narrative_ar للتحقق فقط ويجب ألا يحتوي أي رقم غير موجود في الحقائق؛ النص النهائي يُبنى من claims فقط على الخادم.
4) أي ادعاء غير موجود في الحقائق مرفوض.

JSON الحقائق المحسوبة مسبقاً:
%s`, string(facts))
}

func sanitizeNarrative(s string) string {
	s = strings.TrimSpace(s)
	s = strings.TrimPrefix(s, "```")
	s = strings.TrimSuffix(s, "```")
	return strings.TrimSpace(s)
}
