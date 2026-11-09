package main

import (
	"errors"
	"strings"
)

// ErrScopedArchiveIDRequired is returned when scoped sell-in replay is requested
// without a non-empty -archive-id. Callers must exit non-zero before legacy reconcile.
var ErrScopedArchiveIDRequired = errors.New(
	"archive id is required for sell-in month-cycle replay (refusing blind rewrite; pass -archive-id=<id>)",
)

// backfillMode is either legacy full-archive reconcile or scoped sell-in archive replay.
type backfillMode string

const (
	modeLegacy backfillMode = "legacy"
	modeScoped backfillMode = "scoped"
)

// resolveBackfillMode decides CLI mode from which flags were explicitly set.
//
// Scoped mode is entered when -archive-id is present on the command line, or when
// -tenant / -kind are set (scoped sell_in intent). Scoped mode without a non-empty
// archive id returns ErrScopedArchiveIDRequired — never fall through to legacy reconcile.
func resolveBackfillMode(archiveIDFlagSet, tenantFlagSet, kindFlagSet bool, archiveID string) (backfillMode, error) {
	scoped := archiveIDFlagSet || tenantFlagSet || kindFlagSet
	if !scoped {
		return modeLegacy, nil
	}
	if strings.TrimSpace(archiveID) == "" {
		return "", ErrScopedArchiveIDRequired
	}
	return modeScoped, nil
}
