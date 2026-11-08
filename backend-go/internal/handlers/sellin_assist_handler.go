package handlers

import (
	"encoding/json"
	"net/http"
	"strings"

	"github.com/tashil/data-sharing/backend/internal/service/sellinassist"
)

// SellInAssistHandler serves Gemini/deterministic Sell-In layout + customer→chain
// suggestions. Approvals never mutate production data or SELLIN_CUSTOMER_CHAIN_MAP.
type SellInAssistHandler struct {
	svc *sellinassist.Service
}

// NewSellInAssistHandler wires the assist service.
func NewSellInAssistHandler(svc *sellinassist.Service) *SellInAssistHandler {
	return &SellInAssistHandler{svc: svc}
}

// HandleList serves GET /api/v1/sell-in/assist/suggestions?status=pending|approved|rejected
func (h *SellInAssistHandler) HandleList(w http.ResponseWriter, r *http.Request) {
	c, ok := tmClaims(w, r)
	if !ok {
		return
	}
	if h.svc == nil {
		writeJSON(w, http.StatusOK, map[string]interface{}{"suggestions": []sellinassist.Suggestion{}, "count": 0})
		return
	}
	status := strings.TrimSpace(r.URL.Query().Get("status"))
	list := h.svc.List(c.TenantID, status)
	writeJSON(w, http.StatusOK, map[string]interface{}{"suggestions": list, "count": len(list)})
}

type layoutSuggestRequest struct {
	Filename string     `json:"filename"`
	Sample   [][]string `json:"sample"`
}

// HandleSuggestLayout serves POST /api/v1/sell-in/assist/suggest-layout
func (h *SellInAssistHandler) HandleSuggestLayout(w http.ResponseWriter, r *http.Request) {
	c, ok := tmWriteClaims(w, r)
	if !ok {
		return
	}
	if !dataQualityWriteRoles[c.Role] {
		writeErr(w, http.StatusForbidden, "مش مسموح لدورك تقترح تخطيط Sell-In")
		return
	}
	if h.svc == nil {
		writeErr(w, http.StatusServiceUnavailable, "خدمة مساعدة Sell-In مش متاحة")
		return
	}
	var req layoutSuggestRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || len(req.Sample) == 0 {
		writeErr(w, http.StatusBadRequest, "sample مطلوب (صفوف من الملف)")
		return
	}
	if strings.TrimSpace(req.Filename) == "" {
		req.Filename = "sellin.xlsx"
	}
	sug, err := h.svc.SuggestLayout(r.Context(), c.TenantID, req.Filename, req.Sample)
	if err != nil {
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, map[string]interface{}{
		"suggestion": sug,
		"note_ar":    "الاقتراح للتأكيد فقط — مفيش حاجة اتحفظت على بيانات الإنتاج",
	})
}

type chainSuggestRequest struct {
	UploadChain string   `json:"upload_chain"`
	Customers   []string `json:"customers"`
}

// HandleSuggestChains serves POST /api/v1/sell-in/assist/suggest-chains
func (h *SellInAssistHandler) HandleSuggestChains(w http.ResponseWriter, r *http.Request) {
	c, ok := tmWriteClaims(w, r)
	if !ok {
		return
	}
	if !dataQualityWriteRoles[c.Role] {
		writeErr(w, http.StatusForbidden, "مش مسموح لدورك تقترح ربط عميل←سلسلة")
		return
	}
	if h.svc == nil {
		writeErr(w, http.StatusServiceUnavailable, "خدمة مساعدة Sell-In مش متاحة")
		return
	}
	var req chainSuggestRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || len(req.Customers) == 0 {
		writeErr(w, http.StatusBadRequest, "customers مطلوب")
		return
	}
	sugs, err := h.svc.SuggestCustomerChains(r.Context(), c.TenantID, req.UploadChain, req.Customers)
	if err != nil {
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, map[string]interface{}{
		"suggestions": sugs,
		"count":       len(sugs),
		"note_ar":     "اقتراحات SELLIN_CUSTOMER_CHAIN_MAP — مش هتتطبق غير بعد موافقة يدوية. مفيش تغيير على الإنتاج.",
	})
}

