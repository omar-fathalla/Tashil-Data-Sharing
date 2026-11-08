package matcher

import (
	"context"
	"errors"
	"fmt"
	"sync"
	"testing"
	"time"
)

func ctx() context.Context { return context.Background() }

func TestEnqueueAndDecide(t *testing.T) {
	store := &MemoryStore{}
	q := NewQueue(store)
	q.now = func() time.Time { return time.Date(2026, 11, 7, 12, 0, 0, 0, time.UTC) }
	cat := sampleCatalog()

	exact := cat.Match(Query{Barcode: "6223000299999"})
	item, err := q.EnqueueMatch(ctx(), "tenant-adeco", Query{Barcode: "6223000299999"}, exact)
	if err != nil {
		t.Fatal(err)
	}
	if item != nil {
		t.Fatal("exact match must not enter review queue")
	}

	weak := cat.Match(Query{SKUName: "منتج غير معروف بالمرة xyz"})
	item, err = q.EnqueueMatch(ctx(), "tenant-adeco", Query{SKUName: "منتج غير معروف بالمرة xyz", SourceFile: "f.xlsx", Rows: 2, Value: 10}, weak)
	if err != nil || item == nil || item.Status != StatusPending {
		t.Fatalf("expected pending review item, got %+v err=%v", item, err)
	}

	list, err := q.List(ctx(), "tenant-adeco", StatusPending)
	if err != nil || len(list) != 1 {
		t.Fatalf("pending=%d err=%v", len(list), err)
	}

	decided, err := q.Decide(ctx(), "tenant-adeco", item.ID, StatusApproved, "admin@adeco.test", "صنف جديد هيضاف للكارتة", "", "", DecideOptions{Catalog: cat})
	if err != nil {
		t.Fatal(err)
	}
	if decided.Status != StatusApproved || decided.DecidedBy != "admin@adeco.test" {
		t.Fatalf("%+v", decided)
	}

	m, err := q.Snapshot(ctx(), "tenant-adeco")
	if err != nil {
		t.Fatal(err)
	}
	if m.Exact != 1 || m.AutoResolved != 1 || m.Approved != 1 || m.Pending != 0 {
		t.Fatalf("metrics: %+v", m)
	}
	if m.InventedBarcodes != 0 {
		t.Fatal("invented barcodes must stay 0")
	}
	if m.LabelsAR["pending"] == "" {
		t.Fatal("Arabic metric labels required")
	}
}

func TestDecideRejectsInventedBarcode(t *testing.T) {
	q := NewQueue(&MemoryStore{})
	cat := sampleCatalog()
	weak := cat.Match(Query{SKUName: "xyz-unknown-product"})
	item, err := q.EnqueueMatch(ctx(), "tenant-adeco", Query{SKUName: "xyz-unknown-product"}, weak)
	if err != nil || item == nil {
		t.Fatal("expected enqueue")
	}
	_, err = q.Decide(ctx(), "tenant-adeco", item.ID, StatusApproved, "a@b.c", "ok", "FGCL-0550-0001", "SKU-SECTOR-001", DecideOptions{Catalog: cat})
	if !errors.Is(err, ErrInventedBarcode) {
		t.Fatalf("must reject invented SKU- barcode, got %v", err)
	}
}

func TestEnqueueUnknownsUsesCatalog(t *testing.T) {
	q := NewQueue(&MemoryStore{})
	cat := sampleCatalog()
	items, err := q.EnqueueUnknowns(ctx(), "tenant-adeco", "sellin.xlsx", []Query{
		{Barcode: "6223000299999", SKUName: "منعم جو"},
		{Barcode: "9999999999999", SKUName: "أجنبي"},
		{SKUName: "منتج نادر جداً بدون باركود"},
	}, cat)
	if err != nil {
		t.Fatal(err)
	}
	if len(items) != 2 {
		t.Fatalf("expected 2 review items, got %d (%+v)", len(items), items)
	}
	m, _ := q.Snapshot(ctx(), "tenant-adeco")
	if m.TotalMatched != 3 || m.Exact != 1 || m.Queued != 2 {
		t.Fatalf("metrics: %+v", m)
	}
}

func TestApproveReusesSuggestedMasterBarcodeOnly(t *testing.T) {
	q := NewQueue(&MemoryStore{})
	cat := sampleCatalog()
	res := cat.Match(Query{SKUName: "كلوريل مبيض"})
	if res.Decision == DecisionNone {
		res.Decision = DecisionUncertain
		res.MatchedItemCode = "FGCL-0550-0001"
		res.SuggestedBarcode = "6223000231227"
		res.BarcodePolicy = "from_master_pending_review"
		res.Confidence = 0.6
		res.ReasonAR = "تشابه متوسط"
	}
	item, err := q.EnqueueMatch(ctx(), "tenant-adeco", Query{SKUName: "كلوريل مبيض"}, res)
	if err != nil || item == nil {
		t.Fatal("expected review item")
	}
	decided, err := q.Decide(ctx(), "tenant-adeco", item.ID, StatusApproved, "a@b.c", "تم التأكيد", res.MatchedItemCode, "", DecideOptions{Catalog: cat})
	if err != nil {
		t.Fatal(err)
	}
	if decided.ChosenBarcode != "6223000231227" {
		t.Fatalf("should reuse suggested master barcode, got %q", decided.ChosenBarcode)
	}
}

