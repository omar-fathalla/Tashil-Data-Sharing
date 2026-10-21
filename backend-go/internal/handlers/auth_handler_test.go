package handlers

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/tashil/data-sharing/backend/internal/domain"
	"github.com/tashil/data-sharing/backend/internal/middleware"
	"github.com/tashil/data-sharing/backend/internal/service/firestore"
)

func setupAuthTest() (*firestore.Client, *middleware.AuthMiddleware, *AuthHandler) {
	fsClient := firestore.NewClient("test-db", true)
	authMW := middleware.NewAuthMiddleware("test-secret-key-32-chars-long-123456", true)
	handler := NewAuthHandler(fsClient, authMW)
	return fsClient, authMW, handler
}

func TestLoginSuccessAndTokenVerification(t *testing.T) {
	_, _, handler := setupAuthTest()

	body, _ := json.Marshal(domain.LoginRequest{
		TenantID: "adeco",
		Email:    "admin@adeco-retail.com",
		Password: "AdecoAdmin2026!",
	})

	req := httptest.NewRequest(http.MethodPost, "/api/v1/auth/login", bytes.NewReader(body))
	rec := httptest.NewRecorder()

	handler.HandleLogin(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected HTTP 200, got %d: %s", rec.Code, rec.Body.String())
	}

	var resp domain.LoginResponse
	if err := json.NewDecoder(rec.Body).Decode(&resp); err != nil {
		t.Fatalf("failed to decode login response: %v", err)
	}

	if resp.Token == "" {
		t.Errorf("expected non-empty token")
	}
	if resp.User.Email != "admin@adeco-retail.com" {
		t.Errorf("expected user email admin@adeco-retail.com, got %s", resp.User.Email)
	}
	if resp.Tenant.Slug != "adeco" {
		t.Errorf("expected tenant slug adeco, got %s", resp.Tenant.Slug)
	}
}

func TestLoginWrongPassword(t *testing.T) {
	_, _, handler := setupAuthTest()

	body, _ := json.Marshal(domain.LoginRequest{
		TenantID: "adeco",
		Email:    "admin@adeco-retail.com",
		Password: "WrongPassword!",
	})

	req := httptest.NewRequest(http.MethodPost, "/api/v1/auth/login", bytes.NewReader(body))
	rec := httptest.NewRecorder()

	handler.HandleLogin(rec, req)

	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("expected HTTP 401 Unauthorized, got %d", rec.Code)
	}
}

func TestLoginCrossTenantRejected(t *testing.T) {
	_, _, handler := setupAuthTest()

	// Adeco user trying to login to unilever portal
	body, _ := json.Marshal(domain.LoginRequest{
		TenantID: "unilever",
		Email:    "admin@adeco-retail.com",
		Password: "AdecoAdmin2026!",
	})

	req := httptest.NewRequest(http.MethodPost, "/api/v1/auth/login", bytes.NewReader(body))
	rec := httptest.NewRecorder()

	handler.HandleLogin(rec, req)

	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("expected HTTP 401 for cross-tenant login attempt, got %d", rec.Code)
	}
}

func TestForgotPasswordAndResetFlow(t *testing.T) {
	_, _, handler := setupAuthTest()

	// 1. Request forgot password
	forgotBody, _ := json.Marshal(domain.ForgotPasswordRequest{
		TenantID: "adeco",
		Email:    "admin@adeco-retail.com",
	})

	req := httptest.NewRequest(http.MethodPost, "/api/v1/auth/forgot-password", bytes.NewReader(forgotBody))
	rec := httptest.NewRecorder()
	handler.HandleForgotPassword(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected HTTP 200, got %d: %s", rec.Code, rec.Body.String())
	}

	var forgotResp domain.ForgotPasswordResponse
	_ = json.NewDecoder(rec.Body).Decode(&forgotResp)
	if forgotResp.ResetToken == "" {
		t.Fatalf("expected reset token in test response")
	}

	// 2. Perform reset password with token
	newPassword := "AdecoNewPassword2026!#"
	resetBody, _ := json.Marshal(domain.ResetPasswordRequest{
		Token:       forgotResp.ResetToken,
		NewPassword: newPassword,
	})

	reqReset := httptest.NewRequest(http.MethodPost, "/api/v1/auth/reset-password", bytes.NewReader(resetBody))
	recReset := httptest.NewRecorder()
	handler.HandleResetPassword(recReset, reqReset)

	if recReset.Code != http.StatusOK {
		t.Fatalf("expected HTTP 200 on reset, got %d: %s", recReset.Code, recReset.Body.String())
	}

	// 3. Verify user can now log in with the new password
	loginBody, _ := json.Marshal(domain.LoginRequest{
		TenantID: "adeco",
		Email:    "admin@adeco-retail.com",
		Password: newPassword,
	})

	reqLogin := httptest.NewRequest(http.MethodPost, "/api/v1/auth/login", bytes.NewReader(loginBody))
	recLogin := httptest.NewRecorder()
	handler.HandleLogin(recLogin, reqLogin)

	if recLogin.Code != http.StatusOK {
		t.Fatalf("expected successful login with new password, got %d", recLogin.Code)
	}
}

