package matcher

import (
	"context"
	"crypto/sha1"
	"encoding/hex"
	"errors"
	"fmt"
	"sort"
	"strings"
	"sync"
	"time"
)

// Review status values (Arabic labels live in the UI).
const (
	StatusPending  = "pending"
	StatusApproved = "approved"
	StatusRejected = "rejected"
)

var (
	// ErrAlreadyDecided is returned when a second decide with a different status is attempted.
	ErrAlreadyDecided = errors.New("تم البت في هذا العنصر مسبقاً")
	// ErrInventedBarcode rejects fabricated barcode patterns.
	ErrInventedBarcode = errors.New("رفض باركود مصنوع: لا يتم اختراع باركودات")
	// ErrTenantMismatch is returned when a persisted document does not belong to the request tenant.
	ErrTenantMismatch = errors.New("tenant mismatch")
)

// ReviewItem is one uncertain / unmatched product waiting for a human decision.
type ReviewItem struct {
	ID               string     `json:"id" firestore:"id"`
	TenantID         string     `json:"tenant_id" firestore:"tenant_id"`
	Status           string     `json:"status" firestore:"status"`
	Query            Query      `json:"query" firestore:"query"`
	Result           Result     `json:"result" firestore:"result"`
	ChosenItemCode   string     `json:"chosen_item_code,omitempty" firestore:"chosen_item_code,omitempty"`
	ChosenBarcode    string     `json:"chosen_barcode,omitempty" firestore:"chosen_barcode,omitempty"`
	DecisionReasonAR string     `json:"decision_reason_ar,omitempty" firestore:"decision_reason_ar,omitempty"`
	CreatedAt        time.Time  `json:"created_at" firestore:"created_at"`
	DecidedAt        *time.Time `json:"decided_at,omitempty" firestore:"decided_at,omitempty"`
	DecidedBy        string     `json:"decided_by,omitempty" firestore:"decided_by,omitempty"`
}

// Queue is the product-match review queue. Pending/approved/rejected state is persisted
// via Store (Firestore in production). No Product Master rows are mutated by decide.
//
// Firestore I/O always uses a timeout and never runs while holding q.mu.
type Queue struct {
	mu    sync.Mutex // protects only in-memory mutation of a loaded State copy
	store Store
	now   func() time.Time
}

// NewQueue creates a queue backed by store (nil → MemoryStore).
func NewQueue(store Store) *Queue {
	if store == nil {
		store = &MemoryStore{}
	}
	return &Queue{store: store, now: time.Now}
}

func reviewID(tenant string, q Query) string {
	key := strings.Join([]string{
		NormalizeTenantKey(tenant),
		normalizeItemCode(q.ItemCode),
		cleanBarcode(q.Barcode),
		normalizeArabicName(q.SKUName),
		strings.TrimSpace(q.SourceFile),
	}, "|")
	sum := sha1.Sum([]byte(key))
	return hex.EncodeToString(sum[:10])
}

func (q *Queue) load(ctx context.Context, tenantID string) (*State, error) {
	key := NormalizeTenantKey(tenantID)
	if key == "" {
		return nil, fmt.Errorf("tenant_id required")
	}
	ctx, cancel := withStoreTimeout(ctx)
	defer cancel()
	// No mutex held during store I/O.
	st, err := q.store.GetProductMatchState(ctx, key)
	if err != nil {
		return nil, err
	}
	if st == nil {
		st = &State{TenantID: key, Metrics: Metrics{TenantID: key}}
	}
	if st.TenantID != "" && NormalizeTenantKey(st.TenantID) != key {
		return nil, ErrTenantMismatch
	}
	st.TenantID = key
	st.Metrics.TenantID = key
	return st, nil
}

func (q *Queue) save(ctx context.Context, st *State) error {
	if st == nil {
		return fmt.Errorf("state cannot be nil")
	}
	key := NormalizeTenantKey(st.TenantID)
	if key == "" {
		return fmt.Errorf("tenant_id required")
	}
	st.TenantID = key
	st.Metrics.TenantID = key
	st.UpdatedAt = q.now().UTC()
	ctx, cancel := withStoreTimeout(ctx)
	defer cancel()
	// No mutex held during store I/O.
	return q.store.SaveProductMatchState(ctx, st)
}

