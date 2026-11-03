package domain

import "time"

// TenantUser represents an authenticated multi-tenant system user.
type TenantUser struct {
	UserID         string    `json:"user_id"`
	TenantID       string    `json:"tenant_id"` // 'system' for Super Admin, or tenant_id
	Email          string    `json:"email"`
	FullName       string    `json:"full_name"`
	PasswordHash   string    `json:"-"` // Omitted from JSON serialization
	Role           UserRole  `json:"role"`
	RoleDisplayAr  string    `json:"role_display_ar,omitempty"`
	AssignedChain  string    `json:"assigned_chain,omitempty"`
	AssignedRegion string    `json:"assigned_region,omitempty"`
	Active         bool      `json:"active"`
	ResetToken     string    `json:"-"`
	TokenExpiry    time.Time `json:"-"`
	CreatedAt      time.Time `json:"created_at"`
	LastLogin      time.Time `json:"last_login"`
}

// TenantProfile represents an enterprise tenant's branding and access configuration.
type TenantProfile struct {
	TenantID       string    `json:"tenant_id"`        // Permanent ID e.g. 'adeco'
	DisplayName    string    `json:"display_name"`     // 'شركة أديكو للصناعات الغذائية'
	Slug           string    `json:"slug"`             // 'adeco'
	PortalURL      string    `json:"portal_url"`       // 'http://localhost:3000/portal/adeco'
	BrandSeedColor string    `json:"brand_seed_color"` // Hex color code e.g. '#1E3A8A'
	LogoURL        string    `json:"logo_url"`
	AdminEmail     string    `json:"admin_email"`
	ActiveChains   []string  `json:"active_chains"`
	CreatedAt      time.Time `json:"created_at"`
}

// RetailChain represents a retail chain belonging to a specific tenant company.
type RetailChain struct {
	ChainID     string    `json:"chain_id"`            // e.g. "fathalla"
	TenantID    string    `json:"tenant_id,omitempty"` // e.g. "adeco"
	DisplayName string    `json:"display_name"`        // e.g. "أسواق فتح الله"
	Code        string    `json:"code"`                // e.g. "fathalla"
	ChainType   string    `json:"chain_type"`          // e.g. "wholesale", "hypermarket", "supermarket", "discount"
	StoreCount  int       `json:"store_count"`         // e.g. 34
	CreatedAt   time.Time `json:"created_at"`
	CreatedBy   string    `json:"created_by,omitempty"` // verified JWT email of the admin who registered it
}

// CreateRetailChainRequest contains fields to register a new tenant-scoped retail chain.
type CreateRetailChainRequest struct {
	TenantID    string `json:"tenant_id,omitempty"`
	DisplayName string `json:"display_name"`
	Code        string `json:"code"`
	ChainType   string `json:"chain_type"`
	StoreCount  int    `json:"store_count"`
}

// UpdateRetailChainRequest contains fields to update an existing tenant-scoped retail chain.
type UpdateRetailChainRequest struct {
	TenantID    string `json:"tenant_id,omitempty"`
	DisplayName string `json:"display_name"`
	ChainType   string `json:"chain_type"`
	StoreCount  int    `json:"store_count"`
}

// LoginRequest defines credentials provided during tenant login.
type LoginRequest struct {
	TenantID string `json:"tenant_id"`
	Email    string `json:"email"`
	Password string `json:"password"`
}

// LoginResponse returns the issued JWT token and user/tenant profile.
type LoginResponse struct {
	Token  string        `json:"token"`
	User   TenantUser    `json:"user"`
	Tenant TenantProfile `json:"tenant"`
}

// ForgotPasswordRequest initiates password recovery.
type ForgotPasswordRequest struct {
	TenantID string `json:"tenant_id"`
	Email    string `json:"email"`
}

// ForgotPasswordResponse confirms password reset request processing.
type ForgotPasswordResponse struct {
	Message    string `json:"message"`
	ResetToken string `json:"reset_token,omitempty"` // populated for testing/direct flow
}

