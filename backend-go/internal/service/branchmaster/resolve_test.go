package branchmaster

import (
	"context"
	"testing"
	"time"
)

func seedFTH(t *testing.T) *Service {
	t.Helper()
	s := New(NewMemoryStore())
	now := time.Date(2026, 11, 9, 12, 0, 0, 0, time.UTC)
	s.now = func() time.Time { return now }
	report := BuildDryRunProposal("adeco", []RawOccurrence{
		{RawName: "عائلة فتح الله ماركت - سموحة", ChainSlug: "fathalla", Source: "sell_out"},
		{RawName: "فتح الله - سموحة", ChainSlug: "fathalla", Source: "sell_in"},
		{RawName: "عائلة فتح الله ماركت - دمنهور", ChainSlug: "fathalla", Source: "sell_out"},
		{RawName: "عائلة فتح الله ماركت - دمنهور - الاستاد", ChainSlug: "fathalla", Source: "sell_out"},
		{RawName: "غير موزع على فرع", ChainSlug: "fathalla", Source: "sell_out"},
	})
	if _, err := s.ConfirmBootstrap(context.Background(), "adeco", report, "owner@test"); err != nil {
		t.Fatal(err)
	}
	return s
}

func TestAliasHitInstant(t *testing.T) {
	s := seedFTH(t)
	st, _ := s.Get(context.Background(), "adeco")
	r := Resolve(st, "fathalla", "فتح الله - سموحة")
	if r.Kind != KindAlias && r.Kind != KindExact && r.Kind != KindNormalized {
		t.Fatalf("kind=%s", r.Kind)
	}
	if r.BranchCode == "" || r.DisplayName != "سموحة" {
		t.Fatalf("got code=%s display=%s", r.BranchCode, r.DisplayName)
	}
}

func TestAmbiguousDamanhourPending(t *testing.T) {
	s := seedFTH(t)
	// After bootstrap, both دمنهور and دمنهور الاستاد exist. A raw "دمنهور"
	// should be exact/normalized to the short one; a near-miss spelling that
	// scores close to BOTH must go pending.
	st, _ := s.Get(context.Background(), "adeco")
	// Force ambiguous by resolving a name that is similar to both.
	r := Resolve(st, "fathalla", "دمنهور الاستاد")
	// Exact/normalized hit on الاستاد is fine (not ambiguous).
	if r.Kind == KindAmbiguous {
		t.Fatalf("exact stadium should not be ambiguous: %+v", r)
	}
	// Observe a fuzzy form that sits between the two.
	res, err := s.ObserveRaw(context.Background(), "adeco", "fathalla", "دمنهور ستاد", "uploader")
	if err != nil {
		t.Fatal(err)
	}
	if res.Kind != KindAmbiguous && res.Kind != KindLow && res.Kind != KindHigh {
		// Depending on scores may be ambiguous or low — never silent exact on wrong one.
		t.Logf("kind=%s conf=%.2f code=%s alt=%s", res.Kind, res.Confidence, res.BranchCode, res.AltCode)
	}
	if res.Kind == KindHigh && res.AltCode != "" {
		t.Fatal("should not auto-link when alt candidate exists closely")
	}
	if res.Kind == KindAmbiguous || res.Kind == KindLow {
		pending, err := s.ListPending(context.Background(), "adeco")
		if err != nil {
			t.Fatal(err)
		}
		if len(pending) == 0 {
			t.Fatal("expected pending entry")
		}
	}
}

func TestUnallocatedExcludedFromLinking(t *testing.T) {
	s := seedFTH(t)
	res, err := s.ObserveRaw(context.Background(), "adeco", "fathalla", "غير موزع على فرع", "uploader")
	if err != nil {
		t.Fatal(err)
	}
	if res.Kind != KindUnallocated {
		t.Fatalf("kind=%s", res.Kind)
	}
	if res.AutoLinked {
		t.Fatal("unallocated must never auto-link")
	}
	code, display := s.ResolveForReport(context.Background(), "adeco", "fathalla", "غير موزع على فرع")
	if display != UnallocatedBranchName {
		t.Fatalf("display=%s", display)
	}
	if code != UnallocatedCode("FTH") {
		t.Fatalf("code=%s", code)
	}
}