// EnqueueMatch stores a review item when the match needs human attention.
// High/exact matches update metrics only (no queue row). Returns the item when enqueued.
func (q *Queue) EnqueueMatch(ctx context.Context, tenantID string, query Query, result Result) (*ReviewItem, error) {
	st, err := q.load(ctx, tenantID)
	if err != nil {
		return nil, err
	}

	q.mu.Lock()
	item := applyEnqueue(st, query, result, q.now)
	q.mu.Unlock()

	if err := q.save(ctx, st); err != nil {
		return nil, err
	}
	return item, nil
}

func applyEnqueue(st *State, query Query, result Result, nowFn func() time.Time) *ReviewItem {
	m := &st.Metrics
	m.TenantID = st.TenantID
	m.TotalMatched++
	switch result.Decision {
	case DecisionExact:
		m.Exact++
		m.AutoResolved++
	case DecisionHigh:
		m.High++
		m.AutoResolved++
	case DecisionUncertain:
		m.Uncertain++
	case DecisionNone:
		m.None++
	}
	m.touch(nowFn())
	if !NeedsReview(result) {
		return nil
	}
	id := reviewID(st.TenantID, query)
	for i := range st.Items {
		it := &st.Items[i]
		if it.ID != id {
			continue
		}
		if NormalizeTenantKey(it.TenantID) != "" && NormalizeTenantKey(it.TenantID) != st.TenantID {
			continue
		}
		if it.Status == StatusPending {
			it.Query = query
			it.Result = result
			it.CreatedAt = nowFn().UTC()
			it.TenantID = st.TenantID
			cp := *it
			return &cp
		}
		break
	}
	m.Queued++
	m.Pending++
	item := ReviewItem{
		ID:        id,
		TenantID:  st.TenantID,
		Status:    StatusPending,
		Query:     query,
		Result:    result,
		CreatedAt: nowFn().UTC(),
	}
	st.Items = append(st.Items, item)
	cp := item
	return &cp
}

// EnqueueUnknowns runs Match for each unknown Sell-In item and enqueues review rows.
func (q *Queue) EnqueueUnknowns(ctx context.Context, tenantID, sourceFile string, unknowns []Query, catalog *Catalog) ([]ReviewItem, error) {
	out := make([]ReviewItem, 0, len(unknowns))
	for _, u := range unknowns {
		if u.SourceFile == "" {
			u.SourceFile = sourceFile
		}
		var res Result
		if catalog == nil {
			res = Result{
				Decision:      DecisionNone,
				ReasonAR:      "كارتة الأصناف غير محمّلة",
				BarcodePolicy: barcodePolicy(cleanBarcode(u.Barcode), "", DecisionNone, false),
				InputBarcode:  cleanBarcode(u.Barcode),
			}
		} else {
			res = catalog.Match(u)
		}
		item, err := q.EnqueueMatch(ctx, tenantID, u, res)
		if err != nil {
			return out, err
		}
		if item != nil {
			out = append(out, *item)
		}
	}
	return out, nil
}

// List returns review items for a tenant filtered by status (empty = all).
func (q *Queue) List(ctx context.Context, tenantID, status string) ([]ReviewItem, error) {
	st, err := q.load(ctx, tenantID)
	if err != nil {
		return nil, err
	}
	out := make([]ReviewItem, 0, len(st.Items))
	for _, it := range st.Items {
		if NormalizeTenantKey(it.TenantID) != "" && NormalizeTenantKey(it.TenantID) != st.TenantID {
			continue // enforce tenant scope on read
		}
		if status != "" && it.Status != status {
			continue
		}
		out = append(out, it)
	}
	sort.Slice(out, func(i, j int) bool {
		if out[i].CreatedAt.Equal(out[j].CreatedAt) {
			return out[i].ID < out[j].ID
		}
		return out[i].CreatedAt.After(out[j].CreatedAt)
	})
	return out, nil
}

