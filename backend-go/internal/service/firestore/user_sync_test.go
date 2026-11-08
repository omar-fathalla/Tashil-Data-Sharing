package firestore

import (
	"context"
	"errors"
	"testing"

	"github.com/tashil/data-sharing/backend/internal/domain"
)

func TestPreferAuthUserActiveWins(t *testing.T) {
	a := domain.TenantUser{UserID: "a", Active: false}
	b := domain.TenantUser{UserID: "b", Active: true}
	got := preferAuthUser(a, b)
	if got.UserID != "b" {
		t.Fatalf("want active user b, got %s", got.UserID)
	}
}

func TestPreferAuthUserStableID(t *testing.T) {
	a := domain.TenantUser{UserID: "user-z", Active: true}
	b := domain.TenantUser{UserID: "user-a", Active: true}
	got := preferAuthUser(a, b)
	if got.UserID != "user-a" {
		t.Fatalf("want lexicographically smaller id, got %s", got.UserID)
	}
}

func TestIsReservedAuthUserID(t *testing.T) {
	if !isReservedAuthUserID("user-super-admin") || !isReservedAuthUserID("User-Super-Admin") {
		t.Fatal("expected reserved id match")
	}
	if isReservedAuthUserID("user-adeco-admin-01") {
		t.Fatal("tenant admin must not be reserved")
	}
}

func TestApplyLoadedTenantUsersEmptyKeepsSeeds(t *testing.T) {
	c := NewClient("db", true)
	if err := c.AuthReady(); err != nil {
		t.Fatal(err)
	}
	before, err := c.GetUserByEmail(context.Background(), "adeco", "admin@adeco-retail.com")
	if err != nil {
		t.Fatal(err)
	}
	c.applyLoadedTenantUsers(nil)
	after, err := c.GetUserByEmail(context.Background(), "adeco", "admin@adeco-retail.com")
	if err != nil {
		t.Fatal(err)
	}
	if before.UserID != after.UserID {
		t.Fatalf("seed user changed on empty FS read: %s -> %s", before.UserID, after.UserID)
	}
}

func TestApplyLoadedTenantUsersNonEmptyReplacesSeeds(t *testing.T) {
	c := NewClient("db", true)
	c.applyLoadedTenantUsers([]domain.TenantUser{{
		UserID:       "user-fs-only",
		TenantID:     "adeco",
		Email:        "fs.admin@adeco-retail.com",
		PasswordHash: "fs-hash",
		Role:         domain.RoleVendorAdmin,
		Active:       true,
	}})

	if _, err := c.GetUserByEmail(context.Background(), "adeco", "admin@adeco-retail.com"); err == nil {
		t.Fatal("seed-only user must be removed when Firestore has users")
	}
	u, err := c.GetUserByEmail(context.Background(), "adeco", "fs.admin@adeco-retail.com")
	if err != nil {
		t.Fatal(err)
	}
	if u.PasswordHash != "fs-hash" {
		t.Fatalf("unexpected hash %q", u.PasswordHash)
	}
	// Super admin remains.
	c.mu.RLock()
	_, ok := c.users[reservedSuperAdminUserID]
	c.mu.RUnlock()
	if !ok {
		t.Fatal("super-admin must survive Firestore hydration")
	}
}

func TestApplyLoadedTenantUsersSkipsReservedAndDedupes(t *testing.T) {
	c := NewClient("db", true)
	c.applyLoadedTenantUsers([]domain.TenantUser{
		{
			UserID:   reservedSuperAdminUserID,
			TenantID: "system",
			Email:    "evil@example.com",
			Role:     domain.RoleVendorAdmin,
			Active:   true,
		},
		{
			UserID:       "user-dup-b",
			TenantID:     "adeco",
			Email:        "dup@adeco-retail.com",
			PasswordHash: "b",
			Role:         domain.RoleVendorAdmin,
			Active:       false,
		},
		{
			UserID:       "user-dup-a",
			TenantID:     "adeco",
			Email:        "dup@adeco-retail.com",
			PasswordHash: "a",
			Role:         domain.RoleVendorAdmin,
			Active:       true,
		},
	})

	c.mu.RLock()
	super := c.users[reservedSuperAdminUserID]
	c.mu.RUnlock()
	if super.Email == "evil@example.com" {
		t.Fatal("firestore must not overwrite reserved super-admin")
	}

	u, err := c.GetUserByEmail(context.Background(), "adeco", "dup@adeco-retail.com")
	if err != nil {
		t.Fatal(err)
	}
	if u.UserID != "user-dup-a" || !u.Active {
		t.Fatalf("expected active duplicate winner user-dup-a, got %+v", u)
	}
	// Flaky map iteration must not surface the inactive twin.
	for i := 0; i < 20; i++ {
		got, err := c.GetUserByEmail(context.Background(), "adeco", "dup@adeco-retail.com")
		if err != nil || got.UserID != "user-dup-a" {
			t.Fatalf("flappy duplicate lookup on iter %d: %+v err=%v", i, got, err)
		}
	}
}

