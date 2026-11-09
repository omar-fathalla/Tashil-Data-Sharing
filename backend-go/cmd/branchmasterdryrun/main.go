// Command branchmasterdryrun builds a one-time Adeco branch-master proposal
// from Sell-In seed names + optional Sell-Out wide-matrix headers (out26) + Returns.
// It writes Markdown + JSON under an output directory and NEVER writes production data.
//
//	go run ./cmd/branchmasterdryrun -out /path/to/docs -tenant adeco \
//	  -sellout-xlsx "backend-go/data/archive/tenant-adeco/arch_adeco_fathalla_*_2026 out.xlsx"
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
	"github.com/tashil/data-sharing/backend/internal/service/customers"
)

func main() {
	outDir := flag.String("out", ".", "output directory for dry-run artifacts")
	tenant := flag.String("tenant", "adeco", "tenant id for the proposal")
	extra := flag.String("extra", "", "optional JSON file of []RawOccurrence")
	sellOutXLSX := flag.String("sellout-xlsx", "", "Sell-Out wide-matrix workbook (out26) — branch headers only")
	flag.Parse()

	var occ []branchmaster.RawOccurrence

	// Sell-In (+ Returns): seed customer names are the Sell-In/Returns customer column.
	for _, name := range customers.SeedCustomerNames() {
		slug := branchmaster.InferChainSlug(name)
		occ = append(occ, branchmaster.RawOccurrence{RawName: name, ChainSlug: slug, Source: "sell_in"})
		occ = append(occ, branchmaster.RawOccurrence{RawName: name, ChainSlug: slug, Source: "returns"})
	}
	for from, to := range customers.SeedAliasPairs() {
		slug := branchmaster.InferChainSlug(to)
		occ = append(occ, branchmaster.RawOccurrence{RawName: from, ChainSlug: slug, Source: "sell_in"})
		occ = append(occ, branchmaster.RawOccurrence{RawName: to, ChainSlug: slug, Source: "sell_in"})
	}

	xlsxPath := strings.TrimSpace(*sellOutXLSX)
	if xlsxPath == "" {
		xlsxPath = discoverDefaultSellOutXLSX()
	}
	if xlsxPath != "" {
		branches, err := readWideMatrixBranches(xlsxPath)
		if err != nil {
			fmt.Fprintf(os.Stderr, "sell-out xlsx: %v\n", err)
			os.Exit(1)
		}
		fmt.Fprintf(os.Stderr, "sell-out branches from %s: %d\n", xlsxPath, len(branches))
		for _, b := range branches {
			occ = append(occ, branchmaster.RawOccurrence{
				RawName: b, ChainSlug: "fathalla", Source: "sell_out",
			})
		}
	}

	if *extra != "" {
		raw, err := os.ReadFile(*extra)
		if err != nil {
			fmt.Fprintf(os.Stderr, "read extra: %v\n", err)
			os.Exit(1)
		}
		var more []branchmaster.RawOccurrence
		if err := json.Unmarshal(raw, &more); err != nil {
			fmt.Fprintf(os.Stderr, "parse extra: %v\n", err)
			os.Exit(1)
		}
		occ = append(occ, more...)
	}

	occ = append(occ, branchmaster.RawOccurrence{
		RawName: branchmaster.UnallocatedBranchName, ChainSlug: "fathalla", Source: "sell_out",
	})

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
	if err := os.WriteFile(mdPath, []byte(renderMarkdown(report, xlsxPath)), 0o644); err != nil {
		fmt.Fprintf(os.Stderr, "write md: %v\n", err)
		os.Exit(1)
	}
	fmt.Printf("wrote %s\nwrote %s\nrows=%d si+so=%d si_only=%d so_only=%d unmatched_so=%d questions=%d\n",
		mdPath, jsonPath, report.BranchCount, report.SellInAndOut, report.SellInOnly, report.SellOutOnly,
		len(report.UnmatchedSellOut), len(report.OwnerQuestions))
}

func discoverDefaultSellOutXLSX() string {
	candidates := []string{
		"backend-go/data/archive/tenant-adeco/arch_adeco_fathalla_1792258238476465882_2026 out.xlsx",
		"../data/archive/tenant-adeco/arch_adeco_fathalla_1792258238476465882_2026 out.xlsx",
		"data/archive/tenant-adeco/arch_adeco_fathalla_1792258238476465882_2026 out.xlsx",
	}
	for _, c := range candidates {
		if st, err := os.Stat(c); err == nil && !st.IsDir() {
			return c
		}
	}
	return ""
}

