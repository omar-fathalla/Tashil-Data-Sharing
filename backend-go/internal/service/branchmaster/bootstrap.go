package branchmaster

import (
	"fmt"
	"sort"
	"strings"
	"time"
)

// RawOccurrence is one observed store/customer name from facts (dry-run / bootstrap).
type RawOccurrence struct {
	RawName     string `json:"raw_name"`
	ChainSlug   string `json:"chain_slug,omitempty"` // optional hint; inferred when empty
	Source      string `json:"source"`               // sell_out | sell_in | returns | plan_branch_code
	SourceTable string `json:"source_table,omitempty"`
	SourceFile  string `json:"source_file,omitempty"`
	ArchiveID   string `json:"archive_id,omitempty"`
	// Optional Plan_2026 Customer_Branch_Code stats (Source=plan_branch_code).
	PlanCode string  `json:"plan_code,omitempty"`
	RowCount int     `json:"row_count,omitempty"`
	ValueEGP float64 `json:"value_egp,omitempty"`
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

	provenance := map[string]struct{}{}
	var planCodeProps []PlanBranchCodeRow
	parentAgg := map[string]*ParentLevelRow{} // key = kind|display
	var quarantined []QuarantinedRow
	policiesUsed := map[string]ChainPolicy{}

	addProvenance := func(src string, cite RawSourceCite) {
		if cite.SourceTable == "" && cite.SourceFile == "" && cite.ArchiveID == "" {
			return
		}
		prov := fmt.Sprintf("%s ← %s", src, cite.SourceTable)
		if cite.SourceFile != "" {
			prov += " / " + cite.SourceFile
		}
		if cite.ArchiveID != "" {
			prov += " (" + cite.ArchiveID + ")"
		}
		provenance[prov] = struct{}{}
	}

	for _, o := range occ {
		src := strings.ToLower(strings.TrimSpace(o.Source))
		if src == "plan_branch_code" {
			code := strings.TrimSpace(o.PlanCode)
			if code == "" {
				code = strings.TrimSpace(o.RawName)
			}
			if code == "" {
				continue
			}
			if isRegionalPlanCode(code) {
				// Regional is parent-level / unallocated — NOT a proposed branch.
				planCodeProps = append(planCodeProps, PlanBranchCodeRow{
					Code: code, RowCount: o.RowCount, ValueEGP: o.ValueEGP,
					Status: "regional_parent_level", SourceFile: o.SourceFile, ArchiveID: o.ArchiveID,
				})
				pk := "regional|" + code
				if parentAgg[pk] == nil {
					parentAgg[pk] = &ParentLevelRow{
						Kind: "regional", DisplayName: code,
						NoteAR:     "مجمع إقليم / Regional — ليس فرعًا مقترحًا؛ بانتظار قرار المالك",
						SourceFile: o.SourceFile, ArchiveID: o.ArchiveID,
					}
				}
				pr := parentAgg[pk]
				pr.RawNames = appendUnique(pr.RawNames, code)
				pr.RowCount = o.RowCount
				pr.ValueEGP = o.ValueEGP
				pr.SourceCites = append(pr.SourceCites, RawSourceCite{
					RawName: code, Source: "plan_branch_code",
					SourceTable: o.SourceTable, SourceFile: o.SourceFile, ArchiveID: o.ArchiveID,
				})
				continue
			}
			planCodeProps = append(planCodeProps, PlanBranchCodeRow{
				Code: code, RowCount: o.RowCount, ValueEGP: o.ValueEGP,
				Status: "unmapped_owner_to_name", SourceFile: o.SourceFile, ArchiveID: o.ArchiveID,
			})
			continue
		}

		raw := strings.TrimSpace(o.RawName)
		if raw == "" {
			continue
		}
		slug := strings.ToLower(strings.TrimSpace(o.ChainSlug))
		if slug == "" {
			slug = InferChainSlug(raw)
		}
		pol := PolicyForSlug(slug)
		policiesUsed[slug] = pol

		cite := RawSourceCite{
			RawName: raw, Source: src,
			SourceTable: strings.TrimSpace(o.SourceTable),
			SourceFile:  strings.TrimSpace(o.SourceFile),
			ArchiveID:   strings.TrimSpace(o.ArchiveID),
		}
		addProvenance(src, cite)

		// Parent-company / legal-entity / regional → separate section (not proposed branches).
		if IsParentLevelRaw(raw) {
			kind := ParentLevelKind(raw)
			display := raw
			if kind == "parent_mini" {
				display = raw // keep full spelling; short «ميني» alone is misleading
			}
			pk := kind + "|" + display
			if parentAgg[pk] == nil {
				note := "مستوى أب / غير موزع كفرع — بانتظار قرار المالك"
				switch kind {
				case "parent_company":
					note = "اسم الشركة الأم (ليست فرعًا) — بانتظار قرار المالك"
				case "parent_mini":
					note = "أب - ميني (ليست فرعًا مقترحًا) — بانتظار قرار المالك"
				case "regional":
					note = "مجمع إقليم / Regional — ليست فرعًا مقترحًا"
				}
				parentAgg[pk] = &ParentLevelRow{
					Kind: kind, DisplayName: display, NoteAR: note,
					SourceFile: o.SourceFile, ArchiveID: o.ArchiveID,
				}
			}
			pr := parentAgg[pk]
			pr.RawNames = appendUnique(pr.RawNames, raw)
			if o.RowCount > 0 {
				pr.RowCount = o.RowCount
				pr.ValueEGP = o.ValueEGP
			}
			pr.SourceCites = append(pr.SourceCites, cite)
			continue
		}

		if pol.QuarantineUnknown && !MatchesKnownChainBanner(raw, slug) && !IsUnallocated(raw) {
			quarantined = append(quarantined, QuarantinedRow{
				RawName: raw, ChainSlug: slug, SourceCites: []RawSourceCite{cite},
				ReasonAR: "اسم غير معروف لهذه السلسلة — محجور (quarantine) حتى يقرّر المالك",
			})
			continue
		}

		key := GroupingKey(slug, raw, pol)
		if key == "" {
			continue
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
		g.cites = append(g.cites, cite)
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

		raws := sortedKeys(g.raws)
		multi := len(raws) > 1
		srcHint := joinSources(g.sources)
		_, hasSI := g.sources["sell_in"]
		_, hasSO := g.sources["sell_out"]
		_, hasRet := g.sources["returns"]
		displayRaw := firstRaw(g)
		// Prefer a non-care spelling for the short display when grocery+care share a code
		// (owner: reports show short location name only — always strip chain prefix).
		for _, r := range sortedKeys(g.raws) {
			if !HasCareLine(r) && !IsUnallocated(r) {
				if displayRaw == "" || HasCareLine(displayRaw) || len([]rune(ShortDisplay(r))) <= len([]rune(ShortDisplay(displayRaw))) {
					displayRaw = r
				}
			}
		}
		display := ShortDisplay(displayRaw)
		if display == "" && len(raws) > 0 {
			display = ShortDisplay(raws[0])
		}
		unalloc := IsUnallocated(display) || IsUnallocated(firstRaw(g))
		var code string
		if unalloc {
			code = UnallocatedCode(cc)
			display = UnallocatedBranchName
		} else {
			seq[cc]++
			code = formatBranchCode(cc, seq[cc])
		}
		pol := PolicyForSlug(g.slug)
		care, grocery, kh := false, false, false
		for _, r := range raws {
			if IsCareLineForPolicy(r, pol) {
				care = true
			} else if !IsUnallocated(r) {
				grocery = true
			}
			if HasKHBanner(r) {
				kh = true
			}
		}
		note := ""
		if care && grocery && pol.MergeCareWithGrocery {
			note = "policy: care+grocery same location → one branch (sum in reports; short display)"
			careMerged++
		}
		locType := InferLocationType(raws)
		// SI-only / SO-only are normal (owner #70) — never flag as missing counterpart.
		// Still never auto-link across sources; each row keeps its own name/values.

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
			LocationType:   locType,
		})
	}

	misspellings := detectLikelyMisspellings(rows)
	reconcile, reconcileNotes := buildSourceReconcile(occ)

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
	sort.Strings(ambiguous)

	// Owner (#70): no owner questions from SI-only / SO-only (normal). Plan excluded.
	var ownerQ []string

	var parentRows []ParentLevelRow
	for _, k := range sortedKeys(func() map[string]struct{} {
		m := map[string]struct{}{}
		for id := range parentAgg {
			m[id] = struct{}{}
		}
		return m
	}()) {
		pr := parentAgg[k]
		pr.RawNames = uniqueSorted(pr.RawNames)
		pr.SourceCites = dedupeCites(pr.SourceCites)
		parentRows = append(parentRows, *pr)
	}

	var policyList []ChainPolicy
	for _, slug := range sortedKeys(func() map[string]struct{} {
		m := map[string]struct{}{}
		for s := range policiesUsed {
			m[s] = struct{}{}
		}
		return m
	}()) {
		policyList = append(policyList, policiesUsed[slug])
	}

	notes := []string{
		"هذا تقرير تجريبي (dry-run) فقط — لم يُكتب أي شيء في الإنتاج.",
		"توحيد الفروع = in26.xlsx (Sell-In/Returns) + out26.xlsx (Sell-Out) فقط.",
		"مستبعد من هذا الـ dry-run: Adco_Fathalla_Sell_In_Plan_2026_Clean.xlsx / arch_sellin_adeco_fathalla_1794179188685072646 — بلا صفوف أب/ميني/Regional ولا 16 كودًا. بيانات BQ لم تُحذف ولم تُعدَّل.",
		"المصادر = بيانات Adeco الحية فقط (BigQuery). لا seed_customers / seed_aliases.",
		"قواعد السلسلة قابلة للضبط لكل chain (care+grocery merge، أرقام الفروع، quarantine للأسماء المجهولة).",
		"قرار المالك: مواد عناية + بقالة لنفس الموقع = فرع واحد (FTH)؛ أرقام مختلفة = فروع مختلفة؛ المسافة فقط مع نفس الرقم تُدمَج.",
		"Sell-In = شحنات الشركة وقد يشمل مواقع إضافية (مخازن مثل مخزن الافوجادو) — Sell-In-only طبيعي؛ يُعلَّم type=warehouse عند المخزن.",
		"Sell-Out = نقاط البيع. وجود فرع في ملف واحد فقط (Sell-In فقط أو Sell-Out فقط) طبيعي — لا تحذير ولا سؤال مالك.",
		"لا ربط تلقائي بين مصادر مختلفة؛ كل صف يبقى مستقلاً بقيمه حتى يقرر المالك الدمج. العرض في التقارير = الاسم القصير فقط (بدون «فرع فتح الله -»).",
		fmt.Sprintf("عدد الفروع التي دُمجت فيها مواد عناية + بقالة في هذا dry-run: %d.", careMerged),
		"جسور المالك: الإبراهيمية = الابراهيمية ريفيرا؛ دمنهور = دمنهور الأندلس؛ سيدي جابر = سيدي جابر المحطة. تبقى منفصلة: الإبراهيمية ميني، دمنهور الاستاد، سيدي جابر ميني.",
		"مصدر Returns = صفوف sell_in_records ذات قيمة سالبة أو نوع مرتجع (من in26).",
	}

	return DryRunReport{
		TenantID:           tenantID,
		GeneratedAt:        now,
		RawNameCount:       countRaws(byNorm) + parentRawCount(parentRows),
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
		UnmatchedSellOut:   nil, // owner: SI-only/SO-only are normal — never flag
		AmbiguousPending:   ambiguous,
		LikelyMisspellings: misspellings,
		DataProvenance:     sortedKeys(provenance),
		SourceReconcile:    reconcile,
		ReconcileNotesAR:   reconcileNotes,
		UnmappedPlanCodes:  sortPlanCodeProps(planCodeProps),
		ParentLevelRows:    parentRows,
		QuarantinedRows:    quarantined,
		ChainPolicies:      policyList,
		Rows:               rows,
		NotesAR:            notes,
	}
}

