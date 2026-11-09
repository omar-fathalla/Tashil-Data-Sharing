package middleware

import (
	"context"
	"errors"
	"net/http"
	"strings"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"github.com/tashil/data-sharing/backend/internal/domain"
)

type contextKey string

const (
	UserClaimsContextKey contextKey = "userClaims"
	// VerifiedClaimsContextKey holds the token's claims before any X-Tenant-ID / X-Simulated-Role /
	// X-Assigned-* header adjustment. Use it for authorization decisions that must not trust headers.
	VerifiedClaimsContextKey contextKey = "verifiedUserClaims"
)

// CustomClaims matches the structure encoded into our JWTs.
type CustomClaims struct {
	UserID         string          `json:"user_id"`
	TenantID       string          `json:"tenant_id"`
	Email          string          `json:"email"`
	Role           domain.UserRole `json:"role"`
	Name           string          `json:"name"`
	RoleDisplayAr  string          `json:"role_display_ar,omitempty"`
	AssignedChain  string          `json:"assigned_chain,omitempty"`
	AssignedRegion string          `json:"assigned_region,omitempty"`
	jwt.RegisteredClaims
}

// AuthMiddleware validates JWT Bearer tokens and extracts tenant context.
type AuthMiddleware struct {
	jwtSecret       []byte
	allowDemoTokens bool
}

// NewAuthMiddleware constructs a new JWT authentication middleware.
func NewAuthMiddleware(secret string, allowDemoTokens bool) *AuthMiddleware {
	return &AuthMiddleware{
		jwtSecret:       []byte(secret),
		allowDemoTokens: allowDemoTokens,
	}
}

// Handler intercepts HTTP requests to validate JWT and set user context.
func (a *AuthMiddleware) Handler(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		// Health check and public routes bypass auth.
		// /livez and /api/v1/health are the Cloud Run-safe probes (/healthz is reserved by Google).
		if r.URL.Path == "/livez" || r.URL.Path == "/api/v1/health" ||
			r.URL.Path == "/healthz" || r.URL.Path == "/" ||
			r.URL.Path == "/api/v1/auth/login" ||
			r.URL.Path == "/api/v1/version" ||
			r.URL.Path == "/api/v1/auth/forgot-password" ||
			r.URL.Path == "/api/v1/auth/reset-password" ||
			strings.HasPrefix(r.URL.Path, "/api/v1/portal/") {
			next.ServeHTTP(w, r)
			return
		}

		authHeader := r.Header.Get("Authorization")
		tenantHeader := r.Header.Get("X-Tenant-ID")

		var claims *domain.UserClaims

		if authHeader != "" {
			tokenParts := strings.Split(authHeader, " ")
			if len(tokenParts) == 2 && strings.EqualFold(tokenParts[0], "bearer") {
				tokenStr := tokenParts[1]

				// Check for development/demo bypass token
				if a.allowDemoTokens && (tokenStr == "demo-superadmin-token" || tokenStr == "superadmin-jwt") {
					claims = &domain.UserClaims{
						UserID:        "user-super-admin",
						TenantID:      "system",
						Email:         "super-admin",
						Role:          domain.RoleSuperAdmin,
						Name:          "مدير عام منصة تسهيل",
						RoleDisplayAr: "مدير عام المنصة (Super Admin)",
					}
				} else if a.allowDemoTokens && (tokenStr == "demo-adeco-token" || tokenStr == "adeco-executive-jwt") {
					claims = &domain.UserClaims{
						UserID:        "user-adeco-admin-01",
						TenantID:      "tenant-adeco",
						Email:         "admin@adeco-retail.com",
						Role:          domain.RoleVendorAdmin,
						Name:          "مدير العمليات (أديكو)",
						RoleDisplayAr: "مدير الشركة الموردة",
					}
				} else if a.allowDemoTokens && strings.HasPrefix(tokenStr, "demo-") && strings.HasSuffix(tokenStr, "-token") {
					slug := strings.TrimSuffix(strings.TrimPrefix(tokenStr, "demo-"), "-token")
					slug = strings.TrimPrefix(strings.ToLower(strings.TrimSpace(slug)), "tenant-")
					if slug == "superadmin" || slug == "admin" || slug == "system" {
						claims = &domain.UserClaims{
							UserID:        "user-super-admin",
							TenantID:      "system",
							Email:         "super-admin",
							Role:          domain.RoleSuperAdmin,
							Name:          "مدير عام منصة تسهيل",
							RoleDisplayAr: "مدير عام المنصة (Super Admin)",
						}
					} else if slug != "" {
						claims = &domain.UserClaims{
							UserID:        "user-" + slug + "-admin-01",
							TenantID:      "tenant-" + slug,
							Email:         "admin@" + slug + "-retail.com",
							Role:          domain.RoleVendorAdmin,
							Name:          "مدير العمليات (" + slug + ")",
							RoleDisplayAr: "مدير الشركة الموردة",
						}
					}
				} else {
					parsedClaims, err := a.verifyToken(tokenStr)
					if err == nil {
						claims = parsedClaims
					}
				}
			}
		}

		// Fallback in demo/development mode: if no token provided, furnish tenant from X-Tenant-ID or default Adeco
		if claims == nil && a.allowDemoTokens {
			fallbackTenant := "tenant-adeco"
			fallbackSlug := "adeco"
			if tenantHeader != "" && !strings.EqualFold(tenantHeader, "system") {
				fallbackSlug = strings.TrimPrefix(strings.ToLower(strings.TrimSpace(tenantHeader)), "tenant-")
				if fallbackSlug != "" {
					fallbackTenant = "tenant-" + fallbackSlug
				}
			}
			claims = &domain.UserClaims{
				UserID:        "user-" + fallbackSlug + "-admin-01",
				TenantID:      fallbackTenant,
				Email:         "admin@" + fallbackSlug + "-retail.com",
				Role:          domain.RoleVendorAdmin,
				Name:          "مدير العمليات (" + fallbackSlug + ")",
				RoleDisplayAr: "مدير الشركة الموردة",
			}
		}

		if claims == nil {
			http.Error(w, `{"error":"unauthorized: valid JWT bearer token required"}`, http.StatusUnauthorized)
			return
		}

		verified := *claims

		// If client provided X-Tenant-ID switch header and user is Super Admin, allow context switch
		if tenantHeader != "" && claims.Role == domain.RoleSuperAdmin && !strings.EqualFold(tenantHeader, "system") {
			normHeader := strings.TrimPrefix(strings.ToLower(strings.TrimSpace(tenantHeader)), "tenant-")
			if normHeader != "" {
				claims.TenantID = "tenant-" + normHeader
			}
		}

		// Role / chain / region simulation headers are honoured only for a verified super admin or in
		// demo mode. For everyone else they are ignored, so a header can never widen access (a chain-A
		// user cannot read chain B, a merchandiser cannot act as vendor_admin).
		if verified.Role == domain.RoleSuperAdmin || a.allowDemoTokens {
			if simRole := strings.TrimSpace(r.Header.Get("X-Simulated-Role")); simRole != "" {
				claims.Role = domain.UserRole(simRole)
			}
			if simChain := strings.TrimSpace(r.Header.Get("X-Assigned-Chain")); simChain != "" {
				claims.AssignedChain = simChain
			}
			if simRegion := strings.TrimSpace(r.Header.Get("X-Assigned-Region")); simRegion != "" {
				claims.AssignedRegion = simRegion
			}
		}

		ctx := context.WithValue(r.Context(), UserClaimsContextKey, claims)
		ctx = context.WithValue(ctx, VerifiedClaimsContextKey, &verified)
		next.ServeHTTP(w, r.WithContext(ctx))
	})
}

