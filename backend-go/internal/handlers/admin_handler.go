package handlers

import (
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"regexp"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/tashil/data-sharing/backend/internal/domain"
	"github.com/tashil/data-sharing/backend/internal/middleware"
	"github.com/tashil/data-sharing/backend/internal/security"
	"github.com/tashil/data-sharing/backend/internal/service/firestore"
)

// AdminHandler manages tenant company lifecycle and provisioning.
type AdminHandler struct {
	fsRepo firestore.Repository
	// referencedChains lists chain codes used by Sell-In data or chain rules (read-only, optional).
	referencedChains func(tenantID string) []string
}

// WithReferencedChains lets GET /admin/chains?include_referenced=1 add chains that Sell-In data
// or SELLIN_CUSTOMER_CHAIN_MAP uses but that have no registered document (registered:false).
func (h *AdminHandler) WithReferencedChains(f func(tenantID string) []string) *AdminHandler {
	h.referencedChains = f
	return h
}

func chainTenantSlug(t string) string {
	t = strings.ToLower(strings.TrimSpace(t))
	t = strings.TrimPrefix(strings.TrimPrefix(t, "tenant-"), "tenant_")
	return t
}

// chainWriteAccess authorizes chain catalog writes (create / update / delete) from the verified JWT
// claims only: role must be an admin role, and the tenant is the claims tenant. A header, query or
// body tenant that differs from the claims tenant is refused (super admins may target any tenant).
// X-Tenant-ID / X-Simulated-Role headers never grant write access. Returns (tenant, status, message).
func (h *AdminHandler) chainWriteAccess(r *http.Request, bodyTenantID string) (string, int, string) {
	claims, ok := middleware.GetVerifiedClaims(r.Context())
	if !ok || claims == nil || strings.TrimSpace(claims.UserID) == "" && strings.TrimSpace(claims.Email) == "" {
		return "", http.StatusUnauthorized, "unauthorized: a valid admin token is required"
	}
	super := claims.Role == domain.RoleSuperAdmin
	if !chainWriteRoles[claims.Role] {
		return "", http.StatusForbidden, "forbidden: admin role required"
	}
	requested := ""
	for _, t := range []string{bodyTenantID, r.URL.Query().Get("tenant_id"), r.Header.Get("X-Tenant-ID")} {
		if t = strings.TrimSpace(t); t == "" {
			continue
		}
		if requested != "" && chainTenantSlug(requested) != chainTenantSlug(t) {
			return "", http.StatusForbidden, "forbidden: conflicting tenant ids"
		}
		requested = t
	}
	own := strings.TrimSpace(claims.TenantID)
	if super || own == "system" {
		if requested != "" {
			return requested, 0, ""
		}
		if own == "" || own == "system" {
			return "adeco", 0, ""
		}
		return own, 0, ""
	}
	if own == "" {
		return "", http.StatusForbidden, "forbidden: token has no tenant"
	}
	if requested != "" && chainTenantSlug(requested) != chainTenantSlug(own) {
		return "", http.StatusForbidden, "forbidden: tenant does not match token"
	}
	return own, 0, ""
}

func writeChainAccessError(w http.ResponseWriter, code int, msg string) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(code)
	_ = json.NewEncoder(w).Encode(map[string]string{"error": msg})
}

// NewAdminHandler constructs an AdminHandler.
func NewAdminHandler(fsRepo firestore.Repository) *AdminHandler {
	return &AdminHandler{fsRepo: fsRepo}
}

// checkSuperAdminAccess uses the verified token claims only; no header can grant super admin.
func (h *AdminHandler) checkSuperAdminAccess(r *http.Request) bool {
	claims, ok := middleware.WriteClaims(r.Context())
	if !ok || claims == nil {
		return false
	}
	if claims.Role == domain.RoleSuperAdmin || claims.TenantID == "system" {
		return true
	}
	return false
}

