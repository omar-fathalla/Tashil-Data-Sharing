package branchmaster

import (
	"context"
	"fmt"
	"strings"
	"sync"
)

// Store persists one State document per tenant.
type Store interface {
	GetBranchMaster(ctx context.Context, tenantID string) (*State, error)
	SaveBranchMaster(ctx context.Context, st *State) error
}

// MemoryStore is the in-process / test store.
type MemoryStore struct {
	mu sync.Mutex
	m  map[string]State
}

// NewMemoryStore returns an empty memory store.
func NewMemoryStore() *MemoryStore {
	return &MemoryStore{m: map[string]State{}}
}

func normalizeTenant(tenantID string) string {
	t := strings.ToLower(strings.TrimSpace(tenantID))
	return strings.TrimPrefix(t, "tenant-")
}

func (m *MemoryStore) GetBranchMaster(_ context.Context, tenantID string) (*State, error) {
	key := normalizeTenant(tenantID)
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.m == nil {
		m.m = map[string]State{}
	}
	s, ok := m.m[key]
	if !ok {
		return &State{TenantID: tenantID}, nil
	}
	cp := cloneState(s)
	cp.TenantID = tenantID
	return &cp, nil
}

func (m *MemoryStore) SaveBranchMaster(_ context.Context, st *State) error {
	if st == nil {
		return fmt.Errorf("branch master state cannot be nil")
	}
	key := normalizeTenant(st.TenantID)
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.m == nil {
		m.m = map[string]State{}
	}
	cp := cloneState(*st)
	cp.TenantID = key
	m.m[key] = cp
	return nil
}

func cloneState(s State) State {
	cp := s
	cp.Chains = append([]Chain(nil), s.Chains...)
	cp.Branches = append([]Branch(nil), s.Branches...)
	cp.Aliases = append([]Alias(nil), s.Aliases...)
	cp.Pending = append([]Pending(nil), s.Pending...)
	cp.Notices = append([]Notice(nil), s.Notices...)
	return cp
}
