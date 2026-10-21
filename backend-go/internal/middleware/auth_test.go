package middleware

import (
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/tashil/data-sharing/backend/internal/domain"
)

func TestAuthMiddlewareValidToken(t *testing.T) {
	secret := "test-secret-key-12345678901234567890"
	authMW := NewAuthMiddleware(secret, true)

	claims := domain.UserClaims{
		UserID:   "usr_100",
		TenantID: "tenant-adeco",
		Email:    "test@adeco.com",
		Role:     domain.RoleExecutive,
		Name:     "Adeco Executive",
	}

	tokenStr, err := authMW.GenerateToken(claims, 1*time.Hour)
	if err != nil {
		t.Fatalf("failed to generate token: %v", err)
	}

	nextHandler := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		userClaims, ok := GetUserClaims(r.Context())
		if !ok || userClaims == nil {
			t.Errorf("expected user claims in context")
			return
		}
		if userClaims.TenantID != "tenant-adeco" {
			t.Errorf("expected tenant-adeco, got %s", userClaims.TenantID)
		}
		w.WriteHeader(http.StatusOK)
	})

	req := httptest.NewRequest("GET", "/api/v1/analytics/records", nil)
	req.Header.Set("Authorization", "Bearer "+tokenStr)
	rec := httptest.NewRecorder()

	authMW.Handler(nextHandler).ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Errorf("expected HTTP 200, got %d", rec.Code)
	}
}

func TestAuthMiddlewareDemoTokenBypass(t *testing.T) {
	secret := "test-secret"
	authMW := NewAuthMiddleware(secret, true)

	nextHandler := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		userClaims, ok := GetUserClaims(r.Context())
		if !ok || userClaims == nil {
			t.Errorf("expected user claims in context")
			return
		}
		if userClaims.TenantID != "tenant-adeco" {
			t.Errorf("expected default tenant-adeco, got %s", userClaims.TenantID)
		}
		w.WriteHeader(http.StatusOK)
	})

	req := httptest.NewRequest("GET", "/api/v1/analytics/records", nil)
	req.Header.Set("Authorization", "Bearer demo-adeco-token")
	rec := httptest.NewRecorder()

	authMW.Handler(nextHandler).ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Errorf("expected HTTP 200, got %d", rec.Code)
	}

	// Test demo-unilever-token maps to tenant-unilever
	unileverHandler := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		userClaims, ok := GetUserClaims(r.Context())
		if !ok || userClaims == nil {
			t.Errorf("expected user claims in context")
			return
		}
		if userClaims.TenantID != "tenant-unilever" {
			t.Errorf("expected tenant-unilever, got %s", userClaims.TenantID)
		}
		w.WriteHeader(http.StatusOK)
	})
	reqUnilever := httptest.NewRequest("GET", "/api/v1/analytics/records", nil)
	reqUnilever.Header.Set("Authorization", "Bearer demo-unilever-token")
	recUnilever := httptest.NewRecorder()
	authMW.Handler(unileverHandler).ServeHTTP(recUnilever, reqUnilever)
	if recUnilever.Code != http.StatusOK {
		t.Errorf("expected HTTP 200, got %d", recUnilever.Code)
	}

	// Test demo-superadmin-token with X-Tenant-ID switches context to target tenant
	superHandler := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		userClaims, ok := GetUserClaims(r.Context())
		if !ok || userClaims == nil {
			t.Errorf("expected user claims in context")
			return
		}
		if userClaims.Role != domain.RoleSuperAdmin {
			t.Errorf("expected RoleSuperAdmin, got %s", userClaims.Role)
		}
		if userClaims.TenantID != "tenant-pepsi" {
			t.Errorf("expected switched TenantID tenant-pepsi, got %s", userClaims.TenantID)
		}
		w.WriteHeader(http.StatusOK)
	})
	reqSuper := httptest.NewRequest("GET", "/api/v1/analytics/records", nil)
	reqSuper.Header.Set("Authorization", "Bearer demo-superadmin-token")
	reqSuper.Header.Set("X-Tenant-ID", "pepsi")
	recSuper := httptest.NewRecorder()
	authMW.Handler(superHandler).ServeHTTP(recSuper, reqSuper)
	if recSuper.Code != http.StatusOK {
		t.Errorf("expected HTTP 200, got %d", recSuper.Code)
	}
}

