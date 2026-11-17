package handlers

import (
	"context"
	"encoding/json"
	"math"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/tashil/data-sharing/backend/internal/domain"
	"github.com/tashil/data-sharing/backend/internal/service/bigquery"
	"github.com/tashil/data-sharing/backend/internal/service/bqsink"
)

const wfTenant = "tenant-waterfall"

func cents(v float64) int64 { return int64(math.Round(v * 100)) }

// assertCardReconciles checks the «من السعر الرسمي إلى الفاتورة» card adds up to the piastre.
func assertCardReconciles(t *testing.T, name string, r PaginatedSellInRecordsResponse) {
	t.Helper()
	if got, want := cents(r.TotalOfficialListExclVATEGP)-cents(r.TotalInvoiceDiscountEGP)-cents(r.TotalExtraChainDiscountEGP), cents(r.TotalExpectedNetEGP); got != want {
		t.Errorf("%s: official − invoice − extra = %d, expected net %d", name, got, want)
	}
	if got, want := cents(r.TotalExpectedNetEGP)-cents(r.TotalExecutionDiffEGP)+cents(r.TotalUnpricedNetEGP), cents(r.TotalNetExclVATEGP); got != want {
		t.Errorf("%s: expected − execution + unpriced = %d, net %d", name, got, want)
	}
	if got, want := cents(r.TotalNetExclVATEGP)+cents(r.TotalVAT14EGP), cents(r.TotalGrossInclVATEGP); got != want {
		t.Errorf("%s: net + VAT = %d, invoices %d", name, got, want)
	}
	if r.TotalNetExclVATEGP != r.TotalValueEGP || r.TotalOtherDifferenceEGP != r.TotalExecutionDiffEGP {
		t.Errorf("%s: net %v vs Excel net %v, other %v vs execution %v", name, r.TotalNetExclVATEGP, r.TotalValueEGP, r.TotalOtherDifferenceEGP, r.TotalExecutionDiffEGP)
	}
}

// newWaterfallRepo: one SKU, 10 pcs × 10 EGP = 100 EGP carton excl. VAT.
func newWaterfallRepo(t *testing.T) *bigquery.Client {
	t.Helper()
	t.Setenv("TASHIL_PRODUCT_MASTER_DIR", t.TempDir())
	c := bigquery.NewClient("p", "d", true)
	if _, err := c.UpsertProductMasterItem(context.Background(), wfTenant, domain.ProductMasterItem{
		ItemCode: "FGCL-0550-0001", OfficialName: "SKU", UnitsPerCarton: 10, VATRate: 0.14,
		UnitPriceExclVAT: 10, InvoiceDiscountPct: 0.25, // per-item column must NOT drive the waterfall
	}); err != nil {
		t.Fatal(err)
	}
	return c
}

func wfRow(id, chain, code string, cases, net float64) domain.SellInRecord {
	name := "SKU"
	if code == "" {
		name = "صنف غير موجود في قائمة الأسعار"
	}
	return domain.SellInRecord{
		RecordID: id, TenantID: wfTenant, RetailerChain: chain, Year: 2026, MonthNum: 9,
		CustomerName: chain, ItemCode: code, ItemName: name, NetQtyCases: cases, NetValueEGP: net,
		TransactionType: "مسحوبات بيع (Sale)",
	}
}

func wfFetch(t *testing.T, repo *bigquery.Client, query string) PaginatedSellInRecordsResponse {
	t.Helper()
	w := httptest.NewRecorder()
	NewAnalyticsHandler(repo).HandleSellInRecords(w, authenticatedRequest(http.MethodGet, "/api/v1/analytics/sell-in-records?limit=50"+query, wfTenant))
	if w.Code != http.StatusOK {
		t.Fatalf("status %d: %s", w.Code, w.Body.String())
	}
	var r PaginatedSellInRecordsResponse
	if err := json.Unmarshal(w.Body.Bytes(), &r); err != nil {
		t.Fatal(err)
	}
	return r
}

