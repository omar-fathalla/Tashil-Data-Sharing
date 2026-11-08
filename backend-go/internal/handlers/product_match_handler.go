package handlers

import (
	"encoding/json"
	"errors"
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
		writeErr(w, http.StatusInternalServerError, err.Error())
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
		writeErr(w, http.StatusInternalServerError, err.Error())
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
		writeProductMatchDecideErr(w, err)
		return
	}
	metrics, _ := h.queue.Snapshot(r.Context(), c.TenantID)
	writeJSON(w, http.StatusOK, map[string]interface{}{
		"item":    item,
		"metrics": metrics,
	})
}

// writeProductMatchDecideErr maps domain errors to safe client messages.
// Raw Firestore / RPC text is never returned to the client.
func writeProductMatchDecideErr(w http.ResponseWriter, err error) {
	switch {
	case errors.Is(err, matcher.ErrNotFound):
		writeErr(w, http.StatusNotFound, "عنصر المراجعة غير موجود")
	case errors.Is(err, matcher.ErrAlreadyDecided):
		writeErr(w, http.StatusConflict, err.Error())
	case errors.Is(err, matcher.ErrInventedBarcode):
		writeErr(w, http.StatusBadRequest, err.Error())
	case errors.Is(err, matcher.ErrTenantMismatch):
		writeErr(w, http.StatusForbidden, "غير مسموح عبر المستأجر")
	default:
		msg := err.Error()
		lower := strings.ToLower(msg)
		if strings.Contains(lower, "firestore") ||
			strings.Contains(lower, "rpc error") ||
			strings.Contains(lower, "code =") ||
			strings.Contains(lower, "google.golang.org") {
			writeErr(w, http.StatusInternalServerError, "تعذر حفظ قرار المراجعة")
			return
		}
		writeErr(w, http.StatusBadRequest, msg)
	}
}

// HandleMetrics serves GET /api/v1/product-match/metrics
func (h *ProductMatchHandler) HandleMetrics(w http.ResponseWriter, r *http.Request) {
	c, ok := tmClaims(w, r)
	if !ok {
		return
	}
	metrics, err := h.queue.Snapshot(r.Context(), c.TenantID)
	if err != nil {
		writeErr(w, http.StatusInternalServerError, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, metrics)
}

// Queue exposes the underlying queue for upload hooks in main.
func (h *ProductMatchHandler) Queue() *matcher.Queue { return h.queue }
