package handlers

import (
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"strings"

	"github.com/tashil/data-sharing/backend/internal/domain"
	"github.com/tashil/data-sharing/backend/internal/service/firestore"
)

// CompetitorHandler serves custom competitor SKU persistence with tenant RLS.
type CompetitorHandler struct {
	repo  firestore.CompetitorSkuRepository
	audit firestore.Repository
}

// NewCompetitorHandler constructs a CompetitorHandler. audit may be nil.
func NewCompetitorHandler(repo firestore.CompetitorSkuRepository, audit firestore.Repository) *CompetitorHandler {
	return &CompetitorHandler{repo: repo, audit: audit}
}

type customSkuPayload struct {
	OwnBarcode            string  `json:"own_barcode"`
	OwnSkuName            string  `json:"own_sku_name"`
	OwnUnitPrice          float64 `json:"own_unit_price"`
	OwnVolumeUnits        float64 `json:"own_volume_units"`
	OwnVolumeUnitLabel    string  `json:"own_volume_unit_label"`
	CompetitorSkuName     string  `json:"competitor_sku_name"`
	CompetitorBrand       string  `json:"competitor_brand"`
	CompetitorSupplier    string  `json:"competitor_supplier"`
	Category              string  `json:"category"`
	PackSizeLabel         string  `json:"pack_size_label"`
	PackVolumeUnits       float64 `json:"pack_volume_units"`
	CompetitorPrice       float64 `json:"competitor_price"`
	RetailerChain         string  `json:"retailer_chain"`
	EstimatedMonthlyUnits *int    `json:"estimated_monthly_units"`
	IsPromoActive         bool    `json:"is_promo_active"`
}

func (p *customSkuPayload) normalize() {
	for _, s := range []*string{&p.OwnBarcode, &p.OwnSkuName, &p.OwnVolumeUnitLabel, &p.CompetitorSkuName,
		&p.CompetitorBrand, &p.CompetitorSupplier, &p.Category, &p.PackSizeLabel, &p.RetailerChain} {
		*s = strings.TrimSpace(*s)
	}
}

func (p customSkuPayload) validate() error {
	if p.OwnBarcode == "" && p.OwnSkuName == "" {
		return fmt.Errorf("own_barcode or own_sku_name is required")
	}
	if p.CompetitorSkuName == "" {
		return fmt.Errorf("competitor_sku_name is required")
	}
	if p.RetailerChain == "" {
		return fmt.Errorf("retailer_chain is required")
	}
	if p.CompetitorPrice <= 0 {
		return fmt.Errorf("competitor_price must be positive")
	}
	if p.OwnUnitPrice < 0 || p.OwnVolumeUnits < 0 || p.PackVolumeUnits < 0 {
		return fmt.Errorf("prices and volumes cannot be negative")
	}
	if p.EstimatedMonthlyUnits != nil && *p.EstimatedMonthlyUnits < 0 {
		return fmt.Errorf("estimated_monthly_units cannot be negative")
	}
	return nil
}

func (h *CompetitorHandler) recordAudit(r *http.Request, c *domain.UserClaims, action, details string) {
	if h.audit == nil {
		return
	}
	_ = h.audit.SaveAuditLog(r.Context(), &domain.AuditLogEntry{
		TenantID: normalizeAuditTenantID(c.TenantID), UserID: c.UserID, UserEmail: c.Email,
		UserRole: string(c.Role), Action: action, Resource: "custom_competitor_sku",
		Details: details, IPAddress: extractRequestIP(r),
	})
}

// HandleListCustomSkus serves GET /api/v1/competitors/custom-skus?chain=&category=
func (h *CompetitorHandler) HandleListCustomSkus(w http.ResponseWriter, r *http.Request) {
	c, ok := tmClaims(w, r)
	if !ok {
		return
	}
	q := r.URL.Query()
	chain := q.Get("chain")
	if k := kamChain(c); k != "" {
		chain = k
	}
	items, err := h.repo.ListCustomCompetitorSkus(r.Context(), c.TenantID, domain.CustomCompetitorSkuFilter{Chain: chain, Category: q.Get("category")})
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "failed to list custom competitor skus")
		return
	}
	writeJSON(w, http.StatusOK, map[string]interface{}{"custom_skus": items, "count": len(items)})
}

