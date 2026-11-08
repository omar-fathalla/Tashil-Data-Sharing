package matcher

import (
	"context"
	"fmt"
	"sort"
	"strings"
	"sync"
	"time"
)

// StoreTimeout bounds every store call against Firestore (or the memory fake).
const StoreTimeout = 8 * time.Second

// MetricsDelta is a set of counter increments applied atomically with an enqueue/decide.
type MetricsDelta struct {
	TotalMatched int64
	Exact        int64
	High         int64
	Uncertain    int64
	None         int64
	AutoResolved int64
	Queued       int64
	Pending      int64
	Approved     int64
	Rejected     int64
}

// EnqueueOp is one match attempt in a batched enqueue.
type EnqueueOp struct {
	ItemID      string
	Query       Query
	Result      Result
	NeedsReview bool
	Delta       MetricsDelta
}

// DecidePatch is the transactional approve/reject payload (status must be pending when applied).
type DecidePatch struct {
	ID             string
	Status         string
	DecidedBy      string
	ReasonAR       string
	ChosenItemCode string
	ChosenBarcode  string
	Now            time.Time
}

// Store persists one document per review item plus a tenant metrics doc.
// Implementations must make DecideItem and EnqueueBatch race-safe (transaction / single lock).
type Store interface {
	ListItems(ctx context.Context, tenantID, status string) ([]ReviewItem, error)
	GetItem(ctx context.Context, tenantID, id string) (*ReviewItem, error)
	GetMetrics(ctx context.Context, tenantID string) (Metrics, error)
	EnqueueBatch(ctx context.Context, tenantID string, ops []EnqueueOp) ([]ReviewItem, error)
	DecideItem(ctx context.Context, tenantID string, patch DecidePatch) (*ReviewItem, error)
}

// MemoryStore is a race-safe in-process durable fake (mutex serializes batch/decide).
// A new Queue on the same MemoryStore simulates a Cloud Run restart.
type MemoryStore struct {
	mu      sync.Mutex
	items   map[string]map[string]ReviewItem // tenant -> id -> item
	metrics map[string]Metrics
}

