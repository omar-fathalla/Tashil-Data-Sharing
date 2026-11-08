package matcher

import (
	"testing"
	"time"
)

func TestSortReviewItemsByPriority_HighValueFirst(t *testing.T) {
	low := ReviewItem{
		ID: "low", Status: StatusPending,
		Query:  Query{SKUName: "a", Rows: 1, Value: 50},
		Result: Result{Decision: DecisionNone, Confidence: 0.1},
	}
	high := ReviewItem{
		ID: "high", Status: StatusPending,
		Query:  Query{SKUName: "b", Rows: 60, Value: 25000},
		Result: Result{Decision: DecisionUncertain, Confidence: 0.7, MatchedItemCode: "X", SuggestedBarcode: "6223000231227"},
	}
	mid := ReviewItem{
		ID: "mid", Status: StatusPending,
		Query:  Query{SKUName: "c", Rows: 12, Value: 1500},
		Result: Result{Decision: DecisionUncertain, Confidence: 0.55, MatchedItemCode: "Y", SuggestedBarcode: "6223000231227"},
	}
	items := []ReviewItem{low, mid, high}
	SortReviewItemsByPriority(items)
	if items[0].ID != "high" || items[1].ID != "mid" || items[2].ID != "low" {
		t.Fatalf("order=%v %v %v", items[0].ID, items[1].ID, items[2].ID)
	}
	if PriorityOf(high) != PriorityHigh || PriorityOf(mid) != PriorityMedium || PriorityOf(low) != PriorityLow {
		t.Fatalf("bands high=%s mid=%s low=%s", PriorityOf(high), PriorityOf(mid), PriorityOf(low))
	}
}

func TestBulkApproveEligible(t *testing.T) {
	ok := ReviewItem{
		Status: StatusPending,
		Result: Result{
			Decision: DecisionUncertain, MatchedItemCode: "FGCL-0550-0001",
			SuggestedBarcode: "6223000231227", Confidence: 0.62,
		},
	}
	if !BulkApproveEligible(ok) {
		t.Fatal("expected eligible")
	}
	none := ok
	none.Result.Decision = DecisionNone
	none.Result.MatchedItemCode = ""
	none.Result.SuggestedBarcode = ""
	if BulkApproveEligible(none) {
		t.Fatal("none without suggestion must not be bulk-eligible")
	}
	noBC := ok
	noBC.Result.SuggestedBarcode = ""
	if BulkApproveEligible(noBC) {
		t.Fatal("missing suggested barcode must not be bulk-eligible")
	}
	approved := ok
	approved.Status = StatusApproved
	if BulkApproveEligible(approved) {
		t.Fatal("already decided must not be bulk-eligible")
	}
}

func TestDecideBulk_ApprovesEligibleSkipsOthers(t *testing.T) {
	q := NewQueue(&MemoryStore{})
	q.now = func() time.Time { return time.Date(2026, 11, 8, 12, 0, 0, 0, time.UTC) }
	cat := sampleCatalog()

	elig, err := q.EnqueueMatch(ctx(), "tenant-adeco",
		Query{SKUName: "كلوريل مبيض تقريبي", Rows: 3, Value: 12000},
		Result{
			Decision: DecisionUncertain, Confidence: 0.62,
			MatchedItemCode: "FGCL-0550-0001", MatchedName: "كلوريل 500 جم مبيض",
			SuggestedBarcode: "6223000231227", ReasonAR: "تشابه متوسط",
		})
	if err != nil || elig == nil {
		t.Fatalf("enqueue eligible: %v %+v", err, elig)
	}
	skip, err := q.EnqueueMatch(ctx(), "tenant-adeco",
		Query{SKUName: "أجنبي تماماً", Barcode: "9999999999999", Rows: 1, Value: 5},
		Result{Decision: DecisionNone, Confidence: 0, ReasonAR: "بدون مرشح", SuggestedBarcode: ""})
	if err != nil || skip == nil {
		t.Fatalf("enqueue skip: %v %+v", err, skip)
	}

	list, err := q.List(ctx(), "tenant-adeco", StatusPending)
	if err != nil || len(list) != 2 {
		t.Fatalf("list=%d err=%v", len(list), err)
	}
	if list[0].ID != elig.ID {
		t.Fatalf("high-value eligible should sort first, got %s then %s", list[0].ID, list[1].ID)
	}

	results, err := q.DecideBulk(ctx(), "tenant-adeco", []string{elig.ID, skip.ID, elig.ID, ""}, StatusApproved, "admin@adeco.test", "اعتماد جماعي", DecideOptions{Catalog: cat})
	if err != nil {
		t.Fatal(err)
	}
	if len(results) != 2 {
		t.Fatalf("deduped results len=%d %+v", len(results), results)
	}
	var okN, skipN int
	for _, r := range results {
		if r.OK {
			okN++
			if r.Item == nil || r.Item.Status != StatusApproved {
				t.Fatalf("approved item: %+v", r)
			}
		}
		if r.Skipped {
			skipN++
		}
	}
	if okN != 1 || skipN != 1 {
		t.Fatalf("ok=%d skip=%d results=%+v", okN, skipN, results)
	}

	m, err := q.Snapshot(ctx(), "tenant-adeco")
	if err != nil {
		t.Fatal(err)
	}
	if m.Approved != 1 || m.Pending != 1 || m.InventedBarcodes != 0 {
		t.Fatalf("metrics %+v", m)
	}
}