// HandleSaveCustomSku serves POST /api/v1/competitors/custom-skus (upsert by dedupe key).
func (h *CompetitorHandler) HandleSaveCustomSku(w http.ResponseWriter, r *http.Request) {
	c, ok := tmWriteClaims(w, r)
	if !ok {
		return
	}
	if !tmWriteRoles[c.Role] {
		writeErr(w, http.StatusForbidden, "role not allowed to modify competitor skus")
		return
	}
	var p customSkuPayload
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 1<<20)).Decode(&p); err != nil {
		writeErr(w, http.StatusBadRequest, "invalid JSON body")
		return
	}
	p.normalize()
	if err := p.validate(); err != nil {
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	if k := kamChain(c); k != "" && !strings.EqualFold(k, p.RetailerChain) {
		writeErr(w, http.StatusForbidden, "chain KAM can only add competitor skus for the assigned chain")
		return
	}
	units := 320
	if p.EstimatedMonthlyUnits != nil {
		units = *p.EstimatedMonthlyUnits
	}
	s := &domain.CustomCompetitorSku{
		TenantID: c.TenantID, OwnBarcode: p.OwnBarcode, OwnSkuName: p.OwnSkuName,
		OwnUnitPrice: p.OwnUnitPrice, OwnVolumeUnits: p.OwnVolumeUnits, OwnVolumeUnitLabel: p.OwnVolumeUnitLabel,
		CompetitorSkuName: p.CompetitorSkuName, CompetitorBrand: p.CompetitorBrand, CompetitorSupplier: p.CompetitorSupplier,
		Category: p.Category, PackSizeLabel: p.PackSizeLabel, PackVolumeUnits: p.PackVolumeUnits,
		CompetitorPrice: p.CompetitorPrice, RetailerChain: p.RetailerChain, EstimatedMonthlyUnits: units,
		IsPromoActive: p.IsPromoActive, CreatedBy: c.Email,
	}
	id := firestore.CustomCompetitorSkuID(s)
	existing, err := h.repo.ListCustomCompetitorSkus(r.Context(), c.TenantID, domain.CustomCompetitorSkuFilter{})
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "failed to load competitor skus")
		return
	}
	isUpdate := false
	for _, e := range existing {
		isUpdate = isUpdate || e.ID == id
	}
	if err := h.repo.SaveCustomCompetitorSku(r.Context(), s); err != nil {
		writeErr(w, http.StatusInternalServerError, "failed to save competitor sku")
		return
	}
	action, status := "CREATE_CUSTOM_COMPETITOR_SKU", http.StatusCreated
	if isUpdate {
		action, status = "UPDATE_CUSTOM_COMPETITOR_SKU", http.StatusOK
	}
	h.recordAudit(r, c, action, fmt.Sprintf("%s own=%s competitor=%s chain=%s price=%.2f", s.ID, ownKeyLabel(s), s.CompetitorSkuName, s.RetailerChain, s.CompetitorPrice))
	writeJSON(w, status, map[string]interface{}{"custom_sku": s, "updated": isUpdate})
}

// HandleDeleteCustomSku serves DELETE /api/v1/competitors/custom-skus/{id}
func (h *CompetitorHandler) HandleDeleteCustomSku(w http.ResponseWriter, r *http.Request) {
	c, ok := tmWriteClaims(w, r)
	if !ok {
		return
	}
	if !tmWriteRoles[c.Role] {
		writeErr(w, http.StatusForbidden, "role not allowed to modify competitor skus")
		return
	}
	id := strings.TrimSpace(r.PathValue("id"))
	if k := kamChain(c); k != "" {
		items, err := h.repo.ListCustomCompetitorSkus(r.Context(), c.TenantID, domain.CustomCompetitorSkuFilter{Chain: k})
		if err != nil {
			writeErr(w, http.StatusInternalServerError, "failed to load competitor sku")
			return
		}
		owned := false
		for _, s := range items {
			owned = owned || s.ID == id
		}
		if !owned {
			writeErr(w, http.StatusNotFound, "custom competitor sku not found")
			return
		}
	}
	if err := h.repo.DeleteCustomCompetitorSku(r.Context(), c.TenantID, id); err != nil {
		if errors.Is(err, firestore.ErrCustomSkuNotFound) {
			writeErr(w, http.StatusNotFound, "custom competitor sku not found")
			return
		}
		writeErr(w, http.StatusInternalServerError, "failed to delete competitor sku")
		return
	}
	h.recordAudit(r, c, "DELETE_CUSTOM_COMPETITOR_SKU", id)
	writeJSON(w, http.StatusOK, map[string]interface{}{"deleted": id})
}

func ownKeyLabel(s *domain.CustomCompetitorSku) string {
	if s.OwnBarcode != "" {
		return s.OwnBarcode
	}
	return s.OwnSkuName
}

type competitorMappingPayload struct {
	OwnBarcode         string `json:"own_barcode"`
	CompetitorBarcode  string `json:"competitor_barcode"`
	CompetitorSkuName  string `json:"competitor_sku_name"`
	CompetitorBrand    string `json:"competitor_brand"`
	CompetitorSupplier string `json:"competitor_supplier"`
	RetailerChain      string `json:"retailer_chain"`
}

func (p *competitorMappingPayload) normalize() {
	for _, s := range []*string{&p.OwnBarcode, &p.CompetitorBarcode, &p.CompetitorSkuName,
		&p.CompetitorBrand, &p.CompetitorSupplier, &p.RetailerChain} {
		*s = strings.TrimSpace(*s)
	}
}

func (p competitorMappingPayload) validate() error {
	if p.OwnBarcode == "" {
		return fmt.Errorf("own_barcode is required")
	}
	if p.CompetitorBarcode == "" {
		return fmt.Errorf("competitor_barcode is required")
	}
	if p.RetailerChain == "" {
		return fmt.Errorf("retailer_chain is required")
	}
	return nil
}

