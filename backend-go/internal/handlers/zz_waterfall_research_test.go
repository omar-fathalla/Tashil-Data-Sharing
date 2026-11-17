package handlers

// Research-only scenario test (scratch branch): prints the Sell-In waterfall the current code
// produces for one carton with a 100 EGP official price, chain terms invoice 10% / extra 5% / VAT 14%.

import (
	"context"
	"fmt"
	"testing"

	"github.com/tashil/data-sharing/backend/internal/domain"
	"github.com/tashil/data-sharing/backend/internal/service/bigquery"
)

func TestResearchWaterfall100EGP(t *testing.T) {
	t.Setenv("TASHIL_PRODUCT_MASTER_DIR", t.TempDir())
	const tenant = "tenant-research"
	c := bigquery.NewClient("p", "d", true)
	ctx := context.Background()
	if _, err := c.UpsertProductMasterItem(ctx, tenant, domain.ProductMasterItem{
		ItemCode: "FGCL-0550-0001", OfficialName: "SKU", UnitsPerCarton: 10, VATRate: 0.14,
		UnitPriceExclVAT: 10, InvoiceDiscountPct: 0.10,
	}); err != nil {
		t.Fatal(err)
	}
	vat := 14.0
	c.SetChainDiscountProfiles(tenant, []domain.ChainDiscountProfile{{Chain: "fathalla", InvoiceDiscountPct: 10, AdditionalDiscountPct: 5, VATRatePct: &vat}})

	scenarios := []struct {
		name string
		recs []domain.SellInRecord
	}{
		{"A Excel net 85.50 (= model)", []domain.SellInRecord{row("a", "FGCL-0550-0001", 1, 85.5)}},
		{"B Excel net 80.00 (deeper)", []domain.SellInRecord{row("b", "FGCL-0550-0001", 1, 80)}},
		{"C Excel net 90.00 (no extra given)", []domain.SellInRecord{row("c", "FGCL-0550-0001", 1, 90)}},
		{"D Excel net 105 (above list)", []domain.SellInRecord{row("d", "FGCL-0550-0001", 1, 105)}},
		{"E matched 85.50 + unmatched 50", []domain.SellInRecord{row("e1", "FGCL-0550-0001", 1, 85.5), row("e2", "", 1, 50)}},
	}
	for _, s := range scenarios {
		if err := c.SetSellInRecords(ctx, tenant, "r.xlsx", s.recs); err != nil {
			t.Fatal(err)
		}
		rows, _, err := c.GetSellInRecords(ctx, tenant, bigquery.SellInRecordFilter{})
		if err != nil {
			t.Fatal(err)
		}
		r := buildSellInRecordsResponse(sellInTotalsFromRecords(rows), nil, len(rows), 0, 0)
		closes := r.TotalOfficialListExclVATEGP - r.TotalInvoiceDiscountEGP - r.TotalExtraChainDiscountEGP - r.TotalOtherDifferenceEGP
		fmt.Printf("%-36s official=%7.2f inv=%6.2f extra=%5.2f other=%7.2f totalDisc=%6.2f | net=%7.2f vat%%=%5.2f vat=%6.2f invoices=%7.2f | 1-2-3-4=%7.2f gap=%6.2f\n",
			s.name, r.TotalOfficialListExclVATEGP, r.TotalInvoiceDiscountEGP, r.TotalExtraChainDiscountEGP, r.TotalOtherDifferenceEGP,
			r.TotalDiscountGrantedEGP, r.TotalNetExclVATEGP, r.VATRatePct, r.TotalVAT14EGP, r.TotalGrossInclVATEGP, closes, r.TotalNetExclVATEGP-closes)
	}
}

func row(id, code string, cases, net float64) domain.SellInRecord {
	name := "SKU"
	if code == "" {
		name = "Unknown item not in price list"
	}
	return domain.SellInRecord{
		RecordID: id, TenantID: "tenant-research", RetailerChain: "fathalla", Year: 2026, MonthNum: 9,
		CustomerName: "Fathalla", ItemCode: code, ItemName: name, NetQtyCases: cases, NetValueEGP: net,
		TransactionType: "مسحوبات بيع (Sale)",
	}
}
