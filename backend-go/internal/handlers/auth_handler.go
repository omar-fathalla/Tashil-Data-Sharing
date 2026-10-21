package handlers

import (
	"encoding/json"
	"fmt"
	"net/http"
	"time"

	"github.com/tashil/data-sharing/backend/internal/domain"
	"github.com/tashil/data-sharing/backend/internal/middleware"
	"github.com/tashil/data-sharing/backend/internal/security"
	"github.com/tashil/data-sharing/backend/internal/service/firestore"
)

// AuthHandler coordinates authentication and password recovery endpoints.
type AuthHandler struct {
	fsRepo firestore.Repository
	authMW *middleware.AuthMiddleware
}

// NewAuthHandler constructs an AuthHandler.
func NewAuthHandler(fsRepo firestore.Repository, authMW *middleware.AuthMiddleware) *AuthHandler {
	return &AuthHandler{
		fsRepo: fsRepo,
		authMW: authMW,
	}
}

// HandleLogin serves POST /api/v1/auth/login.
func (h *AuthHandler) HandleLogin(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, `{"error":"method not allowed"}`, http.StatusMethodNotAllowed)
		return
	}

	var req domain.LoginRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, `{"error":"invalid request body"}`, http.StatusBadRequest)
		return
	}

	if req.Email == "" || req.Password == "" {
		http.Error(w, `{"error":"email and password are required"}`, http.StatusBadRequest)
		return
	}

	user, err := h.fsRepo.GetUserByEmail(r.Context(), req.TenantID, req.Email)
	if err != nil {
		http.Error(w, `{"error":"invalid credentials or unassigned company"}`, http.StatusUnauthorized)
		return
	}

	if !user.Active {
		http.Error(w, `{"error":"account is deactivated"}`, http.StatusForbidden)
		return
	}

	if !security.CheckPassword(req.Password, user.PasswordHash) {
		http.Error(w, `{"error":"invalid credentials"}`, http.StatusUnauthorized)
		return
	}

	// Update last login
	now := time.Now()
	user.LastLogin = now
	_ = h.fsRepo.SaveUser(r.Context(), user)

	// Record enterprise audit log for successful login
	_ = h.fsRepo.SaveAuditLog(r.Context(), &domain.AuditLogEntry{
		TenantID:  normalizeAuditTenantID(user.TenantID),
		UserID:    user.UserID,
		UserEmail: user.Email,
		UserRole:  string(user.Role),
		Action:    "AUTH_LOGIN",
		Resource:  "auth/login",
		Details:   fmt.Sprintf("تسجيل دخول ناجح للمستخدم %s (%s)", user.FullName, user.Email),
		IPAddress: extractRequestIP(r),
		Status:    "SUCCESS",
		CreatedAt: now,
	})

	// Fetch tenant profile (or system profile for Super Admin)
	var tenantProfile domain.TenantProfile
	if user.Role == domain.RoleSuperAdmin {
		tenantProfile = domain.TenantProfile{
			TenantID:       "system",
			DisplayName:    "لوحة الإدارة العليا (Super Admin)",
			Slug:           "admin",
			PortalURL:      "http://localhost:3000/admin",
			BrandSeedColor: "#0F172A",
			AdminEmail:     user.Email,
			ActiveChains:   []string{"carrefour", "fathalla", "gomla", "spinneys"},
			CreatedAt:      user.CreatedAt,
		}
	} else {
		tp, err := h.fsRepo.GetTenantProfile(r.Context(), user.TenantID)
		if err == nil && tp != nil {
			tenantProfile = *tp
		} else {
			tenantProfile = domain.TenantProfile{
				TenantID:       user.TenantID,
				DisplayName:    user.FullName,
				Slug:           user.TenantID,
				PortalURL:      "http://localhost:3000/portal/" + user.TenantID,
				BrandSeedColor: "#1E3A8A",
				AdminEmail:     user.Email,
			}
		}
	}

	// Issue JWT token with claims
	tokenStr, err := h.authMW.GenerateToken(domain.UserClaims{
		UserID:         user.UserID,
		TenantID:       user.TenantID,
		Email:          user.Email,
		Role:           user.Role,
		Name:           user.FullName,
		RoleDisplayAr:  user.RoleDisplayAr,
		AssignedChain:  user.AssignedChain,
		AssignedRegion: user.AssignedRegion,
	}, 24*time.Hour)

	if err != nil {
		http.Error(w, `{"error":"failed to generate access token"}`, http.StatusInternalServerError)
		return
	}

	resp := domain.LoginResponse{
		Token:  tokenStr,
		User:   *user,
		Tenant: tenantProfile,
	}

	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(resp)
}

