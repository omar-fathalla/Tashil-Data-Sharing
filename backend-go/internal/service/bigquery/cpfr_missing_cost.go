package bigquery

import (
	"sort"
	"strings"

	"github.com/tashil/data-sharing/backend/internal/domain"
)

// Reasons an item has no real factory cost.
const (
	missingCostReasonNotInMaster     = "not_in_master"
	missingCostReasonNoPriceInMaster = "no_price_in_master"
)

// Cost sources considered REAL.
const (
	costSourceSellOutSheet       = "sell_out_sheet"
	costSourceMasterNetInvoice   = "master_net_invoice_cost"
	costSourceMasterListLessDisc = "master_list_price_less_invoice_discount"
)

func missingCostReasonAr(reason string) string {
	switch reason {
	case missingCostReasonNotInMaster:
		return "غير موجود في كارتة الأصناف (لا كود ولا باركود ولا اسم مطابق)"
	case missingCostReasonNoPriceInMaster:
		return "موجود في كارتة الأصناف لكن بدون سعر"
	}
	return "بدون تكلفة حقيقية"
}

// resolveRealFactoryUnitCost returns the per-piece factory cost incl. VAT from REAL sources only:
//  1. the cost written in the Sell-Out sheet,
//  2. the product master net invoice cost (list price incl. VAT minus the invoice discount),
//  3. the product master list price incl. VAT minus the standard 10% invoice discount
//     (still master-based, used only when the master row has no net cost computed).
//
// There is NO guess from the selling price. When nothing real exists it returns 0 and a reason.
// Accepted assumption: the Aug-2026 master price applies to Jan–Apr 2026 as well.
func resolveRealFactoryUnitCost(sheetCost float64, pm domain.ProductMasterItem, pmOk bool) (float64, string, string) {
	if sheetCost > 0 {
		return sheetCost, costSourceSellOutSheet, ""
	}
	if !pmOk {
		return 0, "", missingCostReasonNotInMaster
	}
	if pm.NetUnitInvoiceCost > 0 {
		return pm.NetUnitInvoiceCost, costSourceMasterNetInvoice, ""
	}
	if pm.UnitPriceInclVAT > 0 {
		return pm.UnitPriceInclVAT * 0.90, costSourceMasterListLessDisc, ""
	}
	return 0, "", missingCostReasonNoPriceInMaster
}

func missingCostKey(itemCode, barcode, name string) string {
	return strings.ToLower(strings.TrimSpace(itemCode)) + "|" + strings.TrimSpace(barcode) + "|" + strings.TrimSpace(name)
}

func accumulateMissingCostItem(acc map[string]*domain.MissingCostItem, itemCode, barcode, name, chain, reason string, pm domain.ProductMasterItem, pmOk bool, units int, revenue float64) {
	key := missingCostKey(itemCode, barcode, name)
	it, ok := acc[key]
	if !ok {
		it = &domain.MissingCostItem{
			ItemCode: strings.TrimSpace(itemCode),
			Barcode:  strings.TrimSpace(barcode),
			SKUName:  strings.TrimSpace(name),
			Reason:   reason,
			ReasonAr: missingCostReasonAr(reason),
		}
		if pmOk {
			it.MasterItemCode = pm.ItemCode
			it.MasterName = pm.OfficialName
		}
		acc[key] = it
	}
	it.UnitsSold += units
	it.SalesValueEGP += revenue
	if chain != "" {
		found := false
		for _, c := range it.Chains {
			if c == chain {
				found = true
				break
			}
		}
		if !found {
			it.Chains = append(it.Chains, chain)
		}
	}
}

func finalizeMissingCostItems(acc map[string]*domain.MissingCostItem) []domain.MissingCostItem {
	out := make([]domain.MissingCostItem, 0, len(acc))
	for _, it := range acc {
		it.SalesValueEGP = round2(it.SalesValueEGP)
		sort.Strings(it.Chains)
		out = append(out, *it)
	}
	sort.SliceStable(out, func(i, j int) bool {
		if out[i].SalesValueEGP != out[j].SalesValueEGP {
			return out[i].SalesValueEGP > out[j].SalesValueEGP
		}
		return out[i].SKUName < out[j].SKUName
	})
	return out
}
