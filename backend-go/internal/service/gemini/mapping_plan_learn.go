package gemini

import (
	"encoding/json"
	"fmt"

	"github.com/tashil/data-sharing/backend/internal/service/gemini/guardrails"
)

// RememberCorrectedPlan stores a human-corrected column map under the same prompt key
// that inferColumnMapping uses, so the next AnalyzeAndNormalize for the same file
// sample reuses the correction (mapping_source=cache) without calling Gemini.
//
// Does not mutate ai_column_mapping.go; callers (upload commit / review UI) supply the
// corrected plan. sample should be the leading rows of the workbook (same shape as
// mapping); it is truncated and sanitized before the key is computed.
func (c *Client) RememberCorrectedPlan(filename string, sample [][]string, plan *ColumnMapPlan) error {
	return c.LearnFromCorrection(filename, sample, plan)
}

// LearnFromCorrection is the Phase B correction→cache learning path.
func (c *Client) LearnFromCorrection(filename string, sample [][]string, plan *ColumnMapPlan) error {
	if c == nil {
		return fmt.Errorf("gemini client is nil")
	}
	if plan == nil {
		return fmt.Errorf("corrected plan is nil")
	}
	raw, err := json.Marshal(plan)
	if err != nil {
		return fmt.Errorf("corrected plan marshal: %w", err)
	}
	if _, err := guardrails.ValidateColumnMapPlanJSON(raw); err != nil {
		return fmt.Errorf("corrected plan schema: %w", err)
	}
	if len(sample) > mappingSampleRows {
		sample = sample[:mappingSampleRows]
	}
	sample = guardrails.SanitizeSampleRows(sample)
	safeFile := guardrails.FilenameForLog(filename)
	prompt := buildColumnMapPrompt(safeFile, sample)
	key := mappingPlanKey(prompt)
	if err := plan.check(sample); err != nil {
		return fmt.Errorf("corrected plan check: %w", err)
	}
	// Human corrections are authoritative for this prompt key.
	learned := *plan
	if learned.Confidence < 1 {
		learned.Confidence = 1
	}
	c.planCache.learnCorrection(key, &learned)
	return nil
}
