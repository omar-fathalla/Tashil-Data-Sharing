package bigquery

import (
	"context"
	"strings"
)

// BranchResolver is the query-time mapping layer over raw store/customer names.
// Implementations must leave facts untouched and only affect grouping/display.
type BranchResolver interface {
	ResolveForReport(ctx context.Context, tenantID, chainSlug, rawStoreName string) (code, display string)
}

// WithBranchResolver attaches an optional branch master mapping layer.
func (c *Client) WithBranchResolver(r BranchResolver) *Client {
	c.branchResolver = r
	return c
}

func (c *Client) mapBranch(ctx context.Context, tenantID, chain, raw string) (code, display string) {
	raw = strings.TrimSpace(raw)
	if raw == "" {
		return "", ""
	}
	if c == nil || c.branchResolver == nil {
		return raw, raw
	}
	code, display = c.branchResolver.ResolveForReport(ctx, tenantID, chain, raw)
	if code == "" {
		code = raw
	}
	if display == "" {
		display = raw
	}
	return code, display
}