type decideRequest struct {
	ID string `json:"id"`
}

// HandleApprove serves POST /api/v1/sell-in/assist/approve
func (h *SellInAssistHandler) HandleApprove(w http.ResponseWriter, r *http.Request) {
	h.decide(w, r, true)
}

// HandleReject serves POST /api/v1/sell-in/assist/reject
func (h *SellInAssistHandler) HandleReject(w http.ResponseWriter, r *http.Request) {
	h.decide(w, r, false)
}

func (h *SellInAssistHandler) decide(w http.ResponseWriter, r *http.Request, approve bool) {
	c, ok := tmWriteClaims(w, r)
	if !ok {
		return
	}
	if !dataQualityWriteRoles[c.Role] {
		writeErr(w, http.StatusForbidden, "مش مسموح لدورك تعتمد أو ترفض اقتراحات Sell-In")
		return
	}
	if h.svc == nil {
		writeErr(w, http.StatusServiceUnavailable, "خدمة مساعدة Sell-In مش متاحة")
		return
	}
	var req decideRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || strings.TrimSpace(req.ID) == "" {
		writeErr(w, http.StatusBadRequest, "id مطلوب")
		return
	}
	actor := c.Email
	if actor == "" {
		actor = c.UserID
	}
	var (
		sug *sellinassist.Suggestion
		err error
	)
	if approve {
		sug, err = h.svc.Approve(req.ID, c.TenantID, actor)
	} else {
		sug, err = h.svc.Reject(req.ID, c.TenantID, actor)
	}
	if err != nil {
		// Cross-tenant / missing ID: identical 404, no body disclosure of other tenants.
		if err == sellinassist.ErrNotFound {
			writeErr(w, http.StatusNotFound, sellinassist.ErrNotFound.Error())
			return
		}
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	resp := map[string]interface{}{
		"suggestion": sug,
		"note_ar":    "اتسجل القرار في ذاكرة السيرفر فقط (مش durable — بيضيع مع الـ restart ومش متشارك بين النسخ). مفيش تعديل على بيانات الإنتاج ولا على متغير SELLIN_CUSTOMER_CHAIN_MAP.",
		"durable":    false,
		"ram_only":   true,
	}
	if approve && sug.Kind == sellinassist.KindCustomerChain && sug.EnvFragment != "" {
		resp["ops_hint_ar"] = "لو حابب تفعّل الربط، ضيف المقطع ده لـ SELLIN_CUSTOMER_CHAIN_MAP بعد المراجعة: " + sug.EnvFragment
		resp["approved_fragments"] = h.svc.ApprovedEnvFragments(c.TenantID)
	}
	writeJSON(w, http.StatusOK, resp)
}

// HandleMetrics serves GET /api/v1/sell-in/assist/metrics
func (h *SellInAssistHandler) HandleMetrics(w http.ResponseWriter, r *http.Request) {
	c, ok := tmClaims(w, r)
	if !ok {
		return
	}
	_ = c
	if h.svc == nil {
		writeJSON(w, http.StatusOK, sellinassist.Metrics{})
		return
	}
	m := h.svc.GetMetrics(c.TenantID)
	writeJSON(w, http.StatusOK, map[string]interface{}{
		"metrics":            m,
		"approved_fragments": h.svc.ApprovedEnvFragments(c.TenantID),
		"success_label_ar":   "نسبة الاعتماد",
		"durable":            false,
		"ram_only":           true,
		"note_ar":            "المؤشرات والقرارات من ذاكرة السيرفر فقط (tenant-scoped) — بتضيع مع الـ restart ومش متشاركة بين النسخ، ومش بتغيّر الإنتاج",
	})
}