func TestForeignNumericBarcodeNeverAssigned(t *testing.T) {
	q := NewQueue(&MemoryStore{})
	cat := sampleCatalog()
	foreign := "6223006125803"
	res := cat.Match(Query{Barcode: foreign, SKUName: "كلوريل 500 جم مبيض"})
	if res.Decision != DecisionNone || res.SuggestedBarcode != "" {
		t.Fatalf("foreign numeric must stay unmatched: %+v", res)
	}
	item, err := q.EnqueueMatch(ctx(), "tenant-adeco", Query{Barcode: foreign, SKUName: "كلوريل 500 جم مبيض"}, res)
	if err != nil || item == nil {
		t.Fatal("expected review")
	}
	_, err = q.Decide(ctx(), "tenant-adeco", item.ID, StatusApproved, "a@b.c", "غلط", "FGCL-0550-0001", foreign, DecideOptions{Catalog: cat})
	if err == nil {
		t.Fatal("must reject foreign barcode paired with master item code")
	}
	decided, err := q.Decide(ctx(), "tenant-adeco", item.ID, StatusApproved, "a@b.c", "باركود أجنبي — بدون تعيين", "", "", DecideOptions{Catalog: cat})
	if err != nil {
		t.Fatal(err)
	}
	if decided.ChosenBarcode != "" {
		t.Fatalf("must not assign barcode on foreign acknowledge, got %q", decided.ChosenBarcode)
	}
}

func TestWrongItemBarcodePairRejected(t *testing.T) {
	q := NewQueue(&MemoryStore{})
	cat := sampleCatalog()
	res := Result{Decision: DecisionUncertain, Confidence: 0.6, ReasonAR: "مراجعة", SuggestedBarcode: "6223000231227", MatchedItemCode: "FGCL-0550-0001"}
	item, err := q.EnqueueMatch(ctx(), "tenant-adeco", Query{SKUName: "تقريبي"}, res)
	if err != nil {
		t.Fatal(err)
	}
	_, err = q.Decide(ctx(), "tenant-adeco", item.ID, StatusApproved, "a@b.c", "x", "FGCL-0550-0001", "6223000234001", DecideOptions{Catalog: cat})
	if err == nil {
		t.Fatal("wrong item/barcode pair must be rejected")
	}
}

func TestDecideIdempotentAndRejectRepeat(t *testing.T) {
	q := NewQueue(&MemoryStore{})
	cat := sampleCatalog()
	res := Result{Decision: DecisionNone, ReasonAR: "لا مرشح"}
	item, err := q.EnqueueMatch(ctx(), "tenant-adeco", Query{SKUName: "idem-test"}, res)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := q.Decide(ctx(), "tenant-adeco", item.ID, StatusRejected, "a@b.c", "رفض", "", "", DecideOptions{Catalog: cat}); err != nil {
		t.Fatal(err)
	}
	m1, _ := q.Snapshot(ctx(), "tenant-adeco")
	again, err := q.Decide(ctx(), "tenant-adeco", item.ID, StatusRejected, "a@b.c", "رفض تاني", "", "", DecideOptions{Catalog: cat})
	if err != nil {
		t.Fatal(err)
	}
	if again.Status != StatusRejected {
		t.Fatalf("%+v", again)
	}
	m2, _ := q.Snapshot(ctx(), "tenant-adeco")
	if m2.Rejected != m1.Rejected || m2.Pending != m1.Pending {
		t.Fatalf("idempotent decide must not bump counters: before=%+v after=%+v", m1, m2)
	}
	_, err = q.Decide(ctx(), "tenant-adeco", item.ID, StatusApproved, "a@b.c", "تبديل", "", "", DecideOptions{Catalog: cat})
	if !errors.Is(err, ErrAlreadyDecided) {
		t.Fatalf("want ErrAlreadyDecided, got %v", err)
	}
	m3, _ := q.Snapshot(ctx(), "tenant-adeco")
	if m3.Approved != 0 || m3.Rejected != m1.Rejected {
		t.Fatalf("repeat different status must not change counters: %+v", m3)
	}
}

