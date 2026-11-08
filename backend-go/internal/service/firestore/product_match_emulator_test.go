package firestore

import (
	"context"
	"errors"
	"fmt"
	"os"
	"strings"
	"sync"
	"testing"
	"time"

	cloudFirestore "cloud.google.com/go/firestore"

	"github.com/tashil/data-sharing/backend/internal/service/matcher"
)

// openProductMatchEmulatorClient attaches a real Firestore client (emulator) to a seeded mock Client.
// Skips when FIRESTORE_EMULATOR_HOST is unset (regular unit CI without emulator).
func openProductMatchEmulatorClient(t *testing.T) *Client {
	t.Helper()
	if os.Getenv("FIRESTORE_EMULATOR_HOST") == "" {
		t.Skip("FIRESTORE_EMULATOR_HOST not set")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()
	fs, err := cloudFirestore.NewClient(ctx, "demo-tashil")
	if err != nil {
		t.Fatalf("firestore emulator client: %v", err)
	}
	t.Cleanup(func() { _ = fs.Close() })
	c := NewClient("emulator-db", true)
	c.fsClient = fs
	return c
}

func uniqueTenant(t *testing.T) string {
	t.Helper()
	name := strings.Map(func(r rune) rune {
		if (r >= 'a' && r <= 'z') || (r >= 'A' && r <= 'Z') || (r >= '0' && r <= '9') {
			return r
		}
		return '-'
	}, t.Name())
	return fmt.Sprintf("emu-%d-%s", time.Now().UnixNano(), name)
}

func TestEmulatorDecideParallelOneWinsNoDoubleCount(t *testing.T) {
	c := openProductMatchEmulatorClient(t)
	ctx := context.Background()
	tenant := uniqueTenant(t)
	q := matcher.NewQueue(c)

	item, err := q.EnqueueMatch(ctx, tenant, matcher.Query{SKUName: "صنف-سباق", SourceFile: "e.xlsx"}, matcher.Result{
		Decision: matcher.DecisionNone, ReasonAR: "لا مرشح",
	})
	if err != nil || item == nil {
		t.Fatalf("enqueue: %v %+v", err, item)
	}

	const workers = 20
	var wg sync.WaitGroup
	errs := make(chan error, workers)
	for i := 0; i < workers; i++ {
		wg.Add(1)
		status := matcher.StatusApproved
		if i%2 == 1 {
			status = matcher.StatusRejected
		}
		go func(st string) {
			defer wg.Done()
			_, err := q.Decide(ctx, tenant, item.ID, st, "racer", "بت", "", "", matcher.DecideOptions{})
			errs <- err
		}(status)
	}
	wg.Wait()
	close(errs)

	ok, already, other := 0, 0, 0
	for err := range errs {
		switch {
		case err == nil:
			ok++
		case errors.Is(err, matcher.ErrAlreadyDecided):
			already++
		default:
			other++
			t.Errorf("unexpected decide err: %v", err)
		}
	}
	if ok < 1 {
		t.Fatal("expected at least one successful decide")
	}
	if other != 0 {
		t.Fatalf("unexpected errors: ok=%d already=%d other=%d", ok, already, other)
	}

	got, err := c.GetItem(ctx, tenant, item.ID)
	if err != nil || got == nil {
		t.Fatalf("get: %v %+v", err, got)
	}
	if got.Status != matcher.StatusApproved && got.Status != matcher.StatusRejected {
		t.Fatalf("final status: %s", got.Status)
	}
	m, err := c.GetMetrics(ctx, tenant)
	if err != nil {
		t.Fatal(err)
	}
	if m.Pending != 0 {
		t.Fatalf("pending want 0 got %d", m.Pending)
	}
	if m.Approved+m.Rejected != 1 {
		t.Fatalf("exactly one decision counter: approved=%d rejected=%d", m.Approved, m.Rejected)
	}
	if got.Status == matcher.StatusApproved && m.Approved != 1 {
		t.Fatalf("approved status vs counters: %+v", m)
	}
	if got.Status == matcher.StatusRejected && m.Rejected != 1 {
		t.Fatalf("rejected status vs counters: %+v", m)
	}
}

func TestEmulatorParallelEnqueueNoLostItems(t *testing.T) {
	c := openProductMatchEmulatorClient(t)
	ctx := context.Background()
	tenant := uniqueTenant(t)
	q := matcher.NewQueue(c)

	const n = 30
	var wg sync.WaitGroup
	errs := make(chan error, n)
	for i := 0; i < n; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			item, err := q.EnqueueMatch(ctx, tenant, matcher.Query{
				SKUName: fmt.Sprintf("صنف-متوازي-%d", i), SourceFile: "p.xlsx",
			}, matcher.Result{Decision: matcher.DecisionUncertain, Confidence: 0.6, ReasonAR: "متوسط"})
			if err != nil {
				errs <- err
				return
			}
			if item == nil {
				errs <- fmt.Errorf("nil item for %d", i)
			}
		}(i)
	}
	wg.Wait()
	close(errs)
	for err := range errs {
		t.Fatalf("enqueue: %v", err)
	}

	list, err := q.List(ctx, tenant, matcher.StatusPending)
	if err != nil {
		t.Fatal(err)
	}
	if len(list) != n {
		t.Fatalf("lost enqueues: want %d pending got %d", n, len(list))
	}
	m, err := q.Snapshot(ctx, tenant)
	if err != nil {
		t.Fatal(err)
	}
	if m.Pending != n || m.Queued != n || m.TotalMatched != n {
		t.Fatalf("counters: %+v", m)
	}
}

