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
	text := sanitizeNarrative(raw)
	if !Grounded(text, agg) {
		// Honesty: never ship AI text that invents or drops the fact-sheet numbers.
		return out
	}
	out.NarrativeAR = text
	out.MappingSource = SourceAI
	out.ModelUsed = opts.Model
	out.Grounded = true
	out.Confidence = conf
	return out
}

func buildGeminiPrompt(agg domain.MonthlySummaryAggregates) string {
	facts, _ := json.MarshalIndent(agg, "", "  ")
	return fmt.Sprintf(`أنت محلل مبيعات تجزئة. اكتب فقرة عربية واحدة قصيرة (3–6 جمل) تلخّص الأداء الشهري.
القواعد الصارمة:
1) استخدم فقط الأرقام والأسماء الموجودة في JSON التالي. لا تختلق أي رقم أو سلسلة أو منتج.
2) اذكر صراحة إجمالي المبيعات والوحدات وأبرز سلسلة إن وُجدت.
3) لا تضف توصيات تشغيلية غير مبنية على الحقول.
4) أعد النص العربي فقط بدون Markdown.

JSON الحقائق المحسوبة مسبقاً:
%s`, string(facts))
}

func sanitizeNarrative(s string) string {
	s = strings.TrimSpace(s)
	s = strings.TrimPrefix(s, "```")
	s = strings.TrimSuffix(s, "```")
	return strings.TrimSpace(s)
}
