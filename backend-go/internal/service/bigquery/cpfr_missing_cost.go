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

// additionalDiscountPct is the extra (contract) discount on top of the invoice discount.
// Mohamed set it to ZERO: the master column "نسبه الخصم الاضافية" is empty for all items.
// Cost per piece = net unit price after invoice discount × (1 − additionalDiscountPct) × qty.
const additionalDiscountPct = 0.0

// defaultInvoiceDiscountPct is the standard Adeco invoice discount.
const defaultInvoiceDiscountPct = 0.10

// resolveRealFactoryUnitCost returns the per-piece factory cost incl. VAT from REAL sources only.
// Priority (confirmed by Mohamed):
//  1. PRIMARY: product master "سعر القطعه بعد خصم الفاتورة" (NetUnitInvoiceCost, incl. VAT,
//     after the 10% invoice discount) × (1 − additionalDiscountPct);
//  2. master list price incl. VAT × (1 − 10%) × (1 − additionalDiscountPct) when the master
//     row has no net price computed;
//  3. the cost written in the Sell-Out sheet, ONLY when the item is not matched in the master.
//
// There is NO guess from the selling price. When nothing real exists it returns 0 and a reason.
// Accepted assumption: the Aug-2026 master price applies to Jan–Apr 2026 as well.
func resolveRealFactoryUnitCost(sheetCost float64, pm domain.ProductMasterItem, pmOk bool) (float64, string, string) {
	if pmOk {
		if pm.NetUnitInvoiceCost > 0 {
			return pm.NetUnitInvoiceCost * (1.0 - additionalDiscountPct), costSourceMasterNetInvoice, ""
		}
		if pm.UnitPriceInclVAT > 0 {
			return pm.UnitPriceInclVAT * (1.0 - defaultInvoiceDiscountPct) * (1.0 - additionalDiscountPct), costSourceMasterListLessDisc, ""
		}
		if sheetCost > 0 {
			return sheetCost, costSourceSellOutSheet, ""
		}
		return 0, "", missingCostReasonNoPriceInMaster
	}
	if sheetCost > 0 {
		return sheetCost, costSourceSellOutSheet, ""
	}
	return 0, "", missingCostReasonNotInMaster
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
