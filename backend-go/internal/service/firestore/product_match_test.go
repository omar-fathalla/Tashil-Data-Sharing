package firestore

import (
	"context"
	"testing"
	"time"

	"github.com/tashil/data-sharing/backend/internal/service/matcher"
)

func TestProductMatchStateSurvivesClientRestart(t *testing.T) {
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

	q2 := matcher.NewQueue(c)
	list, err := q2.List(ctx, "tenant-adeco", matcher.StatusRejected)
	if err != nil || len(list) != 1 || list[0].ID != item.ID {
		t.Fatalf("persist via firestore mock: %v %+v", err, list)
	}

	other, err := q2.List(ctx, "tenant-pepsi", matcher.StatusRejected)
	if err != nil || len(other) != 0 {
		t.Fatalf("tenant isolation: %v %+v", err, other)
	}
}

func TestProductMatchGetEmptyMetrics(t *testing.T) {
	c := NewClient("test-db", true)
	m, err := c.GetMetrics(context.Background(), "tenant-newco")
	if err != nil || m.TenantID != "newco" {
		t.Fatalf("%+v %v", m, err)
	}
	it, err := c.GetItem(context.Background(), "tenant-newco", "missing")
	if err != nil || it != nil {
		t.Fatalf("%+v %v", it, err)
	}
}

func TestProductMatchDecideIdempotentOnClient(t *testing.T) {
	c := NewClient("test-db", true)
	ctx := context.Background()
	now := time.Now().UTC()
	_, err := c.EnqueueBatch(ctx, "tenant-adeco", []matcher.EnqueueOp{{
		ItemID: "item1", NeedsReview: true,
		Query: matcher.Query{SKUName: "x"}, Result: matcher.Result{Decision: matcher.DecisionNone},
		Delta: matcher.MetricsDelta{TotalMatched: 1, None: 1, Queued: 1, Pending: 1},
	}})
	if err != nil {
		t.Fatal(err)
	}
	a, err := c.DecideItem(ctx, "tenant-adeco", matcher.DecidePatch{ID: "item1", Status: matcher.StatusApproved, DecidedBy: "a", Now: now})
	if err != nil || a.Status != matcher.StatusApproved {
		t.Fatalf("%v %+v", err, a)
	}
	b, err := c.DecideItem(ctx, "tenant-adeco", matcher.DecidePatch{ID: "item1", Status: matcher.StatusApproved, DecidedBy: "a", Now: now})
	if err != nil || b.Status != matcher.StatusApproved {
		t.Fatalf("idempotent: %v %+v", err, b)
	}
	m, _ := c.GetMetrics(ctx, "tenant-adeco")
	if m.Approved != 1 || m.Pending != 0 {
		t.Fatalf("counters: %+v", m)
	}
}