// ResetPasswordRequest uses a reset token to update password.
type ResetPasswordRequest struct {
	Token       string `json:"token"`
	NewPassword string `json:"new_password"`
}

// ResetPasswordResponse acknowledges password reset completion.
type ResetPasswordResponse struct {
	Message string `json:"message"`
}

// ChangePasswordRequest allows authenticated users to update their password.
type ChangePasswordRequest struct {
	OldPassword string `json:"old_password"`
	NewPassword string `json:"new_password"`
}

// ChangePasswordResponse acknowledges authenticated password change.
type ChangePasswordResponse struct {
	Message string `json:"message"`
}

// CreateTenantRequest captures provisioning parameters for a new tenant company.
type CreateTenantRequest struct {
	DisplayName    string   `json:"display_name"`
	Slug           string   `json:"slug"`
	BrandSeedColor string   `json:"brand_seed_color"`
	AdminEmail     string   `json:"admin_email"`
	AdminName      string   `json:"admin_name,omitempty"`
	AdminPassword  string   `json:"admin_password,omitempty"`
	LogoURL        string   `json:"logo_url,omitempty"`
	ActiveChains   []string `json:"active_chains,omitempty"`
}

// CreateTenantResponse returns provisioned company details, portal URL, and initial credentials.
type CreateTenantResponse struct {
	Tenant            TenantProfile `json:"tenant"`
	AdminUser         TenantUser    `json:"admin_user"`
	TemporaryPassword string        `json:"temporary_password"`
	PortalURL         string        `json:"portal_url"`
	Message           string        `json:"message"`
}

// UpdateTenantRequest captures editable parameters for an existing tenant company.
type UpdateTenantRequest struct {
	DisplayName    string   `json:"display_name"`
	BrandSeedColor string   `json:"brand_seed_color"`
	AdminEmail     string   `json:"admin_email"`
	LogoURL        string   `json:"logo_url,omitempty"`
	ActiveChains   []string `json:"active_chains,omitempty"`
}


// AdminResetPasswordRequest allows Super Admin to force reset tenant admin credentials.
type AdminResetPasswordRequest struct {
	NewPassword string `json:"new_password,omitempty"`
}

// AdminResetPasswordResponse returns generated temporary credentials.
type AdminResetPasswordResponse struct {
	TenantID          string `json:"tenant_id"`
	AdminEmail        string `json:"admin_email"`
	TemporaryPassword string `json:"temporary_password"`
	Message           string `json:"message"`
}

// TenantMetaResponse serves tenant branding for dedicated portal routing.
type TenantMetaResponse struct {
	TenantID       string   `json:"tenant_id"`
	DisplayName    string   `json:"display_name"`
	Slug           string   `json:"slug"`
	PortalURL      string   `json:"portal_url"`
	BrandSeedColor string   `json:"brand_seed_color"`
	LogoURL        string   `json:"logo_url"`
	AdminEmail     string   `json:"admin_email"`
	ActiveChains   []string `json:"active_chains"`
}

// AuditLogEntry records an immutable security or operational audit event.
type AuditLogEntry struct {
	LogID     string    `json:"log_id"`
	TenantID  string    `json:"tenant_id"`
	UserID    string    `json:"user_id"`
	UserEmail string    `json:"user_email"`
	UserRole  string    `json:"user_role"`
	Action    string    `json:"action"`
	Resource  string    `json:"resource"`
	Details   string    `json:"details"`
	IPAddress string    `json:"ip_address"`
	Status    string    `json:"status"`
	CreatedAt time.Time `json:"created_at"`
}

// CreateAuditLogRequest defines the payload for recording a client-side audit action (e.g. EXPORT_EXCEL).
type CreateAuditLogRequest struct {
	Action   string `json:"action"`
	Resource string `json:"resource"`
	Details  string `json:"details"`
}