func (h *AdminHandler) resolveChainTenantID(r *http.Request, bodyTenantID string) string {
	if t := strings.TrimSpace(bodyTenantID); t != "" {
		return t
	}
	if q := strings.TrimSpace(r.URL.Query().Get("tenant_id")); q != "" {
		return q
	}
	if hdr := strings.TrimSpace(r.Header.Get("X-Tenant-ID")); hdr != "" {
		return hdr
	}
	if claims, ok := middleware.GetUserClaims(r.Context()); ok && claims != nil {
		if t := strings.TrimSpace(claims.TenantID); t != "" && t != "system" {
			return t
		}
	}
	return "adeco"
}

// HandleListTenants serves GET /api/v1/admin/tenants.
func (h *AdminHandler) HandleListTenants(w http.ResponseWriter, r *http.Request) {
	if !h.checkSuperAdminAccess(r) {
		http.Error(w, `{"error":"forbidden: super admin access required"}`, http.StatusForbidden)
		return
	}

	profiles, err := h.fsRepo.ListTenantProfiles(r.Context())
	if err != nil {
		http.Error(w, `{"error":"failed to list tenant profiles"}`, http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(profiles)
}

// HandleListChains serves GET /api/v1/admin/chains.
func (h *AdminHandler) HandleListChains(w http.ResponseWriter, r *http.Request) {
	tenantID := h.resolveChainTenantID(r, "")
	chains, err := h.fsRepo.ListRetailChainsByTenant(r.Context(), tenantID)
	if err != nil {
		http.Error(w, `{"error":"failed to list retail chains"}`, http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	if r.URL.Query().Get("include_referenced") != "1" || h.referencedChains == nil {
		_ = json.NewEncoder(w).Encode(chains)
		return
	}
	// Read-only: registered chains plus chains referenced by Sell-In data / chain rules. Nothing is written.
	type listedChain struct {
		domain.RetailChain
		Registered bool `json:"registered"`
	}
	out := make([]listedChain, 0, len(chains))
	seen := map[string]bool{}
	for _, c := range chains {
		seen[strings.ToLower(c.Code)] = true
		out = append(out, listedChain{RetailChain: c, Registered: true})
	}
	for _, code := range h.referencedChains(tenantID) {
		code = strings.ToLower(strings.TrimSpace(code))
		if code == "" || seen[code] {
			continue
		}
		seen[code] = true
		name := code
		if n, ok := domain.GetCustomChainDisplayName(code); ok && n != "" {
			name = n
		}
		out = append(out, listedChain{RetailChain: domain.RetailChain{ChainID: code, Code: code, DisplayName: name, TenantID: chainTenantSlug(tenantID)}})
	}
	_ = json.NewEncoder(w).Encode(out)
}

// HandleCreateChain serves POST /api/v1/admin/chains.
func (h *AdminHandler) HandleCreateChain(w http.ResponseWriter, r *http.Request) {
	var req domain.CreateRetailChainRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, `{"error":"invalid request payload"}`, http.StatusBadRequest)
		return
	}

	tenantID, code0, msg := h.chainWriteAccess(r, req.TenantID)
	if code0 != 0 {
		writeChainAccessError(w, code0, msg)
		return
	}

	if strings.TrimSpace(req.DisplayName) == "" {
		http.Error(w, `{"error":"display_name is required"}`, http.StatusBadRequest)
		return
	}

	code := strings.TrimSpace(strings.ToLower(req.Code))
	if code == "" {
		re := regexp.MustCompile("[^a-z0-9]+")
		code = strings.Trim(re.ReplaceAllString(strings.ToLower(req.DisplayName), "-"), "-")
		if code == "" {
			code = "chain-" + uuid.New().String()[:8]
		}
	}

	chainType := strings.TrimSpace(req.ChainType)
	if chainType == "" {
		chainType = "supermarket"
	}

	claims, _ := middleware.GetVerifiedClaims(r.Context())
	createdBy := ""
	if claims != nil {
		createdBy = strings.TrimSpace(claims.Email)
		if createdBy == "" {
			createdBy = claims.UserID
		}
	}
	chain := &domain.RetailChain{
		ChainID:     code,
		TenantID:    tenantID,
		DisplayName: strings.TrimSpace(req.DisplayName),
		Code:        code,
		ChainType:   chainType,
		StoreCount:  req.StoreCount,
		CreatedAt:   time.Now().UTC(),
		CreatedBy:   createdBy,
	}

	// Create-if-absent: a duplicate code is 409, never an overwrite. Registering a chain touches no
	// Sell-In row, StoreID or prefix; it only adds the chain to the catalog.
	if err := h.fsRepo.CreateRetailChain(r.Context(), chain); err != nil {
		if errors.Is(err, firestore.ErrRetailChainExists) {
			writeChainAccessError(w, http.StatusConflict, fmt.Sprintf("السلسلة بالكود %q متسجلة قبل كده؛ مفيش حاجة اتغيرت", code))
			return
		}
		http.Error(w, `{"error":"failed to save retail chain"}`, http.StatusInternalServerError)
		return
	}

	// Keep tenant profile AssignedChains in sync if profile exists
	if profile, err := h.fsRepo.GetTenantProfileBySlug(r.Context(), strings.TrimPrefix(strings.ToLower(tenantID), "tenant-")); err == nil && profile != nil {
		found := false
		for _, c := range profile.ActiveChains {
			if strings.EqualFold(c, code) {
				found = true
				break
			}
		}
		if !found {
			profile.ActiveChains = append(profile.ActiveChains, code)
			_ = h.fsRepo.SaveTenantProfile(r.Context(), profile)
		}
	}

	// Record audit log (who and when, from the verified token)
	_ = h.fsRepo.SaveAuditLog(r.Context(), &domain.AuditLogEntry{
		LogID:     "log-" + uuid.New().String()[:8],
		TenantID:  tenantID,
		UserID:    claims.UserID,
		UserEmail: createdBy,
		UserRole:  string(claims.Role),
		Action:    "CREATE_CHAIN",
		Resource:  chain.Code,
		Details:   fmt.Sprintf("إضافة سلسلة تجزئة للشركة (%s): %s (كود: %s)", tenantID, chain.DisplayName, chain.Code),
		IPAddress: r.RemoteAddr,
		Status:    "success",
		CreatedAt: time.Now(),
	})

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusCreated)
	_ = json.NewEncoder(w).Encode(chain)
}

// HandleUpdateChain serves PUT /api/v1/admin/chains/{id}.
func (h *AdminHandler) HandleUpdateChain(w http.ResponseWriter, r *http.Request) {
	code := r.PathValue("id")
	if code == "" {
		code = r.URL.Query().Get("code")
	}
	if code == "" {
		http.Error(w, `{"error":"chain code or id is required"}`, http.StatusBadRequest)
		return
	}

	var req domain.UpdateRetailChainRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, `{"error":"invalid request payload"}`, http.StatusBadRequest)
		return
	}

	tenantID, code0, msg := h.chainWriteAccess(r, req.TenantID)
	if code0 != 0 {
		writeChainAccessError(w, code0, msg)
		return
	}

	existing, err := h.fsRepo.GetRetailChainByTenant(r.Context(), tenantID, code)
	if err != nil || existing == nil {
		http.Error(w, fmt.Sprintf(`{"error":"retail chain '%s' not found"}`, code), http.StatusNotFound)
		return
	}

	if strings.TrimSpace(req.DisplayName) != "" {
		existing.DisplayName = strings.TrimSpace(req.DisplayName)
	}
	if strings.TrimSpace(req.ChainType) != "" {
		existing.ChainType = strings.TrimSpace(req.ChainType)
	}
	if req.StoreCount >= 0 {
		existing.StoreCount = req.StoreCount
	}
	existing.TenantID = tenantID

	if err := h.fsRepo.SaveRetailChain(r.Context(), existing); err != nil {
		http.Error(w, `{"error":"failed to update retail chain"}`, http.StatusInternalServerError)
		return
	}

	claims, _ := middleware.GetUserClaims(r.Context())
	adminEmail := "tenant-admin"
	if claims != nil && claims.Email != "" {
		adminEmail = claims.Email
	}
	_ = h.fsRepo.SaveAuditLog(r.Context(), &domain.AuditLogEntry{
		LogID:     "log-" + uuid.New().String()[:8],
		TenantID:  tenantID,
		UserID:    "admin",
		UserEmail: adminEmail,
		UserRole:  "vendor_admin",
		Action:    "UPDATE_CHAIN",
		Resource:  existing.Code,
		Details:   fmt.Sprintf("تعديل بيانات سلسلة التجزئة (%s): %s (فروع: %d)", tenantID, existing.DisplayName, existing.StoreCount),
		IPAddress: r.RemoteAddr,
		Status:    "success",
		CreatedAt: time.Now(),
	})

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	_ = json.NewEncoder(w).Encode(existing)
}

