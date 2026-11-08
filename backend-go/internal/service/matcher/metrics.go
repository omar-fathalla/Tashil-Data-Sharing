package matcher

import (
	"context"
	"math"
	"time"
)

// Metrics are success / review KPIs for product matching (Arabic UI consumes labels).
type Metrics struct {
	TenantID     string    `json:"tenant_id" firestore:"tenant_id"`
	TotalMatched int       `json:"total_matched" firestore:"total_matched"`
	Exact        int       `json:"exact" firestore:"exact"`
	High         int       `json:"high" firestore:"high"`
	Uncertain    int       `json:"uncertain" firestore:"uncertain"`
	None         int       `json:"none" firestore:"none"`
	AutoResolved int       `json:"auto_resolved" firestore:"auto_resolved"`
	Queued       int       `json:"queued" firestore:"queued"`
	Pending      int       `json:"pending" firestore:"pending"`
	Approved     int       `json:"approved" firestore:"approved"`
	Rejected     int       `json:"rejected" firestore:"rejected"`
	UpdatedAt    time.Time `json:"updated_at" firestore:"updated_at"`

	// Derived rates (filled by Snapshot; not authoritative in Firestore).
	AutoResolveRate  float64           `json:"auto_resolve_rate" firestore:"-"`
	ReviewRate       float64           `json:"review_rate" firestore:"-"`
	ApprovalRate     float64           `json:"approval_rate" firestore:"-"`
	InventedBarcodes int               `json:"invented_barcodes" firestore:"-"`
	LabelsAR         map[string]string `json:"labels_ar" firestore:"-"`
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

func decorateMetrics(src Metrics, tenantID string) Metrics {
	out := src
	out.TenantID = NormalizeTenantKey(tenantID)
	out.AutoResolveRate = rate(out.AutoResolved, out.TotalMatched)
	out.ReviewRate = rate(out.Queued, out.TotalMatched)
	decided := out.Approved + out.Rejected
	out.ApprovalRate = rate(out.Approved, decided)
	out.InventedBarcodes = 0
	out.LabelsAR = metricLabelsAR()
	return out
}

// Snapshot returns persisted metrics with derived rates and Arabic labels.
func (q *Queue) Snapshot(ctx context.Context, tenantID string) (Metrics, error) {
	st, err := q.load(ctx, tenantID)
	if err != nil {
		return Metrics{}, err
	}
	return decorateMetrics(st.Metrics, st.TenantID), nil
}

func metricLabelsAR() map[string]string {
	return map[string]string{
		"total_matched":     "إجمالي محاولات المطابقة",
		"exact":             "تطابق تام",
		"high":              "ثقة عالية (تلقائي)",
		"uncertain":         "غير مؤكد (مراجعة)",
		"none":              "بدون مرشح",
		"auto_resolved":     "حُسم تلقائياً",
		"queued":            "أُدخل قائمة المراجعة",
		"pending":           "بانتظار المراجعة",
		"approved":          "اعتُمد يدوياً",
		"rejected":          "رُفض يدوياً",
		"auto_resolve_rate": "نسبة الحسم التلقائي",
		"review_rate":       "نسبة الإحالة للمراجعة",
		"approval_rate":     "نسبة الاعتماد بعد المراجعة",
		"invented_barcodes": "باركودات مخترعة (يجب أن تبقى صفر)",
	}
}