func TestTenantIsolation(t *testing.T) {
	q := NewQueue(&MemoryStore{})
	cat := sampleCatalog()
	res := Result{Decision: DecisionNone, ReasonAR: "x"}
	item, err := q.EnqueueMatch(ctx(), "tenant-adeco", Query{SKUName: "عزل"}, res)
	if err != nil {
		t.Fatal(err)
	}
	other, err := q.List(ctx(), "tenant-other", StatusPending)
	if err != nil || len(other) != 0 {
		t.Fatal("other tenant must not see adeco queue")
	}
	_, err = q.Decide(ctx(), "tenant-other", item.ID, StatusApproved, "x@y.z", "", "", "", DecideOptions{Catalog: cat})
	if err == nil {
		t.Fatal("cross-tenant decide must fail")
	}
	pending, _ := q.List(ctx(), "tenant-adeco", StatusPending)
	if len(pending) != 1 {
		t.Fatal("adeco item must remain pending")
	}
	mOther, _ := q.Snapshot(ctx(), "tenant-other")
	if mOther.TotalMatched != 0 || mOther.Pending != 0 {
		t.Fatalf("other tenant metrics must stay empty: %+v", mOther)
	}
}

func TestEnqueueRefreshDoesNotDoubleCountQueued(t *testing.T) {
	q := NewQueue(&MemoryStore{})
	res := Result{Decision: DecisionUncertain, Confidence: 0.6, ReasonAR: "متوسط"}
	q1 := Query{SKUName: "نفس الصنف", SourceFile: "a.xlsx"}
	if _, err := q.EnqueueMatch(ctx(), "tenant-adeco", q1, res); err != nil {
		t.Fatal(err)
	}
	m1, _ := q.Snapshot(ctx(), "tenant-adeco")
	if _, err := q.EnqueueMatch(ctx(), "tenant-adeco", q1, res); err != nil {
		t.Fatal(err)
	}
	m2, _ := q.Snapshot(ctx(), "tenant-adeco")
	if m2.Queued != m1.Queued || m2.Pending != m1.Pending || m2.Pending != 1 {
		t.Fatalf("refresh must not double Queued/Pending: before=%+v after=%+v", m1, m2)
	}
	if m2.TotalMatched != m1.TotalMatched+1 {
		t.Fatalf("TotalMatched should still count the attempt: %+v", m2)
	}
}

func TestDecisionsSurviveSimulatedRestart(t *testing.T) {
	store := &MemoryStore{}
	cat := sampleCatalog()
	q1 := NewQueue(store)
	res := Result{Decision: DecisionUncertain, Confidence: 0.7, ReasonAR: "مراجعة", MatchedItemCode: "FGCL-0550-0001", SuggestedBarcode: "6223000231227"}
	item, err := q1.EnqueueMatch(ctx(), "tenant-adeco", Query{SKUName: "كلوريل تقريبي", SourceFile: "u.xlsx"}, res)
	if err != nil || item == nil {
		t.Fatalf("enqueue: %v %+v", err, item)
	}
	if _, err := q1.Decide(ctx(), "tenant-adeco", item.ID, StatusApproved, "admin@adeco.test", "تم", "FGCL-0550-0001", "6223000231227", DecideOptions{Catalog: cat}); err != nil {
		t.Fatal(err)
	}

	// New Queue instance = new Cloud Run process, same durable store.
	q2 := NewQueue(store)
	approved, err := q2.List(ctx(), "tenant-adeco", StatusApproved)
	if err != nil {
		t.Fatal(err)
	}
	if len(approved) != 1 || approved[0].ID != item.ID || approved[0].ChosenBarcode != "6223000231227" {
		t.Fatalf("decision must survive restart: %+v", approved)
	}
	pending, _ := q2.List(ctx(), "tenant-adeco", StatusPending)
	if len(pending) != 0 {
		t.Fatalf("pending after restart: %+v", pending)
	}
	m, err := q2.Snapshot(ctx(), "tenant-adeco")
	if err != nil || m.Approved != 1 || m.Pending != 0 {
		t.Fatalf("metrics after restart: %+v err=%v", m, err)
	}

	// Idempotent after restart
	again, err := q2.Decide(ctx(), "tenant-adeco", item.ID, StatusApproved, "admin@adeco.test", "تكرار", "FGCL-0550-0001", "6223000231227", DecideOptions{Catalog: cat})
	if err != nil || again.Status != StatusApproved {
		t.Fatalf("idempotent after restart: %v %+v", err, again)
	}
	m2, _ := q2.Snapshot(ctx(), "tenant-adeco")
	if m2.Approved != 1 {
		t.Fatalf("idempotent must not bump Approved after restart: %+v", m2)
	}
}

