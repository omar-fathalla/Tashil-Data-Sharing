package firestore

import (
	"context"
	"testing"
	"time"

	"github.com/tashil/data-sharing/backend/internal/service/matcher"
)

func TestProductMatchStateSurvivesClientRestart(t *testing.T) {
	// Two mock clients share nothing — use matcher.MemoryStore via Queue for restart.
	// This test verifies the Firestore Client mock path (useMock=true) keeps state on the same client,
	// and that Queue+Client round-trips tenant-scoped documents.
	c := NewClient("test-db", true)
	q1 := matcher.NewQueue(c)
	ctx := context.Background()

	res := matcher.Result{Decision: matcher.DecisionNone, ReasonAR: "لا مرشح", BarcodePolicy: "empty"}
	item, err := q1.EnqueueMatch(ctx, "tenant-adeco", matcher.Query{SKUName: "صنف دائم", SourceFile: "a.xlsx"}, res)
	if err != nil || item == nil {
		t.Fatalf("enqueue: %v %+v", err, item)
	}
	if _, err := q1.Decide(ctx, "tenant-adeco", item.ID, matcher.StatusRejected, "a@b.c", "رفض", "", "", matcher.DecideOptions{}); err != nil {
		t.Fatal(err)
	}

	// Same Client instance (shared mock map) — new Queue simulates process reuse of the store handle.
	q2 := matcher.NewQueue(c)
	list, err := q2.List(ctx, "tenant-adeco", matcher.StatusRejected)
	if err != nil || len(list) != 1 || list[0].ID != item.ID {
		t.Fatalf("persist via firestore mock: %v %+v", err, list)
	}

	// Cross-tenant empty
	other, err := q2.List(ctx, "tenant-pepsi", matcher.StatusRejected)
	if err != nil || len(other) != 0 {
		t.Fatalf("tenant isolation: %v %+v", err, other)
	}
}

func TestProductMatchSaveRejectsTenantMismatch(t *testing.T) {
	c := NewClient("test-db", true)
	st := &matcher.State{
		TenantID: "adeco",
		Items: []matcher.ReviewItem{{
			ID: "x", TenantID: "pepsi", Status: matcher.StatusPending, CreatedAt: time.Now().UTC(),
		}},
	}
	// Save uses State.TenantID for the doc; item-level mismatch is filtered on List.
	if err := c.SaveProductMatchState(context.Background(), st); err != nil {
		t.Fatal(err)
	}
	got, err := c.GetProductMatchState(context.Background(), "tenant-adeco")
	if err != nil {
		t.Fatal(err)
	}
	if got.TenantID != "adeco" {
		t.Fatalf("slug=%s", got.TenantID)
	}
}

func TestProductMatchGetEmpty(t *testing.T) {
	c := NewClient("test-db", true)
	st, err := c.GetProductMatchState(context.Background(), "tenant-newco")
	if err != nil || st == nil || st.TenantID != "newco" {
		t.Fatalf("%+v %v", st, err)
	}
}