// readWideMatrixBranches reads the first header row of a Sell-Out wide matrix and
// returns distinct branch display columns (skips barcode/meta/qty/month columns).
// Uses raw ZIP+XML so we do not depend on excelize/openpyxl in CI.
func readWideMatrixBranches(path string) ([]string, error) {
	// Prefer a tiny shared helper via python if available is avoided in Go path —
	// ship a minimal OOXML sharedStrings + sheet1 row1 reader.
	return readXLSXHeaderBranches(path)
}

func renderMarkdown(r branchmaster.DryRunReport, sellOutPath string) string {
	var b strings.Builder
	b.WriteString("# Adeco branch master — dry-run proposal\n\n")
	b.WriteString("**Status: HOLD — owner approval required before any production write.**\n\n")
	b.WriteString(fmt.Sprintf("- Tenant: `%s`\n", r.TenantID))
	b.WriteString(fmt.Sprintf("- Generated (UTC): `%s`\n", r.GeneratedAt.Format(time.RFC3339)))
	if sellOutPath != "" {
		b.WriteString(fmt.Sprintf("- Sell-Out source: `%s` (header branch columns only; file not modified)\n", filepath.Base(sellOutPath)))
	}
	b.WriteString(fmt.Sprintf("- Raw name observations: **%d**\n", r.RawNameCount))
	b.WriteString(fmt.Sprintf("- Unique normalized keys / proposed branches: **%d**\n", r.UniqueNormCount))
	b.WriteString(fmt.Sprintf("- Chains: **%d**\n\n", r.ChainCount))

	b.WriteString("## Top summary\n\n")
	b.WriteString(fmt.Sprintf("| Metric | Count |\n| --- | ---: |\n"))
	b.WriteString(fmt.Sprintf("| Sell-In **and** Sell-Out | %d |\n", r.SellInAndOut))
	b.WriteString(fmt.Sprintf("| Sell-In only | %d |\n", r.SellInOnly))
	b.WriteString(fmt.Sprintf("| Sell-Out only | %d |\n", r.SellOutOnly))
	b.WriteString(fmt.Sprintf("| Multi-spelling merges | %d |\n", r.MultiSpelling))
	b.WriteString(fmt.Sprintf("| Branches with Returns coverage | %d |\n", r.ReturnsCovered))
	b.WriteString(fmt.Sprintf("| Unmatched Sell-Out (no Sell-In counterpart) | %d |\n", len(r.UnmatchedSellOut)))
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

	if len(r.OwnerQuestions) > 0 {
		b.WriteString("### Owner questions (do not guess)\n\n")
		for i, q := range r.OwnerQuestions {
			b.WriteString(fmt.Sprintf("%d. %s\n", i+1, q))
		}
		b.WriteString("\n")
	}

	if len(r.UnmatchedSellOut) > 0 {
		b.WriteString("### Unmatched Sell-Out names\n\n")
		b.WriteString("Present in out26 headers but no Sell-In customer normalized to the same short name:\n\n")
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

	b.WriteString("\n## Proposed branches\n\n")
	b.WriteString("| Code | Chain | Display (short) | Raw spellings | Sources |\n")
	b.WriteString("| --- | --- | --- | --- | --- |\n")
	rows := append([]branchmaster.ProposalRow(nil), r.Rows...)
	sort.Slice(rows, func(i, j int) bool { return rows[i].BranchCode < rows[j].BranchCode })
	for _, row := range rows {
		raws := strings.Join(row.RawNames, "<br>")
		if len(row.RawNames) > 4 {
			raws = strings.Join(row.RawNames[:4], "<br>") + fmt.Sprintf("<br>… +%d", len(row.RawNames)-4)
		}
		display := row.DisplayName
		if row.Unallocated {
			display = "**" + display + "**"
		}
		b.WriteString(fmt.Sprintf("| `%s` | %s (`%s`) | %s | %s | %s |\n",
			row.BranchCode, row.ChainSlug, row.ChainCode, display, raws, row.SourceHint))
	}
	b.WriteString("\n## Next step\n\n")
	b.WriteString("Owner answers the questions above, then `POST /api/v1/branches/bootstrap/confirm` ")
	b.WriteString("with the JSON payload — **not** done by this dry-run.\n")
	return b.String()
}
