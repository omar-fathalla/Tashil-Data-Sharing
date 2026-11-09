package branchmaster

import "testing"

func TestChainPolicy_CareMergeConfigurable(t *testing.T) {
	fth := PolicyForSlug("fathalla")
	if !fth.MergeCareWithGrocery || !fth.KeepNumberedDistinct {
		t.Fatalf("fathalla policy: %+v", fth)
	}
	acme := PolicyForSlug("acme")
	if acme.MergeCareWithGrocery {
		t.Fatal("acme synthetic chain must NOT merge care+grocery")
	}

	// Fathalla: care + grocery → same grouping key
	kg := GroupingKey("fathalla", "عائله فتح الله ماركت - سموحة", fth)
	kc := GroupingKey("fathalla", "عائله فتح الله ماركت مواد عناية - سموحة", fth)
	if kg != kc {
		t.Fatalf("fathalla care/grocery should share key: %q vs %q", kg, kc)
	}

	// Acme: care + grocery → different keys
	ag := GroupingKey("acme", "Acme Market - Downtown", acme)
	ac := GroupingKey("acme", "Acme Market مواد عناية - Downtown", acme)
	if ag == ac {
		t.Fatalf("acme care/grocery must stay separate: %q vs %q", ag, ac)
	}
}

func TestChainPolicy_NumberedDistinct(t *testing.T) {
	p := PolicyForSlug("fathalla")
	a := GroupingKey("fathalla", "عائله فتح الله ماركت - كفر الدوار", p)
	b := GroupingKey("fathalla", "عائله فتح الله ماركت - كفر الدوار 2", p)
	c := GroupingKey("fathalla", "عائله فتح الله ماركت مواد عناية - كفر الدوار2", p)
	if a == b {
		t.Fatal("different numbers must not share a key")
	}
	if b != c {
		t.Fatalf("same number whitespace variants must share key: %q vs %q", b, c)
	}
}

func TestDryRun_SecondChainAndQuarantine(t *testing.T) {
	report := BuildDryRunProposal("tenant-x", []RawOccurrence{
		{RawName: "Acme Market - North", ChainSlug: "acme", Source: "sell_in", SourceTable: "t.sell_in", SourceFile: "acme.xlsx"},
		{RawName: "Acme Market مواد عناية - North", ChainSlug: "acme", Source: "sell_in", SourceTable: "t.sell_in", SourceFile: "acme.xlsx"},
		{RawName: "Random Unknown Store", ChainSlug: "acme", Source: "sell_in", SourceTable: "t.sell_in", SourceFile: "acme.xlsx"},
		{RawName: "عائله فتح الله ماركت - سموحة", ChainSlug: "fathalla", Source: "sell_in", SourceTable: "t.sell_in", SourceFile: "in26.xlsx"},
		{RawName: "عائله فتح الله ماركت مواد عناية - سموحة", ChainSlug: "fathalla", Source: "sell_in", SourceTable: "t.sell_in", SourceFile: "in26.xlsx"},
	})
	if report.ChainCount < 2 {
		t.Fatalf("expected ≥2 chains, got %d summaries=%v", report.ChainCount, report.ChainSummaries)
	}
	// Acme: 2 proposed (care≠grocery) + 1 quarantined
	acmeBranches := 0
	for _, r := range report.Rows {
		if r.ChainSlug == "acme" {
			acmeBranches++
		}
	}
	if acmeBranches != 2 {
		t.Fatalf("acme proposed branches=%d want 2 (care separate)", acmeBranches)
	}
	if len(report.QuarantinedRows) < 1 {
		t.Fatalf("expected quarantined unknown name, got %v", report.QuarantinedRows)
	}
	// Fathalla smouha care+grocery merged → 1 branch
	fth := 0
	for _, r := range report.Rows {
		if r.ChainSlug == "fathalla" {
			fth++
		}
	}
	if fth != 1 {
		t.Fatalf("fathalla smouha merged branches=%d want 1", fth)
	}
}

func TestDryRun_ParentLevelNotProposed(t *testing.T) {
	report := BuildDryRunProposal("adeco", []RawOccurrence{
		{RawName: "عائله فتح الله ماركت لتصنيع وتجاره السلع الغذائيه ش م م", ChainSlug: "fathalla", Source: "sell_in",
			SourceTable: "t.sell_in", SourceFile: "Adco_Fathalla_Sell_In_Plan_2026_Clean.xlsx", RowCount: 7622, ValueEGP: 100},
		{RawName: "عائله فتح الله ماركت لتصنيع وتجاره السلع الغذائيه ش م م - ميني", ChainSlug: "fathalla", Source: "sell_in",
			SourceTable: "t.sell_in", SourceFile: "Adco_Fathalla_Sell_In_Plan_2026_Clean.xlsx", RowCount: 204, ValueEGP: 20},
		{RawName: "مجمع الإقليم (Regional)", PlanCode: "مجمع الإقليم (Regional)", ChainSlug: "fathalla", Source: "plan_branch_code",
			SourceTable: "t.sell_in", SourceFile: "Adco_Fathalla_Sell_In_Plan_2026_Clean.xlsx", RowCount: 6129, ValueEGP: 50},
		{RawName: "عائله فتح الله ماركت - سموحة", ChainSlug: "fathalla", Source: "sell_in",
			SourceTable: "t.sell_in", SourceFile: "in26.xlsx"},
	})
	for _, r := range report.Rows {
		if IsParentLevelRaw(r.DisplayName) || stringsContainsAny(r.DisplayName, "إقليم", "تصنيع", "مجمع") {
			t.Fatalf("parent-level leaked into proposed branches: %+v", r)
		}
		for _, n := range r.RawNames {
			if IsParentLevelRaw(n) {
				t.Fatalf("parent raw in proposed: %q", n)
			}
		}
	}
	if len(report.ParentLevelRows) < 3 {
		t.Fatalf("parent_level_rows=%d want ≥3: %+v", len(report.ParentLevelRows), report.ParentLevelRows)
	}
}