func TestApplyLoadedTenantUsersEmptyHashDoesNotKeepSeed(t *testing.T) {
	c := NewClient("db", true)
	c.applyLoadedTenantUsers([]domain.TenantUser{{
		UserID:       "user-adeco-admin-01",
		TenantID:     "adeco",
		Email:        "admin@adeco-retail.com",
		PasswordHash: "",
		Role:         domain.RoleVendorAdmin,
		Active:       true,
	}})
	u, err := c.GetUserByEmail(context.Background(), "adeco", "admin@adeco-retail.com")
	if err != nil {
		t.Fatal(err)
	}
	if u.PasswordHash != "" {
		t.Fatalf("empty FS hash must not fall back to seed hash, got %q", u.PasswordHash)
	}
}

func TestTenantIsolationOnLoginLookup(t *testing.T) {
	c := NewClient("db", true)
	c.applyLoadedTenantUsers([]domain.TenantUser{
		{
			UserID:       "user-adeco",
			TenantID:     "adeco",
			Email:        "shared@example.com",
			PasswordHash: "a",
			Role:         domain.RoleVendorAdmin,
			Active:       true,
		},
		{
			UserID:       "user-unilever",
			TenantID:     "unilever",
			Email:        "shared@example.com",
			PasswordHash: "u",
			Role:         domain.RoleVendorAdmin,
			Active:       true,
		},
	})
	a, err := c.GetUserByEmail(context.Background(), "adeco", "shared@example.com")
	if err != nil || a.UserID != "user-adeco" {
		t.Fatalf("adeco lookup: %+v err=%v", a, err)
	}
	u, err := c.GetUserByEmail(context.Background(), "unilever", "shared@example.com")
	if err != nil || u.UserID != "user-unilever" {
		t.Fatalf("unilever lookup: %+v err=%v", u, err)
	}
}

func TestDeactivatedUserStillResolvesForHandlerGate(t *testing.T) {
	c := NewClient("db", true)
	c.applyLoadedTenantUsers([]domain.TenantUser{{
		UserID:       "user-inactive",
		TenantID:     "adeco",
		Email:        "inactive@adeco-retail.com",
		PasswordHash: "x",
		Role:         domain.RoleVendorAdmin,
		Active:       false,
	}})
	u, err := c.GetUserByEmail(context.Background(), "adeco", "inactive@adeco-retail.com")
	if err != nil {
		t.Fatal(err)
	}
	if u.Active {
		t.Fatal("expected inactive flag preserved")
	}
}

func TestMarkAuthLoadFailedBlocksLoginLookup(t *testing.T) {
	c := NewClient("db", true)
	c.markAuthLoadFailed(errors.New("simulated timeout"))
	if err := c.AuthReady(); err == nil {
		t.Fatal("expected AuthReady error")
	}
	if _, err := c.GetUserByEmail(context.Background(), "adeco", "admin@adeco-retail.com"); err == nil {
		t.Fatal("login lookup must fail when auth is not ready")
	}
	c.mu.RLock()
	_, hasSeed := c.users["user-adeco-admin-01"]
	_, hasSuper := c.users[reservedSuperAdminUserID]
	c.mu.RUnlock()
	if hasSeed {
		t.Fatal("failed hydration must strip seed users")
	}
	if !hasSuper {
		t.Fatal("failed hydration must keep reserved super-admin")
	}
}

func TestHealthzWithAuthReflectsReadiness(t *testing.T) {
	// Imported via handlers in a sibling test; keep firestore-level coverage here.
	c := NewClient("db", true)
	if err := c.AuthReady(); err != nil {
		t.Fatal(err)
	}
	c.markAuthLoadFailed(errors.New("boom"))
	if err := c.AuthReady(); err == nil {
		t.Fatal("expected not ready")
	}
}
