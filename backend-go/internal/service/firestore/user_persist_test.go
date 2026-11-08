package firestore

import (
	"context"
	"errors"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/tashil/data-sharing/backend/internal/domain"
)

func TestUpdatePasswordPersistFailureDoesNotPublish(t *testing.T) {
	c := NewClient("db", true)
	before, err := c.GetUserByEmail(context.Background(), "adeco", "admin@adeco-retail.com")
	if err != nil {
		t.Fatal(err)
	}
	origHash := before.PasswordHash

	var sawPersist atomic.Bool
	c.persistTenantUserFn = func(ctx context.Context, u domain.TenantUser) error {
		sawPersist.Store(true)
		// Mid-persist: login map must still show the old hash.
		cur, err := c.GetUserByEmail(context.Background(), "adeco", "admin@adeco-retail.com")
		if err != nil {
			t.Errorf("lookup during persist: %v", err)
			return errors.New("fs down")
		}
		if cur.PasswordHash != origHash {
			t.Errorf("uncommitted hash visible during persist: got %q want %q", cur.PasswordHash, origHash)
		}
		return errors.New("fs down")
	}

	if err := c.UpdateUserPassword(context.Background(), before.UserID, "new-hash-should-not-publish"); err == nil {
		t.Fatal("expected persist failure")
	}
	if !sawPersist.Load() {
		t.Fatal("persist hook was not called")
	}
	after, err := c.GetUserByEmail(context.Background(), "adeco", "admin@adeco-retail.com")
	if err != nil {
		t.Fatal(err)
	}
	if after.PasswordHash != origHash {
		t.Fatalf("failed persist published hash: got %q want %q", after.PasswordHash, origHash)
	}
}

func TestSaveUserPersistFailureDoesNotPublishNewUser(t *testing.T) {
	c := NewClient("db", true)
	c.persistTenantUserFn = func(ctx context.Context, u domain.TenantUser) error {
		return errors.New("fs down")
	}
	u := domain.TenantUser{
		UserID:       "user-new-persist-fail",
		TenantID:     "adeco",
		Email:        "new.fail@adeco-retail.com",
		PasswordHash: "secret",
		Role:         domain.RoleVendorAdmin,
		Active:       true,
	}
	if err := c.SaveUser(context.Background(), &u); err == nil {
		t.Fatal("expected persist failure")
	}
	if _, err := c.GetUserByEmail(context.Background(), "adeco", "new.fail@adeco-retail.com"); err == nil {
		t.Fatal("failed SaveUser must not make user loginable")
	}
}

func TestConcurrentPasswordWritersLatestWinsAndFailureDoesNotClobber(t *testing.T) {
	c := NewClient("db", true)
	base, err := c.GetUserByEmail(context.Background(), "adeco", "admin@adeco-retail.com")
	if err != nil {
		t.Fatal(err)
	}

	var (
		releaseFirst sync.WaitGroup
		firstDone    sync.WaitGroup
		secondDone   sync.WaitGroup
		firstStarted sync.WaitGroup
	)
	releaseFirst.Add(1)
	firstDone.Add(1)
	secondDone.Add(1)
	firstStarted.Add(1)

	var persistCalls atomic.Int32
	c.persistTenantUserFn = func(ctx context.Context, u domain.TenantUser) error {
		n := persistCalls.Add(1)
		if u.PasswordHash == "hash-first" {
			firstStarted.Done()
			releaseFirst.Wait()
			return errors.New("first writer persist failed")
		}
		if u.PasswordHash == "hash-second" {
			return nil
		}
		t.Errorf("unexpected persist hash %q (call %d)", u.PasswordHash, n)
		return errors.New("unexpected")
	}

	var firstErr, secondErr error
	go func() {
		defer firstDone.Done()
		firstErr = c.UpdateUserPassword(context.Background(), base.UserID, "hash-first")
	}()
	firstStarted.Wait()

	go func() {
		defer secondDone.Done()
		// Gate is held by first writer; this blocks until first finishes persist+return.
		secondErr = c.UpdateUserPassword(context.Background(), base.UserID, "hash-second")
	}()

	// Give the second goroutine a moment to block on the per-user gate.
	time.Sleep(20 * time.Millisecond)
	releaseFirst.Done()
	firstDone.Wait()
	secondDone.Wait()

	if firstErr == nil {
		t.Fatal("first writer should fail persist")
	}
	if secondErr != nil {
		t.Fatalf("second writer should succeed: %v", secondErr)
	}
	got, err := c.GetUserByEmail(context.Background(), "adeco", "admin@adeco-retail.com")
	if err != nil {
		t.Fatal(err)
	}
	if got.PasswordHash != "hash-second" {
		t.Fatalf("expected latest successful hash, got %q", got.PasswordHash)
	}
}

func TestRefreshAuthUsersTwoClientPasswordConvergence(t *testing.T) {
	// Simulate two instances sharing the same durable store via applyLoadedTenantUsers.
	a := NewClient("db-a", true)
	b := NewClient("db-b", true)

	shared := []domain.TenantUser{{
		UserID:       "user-shared-admin",
		TenantID:     "adeco",
		Email:        "shared.refresh@adeco-retail.com",
		PasswordHash: "old",
		Role:         domain.RoleVendorAdmin,
		Active:       true,
	}}
	a.applyLoadedTenantUsers(shared)
	b.applyLoadedTenantUsers(shared)

	a.persistTenantUserFn = func(ctx context.Context, u domain.TenantUser) error {
		shared = []domain.TenantUser{u}
		return nil
	}
	if err := a.UpdateUserPassword(context.Background(), "user-shared-admin", "new"); err != nil {
		t.Fatal(err)
	}

	// B still has old until refresh.
	old, err := b.GetUserByEmail(context.Background(), "adeco", "shared.refresh@adeco-retail.com")
	if err != nil {
		t.Fatal(err)
	}
	if old.PasswordHash != "old" {
		t.Fatalf("peer should still see old hash before refresh, got %q", old.PasswordHash)
	}

	b.applyLoadedTenantUsers(shared)
	fresh, err := b.GetUserByEmail(context.Background(), "adeco", "shared.refresh@adeco-retail.com")
	if err != nil {
		t.Fatal(err)
	}
	if fresh.PasswordHash != "new" {
		t.Fatalf("after refresh peer must see new hash, got %q", fresh.PasswordHash)
	}
}

func TestRefreshAuthUsersDeactivationConvergence(t *testing.T) {
	a := NewClient("db-a", true)
	b := NewClient("db-b", true)
	shared := []domain.TenantUser{{
		UserID:       "user-shared-deact",
		TenantID:     "adeco",
		Email:        "deact@adeco-retail.com",
		PasswordHash: "x",
		Role:         domain.RoleVendorAdmin,
		Active:       true,
	}}
	a.applyLoadedTenantUsers(shared)
	b.applyLoadedTenantUsers(shared)

	a.persistTenantUserFn = func(ctx context.Context, u domain.TenantUser) error {
		shared = []domain.TenantUser{u}
		return nil
	}
	u := shared[0]
	u.Active = false
	if err := a.SaveUser(context.Background(), &u); err != nil {
		t.Fatal(err)
	}
	b.applyLoadedTenantUsers(shared)
	got, err := b.GetUserByEmail(context.Background(), "adeco", "deact@adeco-retail.com")
	if err != nil {
		t.Fatal(err)
	}
	if got.Active {
		t.Fatal("deactivation must be visible after peer refresh")
	}
}
