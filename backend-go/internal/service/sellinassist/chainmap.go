package sellinassist

import (
	"fmt"
	"sort"
	"strings"

	"github.com/tashil/data-sharing/backend/internal/service/bigquery"
)

// Heuristic customer→chain rules used only as suggestions. First match wins.
// These mirror the ops style of SELLIN_CUSTOMER_CHAIN_MAP ("substring=chain").
var heuristicChainRules = []struct {
	needle string
	chain  string
	label  string // short Arabic/ops needle for the env fragment
}{
	{"بيت الجمل", "beet-elgomla", "بيت الجمله"},
	{"كيه اتش", "gomla", "كيه اتش"},
	{"جمله ماركت", "gomla", "جمله ماركت"},
	{"جملة ماركت", "gomla", "جملة ماركت"},
	{"زهران", "zahran", "زهران"},
	{"المنصوره", "chain-1080314", "المنصوره"},
	{"المنصورة", "chain-1080314", "المنصوره"},
	{"وكال", "chain-1080314", "وكاله"},
	{"كارفور", "carrefour", "كارفور"},
	{"carrefour", "carrefour", "carrefour"},
	{"سبينيس", "spinneys", "سبينيس"},
	{"spinneys", "spinneys", "spinneys"},
	{"كازيون", "kazyon", "كازيون"},
	{"kazyon", "kazyon", "kazyon"},
}

// knownChains is the set of chain codes we may suggest.
var knownChains = map[string]bool{
	"fathalla": true, "beet-elgomla": true, "gomla": true,
	"chain-1080314": true, "zahran": true, "carrefour": true,
	"spinneys": true, "kazyon": true,
}

type chainCandidate struct {
	Needle   string
	Chain    string
	Label    string
	Samples  []string
	ReasonAR string
	Conf     float64
}

// proposeCustomerChains groups customers that still sit on the upload/generic chain
// and proposes SELLIN_CUSTOMER_CHAIN_MAP fragments. Already-resolved names are skipped.
func proposeCustomerChains(customers []string, uploadChain string) []chainCandidate {
	uploadChain = strings.ToLower(strings.TrimSpace(uploadChain))
	if uploadChain == "" {
		uploadChain = "fathalla"
	}
	grouped := map[string]*chainCandidate{}
	for _, raw := range customers {
		name := strings.TrimSpace(raw)
		if name == "" {
			continue
		}
		resolved := bigquery.ResolveSellInChain(name, uploadChain)
		if strings.ToLower(resolved) != uploadChain && resolved != "" {
			// Already covered by live SELLIN_CUSTOMER_CHAIN_MAP / built-ins — skip.
			continue
		}
		norm := normalizeArabic(name)
		low := strings.ToLower(norm)
		for _, rule := range heuristicChainRules {
			needle := normalizeArabic(rule.needle)
			if !strings.Contains(low, strings.ToLower(needle)) {
				continue
			}
			key := rule.chain + "|" + rule.label
			c, ok := grouped[key]
			if !ok {
				c = &chainCandidate{
					Needle:   rule.label,
					Chain:    rule.chain,
					Label:    rule.label,
					ReasonAR: fmt.Sprintf("اسم العميل فيه «%s» → سلسلة مقترحة «%s» (اقتراح بس، مش هيتعمل غير بعد موافقتك)", rule.label, rule.chain),
					Conf:     0.82,
				}
				grouped[key] = c
			}
			if len(c.Samples) < 5 {
				dup := false
				for _, s := range c.Samples {
					if s == name {
						dup = true
						break
					}
				}
				if !dup {
					c.Samples = append(c.Samples, name)
				}
			}
			break
		}
	}
	out := make([]chainCandidate, 0, len(grouped))
	for _, c := range grouped {
		out = append(out, *c)
	}
	sort.Slice(out, func(i, j int) bool {
		if out[i].Chain != out[j].Chain {
			return out[i].Chain < out[j].Chain
		}
		return out[i].Needle < out[j].Needle
	})
	return out
}

func envFragment(needle, chain string) string {
	return strings.TrimSpace(needle) + "=" + strings.ToLower(strings.TrimSpace(chain))
}

// ParseEnvFragment validates a SELLIN_CUSTOMER_CHAIN_MAP-style "needle=chain" fragment.
func ParseEnvFragment(frag string) (needle, chain string, ok bool) {
	parts := strings.SplitN(frag, "=", 2)
	if len(parts) != 2 {
		return "", "", false
	}
	needle = strings.TrimSpace(parts[0])
	chain = strings.ToLower(strings.TrimSpace(parts[1]))
	if needle == "" || chain == "" || !knownChains[chain] {
		return "", "", false
	}
	return needle, chain, true
}
