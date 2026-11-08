package handlers

import (
	"encoding/json"
	"errors"
	"log"
	"net/http"
	"strings"

	"github.com/tashil/data-sharing/backend/internal/domain"
	"github.com/tashil/data-sharing/backend/internal/service/matcher"
)

// ProductMasterCatalogSource supplies Product Master items for matching (read-only).
type ProductMasterCatalogSource interface {
	GetProductMasterItems(tenantID string) []domain.ProductMasterItem
}

// ProductMatchHandler serves product/barcode matching + review queue APIs.
// It does not mutate Product Master or production Sell-In/Sell-Out rows.
type ProductMatchHandler struct {
	queue *matcher.Queue
	pm    ProductMasterCatalogSource
}

func NewProductMatchHandler(queue *matcher.Queue, pm ProductMasterCatalogSource) *ProductMatchHandler {
	return &ProductMatchHandler{queue: queue, pm: pm}
}

func (h *ProductMatchHandler) catalog(tenantID string) *matcher.Catalog {
	if h.pm == nil {
		return matcher.NewCatalog(nil)
	}
	return matcher.NewCatalog(h.pm.GetProductMasterItems(tenantID))
}

var productMatchWriteRoles = map[domain.UserRole]bool{
	domain.RoleSuperAdmin: true, domain.RoleVendorAdmin: true, domain.RoleAdmin: true,
	domain.RoleNationalSalesManager: true, domain.RoleExecutive: true,
}

func productMatchTenantSlug(tenantID string) string {
	return strings.TrimPrefix(strings.ToLower(strings.TrimSpace(tenantID)), "tenant-")
}

