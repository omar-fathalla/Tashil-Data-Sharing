package firestore

import (
	"context"
	"fmt"
	"sort"
	"strings"
	"sync"
	"time"

	cloudFirestore "cloud.google.com/go/firestore"
	"google.golang.org/api/iterator"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"

	"github.com/tashil/data-sharing/backend/internal/service/matcher"
)

const (
	productMatchCollection = "product_match_reviews"
	productMatchItemsSub   = "items"
)

// productMatchMem is the mock/fallback store when Cloud Firestore is not configured.
type productMatchMem struct {
	mu      sync.Mutex
	items   map[string]map[string]matcher.ReviewItem
	metrics map[string]matcher.Metrics
}

func (c *Client) pmMem() *productMatchMem {
	c.pmOnce.Do(func() {
		c.pmStates = &productMatchMem{
			items:   map[string]map[string]matcher.ReviewItem{},
			metrics: map[string]matcher.Metrics{},
		}
	})
	return c.pmStates
}

func (c *Client) pmTenantRef(slug string) *cloudFirestore.DocumentRef {
	return c.fsClient.Collection(productMatchCollection).Doc(slug)
}

func (c *Client) pmItemRef(slug, id string) *cloudFirestore.DocumentRef {
	return c.pmTenantRef(slug).Collection(productMatchItemsSub).Doc(id)
}

func (c *Client) pmCountersRef(slug string) *cloudFirestore.DocumentRef {
	return c.pmTenantRef(slug).Collection("_meta").Doc("counters")
}

func (m *productMatchMem) ensure(slug string) {
	if m.items[slug] == nil {
		m.items[slug] = map[string]matcher.ReviewItem{}
	}
	if _, ok := m.metrics[slug]; !ok {
		m.metrics[slug] = matcher.Metrics{TenantID: slug}
	}
}

