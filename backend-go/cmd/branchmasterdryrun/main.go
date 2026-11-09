// Command branchmasterdryrun builds a one-time Adeco branch-master proposal
// from LIVE BigQuery occurrences only (JSON export). It NEVER invents names from
// seed_customers / seed_aliases / old archive xlsx, and NEVER writes production data.
//
//	go run ./cmd/branchmasterdryrun -out /path/to/docs -tenant adeco \
//	  -live-json /path/to/adeco-live-occurrences.json
package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"

	"github.com/tashil/data-sharing/backend/internal/service/branchmaster"
)

func main() {
	outDir := flag.String("out", ".", "output directory for dry-run artifacts")
	tenant := flag.String("tenant", "adeco", "tenant id for the proposal")
	liveJSON := flag.String("live-json", "", "required JSON file of []RawOccurrence from live BQ (with source_table/source_file)")
	flag.Parse()

	if strings.TrimSpace(*liveJSON) == "" {
		fmt.Fprintf(os.Stderr, "refusing to run without -live-json (seed_customers/seed_aliases permanently disabled for dry-run)\n")
		os.Exit(2)
	}
	// Permanent guard: this command must never import or call customers.Seed*.
	raw, err := os.ReadFile(*liveJSON)
	if err != nil {
		fmt.Fprintf(os.Stderr, "read live-json: %v\n", err)
		os.Exit(1)
	}
	var occ []branchmaster.RawOccurrence
	if err := json.Unmarshal(raw, &occ); err != nil {
		fmt.Fprintf(os.Stderr, "parse live-json: %v\n", err)
		os.Exit(1)
	}
	if len(occ) == 0 {
		fmt.Fprintf(os.Stderr, "live-json is empty\n")
		os.Exit(1)
	}
	for i, o := range occ {
		if strings.TrimSpace(o.RawName) == "" {
			fmt.Fprintf(os.Stderr, "live-json[%d]: empty raw_name\n", i)
			os.Exit(1)
		}
		if strings.TrimSpace(o.SourceTable) == "" && strings.TrimSpace(o.SourceFile) == "" {
			fmt.Fprintf(os.Stderr, "live-json[%d] %q: missing source_table/source_file citation\n", i, o.RawName)
			os.Exit(1)
		}
	}
	kept, skipped := branchmaster.FilterUnificationSources(occ)
	if skipped > 0 {
		fmt.Fprintf(os.Stderr, "excluded %d Plan_2026 / non-unification rows (BQ data untouched)\n", skipped)
	}
	occ = kept
	if len(occ) == 0 {
		fmt.Fprintf(os.Stderr, "no in26/out26 occurrences left after Plan exclusion\n")
		os.Exit(1)
	}
	fmt.Fprintf(os.Stderr, "live occurrences: %d from %s (unification = in26.xlsx + out26.xlsx only)\n", len(occ), *liveJSON)

	report := branchmaster.BuildDryRunProposal(*tenant, occ)
	if err := os.MkdirAll(*outDir, 0o755); err != nil {
		fmt.Fprintf(os.Stderr, "mkdir: %v\n", err)
		os.Exit(1)
	}
	jsonPath := filepath.Join(*outDir, "adeco-branch-master-dry-run.json")
	mdPath := filepath.Join(*outDir, "adeco-branch-master-dry-run.md")
	jb, _ := json.MarshalIndent(report, "", "  ")
	if err := os.WriteFile(jsonPath, jb, 0o644); err != nil {
		fmt.Fprintf(os.Stderr, "write json: %v\n", err)
		os.Exit(1)
	}
	if err := os.WriteFile(mdPath, []byte(renderMarkdown(report, *liveJSON)), 0o644); err != nil {
		fmt.Fprintf(os.Stderr, "write md: %v\n", err)
		os.Exit(1)
	}
	fmt.Printf("wrote %s\nwrote %s\nrows=%d chains=%d si+so=%d si_only=%d so_only=%d unmatched_so=%d questions=%d\n",
		mdPath, jsonPath, report.BranchCount, report.ChainCount, report.SellInAndOut, report.SellInOnly, report.SellOutOnly,
		len(report.UnmatchedSellOut), len(report.OwnerQuestions))
}

