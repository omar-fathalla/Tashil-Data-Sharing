package main

import (
	"errors"
	"testing"
)

func TestResolveBackfillModeRefusesUnscopedByDefault(t *testing.T) {
	// Bare invocation and bare -execute (Execute=true, no opt-in) must refuse.
	for _, name := range []string{"no flags", "execute alone"} {
		f := backfillCLIFlags{}
		if name == "execute alone" {
			f.Execute = true
		}
		mode, err := resolveBackfillMode(f)
		if !errors.Is(err, ErrLegacyOptInRequired) {
			t.Fatalf("%s: want ErrLegacyOptInRequired, got mode=%q err=%v", name, mode, err)
		}
	}
}

func TestResolveBackfillModeScopedWithArchiveID(t *testing.T) {
	mode, err := resolveBackfillMode(backfillCLIFlags{
		ArchiveIDFlagSet: true, ArchiveID: "arch_sellin_x",
	})
	if err != nil || mode != modeScoped {
		t.Fatalf("got mode=%q err=%v want scoped", mode, err)
	}
	mode, err = resolveBackfillMode(backfillCLIFlags{
		ArchiveIDFlagSet: true, TenantFlagSet: true, KindFlagSet: true,
		ArchiveID: "arch_sellin_x", Tenant: "tenant-adeco", Kind: "sell_in", Execute: true,
	})
	if err != nil || mode != modeScoped {
		t.Fatalf("with tenant/kind: mode=%q err=%v", mode, err)
	}
}

func TestResolveBackfillModeRefusesEmptyArchiveID(t *testing.T) {
	cases := []backfillCLIFlags{
		{ArchiveIDFlagSet: true, ArchiveID: ""},
		{ArchiveIDFlagSet: true, ArchiveID: "  "},
		{TenantFlagSet: true, Tenant: "tenant-adeco"},
		{KindFlagSet: true, Kind: "sell_in"},
		{TenantFlagSet: true, KindFlagSet: true, Tenant: "tenant-adeco", Kind: "sell_in"},
		{ArchiveIDFlagSet: true, TenantFlagSet: true, KindFlagSet: true, ArchiveID: "", Execute: true},
	}
	for i, f := range cases {
		mode, err := resolveBackfillMode(f)
		if !errors.Is(err, ErrScopedArchiveIDRequired) {
			t.Fatalf("case %d: want ErrScopedArchiveIDRequired, got mode=%q err=%v", i, mode, err)
		}
	}
}

func TestResolveBackfillModeLegacyOptIn(t *testing.T) {
	mode, err := resolveBackfillMode(backfillCLIFlags{LegacyReconcileAll: true})
	if err != nil || mode != modeLegacy {
		t.Fatalf("got mode=%q err=%v want legacy", mode, err)
	}
	mode, err = resolveBackfillMode(backfillCLIFlags{LegacyReconcileAll: true, Execute: true})
	if err != nil || mode != modeLegacy {
		t.Fatalf("legacy+execute: mode=%q err=%v", mode, err)
	}
}

func TestResolveBackfillModeLegacyScopedConflict(t *testing.T) {
	_, err := resolveBackfillMode(backfillCLIFlags{
		LegacyReconcileAll: true, ArchiveIDFlagSet: true, ArchiveID: "arch_x",
	})
	if !errors.Is(err, ErrLegacyScopedConflict) {
		t.Fatalf("want conflict, got %v", err)
	}
}

func TestRunBackfillEntryExecuteAloneNeverCallsLegacy(t *testing.T) {
	legacyCalled, scopedCalled := false, false
	err := runBackfillEntry(backfillCLIFlags{Execute: true},
		func(string, string, string, bool) { scopedCalled = true },
		func(bool) { legacyCalled = true },
	)
	if !errors.Is(err, ErrLegacyOptInRequired) {
		t.Fatalf("want ErrLegacyOptInRequired, got %v", err)
	}
	if legacyCalled || scopedCalled {
		t.Fatal("unscoped -execute must not call scoped or legacy paths")
	}
}