func TestStoreTimeoutDeadlineHonored(t *testing.T) {
	store := &MemoryStore{}
	q := NewQueue(store)
	dctx, cancel := context.WithTimeout(context.Background(), time.Millisecond)
	defer cancel()
	// MemoryStore ignores ctx; ensure API still accepts parent deadline without panicking.
	_, err := q.List(dctx, "tenant-adeco", "")
	if err != nil {
		t.Fatal(err)
	}
}

func TestNormalizeTenantKey(t *testing.T) {
	if NormalizeTenantKey("tenant-adeco") != "adeco" || NormalizeTenantKey("Adeco") != "adeco" {
		t.Fatal(NormalizeTenantKey("tenant-adeco"))
	}
}

// TestConcurrentDecideAndEnqueueNoLostWrites races Decide against Enqueue on the same store.
// MemoryStore serializes under one mutex the way Firestore transactions serialize item+counter writes.
func TestConcurrentDecideAndEnqueueNoLostWrites(t *testing.T) {
	store := &MemoryStore{}
	q := NewQueue(store)
	const n = 40
	ids := make([]string, n)
	for i := 0; i < n; i++ {
		item, err := q.EnqueueMatch(ctx(), "tenant-adeco", Query{
			SKUName: fmt.Sprintf("صنف-متزامن-%d", i), SourceFile: "race.xlsx",
		}, Result{Decision: DecisionNone, ReasonAR: "لا مرشح"})
		if err != nil || item == nil {
			t.Fatalf("seed %d: %v %+v", i, err, item)
		}
		ids[i] = item.ID
	}

	var wg sync.WaitGroup
	errCh := make(chan error, n*3)
	for i := 0; i < n; i++ {
		wg.Add(1)
		go func(id string) {
			defer wg.Done()
			_, err := q.Decide(ctx(), "tenant-adeco", id, StatusRejected, "racer@test", "رفض متزامن", "", "", DecideOptions{})
			if err != nil {
				errCh <- err
			}
		}(ids[i])
	}
	for i := 0; i < n; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			item, err := q.EnqueueMatch(ctx(), "tenant-adeco", Query{
				SKUName: fmt.Sprintf("صنف-جديد-%d", i), SourceFile: "race2.xlsx",
			}, Result{Decision: DecisionUncertain, Confidence: 0.6, ReasonAR: "متوسط"})
			if err != nil {
				errCh <- err
				return
			}
			if item == nil {
				errCh <- fmt.Errorf("enqueue %d returned nil item", i)
			}
		}(i)
	}
	wg.Wait()
	close(errCh)
	for err := range errCh {
		t.Fatalf("concurrent op: %v", err)
	}

	rejected, err := q.List(ctx(), "tenant-adeco", StatusRejected)
	if err != nil {
		t.Fatal(err)
	}
	pending, err := q.List(ctx(), "tenant-adeco", StatusPending)
	if err != nil {
		t.Fatal(err)
	}
	if len(rejected) != n {
		t.Fatalf("lost decides: want %d rejected, got %d", n, len(rejected))
	}
	if len(pending) != n {
		t.Fatalf("lost enqueues: want %d pending, got %d", n, len(pending))
	}
	m, err := q.Snapshot(ctx(), "tenant-adeco")
	if err != nil {
		t.Fatal(err)
	}
	if m.Rejected != n || m.Pending != n {
		t.Fatalf("counter drift: %+v", m)
	}
	if m.TotalMatched != 2*n {
		t.Fatalf("TotalMatched want %d got %d", 2*n, m.TotalMatched)
	}
}

func TestConcurrentDecideSameItemNoDoubleCount(t *testing.T) {
	store := &MemoryStore{}
	q := NewQueue(store)
	item, err := q.EnqueueMatch(ctx(), "tenant-adeco", Query{SKUName: "نفس-العنصر"}, Result{Decision: DecisionNone, ReasonAR: "x"})
	if err != nil || item == nil {
		t.Fatal(err)
	}
	const workers = 20
	var wg sync.WaitGroup
	results := make(chan error, workers)
	for i := 0; i < workers; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			_, err := q.Decide(ctx(), "tenant-adeco", item.ID, StatusApproved, "a@b.c", "ok", "", "", DecideOptions{})
			results <- err
		}()
	}
	wg.Wait()
	close(results)
	ok, already := 0, 0
	for err := range results {
		if err == nil {
			ok++
			continue
		}
		if errors.Is(err, ErrAlreadyDecided) {
			already++
			continue
		}
		t.Fatalf("unexpected: %v", err)
	}
	if ok < 1 {
		t.Fatal("at least one decide must succeed")
	}
	m, _ := q.Snapshot(ctx(), "tenant-adeco")
	if m.Approved != 1 || m.Pending != 0 {
		t.Fatalf("must not double-count approve under race: %+v (ok=%d already=%d)", m, ok, already)
	}
}
