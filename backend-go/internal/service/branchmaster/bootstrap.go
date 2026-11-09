package branchmaster

import (
	"fmt"
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
	sellOutRaw := map[string]string{} // normalize(raw) → original sell-out raw (for unmatched list)

	for _, o := range occ {
		raw := strings.TrimSpace(o.RawName)
		if raw == "" {
			continue
		}
		norm := LinkNormalize(raw)
		if norm == "" {
			continue
		}
		slug := strings.ToLower(strings.TrimSpace(o.ChainSlug))
		if slug == "" {
			slug = InferChainSlug(raw)
		}
		// Chain-scoped key so "6 اكتوبر" under beet ≠ KH/fathalla "6 اكتوبر".
		key := ChainCodeForSlug(slug) + "|" + norm
		src := strings.ToLower(strings.TrimSpace(o.Source))
		if src == "sell_out" {
			sellOutRaw[key] = raw
		}
		g := byNorm[key]
		if g == nil {
			g = &proposalGroup{
				raws:    map[string]struct{}{},
				sources: map[string]struct{}{},
				slug:    slug,
			}
			byNorm[key] = g
		}
		g.raws[raw] = struct{}{}
		if src != "" {
			g.sources[src] = struct{}{}
		}
	}

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
			return IsUnallocated(sj)
		}
		return si < sj
	})

	seq := map[string]int{}
	var rows []ProposalRow
	chainSet := map[string]bool{}
	chainAgg := map[string]*DryRunChainSummary{}
	var unmatchedSO []string
	var ambiguous []string
	careMergeExamples := []string{}
	khExamples := []string{}
	sawCareMerge, sawKH := false, false

	sellInOut, sellInOnly, sellOutOnly, multiSpell, returnsHit := 0, 0, 0, 0, 0

	for _, k := range keys {
		g := k.g
		cc := ChainCodeForSlug(g.slug)
		chainSet[cc] = true
		if chainAgg[cc] == nil {
			chainAgg[cc] = &DryRunChainSummary{ChainSlug: g.slug, ChainCode: cc}
		}
		ca := chainAgg[cc]
		ca.Branches++

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
		_, hasSI := g.sources["sell_in"]
		_, hasSO := g.sources["sell_out"]
		_, hasRet := g.sources["returns"]
		multi := len(raws) > 1
		care, grocery, kh := false, false, false
		for _, r := range raws {
			if HasCareLine(r) {
				care = true
			} else if !IsUnallocated(r) {
				grocery = true
			}
			if HasKHBanner(r) {
				kh = true
			}
		}
		note := ""
		if care && grocery {
			note = "مواد عناية + بقالة لنفس المفتاح الموحّد"
			sawCareMerge = true
			if len(careMergeExamples) < 8 {
				careMergeExamples = append(careMergeExamples, fmt.Sprintf("%s (%s)", code, display))
			}
			ambiguous = append(ambiguous, fmt.Sprintf("%s (%s): %s", code, display, note))
		}
		if kh {
			sawKH = true
			if len(khExamples) < 8 {
				khExamples = append(khExamples, fmt.Sprintf("%s (%s)", code, display))
			}
		}
		// Sell-out with no Sell-In counterpart
		if hasSO && !hasSI && !unalloc {
			unmatchedSO = append(unmatchedSO, fmt.Sprintf("%s → proposed %s (%s)", sellOutRaw[k.key], code, display))
		}

		switch {
		case hasSI && hasSO:
			sellInOut++
			ca.SellInOut++
		case hasSI && !hasSO:
			sellInOnly++
			ca.SellInOnly++
		case hasSO && !hasSI:
			sellOutOnly++
			ca.SellOutOnly++
		}
		if multi {
			multiSpell++
		}
		if hasRet {
			returnsHit++
			ca.ReturnsHit++
		}

		rows = append(rows, ProposalRow{
			RawNames:       raws,
			NormalizedKey:  k.key,
			ChainSlug:      g.slug,
			ChainCode:      cc,
			BranchCode:     code,
			DisplayName:    display,
			Unallocated:    unalloc,
			SourceHint:     srcHint,
			HasCareLine:    care,
			HasGroceryLine: grocery,
			HasKHBanner:    kh,
			MultiSpelling:  multi,
			AmbiguousNote:  note,
		})
	}

	var summaries []DryRunChainSummary
	for _, cc := range sortedKeys(func() map[string]struct{} {
		m := map[string]struct{}{}
		for k := range chainAgg {
			m[k] = struct{}{}
		}
		return m
	}()) {
		summaries = append(summaries, *chainAgg[cc])
	}
	sort.Strings(unmatchedSO)
	sort.Strings(ambiguous)

	var ownerQ []string
	if sawCareMerge {
		ownerQ = append(ownerQ, fmt.Sprintf(
			"هل صفوف «مواد عناية» لنفس الموقع الجغرافي تُحسب مع البقالة تحت كود فرع واحد؟ (اقتراح dry-run الحالي: نعم، دمج بعد إزالة البادئة — أمثلة: %s)",
			strings.Join(careMergeExamples, "، ")))
	}
	if sawKH {
		ownerQ = append(ownerQ, fmt.Sprintf(
			"هل «كيه اتش جمله ماركت» سلسلة مستقلة (كود جديد مثل KHG) أم تبقى تحت فتح الله / FTH كما في رفع Sell-In الحالي؟ (أمثلة: %s)",
			strings.Join(khExamples, "، ")))
	}
	if len(unmatchedSO) > 0 {
		ownerQ = append(ownerQ, fmt.Sprintf(
			"هناك %d اسم Sell-Out من out26 بلا مقابل Sell-In بعد التوحيد — اعتماد كفروع جديدة أم ربط يدوي؟ (انظر unmatched_sell_out)",
			len(unmatchedSO)))
	}

	notes := []string{
		"هذا تقرير تجريبي (dry-run) فقط — لم يُكتب أي شيء في الإنتاج.",
		"بعد موافقة المالك تُحفظ الجداول (سلاسل / فروع / أسماء مستعارة) مرة واحدة.",
		"«غير موزع على فرع» يبقى دلواً منفصلاً ولا يُربط تلقائياً بأي فرع حقيقي.",
		"التجميع في التقارير يتم بكود الفرع مع الاسم القصير؛ الأسماء الخام في الحقائق لا تُمس.",
		"أسماء Sell-Out (out26) رُبطت بأكواد Sell-In عند تطابق الاسم القصير بعد التوحيد؛ غير المطابق مذكور في unmatched_sell_out.",
		"مصدر Returns = أسماء عملاء Sell-In (المرتجعات تُجمَّع على نفس عمود العميل).",
	}

	return DryRunReport{
		TenantID:         tenantID,
		GeneratedAt:      now,
		RawNameCount:     countRaws(byNorm),
		UniqueNormCount:  len(byNorm),
		ChainCount:       len(chainSet),
		BranchCount:      len(rows),
		SellInAndOut:     sellInOut,
		SellInOnly:       sellInOnly,
		SellOutOnly:      sellOutOnly,
		MultiSpelling:    multiSpell,
		ReturnsCovered:   returnsHit,
		ChainSummaries:   summaries,
		OwnerQuestions:   ownerQ,
		UnmatchedSellOut: unmatchedSO,
		AmbiguousPending: ambiguous,
		Rows:             rows,
		NotesAR:          notes,
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
	order := []string{"sell_in", "sell_out", "returns"}
	var parts []string
	for _, o := range order {
		if _, ok := m[o]; ok {
			parts = append(parts, o)
		}
	}
	for k := range m {
		found := false
		for _, o := range order {
			if k == o {
				found = true
				break
			}
		}
		if !found {
			parts = append(parts, k)
		}
	}
	return strings.Join(parts, "+")
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