// HandleForgotPassword serves POST /api/v1/auth/forgot-password.
func (h *AuthHandler) HandleForgotPassword(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, `{"error":"method not allowed"}`, http.StatusMethodNotAllowed)
		return
	}

	var req domain.ForgotPasswordRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, `{"error":"invalid request body"}`, http.StatusBadRequest)
		return
	}

	if req.Email == "" {
		http.Error(w, `{"error":"email is required"}`, http.StatusBadRequest)
		return
	}

	user, err := h.fsRepo.GetUserByEmail(r.Context(), req.TenantID, req.Email)
	if err != nil {
		// Secure response: do not reveal whether user exists or not, but return success
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(domain.ForgotPasswordResponse{
			Message: "إذا كان البريد مسجلاً، فسيتم إرسال رابط استعادة كلمة المرور",
		})
		return
	}

	resetToken := security.GenerateResetToken()
	expiry := time.Now().Add(1 * time.Hour)

	if err := h.fsRepo.SetUserResetToken(r.Context(), user.UserID, resetToken, expiry); err != nil {
		http.Error(w, `{"error":"failed to generate reset token"}`, http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(domain.ForgotPasswordResponse{
		Message:    "تم توليد رمز استعادة كلمة المرور بنجاح",
		ResetToken: resetToken,
	})
}

// HandleResetPassword serves POST /api/v1/auth/reset-password.
func (h *AuthHandler) HandleResetPassword(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, `{"error":"method not allowed"}`, http.StatusMethodNotAllowed)
		return
	}

	var req domain.ResetPasswordRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, `{"error":"invalid request body"}`, http.StatusBadRequest)
		return
	}

	if req.Token == "" || req.NewPassword == "" {
		http.Error(w, `{"error":"token and new_password are required"}`, http.StatusBadRequest)
		return
	}

	if len(req.NewPassword) < 8 {
		http.Error(w, `{"error":"password must be at least 8 characters long"}`, http.StatusBadRequest)
		return
	}

	user, err := h.fsRepo.GetUserByResetToken(r.Context(), req.Token)
	if err != nil {
		http.Error(w, `{"error":"invalid or expired reset token"}`, http.StatusBadRequest)
		return
	}

	hash, err := security.HashPassword(req.NewPassword)
	if err != nil {
		http.Error(w, `{"error":"failed to process password"}`, http.StatusInternalServerError)
		return
	}

	if err := h.fsRepo.UpdateUserPassword(r.Context(), user.UserID, hash); err != nil {
		http.Error(w, `{"error":"failed to update password"}`, http.StatusInternalServerError)
		return
	}

	_ = h.fsRepo.SaveAuditLog(r.Context(), &domain.AuditLogEntry{
		TenantID:  normalizeAuditTenantID(user.TenantID),
		UserID:    user.UserID,
		UserEmail: user.Email,
		UserRole:  string(user.Role),
		Action:    "PASSWORD_RESET",
		Resource:  "auth/reset-password",
		Details:   fmt.Sprintf("استعادة وتحديث كلمة المرور للمستخدم %s", user.Email),
		IPAddress: extractRequestIP(r),
		Status:    "SUCCESS",
		CreatedAt: time.Now(),
	})

	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(domain.ResetPasswordResponse{
		Message: "تم تحديث كلمة المرور بنجاح، يمكنك الآن تسجيل الدخول",
	})
}

// HandleChangePassword serves POST /api/v1/auth/change-password.
func (h *AuthHandler) HandleChangePassword(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, `{"error":"method not allowed"}`, http.StatusMethodNotAllowed)
		return
	}

	claims, ok := middleware.GetUserClaims(r.Context())
	if !ok || claims == nil {
		http.Error(w, `{"error":"unauthorized"}`, http.StatusUnauthorized)
		return
	}

	var req domain.ChangePasswordRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, `{"error":"invalid request body"}`, http.StatusBadRequest)
		return
	}

	if req.OldPassword == "" || req.NewPassword == "" {
		http.Error(w, `{"error":"old_password and new_password are required"}`, http.StatusBadRequest)
		return
	}

	if len(req.NewPassword) < 8 {
		http.Error(w, `{"error":"new password must be at least 8 characters long"}`, http.StatusBadRequest)
		return
	}

	user, err := h.fsRepo.GetUserByID(r.Context(), claims.UserID)
	if err != nil {
		http.Error(w, `{"error":"user not found"}`, http.StatusNotFound)
		return
	}

	if !security.CheckPassword(req.OldPassword, user.PasswordHash) {
		http.Error(w, `{"error":"كلمة المرور الحالية غير صحيحة"}`, http.StatusBadRequest)
		return
	}

	newHash, err := security.HashPassword(req.NewPassword)
	if err != nil {
		http.Error(w, `{"error":"failed to process new password"}`, http.StatusInternalServerError)
		return
	}

	if err := h.fsRepo.UpdateUserPassword(r.Context(), user.UserID, newHash); err != nil {
		http.Error(w, `{"error":"failed to update password"}`, http.StatusInternalServerError)
		return
	}

	_ = h.fsRepo.SaveAuditLog(r.Context(), &domain.AuditLogEntry{
		TenantID:  normalizeAuditTenantID(user.TenantID),
		UserID:    user.UserID,
		UserEmail: user.Email,
		UserRole:  string(user.Role),
		Action:    "PASSWORD_CHANGE",
		Resource:  "auth/change-password",
		Details:   fmt.Sprintf("تغيير كلمة المرور للمستخدم %s", user.Email),
		IPAddress: extractRequestIP(r),
		Status:    "SUCCESS",
		CreatedAt: time.Now(),
	})

	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(domain.ChangePasswordResponse{
		Message: "تم تعديل كلمة المرور بنجاح",
	})
}
