package firestore

import (
	"context"
	"testing"
	"time"
)

func TestLeaseSingleHolderAndExpiry(t *testing.T) {
	c := NewClient("db", true)
	ctx := context.Background()
	if ok, err := c.TryAcquireLease(ctx, "archive-sync", "a", time.Hour); err != nil || !ok {
		t.Fatalf("first acquire: %v %v", ok, err)
	}
	if ok, _ := c.TryAcquireLease(ctx, "archive-sync", "b", time.Hour); ok {
		t.Fatal("second holder must not acquire a live lease")
	}
	if ok, _ := c.TryAcquireLease(ctx, "archive-sync", "a", time.Hour); !ok {
		t.Fatal("holder must be able to renew")
	}
	_ = c.ReleaseLease(ctx, "archive-sync", "b") // not the holder: no-op
	if ok, _ := c.TryAcquireLease(ctx, "archive-sync", "b", time.Hour); ok {
		t.Fatal("release by a non-holder must not free the lease")
	}
	_ = c.ReleaseLease(ctx, "archive-sync", "a")
	if ok, _ := c.TryAcquireLease(ctx, "archive-sync", "b", time.Nanosecond); !ok {
		t.Fatal("released lease must be free")
	}
	time.Sleep(2 * time.Millisecond)
	if ok, _ := c.TryAcquireLease(ctx, "archive-sync", "c", time.Hour); !ok {
		t.Fatal("expired lease must be free")
	}
}
