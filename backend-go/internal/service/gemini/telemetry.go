package gemini

import (
	"github.com/tashil/data-sharing/backend/internal/domain"
	"github.com/tashil/data-sharing/backend/internal/service/gemini/guardrails"
)

func applyGuardrailEvents(payload *domain.NormalizedRetailIngestionPayload, ev *guardrails.Events) {
	// Branch-norm summary is cheap and useful on AI-mapped payloads too.
	attachBranchNormSummary(payload)
	if payload == nil || ev == nil {
		return
	}
	payload.GuardrailTelemetry = &domain.GuardrailTelemetry{
		SchemaChecked:    ev.SchemaChecked,
		SchemaValid:      ev.SchemaValid,
		GeminiCallLogged: ev.GeminiCallLogged,
		GeminiCallCount:  ev.GeminiCallCount,
		GeminiLatencyMS:  ev.GeminiLatencyMS,
		SampleSanitized:  ev.SampleSanitized,
		MockRefused:      ev.MockRefused,
	}
}

func eventsFromTelemetry(t *domain.GuardrailTelemetry) guardrails.Events {
	if t == nil {
		return guardrails.Events{}
	}
	return guardrails.Events{
		SchemaChecked:    t.SchemaChecked,
		SchemaValid:      t.SchemaValid,
		GeminiCallLogged: t.GeminiCallLogged,
		GeminiCallCount:  t.GeminiCallCount,
		GeminiLatencyMS:  t.GeminiLatencyMS,
		SampleSanitized:  t.SampleSanitized,
		MockRefused:      t.MockRefused,
	}
}
