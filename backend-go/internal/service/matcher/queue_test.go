package matcher

import (
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

	decided, err := q.Decide("tenant-adeco", item.ID, StatusApproved, "admin@adeco.test", "صنف جديد هيضاف للكارتة", "", "")
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
	_, err := q.Decide("tenant-adeco", item.ID, StatusApproved, "a@b.c", "ok", "FGCL-0550-0001", "SKU-SECTOR-001")
	if err == nil {
		t.Fatal("must reject invented SKU- barcode")
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
	// Force uncertain by using a partial-ish name that still finds candidates
	res := cat.Match(Query{SKUName: "كلوريل مبيض"})
	if res.Decision == DecisionNone {
		// Still enqueue manually with a suggested barcode from master
		res.Decision = DecisionUncertain
		res.SuggestedBarcode = "6223000231227"
		res.BarcodePolicy = "from_master_pending_review"
		res.Confidence = 0.6
		res.ReasonAR = "تشابه متوسط"
	}
	item := q.EnqueueMatch("tenant-adeco", Query{SKUName: "كلوريل مبيض"}, res)
	if item == nil {
		t.Fatal("expected review item")
	}
	decided, err := q.Decide("tenant-adeco", item.ID, StatusApproved, "a@b.c", "تم التأكيد", res.MatchedItemCode, "")
	if err != nil {
		t.Fatal(err)
	}
	if decided.ChosenBarcode != "6223000231227" {
		t.Fatalf("should reuse suggested master barcode, got %q", decided.ChosenBarcode)
	}
}