// HandleDeleteChain serves DELETE /api/v1/admin/chains/{id}.
func (h *AdminHandler) HandleDeleteChain(w http.ResponseWriter, r *http.Request) {
	tenantID, code0, msg := h.chainWriteAccess(r, "")
	if code0 != 0 {
		writeChainAccessError(w, code0, msg)
		return
	}

	code := r.PathValue("id")
	if code == "" {
		code = r.URL.Query().Get("code")
	}
	if code == "" {
		http.Error(w, `{"error":"chain code or id is required"}`, http.StatusBadRequest)
		return
	}

	existing, err := h.fsRepo.GetRetailChainByTenant(r.Context(), tenantID, code)
	if err != nil || existing == nil {
		http.Error(w, fmt.Sprintf(`{"error":"retail chain '%s' not found"}`, code), http.StatusNotFound)
		return
	}

	if err := h.fsRepo.DeleteRetailChainByTenant(r.Context(), tenantID, code); err != nil {
		http.Error(w, `{"error":"failed to delete retail chain"}`, http.StatusInternalServerError)
		return
	}

	// Remove from tenant profile AssignedChains if present
	if profile, err := h.fsRepo.GetTenantProfileBySlug(r.Context(), strings.TrimPrefix(strings.ToLower(tenantID), "tenant-")); err == nil && profile != nil {
		filtered := make([]string, 0, len(profile.ActiveChains))
		for _, c := range profile.ActiveChains {
			if !strings.EqualFold(c, code) {
				filtered = append(filtered, c)
			}
		}
		profile.ActiveChains = filtered
		_ = h.fsRepo.SaveTenantProfile(r.Context(), profile)
	}

	claims, _ := middleware.GetUserClaims(r.Context())
	adminEmail := "tenant-admin"
	if claims != nil && claims.Email != "" {
		adminEmail = claims.Email
	}
	_ = h.fsRepo.SaveAuditLog(r.Context(), &domain.AuditLogEntry{
		LogID:     "log-" + uuid.New().String()[:8],
		TenantID:  tenantID,
		UserID:    "admin",
		UserEmail: adminEmail,
		UserRole:  "vendor_admin",
		Action:    "DELETE_CHAIN",
		Resource:  code,
		Details:   fmt.Sprintf("حذف سلسلة التجزئة للشركة (%s): %s (%s)", tenantID, existing.DisplayName, code),
		IPAddress: r.RemoteAddr,
		Status:    "success",
		CreatedAt: time.Now(),
	})

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	_ = json.NewEncoder(w).Encode(map[string]interface{}{
		"status":    "deleted",
		"code":      code,
		"tenant_id": tenantID,
		"message":   "تم حذف سلسلة التجزئة بنجاح",
	})
}