// HandleMatch serves POST /api/v1/product-match — dry match one or many queries (no persist).
func (h *ProductMatchHandler) HandleMatch(w http.ResponseWriter, r *http.Request) {
	c, ok := tmClaims(w, r)
	if !ok {
		return
	}
	var body struct {
		ItemCode string          `json:"item_code"`
		Barcode  string          `json:"barcode"`
		SKUName  string          `json:"sku_name"`
		Queries  []matcher.Query `json:"queries"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeErr(w, http.StatusBadRequest, "invalid JSON body")
		return
	}
	cat := h.catalog(c.TenantID)
	if len(body.Queries) > 0 {
		results := cat.MatchBatch(body.Queries)
		writeJSON(w, http.StatusOK, map[string]interface{}{
			"results": results,
			"count":   len(results),
		})
		return
	}
	res := cat.Match(matcher.Query{ItemCode: body.ItemCode, Barcode: body.Barcode, SKUName: body.SKUName})
	writeJSON(w, http.StatusOK, res)
}

// HandleEnqueue serves POST /api/v1/product-match/enqueue — match + enqueue review rows.
func (h *ProductMatchHandler) HandleEnqueue(w http.ResponseWriter, r *http.Request) {
	c, ok := tmWriteClaims(w, r)
	if !ok {
		return
	}
	if !productMatchWriteRoles[c.Role] {
		writeErr(w, http.StatusForbidden, "role not allowed to enqueue product match reviews")
		return
	}
	var body struct {
		SourceFile string          `json:"source_file"`
		Queries    []matcher.Query `json:"queries"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil || len(body.Queries) == 0 {
		writeErr(w, http.StatusBadRequest, "queries required")
		return
	}
	items, err := h.queue.EnqueueUnknowns(r.Context(), c.TenantID, body.SourceFile, body.Queries, h.catalog(c.TenantID))
	if err != nil {
		log.Printf("[product-match] enqueue failed tenant=%s: %v", productMatchTenantSlug(c.TenantID), err)
		writeErr(w, http.StatusInternalServerError, "تعذر إضافة عناصر المراجعة")
		return
	}
	metrics, _ := h.queue.Snapshot(r.Context(), c.TenantID)
	writeJSON(w, http.StatusOK, map[string]interface{}{
		"enqueued": items,
		"count":    len(items),
		"metrics":  metrics,
	})
}

// HandleListReview serves GET /api/v1/product-match/review?status=pending|approved|rejected
func (h *ProductMatchHandler) HandleListReview(w http.ResponseWriter, r *http.Request) {
	c, ok := tmClaims(w, r)
	if !ok {
		return
	}
	status := strings.TrimSpace(r.URL.Query().Get("status"))
	items, err := h.queue.List(r.Context(), c.TenantID, status)
	if err != nil {
		log.Printf("[product-match] list failed tenant=%s: %v", productMatchTenantSlug(c.TenantID), err)
		writeErr(w, http.StatusInternalServerError, "تعذر تحميل قائمة المراجعة")
		return
	}
	metrics, _ := h.queue.Snapshot(r.Context(), c.TenantID)
	writeJSON(w, http.StatusOK, map[string]interface{}{
		"items":   items,
		"count":   len(items),
		"metrics": metrics,
	})
}

// HandleDecide serves POST /api/v1/product-match/review/decide
func (h *ProductMatchHandler) HandleDecide(w http.ResponseWriter, r *http.Request) {
	c, ok := tmWriteClaims(w, r)
	if !ok {
		return
	}
	if !productMatchWriteRoles[c.Role] {
		writeErr(w, http.StatusForbidden, "role not allowed to decide product match reviews")
		return
	}
	var body struct {
		ID             string `json:"id"`
		Status         string `json:"status"` // approved | rejected
		ReasonAR       string `json:"reason_ar"`
		ChosenItemCode string `json:"chosen_item_code"`
		ChosenBarcode  string `json:"chosen_barcode"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil || strings.TrimSpace(body.ID) == "" {
		writeErr(w, http.StatusBadRequest, "id and status required")
		return
	}
	item, err := h.queue.Decide(r.Context(), c.TenantID, body.ID, body.Status, c.Email, body.ReasonAR, body.ChosenItemCode, body.ChosenBarcode, matcher.DecideOptions{
		Catalog: h.catalog(c.TenantID),
	})
	if err != nil {
		writeProductMatchDecideErr(w, productMatchTenantSlug(c.TenantID), err)
		return
	}
	metrics, _ := h.queue.Snapshot(r.Context(), c.TenantID)
	writeJSON(w, http.StatusOK, map[string]interface{}{
		"item":    item,
		"metrics": metrics,
	})
}

// writeProductMatchDecideErr maps domain errors to safe client messages.
// Raw Firestore / RPC / err.Error() text is never returned to the client.
func writeProductMatchDecideErr(w http.ResponseWriter, tenantSlug string, err error) {
	log.Printf("[product-match] decide failed tenant=%s: %v", tenantSlug, err)
	switch {
	case errors.Is(err, matcher.ErrNotFound):
		writeErr(w, http.StatusNotFound, "عنصر المراجعة غير موجود")
	case errors.Is(err, matcher.ErrAlreadyDecided):
		writeErr(w, http.StatusConflict, "تم البت في هذا العنصر مسبقاً")
	case errors.Is(err, matcher.ErrInventedBarcode):
		writeErr(w, http.StatusBadRequest, "رفض باركود مصنوع: لا يتم اختراع باركودات")
	case errors.Is(err, matcher.ErrTenantMismatch):
		writeErr(w, http.StatusForbidden, "غير مسموح عبر المستأجر")
	default:
		// Validation / catalog / store failures: fixed client copy only.
		msg := err.Error()
		lower := strings.ToLower(msg)
		if strings.Contains(lower, "firestore") ||
			strings.Contains(lower, "rpc error") ||
			strings.Contains(lower, "code =") ||
			strings.Contains(lower, "google.golang.org") ||
			strings.Contains(lower, "unexpected status") {
			writeErr(w, http.StatusInternalServerError, "تعذر حفظ قرار المراجعة")
			return
		}
		if strings.Contains(lower, "status must be") {
			writeErr(w, http.StatusBadRequest, "الحالة يجب أن تكون اعتماد أو رفض")
			return
		}
		writeErr(w, http.StatusBadRequest, "القرار غير صالح")
	}
}

// HandleBulkDecide serves POST /api/v1/product-match/review/bulk-decide
// Body: {ids:[], status:"approved"|"rejected", reason_ar?:string}
// Approve uses each item's matched Product Master suggestion only (never invents barcodes).
func (h *ProductMatchHandler) HandleBulkDecide(w http.ResponseWriter, r *http.Request) {
	c, ok := tmWriteClaims(w, r)
	if !ok {
		return
	}
	if !productMatchWriteRoles[c.Role] {
		writeErr(w, http.StatusForbidden, "role not allowed to decide product match reviews")
		return
	}
	var body struct {
		IDs      []string `json:"ids"`
		Status   string   `json:"status"`
		ReasonAR string   `json:"reason_ar"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil || len(body.IDs) == 0 {
		writeErr(w, http.StatusBadRequest, "ids and status required")
		return
	}
	results, err := h.queue.DecideBulk(r.Context(), c.TenantID, body.IDs, body.Status, c.Email, body.ReasonAR, matcher.DecideOptions{
		Catalog: h.catalog(c.TenantID),
	})
	if err != nil {
		log.Printf("[product-match] bulk-decide failed tenant=%s: %v", productMatchTenantSlug(c.TenantID), err)
		msg := "تعذر تنفيذ الاعتماد الجماعي"
		if strings.Contains(strings.ToLower(err.Error()), "status must be") {
			msg = "الحالة يجب أن تكون اعتماد أو رفض"
			writeErr(w, http.StatusBadRequest, msg)
			return
		}
		writeErr(w, http.StatusBadRequest, msg)
		return
	}
	approved, skipped, failed := 0, 0, 0
	for _, row := range results {
		switch {
		case row.OK:
			approved++
		case row.Skipped:
			skipped++
		default:
			failed++
		}
	}
	metrics, _ := h.queue.Snapshot(r.Context(), c.TenantID)
	writeJSON(w, http.StatusOK, map[string]interface{}{
		"results":  results,
		"count":    len(results),
		"approved": approved,
		"skipped":  skipped,
		"failed":   failed,
		"metrics":  metrics,
	})
}

// HandleMetrics serves GET /api/v1/product-match/metrics
func (h *ProductMatchHandler) HandleMetrics(w http.ResponseWriter, r *http.Request) {
	c, ok := tmClaims(w, r)
	if !ok {
		return
	}
	metrics, err := h.queue.Snapshot(r.Context(), c.TenantID)
	if err != nil {
		log.Printf("[product-match] metrics failed tenant=%s: %v", productMatchTenantSlug(c.TenantID), err)
		writeErr(w, http.StatusInternalServerError, "تعذر تحميل مقاييس المطابقة")
		return
	}
	writeJSON(w, http.StatusOK, metrics)
}

// Queue exposes the underlying queue for upload hooks in main.
func (h *ProductMatchHandler) Queue() *matcher.Queue { return h.queue }
