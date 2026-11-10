package handlers

import (
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
	"sync"
	"time"

	"github.com/tashil/data-sharing/backend/internal/domain"
	"github.com/tashil/data-sharing/backend/internal/middleware"
	"github.com/tashil/data-sharing/backend/internal/security"
	"github.com/tashil/data-sharing/backend/internal/service/firestore"
)

// Generic forgot-password acknowledgement — identical for known and unknown emails
// so responses never enumerate accounts or leak reset tokens.
const forgotPasswordAckMessage = "إذا كان البريد مسجلاً، فسيتم إرسال رابط استعادة كلمة المرور"

const (
	authLoginRateLimitMsg  = "تم تجاوز عدد محاولات تسجيل الدخول. حاول مرة أخرى لاحقاً"
	authForgotRateLimitMsg = "تم تجاوز عدد طلبات استعادة كلمة المرور. حاول مرة أخرى لاحقاً"

	authLoginMaxAttempts  = 10
	authLoginWindow       = time.Minute
	authForgotMaxAttempts = 5
	authForgotWindow      = 15 * time.Minute
)

// AuthHandler coordinates authentication and password recovery endpoints.
// Rate-limit maps are in-memory only (acceptable while Cloud Run maxScale=1).
type AuthHandler struct {
	fsRepo firestore.Repository
	authMW *middleware.AuthMiddleware

	rateMu     sync.Mutex
	loginHits  map[string][]time.Time // failed logins only: IP|email → timestamps
	forgotHits map[string][]time.Time
}

// NewAuthHandler constructs an AuthHandler.
func NewAuthHandler(fsRepo firestore.Repository, authMW *middleware.AuthMiddleware) *AuthHandler {
	return &AuthHandler{
		fsRepo:     fsRepo,
		authMW:     authMW,
		loginHits:  make(map[string][]time.Time),
		forgotHits: make(map[string][]time.Time),
	}
}

// pruneRateLocked drops expired hits and returns the remaining count for key.
// Caller must hold h.rateMu.
func (h *AuthHandler) pruneRateLocked(bucket map[string][]time.Time, key string, window time.Duration) int {
	now := time.Now()
	cutoff := now.Add(-window)
	kept := bucket[key][:0]
	for _, t := range bucket[key] {
		if t.After(cutoff) {
			kept = append(kept, t)
		}
	}
	bucket[key] = kept
	return len(kept)
}

func (h *AuthHandler) isRateLimited(bucket map[string][]time.Time, key string, max int, window time.Duration) bool {
	h.rateMu.Lock()
	defer h.rateMu.Unlock()
	return h.pruneRateLocked(bucket, key, window) >= max
}

func (h *AuthHandler) recordRateHit(bucket map[string][]time.Time, key string, window time.Duration) {
	h.rateMu.Lock()
	defer h.rateMu.Unlock()
	_ = h.pruneRateLocked(bucket, key, window)
	bucket[key] = append(bucket[key], time.Now())
}

// allowRate records a hit unless the key is already at the limit (used for forgot-password).
func (h *AuthHandler) allowRate(bucket map[string][]time.Time, key string, max int, window time.Duration) bool {
	h.rateMu.Lock()
	defer h.rateMu.Unlock()
	if h.pruneRateLocked(bucket, key, window) >= max {
		return false
	}
	bucket[key] = append(bucket[key], time.Now())
	return true
}

// authRateKey uses extractRequestIP (X-Forwarded-For leftmost hop — Cloud Run/GFE
// and Firebase Hosting populate this with the client IP) plus a normalized email.
func authRateKey(r *http.Request, email string) string {
	ip := extractRequestIP(r)
	email = strings.ToLower(strings.TrimSpace(email))
	if email == "" {
		return ip
	}
	return ip + "|" + email
}

// HandleLogin serves POST /api/v1/auth/login.
func (h *AuthHandler) HandleLogin(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, `{"error":"method not allowed"}`, http.StatusMethodNotAllowed)
		return
	}

	// Refresh before credential check so peer password/Active changes converge
	// (single-instance stopgap still applies; see docs/DEPLOY.md).
	if err := h.fsRepo.EnsureAuthUsersFresh(r.Context()); err != nil {
		http.Error(w, `{"error":"authentication service unavailable"}`, http.StatusServiceUnavailable)
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

	rateKey := authRateKey(r, req.Email)
	if h.isRateLimited(h.loginHits, rateKey, authLoginMaxAttempts, authLoginWindow) {
		writeErr(w, http.StatusTooManyRequests, authLoginRateLimitMsg)
		return
	}

	recordLoginFailure := func() {
		h.recordRateHit(h.loginHits, rateKey, authLoginWindow)
	}

	user, err := h.fsRepo.GetUserByEmail(r.Context(), req.TenantID, req.Email)
	if err != nil {
		recordLoginFailure()
		http.Error(w, `{"error":"invalid credentials or unassigned company"}`, http.StatusUnauthorized)
		return
	}

	if !user.Active {
		recordLoginFailure()
		http.Error(w, `{"error":"account is deactivated"}`, http.StatusForbidden)
		return
	}

	if !security.CheckPassword(req.Password, user.PasswordHash) {
		recordLoginFailure()
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
// Always returns the same generic 200 body; never returns the reset token.
// Token is stored server-side for the reset-password endpoint (email OOB when wired).
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

	if !h.allowRate(h.forgotHits, authRateKey(r, req.Email), authForgotMaxAttempts, authForgotWindow) {
		writeErr(w, http.StatusTooManyRequests, authForgotRateLimitMsg)
		return
	}

	writeForgotAck := func() {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		_ = json.NewEncoder(w).Encode(domain.ForgotPasswordResponse{
			Message: forgotPasswordAckMessage,
		})
	}

	user, err := h.fsRepo.GetUserByEmail(r.Context(), req.TenantID, req.Email)
	if err != nil {
		writeForgotAck()
		return
	}

	resetToken := security.GenerateResetToken()
	expiry := time.Now().Add(1 * time.Hour)

	// Store server-side only. Deliver via email when an outbound mail channel exists;
	// never put the token in the HTTP response.
	if err := h.fsRepo.SetUserResetToken(r.Context(), user.UserID, resetToken, expiry); err != nil {
		// Do not reveal whether the account exists; still return the generic ack.
		writeForgotAck()
		return
	}

	writeForgotAck()
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
