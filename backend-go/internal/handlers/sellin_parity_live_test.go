//go:build livebq

package handlers

// Read-only parity/latency harness against the live BigQuery dataset. Run with:
//
//	TASHIL_PRODUCT_MASTER_DIR=/tmp/pm-copy go test -tags livebq -run TestSellInParityLive -v ./internal/handlers/
//
// It only reads sell_in_records (ReadSellIn + QuerySellInTotals); no sink writes, no precompute.

import (
	"context"
	"encoding/json"
	"fmt"
	"math"
	"net/http"
	"net/http/httptest"
	"os"
	"testing"
	"time"

	"github.com/tashil/data-sharing/backend/internal/service/bigquery"
	"github.com/tashil/data-sharing/backend/internal/service/bqsink"
)

type timedQuerier struct {
	q    *bqsink.BigQuerySink
	last *bqsink.SellInTotalsResult
}

func (t *timedQuerier) QuerySellInTotals(ctx context.Context, q bqsink.SellInTotalsQuery) (*bqsink.SellInTotalsResult, error) {
	r, err := t.q.QuerySellInTotals(ctx, q)
	t.last = r
	return r, err
}

func TestSellInParityLive(t *testing.T) {
	if os.Getenv("TASHIL_PRODUCT_MASTER_DIR") == "" {
		t.Fatal("set TASHIL_PRODUCT_MASTER_DIR to a copy of data/product_master")
	}
	ctx := context.Background()
	sinkAny := bqsink.New(ctx, bqsink.Config{Enabled: true, ProjectID: "tashil-data-sharing", Dataset: "tashil_analytics", Location: "europe-west1"})
	sink, ok := sinkAny.(*bqsink.BigQuerySink)
	if !ok {
		t.Fatal("no BigQuery sink")
	}
	const tenant = "tenant-adeco"
	start := time.Now()
	recs, err := sink.ReadSellIn(ctx, tenant)
	if err != nil {
		t.Fatal(err)
	}
	t.Logf("ReadSellIn: %d rows in %v", len(recs), time.Since(start))
	repo := bigquery.NewClient("tashil-data-sharing", "tashil_analytics", true)
	start = time.Now()
	repo.ReplaceSellInRecords(tenant, recs)
	t.Logf("ReplaceSellInRecords (enrich): %v", time.Since(start))

	mem := NewAnalyticsHandler(repo)
	tq := &timedQuerier{q: sink}
	bq := NewAnalyticsHandler(repo).WithSellInTotalsQuerier(tq)

	call := func(h *AnalyticsHandler, url string) (PaginatedSellInRecordsResponse, time.Duration, string) {
		w := httptest.NewRecorder()
		s := time.Now()
		h.HandleSellInRecords(w, authenticatedRequest(http.MethodGet, url, tenant))
		d := time.Since(s)
		var resp PaginatedSellInRecordsResponse
		if err := json.Unmarshal(w.Body.Bytes(), &resp); err != nil {
			t.Fatalf("%s: %v %s", url, err, w.Body.String())
		}
		return resp, d, w.Header().Get("X-Records-Source")
	}
	// Chains present after the Stage B resolver.
	_, _, _ = call(bq, "/api/v1/analytics/sell-in-records?limit=25")
	chains := []string{"all"}
	if tq.last != nil {
		seen := map[string]bool{}
		for _, g := range tq.last.Groups {
			if !seen[g.Chain] {
				seen[g.Chain] = true
				chains = append(chains, g.Chain)
			}
		}
	}
	fmt.Println("| year | month | chain | field | memory | bigquery | diff |")
	type combo struct {
		year, month int
		chain       string
	}
	var combos []combo
	for _, y := range []int{2025, 2026} {
		for _, c := range chains {
			combos = append(combos, combo{y, 0, c})
		}
	}
	combos = append(combos, combo{2026, 3, "all"}, combo{2025, 11, "all"})
	mismatch := 0
	for _, cb := range combos {
		url := fmt.Sprintf("/api/v1/analytics/sell-in-records?limit=25&year=%d", cb.year)
		if cb.chain != "all" {
			url += "&chain=" + cb.chain
		}
		if cb.month > 0 {
			url += fmt.Sprintf("&month=%d", cb.month)
		}
		m, md, ms := call(mem, url)
		b, bd, bs := call(bq, url)
		cold := tq.last
		_, bd2, _ := call(bq, url) // warm (BigQuery result cache)
		warm := tq.last
		fields := []struct {
			n    string
			a, b float64
		}{
			{"rows", float64(m.TotalCount), float64(b.TotalCount)},
			{"net", m.TotalValueEGP, b.TotalValueEGP},
			{"cases", m.TotalCases, b.TotalCases},
			{"units", float64(m.TotalUnitsPieces), float64(b.TotalUnitsPieces)},
			{"tons", m.TotalWeightTons, b.TotalWeightTons},
			{"list_excl", m.TotalOfficialListExclVATEGP, b.TotalOfficialListExclVATEGP},
			{"list_incl", m.TotalOfficialListInclVATEGP, b.TotalOfficialListInclVATEGP},
			{"discount", m.TotalDiscountGrantedEGP, b.TotalDiscountGrantedEGP},
			{"eff_disc_pct", m.EffectiveDiscountPct, b.EffectiveDiscountPct},
			{"vat", m.TotalVAT14EGP, b.TotalVAT14EGP},
			{"gross", m.TotalGrossInclVATEGP, b.TotalGrossInclVATEGP},
			{"matched_skus", float64(m.MatchedCatalogSKUsCount), float64(b.MatchedCatalogSKUsCount)},
		}
		for _, f := range fields {
			d := f.b - f.a
			flag := ""
			if math.Abs(d) > 0.05 {
				flag = " ⚠"
				mismatch++
			}
			fmt.Printf("| %d | %d | %s | %s | %.2f | %.2f | %.2f%s |\n", cb.year, cb.month, cb.chain, f.n, f.a, f.b, d, flag)
		}
		pageSame := len(m.Records) == len(b.Records)
		for i := 0; pageSame && i < len(m.Records); i++ {
			x, y := m.Records[i], b.Records[i]
			if x.Year != y.Year || x.MonthNum != y.MonthNum || x.NetValueEGP != y.NetValueEGP || x.RetailerChain != y.RetailerChain ||
				x.NetQtyCases != y.NetQtyCases || x.OfficialListValueExclEGP != y.OfficialListValueExclEGP || x.TotalUnitsSupplied != y.TotalUnitsSupplied {
				pageSame = false
				t.Logf("page row %d differs: mem=%+v\nbq=%+v", i, x, y)
			}
		}
		if !pageSame {
			mismatch++
		}
		fmt.Printf("PAGE %d/%d/%s rows=%d/%d same=%v\n", cb.year, cb.month, cb.chain, len(m.Records), len(b.Records), pageSame)
		js := func(r *bqsink.SellInTotalsResult) string {
			if r == nil {
				return "-"
			}
			return fmt.Sprintf("totals=%dms(cache=%v) groups=%dms(cache=%v) page=%dms(cache=%v) wall=%v", r.Jobs[0].ElapsedMS, r.Jobs[0].CacheHit,
				r.Jobs[1].ElapsedMS, r.Jobs[1].CacheHit, r.Jobs[2].ElapsedMS, r.Jobs[2].CacheHit, r.Duration.Round(time.Millisecond))
		}
		fmt.Printf("TIMING %d/%d/%s memory=%v[%s] bq_cold=%v[%s] {%s} bq_warm=%v {%s}\n", cb.year, cb.month, cb.chain,
			md.Round(time.Millisecond), ms, bd.Round(time.Millisecond), bs, js(cold), bd2.Round(time.Millisecond), js(warm))
	}
	t.Logf("fields beyond 0.05: %d", mismatch)
}
