package guardrails

import (
	"fmt"
	"sort"
	"strings"
)

// PlanSummary is an allowlisted, PII-safe summary of a column-map plan for logs.
// It never includes branch names, header cell text, or raw model JSON.
type PlanSummary struct {
	Layout     string
	Confidence float64
	Columns    int
	Roles      []string // sorted unique roles only
}

// FormatPlanSummary renders PlanSummary for ops logs.
func FormatPlanSummary(s PlanSummary) string {
	roles := append([]string(nil), s.Roles...)
	sort.Strings(roles)
	return fmt.Sprintf("layout=%s confidence=%.2f columns=%d roles=%s",
		s.Layout, s.Confidence, s.Columns, strings.Join(roles, ","))
}

// SummarizeColumnMapJSON builds a PII-safe summary from raw mapping JSON without
// echoing model-supplied branch/header strings.
func SummarizeColumnMapJSON(raw []byte) string {
	plan, err := ValidateColumnMapPlanJSON(raw)
	if err != nil {
		return fmt.Sprintf("plan=unparseable err=%q", RedactString(err.Error()))
	}
	roleSet := map[string]bool{}
	for _, c := range plan.Columns {
		roleSet[c.Role] = true
	}
	roles := make([]string, 0, len(roleSet))
	for r := range roleSet {
		roles = append(roles, r)
	}
	return FormatPlanSummary(PlanSummary{
		Layout:     plan.Layout,
		Confidence: plan.Confidence,
		Columns:    len(plan.Columns),
		Roles:      roles,
	})
}

// SafeIssues redacts each validation issue string before logging.
func SafeIssues(issues []string) []string {
	if len(issues) == 0 {
		return nil
	}
	out := make([]string, len(issues))
	for i, s := range issues {
		out[i] = RedactString(s)
	}
	return out
}
