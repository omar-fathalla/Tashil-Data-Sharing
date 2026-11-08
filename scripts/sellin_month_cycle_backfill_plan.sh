#!/usr/bin/env bash
# Plan-only helper for re-ingesting Adeco GP/Dynamics Sell-In after the month-cycle
# period_month fix lands. Does NOT write to production.
#
# Why a plain archive reconcile is not enough:
#   ReconcileArchivesToSink only re-parses archives that have zero BigQuery rows under
#   their archive id. Existing sell_in_records already have Document-Date-based
#   period_month values, so they would be skipped and stay wrong.
#
# Why a blind re-upload is unsafe:
#   SetSellInRecords / PlanSellIn replace by (chain_key, period_month). After the fix,
#   rows move to different period_month buckets; old wrong-month buckets would orphan
#   unless deleted first.
#
# Recommended operator steps (after this PR is deployed — do not run from CI agents):
#   1. Snapshot / export current sell_in_records + agg_sell_through for tenant-adeco.
#   2. Dry-run list of Sell-In archives:
#        TASHIL_ARCHIVE_DIR=... USE_MOCK_SERVICES=true go run ./cmd/bqbackfill
#   3. Delete existing sink rows for those Sell-In archive ids (or the whole tenant
#      sell_in_records partition set) so reconcile will rewrite.
#   4. Re-parse + write with the new parser:
#        TASHIL_ARCHIVE_DIR=... PROJECT_ID=... BIGQUERY_DATASET=... \
#          USE_MOCK_SERVICES=true go run ./cmd/bqbackfill -execute
#   5. Rebuild analytics aggregates (agg_sell_through and monthly Sell-In trend) for
#      the tenant — same path the server uses after SetSellInRecords / precompute.
#   6. Spot-check Feb/Aug boundary months against month_cycle_expected.csv totals.
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

echo "=== Sell-In month-cycle backfill PLAN (no writes) ==="
echo "Repo: $ROOT"
echo
echo "Rule: period_month from file 'month' column (company cycle), not Document Date."
echo "Expected reference: backend-go/internal/service/gemini/testdata/month_cycle_expected.csv"
echo "  TOTAL rows 40927 / net TO 133191402.85"
echo

if [[ "${1:-}" == "-execute" || "${SELLIN_MONTH_CYCLE_EXECUTE:-}" == "1" ]]; then
  echo "REFUSED: this script never executes a prod backfill." >&2
  echo "Follow the operator steps in the header comments after deploy." >&2
  exit 2
fi

if [[ -n "${TASHIL_ARCHIVE_DIR:-}" && -d "${TASHIL_ARCHIVE_DIR}" ]]; then
  echo "Sell-In archives under TASHIL_ARCHIVE_DIR=${TASHIL_ARCHIVE_DIR}:"
  find "$TASHIL_ARCHIVE_DIR" -type f \( -iname '*sell*in*' -o -iname 'in2*.xlsx' -o -iname '*sop*' \) 2>/dev/null | head -50 || true
  echo
  echo "Dry-run bqbackfill list (no BigQuery writes):"
  echo "  (cd backend-go && USE_MOCK_SERVICES=true TASHIL_ARCHIVE_DIR=\"$TASHIL_ARCHIVE_DIR\" go run ./cmd/bqbackfill)"
else
  echo "TASHIL_ARCHIVE_DIR unset — skipping local archive listing."
fi

echo
echo "Open questions before running for real:"
echo "  - Confirm Sell-Out should (or should not) share the company month cycle for sell-through."
echo "  - Confirm which tenants/chains hold GP SOP exports with a month column."
echo "Done (plan only)."
