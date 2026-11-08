package matcher

import (
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
)

// ReviewItem is one uncertain / unmatched product waiting for a human decision.
type ReviewItem struct {
	ID               string     `json:"id"`
	TenantID         string     `json:"tenant_id"`
	Status           string     `json:"status"`
	Query            Query      `json:"query"`
	Result           Result     `json:"result"`
	ChosenItemCode   string     `json:"chosen_item_code,omitempty"`
	ChosenBarcode    string     `json:"chosen_barcode,omitempty"`
	DecisionReasonAR string     `json:"decision_reason_ar,omitempty"`
	CreatedAt        time.Time  `json:"created_at"`
	DecidedAt        *time.Time `json:"decided_at,omitempty"`
	DecidedBy        string     `json:"decided_by,omitempty"`
}

// Queue is an in-memory per-tenant review queue. No production Product Master
// rows are mutated by approve/reject — decisions are recorded for operators only.
//
// Durability: RAM-only today (lost on restart / not shared across Cloud Run
// instances). Open decision for Mohamed — see docs/gemini-barcode-matching.md.
type Queue struct {
	mu      sync.RWMutex
	items   map[string]map[string]*ReviewItem // tenant -> id -> item
	metrics map[string]*Metrics
	now     func() time.Time
}

// NewQueue creates an empty review queue.
func NewQueue() *Queue {
	return &Queue{
		items:   make(map[string]map[string]*ReviewItem),
		metrics: make(map[string]*Metrics),
		now:     time.Now,
	}
}

func reviewID(tenant string, q Query) string {
	key := strings.Join([]string{
		strings.TrimSpace(tenant),
		normalizeItemCode(q.ItemCode),
		cleanBarcode(q.Barcode),
		normalizeArabicName(q.SKUName),
		strings.TrimSpace(q.SourceFile),
	}, "|")
	sum := sha1.Sum([]byte(key))
	return hex.EncodeToString(sum[:10])
}

// EnqueueMatch stores a review item when the match needs human attention.
// High/exact matches update metrics only (no queue row). Returns the item when enqueued.
// Re-upload of the same pending key refreshes the row without double-counting Queued/Pending.
func (q *Queue) EnqueueMatch(tenantID string, query Query, result Result) *ReviewItem {
	tenantID = strings.TrimSpace(tenantID)
	if tenantID == "" {
		return nil
	}
	q.mu.Lock()
	defer q.mu.Unlock()
	m := q.ensureMetricsLocked(tenantID)
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
	if !NeedsReview(result) {
		m.touch(q.now())
		return nil
	}
	id := reviewID(tenantID, query)
	bucket, ok := q.items[tenantID]
	if !ok {
		bucket = make(map[string]*ReviewItem)
		q.items[tenantID] = bucket
	}
	if existing, ok := bucket[id]; ok && existing.Status == StatusPending {
		// Refresh payload only — do not bump Queued/Pending again.
		existing.Query = query
		existing.Result = result
		existing.CreatedAt = q.now().UTC()
		m.touch(q.now())
		cp := *existing
		return &cp
	}
	// Re-open a previously decided item only as a new pending row (rare re-upload after decide).
	m.Queued++
	item := &ReviewItem{
		ID:        id,
		TenantID:  tenantID,
		Status:    StatusPending,
		Query:     query,
		Result:    result,
		CreatedAt: q.now().UTC(),
	}
	bucket[id] = item
	m.Pending++
	m.touch(q.now())
	cp := *item
	return &cp
}

// EnqueueUnknowns runs Match for each unknown Sell-In item and enqueues review rows.
// Catalog may be nil (treated as empty → all DecisionNone).
func (q *Queue) EnqueueUnknowns(tenantID, sourceFile string, unknowns []Query, catalog *Catalog) []ReviewItem {
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
		if item := q.EnqueueMatch(tenantID, u, res); item != nil {
			out = append(out, *item)
		}
	}
	return out
}

// List returns review items for a tenant filtered by status (empty = all).
func (q *Queue) List(tenantID, status string) []ReviewItem {
	q.mu.RLock()
	defer q.mu.RUnlock()
	bucket := q.items[strings.TrimSpace(tenantID)]
	out := make([]ReviewItem, 0, len(bucket))
	for _, it := range bucket {
		if status != "" && it.Status != status {
			continue
		}
		out = append(out, *it)
	}
	sort.Slice(out, func(i, j int) bool {
		if out[i].CreatedAt.Equal(out[j].CreatedAt) {
			return out[i].ID < out[j].ID
		}
		return out[i].CreatedAt.After(out[j].CreatedAt)
	})
	return out
}

// DecideOptions carries optional catalog validation for approve.
type DecideOptions struct {
	Catalog *Catalog // tenant Product Master; required to validate chosen code/barcode on approve
}

// Decide records an approve/reject. Same-status repeats are idempotent (no counter bump).
// Different-status repeats return ErrAlreadyDecided. Approve validates chosen_barcode /
// chosen_item_code against the tenant catalog when provided.
func (q *Queue) Decide(tenantID, id, status, decidedBy, reasonAR, chosenItemCode, chosenBarcode string, opts DecideOptions) (*ReviewItem, error) {
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

	q.mu.Lock()
	defer q.mu.Unlock()
	bucket := q.items[strings.TrimSpace(tenantID)]
	it, ok := bucket[id]
	if !ok {
		return nil, fmt.Errorf("review item not found")
	}

	// Idempotent / reject-repeat handling before mutating counters.
	if it.Status == StatusApproved || it.Status == StatusRejected {
		if it.Status == status {
			cp := *it
			return &cp, nil // idempotent success
		}
		return nil, ErrAlreadyDecided
	}
	if it.Status != StatusPending {
		return nil, fmt.Errorf("unexpected status %s", it.Status)
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
				return nil, err
			}
		} else if effectiveBC != "" || effectiveCode != "" {
			// Without a catalog we still refuse to invent; barcode must be empty or digits-only (already cleaned).
			// Pair validation is skipped only when Catalog is nil (tests that do not care about PM).
		}
		chosenItemCode = effectiveCode
		chosenBarcode = effectiveBC
	}

	now := q.now().UTC()
	it.Status = status
	it.DecidedBy = strings.TrimSpace(decidedBy)
	it.DecisionReasonAR = strings.TrimSpace(reasonAR)
	it.DecidedAt = &now
	it.ChosenItemCode = chosenItemCode
	it.ChosenBarcode = chosenBarcode

	m := q.ensureMetricsLocked(tenantID)
	m.Pending--
	if m.Pending < 0 {
		m.Pending = 0
	}
	if status == StatusApproved {
		m.Approved++
	} else {
		m.Rejected++
	}
	m.touch(q.now())
	cp := *it
	return &cp, nil
}

// looksInventedBarcode flags non-digit barcodes that are not empty after trim
// (real GTINs are digits-only; anything with letters was fabricated).
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

func (q *Queue) ensureMetricsLocked(tenantID string) *Metrics {
	m, ok := q.metrics[tenantID]
	if !ok {
		m = &Metrics{TenantID: tenantID}
		q.metrics[tenantID] = m
	}
	return m
}