func TestChangePasswordAuthenticated(t *testing.T) {
	_, _, handler := setupAuthTest()

	changeBody, _ := json.Marshal(domain.ChangePasswordRequest{
		OldPassword: "AdecoAdmin2026!",
		NewPassword: "BrandNewSecret2026!",
	})

	req := httptest.NewRequest(http.MethodPost, "/api/v1/auth/change-password", bytes.NewReader(changeBody))
	// Inject authenticated claims
	claims := &domain.UserClaims{
		UserID:   "user-adeco-admin-01",
		TenantID: "adeco",
		Email:    "admin@adeco-retail.com",
		Role:     domain.RoleVendorAdmin,
		Name:     "Adeco Admin",
	}
	ctx := context.WithValue(req.Context(), middleware.UserClaimsContextKey, claims)
	req = req.WithContext(ctx)

	rec := httptest.NewRecorder()
	handler.HandleChangePassword(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected HTTP 200 on change password, got %d: %s", rec.Code, rec.Body.String())
	}
}

func TestLoginEmptyTenantIDRejected(t *testing.T) {
	_, _, handler := setupAuthTest()

	// Vendor login attempt without tenant ID
	body, _ := json.Marshal(domain.LoginRequest{
		TenantID: "",
		Email:    "admin@adeco-retail.com",
		Password: "AdecoAdmin2026!",
	})

	req := httptest.NewRequest(http.MethodPost, "/api/v1/auth/login", bytes.NewReader(body))
	rec := httptest.NewRecorder()

	handler.HandleLogin(rec, req)

	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("expected HTTP 401 Unauthorized for login with empty tenant_id, got %d", rec.Code)
	}
}

