package arabicqa

import (
	"fmt"
	"strings"
)

// Claim is one grounded metric bound to an entity. Narratives (deterministic or
// Gemini) must be built only from these pairs — values cannot be reassigned.
type Claim struct {
	Metric  string  `json:"metric"`
	Entity  string  `json:"entity"`
	Value   float64 `json:"value"`
	Display string  `json:"display"`
}

func claimKey(metric, entity string) string {
	return strings.ToLower(strings.TrimSpace(metric)) + "|" + strings.ToLower(strings.TrimSpace(entity))
}

func (c Claim) key() string {
	return claimKey(c.Metric, c.Entity)
}

func claimDisplayEGP(v float64) string {
	return fmt.Sprintf("%.2f ج.م", v)
}

func claimDisplayInt(v float64) string {
	return fmt.Sprintf("%.0f", v)
}

func claimDisplayPct(v float64) string {
	return fmt.Sprintf("%.1f%%", v)
}

// narrativeFromClaims builds the Arabic answer strictly from metric+entity claims.
func narrativeFromClaims(period string, intro string, claims []Claim) string {
	if len(claims) == 0 {
		return fmt.Sprintf("%s مفيش أرقام مؤسسة للفترة %s.", intro, periodLabel(period))
	}
	parts := make([]string, 0, len(claims))
	for _, c := range claims {
		label := c.Entity
		if label == "" || label == "tenant" {
			label = metricLabelAR(c.Metric)
		} else {
			label = fmt.Sprintf("%s (%s)", label, metricLabelAR(c.Metric))
		}
		parts = append(parts, fmt.Sprintf("%s: %s", label, c.Display))
	}
	return fmt.Sprintf("%s (فترة %s): %s. قراءة فقط من بيانات المستأجر في BigQuery.",
		intro, periodLabel(period), strings.Join(parts, "؛ "))
}

func metricLabelAR(metric string) string {
	switch metric {
	case "total_revenue", "total_net_value":
		return "الإيراد"
	case "total_units", "total_units_sold":
		return "الوحدات"
	case "active_stores_count":
		return "المتاجر النشطة"
	case "tenant_market_share_pct", "share_pct":
		return "حصة السوق"
	case "revenue_mom_pct":
		return "نمو الإيراد شهريًا"
	case "record_count":
		return "عدد السجلات"
	default:
		return metric
	}
}

func claimsToEvidence(period string, claims []Claim, extra map[string]interface{}) map[string]interface{} {
	out := map[string]interface{}{
		"period": period,
		"claims": claimsToMaps(claims),
	}
	for k, v := range extra {
		out[k] = v
	}
	// Keep flat metric keys for older clients/tests (tenant-level claims only).
	for _, c := range claims {
		if c.Entity == "tenant" || c.Entity == "" {
			out[c.Metric] = c.Value
		}
	}
	return out
}

func claimsToMaps(claims []Claim) []map[string]interface{} {
	out := make([]map[string]interface{}, 0, len(claims))
	for _, c := range claims {
		out = append(out, map[string]interface{}{
			"metric":  c.Metric,
			"entity":  c.Entity,
			"value":   c.Value,
			"display": c.Display,
		})
	}
	return out
}

func claimsFromEvidence(evidence map[string]interface{}) []Claim {
	raw, ok := evidence["claims"]
	if !ok {
		return nil
	}
	switch xs := raw.(type) {
	case []Claim:
		return xs
	case []map[string]interface{}:
		out := make([]Claim, 0, len(xs))
		for _, m := range xs {
			out = append(out, claimFromMap(m))
		}
		return out
	case []interface{}:
		out := make([]Claim, 0, len(xs))
		for _, item := range xs {
			if m, ok := item.(map[string]interface{}); ok {
				out = append(out, claimFromMap(m))
			}
		}
		return out
	default:
		return nil
	}
}

func claimFromMap(m map[string]interface{}) Claim {
	c := Claim{
		Metric:  fmt.Sprint(m["metric"]),
		Entity:  fmt.Sprint(m["entity"]),
		Display: fmt.Sprint(m["display"]),
	}
	switch v := m["value"].(type) {
	case float64:
		c.Value = v
	case float32:
		c.Value = float64(v)
	case int:
		c.Value = float64(v)
	case int64:
		c.Value = float64(v)
	}
	if c.Display == "" || c.Display == "<nil>" {
		c.Display = claimDisplayEGP(c.Value)
	}
	if c.Entity == "<nil>" {
		c.Entity = "tenant"
	}
	return c
}

// claimIndex indexes evidence claims by metric|entity → value.
func claimIndex(claims []Claim) map[string]Claim {
	idx := make(map[string]Claim, len(claims))
	for _, c := range claims {
		idx[c.key()] = c
	}
	return idx
}

func sameValue(a, b float64) bool {
	const eps = 0.005
	if a > b {
		return a-b < eps
	}
	return b-a < eps
}
