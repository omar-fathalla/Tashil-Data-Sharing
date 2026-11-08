package gemini

import (
	"encoding/json"
	"fmt"

	"github.com/tashil/data-sharing/backend/internal/service/gemini/guardrails"
)

// MappingCorrectionLearner is implemented by *Client so ingestion can save approved
// corrections without depending on concrete fields.
type MappingCorrectionLearner interface {
	LearnFromCorrection(tenantID, filename string, sample [][]string, plan *ColumnMapPlan) error
	RememberCorrectedPlan(tenantID, filename string, sample [][]string, plan *ColumnMapPlan) error
	LookupCachedMappingPlan(tenantID, filename string, sample [][]string) (*ColumnMapPlan, string, bool)
}

// MappingSampleFromFile returns the leading rows used for column-mapping cache keys.
func MappingSampleFromFile(raw []byte) ([][]string, bool) {
	rows, ok := readSingleSheetRows(raw)
	if !ok || len(rows) < 2 {
		return nil, false
	}
	if len(rows) > mappingSampleRows {
		rows = rows[:mappingSampleRows]
	}
	return guardrails.SanitizeSampleRows(rows), true
}

func mappingPromptKey(filename string, sample [][]string) string {
	if len(sample) > mappingSampleRows {
		sample = sample[:mappingSampleRows]
	}
	sample = guardrails.SanitizeSampleRows(sample)
	safeFile := guardrails.FilenameForLog(filename)
	return mappingPlanKey(buildColumnMapPrompt(safeFile, sample))
}

// RememberCorrectedPlan stores a human-corrected column map under the same prompt key
// that inferColumnMapping uses (tenant-scoped), so the next AnalyzeAndNormalize for the
// same tenant + file sample reuses the correction (mapping_source=cache) without Gemini.
//
// Does not mutate ai_column_mapping.go; callers (upload commit / review UI) supply the
// corrected plan.
func (c *Client) RememberCorrectedPlan(tenantID, filename string, sample [][]string, plan *ColumnMapPlan) error {
	return c.LearnFromCorrection(tenantID, filename, sample, plan)
}

// LearnFromCorrection is the Phase B correction→cache learning path (tenant-isolated).
func (c *Client) LearnFromCorrection(tenantID, filename string, sample [][]string, plan *ColumnMapPlan) error {
	if c == nil {
		return fmt.Errorf("gemini client is nil")
	}
	if normalizeMappingTenant(tenantID) == "" {
		return fmt.Errorf("tenant_id is required for mapping corrections")
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
	if err := plan.check(sample); err != nil {
		return fmt.Errorf("corrected plan check: %w", err)
	}
	key := mappingPromptKey(filename, sample)
	learned := *plan
	if learned.Confidence < 1 {
		learned.Confidence = 1
	}
	if err := c.forTenant(tenantID).planCache.learnCorrection(key, &learned); err != nil {
		return fmt.Errorf("فشل حفظ تصحيح الربط على القرص: %w", err)
	}
	return nil
}

// LookupCachedMappingPlan returns a tenant-scoped cached plan for the filename/sample key.
func (c *Client) LookupCachedMappingPlan(tenantID, filename string, sample [][]string) (*ColumnMapPlan, string, bool) {
	if c == nil || normalizeMappingTenant(tenantID) == "" {
		return nil, "", false
	}
	key := mappingPromptKey(filename, sample)
	return c.forTenant(tenantID).planCache.getEntry(key)
}
