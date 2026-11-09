#!/usr/bin/env bash
# Plan-only helper for re-ingesting Adeco GP/Dynamics Sell-In after the month-cycle
# period_month fix lands. Does NOT write to production.
#
# Why a plain archive reconcile is not enough:
#   ReconcileArchivesToSink only re-parses archives that have zero BigQuery rows under
#   their archive id. Existing sell_in_records already have Document-Date-based
#   period_month values, so they would be skipped and stay wrong.
#   Unscoped `bqbackfill -execute` is refused by default; full-archive orphan cleanup
#   requires explicit `-legacy-reconcile-all` (not used for month-cycle redistributes):
#        go run ./cmd/bqbackfill -legacy-reconcile-all            # dry-run report
#        go run ./cmd/bqbackfill -legacy-reconcile-all -execute   # writes + orphans
#   Dry-run scoped replay does not attach an aggregates writer / scheduleRecompute.
#   -execute materializes agg_* synchronously (process waits; no in-flight exit).
#
# Why archive-scoped force replay is safe:
#   PlanSellIn / WriteSellIn replace by archive_id + batch_id + legacy source_file
#   (not by chain/month). Re-parsing in26 only rewrites that archive's rows; other
#   tenant files (e.g. Adco_Fathalla_Sell_In_Plan_2026_Clean.xlsx) stay untouched.
#   No orphan cleanup runs in this mode.
#
# Recommended operator steps (after this PR is reviewed — do not run from CI agents):
#   Backup already exists: tashil_analytics.sell_in_records_backup_20261109_in26
#   1. Dry-run (prints per-month BEFORE/AFTER rows + net; refuses without -archive-id):
#        TASHIL_ARCHIVE_DIR=... PROJECT_ID=... BIGQUERY_DATASET=... USE_MOCK_SERVICES=true \
#          go run ./cmd/bqbackfill \
#          -archive-id=arch_sellin_adeco_fathalla_1794178032976473890 \
#          -tenant=tenant-adeco -kind=sell_in
#   2. Execute the same command with -execute (replaces only that archive's rows and
#      refreshes agg_sell_through via GetAnalyticsAggregates).
#   3. Spot-check per-month totals against
#      backend-go/internal/service/gemini/testdata/month_cycle_expected.csv
#      (TOTAL 40927 rows / net TO 133191402.85).
#
# Sell-Out alignment (proposal only — NOT implemented in this PR):
#   Sell-through compares Sell-In period_month to Sell-Out calendar months. If Sell-Out
#   stays on Document/calendar month while Sell-In uses the company cycle, mid-cycle
#   boundary weeks will misalign. Decide whether Sell-Out should adopt the same cycle
#   before relying on agg_sell_through rates for Adeco.
#
# This script only prints the plan and lists local archive sell-in files when
# TASHIL_ARCHIVE_DIR is set. It refuses -execute / prod credentials.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

ARCHIVE_ID="${SELLIN_REPLAY_ARCHIVE_ID:-arch_sellin_adeco_fathalla_1794178032976473890}"

echo "=== Sell-In month-cycle backfill PLAN (no writes) ==="
echo "Repo: $ROOT"
echo
echo "Rule: period_month from file 'month' column (company cycle), not Document Date."
echo "Expected reference: backend-go/internal/service/gemini/testdata/month_cycle_expected.csv"
echo "  TOTAL rows 40927 / net TO 133191402.85"
echo "Scoped archive: $ARCHIVE_ID (tenant-adeco / sell_in only)"
echo

if [[ "${1:-}" == "-execute" || "${SELLIN_MONTH_CYCLE_EXECUTE:-}" == "1" ]]; then
  echo "REFUSED: this script never executes a prod backfill." >&2
  echo "Follow the operator steps in the header comments after review." >&2
  exit 2
fi

if [[ -n "${TASHIL_ARCHIVE_DIR:-}" && -d "${TASHIL_ARCHIVE_DIR}" ]]; then
  echo "Sell-In archives under TASHIL_ARCHIVE_DIR=${TASHIL_ARCHIVE_DIR}:"
  find "$TASHIL_ARCHIVE_DIR" -type f \( -iname '*sell*in*' -o -iname 'in2*.xlsx' -o -iname '*sop*' \) 2>/dev/null | head -50 || true
  echo
  echo "Dry-run scoped replay (no BigQuery writes):"
  echo "  (cd backend-go && USE_MOCK_SERVICES=true TASHIL_ARCHIVE_DIR=\"$TASHIL_ARCHIVE_DIR\" \\"
  echo "     PROJECT_ID=\"\${PROJECT_ID:-tashil-data-sharing}\" BIGQUERY_DATASET=\"\${BIGQUERY_DATASET:-tashil_analytics}\" \\"
  echo "     go run ./cmd/bqbackfill -archive-id=$ARCHIVE_ID -tenant=tenant-adeco -kind=sell_in)"
else
  echo "TASHIL_ARCHIVE_DIR unset — skipping local archive listing."
  echo "Dry-run command shape:"
  echo "  (cd backend-go && USE_MOCK_SERVICES=true TASHIL_ARCHIVE_DIR=... \\"
  echo "     go run ./cmd/bqbackfill -archive-id=$ARCHIVE_ID -tenant=tenant-adeco -kind=sell_in)"
fi

echo
echo "Open questions before running for real:"
echo "  - Confirm Sell-Out should (or should not) share the company month cycle for sell-through."
echo "  - Confirm which tenants/chains hold GP SOP exports with a month column."
echo "Done (plan only)."
