package matcher

import (
	"context"
	"crypto/sha1"
	"encoding/hex"
	"errors"
	"fmt"
	"strings"
	"time"
)

// Review status values (Arabic labels live in the UI).
const (
	StatusPending  = "pending"
	StatusApproved = "approved"
	StatusRejected = "rejected"
)

// EnqueueBatchSize caps writes per store batch (items + metrics).
const EnqueueBatchSize = 200

var (
	// ErrAlreadyDecided is returned when a second decide with a different status is attempted.
	ErrAlreadyDecided = errors.New("تم البت في هذا العنصر مسبقاً")
	// ErrInventedBarcode rejects fabricated barcode patterns.
	ErrInventedBarcode = errors.New("رفض باركود مصنوع: لا يتم اختراع باركودات")
	// ErrTenantMismatch is returned when a persisted document does not belong to the request tenant.
	ErrTenantMismatch = errors.New("tenant mismatch")
	// ErrNotFound is returned when a review item id is unknown for the tenant.
	ErrNotFound = errors.New("review item not found")
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

// Queue is the product-match review queue. Persistence is one Firestore doc per item
// plus a tenant metrics doc (Increment). Store I/O uses timeouts; Queue holds no mutex
// across I/O — race safety lives in Store (transaction / MemoryStore lock).
type Queue struct {
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

func matchDelta(result Result, needsReview bool) MetricsDelta {
	d := MetricsDelta{TotalMatched: 1}
	switch result.Decision {
	case DecisionExact:
		d.Exact = 1
		d.AutoResolved = 1
	case DecisionHigh:
		d.High = 1
		d.AutoResolved = 1
	case DecisionUncertain:
		d.Uncertain = 1
	case DecisionNone:
		d.None = 1
	}
	if needsReview {
		// Store clears Queued/Pending when refreshing an existing pending item.
		d.Queued = 1
		d.Pending = 1
	}
	return d
}

func buildOp(tenantID string, u Query, res Result) EnqueueOp {
	needs := NeedsReview(res)
	return EnqueueOp{
		ItemID: reviewID(tenantID, u), Query: u, Result: res,
		NeedsReview: needs, Delta: matchDelta(res, needs),
	}
}

// EnqueueMatch stores one match attempt.
func (q *Queue) EnqueueMatch(ctx context.Context, tenantID string, query Query, result Result) (*ReviewItem, error) {
	ctx, cancel := withStoreTimeout(ctx)
	defer cancel()
	items, err := q.store.EnqueueBatch(ctx, tenantID, []EnqueueOp{buildOp(tenantID, query, result)})
	if err != nil {
		return nil, err
	}
	if len(items) == 0 {
		return nil, nil
	}
	cp := items[0]
	return &cp, nil
}

// EnqueueUnknowns matches each unknown row and persists ops in batched store writes
// (one transaction/batch per chunk — not one full-doc rewrite per row).
func (q *Queue) EnqueueUnknowns(ctx context.Context, tenantID, sourceFile string, unknowns []Query, catalog *Catalog) ([]ReviewItem, error) {
	ops := make([]EnqueueOp, 0, len(unknowns))
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
		ops = append(ops, buildOp(tenantID, u, res))
	}

	out := make([]ReviewItem, 0)
	for i := 0; i < len(ops); i += EnqueueBatchSize {
		end := i + EnqueueBatchSize
		if end > len(ops) {
			end = len(ops)
		}
		ctxChunk, cancel := withStoreTimeout(ctx)
		items, err := q.store.EnqueueBatch(ctxChunk, tenantID, ops[i:end])
		cancel()
		if err != nil {
			return out, err
		}
		out = append(out, items...)
	}
	return out, nil
}

// List returns review items for a tenant filtered by status (empty = all).
func (q *Queue) List(ctx context.Context, tenantID, status string) ([]ReviewItem, error) {
	ctx, cancel := withStoreTimeout(ctx)
	defer cancel()
	return q.store.ListItems(ctx, tenantID, status)
}

// DecideOptions carries optional catalog validation for approve.
type DecideOptions struct {
	Catalog *Catalog
}

// Decide records an approve/reject via a store transaction (pending check + Increment counters).
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

	ctxGet, cancelGet := withStoreTimeout(ctx)
	existing, err := q.store.GetItem(ctxGet, tenantID, id)
	cancelGet()
	if err != nil {
		return nil, err
	}
	if existing == nil {
		return nil, ErrNotFound
	}
	if NormalizeTenantKey(existing.TenantID) != "" && NormalizeTenantKey(existing.TenantID) != NormalizeTenantKey(tenantID) {
		return nil, ErrTenantMismatch
	}
	if existing.Status == StatusApproved || existing.Status == StatusRejected {
		if existing.Status == status {
			cp := *existing
			return &cp, nil
		}
		return nil, ErrAlreadyDecided
	}

	if status == StatusApproved {
		suggested := cleanBarcode(existing.Result.SuggestedBarcode)
		effectiveCode := chosenItemCode
		effectiveBC := chosenBarcode
		if effectiveBC == "" && suggested != "" {
			effectiveBC = suggested
		}
		if effectiveCode == "" {
			effectiveCode = normalizeItemCode(existing.Result.MatchedItemCode)
		}
		if opts.Catalog != nil {
			if err := opts.Catalog.ValidateChosen(effectiveCode, effectiveBC); err != nil {
				return nil, err
			}
		}
		chosenItemCode = effectiveCode
		chosenBarcode = effectiveBC
	}

	ctxDec, cancelDec := withStoreTimeout(ctx)
	defer cancelDec()
	return q.store.DecideItem(ctxDec, tenantID, DecidePatch{
		ID: id, Status: status, DecidedBy: strings.TrimSpace(decidedBy),
		ReasonAR: strings.TrimSpace(reasonAR), ChosenItemCode: chosenItemCode,
		ChosenBarcode: chosenBarcode, Now: q.now().UTC(),
	})
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
