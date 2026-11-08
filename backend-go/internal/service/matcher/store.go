package matcher

import (
	"context"
	"fmt"
	"strings"
	"sync"
	"time"
)

// StoreTimeout bounds every Get/Save against Firestore (or the memory fake).
const StoreTimeout = 8 * time.Second

// State is the persisted product-match review queue for one tenant.
type State struct {
	TenantID  string       `json:"tenant_id" firestore:"tenant_id"`
	Items     []ReviewItem `json:"items" firestore:"items"`
	Metrics   Metrics      `json:"metrics" firestore:"metrics"`
	UpdatedAt time.Time    `json:"updated_at" firestore:"updated_at"`
}

// Store persists the review queue (Firestore in production, MemoryStore in tests/mock).
type Store interface {
	GetProductMatchState(ctx context.Context, tenantID string) (*State, error)
	SaveProductMatchState(ctx context.Context, st *State) error
}

// MemoryStore is an in-process durable fake used by unit tests and mock Firestore.
// A new Queue pointing at the same MemoryStore simulates a Cloud Run restart.
type MemoryStore struct {
	mu sync.Mutex
	m  map[string]State
}

// NormalizeTenantKey canonicalizes tenant IDs for document scoping (tenant-adeco → adeco).
func NormalizeTenantKey(tenantID string) string {
	return strings.TrimPrefix(strings.ToLower(strings.TrimSpace(tenantID)), "tenant-")
}

func (m *MemoryStore) GetProductMatchState(_ context.Context, tenantID string) (*State, error) {
	key := NormalizeTenantKey(tenantID)
	if key == "" {
		return nil, fmt.Errorf("tenant_id required")
	}
	m.mu.Lock()
	defer m.mu.Unlock()
	st, ok := m.m[key]
	if !ok {
		return &State{TenantID: key, Items: nil, Metrics: Metrics{TenantID: key}}, nil
	}
	if st.TenantID != "" && NormalizeTenantKey(st.TenantID) != key {
		return nil, fmt.Errorf("tenant mismatch: store=%s request=%s", st.TenantID, key)
	}
	cp := cloneState(&st)
	cp.TenantID = key
	cp.Metrics.TenantID = key
	return cp, nil
}

func (m *MemoryStore) SaveProductMatchState(_ context.Context, st *State) error {
	if st == nil {
		return fmt.Errorf("state cannot be nil")
	}
	key := NormalizeTenantKey(st.TenantID)
	if key == "" {
		return fmt.Errorf("tenant_id required")
	}
	if st.TenantID != "" && NormalizeTenantKey(st.TenantID) != key {
		return fmt.Errorf("tenant mismatch on save")
	}
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.m == nil {
		m.m = map[string]State{}
	}
	cp := cloneState(st)
	cp.TenantID = key
	cp.Metrics.TenantID = key
	cp.UpdatedAt = time.Now().UTC()
	m.m[key] = *cp
	return nil
}

func cloneState(st *State) *State {
	if st == nil {
		return &State{}
	}
	cp := *st
	cp.Items = append([]ReviewItem(nil), st.Items...)
	for i := range cp.Items {
		if st.Items[i].DecidedAt != nil {
			t := *st.Items[i].DecidedAt
			cp.Items[i].DecidedAt = &t
		}
		if len(st.Items[i].Result.Candidates) > 0 {
			cp.Items[i].Result.Candidates = append([]Candidate(nil), st.Items[i].Result.Candidates...)
		}
	}
	cp.Metrics = st.Metrics
	cp.Metrics.LabelsAR = nil // derived at read time
	return &cp
}

func withStoreTimeout(parent context.Context) (context.Context, context.CancelFunc) {
	if parent == nil {
		parent = context.Background()
	}
	if _, ok := parent.Deadline(); ok {
		return context.WithCancel(parent)
	}
	return context.WithTimeout(parent, StoreTimeout)
}
