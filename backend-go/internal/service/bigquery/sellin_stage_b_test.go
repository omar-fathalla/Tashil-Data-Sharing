package bigquery

import (
	"testing"

	"github.com/tashil/data-sharing/backend/internal/domain"
)

func TestResolveSellInChainFromCustomer(t *testing.T) {
	rules := append(parseCustomerChainRules("كيه اتش=gomla"), func() []customerChainRule {
		var out []customerChainRule
		for _, r := range defaultCustomerChainRules {
			out = append(out, customerChainRule{normalizeArabicCustomer(r.needle), r.chain})
		}
		return out
	}()...)
	cases := []struct{ customer, current, want string }{
		{"فتح الله بيت الجمله للتجاره والتوريدات ش م م - فرع 3", "fathalla", "beet-elgomla"},
		{"عائله فتح الله ماركت - مخزن الافوجادو", "fathalla", "fathalla"},
		{"فرع فتح الله - كيه اتش جمله ماركت", "fathalla", "gomla"},
		{"فرع فتح الله - زهران", "fathalla", "fathalla"},
		{"فتح الله بيت الجمله", "carrefour", "carrefour"},
	}
	for _, c := range cases {
		if got := resolveSellInChainFromCustomer(rules, c.customer, c.current); got != c.want {
			t.Errorf("%q: got %q want %q", c.customer, got, c.want)
		}
	}
	// Ambiguous names stay on the uploaded chain with the built-in rules only.
	if got := resolveSellInChainFromCustomer(rules[1:], "فرع فتح الله - كيه اتش جمله ماركت", "fathalla"); got != "fathalla" {
		t.Errorf("ambiguous mapping applied without config: %q", got)
	}
}

func TestSellInQtyLooksLikePieces(t *testing.T) {
	// in26 Maxell row: 332 qty, 89,117 EGP, unit 298.25, carton 3579 (12/carton) -> pieces.
	if !sellInQtyLooksLikePieces(332, 89117.1, 298.25, 3579, 12) {
		t.Fatal("expected pieces")
	}
	// in26 Fiba row: 3735 qty, 3,547,122 EGP, unit 258.97, carton 1035.88 -> cases.
	if sellInQtyLooksLikePieces(3735, 3547122.03, 258.97, 1035.88, 4) {
		t.Fatal("expected cases")
	}
}

func TestEnrichSellInUnmatchedHasNoDefaultDiscount(t *testing.T) {
	c := &Client{}
	r := domain.SellInRecord{TenantID: "tenant-adeco", ItemName: "صنف غير موجود xyz", NetQtyCases: 2, NetValueEGP: 100}
	c.enrichSellInRecordLocked(&r)
	if r.InvoiceDiscountPct != 0 {
		t.Fatalf("unmatched discount = %v, want 0", r.InvoiceDiscountPct)
	}
}

func TestSellOutForeignBarcode(t *testing.T) {
	c := &Client{productMasterByBarcode: map[string]map[string]domain.ProductMasterItem{
		"tenant-adeco": {"6223000231500": {Barcode: "6223000231500"}},
	}}
	if !c.sellOutHasForeignBarcodeLocked("tenant-adeco", "6223006125803") {
		t.Fatal("Arma barcode should be foreign")
	}
	if c.sellOutHasForeignBarcodeLocked("tenant-adeco", "6223000231500") {
		t.Fatal("Adeco barcode is not foreign")
	}
	if c.sellOutHasForeignBarcodeLocked("tenant-adeco", "") {
		t.Fatal("empty barcode is not foreign")
	}
}