func TestRunBackfillEntryEmptyArchiveIDNeverCallsLegacy(t *testing.T) {
	legacyCalled, scopedCalled := false, false
	err := runBackfillEntry(backfillCLIFlags{ArchiveIDFlagSet: true, ArchiveID: "", Execute: true},
		func(string, string, string, bool) { scopedCalled = true },
		func(bool) { legacyCalled = true },
	)
	if !errors.Is(err, ErrScopedArchiveIDRequired) {
		t.Fatalf("want ErrScopedArchiveIDRequired, got %v", err)
	}
	if legacyCalled || scopedCalled {
		t.Fatal("empty -archive-id must not call any path")
	}
}

func TestRunBackfillEntryTenantKindWithoutIDNeverCallsLegacy(t *testing.T) {
	legacyCalled, scopedCalled := false, false
	err := runBackfillEntry(backfillCLIFlags{
		TenantFlagSet: true, KindFlagSet: true,
		Tenant: "tenant-adeco", Kind: "sell_in", Execute: true,
	},
		func(string, string, string, bool) { scopedCalled = true },
		func(bool) { legacyCalled = true },
	)
	if !errors.Is(err, ErrScopedArchiveIDRequired) {
		t.Fatalf("want ErrScopedArchiveIDRequired, got %v", err)
	}
	if legacyCalled || scopedCalled {
		t.Fatal("-tenant/-kind without archive id must not call any path")
	}
}

func TestRunBackfillEntryScopedCallsReplayNotLegacy(t *testing.T) {
	legacyCalled := false
	var gotID, gotTenant, gotKind string
	var gotExec bool
	err := runBackfillEntry(backfillCLIFlags{
		ArchiveIDFlagSet: true, TenantFlagSet: true, KindFlagSet: true,
		ArchiveID: "arch_sellin_adeco_fathalla_1794178032976473890",
		Tenant:    "tenant-adeco", Kind: "sell_in", Execute: true,
	},
		func(id, tenant, kind string, execute bool) {
			gotID, gotTenant, gotKind, gotExec = id, tenant, kind, execute
		},
		func(bool) { legacyCalled = true },
	)
	if err != nil {
		t.Fatal(err)
	}
	if legacyCalled {
		t.Fatal("legacy must not run in scoped mode")
	}
	if gotID != "arch_sellin_adeco_fathalla_1794178032976473890" || gotTenant != "tenant-adeco" || gotKind != "sell_in" || !gotExec {
		t.Fatalf("scoped args id=%q tenant=%q kind=%q exec=%v", gotID, gotTenant, gotKind, gotExec)
	}
}

func TestRunBackfillEntryExplicitLegacyFlagWorks(t *testing.T) {
	legacyCalled, scopedCalled := false, false
	var gotExec bool
	err := runBackfillEntry(backfillCLIFlags{LegacyReconcileAll: true, Execute: true},
		func(string, string, string, bool) { scopedCalled = true },
		func(execute bool) { legacyCalled = true; gotExec = execute },
	)
	if err != nil {
		t.Fatal(err)
	}
	if scopedCalled || !legacyCalled || !gotExec {
		t.Fatalf("legacy opt-in: scoped=%v legacy=%v exec=%v", scopedCalled, legacyCalled, gotExec)
	}
}

func TestMainDispatchesViaRunBackfillEntry(t *testing.T) {
	// Guarantees main()'s dispatcher contract: same entry as these tests.
	// Simulate main after parseBackfillFlags by calling runBackfillEntry with the
	// same callbacks shape main uses (mainScopedReplay / mainLegacyReconcile stubs).
	called := ""
	err := runBackfillEntry(backfillCLIFlags{Execute: true},
		func(string, string, string, bool) { called = "scoped" },
		func(bool) { called = "legacy" },
	)
	if !errors.Is(err, ErrLegacyOptInRequired) || called != "" {
		t.Fatalf("main-equivalent -execute alone: err=%v called=%q", err, called)
	}

	err = runBackfillEntry(backfillCLIFlags{LegacyReconcileAll: true},
		func(string, string, string, bool) { called = "scoped" },
		func(bool) { called = "legacy" },
	)
	if err != nil || called != "legacy" {
		t.Fatalf("main-equivalent legacy opt-in: err=%v called=%q", err, called)
	}
}