// HandleCreateTenant serves POST /api/v1/admin/tenants.
func (h *AdminHandler) HandleCreateTenant(w http.ResponseWriter, r *http.Request) {
	if !h.checkSuperAdminAccess(r) {
		http.Error(w, `{"error":"forbidden: super admin access required"}`, http.StatusForbidden)
		return
	}

	var req domain.CreateTenantRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, `{"error":"invalid request payload"}`, http.StatusBadRequest)
		return
	}

	if strings.TrimSpace(req.DisplayName) == "" || strings.TrimSpace(req.AdminEmail) == "" {
		http.Error(w, `{"error":"display_name and admin_email are required"}`, http.StatusBadRequest)
		return
	}

	// Generate or sanitize slug
	slug := strings.TrimSpace(strings.ToLower(req.Slug))
	if slug == "" {
		re := regexp.MustCompile("[^a-z0-9]+")
		slug = strings.Trim(re.ReplaceAllString(strings.ToLower(req.DisplayName), "-"), "-")
		if slug == "" {
			slug = "tenant-" + uuid.New().String()[:8]
		}
	}

	// Check if slug or tenant already exists
	if existing, _ := h.fsRepo.GetTenantProfileBySlug(r.Context(), slug); existing != nil {
		http.Error(w, fmt.Sprintf(`{"error":"company slug '%s' is already registered"}`, slug), http.StatusConflict)
		return
	}

	brandColor := strings.TrimSpace(req.BrandSeedColor)
	if brandColor == "" {
		brandColor = "#35A211" // ADCO logo green
	}

	portalURL := fmt.Sprintf("http://localhost:3000/portal/%s", slug)
	tenantID := slug

	// Determine temporary password
	tempPassword := strings.TrimSpace(req.AdminPassword)
	if tempPassword == "" {
		tempPassword = security.GenerateTemporaryPassword(12)
	}

	passHash, err := security.HashPassword(tempPassword)
	if err != nil {
		http.Error(w, `{"error":"failed to hash admin password"}`, http.StatusInternalServerError)
		return
	}

	chains := req.ActiveChains
	if chains == nil {
		chains = []string{}
	}

	now := time.Now()

	profile := domain.TenantProfile{
		TenantID:       tenantID,
		DisplayName:    req.DisplayName,
		Slug:           slug,
		PortalURL:      portalURL,
		BrandSeedColor: brandColor,
		LogoURL:        req.LogoURL,
		AdminEmail:     req.AdminEmail,
		ActiveChains:   chains,
		CreatedAt:      now,
	}

	if err := h.fsRepo.SaveTenantProfile(r.Context(), &profile); err != nil {
		http.Error(w, `{"error":"failed to save tenant profile"}`, http.StatusInternalServerError)
		return
	}

	adminName := req.AdminName
	if adminName == "" {
		adminName = fmt.Sprintf("مسؤول %s", req.DisplayName)
	}

	adminUser := domain.TenantUser{
		UserID:        fmt.Sprintf("user-%s-admin", slug),
		TenantID:      tenantID,
		Email:         req.AdminEmail,
		FullName:      adminName,
		PasswordHash:  passHash,
		Role:          domain.RoleVendorAdmin,
		RoleDisplayAr: "مدير الشركة الموردة",
		Active:        true,
		CreatedAt:     now,
		LastLogin:     time.Time{},
	}

	if err := h.fsRepo.SaveUser(r.Context(), &adminUser); err != nil {
		http.Error(w, `{"error":"failed to create admin user"}`, http.StatusInternalServerError)
		return
	}

	if claims, ok := middleware.GetUserClaims(r.Context()); ok && claims != nil {
		_ = h.fsRepo.SaveAuditLog(r.Context(), &domain.AuditLogEntry{
			TenantID:  normalizeAuditTenantID(tenantID),
			UserID:    claims.UserID,
			UserEmail: claims.Email,
			UserRole:  string(claims.Role),
			Action:    "TENANT_PROVISION",
			Resource:  "admin/tenants/" + slug,
			Details:   fmt.Sprintf("إنشاء وتجهيز بوابة الشركة: %s (%s)", profile.DisplayName, slug),
			IPAddress: extractRequestIP(r),
			Status:    "SUCCESS",
			CreatedAt: now,
		})
	}

	resp := domain.CreateTenantResponse{
		Tenant:            profile,
		AdminUser:         adminUser,
		TemporaryPassword: tempPassword,
		PortalURL:         portalURL,
		Message:           "تم إنشاء وتجهيز بوابة الشركة وحساب الإدارة بنجاح",
	}

	w.WriteHeader(http.StatusCreated)
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(resp)
}

