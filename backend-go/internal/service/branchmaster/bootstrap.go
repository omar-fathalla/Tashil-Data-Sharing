package branchmaster

import (
	"fmt"
	"sort"
	"strings"
	"time"
	"unicode"
)

// RawOccurrence is one observed store/customer name from facts (dry-run / bootstrap).
type RawOccurrence struct {
	RawName     string `json:"raw_name"`
	ChainSlug   string `json:"chain_slug,omitempty"` // optional hint; inferred when empty
	Source      string `json:"source"`               // sell_out | sell_in | returns
	SourceTable string `json:"source_table,omitempty"`
	SourceFile  string `json:"source_file,omitempty"`
	ArchiveID   string `json:"archive_id,omitempty"`
}

// RawSourceCite cites the live table/file that produced one raw spelling.
type RawSourceCite struct {
	RawName     string `json:"raw_name"`
	Source      string `json:"source"` // sell_in | sell_out | returns
	SourceTable string `json:"source_table,omitempty"`
	SourceFile  string `json:"source_file,omitempty"`
	ArchiveID   string `json:"archive_id,omitempty"`
}

type proposalGroup struct {
	raws    map[string]struct{}
	sources map[string]struct{}
	cites   []RawSourceCite
	slug    string
}

// BuildDryRunProposal groups current raw names into proposed chain+branch codes
// and short display names. It does NOT write any production state — owner must
// confirm before ApplyProposal.
func BuildDryRunProposal(tenantID string, occ []RawOccurrence) DryRunReport {
	now := time.Now().UTC()
	byNorm := map[string]*proposalGroup{}
	sellOutRaw := map[string]string{} // normalize(raw) → original sell-out raw (for unmatched list)

	provenance := map[string]struct{}{}
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
		// Chain-scoped key so same short name under different chains stay separate.
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
		cite := RawSourceCite{
			RawName:     raw,
			Source:      src,
			SourceTable: strings.TrimSpace(o.SourceTable),
			SourceFile:  strings.TrimSpace(o.SourceFile),
			ArchiveID:   strings.TrimSpace(o.ArchiveID),
		}
		if cite.SourceTable != "" || cite.SourceFile != "" || cite.ArchiveID != "" {
			g.cites = append(g.cites, cite)
			prov := fmt.Sprintf("%s ← %s", src, cite.SourceTable)
			if cite.SourceFile != "" {
				prov += " / " + cite.SourceFile
			}
			if cite.ArchiveID != "" {
				prov += " (" + cite.ArchiveID + ")"
			}
			provenance[prov] = struct{}{}
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
	careMerged := 0

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

		displayRaw := firstRaw(g)
		// Prefer a non-care spelling for the short display when grocery+care share a code
		// (owner: show short location name only).
		for _, r := range sortedKeys(g.raws) {
			if !HasCareLine(r) && !IsUnallocated(r) {
				if displayRaw == "" || HasCareLine(displayRaw) || len([]rune(ShortDisplay(r))) <= len([]rune(ShortDisplay(displayRaw))) {
					displayRaw = r
				}
			}
		}
		display := ShortDisplay(displayRaw)
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
			// Owner (Mohamed, 9 Nov): care-line + grocery at same location = ONE branch.
			note = "owner: مواد عناية + بقالة = نفس الفرع (مجموع في التقارير؛ الاسم القصير فقط)"
			careMerged++
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
			RawSourceCites: dedupeCites(g.cites),
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

	misspellings := detectLikelyMisspellings(rows)

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
	if len(misspellings) > 0 {
		ownerQ = append(ownerQ, fmt.Sprintf(
			"أزواج أسماء متقاربة قد تكون إملاءً مختلفًا لنفس الفرع — أكّد الدمج أو أبقِها منفصلة (انظر likely_misspellings): %s",
			strings.Join(misspellings[:min(3, len(misspellings))], "؛ ")))
	}
	if len(unmatchedSO) > 0 {
		ownerQ = append(ownerQ, fmt.Sprintf(
			"هناك %d اسم Sell-Out من out26 بلا مقابل Sell-In بعد التوحيد — اعتماد كفروع جديدة أم ربط يدوي؟ (انظر unmatched_sell_out)",
			len(unmatchedSO)))
	}

	notes := []string{
		"هذا تقرير تجريبي (dry-run) فقط — لم يُكتب أي شيء في الإنتاج.",
		"المصادر = بيانات Adeco الحية فقط (BigQuery). لا seed_customers / seed_aliases / ملفات أرشيف قديمة.",
		"قرار المالك (9 Nov): «عائله فتح الله ماركت مواد عناية - X» = نفس فرع «عائله فتح الله ماركت - X» تحت كود FTH واحد؛ التقارير تجمع الاثنين وتعرض الاسم القصير فقط.",
		fmt.Sprintf("عدد الفروع التي دُمجت فيها مواد عناية + بقالة في هذا dry-run: %d.", careMerged),
		"بعد موافقة المالك على بقية الأسئلة تُحفظ الجداول (سلاسل / فروع / أسماء مستعارة) مرة واحدة.",
		"«غير موزع على فرع» يظهر فقط إن وُجد في الحقائق الحية؛ لا يُختلق هنا.",
		"التجميع في التقارير يتم بكود الفرع مع الاسم القصير؛ الأسماء الخام في الحقائق لا تُمس.",
		"أسماء Sell-Out رُبطت بأكواد Sell-In عند تطابق الاسم القصير بعد التوحيد؛ غير المطابق مذكور في unmatched_sell_out.",
		"مصدر Returns = صفوف sell_in_records ذات قيمة سالبة أو نوع مرتجع (نفس عمود customer_name).",
		"سلسلة واحدة حاليًا: أسواق فتح الله (FTH) حسب chain_key الحي وقرار المالك.",
	}

	return DryRunReport{
		TenantID:           tenantID,
		GeneratedAt:        now,
		RawNameCount:       countRaws(byNorm),
		UniqueNormCount:    len(byNorm),
		ChainCount:         len(chainSet),
		BranchCount:        len(rows),
		SellInAndOut:       sellInOut,
		SellInOnly:         sellInOnly,
		SellOutOnly:        sellOutOnly,
		MultiSpelling:      multiSpell,
		ReturnsCovered:     returnsHit,
		ChainSummaries:     summaries,
		OwnerQuestions:     ownerQ,
		UnmatchedSellOut:   unmatchedSO,
		AmbiguousPending:   ambiguous,
		LikelyMisspellings: misspellings,
		DataProvenance:     sortedKeys(provenance),
		Rows:               rows,
		NotesAR:            notes,
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

func dedupeCites(in []RawSourceCite) []RawSourceCite {
	if len(in) == 0 {
		return nil
	}
	seen := map[string]struct{}{}
	var out []RawSourceCite
	for _, c := range in {
		k := c.RawName + "|" + c.Source + "|" + c.SourceTable + "|" + c.SourceFile + "|" + c.ArchiveID
		if _, ok := seen[k]; ok {
			continue
		}
		seen[k] = struct{}{}
		out = append(out, c)
	}
	sort.Slice(out, func(i, j int) bool {
		if out[i].RawName != out[j].RawName {
			return out[i].RawName < out[j].RawName
		}
		return out[i].Source < out[j].Source
	})
	return out
}

// detectLikelyMisspellings flags near-duplicate short names within one chain
// (e.g. نيس vs نيس2, كفر الدوار 2 vs كفر الدوار2) for owner confirm — not auto-merged.
func detectLikelyMisspellings(rows []ProposalRow) []string {
	type item struct {
		code, display, norm string
	}
	byChain := map[string][]item{}
	for _, r := range rows {
		if r.Unallocated {
			continue
		}
		norm := r.NormalizedKey
		if i := strings.IndexByte(norm, '|'); i >= 0 {
			norm = norm[i+1:]
		}
		byChain[r.ChainCode] = append(byChain[r.ChainCode], item{r.BranchCode, r.DisplayName, norm})
	}
	var out []string
	for _, items := range byChain {
		for i := 0; i < len(items); i++ {
			for j := i + 1; j < len(items); j++ {
				a, b := items[i], items[j]
				if likelyMisspellingPair(a.norm, b.norm) {
					out = append(out, fmt.Sprintf("%s (%s) ↔ %s (%s)", a.code, a.display, b.code, b.display))
				}
			}
		}
	}
	sort.Strings(out)
	return out
}

func likelyMisspellingPair(a, b string) bool {
	a = strings.TrimSpace(a)
	b = strings.TrimSpace(b)
	if a == "" || b == "" || a == b {
		return false
	}
	// Mini / مول / ريفيرا / المحطة are real distinct sites — never flag as typos.
	distinct := []string{"ميني", "mini", "مول", "ريفيرا", "المحطه", "المحطة", "استاد", "اندلس", "out let", "اوت ليت"}
	for _, d := range distinct {
		ha, hb := strings.Contains(a, d), strings.Contains(b, d)
		if ha != hb {
			return false
		}
	}
	// Same after removing spaces only (e.g. كفر الدوار2 vs كفر الدوار 2).
	nospace := func(s string) string { return strings.ReplaceAll(s, " ", "") }
	if nospace(a) == nospace(b) {
		return true
	}
	// Same letters ignoring trailing/embedded digits (نيس vs نيس2) — owner confirm.
	letters := func(s string) string {
		var b strings.Builder
		for _, r := range s {
			if r >= '0' && r <= '9' || unicode.IsSpace(r) {
				continue
			}
			b.WriteRune(r)
		}
		return b.String()
	}
	la, lb := letters(a), letters(b)
	if la != "" && la == lb {
		// Digit on one side only — flag short stems (نيس vs نيس2), not numbered
		// sites like كفر الدوار vs كفر الدوار 2.
		da, db := hasDigit(a), hasDigit(b)
		if da != db && len([]rune(la)) <= 5 {
			return true
		}
	}
	return false
}

func hasDigit(s string) bool {
	for _, r := range s {
		if r >= '0' && r <= '9' {
			return true
		}
	}
	return false
}

func min(a, b int) int {
	if a < b {
		return a
	}
	return b
}

func hasAliasKey(st *State, key string) bool {
	for _, a := range st.Aliases {
		if a.NormalizedKey == key {
			return true
		}
	}
	return false
}
