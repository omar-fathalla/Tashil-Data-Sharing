package bigquery

import (
	"context"
	"sync"
	"testing"
	"time"

	"github.com/tashil/data-sharing/backend/internal/domain"
)

// sharedStore stands in for Firestore shared by all Cloud Run instances.
type sharedStore struct {
	mu    sync.Mutex
	data  map[string][]domain.ChainDiscountProfile
	reads int
}

func (s *sharedStore) GetChainDiscountProfiles(_ context.Context, tenant string) (*domain.ChainDiscountProfiles, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.reads++
	return &domain.ChainDiscountProfiles{TenantID: tenant, Profiles: append([]domain.ChainDiscountProfile(nil), s.data[tenant]...)}, nil
}

func (s *sharedStore) save(tenant string, p []domain.ChainDiscountProfile) {
	s.mu.Lock()
	s.data[tenant] = p
	s.mu.Unlock()
}

// Two instances share one store: a save handled by instance A reaches instance B on its next
// read after the TTL, invalidating B's version; unchanged data never invalidates.
func TestChainDiscountsSyncAcrossInstances(t *testing.T) {
	store := &sharedStore{data: map[string][]domain.ChainDiscountProfile{}}
	const ttl = 50 * time.Millisecond
	a := (&Client{}).WithChainDiscountSource(store, ttl)
	b := (&Client{}).WithChainDiscountSource(store, ttl)
	ctx := context.Background()
	const tenant = "tenant-adeco"

	b.syncChainDiscounts(ctx, tenant)
	v0 := b.AnalyticsSourceVersion()
	if _, ok := b.chainDiscountProfile(normalizeTenantKey(tenant), "fathalla"); ok {
		t.Fatal("no profile expected yet")
	}

	// Instance A saves (handler path: Firestore write + local apply).
	prof := []domain.ChainDiscountProfile{{Chain: "Fathalla", InvoiceDiscountPct: 12, AdditionalDiscountPct: 5}}
	store.save(tenant, prof)
	a.SetChainDiscountProfiles(tenant, prof)

	// Within the TTL instance B does not re-read.
	reads := store.reads
	b.syncChainDiscounts(ctx, tenant)
	if store.reads != reads || b.AnalyticsSourceVersion() != v0 {
		t.Fatal("re-read inside TTL")
	}

	time.Sleep(ttl + 10*time.Millisecond)
	b.syncChainDiscounts(ctx, tenant)
	got, ok := b.chainDiscountProfile(normalizeTenantKey(tenant), "fathalla")
	if !ok || got.InvoiceDiscountPct != 12 || got.AdditionalDiscountPct != 5 {
		t.Fatalf("instance B not synced: %+v %v", got, ok)
	}
	v1 := b.AnalyticsSourceVersion()
	if v1 <= v0 {
		t.Fatal("sync must bump the version so cached results are recomputed")
	}

	// Unchanged data: re-read but no invalidation.
	time.Sleep(ttl + 10*time.Millisecond)
	b.syncChainDiscounts(ctx, tenant)
	if b.AnalyticsSourceVersion() != v1 {
		t.Fatal("unchanged profiles must not invalidate")
	}

	// Delete on A propagates too.
	store.save(tenant, nil)
	time.Sleep(ttl + 10*time.Millisecond)
	b.syncChainDiscounts(ctx, tenant)
	if _, ok := b.chainDiscountProfile(normalizeTenantKey(tenant), "fathalla"); ok {
		t.Fatal("deleted profile still applied on B")
	}
	if b.AnalyticsSourceVersion() <= v1 {
		t.Fatal("delete must bump the version")
	}
}