// HandleResetTenantPassword serves POST /api/v1/admin/tenants/{id}/reset-password.
func (h *AdminHandler) HandleResetTenantPassword(w http.ResponseWriter, r *http.Request) {
	if !h.checkSuperAdminAccess(r) {
		http.Error(w, `{"error":"forbidden: super admin access required"}`, http.StatusForbidden)
		return
	}

	tenantID := r.PathValue("id")
	if tenantID == "" {
		http.Error(w, `{"error":"tenant id is required"}`, http.StatusBadRequest)
		return
	}

	profile, err := h.fsRepo.GetTenantProfile(r.Context(), tenantID)
	if err != nil {
		profile, err = h.fsRepo.GetTenantProfileBySlug(r.Context(), tenantID)
	}
	if err != nil || profile == nil {
		http.Error(w, `{"error":"tenant company not found"}`, http.StatusNotFound)
		return
	}

	var req domain.AdminResetPasswordRequest
	_ = json.NewDecoder(r.Body).Decode(&req)

	newPassword := strings.TrimSpace(req.NewPassword)
	if newPassword == "" {
		newPassword = security.GenerateTemporaryPassword(12)
	}

	user, err := h.fsRepo.GetUserByEmail(r.Context(), profile.TenantID, profile.AdminEmail)
	if err != nil {
		http.Error(w, `{"error":"admin user for tenant not found"}`, http.StatusNotFound)
		return
	}

	passHash, err := security.HashPassword(newPassword)
	if err != nil {
		http.Error(w, `{"error":"failed to hash new password"}`, http.StatusInternalServerError)
		return
	}

	if err := h.fsRepo.UpdateUserPassword(r.Context(), user.UserID, passHash); err != nil {
		http.Error(w, `{"error":"failed to update password"}`, http.StatusInternalServerError)
		return
	}

	if claims, ok := middleware.GetUserClaims(r.Context()); ok && claims != nil {
		_ = h.fsRepo.SaveAuditLog(r.Context(), &domain.AuditLogEntry{
			TenantID:  normalizeAuditTenantID(profile.TenantID),
			UserID:    claims.UserID,
			UserEmail: claims.Email,
			UserRole:  string(claims.Role),
			Action:    "ADMIN_PASSWORD_RESET",
			Resource:  "admin/tenants/" + profile.Slug + "/reset-password",
			Details:   fmt.Sprintf("إعادة تعيين كلمة مرور مسؤول شركة %s (%s)", profile.DisplayName, user.Email),
			IPAddress: extractRequestIP(r),
			Status:    "SUCCESS",
			CreatedAt: time.Now(),
		})
	}

	resp := domain.AdminResetPasswordResponse{
		TenantID:          profile.TenantID,
		AdminEmail:        user.Email,
		TemporaryPassword: newPassword,
		Message:           fmt.Sprintf("تم توليد كلمة مرور جديدة لمسؤول شركة %s", profile.DisplayName),
	}

	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(resp)
}