// HandleListCompetitorMappings serves GET /api/v1/competitors/mappings?chain=&own_barcode=
// Owner-approved pins only — never auto-matched. Empty until an owner saves one
// (this PR does not backfill production seed mappings).
func (h *CompetitorHandler) HandleListCompetitorMappings(w http.ResponseWriter, r *http.Request) {
	c, ok := tmClaims(w, r)
	if !ok {
		return
	}
	q := r.URL.Query()
	chain := q.Get("chain")
	if k := kamChain(c); k != "" {
		chain = k
	}
	items, err := h.repo.ListCompetitorMappings(r.Context(), c.TenantID, domain.CompetitorMappingFilter{
		Chain: chain, OwnBarcode: q.Get("own_barcode"),
	})
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "failed to list competitor mappings")
		return
	}
	writeJSON(w, http.StatusOK, map[string]interface{}{"mappings": items, "count": len(items)})
}

// HandleSaveCompetitorMapping serves POST /api/v1/competitors/mappings (upsert by dedupe key).
func (h *CompetitorHandler) HandleSaveCompetitorMapping(w http.ResponseWriter, r *http.Request) {
	c, ok := tmWriteClaims(w, r)
	if !ok {
		return
	}
	if !tmWriteRoles[c.Role] {
		writeErr(w, http.StatusForbidden, "role not allowed to modify competitor mappings")
		return
	}
	var p competitorMappingPayload
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 1<<20)).Decode(&p); err != nil {
		writeErr(w, http.StatusBadRequest, "invalid JSON body")
		return
	}
	p.normalize()
	if err := p.validate(); err != nil {
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	if k := kamChain(c); k != "" && !strings.EqualFold(k, p.RetailerChain) {
		writeErr(w, http.StatusForbidden, "chain KAM can only add mappings for the assigned chain")
		return
	}
	m := &domain.CompetitorMapping{
		TenantID: c.TenantID, OwnBarcode: p.OwnBarcode, CompetitorBarcode: p.CompetitorBarcode,
		CompetitorSkuName: p.CompetitorSkuName, CompetitorBrand: p.CompetitorBrand,
		CompetitorSupplier: p.CompetitorSupplier, RetailerChain: p.RetailerChain, CreatedBy: c.Email,
	}
	id := firestore.CompetitorMappingID(m)
	existing, err := h.repo.ListCompetitorMappings(r.Context(), c.TenantID, domain.CompetitorMappingFilter{})
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "failed to load competitor mappings")
		return
	}
	isUpdate := false
	for _, e := range existing {
		isUpdate = isUpdate || e.ID == id
	}
	if err := h.repo.SaveCompetitorMapping(r.Context(), m); err != nil {
		writeErr(w, http.StatusInternalServerError, "failed to save competitor mapping")
		return
	}
	action, status := "CREATE_COMPETITOR_MAPPING", http.StatusCreated
	if isUpdate {
		action, status = "UPDATE_COMPETITOR_MAPPING", http.StatusOK
	}
	h.recordAudit(r, c, action, fmt.Sprintf("%s own=%s competitor=%s chain=%s", m.ID, m.OwnBarcode, m.CompetitorBarcode, m.RetailerChain))
	writeJSON(w, status, map[string]interface{}{"mapping": m, "updated": isUpdate})
}

// HandleDeleteCompetitorMapping serves DELETE /api/v1/competitors/mappings/{id}
func (h *CompetitorHandler) HandleDeleteCompetitorMapping(w http.ResponseWriter, r *http.Request) {
	c, ok := tmWriteClaims(w, r)
	if !ok {
		return
	}
	if !tmWriteRoles[c.Role] {
		writeErr(w, http.StatusForbidden, "role not allowed to modify competitor mappings")
		return
	}
	id := strings.TrimSpace(r.PathValue("id"))
	if k := kamChain(c); k != "" {
		items, err := h.repo.ListCompetitorMappings(r.Context(), c.TenantID, domain.CompetitorMappingFilter{Chain: k})
		if err != nil {
			writeErr(w, http.StatusInternalServerError, "failed to load competitor mapping")
			return
		}
		owned := false
		for _, m := range items {
			owned = owned || m.ID == id
		}
		if !owned {
			writeErr(w, http.StatusNotFound, "competitor mapping not found")
			return
		}
	}
	if err := h.repo.DeleteCompetitorMapping(r.Context(), c.TenantID, id); err != nil {
		if errors.Is(err, firestore.ErrCompetitorMappingNotFound) {
			writeErr(w, http.StatusNotFound, "competitor mapping not found")
			return
		}
		writeErr(w, http.StatusInternalServerError, "failed to delete competitor mapping")
		return
	}
	h.recordAudit(r, c, "DELETE_COMPETITOR_MAPPING", id)
	writeJSON(w, http.StatusOK, map[string]interface{}{"deleted": id})
}
