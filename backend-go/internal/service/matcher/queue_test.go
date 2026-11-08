package matcher

import (
	"errors"
	"testing"
	"time"
)

func TestEnqueueAndDecide(t *testing.T) {
	q := NewQueue()
	q.now = func() time.Time { return time.Date(2026, 11, 7, 12, 0, 0, 0, time.UTC) }
	cat := sampleCatalog()

	exact := cat.Match(Query{Barcode: "6223000299999"})
	if item := q.EnqueueMatch("tenant-adeco", Query{Barcode: "6223000299999"}, exact); item != nil {
		t.Fatal("exact match must not enter review queue")
	}

	weak := cat.Match(Query{SKUName: "منتج غير معروف بالمرة xyz"})
	item := q.EnqueueMatch("tenant-adeco", Query{SKUName: "منتج غير معروف بالمرة xyz", SourceFile: "f.xlsx", Rows: 2, Value: 10}, weak)
	if item == nil || item.Status != StatusPending {
		t.Fatalf("expected pending review item, got %+v", item)
	}

	list := q.List("tenant-adeco", StatusPending)
	if len(list) != 1 {
		t.Fatalf("pending=%d", len(list))
	}

	decided, err := q.Decide("tenant-adeco", item.ID, StatusApproved, "admin@adeco.test", "صنف جديد هيضاف للكارتة", "", "", DecideOptions{Catalog: cat})
	if err != nil {
		t.Fatal(err)
	}
	if decided.Status != StatusApproved || decided.DecidedBy != "admin@adeco.test" {
		t.Fatalf("%+v", decided)
	}

	m := q.Snapshot("tenant-adeco")
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
	q := NewQueue()
	cat := sampleCatalog()
	weak := cat.Match(Query{SKUName: "xyz-unknown-product"})
	item := q.EnqueueMatch("tenant-adeco", Query{SKUName: "xyz-unknown-product"}, weak)
	if item == nil {
		t.Fatal("expected enqueue")
	}
	_, err := q.Decide("tenant-adeco", item.ID, StatusApproved, "a@b.c", "ok", "FGCL-0550-0001", "SKU-SECTOR-001", DecideOptions{Catalog: cat})
	if !errors.Is(err, ErrInventedBarcode) {
		t.Fatalf("must reject invented SKU- barcode, got %v", err)
	}
}

func TestEnqueueUnknownsUsesCatalog(t *testing.T) {
	q := NewQueue()
	cat := sampleCatalog()
	items := q.EnqueueUnknowns("tenant-adeco", "sellin.xlsx", []Query{
		{Barcode: "6223000299999", SKUName: "منعم جو"}, // unique barcode → auto exact
		{Barcode: "9999999999999", SKUName: "أجنبي"},   // foreign → review
		{SKUName: "منتج نادر جداً بدون باركود"},
	}, cat)
	if len(items) != 2 {
		t.Fatalf("expected 2 review items, got %d (%+v)", len(items), items)
	}
	m := q.Snapshot("tenant-adeco")
	if m.TotalMatched != 3 || m.Exact != 1 || m.Queued != 2 {
		t.Fatalf("metrics: %+v", m)
	}
}

func TestApproveReusesSuggestedMasterBarcodeOnly(t *testing.T) {
	q := NewQueue()
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
	item := q.EnqueueMatch("tenant-adeco", Query{SKUName: "كلوريل مبيض"}, res)
	if item == nil {
		t.Fatal("expected review item")
	}
	decided, err := q.Decide("tenant-adeco", item.ID, StatusApproved, "a@b.c", "تم التأكيد", res.MatchedItemCode, "", DecideOptions{Catalog: cat})
	if err != nil {
		t.Fatal(err)
	}
	if decided.ChosenBarcode != "6223000231227" {
		t.Fatalf("should reuse suggested master barcode, got %q", decided.ChosenBarcode)
	}
}

func TestForeignNumericBarcodeNeverAssigned(t *testing.T) {
	q := NewQueue()
	cat := sampleCatalog()
	foreign := "6223006125803"
	res := cat.Match(Query{Barcode: foreign, SKUName: "كلوريل 500 جم مبيض"})
	if res.Decision != DecisionNone || res.SuggestedBarcode != "" {
		t.Fatalf("foreign numeric must stay unmatched: %+v", res)
	}
	item := q.EnqueueMatch("tenant-adeco", Query{Barcode: foreign, SKUName: "كلوريل 500 جم مبيض"}, res)
	if item == nil {
		t.Fatal("expected review")
	}
	// Wrong pair: master item + foreign barcode
	_, err := q.Decide("tenant-adeco", item.ID, StatusApproved, "a@b.c", "غلط", "FGCL-0550-0001", foreign, DecideOptions{Catalog: cat})
	if err == nil {
		t.Fatal("must reject foreign barcode paired with master item code")
	}
	// Approve acknowledging unknown without inventing a barcode
	decided, err := q.Decide("tenant-adeco", item.ID, StatusApproved, "a@b.c", "باركود أجنبي — بدون تعيين", "", "", DecideOptions{Catalog: cat})
	if err != nil {
		t.Fatal(err)
	}
	if decided.ChosenBarcode != "" {
		t.Fatalf("must not assign barcode on foreign acknowledge, got %q", decided.ChosenBarcode)
	}
}