// HandleUpdateTenant serves PUT /api/v1/admin/tenants/{id}.
func (h *AdminHandler) HandleUpdateTenant(w http.ResponseWriter, r *http.Request) {
	if !h.checkSuperAdminAccess(r) {
		http.Error(w, `{"error":"forbidden: super admin access required"}`, http.StatusForbidden)
		return
	}

	slug := r.PathValue("id")
	if slug == "" {
		slug = r.URL.Query().Get("slug")
	}
	if slug == "" {
		http.Error(w, `{"error":"tenant id or slug is required"}`, http.StatusBadRequest)
		return
	}

	existing, err := h.fsRepo.GetTenantProfile(r.Context(), slug)
	if err != nil || existing == nil {
		existing, err = h.fsRepo.GetTenantProfileBySlug(r.Context(), slug)
	}
	if err != nil || existing == nil {
		http.Error(w, fmt.Sprintf(`{"error":"tenant company '%s' not found"}`, slug), http.StatusNotFound)
		return
	}

	var req domain.UpdateTenantRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, `{"error":"invalid request payload"}`, http.StatusBadRequest)
		return
	}

	if strings.TrimSpace(req.DisplayName) != "" {
		existing.DisplayName = strings.TrimSpace(req.DisplayName)
	}
	if strings.TrimSpace(req.BrandSeedColor) != "" {
		existing.BrandSeedColor = strings.TrimSpace(req.BrandSeedColor)
	}
	if strings.TrimSpace(req.AdminEmail) != "" {
		existing.AdminEmail = strings.TrimSpace(req.AdminEmail)
	}
	if strings.TrimSpace(req.LogoURL) != "" {
		existing.LogoURL = strings.TrimSpace(req.LogoURL)
	}
	if req.ActiveChains != nil {
		existing.ActiveChains = req.ActiveChains
	}

	if err := h.fsRepo.SaveTenantProfile(r.Context(), existing); err != nil {
		http.Error(w, `{"error":"failed to update tenant profile"}`, http.StatusInternalServerError)
		return
	}

	claims, _ := middleware.GetUserClaims(r.Context())
	adminEmail := "super-admin"
	if claims != nil && claims.Email != "" {
		adminEmail = claims.Email
	}
	_ = h.fsRepo.SaveAuditLog(r.Context(), &domain.AuditLogEntry{
		LogID:     "log-" + uuid.New().String()[:8],
		TenantID:  normalizeAuditTenantID(existing.TenantID),
		UserID:    "admin",
		UserEmail: adminEmail,
		UserRole:  "super_admin",
		Action:    "TENANT_UPDATE",
		Resource:  "admin/tenants/" + existing.Slug,
		Details:   fmt.Sprintf("تعديل بيانات الشركة الموردة: %s (%s)", existing.DisplayName, existing.Slug),
		IPAddress: extractRequestIP(r),
		Status:    "SUCCESS",
		CreatedAt: time.Now(),
	})

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	_ = json.NewEncoder(w).Encode(existing)
}

