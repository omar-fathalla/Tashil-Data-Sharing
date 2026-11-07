package firestore

import (
	"testing"

	"github.com/tashil/data-sharing/backend/internal/domain"
)

func TestMergeFirestoreUserKeepsSeedHashWhenFSEmpty(t *testing.T) {
	seed := domain.TenantUser{
		UserID:       "user-adeco-admin-01",
		TenantID:     "adeco",
		Email:        "admin@adeco-retail.com",
		PasswordHash: "seed-hash",
		Role:         domain.RoleVendorAdmin,
		Active:       true,
	}
	fromFS := domain.TenantUser{
		UserID:       "user-adeco-admin-01",
		TenantID:     "adeco",
		Email:        "admin@adeco-retail.com",
		PasswordHash: "",
		Role:         domain.RoleVendorAdmin,
		Active:       true,
	}
	got := mergeFirestoreUser(seed, true, fromFS)
	if got.PasswordHash != "seed-hash" {
		t.Fatalf("expected seed hash retained, got %q", got.PasswordHash)
	}
}

func TestMergeFirestoreUserPrefersFirestoreHash(t *testing.T) {
	seed := domain.TenantUser{
		UserID:       "user-adeco-admin-01",
		PasswordHash: "seed-hash",
	}
	fromFS := domain.TenantUser{
		UserID:       "user-adeco-admin-01",
		Email:        "admin@adeco-retail.com",
		PasswordHash: "changed-hash",
		TenantID:     "adeco",
		Role:         domain.RoleVendorAdmin,
		Active:       true,
	}
	got := mergeFirestoreUser(seed, true, fromFS)
	if got.PasswordHash != "changed-hash" {
		t.Fatalf("expected Firestore hash to win, got %q", got.PasswordHash)
	}
}

func TestGetUserByEmailAfterOverlay(t *testing.T) {
	c := NewClient("db", true)
	c.mu.Lock()
	c.users["user-adeco-admin-01"] = domain.TenantUser{
		UserID:       "user-adeco-admin-01",
		TenantID:     "adeco",
		Email:        "admin@adeco-retail.com",
		PasswordHash: "changed-after-login",
		Role:         domain.RoleVendorAdmin,
		Active:       true,
	}
	c.mu.Unlock()

	u, err := c.GetUserByEmail(t.Context(), "adeco", "admin@adeco-retail.com")
	if err != nil {
		t.Fatal(err)
	}
	if u.PasswordHash != "changed-after-login" {
		t.Fatalf("overlay hash not visible to login lookup: %q", u.PasswordHash)
	}
}
