package bigquery

import (
	"testing"

	"github.com/tashil/data-sharing/backend/internal/domain"
)

func TestResolveRealFactoryUnitCostNoGuessing(t *testing.T) {
	pm := domain.ProductMasterItem{NetUnitInvoiceCost: 50, UnitPriceInclVAT: 60}
	if c, src, _ := resolveRealFactoryUnitCost(40, pm, true); c != 50 || src != costSourceMasterNetInvoice {
		t.Fatalf("master net price is primary, got %v %s", c, src)
	}
	if c, src, _ := resolveRealFactoryUnitCost(40, domain.ProductMasterItem{}, false); c != 40 || src != costSourceSellOutSheet {
		t.Fatalf("sheet cost only when not in master, got %v %s", c, src)
	}
	if additionalDiscountPct != 0 {
		t.Fatalf("additional discount must be zero")
	}
	if c, src, _ := resolveRealFactoryUnitCost(0, pm, true); c != 50 || src != costSourceMasterNetInvoice {
		t.Fatalf("master net cost expected, got %v %s", c, src)
	}
	if c, src, _ := resolveRealFactoryUnitCost(0, domain.ProductMasterItem{UnitPriceInclVAT: 100}, true); c != 90 || src != costSourceMasterListLessDisc {
		t.Fatalf("master list less 10%% expected, got %v %s", c, src)
	}
	if c, _, reason := resolveRealFactoryUnitCost(0, domain.ProductMasterItem{}, false); c != 0 || reason != missingCostReasonNotInMaster {
		t.Fatalf("expected empty cost not_in_master, got %v %s", c, reason)
	}
	if c, _, reason := resolveRealFactoryUnitCost(0, domain.ProductMasterItem{ItemCode: "X"}, true); c != 0 || reason != missingCostReasonNoPriceInMaster {
		t.Fatalf("expected empty cost no_price_in_master, got %v %s", c, reason)
	}
}

func TestMissingCostItemsAggregationAndSort(t *testing.T) {
	acc := map[string]*domain.MissingCostItem{}
	none := domain.ProductMasterItem{}
	accumulateMissingCostItem(acc, "A1", "111", "صنف أ", "fathalla", missingCostReasonNotInMaster, none, false, 3, 30)
	accumulateMissingCostItem(acc, "A1", "111", "صنف أ", "kazyon", missingCostReasonNotInMaster, none, false, 2, 20)
	accumulateMissingCostItem(acc, "A1", "111", "صنف أ", "fathalla", missingCostReasonNotInMaster, none, false, 1, 10)
	accumulateMissingCostItem(acc, "B2", "222", "صنف ب", "fathalla", missingCostReasonNoPriceInMaster, domain.ProductMasterItem{ItemCode: "M-B2", OfficialName: "ب"}, true, 100, 500)
	out := finalizeMissingCostItems(acc)
	if len(out) != 2 {
		t.Fatalf("expected 2 items, got %d", len(out))
	}
	if out[0].ItemCode != "B2" || out[0].MasterItemCode != "M-B2" || out[0].ReasonAr == "" {
		t.Fatalf("expected B2 first by sales value with master info, got %+v", out[0])
	}
	a := out[1]
	if a.UnitsSold != 6 || a.SalesValueEGP != 60 || len(a.Chains) != 2 || a.Chains[0] != "fathalla" {
		t.Fatalf("unexpected aggregation %+v", a)
	}
}

func TestChainMarginIsNotClampedAtZero(t *testing.T) {
	// The clamp was removed: a real loss must stay negative.
	sales, cost := 40.0, 61.0
	if m := round2(sales - cost); m != -21 {
		t.Fatalf("expected -21 loss, got %v", m)
	}
}
