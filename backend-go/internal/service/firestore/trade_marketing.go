package firestore

import (
	"context"
	"errors"
	"fmt"
	"sort"
	"strings"
	"time"

	"google.golang.org/api/iterator"

	"github.com/tashil/data-sharing/backend/internal/domain"
)

const marketingExpensesCollection = "marketing_expenses"

// ErrExpenseNotFound is returned when an expense does not exist for the tenant.
var ErrExpenseNotFound = errors.New("marketing expense not found")

// TradeMarketingRepository persists trade-marketing expenses, always scoped by tenant.
type TradeMarketingRepository interface {
	SaveMarketingExpense(ctx context.Context, e *domain.MarketingExpense) error
	ListMarketingExpenses(ctx context.Context, tenantID string, f domain.MarketingExpenseFilter) ([]domain.MarketingExpense, error)
	DeleteMarketingExpense(ctx context.Context, tenantID, id string) error
}

var _ TradeMarketingRepository = (*Client)(nil)

func expenseTenantKey(tenantID string) string { return normalizeFirestoreTenantSlug(tenantID) }

// SaveMarketingExpense creates or updates an expense. Updates must belong to the same tenant.
// Writes go synchronously to Firestore so data survives Cloud Run instance restarts.
func (c *Client) SaveMarketingExpense(ctx context.Context, e *domain.MarketingExpense) error {
	if e == nil {
		return fmt.Errorf("expense cannot be nil")
	}
	slug := expenseTenantKey(e.TenantID)
	e.TenantID = slug
	now := time.Now().UTC()

	c.tmMu.Lock()
	if c.tmExpenses == nil {
		c.tmExpenses = make(map[string]domain.MarketingExpense)
	}
	if e.ID == "" {
		e.ID = fmt.Sprintf("mexp_%d", now.UnixNano())
		e.CreatedAt = now
	} else if prev, ok := c.tmExpenses[e.ID]; ok {
		if prev.TenantID != slug {
			c.tmMu.Unlock()
			return ErrExpenseNotFound
		}
		e.CreatedAt, e.CreatedBy = prev.CreatedAt, prev.CreatedBy
	}
	if e.CreatedAt.IsZero() {
		e.CreatedAt = now
	}
	e.UpdatedAt = now
	c.tmExpenses[e.ID] = *e
	c.tmMu.Unlock()

	if c.fsClient != nil {
		doc := c.fsClient.Collection(marketingExpensesCollection).Doc(e.ID)
		if snap, err := doc.Get(ctx); err == nil {
			var existing domain.MarketingExpense
			if snap.DataTo(&existing) == nil && existing.TenantID != slug {
				return ErrExpenseNotFound
			}
		}
		if _, err := doc.Set(ctx, *e); err != nil {
			return fmt.Errorf("firestore save expense: %w", err)
		}
	}
	return nil
}

// ListMarketingExpenses returns the tenant's expenses, newest period first.
// With Firestore configured it reads from Firestore (source of truth across instances).
func (c *Client) ListMarketingExpenses(ctx context.Context, tenantID string, f domain.MarketingExpenseFilter) ([]domain.MarketingExpense, error) {
	slug := expenseTenantKey(tenantID)
	var all []domain.MarketingExpense

	if c.fsClient != nil {
		it := c.fsClient.Collection(marketingExpensesCollection).Where("tenant_id", "==", slug).Documents(ctx)
		defer it.Stop()
		fresh := make(map[string]domain.MarketingExpense)
		for {
			snap, err := it.Next()
			if err == iterator.Done {
				break
			}
			if err != nil {
				return nil, fmt.Errorf("firestore list expenses: %w", err)
			}
			var e domain.MarketingExpense
			if snap.DataTo(&e) == nil {
				all = append(all, e)
				fresh[e.ID] = e
			}
		}
		c.tmMu.Lock()
		if c.tmExpenses == nil {
			c.tmExpenses = make(map[string]domain.MarketingExpense)
		}
		for id, e := range fresh {
			c.tmExpenses[id] = e
		}
		c.tmMu.Unlock()
	} else {
		c.tmMu.RLock()
		for _, e := range c.tmExpenses {
			if e.TenantID == slug {
				all = append(all, e)
			}
		}
		c.tmMu.RUnlock()
	}

	chain := strings.ToLower(strings.TrimSpace(f.Chain))
	if chain == "all" || chain == "الكل" {
		chain = ""
	}
	out := make([]domain.MarketingExpense, 0, len(all))
	for _, e := range all {
		if f.Year > 0 && e.Year != f.Year {
			continue
		}
		if f.Month > 0 && e.Month != f.Month {
			continue
		}
		if chain != "" && strings.ToLower(strings.TrimSpace(e.ChainName)) != chain {
			continue
		}
		out = append(out, e)
	}
	sort.Slice(out, func(i, j int) bool {
		if out[i].Year != out[j].Year {
			return out[i].Year > out[j].Year
		}
		if out[i].Month != out[j].Month {
			return out[i].Month > out[j].Month
		}
		return out[i].CreatedAt.After(out[j].CreatedAt)
	})
	return out, nil
}

// DeleteMarketingExpense removes an expense only if it belongs to tenantID.
func (c *Client) DeleteMarketingExpense(ctx context.Context, tenantID, id string) error {
	slug := expenseTenantKey(tenantID)
	id = strings.TrimSpace(id)
	if id == "" {
		return ErrExpenseNotFound
	}
	found := false
	c.tmMu.Lock()
	if e, ok := c.tmExpenses[id]; ok {
		if e.TenantID != slug {
			c.tmMu.Unlock()
			return ErrExpenseNotFound
		}
		delete(c.tmExpenses, id)
		found = true
	}
	c.tmMu.Unlock()

	if c.fsClient != nil {
		doc := c.fsClient.Collection(marketingExpensesCollection).Doc(id)
		snap, err := doc.Get(ctx)
		if err != nil {
			if found {
				return nil
			}
			return ErrExpenseNotFound
		}
		var e domain.MarketingExpense
		if snap.DataTo(&e) != nil || e.TenantID != slug {
			return ErrExpenseNotFound
		}
		if _, err := doc.Delete(ctx); err != nil {
			return fmt.Errorf("firestore delete expense: %w", err)
		}
		return nil
	}
	if !found {
		return ErrExpenseNotFound
	}
	return nil
}