// Owner model, one carton at 100 EGP official, Fathalla terms invoice 10% / extra 5% / VAT 14%:
// expected = 100 × 0.90 × 0.95 = 85.50.
func TestSellInWaterfall100EGPScenarios(t *testing.T) {
	repo := newWaterfallRepo(t)
	vat := 14.0
	repo.SetChainDiscountProfiles(wfTenant, []domain.ChainDiscountProfile{{Chain: "fathalla", InvoiceDiscountPct: 10, AdditionalDiscountPct: 5, VATRatePct: &vat}})

	cases := []struct {
		name                                string
		rows                                []domain.SellInRecord
		official, inv, extra, expected      float64
		execution, unpriced, net, vat, gros float64
	}{
		{"A net 85.50 = model", []domain.SellInRecord{wfRow("a", "fathalla", "FGCL-0550-0001", 1, 85.5)}, 100, 10, 4.5, 85.5, 0, 0, 85.5, 11.97, 97.47},
		{"B net 80 (deeper than terms)", []domain.SellInRecord{wfRow("b", "fathalla", "FGCL-0550-0001", 1, 80)}, 100, 10, 4.5, 85.5, 5.5, 0, 80, 11.2, 91.2},
		{"C net 90 (extra not given)", []domain.SellInRecord{wfRow("c", "fathalla", "FGCL-0550-0001", 1, 90)}, 100, 10, 4.5, 85.5, -4.5, 0, 90, 12.6, 102.6},
		{"D net 105 (above list)", []domain.SellInRecord{wfRow("d", "fathalla", "FGCL-0550-0001", 1, 105)}, 100, 10, 4.5, 85.5, -19.5, 0, 105, 14.7, 119.7},
		{"E 85.50 + unmatched 50", []domain.SellInRecord{wfRow("e1", "fathalla", "FGCL-0550-0001", 1, 85.5), wfRow("e2", "fathalla", "", 1, 50)}, 100, 10, 4.5, 85.5, 0, 50, 135.5, 18.97, 154.47},
	}
	for _, tc := range cases {
		repo.ReplaceSellInRecords(wfTenant, tc.rows)
		r := wfFetch(t, repo, "&chain=fathalla")
		got := []float64{r.TotalOfficialListExclVATEGP, r.TotalInvoiceDiscountEGP, r.TotalExtraChainDiscountEGP, r.TotalExpectedNetEGP,
			r.TotalExecutionDiffEGP, r.TotalUnpricedNetEGP, r.TotalNetExclVATEGP, r.TotalVAT14EGP, r.TotalGrossInclVATEGP}
		want := []float64{tc.official, tc.inv, tc.extra, tc.expected, tc.execution, tc.unpriced, tc.net, tc.vat, tc.gros}
		for i := range want {
			if cents(got[i]) != cents(want[i]) {
				t.Errorf("%s: card %v, want %v", tc.name, got, want)
				break
			}
		}
		assertCardReconciles(t, tc.name, r)
		// One chain: the badges show the saved terms exactly (extra 5%, not 4.5% of official).
		if r.TermsAveraged || r.InvoiceDiscountPct != 10 || r.ExtraDiscountPct != 5 || r.VATRatePct != 14 {
			t.Errorf("%s: badges inv=%v extra=%v vat=%v averaged=%v", tc.name, r.InvoiceDiscountPct, r.ExtraDiscountPct, r.VATRatePct, r.TermsAveraged)
		}
		if len(r.ChainTerms) != 1 || !r.ChainTerms[0].Saved || r.ChainTerms[0].Chain != "fathalla" {
			t.Errorf("%s: chain terms %+v", tc.name, r.ChainTerms)
		}
	}

	// D: the above-list row keeps its negative discount (no clamp to 0).
	repo.ReplaceSellInRecords(wfTenant, cases[3].rows)
	if r := wfFetch(t, repo, ""); len(r.Records) != 1 || r.Records[0].DiscountGrantedEGP != -5 || r.TotalDiscountGrantedEGP != -5 {
		t.Fatalf("above-list discount: %+v / total %v", r.Records, r.TotalDiscountGrantedEGP)
	}
}