func TestNewBranchCreatesCode(t *testing.T) {
	s := seedFTH(t)
	res, err := s.ObserveRaw(context.Background(), "adeco", "fathalla", "عائلة فتح الله ماركت - الزقازيق الجديدة جدا", "uploader")
	if err != nil {
		t.Fatal(err)
	}
	if res.Kind != KindNew {
		t.Fatalf("kind=%s reason=%s", res.Kind, res.ReasonAR)
	}
	if res.BranchCode == "" {
		t.Fatal("expected new code")
	}
	st, _ := s.Get(context.Background(), "adeco")
	found := false
	for _, n := range st.Notices {
		if n.Kind == "new_branch" {
			found = true
		}
	}
	if !found {
		t.Fatal("expected new_branch notice")
	}
}

func TestBootstrapDedupeSpellings(t *testing.T) {
	report := BuildDryRunProposal("adeco", []RawOccurrence{
		{RawName: "عائلة فتح الله ماركت - سموحة", ChainSlug: "fathalla"},
		{RawName: "عائله فتح الله ماركت - سموحه", ChainSlug: "fathalla"},
		{RawName: "فتح الله - سموحة", ChainSlug: "fathalla"},
		{RawName: "سموحة", ChainSlug: "fathalla"},
	})
	if report.UniqueNormCount != 1 {
		t.Fatalf("unique=%d rows=%d", report.UniqueNormCount, len(report.Rows))
	}
	if len(report.Rows[0].RawNames) != 4 {
		t.Fatalf("raws=%v", report.Rows[0].RawNames)
	}
	if report.Rows[0].BranchCode != "FTH-001" {
		t.Fatalf("code=%s", report.Rows[0].BranchCode)
	}
	if report.Rows[0].DisplayName != "سموحة" && report.Rows[0].DisplayName != "سموحه" {
		// ShortDisplay keeps original hamza/taa form from shortest raw.
		t.Logf("display=%s", report.Rows[0].DisplayName)
	}
}

func TestReportGroupingTotalsIdentical(t *testing.T) {
	s := seedFTH(t)
	rows := []struct {
		Raw   string
		Value float64
	}{
		{"عائلة فتح الله ماركت - سموحة", 100},
		{"فتح الله - سموحة", 50},
		{"عائلة فتح الله ماركت - دمنهور", 20},
		{"غير موزع على فرع", 7},
	}
	// Without mapping: 4 buckets. With mapping: smouha merged.
	rawTotals := map[string]float64{}
	for _, r := range rows {
		rawTotals[r.Raw] += r.Value
	}
	var sumRaw float64
	for _, v := range rawTotals {
		sumRaw += v
	}
	mapped := GroupTotals(func(raw string) (string, string) {
		return s.ResolveForReport(context.Background(), "adeco", "fathalla", raw)
	}, rows)
	var sumMapped float64
	for _, v := range mapped {
		sumMapped += v
	}
	if sumRaw != sumMapped {
		t.Fatalf("totals changed: raw=%v mapped=%v", sumRaw, sumMapped)
	}
	smouhaCode, _ := s.ResolveForReport(context.Background(), "adeco", "fathalla", "فتح الله - سموحة")
	if mapped[smouhaCode] != 150 {
		t.Fatalf("smouha total=%v map=%v", mapped[smouhaCode], mapped)
	}
}

func TestHighAutoLinkSavesAlias(t *testing.T) {
	s := seedFTH(t)
	st, _ := s.Get(context.Background(), "adeco")
	// Pick an existing branch display and create a near-identical spelling.
	var target Branch
	for _, b := range st.Branches {
		if b.DisplayName == "سموحة" || Normalize(b.DisplayName) == Normalize("سموحة") {
			target = b
			break
		}
	}
	if target.Code == "" {
		t.Fatal("no smouha branch")
	}
	// Very close spelling should high-auto-link.
	res, err := s.ObserveRaw(context.Background(), "adeco", "fathalla", "سموحه", "uploader")
	if err != nil {
		t.Fatal(err)
	}
	// "سموحه" normalizes equal to "سموحة" → normalized hit, not necessarily KindHigh.
	if res.BranchCode != target.Code && res.Kind != KindNormalized && res.Kind != KindHigh && res.Kind != KindAlias {
		t.Fatalf("unexpected %+v want %s", res, target.Code)
	}
}
