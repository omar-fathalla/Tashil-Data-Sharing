package bigquery

import (
	"os"
	"strings"
	"sync"
)

// Sell-In customer -> chain resolution.
//
// The Fathalla "out" exports (in25/in26) are uploaded under one chain, so every row was stored as
// "fathalla" and the Gomla / Beet El Gomla / Wakala filters showed 0. The customer column tells the
// real banner. Only mappings that are unambiguous from the name are built in; anything else stays on
// the uploaded chain until Mohamed confirms it through SELLIN_CUSTOMER_CHAIN_MAP, e.g.
//
//	SELLIN_CUSTOMER_CHAIN_MAP="كيه اتش=gomla;المنصوره=chain-1080314"
//
// Entries are "substring=chain" separated by ";" and are checked before the built-in rules. Resolution
// happens when records are loaded/enriched in memory; stored BigQuery rows are not rewritten.

type customerChainRule struct {
	needle string
	chain  string
}

// Built-in, unambiguous rules (first match wins).
var defaultCustomerChainRules = []customerChainRule{
	{"بيت الجمله", "beet-elgomla"},
	{"بيت الجملة", "beet-elgomla"},
	{"عائله فتح الله ماركت", "fathalla"},
	{"عائلة فتح الله ماركت", "fathalla"},
	{"فتح الله اسواق", "fathalla"},
	{"فتح الله أسواق", "fathalla"},
}

// SellInChainMapEnv names the env var holding extra customer->chain rules.
const SellInChainMapEnv = "SELLIN_CUSTOMER_CHAIN_MAP"

var (
	customerChainRulesOnce sync.Once
	customerChainRules     []customerChainRule
)

func parseCustomerChainRules(spec string) []customerChainRule {
	var out []customerChainRule
	for _, part := range strings.Split(spec, ";") {
		kv := strings.SplitN(part, "=", 2)
		if len(kv) != 2 {
			continue
		}
		needle := normalizeArabicCustomer(kv[0])
		chain := strings.ToLower(strings.TrimSpace(kv[1]))
		if needle == "" || chain == "" {
			continue
		}
		out = append(out, customerChainRule{needle: needle, chain: chain})
	}
	return out
}

func activeCustomerChainRules() []customerChainRule {
	customerChainRulesOnce.Do(func() {
		rules := parseCustomerChainRules(os.Getenv(SellInChainMapEnv))
		for _, r := range defaultCustomerChainRules {
			rules = append(rules, customerChainRule{needle: normalizeArabicCustomer(r.needle), chain: r.chain})
		}
		customerChainRules = rules
	})
	return customerChainRules
}

var arabicCustomerReplacer = strings.NewReplacer("أ", "ا", "إ", "ا", "آ", "ا", "ة", "ه", "ى", "ي")

func normalizeArabicCustomer(s string) string {
	s = strings.TrimSpace(s)
	s = arabicCustomerReplacer.Replace(s)
	return strings.Join(strings.Fields(s), " ")
}

// resolveSellInChainFromCustomer returns the chain for a customer name using the given rules, or
// current when no rule matches. Only rows on the generic upload chain ("" / "fathalla") are re-mapped.
func resolveSellInChainFromCustomer(rules []customerChainRule, customer, current string) string {
	cur := strings.ToLower(strings.TrimSpace(current))
	if cur != "" && cur != "fathalla" {
		return current
	}
	name := normalizeArabicCustomer(customer)
	if name == "" {
		return current
	}
	for _, r := range rules {
		if strings.Contains(name, r.needle) {
			return r.chain
		}
	}
	return current
}

// ResolveSellInChain applies the same customer->chain rules SetSellInRecords uses, so callers can
// key incoming rows by the chain they will be stored under.
func ResolveSellInChain(customer, current string) string {
	return resolveSellInChainFromCustomer(activeCustomerChainRules(), customer, current)
}

// ActiveSellInChainRules returns the normalized (needle, chain) pairs in match order, so the
// BigQuery Sell-In totals query resolves chains exactly like the in-memory enrichment.
func ActiveSellInChainRules() [][2]string {
	rules := activeCustomerChainRules()
	out := make([][2]string, len(rules))
	for i, r := range rules {
		out[i] = [2]string{r.needle, r.chain}
	}
	return out
}