func stringsContainsAny(s string, subs ...string) bool {
	for _, sub := range subs {
		if len(sub) > 0 && stringIndex(s, sub) >= 0 {
			return true
		}
	}
	return false
}

func TestDryRun_UnmappedKeepsOriginalRawDisplay(t *testing.T) {
	report := BuildDryRunProposal("adeco", []RawOccurrence{
		{RawName: "فرع فتح الله - الأنفوشي", ChainSlug: "fathalla", Source: "sell_out",
			SourceTable: "t.sell_out", SourceFile: "out26.xlsx"},
		{RawName: "عائله فتح الله ماركت - مخزن الافوجادو", ChainSlug: "fathalla", Source: "sell_in",
			SourceTable: "t.sell_in", SourceFile: "in26.xlsx"},
	})
	var anfoushy, warehouse *ProposalRow
	for i := range report.Rows {
		r := &report.Rows[i]
		if stringIndex(r.DisplayName, "الأنفوشي") >= 0 || stringIndex(stringsJoin(r.RawNames), "الأنفوشي") >= 0 {
			anfoushy = r
		}
		if r.LocationType == "warehouse" || stringIndex(r.DisplayName, "افوجادو") >= 0 {
			warehouse = r
		}
	}
	if anfoushy == nil {
		t.Fatalf("Sell-Out-only anfoushy missing from rows (must stay visible): %+v", report.Rows)
	}
	const wantRaw = "فرع فتح الله - الأنفوشي"
	if anfoushy.DisplayName != wantRaw {
		t.Fatalf("unmapped must keep ORIGINAL raw as display (not ShortDisplay), got %q want %q", anfoushy.DisplayName, wantRaw)
	}
	if ShortDisplay(wantRaw) == wantRaw {
		t.Fatal("test invariant: ShortDisplay would have changed the raw — fixture needs a prefixed name")
	}
	if len(report.UnmatchedSellOut) == 0 || stringIndex(report.UnmatchedSellOut[0], "missing Sell-In counterpart") < 0 {
		t.Fatalf("expected missing Sell-In counterpart flag, got %v", report.UnmatchedSellOut)
	}
	if warehouse == nil || warehouse.LocationType != "warehouse" {
		t.Fatalf("expected warehouse type for مخزن الافوجادو, got %+v", warehouse)
	}
	// Warehouse is SI-only and valid — not in unmatched SO list.
	for _, u := range report.UnmatchedSellOut {
		if stringIndex(u, "افوجادو") >= 0 {
			t.Fatalf("warehouse must not be flagged as missing SI: %s", u)
		}
	}
}

func TestDryRun_UnmappedPlanCodeKeepsRawCode(t *testing.T) {
	report := BuildDryRunProposal("adeco", []RawOccurrence{
		{RawName: "FTH-031", PlanCode: "FTH-031", ChainSlug: "fathalla", Source: "plan_branch_code",
			SourceTable: "t.sell_in", SourceFile: "Plan_2026_Clean.xlsx", RowCount: 10, ValueEGP: 99},
		{RawName: "مجمع الإقليم (Regional)", PlanCode: "مجمع الإقليم (Regional)", ChainSlug: "fathalla", Source: "plan_branch_code",
			SourceTable: "t.sell_in", SourceFile: "Plan_2026_Clean.xlsx", RowCount: 5, ValueEGP: 1},
	})
	found := false
	for _, p := range report.UnmappedPlanCodes {
		if p.Code == "FTH-031" && p.Status == "unmapped_owner_to_name" {
			found = true
			if p.RowCount != 10 {
				t.Fatalf("plan code row must stay counted: %+v", p)
			}
		}
		// Unmapped codes must never invent a display name different from the raw code.
		if p.Status == "unmapped_owner_to_name" && p.Code == "" {
			t.Fatalf("unmapped plan code lost raw code: %+v", p)
		}
	}
	if !found {
		t.Fatalf("FTH-031 must stay listed under original raw code: %+v", report.UnmappedPlanCodes)
	}
	// Regional is parent-level, not a proposed branch and not an invented name.
	for _, r := range report.Rows {
		if stringIndex(r.DisplayName, "Regional") >= 0 || stringIndex(r.DisplayName, "إقليم") >= 0 {
			t.Fatalf("Regional leaked into proposed branches: %+v", r)
		}
	}
	if len(report.ParentLevelRows) < 1 {
		t.Fatalf("Regional should appear in parent_level_rows: %+v", report.ParentLevelRows)
	}
}

func stringsJoin(in []string) string {
	out := ""
	for _, s := range in {
		out += s + " "
	}
	return out
}
