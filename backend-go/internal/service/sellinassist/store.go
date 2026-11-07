package sellinassist

import (
	"fmt"
	"sort"
	"sync"
	"time"

	"github.com/google/uuid"
)

// Store holds suggestions in memory only. Approvals never mutate production data.
type Store struct {
	mu   sync.RWMutex
	byID map[string]*Suggestion
}

// NewStore returns an empty in-memory suggestion store.
func NewStore() *Store {
	return &Store{byID: make(map[string]*Suggestion)}
}

func (s *Store) put(sug *Suggestion) *Suggestion {
	if sug.ID == "" {
		sug.ID = uuid.NewString()
	}
	if sug.Status == "" {
		sug.Status = StatusPending
	}
	if sug.CreatedAt.IsZero() {
		sug.CreatedAt = time.Now().UTC()
	}
	cp := *sug
	if sug.Columns != nil {
		cp.Columns = append([]ColumnRole(nil), sug.Columns...)
	}
	if sug.SampleCustomers != nil {
		cp.SampleCustomers = append([]string(nil), sug.SampleCustomers...)
	}
	if sug.MissingRoles != nil {
		cp.MissingRoles = append([]string(nil), sug.MissingRoles...)
	}
	s.mu.Lock()
	s.byID[cp.ID] = &cp
	s.mu.Unlock()
	out := cp
	return &out
}

func (s *Store) get(id string) (*Suggestion, bool) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	v, ok := s.byID[id]
	if !ok {
		return nil, false
	}
	cp := *v
	return &cp, true
}

func (s *Store) list(tenantID, status string) []Suggestion {
	s.mu.RLock()
	defer s.mu.RUnlock()
	out := make([]Suggestion, 0)
	for _, v := range s.byID {
		if tenantID != "" && v.TenantID != tenantID {
			continue
		}
		if status != "" && v.Status != status {
			continue
		}
		out = append(out, *v)
	}
	sort.Slice(out, func(i, j int) bool {
		return out[i].CreatedAt.After(out[j].CreatedAt)
	})
	return out
}

func (s *Store) decide(id, status, actor string) (*Suggestion, error) {
	if status != StatusApproved && status != StatusRejected {
		return nil, fmt.Errorf("الحالة لازم تكون approved أو rejected")
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	v, ok := s.byID[id]
	if !ok {
		return nil, fmt.Errorf("الاقتراح مش موجود")
	}
	if v.Status != StatusPending {
		return nil, fmt.Errorf("الاقتراح اتاخد عليه قرار قبل كده (%s)", v.Status)
	}
	now := time.Now().UTC()
	v.Status = status
	v.DecidedAt = &now
	v.DecidedBy = actor
	cp := *v
	return &cp, nil
}

func (s *Store) snapshotCounts() (pending, approved, rejected, layoutSug, layoutApp, chainSug, chainApp int) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	for _, v := range s.byID {
		switch v.Status {
		case StatusPending:
			pending++
		case StatusApproved:
			approved++
		case StatusRejected:
			rejected++
		}
		switch v.Kind {
		case KindLayout:
			layoutSug++
			if v.Status == StatusApproved {
				layoutApp++
			}
		case KindCustomerChain:
			chainSug++
			if v.Status == StatusApproved {
				chainApp++
			}
		}
	}
	return
}