func TestWrongItemBarcodePairRejected(t *testing.T) {
	q := NewQueue()
	cat := sampleCatalog()
	res := Result{Decision: DecisionUncertain, Confidence: 0.6, ReasonAR: "مراجعة", SuggestedBarcode: "6223000231227", MatchedItemCode: "FGCL-0550-0001"}
	item := q.EnqueueMatch("tenant-adeco", Query{SKUName: "تقريبي"}, res)
	// Pair Feba barcode with Clorel item code
	_, err := q.Decide("tenant-adeco", item.ID, StatusApproved, "a@b.c", "x", "FGCL-0550-0001", "6223000234001", DecideOptions{Catalog: cat})
	if err == nil {
		t.Fatal("wrong item/barcode pair must be rejected")
	}
}

func TestDecideIdempotentAndRejectRepeat(t *testing.T) {
	q := NewQueue()
	cat := sampleCatalog()
	res := Result{Decision: DecisionNone, ReasonAR: "لا مرشح"}
	item := q.EnqueueMatch("tenant-adeco", Query{SKUName: "idem-test"}, res)
	if _, err := q.Decide("tenant-adeco", item.ID, StatusRejected, "a@b.c", "رفض", "", "", DecideOptions{Catalog: cat}); err != nil {
		t.Fatal(err)
	}
	m1 := q.Snapshot("tenant-adeco")
	// Same status again → idempotent, counters unchanged
	again, err := q.Decide("tenant-adeco", item.ID, StatusRejected, "a@b.c", "رفض تاني", "", "", DecideOptions{Catalog: cat})
	if err != nil {
		t.Fatal(err)
	}
	if again.Status != StatusRejected {
		t.Fatalf("%+v", again)
	}
	m2 := q.Snapshot("tenant-adeco")
	if m2.Rejected != m1.Rejected || m2.Pending != m1.Pending {
		t.Fatalf("idempotent decide must not bump counters: before=%+v after=%+v", m1, m2)
	}
	// Different status → reject
	_, err = q.Decide("tenant-adeco", item.ID, StatusApproved, "a@b.c", "تبديل", "", "", DecideOptions{Catalog: cat})
	if !errors.Is(err, ErrAlreadyDecided) {
		t.Fatalf("want ErrAlreadyDecided, got %v", err)
	}
	m3 := q.Snapshot("tenant-adeco")
	if m3.Approved != 0 || m3.Rejected != m1.Rejected {
		t.Fatalf("repeat different status must not change counters: %+v", m3)
	}
}

func TestTenantIsolation(t *testing.T) {
	q := NewQueue()
	cat := sampleCatalog()
	res := Result{Decision: DecisionNone, ReasonAR: "x"}
	item := q.EnqueueMatch("tenant-adeco", Query{SKUName: "عزل"}, res)
	if len(q.List("tenant-other", StatusPending)) != 0 {
		t.Fatal("other tenant must not see adeco queue")
	}
	_, err := q.Decide("tenant-other", item.ID, StatusApproved, "x@y.z", "", "", "", DecideOptions{Catalog: cat})
	if err == nil {
		t.Fatal("cross-tenant decide must fail")
	}
	if len(q.List("tenant-adeco", StatusPending)) != 1 {
		t.Fatal("adeco item must remain pending")
	}
	mOther := q.Snapshot("tenant-other")
	if mOther.TotalMatched != 0 || mOther.Pending != 0 {
		t.Fatalf("other tenant metrics must stay empty: %+v", mOther)
	}
}

func TestEnqueueRefreshDoesNotDoubleCountQueued(t *testing.T) {
	q := NewQueue()
	res := Result{Decision: DecisionUncertain, Confidence: 0.6, ReasonAR: "متوسط"}
	q1 := Query{SKUName: "نفس الصنف", SourceFile: "a.xlsx"}
	if q.EnqueueMatch("tenant-adeco", q1, res) == nil {
		t.Fatal("first enqueue")
	}
	m1 := q.Snapshot("tenant-adeco")
	if q.EnqueueMatch("tenant-adeco", q1, res) == nil {
		t.Fatal("refresh enqueue")
	}
	m2 := q.Snapshot("tenant-adeco")
	if m2.Queued != m1.Queued || m2.Pending != m1.Pending || m2.Pending != 1 {
		t.Fatalf("refresh must not double Queued/Pending: before=%+v after=%+v", m1, m2)
	}
	if m2.TotalMatched != m1.TotalMatched+1 {
		t.Fatalf("TotalMatched should still count the attempt: %+v", m2)
	}
}
