package ingestion

import (
	"errors"
	"fmt"

	"github.com/tashil/data-sharing/backend/internal/domain"
	"github.com/tashil/data-sharing/backend/internal/service/gemini/guardrails"
)

// attachGuardrails fills human-approval + success metrics from observed telemetry on the payload.
func attachGuardrails(res *IngestionResult, validation *domain.IngestionValidation) {
	if res == nil {
		return
	}
	status := ""
	if validation != nil {
		status = validation.Status
	}
	d := guardrails.EvaluateApproval(guardrails.Input{
		MappingSource:     res.MappingSource,
		MappingConfidence: res.MappingConfidence,
		IsStaged:          res.IsStaged,
		IsCommitted:       res.IsCommitted,
		HumanApproved:     res.IsCommitted, // commit path is the explicit human approval
		ValidationStatus:  status,
		AnomalyCount:      res.AnomalyRows,
		ChainMismatch:     res.ChainMismatchDetected,
	})
	res.RequiresHumanApproval = d.RequiresHumanApproval
	res.GuardrailReasonsAR = d.ArabicReasons
	ev := eventsFromResult(res)
	m := guardrails.BuildSuccessMetrics(ev, res.MappingSource, res.MappingConfidence, d)
	res.GuardrailMetrics = &m
}

func eventsFromResult(res *IngestionResult) guardrails.Events {
	if res == nil || res.Payload == nil || res.Payload.GuardrailTelemetry == nil {
		return guardrails.Events{}
	}
	t := res.Payload.GuardrailTelemetry
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

// enforceDurableWriteApproval blocks AI/cache/mock/flagged durable writes unless humanApproved.
func enforceDurableWriteApproval(mappingSource string, validation *domain.IngestionValidation, anomalyCount int, chainMismatch, humanApproved bool) error {
	status := ""
	if validation != nil {
		status = validation.Status
	}
	err := guardrails.BlockDurableWrite(guardrails.Input{
		MappingSource:    mappingSource,
		ValidationStatus: status,
		AnomalyCount:     anomalyCount,
		ChainMismatch:    chainMismatch,
		HumanApproved:    humanApproved,
	})
	if err == nil {
		return nil
	}
	if errors.Is(err, guardrails.ErrHumanApprovalRequired) {
		return fmt.Errorf("%w: ارفع الملف كمعاينة ثم اعتمدها قبل الحفظ النهائي", err)
	}
	return err
}