// HandleDeleteTenant serves DELETE /api/v1/admin/tenants/{id}.
func (h *AdminHandler) HandleDeleteTenant(w http.ResponseWriter, r *http.Request) {
	if !h.checkSuperAdminAccess(r) {
		http.Error(w, `{"error":"forbidden: super admin access required"}`, http.StatusForbidden)
		return
	}

	slug := r.PathValue("id")
	if slug == "" {
		slug = r.URL.Query().Get("slug")
	}
	if slug == "" {
		http.Error(w, `{"error":"tenant id or slug is required"}`, http.StatusBadRequest)
		return
	}

	existing, err := h.fsRepo.GetTenantProfile(r.Context(), slug)
	if err != nil || existing == nil {
		existing, err = h.fsRepo.GetTenantProfileBySlug(r.Context(), slug)
	}
	if err != nil || existing == nil {
		http.Error(w, fmt.Sprintf(`{"error":"tenant company '%s' not found"}`, slug), http.StatusNotFound)
		return
	}

	if err := h.fsRepo.DeleteTenantProfile(r.Context(), existing.Slug); err != nil {
		http.Error(w, `{"error":"failed to delete tenant profile"}`, http.StatusInternalServerError)
		return
	}

	claims, _ := middleware.GetUserClaims(r.Context())
	adminEmail := "super-admin"
	if claims != nil && claims.Email != "" {
		adminEmail = claims.Email
	}
	_ = h.fsRepo.SaveAuditLog(r.Context(), &domain.AuditLogEntry{
		LogID:     "log-" + uuid.New().String()[:8],
		TenantID:  "system",
		UserID:    "admin",
		UserEmail: adminEmail,
		UserRole:  "super_admin",
		Action:    "TENANT_DELETE",
		Resource:  "admin/tenants/" + existing.Slug,
		Details:   fmt.Sprintf("حذف بوابة الشركة نهائياً من المنصة: %s (%s)", existing.DisplayName, existing.Slug),
		IPAddress: extractRequestIP(r),
		Status:    "SUCCESS",
		CreatedAt: time.Now(),
	})

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	_ = json.NewEncoder(w).Encode(map[string]interface{}{
		"status":  "deleted",
		"slug":    existing.Slug,
		"message": "تم حذف الشركة وإيقاف بوابتها بنجاح",
	})
}