// A chain without saved terms gets the flat 10% invoice / 0% extra / 14% VAT, not the per-item column.
func TestSellInWaterfallDefaultTerms(t *testing.T) {
	repo := newWaterfallRepo(t)
	repo.ReplaceSellInRecords(wfTenant, []domain.SellInRecord{wfRow("x", "fathalla", "FGCL-0550-0001", 1, 90)})
	r := wfFetch(t, repo, "")
	if r.TotalOfficialListExclVATEGP != 100 || r.TotalInvoiceDiscountEGP != 10 || r.TotalExtraChainDiscountEGP != 0 ||
		r.TotalExpectedNetEGP != 90 || r.TotalExecutionDiffEGP != 0 || r.TotalVAT14EGP != 12.6 || r.TotalGrossInclVATEGP != 102.6 {
		t.Fatalf("default card: %+v", r)
	}
	assertCardReconciles(t, "default", r)
	if r.InvoiceDiscountPct != 10 || r.ExtraDiscountPct != 0 || r.VATRatePct != 14 || len(r.ChainTerms) != 1 || r.ChainTerms[0].Saved {
		t.Fatalf("default badges: inv=%v extra=%v vat=%v terms=%+v", r.InvoiceDiscountPct, r.ExtraDiscountPct, r.VATRatePct, r.ChainTerms)
	}
	if rec := r.Records[0]; rec.InvoiceDiscountPct != 10 || rec.ExtraDiscountPct != 0 || rec.VATRate != 0.14 {
		t.Fatalf("row terms: %+v", rec)
	}

	// Saving terms re-prices at once; removing them restores the defaults.
	repo.SetChainDiscountProfiles(wfTenant, []domain.ChainDiscountProfile{{Chain: "Fathalla", InvoiceDiscountPct: 12, AdditionalDiscountPct: 3}})
	r = wfFetch(t, repo, "")
	if r.TotalInvoiceDiscountEGP != 12 || r.TotalExtraChainDiscountEGP != 2.64 || r.TotalExpectedNetEGP != 85.36 || r.ExtraDiscountPct != 3 || r.VATRatePct != 14 {
		t.Fatalf("saved terms: %+v", r)
	}
	assertCardReconciles(t, "saved", r)
	repo.SetChainDiscountProfiles(wfTenant, nil)
	if r = wfFetch(t, repo, ""); r.TotalInvoiceDiscountEGP != 10 || r.TotalExpectedNetEGP != 90 {
		t.Fatalf("defaults after delete: %+v", r)
	}
}

// All chains: each chain uses its own terms; the badges are official-weighted averages with a breakdown.
func TestSellInWaterfallAllChainsWeighted(t *testing.T) {
	repo := newWaterfallRepo(t)
	repo.SetChainDiscountProfiles(wfTenant, []domain.ChainDiscountProfile{{Chain: "fathalla", InvoiceDiscountPct: 10, AdditionalDiscountPct: 5}})
	repo.ReplaceSellInRecords(wfTenant, []domain.SellInRecord{
		wfRow("f", "fathalla", "FGCL-0550-0001", 3, 256.5), // 300 official → 256.50 expected
		wfRow("g", "gomla", "FGCL-0550-0001", 1, 88),       // default 10%: 100 → 90 expected
		wfRow("u", "gomla", "", 1, 50),                     // unpriced
	})
	r := wfFetch(t, repo, "")
	if r.TotalOfficialListExclVATEGP != 400 || r.TotalInvoiceDiscountEGP != 40 || r.TotalExtraChainDiscountEGP != 13.5 ||
		r.TotalExpectedNetEGP != 346.5 || r.TotalExecutionDiffEGP != 2 || r.TotalUnpricedNetEGP != 50 || r.TotalNetExclVATEGP != 394.5 {
		t.Fatalf("all-chains card: %+v", r)
	}
	assertCardReconciles(t, "all chains", r)
	// invoice 40/400 = 10%; extra 13.5/360 = 3.75%.
	if !r.TermsAveraged || r.InvoiceDiscountPct != 10 || r.ExtraDiscountPct != 3.75 || len(r.ChainTerms) != 2 {
		t.Fatalf("weighted badges: inv=%v extra=%v averaged=%v terms=%+v", r.InvoiceDiscountPct, r.ExtraDiscountPct, r.TermsAveraged, r.ChainTerms)
	}
	f, g := r.ChainTerms[0], r.ChainTerms[1]
	if f.Chain != "fathalla" || !f.Saved || f.ExtraDiscountPct != 5 || f.ExpectedNetEGP != 256.5 ||
		g.Chain != "gomla" || g.Saved || g.InvoiceDiscountPct != 10 || g.ExpectedNetEGP != 90 || g.UnpricedNetEGP != 50 {
		t.Fatalf("breakdown: %+v", r.ChainTerms)
	}
}