func TestEmulatorRestartPersistence(t *testing.T) {
	c1 := openProductMatchEmulatorClient(t)
	ctx := context.Background()
	tenant := uniqueTenant(t)
	q1 := matcher.NewQueue(c1)

	item, err := q1.EnqueueMatch(ctx, tenant, matcher.Query{SKUName: "صنف-دائم", SourceFile: "r.xlsx"}, matcher.Result{
		Decision: matcher.DecisionNone, ReasonAR: "لا",
	})
	if err != nil || item == nil {
		t.Fatalf("enqueue: %v %+v", err, item)
	}
	if _, err := q1.Decide(ctx, tenant, item.ID, matcher.StatusRejected, "admin", "رفض", "", "", matcher.DecideOptions{}); err != nil {
		t.Fatal(err)
	}

	// New Client + Queue = Cloud Run restart; same emulator Firestore.
	c2 := openProductMatchEmulatorClient(t)
	c2.fsClient = c1.fsClient
	q2 := matcher.NewQueue(c2)
	list, err := q2.List(ctx, tenant, matcher.StatusRejected)
	if err != nil {
		t.Fatal(err)
	}
	if len(list) != 1 || list[0].ID != item.ID {
		t.Fatalf("decision must survive restart: %+v", list)
	}
	m, err := q2.Snapshot(ctx, tenant)
	if err != nil || m.Rejected != 1 || m.Pending != 0 {
		t.Fatalf("metrics after restart: %+v err=%v", m, err)
	}
}

func TestEmulatorDecideThenEnqueueSameTxnPath(t *testing.T) {
	// Ensures write-then-Increment (no counter read) works for both Decide and multi-item Enqueue.
	c := openProductMatchEmulatorClient(t)
	ctx := context.Background()
	tenant := uniqueTenant(t)
	q := matcher.NewQueue(c)

	ops := make([]matcher.EnqueueOp, 0, 5)
	for i := 0; i < 5; i++ {
		ops = append(ops, matcher.EnqueueOp{
			ItemID: fmt.Sprintf("batch-%d", i), NeedsReview: true,
			Query:  matcher.Query{SKUName: fmt.Sprintf("ب-%d", i)},
			Result: matcher.Result{Decision: matcher.DecisionNone, ReasonAR: "x"},
			Delta:  matcher.MetricsDelta{TotalMatched: 1, None: 1, Queued: 1, Pending: 1},
		})
	}
	items, err := c.EnqueueBatch(ctx, tenant, ops)
	if err != nil || len(items) != 5 {
		t.Fatalf("batch enqueue: %v len=%d", err, len(items))
	}
	decided, err := q.Decide(ctx, tenant, items[0].ID, matcher.StatusApproved, "a", "ok", "", "", matcher.DecideOptions{})
	if err != nil || decided.Status != matcher.StatusApproved {
		t.Fatalf("decide: %v %+v", err, decided)
	}
	m, err := c.GetMetrics(ctx, tenant)
	if err != nil {
		t.Fatal(err)
	}
	if m.Approved != 1 || m.Pending != 4 || m.TotalMatched != 5 {
		t.Fatalf("counters after decide+batch: %+v", m)
	}
}
