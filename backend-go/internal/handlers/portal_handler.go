package handlers

import (
	"encoding/json"
	"net/http"
	"strings"

	"github.com/tashil/data-sharing/backend/internal/domain"
	"github.com/tashil/data-sharing/backend/internal/service/firestore"
)

// PortalHandler serves tenant portal metadata and branding.
type PortalHandler struct {
	fsRepo firestore.Repository
}

// NewPortalHandler constructs a PortalHandler.
func NewPortalHandler(fsRepo firestore.Repository) *PortalHandler {
	return &PortalHandler{fsRepo: fsRepo}
}

// HandleGetPortalMeta serves GET /api/v1/portal/{slug}/meta.
func (h *PortalHandler) HandleGetPortalMeta(w http.ResponseWriter, r *http.Request) {
	slug := r.PathValue("slug")
	if slug == "" {
		// Fallback for custom routing or query param
		slug = r.URL.Query().Get("slug")
	}

	if slug == "" {
		http.Error(w, `{"error":"slug parameter is required"}`, http.StatusBadRequest)
		return
	}

	slug = strings.TrimSpace(strings.ToLower(slug))
	profile, err := h.fsRepo.GetTenantProfileBySlug(r.Context(), slug)
	if err != nil {
		http.Error(w, `{"error":"tenant portal not found"}`, http.StatusNotFound)
		return
	}

	resp := domain.TenantMetaResponse{
		TenantID:       profile.TenantID,
		DisplayName:    profile.DisplayName,
		Slug:           profile.Slug,
		PortalURL:      profile.PortalURL,
		BrandSeedColor: profile.BrandSeedColor,
		LogoURL:        profile.LogoURL,
		AdminEmail:     profile.AdminEmail,
		ActiveChains:   profile.ActiveChains,
	}

	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(resp)
}