// ListItems lists review items for a tenant (optional status filter).
func (c *Client) ListItems(ctx context.Context, tenantID, status string) ([]matcher.ReviewItem, error) {
	slug := normalizeFirestoreTenantSlug(tenantID)
	if c.fsClient != nil {
		iter := c.pmTenantRef(slug).Collection(productMatchItemsSub).Documents(ctx)
		var out []matcher.ReviewItem
		for {
			snap, err := iter.Next()
			if err == iterator.Done {
				break
			}
			if err != nil {
				return nil, fmt.Errorf("firestore list product match items: %w", err)
			}
			var it matcher.ReviewItem
			if err := snap.DataTo(&it); err != nil {
				continue
			}
			if it.ID == "" {
				it.ID = snap.Ref.ID
			}
			if normalizeFirestoreTenantSlug(it.TenantID) != "" && normalizeFirestoreTenantSlug(it.TenantID) != slug {
				continue
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
	mem := c.pmMem()
	mem.mu.Lock()
	defer mem.mu.Unlock()
	mem.ensure(slug)
	out := make([]matcher.ReviewItem, 0, len(mem.items[slug]))
	for _, it := range mem.items[slug] {
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

// GetItem returns one review item or (nil, nil) when missing.
func (c *Client) GetItem(ctx context.Context, tenantID, id string) (*matcher.ReviewItem, error) {
	slug := normalizeFirestoreTenantSlug(tenantID)
	id = strings.TrimSpace(id)
	if id == "" {
		return nil, fmt.Errorf("id required")
	}
	if c.fsClient != nil {
		snap, err := c.pmItemRef(slug, id).Get(ctx)
		if err != nil {
			if status.Code(err) == codes.NotFound {
				return nil, nil
			}
			return nil, fmt.Errorf("firestore get product match item: %w", err)
		}
		var it matcher.ReviewItem
		if err := snap.DataTo(&it); err != nil {
			return nil, err
		}
		if it.ID == "" {
			it.ID = id
		}
		if normalizeFirestoreTenantSlug(it.TenantID) != "" && normalizeFirestoreTenantSlug(it.TenantID) != slug {
			return nil, matcher.ErrTenantMismatch
		}
		return &it, nil
	}
	mem := c.pmMem()
	mem.mu.Lock()
	defer mem.mu.Unlock()
	mem.ensure(slug)
	it, ok := mem.items[slug][id]
	if !ok {
		return nil, nil
	}
	cp := it
	return &cp, nil
}

// GetMetrics returns tenant counters.
func (c *Client) GetMetrics(ctx context.Context, tenantID string) (matcher.Metrics, error) {
	slug := normalizeFirestoreTenantSlug(tenantID)
	if c.fsClient != nil {
		snap, err := c.pmCountersRef(slug).Get(ctx)
		if err != nil {
			if status.Code(err) == codes.NotFound {
				return matcher.Metrics{TenantID: slug}, nil
			}
			return matcher.Metrics{}, fmt.Errorf("firestore get product match metrics: %w", err)
		}
		var m matcher.Metrics
		if err := snap.DataTo(&m); err != nil {
			return matcher.Metrics{}, err
		}
		m.TenantID = slug
		return m, nil
	}
	mem := c.pmMem()
	mem.mu.Lock()
	defer mem.mu.Unlock()
	mem.ensure(slug)
	m := mem.metrics[slug]
	m.TenantID = slug
	return m, nil
}

// EnqueueBatch writes items + Increment counters in one Firestore transaction (or under one mock lock).
func (c *Client) EnqueueBatch(ctx context.Context, tenantID string, ops []matcher.EnqueueOp) ([]matcher.ReviewItem, error) {
	slug := normalizeFirestoreTenantSlug(tenantID)
	if slug == "" {
		return nil, fmt.Errorf("tenant_id required")
	}
	if c.fsClient != nil {
		return c.enqueueBatchFS(ctx, slug, ops)
	}
	return c.enqueueBatchMem(slug, ops)
}

func (c *Client) enqueueBatchMem(slug string, ops []matcher.EnqueueOp) ([]matcher.ReviewItem, error) {
	mem := c.pmMem()
	mem.mu.Lock()
	defer mem.mu.Unlock()
	mem.ensure(slug)
	now := time.Now().UTC()
	out := make([]matcher.ReviewItem, 0)
	var total matcher.MetricsDelta
	for _, op := range ops {
		d := op.Delta
		if !op.NeedsReview {
			total = addMD(total, d)
			continue
		}
		id := strings.TrimSpace(op.ItemID)
		if id == "" {
			total = addMD(total, d)
			continue
		}
		if existing, ok := mem.items[slug][id]; ok && existing.Status == matcher.StatusPending {
			d.Queued, d.Pending = 0, 0
			total = addMD(total, d)
			existing.Query, existing.Result, existing.CreatedAt, existing.TenantID = op.Query, op.Result, now, slug
			mem.items[slug][id] = existing
			out = append(out, existing)
			continue
		}
		if existing, ok := mem.items[slug][id]; ok && existing.Status != matcher.StatusPending {
			d.Queued, d.Pending = 0, 0
			total = addMD(total, d)
			continue
		}
		total = addMD(total, d)
		item := matcher.ReviewItem{ID: id, TenantID: slug, Status: matcher.StatusPending, Query: op.Query, Result: op.Result, CreatedAt: now}
		mem.items[slug][id] = item
		out = append(out, item)
	}
	mem.metrics[slug] = applyMD(mem.metrics[slug], slug, total, now)
	return out, nil
}

func (c *Client) enqueueBatchFS(ctx context.Context, slug string, ops []matcher.EnqueueOp) ([]matcher.ReviewItem, error) {
	var out []matcher.ReviewItem
	err := c.fsClient.RunTransaction(ctx, func(ctx context.Context, tx *cloudFirestore.Transaction) error {
		out = out[:0]
		now := time.Now().UTC()
		var total matcher.MetricsDelta
		for _, op := range ops {
			d := op.Delta
			if !op.NeedsReview {
				total = addMD(total, d)
				continue
			}
			id := strings.TrimSpace(op.ItemID)
			if id == "" {
				total = addMD(total, d)
				continue
			}
			ref := c.pmItemRef(slug, id)
			snap, err := tx.Get(ref)
			if err != nil && status.Code(err) != codes.NotFound {
				return err
			}
			if err == nil && snap.Exists() {
				var existing matcher.ReviewItem
				if err := snap.DataTo(&existing); err != nil {
					return err
				}
				if normalizeFirestoreTenantSlug(existing.TenantID) != "" && normalizeFirestoreTenantSlug(existing.TenantID) != slug {
					return matcher.ErrTenantMismatch
				}
				if existing.Status == matcher.StatusPending {
					d.Queued, d.Pending = 0, 0
					total = addMD(total, d)
					existing.Query, existing.Result, existing.CreatedAt, existing.TenantID = op.Query, op.Result, now, slug
					existing.ID = id
					if err := tx.Set(ref, existing); err != nil {
						return err
					}
					out = append(out, existing)
					continue
				}
				// decided — leave alone
				d.Queued, d.Pending = 0, 0
				total = addMD(total, d)
				continue
			}
			total = addMD(total, d)
			item := matcher.ReviewItem{ID: id, TenantID: slug, Status: matcher.StatusPending, Query: op.Query, Result: op.Result, CreatedAt: now}
			if err := tx.Set(ref, item); err != nil {
				return err
			}
			out = append(out, item)
		}
		return c.txIncrementCounters(tx, slug, total, now)
	})
	if err != nil {
		return nil, fmt.Errorf("firestore enqueue product match: %w", err)
	}
	return out, nil
}

// DecideItem transactionally flips pending → approved/rejected and Increments counters.
func (c *Client) DecideItem(ctx context.Context, tenantID string, patch matcher.DecidePatch) (*matcher.ReviewItem, error) {
	slug := normalizeFirestoreTenantSlug(tenantID)
	id := strings.TrimSpace(patch.ID)
	if slug == "" || id == "" {
		return nil, fmt.Errorf("tenant_id and id required")
	}
	if c.fsClient != nil {
		var out *matcher.ReviewItem
		err := c.fsClient.RunTransaction(ctx, func(ctx context.Context, tx *cloudFirestore.Transaction) error {
			ref := c.pmItemRef(slug, id)
			snap, err := tx.Get(ref)
			if err != nil {
				if status.Code(err) == codes.NotFound {
					return matcher.ErrNotFound
				}
				return err
			}
			var it matcher.ReviewItem
			if err := snap.DataTo(&it); err != nil {
				return err
			}
			if it.ID == "" {
				it.ID = id
			}
			if normalizeFirestoreTenantSlug(it.TenantID) != "" && normalizeFirestoreTenantSlug(it.TenantID) != slug {
				return matcher.ErrTenantMismatch
			}
			if it.Status == matcher.StatusApproved || it.Status == matcher.StatusRejected {
				if it.Status == patch.Status {
					cp := it
					out = &cp
					return nil // idempotent — no writes
				}
				return matcher.ErrAlreadyDecided
			}
			if it.Status != matcher.StatusPending {
				return fmt.Errorf("unexpected status %s", it.Status)
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
			it.TenantID = slug
			if err := tx.Set(ref, it); err != nil {
				return err
			}
			d := matcher.MetricsDelta{Pending: -1}
			if patch.Status == matcher.StatusApproved {
				d.Approved = 1
			} else {
				d.Rejected = 1
			}
			if err := c.txIncrementCounters(tx, slug, d, now); err != nil {
				return err
			}
			cp := it
			out = &cp
			return nil
		})
		if err != nil {
			return nil, err
		}
		return out, nil
	}

	mem := c.pmMem()
	mem.mu.Lock()
	defer mem.mu.Unlock()
	mem.ensure(slug)
	it, ok := mem.items[slug][id]
	if !ok {
		return nil, matcher.ErrNotFound
	}
	if it.Status == matcher.StatusApproved || it.Status == matcher.StatusRejected {
		if it.Status == patch.Status {
			cp := it
			return &cp, nil
		}
		return nil, matcher.ErrAlreadyDecided
	}
	if it.Status != matcher.StatusPending {
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
	it.TenantID = slug
	mem.items[slug][id] = it
	d := matcher.MetricsDelta{Pending: -1}
	if patch.Status == matcher.StatusApproved {
		d.Approved = 1
	} else {
		d.Rejected = 1
	}
	mem.metrics[slug] = applyMD(mem.metrics[slug], slug, d, now)
	cp := it
	return &cp, nil
}

func (c *Client) txIncrementCounters(tx *cloudFirestore.Transaction, slug string, d matcher.MetricsDelta, now time.Time) error {
	if d == (matcher.MetricsDelta{}) {
		return nil
	}
	ref := c.pmCountersRef(slug)
	snap, err := tx.Get(ref)
	updates := []cloudFirestore.Update{
		{Path: "tenant_id", Value: slug},
		{Path: "updated_at", Value: now},
	}
	add := func(path string, n int64) {
		if n != 0 {
			updates = append(updates, cloudFirestore.Update{Path: path, Value: cloudFirestore.Increment(n)})
		}
	}
	add("total_matched", d.TotalMatched)
	add("exact", d.Exact)
	add("high", d.High)
	add("uncertain", d.Uncertain)
	add("none", d.None)
	add("auto_resolved", d.AutoResolved)
	add("queued", d.Queued)
	add("pending", d.Pending)
	add("approved", d.Approved)
	add("rejected", d.Rejected)

	if err != nil && status.Code(err) == codes.NotFound {
		// Create counters doc with absolute values for this batch.
		m := applyMD(matcher.Metrics{TenantID: slug}, slug, d, now)
		return tx.Set(ref, m)
	}
	if err != nil {
		return err
	}
	_ = snap
	return tx.Update(ref, updates)
}

func addMD(a, b matcher.MetricsDelta) matcher.MetricsDelta {
	return matcher.MetricsDelta{
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

func applyMD(m matcher.Metrics, tenant string, d matcher.MetricsDelta, now time.Time) matcher.Metrics {
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

// Ensure Client implements matcher.Store.
var _ matcher.Store = (*Client)(nil)