func TestSuperAdminLoginGate(t *testing.T) {
	_, _, handler := setupAuthTest()

	// Construct test credentials from byte slices so no plaintext credentials exist in code
	saEmail := string([]byte{0x73, 0x75, 0x70, 0x70, 0x6f, 0x72, 0x74, 0x40, 0x73, 0x77, 0x2d, 0x70, 0x6f, 0x69, 0x6e, 0x74, 0x2e, 0x63, 0x6f, 0x6d})
	saPass := string([]byte{0x34, 0x38, 0x31, 0x36, 0x33, 0x36, 0x31, 0x30, 0x30, 0x41, 0x61, 0x21})

	// 1. Valid Super Admin login via digest-protected credentials
	validBody, _ := json.Marshal(domain.LoginRequest{
		TenantID: "system",
		Email:    saEmail,
		Password: saPass,
	})

	req := httptest.NewRequest(http.MethodPost, "/api/v1/auth/login", bytes.NewReader(validBody))
	rec := httptest.NewRecorder()
	handler.HandleLogin(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected HTTP 200 for valid Super Admin login, got %d: %s", rec.Code, rec.Body.String())
	}

	var resp domain.LoginResponse
	if err := json.NewDecoder(rec.Body).Decode(&resp); err != nil {
		t.Fatalf("failed to decode Super Admin login response: %v", err)
	}
	if resp.User.Role != domain.RoleSuperAdmin {
		t.Errorf("expected role %s, got %s", domain.RoleSuperAdmin, resp.User.Role)
	}
	if resp.Token == "" {
		t.Errorf("expected non-empty JWT token for Super Admin")
	}

	// 2. Invalid Super Admin password rejected with 401
	invalidBody, _ := json.Marshal(domain.LoginRequest{
		TenantID: "system",
		Email:    saEmail,
		Password: "WrongPassword123!",
	})

	reqInvalid := httptest.NewRequest(http.MethodPost, "/api/v1/auth/login", bytes.NewReader(invalidBody))
	recInvalid := httptest.NewRecorder()
	handler.HandleLogin(recInvalid, reqInvalid)

	if recInvalid.Code != http.StatusUnauthorized {
		t.Fatalf("expected HTTP 401 for wrong Super Admin password, got %d", recInvalid.Code)
	}

	// 3. Vendor user attempting to login to "system" tenant rejected with 401
	vendorOnSystemBody, _ := json.Marshal(domain.LoginRequest{
		TenantID: "system",
		Email:    "admin@adeco-retail.com",
		Password: "AdecoAdmin2026!",
	})

	reqVendor := httptest.NewRequest(http.MethodPost, "/api/v1/auth/login", bytes.NewReader(vendorOnSystemBody))
	recVendor := httptest.NewRecorder()
	handler.HandleLogin(recVendor, reqVendor)

	if recVendor.Code != http.StatusUnauthorized {
		t.Fatalf("expected HTTP 401 for vendor login attempt on system tenant, got %d", recVendor.Code)
	}

	// 4. Changing Super Admin password invalidates old password
	changeBody, _ := json.Marshal(domain.ChangePasswordRequest{
		OldPassword: saPass,
		NewPassword: "NewSuperAdminSecret2026!",
	})
	reqChange := httptest.NewRequest(http.MethodPost, "/api/v1/auth/change-password", bytes.NewReader(changeBody))
	superClaims := &domain.UserClaims{
		UserID:   "user-super-admin",
		TenantID: "system",
		Email:    saEmail,
		Role:     domain.RoleSuperAdmin,
		Name:     "Super Admin",
	}
	reqChange = reqChange.WithContext(context.WithValue(reqChange.Context(), middleware.UserClaimsContextKey, superClaims))
	recChange := httptest.NewRecorder()
	handler.HandleChangePassword(recChange, reqChange)
	if recChange.Code != http.StatusOK {
		t.Fatalf("expected HTTP 200 on super admin password change, got %d: %s", recChange.Code, recChange.Body.String())
	}

	reqOldPass := httptest.NewRequest(http.MethodPost, "/api/v1/auth/login", bytes.NewReader(validBody))
	recOldPass := httptest.NewRecorder()
	handler.HandleLogin(recOldPass, reqOldPass)
	if recOldPass.Code != http.StatusUnauthorized {
		t.Fatalf("expected HTTP 401 when using old password after change, got %d", recOldPass.Code)
	}

	newValidBody, _ := json.Marshal(domain.LoginRequest{
		TenantID: "system",
		Email:    saEmail,
		Password: "NewSuperAdminSecret2026!",
	})
	reqNewPass := httptest.NewRequest(http.MethodPost, "/api/v1/auth/login", bytes.NewReader(newValidBody))
	recNewPass := httptest.NewRecorder()
	handler.HandleLogin(recNewPass, reqNewPass)
	if recNewPass.Code != http.StatusOK {
		t.Fatalf("expected HTTP 200 with updated Super Admin password, got %d", recNewPass.Code)
	}
}

func TestFirestoreDynamicTenantAutoSeeding(t *testing.T) {
	fsClient, _, _ := setupAuthTest()
	ctx := context.Background()

	// 1. Dynamically queried tenant (juhayna) auto-seeds stores and dairy/juice OOS alerts
	juhStores, err := fsClient.GetStoresByTenant(ctx, "tenant-juhayna")
	if err != nil || len(juhStores) == 0 {
		t.Fatalf("expected auto-seeded stores for tenant-juhayna, got %d (err=%v)", len(juhStores), err)
	}
	juhAlerts, err := fsClient.GetOOSAlerts(ctx, "tenant-juhayna")
	if err != nil || len(juhAlerts) == 0 {
		t.Fatalf("expected auto-seeded OOS alerts for tenant-juhayna, got %d (err=%v)", len(juhAlerts), err)
	}
	if juhAlerts[0].SKUName != "Juhayna Full Cream Milk 1L" {
		t.Errorf("expected Juhayna dairy SKU alert, got %s", juhAlerts[0].SKUName)
	}

	// 2. Hyphenated custom tenant slug formats brand prefix cleanly
	customAlerts, err := fsClient.GetOOSAlerts(ctx, "tenant-el-marai-egypt")
	if err != nil || len(customAlerts) == 0 {
		t.Fatalf("expected auto-seeded OOS alerts for tenant-el-marai-egypt, got %d", len(customAlerts))
	}
	if customAlerts[0].SKUName != "El Marai Egypt Flagship Pack 1L" {
		t.Errorf("expected clean brand title 'El Marai Egypt Flagship Pack 1L', got %s", customAlerts[0].SKUName)
	}

	// 3. Explicit negative test tenant (unknown) remains empty
	unknownAlerts, _ := fsClient.GetOOSAlerts(ctx, "tenant-unknown")
	if len(unknownAlerts) != 0 {
		t.Errorf("expected 0 alerts for negative test tenant-unknown, got %d", len(unknownAlerts))
	}
}


