package handlers

import (
	"encoding/json"
	"net/http"

	"github.com/tashil/data-sharing/backend/internal/middleware"
	"github.com/tashil/data-sharing/backend/internal/service/firestore"
)

// StoreHandler provides store and tenant master metadata.
type StoreHandler struct {
	fsRepo firestore.Repository
}

// NewStoreHandler constructs a StoreHandler.
func NewStoreHandler(fsRepo firestore.Repository) *StoreHandler {
	return &StoreHandler{fsRepo: fsRepo}
}

// HandleGetStores serves GET /api/v1/stores.
func (h *StoreHandler) HandleGetStores(w http.ResponseWriter, r *http.Request) {
	tenantID, err := middleware.EnforceTenantRLS(r)
	if err != nil {
		http.Error(w, `{"error":"unauthorized tenant context"}`, http.StatusUnauthorized)
		return
	}

	stores, err := h.fsRepo.GetStoresByTenant(r.Context(), tenantID)
	if err != nil {
		http.Error(w, `{"error":"failed to get stores"}`, http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]interface{}{
		"stores": stores,
		"count":  len(stores),
	})
}

// HandleGetTenants serves GET /api/v1/tenants.
func (h *StoreHandler) HandleGetTenants(w http.ResponseWriter, r *http.Request) {
	tenants, err := h.fsRepo.ListTenants(r.Context())
	if err != nil {
		http.Error(w, `{"error":"failed to list tenants"}`, http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(tenants)
}

// HandleGetBatches serves GET /api/v1/batches.
func (h *StoreHandler) HandleGetBatches(w http.ResponseWriter, r *http.Request) {
	tenantID, err := middleware.EnforceTenantRLS(r)
	if err != nil {
		http.Error(w, `{"error":"unauthorized tenant context"}`, http.StatusUnauthorized)
		return
	}

	batches, err := h.fsRepo.ListIngestionBatches(r.Context(), tenantID)
	if err != nil {
		http.Error(w, `{"error":"failed to list batches"}`, http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(batches)
}
