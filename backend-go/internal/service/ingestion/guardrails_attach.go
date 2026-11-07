package ingestion

import (
	"github.com/tashil/data-sharing/backend/internal/domain"
	"github.com/tashil/data-sharing/backend/internal/service/gemini"
	"github.com/tashil/data-sharing/backend/internal/service/gemini/guardrails"
)

// attachGuardrails fills human-approval + success metrics without changing durable write paths.
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
		ValidationStatus:  status,
		AnomalyCount:      res.AnomalyRows,
		ChainMismatch:     res.ChainMismatchDetected,
	})
	res.RequiresHumanApproval = d.RequiresHumanApproval
	res.GuardrailReasonsAR = d.ArabicReasons
	callLogged := res.MappingSource == gemini.MappingSourceAI || res.MappingSource == gemini.MappingSourceCache
	m := guardrails.BuildSuccessMetrics(true, res.MappingSource, res.MappingConfidence, d, callLogged)
	res.GuardrailMetrics = &m
}
