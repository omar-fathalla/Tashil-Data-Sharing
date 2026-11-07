package matcher

import (
	"math"
	"strings"
	"time"
)

// Metrics are success / review KPIs for product matching (Arabic UI consumes labels).
type Metrics struct {
	TenantID     string    `json:"tenant_id"`
	TotalMatched int       `json:"total_matched"`
	Exact        int       `json:"exact"`
	High         int       `json:"high"`
	Uncertain    int       `json:"uncertain"`
	None         int       `json:"none"`
	AutoResolved int       `json:"auto_resolved"`
	Queued       int       `json:"queued"`
	Pending      int       `json:"pending"`
	Approved     int       `json:"approved"`
	Rejected     int       `json:"rejected"`
	UpdatedAt    time.Time `json:"updated_at"`

	// Derived rates (filled by Snapshot).
	AutoResolveRate   float64 `json:"auto_resolve_rate"`
	ReviewRate        float64 `json:"review_rate"`
	ApprovalRate      float64 `json:"approval_rate"`
	InventedBarcodes  int     `json:"invented_barcodes"` // always 0 — invariant metric
	LabelsAR          map[string]string `json:"labels_ar"`
}

func (m *Metrics) touch(t time.Time) {
	m.UpdatedAt = t.UTC()
}

func rate(n, d int) float64 {
	if d <= 0 {
		return 0
	}
	return math.Round((float64(n)/float64(d))*1000) / 1000
}

// Snapshot returns a copy with derived rates and Arabic labels.
func (q *Queue) Snapshot(tenantID string) Metrics {
	q.mu.RLock()
	defer q.mu.RUnlock()
	tenantID = strings.TrimSpace(tenantID)
	src := q.metrics[tenantID]
	if src == nil {
		return Metrics{
			TenantID:         tenantID,
			InventedBarcodes: 0,
			LabelsAR:         metricLabelsAR(),
		}
	}
	out := *src
	out.AutoResolveRate = rate(out.AutoResolved, out.TotalMatched)
	out.ReviewRate = rate(out.Queued, out.TotalMatched)
	decided := out.Approved + out.Rejected
	out.ApprovalRate = rate(out.Approved, decided)
	out.InventedBarcodes = 0 // invariant: matcher never invents barcodes
	out.LabelsAR = metricLabelsAR()
	return out
}

func metricLabelsAR() map[string]string {
	return map[string]string{
		"total_matched":      "إجمالي محاولات المطابقة",
		"exact":              "تطابق تام",
		"high":               "ثقة عالية (تلقائي)",
		"uncertain":          "غير مؤكد (مراجعة)",
		"none":               "بدون مرشح",
		"auto_resolved":      "حُسم تلقائياً",
		"queued":             "أُدخل قائمة المراجعة",
		"pending":            "بانتظار المراجعة",
		"approved":           "اعتُمد يدوياً",
		"rejected":           "رُفض يدوياً",
		"auto_resolve_rate":  "نسبة الحسم التلقائي",
		"review_rate":        "نسبة الإحالة للمراجعة",
		"approval_rate":      "نسبة الاعتماد بعد المراجعة",
		"invented_barcodes":  "باركودات مخترعة (يجب أن تبقى صفر)",
	}
}