// DecideOptions carries optional catalog validation for approve.
type DecideOptions struct {
	Catalog *Catalog
}

// Decide records an approve/reject. Same-status repeats are idempotent (no counter bump).
func (q *Queue) Decide(ctx context.Context, tenantID, id, status, decidedBy, reasonAR, chosenItemCode, chosenBarcode string, opts DecideOptions) (*ReviewItem, error) {
	status = strings.TrimSpace(status)
	if status != StatusApproved && status != StatusRejected {
		return nil, fmt.Errorf("status must be %s or %s", StatusApproved, StatusRejected)
	}
	rawChosen := strings.TrimSpace(chosenBarcode)
	upperRaw := strings.ToUpper(rawChosen)
	if strings.HasPrefix(upperRaw, "SKU") || strings.Contains(upperRaw, "SKU-") || looksInventedBarcode(rawChosen) {
		return nil, ErrInventedBarcode
	}
	chosenBarcode = cleanBarcode(rawChosen)
	chosenItemCode = normalizeItemCode(chosenItemCode)

	st, err := q.load(ctx, tenantID)
	if err != nil {
		return nil, err
	}

	q.mu.Lock()
	item, mutated, err := applyDecide(st, id, status, decidedBy, reasonAR, chosenItemCode, chosenBarcode, opts, q.now)
	q.mu.Unlock()
	if err != nil {
		return nil, err
	}
	if !mutated {
		return item, nil // idempotent hit — no save needed
	}
	if err := q.save(ctx, st); err != nil {
		return nil, err
	}
	return item, nil
}

func applyDecide(st *State, id, status, decidedBy, reasonAR, chosenItemCode, chosenBarcode string, opts DecideOptions, nowFn func() time.Time) (*ReviewItem, bool, error) {
	idx := -1
	for i := range st.Items {
		if st.Items[i].ID != id {
			continue
		}
		if NormalizeTenantKey(st.Items[i].TenantID) != "" && NormalizeTenantKey(st.Items[i].TenantID) != st.TenantID {
			return nil, false, ErrTenantMismatch
		}
		idx = i
		break
	}
	if idx < 0 {
		return nil, false, fmt.Errorf("review item not found")
	}
	it := &st.Items[idx]

	if it.Status == StatusApproved || it.Status == StatusRejected {
		if it.Status == status {
			cp := *it
			return &cp, false, nil
		}
		return nil, false, ErrAlreadyDecided
	}
	if it.Status != StatusPending {
		return nil, false, fmt.Errorf("unexpected status %s", it.Status)
	}

	if status == StatusApproved {
		suggested := cleanBarcode(it.Result.SuggestedBarcode)
		effectiveCode := chosenItemCode
		effectiveBC := chosenBarcode
		if effectiveBC == "" && suggested != "" {
			effectiveBC = suggested
		}
		if effectiveCode == "" {
			effectiveCode = normalizeItemCode(it.Result.MatchedItemCode)
		}
		if opts.Catalog != nil {
			if err := opts.Catalog.ValidateChosen(effectiveCode, effectiveBC); err != nil {
				return nil, false, err
			}
		}
		chosenItemCode = effectiveCode
		chosenBarcode = effectiveBC
	}

	now := nowFn().UTC()
	it.Status = status
	it.DecidedBy = strings.TrimSpace(decidedBy)
	it.DecisionReasonAR = strings.TrimSpace(reasonAR)
	it.DecidedAt = &now
	it.ChosenItemCode = chosenItemCode
	it.ChosenBarcode = chosenBarcode
	it.TenantID = st.TenantID

	m := &st.Metrics
	m.Pending--
	if m.Pending < 0 {
		m.Pending = 0
	}
	if status == StatusApproved {
		m.Approved++
	} else {
		m.Rejected++
	}
	m.touch(nowFn())
	cp := *it
	return &cp, true, nil
}

func looksInventedBarcode(raw string) bool {
	raw = strings.TrimSpace(raw)
	if raw == "" {
		return false
	}
	for _, r := range raw {
		if (r >= 'A' && r <= 'Z') || (r >= 'a' && r <= 'z') {
			return true
		}
	}
	return false
}
