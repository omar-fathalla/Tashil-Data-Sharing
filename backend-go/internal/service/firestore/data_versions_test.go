package firestore

import (
	"context"
	"testing"
)

func TestDataVersionMockBumpAndTenantAliases(t *testing.T) {
	c := NewClient("db", true)
	ctx := context.Background()
	if v, err := c.GetDataVersion(ctx, "tenant-adeco", "sell_in"); err != nil || v != "" {
		t.Fatalf("want empty, got %q %v", v, err)
	}
	v1, err := c.BumpDataVersion(ctx, "tenant-adeco", "sell_in")
	if err != nil || v1 == "" {
		t.Fatalf("bump: %q %v", v1, err)
	}
	if got, _ := c.GetDataVersion(ctx, "adeco", "sell_in"); got != v1 {
		t.Fatalf("alias lookup: %q != %q", got, v1)
	}
	if got, _ := c.GetDataVersion(ctx, "adeco", "sell_out"); got != "" {
		t.Fatalf("kinds must be independent, got %q", got)
	}
	v2, _ := c.BumpDataVersion(ctx, "adeco", "sell_in")
	if v2 == v1 {
		t.Fatal("bump must change the version")
	}
}
