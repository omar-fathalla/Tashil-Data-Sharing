package matcher

import (
	"strings"
	"testing"

	"github.com/tashil/data-sharing/backend/internal/domain"
)

func sampleCatalog() *Catalog {
	return NewCatalog([]domain.ProductMasterItem{
		{
			ItemCode: "FGCL-0550-0001", Barcode: "6223000231227",
			OfficialName: "كلوريل 500 جم مبيض", Brand: "كلوريل (Clorel)", ItemType: "عادي",
			IsPrimaryForBarcode: true,
		},
		// Shared GTIN with the regular SKU above — forces disambiguation / review when name is weak.
		{
			ItemCode: "FGCL-0550-0002", Barcode: "6223000231227",
			OfficialName: "عرض كلوريل 500 جم مبيض", Brand: "كلوريل (Clorel)", ItemType: "عرض",
		},
		{
			ItemCode: "FGDW-1000-0010", Barcode: "6223000234001",
			OfficialName: "فيبا دش 1.1 كجم", Brand: "فيبا (Feba)", ItemType: "عادي",
			IsPrimaryForBarcode: true,
		},
		{
			ItemCode: "FGHC-0700-0214", Barcode: "6223000233436",
			OfficialName: "فوم زجاج 750 مل", Brand: "فوم", ItemType: "عادي",
			IsPrimaryForBarcode: true,
		},
		// Unique barcode used for exact-match tests.
		{
			ItemCode: "FGLC-0100-0001", Barcode: "6223000299999",
			OfficialName: "منعم جو 1 لتر", Brand: "جو", ItemType: "عادي",
			IsPrimaryForBarcode: true,
		},
	})
}

func TestExactBarcodeAndCode(t *testing.T) {
	c := sampleCatalog()
	r := c.Match(Query{Barcode: "622-3000-299999"})
	if r.Decision != DecisionExact || r.Confidence < 0.9 {
		t.Fatalf("exact barcode: %+v", r)
	}
	if r.SuggestedBarcode != "6223000299999" || r.BarcodePolicy != "preserved_input" {
		t.Fatalf("barcode policy: %+v", r)
	}
	r2 := c.Match(Query{ItemCode: "fgcl-0550-0001"})
	if r2.Decision != DecisionExact || r2.MatchedItemCode != "FGCL-0550-0001" {
		t.Fatalf("exact code: %+v", r2)
	}
	// Shared GTIN with no name → uncertain review (do not auto-pick).
	shared := c.Match(Query{Barcode: "6223000231227"})
	if shared.Decision != DecisionUncertain || !NeedsReview(shared) {
		t.Fatalf("shared barcode without name must review: %+v", shared)
	}
}

func TestNeverInventBarcode(t *testing.T) {
	c := sampleCatalog()
	// No barcode on input + weak name → empty suggested, never SKU-…
	r := c.Match(Query{SKUName: "منتج غير معروف بالمرة xyz"})
	if r.SuggestedBarcode != "" {
		t.Fatalf("must not invent barcode, got %q", r.SuggestedBarcode)
	}
	if strings.HasPrefix(strings.ToUpper(r.SuggestedBarcode), "SKU") {
		t.Fatal("synthetic SKU barcode invented")
	}
	// Strong name match may suggest master's real barcode only
	r2 := c.Match(Query{SKUName: "كلوريل 500 جم مبيض"})
	if r2.Decision != DecisionHigh && r2.Decision != DecisionExact {
		t.Fatalf("expected high/exact name match: %+v", r2)
	}
	if r2.SuggestedBarcode != "6223000231227" {
		t.Fatalf("suggested must come from master, got %q", r2.SuggestedBarcode)
	}
	if r2.BarcodePolicy != "from_master" {
		t.Fatalf("policy=%s", r2.BarcodePolicy)
	}
}

func TestForeignBarcodeNeverReassigned(t *testing.T) {
	c := sampleCatalog()
	foreign := "6223006125803" // not in catalog
	r := c.Match(Query{Barcode: foreign, SKUName: "كلوريل 500 جم مبيض"})
	if r.Decision != DecisionNone {
		t.Fatalf("foreign barcode must not auto-match by name: %+v", r)
	}
	if r.SuggestedBarcode != "" {
		t.Fatalf("must not replace foreign barcode with master barcode, got %q", r.SuggestedBarcode)
	}
	if r.InputBarcode != foreign || r.BarcodePolicy != "preserved_input" {
		t.Fatalf("must preserve input: %+v", r)
	}
}

func TestUncertainNeedsReview(t *testing.T) {
	c := sampleCatalog()
	r := c.Match(Query{SKUName: "فوم"}) // too short / ambiguous
	if !NeedsReview(r) && r.Decision != DecisionHigh {
		// Either uncertain/none (review) or if somehow high, ok — but confidence reason required
		t.Fatalf("expected reviewable or high with reason: %+v", r)
	}
	if strings.TrimSpace(r.ReasonAR) == "" {
		t.Fatal("Arabic reason required")
	}
}

func TestSharedBarcodeDisambiguation(t *testing.T) {
	c := sampleCatalog()
	r := c.Match(Query{Barcode: "6223000231227", SKUName: "عرض كلوريل 500 جم مبيض"})
	if r.MatchedItemCode == "" || len(r.Candidates) < 2 {
		t.Fatalf("shared barcode should rank candidates: %+v", r)
	}
	if r.InputBarcode != "6223000231227" {
		t.Fatalf("must preserve barcode: %+v", r)
	}
}

func TestEmptyCatalog(t *testing.T) {
	c := NewCatalog(nil)
	r := c.Match(Query{Barcode: "6223000231227"})
	if r.Decision != DecisionNone || r.SuggestedBarcode != "" {
		t.Fatalf("%+v", r)
	}
}

func TestMatchBatch(t *testing.T) {
	c := sampleCatalog()
	out := c.MatchBatch([]Query{
		{Barcode: "6223000299999"},
		{SKUName: "منتج غريب جداً"},
	})
	if len(out) != 2 || out[0].Decision != DecisionExact || !NeedsReview(out[1]) {
		t.Fatalf("%+v", out)
	}
}