func renderMarkdown(r branchmaster.DryRunReport, liveJSONPath string) string {
	var b strings.Builder
	b.WriteString("---\n")
	b.WriteString("cursor:\n")
	b.WriteString("  subagentId: \"bc-c458e397-32ee-5f05-a5fe-2e7cd211dee3\"\n")
	b.WriteString("---\n\n")
	b.WriteString("# Adeco branch master — dry-run proposal\n\n")
	b.WriteString("**Status: HOLD — owner approval required before any production write.**\n\n")
	b.WriteString(fmt.Sprintf("- Tenant: `%s`\n", r.TenantID))
	b.WriteString(fmt.Sprintf("- Generated (UTC): `%s`\n", r.GeneratedAt.Format(time.RFC3339)))
	b.WriteString(fmt.Sprintf("- Live input: `%s`\n", filepath.Base(liveJSONPath)))
	b.WriteString("- **Unification sources only:** `in26.xlsx` (Sell-In + Returns) + `out26.xlsx` (Sell-Out)\n")
	b.WriteString("- **Excluded (BQ untouched):** `Adco_Fathalla_Sell_In_Plan_2026_Clean.xlsx` / `arch_sellin_adeco_fathalla_1794179188685072646` — no parent/mini/Regional/16 codes in this proposal\n")
	b.WriteString(fmt.Sprintf("- Raw name observations: **%d**\n", r.RawNameCount))
	b.WriteString(fmt.Sprintf("- Unique normalized keys / proposed branches: **%d**\n", r.UniqueNormCount))
	b.WriteString(fmt.Sprintf("- Chains: **%d**\n\n", r.ChainCount))

	b.WriteString("## Source of prior false names (corrected)\n\n")
	b.WriteString("Earlier dry-runs listed «كيه اتش جمله ماركت …» and «فتح الله بيت الجمله …» (BET).\n")
	b.WriteString("Those came from **embedded fixtures**, not live Adeco BQ:\n\n")
	b.WriteString("- `backend-go/internal/service/customers/seed_customers.json` (199 names; ~60 KH, ~30 BET)\n")
	b.WriteString("- `backend-go/internal/service/customers/seed_aliases.json` (~60 KH alias pairs)\n")
	b.WriteString("- wired by `cmd/branchmasterdryrun` via `customers.SeedCustomerNames()` / `SeedAliasPairs()`\n")
	b.WriteString("- plus an **old local archive xlsx** header pass (`arch_adeco_fathalla_1792258238476465882_2026 out.xlsx`), not current `out26`\n\n")
	b.WriteString("Checked and **not** the source: live `sell_in_records`, live `sell_out_facts`, and `sell_in_records_backup_20261109_in26` contain **no** `كيه اتش` / `بيت الجمله` tokens.\n")
	b.WriteString("This dry-run uses **live BQ in26+out26 only** (Plan archive excluded from unification; not deleted).\n\n")

	if len(r.DataProvenance) > 0 {
		b.WriteString("## Data provenance (live)\n\n")
		for _, p := range r.DataProvenance {
			b.WriteString("- " + p + "\n")
		}
		b.WriteString("\n")
	}

	if len(r.SourceReconcile) > 0 {
		b.WriteString("## Per-source branch count reconciliation\n\n")
		b.WriteString("| Source file | Table | Raw spellings | Care | Grocery/other | Unique locations | Note |\n")
		b.WriteString("| --- | --- | ---: | ---: | ---: | ---: | --- |\n")
		for _, s := range r.SourceReconcile {
			b.WriteString(fmt.Sprintf("| `%s` | `%s` | %d | %d | %d | %d | %s |\n",
				s.SourceFile, s.SourceTable, s.RawSpellings, s.CareSpellings, s.GrocerySpellings, s.UniqueLocations, s.NoteAR))
		}
		b.WriteString("\n")
		for _, n := range r.ReconcileNotesAR {
			b.WriteString("- " + n + "\n")
		}
		b.WriteString("\n")
	}

	unmappedPlan := 0
	for _, p := range r.UnmappedPlanCodes {
		if p.Status == "unmapped_owner_to_name" {
			unmappedPlan++
		}
	}

	b.WriteString("## Top summary\n\n")
	b.WriteString("| Metric | Count |\n| --- | ---: |\n")
	b.WriteString(fmt.Sprintf("| Sell-In **and** Sell-Out | %d |\n", r.SellInAndOut))
	b.WriteString(fmt.Sprintf("| Sell-In only | %d |\n", r.SellInOnly))
	b.WriteString(fmt.Sprintf("| Sell-Out only | %d |\n", r.SellOutOnly))
	b.WriteString(fmt.Sprintf("| Multi-spelling merges | %d |\n", r.MultiSpelling))
	b.WriteString(fmt.Sprintf("| Branches with Returns coverage | %d |\n", r.ReturnsCovered))
	b.WriteString(fmt.Sprintf("| Unmatched Sell-Out (no Sell-In counterpart) | %d |\n", len(r.UnmatchedSellOut)))
	b.WriteString(fmt.Sprintf("| Unmapped Plan branch codes (owner to name) | %d |\n", unmappedPlan))
	b.WriteString(fmt.Sprintf("| Likely misspelling pairs | %d |\n", len(r.LikelyMisspellings)))
	b.WriteString(fmt.Sprintf("| Owner questions / ambiguous | %d / %d |\n\n", len(r.OwnerQuestions), len(r.AmbiguousPending)))

	if len(r.ChainSummaries) > 0 {
		b.WriteString("### Per chain\n\n")
		b.WriteString("| Chain | Code | Branches | SI+SO | SI only | SO only | +Returns |\n")
		b.WriteString("| --- | --- | ---: | ---: | ---: | ---: | ---: |\n")
		for _, c := range r.ChainSummaries {
			b.WriteString(fmt.Sprintf("| %s | `%s` | %d | %d | %d | %d | %d |\n",
				c.ChainSlug, c.ChainCode, c.Branches, c.SellInOut, c.SellInOnly, c.SellOutOnly, c.ReturnsHit))
		}
		b.WriteString("\n")
	}

	if len(r.ParentLevelRows) > 0 {
		b.WriteString("## Unallocated / parent-level (NOT proposed branches)\n\n")
		b.WriteString("Parent company names and Regional are **not** store branches. Totals kept for reconcile; owner decides mapping later.\n\n")
		b.WriteString("| Kind | Display | Rows | Value EGP | Source file | Note |\n")
		b.WriteString("| --- | --- | ---: | ---: | --- | --- |\n")
		for _, p := range r.ParentLevelRows {
			b.WriteString(fmt.Sprintf("| `%s` | %s | %d | %.2f | `%s` | %s |\n",
				p.Kind, p.DisplayName, p.RowCount, p.ValueEGP, p.SourceFile, p.NoteAR))
		}
		b.WriteString("\n")
	}

	if len(r.ChainPolicies) > 0 {
		b.WriteString("### Chain policies in effect\n\n")
		b.WriteString("| Slug | Care+grocery merge | Numbered distinct | Quarantine unknown |\n")
		b.WriteString("| --- | --- | --- | --- |\n")
		for _, p := range r.ChainPolicies {
			b.WriteString(fmt.Sprintf("| `%s` | %v | %v | %v |\n",
				p.Slug, p.MergeCareWithGrocery, p.KeepNumberedDistinct, p.QuarantineUnknown))
		}
		b.WriteString("\n")
	}

	if len(r.QuarantinedRows) > 0 {
		b.WriteString("### Quarantined unknown names\n\n")
		for _, q := range r.QuarantinedRows {
			b.WriteString(fmt.Sprintf("- `%s` (%s): %s\n", q.RawName, q.ChainSlug, q.ReasonAR))
		}
		b.WriteString("\n")
	}

	if len(r.OwnerQuestions) > 0 {
		b.WriteString("### Owner questions (do not guess)\n\n")
		for i, q := range r.OwnerQuestions {
			b.WriteString(fmt.Sprintf("%d. %s\n", i+1, q))
		}
		b.WriteString("\n")
	}

	if len(r.LikelyMisspellings) > 0 {
		b.WriteString("### Likely misspelling pairs (owner confirm)\n\n")
		b.WriteString("Kept as separate proposed codes until owner confirms merge:\n\n")
		for _, m := range r.LikelyMisspellings {
			b.WriteString("- " + m + "\n")
		}
		b.WriteString("\n")
	}

	if len(r.UnmappedPlanCodes) > 0 {
		b.WriteString("### Plan_2026_Clean Customer_Branch_Code\n\n")
		b.WriteString("File has **no branch-name column**. `Customer_Name` = parent only. Codes below are live BQ `customer_branch_code` — ")
		b.WriteString("**do not guess names**. Each unmapped code stays listed and counted under its **original raw code** as display until the owner names/maps it.\n\n")
		b.WriteString("| Code (raw display) | Rows | Value EGP | Status |\n| --- | ---: | ---: | --- |\n")
		for _, p := range r.UnmappedPlanCodes {
			status := p.Status
			if status == "unmapped_owner_to_name" {
				status = "unmapped — keep raw code as display until owner maps"
			}
			if status == "regional_parent_level" || status == "regional_bucket" {
				status = "Regional → parent-level (not a proposed branch)"
			}
			b.WriteString(fmt.Sprintf("| `%s` | %d | %.2f | %s |\n", p.Code, p.RowCount, p.ValueEGP, status))
		}
		b.WriteString("\n")
	}

	if len(r.UnmatchedSellOut) > 0 {
		b.WriteString("### Unmatched Sell-Out names\n\n")
		b.WriteString("Present in live `sell_out_facts` (out26) but **missing Sell-In counterpart**. ")
		b.WriteString("Each stays visible as its **own row** with the **original raw** display name until the owner maps it — never hidden, never guess-merged to a warehouse/Regional:\n\n")
		for _, u := range r.UnmatchedSellOut {
			b.WriteString("- " + u + "\n")
		}
		b.WriteString("\n")
	}

	if len(r.AmbiguousPending) > 0 {
		b.WriteString("### Ambiguous / pending owner decision\n\n")
		for _, a := range r.AmbiguousPending {
			b.WriteString("- " + a + "\n")
		}
		b.WriteString("\n")
	}

	b.WriteString("## Notes\n\n")
	for _, n := range r.NotesAR {
		b.WriteString("- " + n + "\n")
	}

	b.WriteString("\n## Sell-In vs Sell-Out rules\n\n")
	b.WriteString("- **Sell-In** = company shipments; may include extra locations (warehouses / مخزن*). SI-only is valid; those rows are typed `warehouse`.\n")
	b.WriteString("- **Sell-Out** = points of sale only; every SO branch must have a Sell-In counterpart.\n")
	b.WriteString("- **Sell-Out-only** = `missing Sell-In counterpart` (owner question). Never auto-link to warehouses or Regional.\n")
	b.WriteString("- **Unmapped** names/codes keep their **original raw** as display, stay visible and counted as their own row until the owner maps them — never hidden, never guess-merged.\n\n")

	b.WriteString("## Proposed branches\n\n")
	b.WriteString("| Code | Chain | Type | Display | Raw spellings (with source) | Sources |\n")
	b.WriteString("| --- | --- | --- | --- | --- | --- |\n")
	rows := append([]branchmaster.ProposalRow(nil), r.Rows...)
	sort.Slice(rows, func(i, j int) bool { return rows[i].BranchCode < rows[j].BranchCode })
	for _, row := range rows {
		raws := formatRawCites(row)
		display := row.DisplayName
		if row.Unallocated {
			display = "**" + display + "**"
		}
		loc := row.LocationType
		if loc == "" {
			loc = "store"
		}
		b.WriteString(fmt.Sprintf("| `%s` | %s (`%s`) | %s | %s | %s | %s |\n",
			row.BranchCode, row.ChainSlug, row.ChainCode, loc, display, raws, row.SourceHint))
	}
	b.WriteString("\n## Next step\n\n")
	b.WriteString("Owner answers the PENDING questions above, then `POST /api/v1/branches/bootstrap/confirm` ")
	b.WriteString("with the JSON payload — **not** done by this dry-run.\n")
	return b.String()
}

