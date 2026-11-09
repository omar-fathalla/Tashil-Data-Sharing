package branchmaster

import (
	"sort"
	"strings"
	"time"
)

// RawOccurrence is one observed store/customer name from facts (dry-run / bootstrap).
type RawOccurrence struct {
	RawName   string
	ChainSlug string // optional hint; inferred when empty
	Source    string // sell_out | sell_in | returns
}

type proposalGroup struct {
	raws    map[string]struct{}
	sources map[string]struct{}
	slug    string
}

// BuildDryRunProposal groups current raw names into proposed chain+branch codes
// and short display names. It does NOT write any production state — owner must
// confirm before ApplyProposal.
func BuildDryRunProposal(tenantID string, occ []RawOccurrence) DryRunReport {
	now := time.Now().UTC()
	byNorm := map[string]*proposalGroup{}
	for _, o := range occ {
		raw := strings.TrimSpace(o.RawName)
		if raw == "" {
			continue
		}
		key := Normalize(raw)
		if key == "" {
			continue
		}
		g := byNorm[key]
		if g == nil {
			slug := strings.ToLower(strings.TrimSpace(o.ChainSlug))
			if slug == "" {
				slug = InferChainSlug(raw)
			}
			g = &proposalGroup{
				raws:    map[string]struct{}{},
				sources: map[string]struct{}{},
				slug:    slug,
			}
			byNorm[key] = g
		}
		g.raws[raw] = struct{}{}
		if o.Source != "" {
			g.sources[o.Source] = struct{}{}
		}
		if g.slug == "" && o.ChainSlug != "" {
			g.slug = strings.ToLower(strings.TrimSpace(o.ChainSlug))
		}
	}

	// Assign codes per chain in stable display-name order.
	type keyed struct {
		key string
		g   *proposalGroup
	}
	var keys []keyed
	for k, g := range byNorm {
		keys = append(keys, keyed{k, g})
	}
	sort.Slice(keys, func(i, j int) bool {
		si, sj := ShortDisplay(firstRaw(keys[i].g)), ShortDisplay(firstRaw(keys[j].g))
		if keys[i].g.slug != keys[j].g.slug {
			return keys[i].g.slug < keys[j].g.slug
		}
		if IsUnallocated(si) != IsUnallocated(sj) {
			return IsUnallocated(sj) // unallocated last within chain
		}
		return si < sj
	})

	seq := map[string]int{} // chainCode → next seq
	var rows []ProposalRow
	chainSet := map[string]bool{}

	for _, k := range keys {
		g := k.g
		cc := ChainCodeForSlug(g.slug)
		chainSet[cc] = true
		display := ShortDisplay(firstRaw(g))
		unalloc := IsUnallocated(display) || IsUnallocated(firstRaw(g))
		var code string
		if unalloc {
			code = UnallocatedCode(cc)
			display = UnallocatedBranchName
		} else {
			seq[cc]++
			code = formatBranchCode(cc, seq[cc])
		}
		raws := sortedKeys(g.raws)
		srcHint := joinSources(g.sources)
		rows = append(rows, ProposalRow{
			RawNames:      raws,
			NormalizedKey: k.key,
			ChainSlug:     g.slug,
			ChainCode:     cc,
			BranchCode:    code,
			DisplayName:   display,
			Unallocated:   unalloc,
			SourceHint:    srcHint,
		})
	}

	notes := []string{
		"هذا تقرير تجريبي (dry-run) فقط — لم يُكتب أي شيء في الإنتاج.",
		"بعد موافقة المالك تُحفظ الجداول (سلاسل / فروع / أسماء مستعارة) مرة واحدة.",
		"«غير موزع على فرع» يبقى دلواً منفصلاً ولا يُربط تلقائياً بأي فرع حقيقي.",
		"التجميع في التقارير يتم بكود الفرع مع الاسم القصير؛ الأسماء الخام في الحقائق لا تُمس.",
	}

	return DryRunReport{
		TenantID:        tenantID,
		GeneratedAt:     now,
		RawNameCount:    countRaws(byNorm),
		UniqueNormCount: len(byNorm),
		ChainCount:      len(chainSet),
		BranchCount:     len(rows),
		Rows:            rows,
		NotesAR:         notes,
	}
}

// ApplyProposal materializes a confirmed proposal into State (idempotent merge).
func ApplyProposal(st *State, report DryRunReport, confirmedBy string, now time.Time) {
	if st == nil {
		return
	}
	if now.IsZero() {
		now = time.Now().UTC()
	}
	for _, row := range report.Rows {
		ensureChain(st, row.ChainSlug, now)
		if _, ok := findBranchByCode(st, row.BranchCode); !ok {
			st.Branches = append(st.Branches, Branch{
				Code:        row.BranchCode,
				ChainCode:   row.ChainCode,
				DisplayName: row.DisplayName,
				Active:      true,
				Unallocated: row.Unallocated,
				CreatedAt:   now,
				UpdatedAt:   now,
			})
		}
		for _, raw := range row.RawNames {
			key := Normalize(raw)
			if key == "" {
				continue
			}
			if row.Unallocated {
				// Record alias for visibility but Resolve never auto-links unallocated.
			}
			if hasAliasKey(st, key) {
				continue
			}
			ts := now
			st.Aliases = append(st.Aliases, Alias{
				RawName:       raw,
				NormalizedKey: key,
				BranchCode:    row.BranchCode,
				Source:        SourceBootstrap,
				Confidence:    1,
				ConfirmedBy:   confirmedBy,
				ConfirmedAt:   &ts,
				CreatedAt:     now,
			})
		}
	}
	st.BootstrapDone = true
	st.UpdatedAt = now
	st.TenantID = report.TenantID
}

func formatBranchCode(chainCode string, n int) string {
	return strings.ToUpper(chainCode) + "-" + formatInt3(n)
}

func formatInt3(n int) string {
	if n < 0 {
		n = 0
	}
	if n > 999 {
		n = n % 1000
	}
	return string([]byte{byte('0' + n/100), byte('0' + (n/10)%10), byte('0' + n%10)})
}

func firstRaw(g *proposalGroup) string {
	if g == nil || len(g.raws) == 0 {
		return ""
	}
	keys := sortedKeys(g.raws)
	// Prefer the shortest raw as canonical display seed (usually already short).
	best := keys[0]
	for _, k := range keys {
		if len([]rune(ShortDisplay(k))) < len([]rune(ShortDisplay(best))) {
			best = k
		}
	}
	return best
}

func sortedKeys(m map[string]struct{}) []string {
	out := make([]string, 0, len(m))
	for k := range m {
		out = append(out, k)
	}
	sort.Strings(out)
	return out
}

func joinSources(m map[string]struct{}) string {
	if len(m) == 0 {
		return ""
	}
	if len(m) > 1 {
		return "mixed"
	}
	for k := range m {
		return k
	}
	return ""
}

func countRaws(byNorm map[string]*proposalGroup) int {
	n := 0
	for _, g := range byNorm {
		n += len(g.raws)
	}
	return n
}

func hasAliasKey(st *State, key string) bool {
	for _, a := range st.Aliases {
		if a.NormalizedKey == key {
			return true
		}
	}
	return false
}
