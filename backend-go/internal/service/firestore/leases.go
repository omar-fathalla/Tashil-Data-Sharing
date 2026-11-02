package firestore

import (
	"context"
	"fmt"
	"time"

	cloudFirestore "cloud.google.com/go/firestore"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

const leasesCollection = "leases"

// LeaseStore is a cross-instance mutual-exclusion lease with a TTL: one holder at a time, and a holder that
// dies stops blocking others once its lease expires.
type LeaseStore interface {
	TryAcquireLease(ctx context.Context, name, holder string, ttl time.Duration) (bool, error)
	ReleaseLease(ctx context.Context, name, holder string) error
}

var _ LeaseStore = (*Client)(nil)

type leaseDoc struct {
	Holder    string    `firestore:"holder"`
	ExpiresAt time.Time `firestore:"expires_at"`
	UpdatedAt time.Time `firestore:"updated_at"`
}

type memLease struct {
	holder  string
	expires time.Time
}

// leaseFree reports whether holder may take (or renew) a lease currently held by cur until exp.
func leaseFree(cur string, exp time.Time, holder string, now time.Time) bool {
	return cur == "" || cur == holder || !now.Before(exp)
}

// TryAcquireLease takes the named lease for ttl if it is free, expired or already held by holder.
func (c *Client) TryAcquireLease(ctx context.Context, name, holder string, ttl time.Duration) (bool, error) {
	now := time.Now().UTC()
	if c.fsClient != nil {
		ref := c.fsClient.Collection(leasesCollection).Doc(name)
		acquired := false
		err := c.fsClient.RunTransaction(ctx, func(ctx context.Context, tx *cloudFirestore.Transaction) error {
			acquired = false
			snap, err := tx.Get(ref)
			if err != nil && status.Code(err) != codes.NotFound {
				return err
			}
			if err == nil && snap.Exists() {
				var d leaseDoc
				if err := snap.DataTo(&d); err != nil {
					return err
				}
				if !leaseFree(d.Holder, d.ExpiresAt, holder, now) {
					return nil
				}
			}
			acquired = true
			return tx.Set(ref, leaseDoc{Holder: holder, ExpiresAt: now.Add(ttl), UpdatedAt: now})
		})
		if err != nil {
			return false, fmt.Errorf("firestore lease %s: %w", name, err)
		}
		return acquired, nil
	}
	c.dvMu.Lock()
	defer c.dvMu.Unlock()
	if c.leases == nil {
		c.leases = map[string]memLease{}
	}
	cur := c.leases[name]
	if !leaseFree(cur.holder, cur.expires, holder, now) {
		return false, nil
	}
	c.leases[name] = memLease{holder: holder, expires: now.Add(ttl)}
	return true, nil
}

// ReleaseLease frees the lease if holder still owns it.
func (c *Client) ReleaseLease(ctx context.Context, name, holder string) error {
	if c.fsClient != nil {
		ref := c.fsClient.Collection(leasesCollection).Doc(name)
		return c.fsClient.RunTransaction(ctx, func(ctx context.Context, tx *cloudFirestore.Transaction) error {
			snap, err := tx.Get(ref)
			if err != nil {
				if status.Code(err) == codes.NotFound {
					return nil
				}
				return err
			}
			var d leaseDoc
			if err := snap.DataTo(&d); err != nil {
				return err
			}
			if d.Holder != holder {
				return nil
			}
			return tx.Delete(ref)
		})
	}
	c.dvMu.Lock()
	defer c.dvMu.Unlock()
	if c.leases[name].holder == holder {
		delete(c.leases, name)
	}
	return nil
}
