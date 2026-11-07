package ingestion

import (
	"context"
	"errors"
	"testing"
)

func TestPurgeTenantDataRefusesWildcard(t *testing.T) {
	p := newTestProcessor(t, t.TempDir())
	for _, id := range []string{"all", "*", " ALL ", " * "} {
		err := p.PurgeTenantData(context.Background(), id)
		if !errors.Is(err, ErrWildcardPurgeRefused) {
			t.Fatalf("PurgeTenantData(%q) must refuse wildcard, got %v", id, err)
		}
	}
}

func TestPurgeAllTenantsAllowedExplicitly(t *testing.T) {
	p := newTestProcessor(t, t.TempDir())
	// No durable sink: memory-only wipe. Role enforcement lives in HandleClearData;
	// this asserts the service entrypoint for global wipe exists separately from PurgeTenantData.
	if err := p.PurgeAllTenants(context.Background()); err != nil {
		t.Fatalf("PurgeAllTenants: %v", err)
	}
}
