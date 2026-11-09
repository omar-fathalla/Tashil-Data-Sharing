package main

import (
	"errors"
	"strings"
)

// ErrScopedArchiveIDRequired is returned when scoped sell-in replay is requested
// without a non-empty -archive-id. Callers must exit non-zero before any sink writes.
var ErrScopedArchiveIDRequired = errors.New(
	"archive id is required for sell-in month-cycle replay (refusing blind rewrite; pass -archive-id=<id>)",
)

// ErrLegacyOptInRequired is returned when neither scoped replay nor explicit legacy
// opt-in is selected. Unscoped -execute must never fall into all-tenant orphan cleanup.
var ErrLegacyOptInRequired = errors.New(
	"refusing unscoped bqbackfill (no all-tenant orphan cleanup by default); pass -archive-id=<id> for sell-in month-cycle replay, or -legacy-reconcile-all for the old full-archive reconcile",
)

// ErrLegacyScopedConflict is returned when -legacy-reconcile-all is combined with scoped flags.
var ErrLegacyScopedConflict = errors.New(
	"cannot combine -legacy-reconcile-all with scoped -archive-id/-tenant/-kind",
)

// backfillMode is either legacy full-archive reconcile or scoped sell-in archive replay.
type backfillMode string

const (
	modeLegacy backfillMode = "legacy"
	modeScoped backfillMode = "scoped"
)

// backfillCLIFlags is the parsed CLI surface shared by main() and tests.
type backfillCLIFlags struct {
	Execute            bool
	LegacyReconcileAll bool
	ArchiveID          string
	Tenant             string
	Kind               string
	ArchiveIDFlagSet   bool
	TenantFlagSet      bool
	KindFlagSet        bool
}

// resolveBackfillMode decides CLI mode from which flags were explicitly set.
//
//	scoped: -archive-id / -tenant / -kind present → require non-empty archive id
//	legacy: only with explicit -legacy-reconcile-all
//	else: refuse (covers bare -execute)
func resolveBackfillMode(f backfillCLIFlags) (backfillMode, error) {
	scoped := f.ArchiveIDFlagSet || f.TenantFlagSet || f.KindFlagSet
	if scoped && f.LegacyReconcileAll {
		return "", ErrLegacyScopedConflict
	}
	if scoped {
		if strings.TrimSpace(f.ArchiveID) == "" {
			return "", ErrScopedArchiveIDRequired
		}
		return modeScoped, nil
	}
	if f.LegacyReconcileAll {
		return modeLegacy, nil
	}
	return "", ErrLegacyOptInRequired
}

// runBackfillEntry is the single CLI dispatcher used by main() and tests.
// On error neither scoped nor legacy callbacks run.
func runBackfillEntry(
	f backfillCLIFlags,
	scoped func(archiveID, tenant, kind string, execute bool),
	legacy func(execute bool),
) error {
	mode, err := resolveBackfillMode(f)
	if err != nil {
		return err
	}
	switch mode {
	case modeScoped:
		scoped(strings.TrimSpace(f.ArchiveID), f.Tenant, f.Kind, f.Execute)
	case modeLegacy:
		legacy(f.Execute)
	default:
		return ErrLegacyOptInRequired
	}
	return nil
}
