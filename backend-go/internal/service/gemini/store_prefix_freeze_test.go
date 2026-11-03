package gemini

import (
	"strings"
	"testing"
)

// Frozen StoreID prefixes: every chain with real branches keeps the prefix already stored in
// BigQuery (sell_in: fat_ only; sell_out: fat_). Zahran / El Wakala rows come from the fathalla file
// and must stay fat_.
func TestStoreIDPrefixesFrozen(t *testing.T) {
	cases := map[string]string{
		"fathalla":     "fat_",
		"":             "fat_",
		"unknown":      "fat_",
		"gomla":        "gom_",
		"beet-elgomla": "bet_",
		"beet_elgomla": "bet_",
		"carrefour":    "crf_",
		"spinneys":     "spi_",
		"metro":        "met_",
		"seoudi":       "seo_",
		"kazyon":       "kaz_",
		"zahran":       "zah_",
		"elwakala":     "elw_",
		"qa_test":      "qat_",
		"qa":           "fat_",
	}
	for chain, want := range cases {
		got := BuildBranchStoreMetadata(chain, "طنطا").ID
		if !strings.HasPrefix(got, want) {
			t.Errorf("chain %q: got %s want prefix %s", chain, got, want)
		}
	}
	if got := BuildBranchStoreMetadata("fathalla", "زهران - طنطا").ID; !strings.HasPrefix(got, "fat_") {
		t.Errorf("zahran row under fathalla upload must stay fat_: %s", got)
	}
}

func TestEmptyRetailerNeverGomla(t *testing.T) {
	for _, raw := range []string{"", "مدينة نصر", "Nasr City", "الدقي"} {
		id, _ := resolveCanonicalStoreID("", raw)
		if strings.HasPrefix(id, "gom_") {
			t.Errorf("empty retailer + %q attributed to gomla: %s", raw, id)
		}
	}
	if id, _ := resolveCanonicalStoreID("gomla", "مدينة نصر"); id != "gom_cairo_nasrcity" {
		t.Errorf("gomla frozen id changed: %s", id)
	}
	if n := defaultStoreNameForRetailer(""); strings.Contains(n, "Gomla") {
		t.Errorf("empty retailer default name is Gomla: %s", n)
	}
}