// The BigQuery path builds the same card and breakdown from the totals and groups queries.
func TestSellInWaterfallBigQueryPathReconciles(t *testing.T) {
	repo := bigquery.NewClient("tashil-test", "retail", true)
	_ = repo.ClearTenantData(context.Background(), "all")
	repo.SetChainDiscountProfiles("tenant-adeco", []domain.ChainDiscountProfile{{Chain: "fathalla", InvoiceDiscountPct: 10, AdditionalDiscountPct: 5}})
	fake := &fakeSellInQuerier{res: &bqsink.SellInTotalsResult{
		Totals: bqsink.SellInTotals{Count: 3, NetValue: 394.5, ListExcl: 400, InvDisc: 40, ExtraDisc: 13.5, ExpectedNet: 346.5,
			UnpricedNet: 50, NetWithList: 344.5, Gross: 449.73, VAT: 55.23},
		Groups: []bqsink.SellInGroupRow{
			{Year: 2026, Month: 9, Chain: "fathalla", Count: 1, NetValue: 256.5, ListExcl: 300, InvDisc: 30, ExtraDisc: 13.5, ExpectedNet: 256.5},
			{Year: 2026, Month: 9, Chain: "gomla", Count: 2, NetValue: 138, ListExcl: 100, InvDisc: 10, ExpectedNet: 90, UnpricedNet: 50},
		},
	}}
	w := httptest.NewRecorder()
	NewAnalyticsHandler(repo).WithSellInTotalsQuerier(fake).HandleSellInRecords(w, authenticatedRequest(http.MethodGet, "/api/v1/analytics/sell-in-records?year=2026&limit=25", "tenant-adeco"))
	if w.Header().Get("X-Records-Source") != "bigquery" {
		t.Fatalf("source %q", w.Header().Get("X-Records-Source"))
	}
	var r PaginatedSellInRecordsResponse
	_ = json.Unmarshal(w.Body.Bytes(), &r)
	assertCardReconciles(t, "bigquery", r)
	if r.TotalExecutionDiffEGP != 2 || r.TotalUnpricedNetEGP != 50 || r.ExtraDiscountPct != 3.75 || len(r.ChainTerms) != 2 || !r.ChainTerms[0].Saved || r.ChainTerms[1].Saved {
		t.Fatalf("bigquery card: %+v", r)
	}
	if len(fake.got.Profiles) != 1 || fake.got.Profiles[0].ExtraDiscountPct != 5 {
		t.Fatalf("profiles not forwarded: %+v", fake.got.Profiles)
	}
}

// Both paths must resolve the same terms: saved profile, else invoice 10% (matched rows) / extra 0% /
// VAT 14%, never the stored per-row rates.
func TestSellInTotalsSQLUsesFlatDefaults(t *testing.T) {
	plain, groups, _, _ := bqsink.SellInTotalsSQL("`p.d.t`", bqsink.SellInTotalsQuery{TenantID: "tenant-adeco"})
	for _, want := range []string{"0.14 AS vr", "IF(matched, 10, 0) AS ipct", "0 AS epct", "AS expected_net", "IF(list_r = 0, net0, 0)"} {
		if !strings.Contains(plain, want) {
			t.Fatalf("SQL missing %q", want)
		}
	}
	for _, bad := range []string{"invoice_discount_pct", "IFNULL(vat_rate", "< 0, 0,"} {
		if strings.Contains(plain, bad) {
			t.Fatalf("SQL must not use %q (stored upload-time rates / clamp)", bad)
		}
	}
	if !strings.Contains(groups, "AS expected_net") || !strings.Contains(groups, "AS unpriced_net") || !strings.Contains(groups, "AS inv_disc") {
		t.Fatal("groups must carry the per-chain waterfall sums")
	}
	// A profile without VAT keeps the flat 14% (like the in-memory row).
	withProf, _, _, params := bqsink.SellInTotalsSQL("`p.d.t`", bqsink.SellInTotalsQuery{TenantID: "tenant-adeco",
		Profiles: []bqsink.SellInChainProfile{{Chain: "gomla", InvoiceDiscountPct: 12, ExtraDiscountPct: 3}}})
	if !strings.Contains(withProf, "CASE WHEN chain_r = @pc0 THEN @pi0 ELSE IF(matched, 10, 0) END AS ipct") ||
		!strings.Contains(withProf, "CASE WHEN chain_r = @pc0 THEN @pe0 ELSE 0 END AS epct") || !strings.Contains(withProf, "0.14 AS vr") {
		t.Fatalf("profile SQL: %s", withProf)
	}
	got := map[string]interface{}{}
	for _, p := range params {
		got[p.Name] = p.Value
	}
	if got["pi0"] != 12.0 || got["pe0"] != 3.0 {
		t.Fatalf("params %+v", got)
	}
	if inv, extra, vat, saved := sellInTermsFor("unknown", nil); inv != domain.DefaultChainInvoiceDiscountPct || extra != 0 || vat != 14 || saved {
		t.Fatalf("handler defaults: %v %v %v %v", inv, extra, vat, saved)
	}
}