// NormalizeTenantKey canonicalizes tenant IDs for document scoping (tenant-adeco → adeco).
func NormalizeTenantKey(tenantID string) string {
	return strings.TrimPrefix(strings.ToLower(strings.TrimSpace(tenantID)), "tenant-")
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

func (m *MemoryStore) ensureTenantLocked(key string) {
	if m.items == nil {
		m.items = map[string]map[string]ReviewItem{}
	}
	if m.metrics == nil {
		m.metrics = map[string]Metrics{}
	}
	if _, ok := m.items[key]; !ok {
		m.items[key] = map[string]ReviewItem{}
	}
	if _, ok := m.metrics[key]; !ok {
		m.metrics[key] = Metrics{TenantID: key}
	}
}

func (m *MemoryStore) ListItems(_ context.Context, tenantID, status string) ([]ReviewItem, error) {
	key := NormalizeTenantKey(tenantID)
	if key == "" {
		return nil, fmt.Errorf("tenant_id required")
	}
	m.mu.Lock()
	defer m.mu.Unlock()
	m.ensureTenantLocked(key)
	out := make([]ReviewItem, 0, len(m.items[key]))
	for _, it := range m.items[key] {
		if NormalizeTenantKey(it.TenantID) != "" && NormalizeTenantKey(it.TenantID) != key {
			continue
		}
		if status != "" && it.Status != status {
			continue
		}
		out = append(out, cloneItem(it))
	}
	sort.Slice(out, func(i, j int) bool {
		if out[i].CreatedAt.Equal(out[j].CreatedAt) {
			return out[i].ID < out[j].ID
		}
		return out[i].CreatedAt.After(out[j].CreatedAt)
	})
	return out, nil
}

func (m *MemoryStore) GetItem(_ context.Context, tenantID, id string) (*ReviewItem, error) {
	key := NormalizeTenantKey(tenantID)
	if key == "" || strings.TrimSpace(id) == "" {
		return nil, fmt.Errorf("tenant_id and id required")
	}
	m.mu.Lock()
	defer m.mu.Unlock()
	m.ensureTenantLocked(key)
	it, ok := m.items[key][id]
	if !ok {
		return nil, nil
	}
	if NormalizeTenantKey(it.TenantID) != "" && NormalizeTenantKey(it.TenantID) != key {
		return nil, ErrTenantMismatch
	}
	cp := cloneItem(it)
	return &cp, nil
}

func (m *MemoryStore) GetMetrics(_ context.Context, tenantID string) (Metrics, error) {
	key := NormalizeTenantKey(tenantID)
	if key == "" {
		return Metrics{}, fmt.Errorf("tenant_id required")
	}
	m.mu.Lock()
	defer m.mu.Unlock()
	m.ensureTenantLocked(key)
	out := m.metrics[key]
	out.TenantID = key
	return out, nil
}

func (m *MemoryStore) EnqueueBatch(_ context.Context, tenantID string, ops []EnqueueOp) ([]ReviewItem, error) {
	key := NormalizeTenantKey(tenantID)
	if key == "" {
		return nil, fmt.Errorf("tenant_id required")
	}
	m.mu.Lock()
	defer m.mu.Unlock()
	m.ensureTenantLocked(key)
	out := make([]ReviewItem, 0)
	var delta MetricsDelta
	now := time.Now().UTC()
	for _, op := range ops {
		d := op.Delta
		if !op.NeedsReview {
			delta = addDelta(delta, d)
			continue
		}
		id := strings.TrimSpace(op.ItemID)
		if id == "" {
			delta = addDelta(delta, d)
			continue
		}
		if existing, ok := m.items[key][id]; ok && existing.Status == StatusPending {
			// Refresh — do not bump Queued/Pending again.
			d.Queued, d.Pending = 0, 0
			delta = addDelta(delta, d)
			existing.Query = op.Query
			existing.Result = op.Result
			existing.CreatedAt = now
			existing.TenantID = key
			m.items[key][id] = existing
			out = append(out, cloneItem(existing))
			continue
		}
		if existing, ok := m.items[key][id]; ok && existing.Status != StatusPending {
			// Already decided — do not overwrite; still count the match attempt.
			d.Queued, d.Pending = 0, 0
			delta = addDelta(delta, d)
			continue
		}
		delta = addDelta(delta, d)
		item := ReviewItem{
			ID: id, TenantID: key, Status: StatusPending,
			Query: op.Query, Result: op.Result, CreatedAt: now,
		}
		m.items[key][id] = item
		out = append(out, cloneItem(item))
	}
	m.metrics[key] = applyDelta(m.metrics[key], key, delta, now)
	return out, nil
}

func (m *MemoryStore) DecideItem(_ context.Context, tenantID string, patch DecidePatch) (*ReviewItem, error) {
	key := NormalizeTenantKey(tenantID)
	if key == "" || strings.TrimSpace(patch.ID) == "" {
		return nil, fmt.Errorf("tenant_id and id required")
	}
	m.mu.Lock()
	defer m.mu.Unlock()
	m.ensureTenantLocked(key)
	it, ok := m.items[key][patch.ID]
	if !ok {
		return nil, ErrNotFound
	}
	if NormalizeTenantKey(it.TenantID) != "" && NormalizeTenantKey(it.TenantID) != key {
		return nil, ErrTenantMismatch
	}
	if it.Status == StatusApproved || it.Status == StatusRejected {
		if it.Status == patch.Status {
			cp := cloneItem(it)
			return &cp, nil
		}
		return nil, ErrAlreadyDecided
	}
	if it.Status != StatusPending {
		return nil, fmt.Errorf("unexpected status %s", it.Status)
	}
	now := patch.Now
	if now.IsZero() {
		now = time.Now().UTC()
	}
	it.Status = patch.Status
	it.DecidedBy = patch.DecidedBy
	it.DecisionReasonAR = patch.ReasonAR
	it.ChosenItemCode = patch.ChosenItemCode
	it.ChosenBarcode = patch.ChosenBarcode
	it.DecidedAt = &now
	it.TenantID = key
	m.items[key][patch.ID] = it

	d := MetricsDelta{Pending: -1}
	if patch.Status == StatusApproved {
		d.Approved = 1
	} else {
		d.Rejected = 1
	}
	m.metrics[key] = applyDelta(m.metrics[key], key, d, now)
	cp := cloneItem(it)
	return &cp, nil
}

func addDelta(a, b MetricsDelta) MetricsDelta {
	return MetricsDelta{
		TotalMatched: a.TotalMatched + b.TotalMatched,
		Exact:        a.Exact + b.Exact,
		High:         a.High + b.High,
		Uncertain:    a.Uncertain + b.Uncertain,
		None:         a.None + b.None,
		AutoResolved: a.AutoResolved + b.AutoResolved,
		Queued:       a.Queued + b.Queued,
		Pending:      a.Pending + b.Pending,
		Approved:     a.Approved + b.Approved,
		Rejected:     a.Rejected + b.Rejected,
	}
}

func applyDelta(m Metrics, tenant string, d MetricsDelta, now time.Time) Metrics {
	m.TenantID = tenant
	m.TotalMatched += int(d.TotalMatched)
	m.Exact += int(d.Exact)
	m.High += int(d.High)
	m.Uncertain += int(d.Uncertain)
	m.None += int(d.None)
	m.AutoResolved += int(d.AutoResolved)
	m.Queued += int(d.Queued)
	m.Pending += int(d.Pending)
	if m.Pending < 0 {
		m.Pending = 0
	}
	m.Approved += int(d.Approved)
	m.Rejected += int(d.Rejected)
	m.UpdatedAt = now
	return m
}

func cloneItem(it ReviewItem) ReviewItem {
	cp := it
	if it.DecidedAt != nil {
		t := *it.DecidedAt
		cp.DecidedAt = &t
	}
	if len(it.Result.Candidates) > 0 {
		cp.Result.Candidates = append([]Candidate(nil), it.Result.Candidates...)
	}
	return cp
}