func (a *AuthMiddleware) verifyToken(tokenStr string) (*domain.UserClaims, error) {
	token, err := jwt.ParseWithClaims(tokenStr, &CustomClaims{}, func(token *jwt.Token) (interface{}, error) {
		if _, ok := token.Method.(*jwt.SigningMethodHMAC); !ok {
			return nil, errors.New("unexpected signing method")
		}
		return a.jwtSecret, nil
	})

	if err != nil || !token.Valid {
		return nil, errors.New("invalid or expired token")
	}

	customClaims, ok := token.Claims.(*CustomClaims)
	if !ok {
		return nil, errors.New("cannot parse custom claims")
	}

	return &domain.UserClaims{
		UserID:         customClaims.UserID,
		TenantID:       customClaims.TenantID,
		Email:          customClaims.Email,
		Role:           customClaims.Role,
		Name:           customClaims.Name,
		RoleDisplayAr:  customClaims.RoleDisplayAr,
		AssignedChain:  customClaims.AssignedChain,
		AssignedRegion: customClaims.AssignedRegion,
	}, nil
}

// GenerateToken creates a signed JWT for testing or initial client login.
func (a *AuthMiddleware) GenerateToken(claims domain.UserClaims, duration time.Duration) (string, error) {
	jwtClaims := CustomClaims{
		UserID:         claims.UserID,
		TenantID:       claims.TenantID,
		Email:          claims.Email,
		Role:           claims.Role,
		Name:           claims.Name,
		RoleDisplayAr:  claims.RoleDisplayAr,
		AssignedChain:  claims.AssignedChain,
		AssignedRegion: claims.AssignedRegion,
		RegisteredClaims: jwt.RegisteredClaims{
			ExpiresAt: jwt.NewNumericDate(time.Now().Add(duration)),
			IssuedAt:  jwt.NewNumericDate(time.Now()),
			Subject:   claims.UserID,
		},
	}

	token := jwt.NewWithClaims(jwt.SigningMethodHS256, jwtClaims)
	return token.SignedString(a.jwtSecret)
}

// GetUserClaims retrieves the authenticated UserClaims from request context.
// GetVerifiedClaims returns the token claims before header-based role/tenant simulation.
func GetVerifiedClaims(ctx context.Context) (*domain.UserClaims, bool) {
	claims, ok := ctx.Value(VerifiedClaimsContextKey).(*domain.UserClaims)
	return claims, ok
}

// WriteClaims returns the claims every write gate must use: the token's own role, user and chain
// (never X-Simulated-Role / X-Assigned-*), with the tenant a super admin selected via X-Tenant-ID.
func WriteClaims(ctx context.Context) (*domain.UserClaims, bool) {
	v, ok := GetVerifiedClaims(ctx)
	if !ok || v == nil {
		// AuthMiddleware always stores verified claims; this only serves handler unit tests that
		// inject claims directly (no headers are applied there).
		return GetUserClaims(ctx)
	}
	out := *v
	if out.Role == domain.RoleSuperAdmin {
		if eff, ok := GetUserClaims(ctx); ok && eff != nil && strings.TrimSpace(eff.TenantID) != "" {
			out.TenantID = eff.TenantID
		}
	}
	return &out, true
}

func GetUserClaims(ctx context.Context) (*domain.UserClaims, bool) {
	claims, ok := ctx.Value(UserClaimsContextKey).(*domain.UserClaims)
	return claims, ok
}
