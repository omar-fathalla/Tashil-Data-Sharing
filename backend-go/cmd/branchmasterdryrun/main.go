// Command branchmasterdryrun builds a one-time Adeco branch-master proposal
// from embedded Sell-In seed customer names (+ optional JSON occurrences file).
// It writes Markdown + JSON under an output directory and NEVER writes production data.
//
//	go run ./cmd/branchmasterdryrun -out /path/to/docs -tenant adeco
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
	flag.Parse()

	var occ []branchmaster.RawOccurrence

	// Seed Sell-In customer names (current Adeco registry source of truth in-repo).
	for _, name := range customers.SeedCustomerNames() {
		occ = append(occ, branchmaster.RawOccurrence{
			RawName:   name,
			ChainSlug: branchmaster.InferChainSlug(name),
			Source:    "sell_in",
		})
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

	// Always include the unallocated synthetic bucket so the proposal documents it.
	occ = append(occ, branchmaster.RawOccurrence{
		RawName:   branchmaster.UnallocatedBranchName,
		ChainSlug: "fathalla",
		Source:    "sell_out",
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
	if err := os.WriteFile(mdPath, []byte(renderMarkdown(report)), 0o644); err != nil {
		fmt.Fprintf(os.Stderr, "write md: %v\n", err)
		os.Exit(1)
	}
	fmt.Printf("wrote %s\nwrote %s\nrows=%d unique_norm=%d chains=%d\n",
		mdPath, jsonPath, report.BranchCount, report.UniqueNormCount, report.ChainCount)
}

func renderMarkdown(r branchmaster.DryRunReport) string {
	var b strings.Builder
	b.WriteString("# Adeco branch master — dry-run proposal\n\n")
	b.WriteString("**Status: HOLD — owner approval required before any production write.**\n\n")
	b.WriteString(fmt.Sprintf("- Tenant: `%s`\n", r.TenantID))
	b.WriteString(fmt.Sprintf("- Generated (UTC): `%s`\n", r.GeneratedAt.Format(time.RFC3339)))
	b.WriteString(fmt.Sprintf("- Raw name observations: **%d**\n", r.RawNameCount))
	b.WriteString(fmt.Sprintf("- Unique normalized keys: **%d**\n", r.UniqueNormCount))
	b.WriteString(fmt.Sprintf("- Proposed chains: **%d** · branches: **%d**\n\n", r.ChainCount, r.BranchCount))
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
	b.WriteString("Owner reviews this sheet, then `POST /api/v1/branches/bootstrap/confirm` with the JSON payload ")
	b.WriteString("(`adeco-branch-master-dry-run.json`) — **not** done by this dry-run.\n")
	return b.String()
}
