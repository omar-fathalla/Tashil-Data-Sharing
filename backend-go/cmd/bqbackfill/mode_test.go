package main

import (
	"errors"
	"testing"
)

func TestResolveBackfillModeLegacyWhenNoScopedFlags(t *testing.T) {
	mode, err := resolveBackfillMode(false, false, false, "")
	if err != nil || mode != modeLegacy {
		t.Fatalf("got mode=%q err=%v want legacy", mode, err)
	}
}

func TestResolveBackfillModeScopedWithArchiveID(t *testing.T) {
	mode, err := resolveBackfillMode(true, false, false, "arch_sellin_x")
	if err != nil || mode != modeScoped {
		t.Fatalf("got mode=%q err=%v want scoped", mode, err)
	}
	mode, err = resolveBackfillMode(true, true, true, "arch_sellin_x")
	if err != nil || mode != modeScoped {
		t.Fatalf("with tenant/kind: mode=%q err=%v", mode, err)
	}
}

func TestResolveBackfillModeRefusesEmptyArchiveID(t *testing.T) {
	cases := []struct {
		name                        string
		archiveSet, tenantSet, kind bool
		archiveID                   string
	}{
		{"archive-id empty string", true, false, false, ""},
		{"archive-id whitespace", true, false, false, "  "},
		{"tenant set without archive", false, true, false, ""},
		{"kind set without archive", false, false, true, ""},
		{"tenant+kind sell_in without archive", false, true, true, ""},
		{"all scoped flags empty archive", true, true, true, ""},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			mode, err := resolveBackfillMode(tc.archiveSet, tc.tenantSet, tc.kind, tc.archiveID)
			if !errors.Is(err, ErrScopedArchiveIDRequired) {
				t.Fatalf("want ErrScopedArchiveIDRequired, got mode=%q err=%v", mode, err)
			}
			if mode != "" {
				t.Fatalf("mode should be empty on refuse, got %q", mode)
			}
		})
	}
}

func TestRunBackfillEntryMissingArchiveIDNeverCallsLegacy(t *testing.T) {
	legacyCalled := false
	scopedCalled := false
	err := runBackfillEntry(true, false, false, "",
		func(string) { scopedCalled = true },
		func() { legacyCalled = true },
	)
	if !errors.Is(err, ErrScopedArchiveIDRequired) {
		t.Fatalf("want ErrScopedArchiveIDRequired, got %v", err)
	}
	if legacyCalled {
		t.Fatal("legacy ReconcileArchivesToSink path must not run when archive id missing")
	}
	if scopedCalled {
		t.Fatal("scoped replay must not run without archive id")
	}

	err = runBackfillEntry(false, true, true, "",
		func(string) { scopedCalled = true },
		func() { legacyCalled = true },
	)
	if !errors.Is(err, ErrScopedArchiveIDRequired) {
		t.Fatalf("tenant/kind scoped without archive: got %v", err)
	}
	if legacyCalled || scopedCalled {
		t.Fatal("neither path may run when scoped flags lack archive id")
	}
}

func TestRunBackfillEntryScopedCallsReplayNotLegacy(t *testing.T) {
	legacyCalled := false
	var gotID string
	err := runBackfillEntry(true, true, true, "arch_sellin_adeco_fathalla_1794178032976473890",
		func(id string) { gotID = id },
		func() { legacyCalled = true },
	)
	if err != nil {
		t.Fatal(err)
	}
	if legacyCalled {
		t.Fatal("legacy must not run in scoped mode")
	}
	if gotID != "arch_sellin_adeco_fathalla_1794178032976473890" {
		t.Fatalf("scoped id=%q", gotID)
	}
}

func TestRunBackfillEntryLegacyWhenNoScopedFlags(t *testing.T) {
	legacyCalled := false
	err := runBackfillEntry(false, false, false, "",
		func(string) { t.Fatal("scoped must not run") },
		func() { legacyCalled = true },
	)
	if err != nil {
		t.Fatal(err)
	}
	if !legacyCalled {
		t.Fatal("legacy should run when no scoped flags")
	}
}