func isRegionalPlanCode(code string) bool {
	c := strings.ToLower(code)
	return strings.Contains(code, "الإقليم") || strings.Contains(c, "regional") || strings.Contains(code, "مجمع")
}

func sortPlanCodeProps(in []PlanBranchCodeRow) []PlanBranchCodeRow {
	sort.Slice(in, func(i, j int) bool {
		ri, rj := isRegionalPlanCode(in[i].Code), isRegionalPlanCode(in[j].Code)
		if ri != rj {
			return ri // regional first
		}
		if in[i].ValueEGP != in[j].ValueEGP {
			return in[i].ValueEGP > in[j].ValueEGP
		}
		return in[i].Code < in[j].Code
	})
	return in
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

// buildSourceReconcile counts raw spellings and unique locations per live source file.
func buildSourceReconcile(occ []RawOccurrence) ([]SourceReconcileRow, []string) {
	type agg struct {
		table, arch string
		raws        map[string]struct{}
		locs        map[string]struct{}
		care, groc  int
	}
	byFile := map[string]*agg{}
	for _, o := range occ {
		raw := strings.TrimSpace(o.RawName)
		file := strings.TrimSpace(o.SourceFile)
		if raw == "" || file == "" {
			continue
		}
		// Count each source stream once per file (sell_in primary; skip returns + plan codes).
		src := strings.ToLower(strings.TrimSpace(o.Source))
		if src == "returns" || src == "plan_branch_code" {
			continue
		}
		a := byFile[file]
		if a == nil {
			a = &agg{table: o.SourceTable, arch: o.ArchiveID, raws: map[string]struct{}{}, locs: map[string]struct{}{}}
			byFile[file] = a
		}
		if _, ok := a.raws[raw]; ok {
			continue
		}
		a.raws[raw] = struct{}{}
		if HasCareLine(raw) {
			a.care++
		} else {
			a.groc++
		}
		if n := LinkNormalize(raw); n != "" {
			a.locs[n] = struct{}{}
		}
	}
	var rows []SourceReconcileRow
	for _, file := range sortedKeys(func() map[string]struct{} {
		m := map[string]struct{}{}
		for k := range byFile {
			m[k] = struct{}{}
		}
		return m
	}()) {
		a := byFile[file]
		note := ""
		switch {
		case strings.Contains(strings.ToLower(file), "out26"):
			note = fmt.Sprintf("Sell-Out wide-matrix stores = %d (this is the «35» live branch count from out26).", len(a.locs))
		case strings.Contains(strings.ToLower(file), "in26"):
			note = fmt.Sprintf("in26: %d grocery + %d care spellings → %d locations after مواد عناية merge with grocery (طنطا Out Let care-only stays separate).",
				a.groc, a.care, len(a.locs))
		case strings.Contains(file, "Plan_2026") || strings.Contains(file, "Sell_In_Plan"):
			note = "Plan_2026_Clean: NO branch-name column. Customer_Name = parent only (2 values). Customer_Branch_Code = Regional bucket + 16 coded branches (listed separately; owner names — do not guess)."
		}
		rows = append(rows, SourceReconcileRow{
			SourceFile:       file,
			SourceTable:      a.table,
			ArchiveID:        a.arch,
			RawSpellings:     len(a.raws),
			CareSpellings:    a.care,
			GrocerySpellings: a.groc,
			UniqueLocations:  len(a.locs),
			NoteAR:           note,
		})
	}
	notes := []string{
		"«35» (Sell-Out) = distinct store_name in live sell_out_facts for out26 archive arch_adeco_fathalla_1794146334922507694.",
		"in26: ~29 grocery + care-only طنطا Out Let ≈ 30 locations after owner care=grocery merge.",
		"Owner (#70): Plan_2026_Clean archive excluded from unification (BQ data untouched). Proposal = in26 + out26 only.",
		"Proposed branch codes = in26/out26 store locations under chain policy; numbered branches stay separate.",
	}
	return rows, notes
}

func appendUnique(in []string, v string) []string {
	for _, x := range in {
		if x == v {
			return in
		}
	}
	return append(in, v)
}

func uniqueSorted(in []string) []string {
	m := map[string]struct{}{}
	for _, s := range in {
		m[s] = struct{}{}
	}
	return sortedKeys(m)
}

func parentRawCount(rows []ParentLevelRow) int {
	n := 0
	for _, r := range rows {
		n += len(r.RawNames)
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
	// Owner: different numbers = different branches (نيس ≠ نيس2, كفر الدوار ≠ كفر الدوار 2).
	if trailingNumber(a) != trailingNumber(b) {
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
	// Same after removing spaces only (e.g. residual whitespace variants).
	return strings.ReplaceAll(a, " ", "") == strings.ReplaceAll(b, " ", "")
}

// trailingNumber returns the trailing digit run, or "" if none (نيس vs نيس2 → "", "2").
func trailingNumber(s string) string {
	runes := []rune(strings.TrimSpace(s))
	i := len(runes) - 1
	for i >= 0 && runes[i] >= '0' && runes[i] <= '9' {
		i--
	}
	if i == len(runes)-1 {
		return ""
	}
	return string(runes[i+1:])
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
