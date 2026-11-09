package gemini

import "context"

type mappingPlanTenantKey struct{}

// WithMappingPlanTenant scopes AnalyzeAndNormalize / plan-cache lookups to tenantID.
// Empty tenantID leaves the unscoped (legacy) namespace.
func WithMappingPlanTenant(ctx context.Context, tenantID string) context.Context {
	if ctx == nil {
		ctx = context.Background()
	}
	t := normalizeMappingTenant(tenantID)
	if t == "" {
		return ctx
	}
	return context.WithValue(ctx, mappingPlanTenantKey{}, t)
}

// MappingPlanTenantFromContext returns the normalized tenant for plan-cache scoping, or "".
func MappingPlanTenantFromContext(ctx context.Context) string {
	if ctx == nil {
		return ""
	}
	if v, ok := ctx.Value(mappingPlanTenantKey{}).(string); ok {
		return normalizeMappingTenant(v)
	}
	return ""
}