func formatRawCites(row branchmaster.ProposalRow) string {
	if len(row.RawSourceCites) == 0 {
		return strings.Join(row.RawNames, "<br>")
	}
	byRaw := map[string][]string{}
	order := []string{}
	seen := map[string]struct{}{}
	for _, c := range row.RawSourceCites {
		if _, ok := seen[c.RawName]; !ok {
			seen[c.RawName] = struct{}{}
			order = append(order, c.RawName)
		}
		label := c.Source
		if c.SourceFile != "" {
			label += ":" + c.SourceFile
		} else if c.SourceTable != "" {
			label += ":" + c.SourceTable
		}
		byRaw[c.RawName] = append(byRaw[c.RawName], label)
	}
	var parts []string
	limit := len(order)
	extra := 0
	if limit > 4 {
		extra = limit - 4
		limit = 4
	}
	for _, name := range order[:limit] {
		tags := uniqueStrings(byRaw[name])
		parts = append(parts, fmt.Sprintf("%s _(%s)_", name, strings.Join(tags, ", ")))
	}
	out := strings.Join(parts, "<br>")
	if extra > 0 {
		out += fmt.Sprintf("<br>… +%d", extra)
	}
	return out
}

func uniqueStrings(in []string) []string {
	seen := map[string]struct{}{}
	var out []string
	for _, s := range in {
		if _, ok := seen[s]; ok {
			continue
		}
		seen[s] = struct{}{}
		out = append(out, s)
	}
	sort.Strings(out)
	return out
}
