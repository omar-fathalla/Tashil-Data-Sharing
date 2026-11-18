#!/usr/bin/env bash
# Yield smoke until CI test-flutter for this SHA is underway or done
# (avoids thrashing the shared Mac with Flutter + Playwright at once).
#
# Waits until CI test-flutter for the PR *head* SHA is in_progress, terminal
# success/failure/skipped, or absent after CI finished (path-filter skip).
#
# IMPORTANT: On pull_request, GITHUB_SHA is the virtual merge commit — CI runs
# are keyed to github.event.pull_request.head.sha. Pass HEAD_SHA from the
# workflow: ${{ github.event.pull_request.head.sha || github.sha }}
set -euo pipefail

REPO="${GITHUB_REPOSITORY:?}"
# Prefer explicit HEAD_SHA (PR head); fall back to GITHUB_SHA (push/merge_group).
SHA="${HEAD_SHA:-${GITHUB_SHA:?}}"
# Default 90m: Mac Flutter can wait behind deploy (30m) + run (35m).
# Job timeout is typically 45m — keep deadline ≤ job so we exit cleanly when possible.
DEADLINE_MIN="${WAIT_CI_FLUTTER_DEADLINE_MIN:-40}"
POLL_SEC="${WAIT_CI_FLUTTER_POLL_SEC:-30}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DIAG="${SCRIPT_DIR}/ci_mac_diag.sh"

if [ -z "${GH_TOKEN:-${GITHUB_TOKEN:-}}" ]; then
  echo "::error::GH_TOKEN/GITHUB_TOKEN required"
  exit 1
fi
export GH_TOKEN="${GH_TOKEN:-$GITHUB_TOKEN}"

echo "Waiting for CI tests / test-flutter on ${SHA} (deadline ${DEADLINE_MIN}m) before Mac smoke"
if [ -n "${GITHUB_SHA:-}" ] && [ "$SHA" != "$GITHUB_SHA" ]; then
  echo "Note: HEAD_SHA=${SHA:0:7} ≠ GITHUB_SHA=${GITHUB_SHA:0:7} (PR virtual merge) — polling head"
fi
deadline=$((SECONDS + DEADLINE_MIN * 60))
poll_n=0

while (( SECONDS < deadline )); do
  poll_n=$((poll_n + 1))
  # Heartbeat breadcrumbs: when the Mac runner drops mid-wait, logs often 404 —
  # flushed lines from earlier polls are the only evidence we keep.
  if [[ -f "$DIAG" ]]; then
    bash "$DIAG" heartbeat "wait-ci-flutter-poll-${poll_n}" 2>/dev/null || true
  else
    echo "wait-ci-flutter poll=${poll_n} epoch=$(date +%s) runner=${RUNNER_NAME:-local}"
  fi

  run_json="$(gh run list \
    --repo "$REPO" \
    --workflow ci.yml \
    --commit "$SHA" \
    --json databaseId,status,conclusion \
    --limit 20)"

  run_id="$(printf '%s' "$run_json" | jq -r '
    ([.[] | select(.status != "completed")] | .[0].databaseId)
    // (.[0].databaseId)
    // empty
  ')"

  if [ -z "$run_id" ]; then
    echo "No CI tests run for ${SHA:0:7} yet; sleeping ${POLL_SEC}s"
    sleep "$POLL_SEC"
    continue
  fi

  ci_status="$(printf '%s' "$run_json" | jq -r --argjson id "$run_id" \
    '.[] | select(.databaseId == $id) | .status' | head -1)"
  ci_conclusion="$(printf '%s' "$run_json" | jq -r --argjson id "$run_id" \
    '.[] | select(.databaseId == $id) | (.conclusion // "")' | head -1)"

  jobs_json="$(gh api "repos/${REPO}/actions/runs/${run_id}/jobs" --paginate)"
  # Matrix shards are named "test-flutter (N)"; exclude test-flutter-gate and the
  # required-check display name "Flutter analyze & test". Aggregate:
  # in_progress if any shard in_progress; completed only when all completed;
  # cancelled if any shard cancelled.
  flutter_agg="$(printf '%s' "$jobs_json" | jq -c '
    def is_flutter_shard:
      (.name | startswith("test-flutter"))
      and (.name | startswith("test-flutter-gate") | not)
      and (.name != "Flutter analyze & test");
    [.jobs[] | select(is_flutter_shard)] as $s
    | if ($s | length) == 0 then
        {status: "missing", conclusion: ""}
      elif ($s | any(.status == "in_progress")) then
        {status: "in_progress", conclusion: ""}
      elif ($s | any((.conclusion // "") == "cancelled")) then
        {status: "completed", conclusion: "cancelled"}
      elif ($s | all(.status == "completed")) then
        {
          status: "completed",
          conclusion: (
            if ($s | any((.conclusion // "") == "failure")) then "failure"
            elif ($s | all((.conclusion // "") == "skipped")) then "skipped"
            elif ($s | all((.conclusion // "") == "success")) then "success"
            else ($s[0].conclusion // "")
            end
          )
        }
      else
        {
          status: ($s | map(.status) | map(select(. != "completed")) | .[0] // "queued"),
          conclusion: ""
        }
      end
  ')"
  flutter_status="$(printf '%s' "$flutter_agg" | jq -r '.status')"
  flutter_conclusion="$(printf '%s' "$flutter_agg" | jq -r '.conclusion')"

  echo "CI run=${run_id} status=${ci_status} conclusion=${ci_conclusion:-none}; test-flutter status=${flutter_status} conclusion=${flutter_conclusion:-none}"

  if [ "$flutter_status" = "in_progress" ]; then
    echo "CI test-flutter in progress — safe to queue smoke on Mac runners"
    exit 0
  fi

  if [ "$flutter_status" = "completed" ]; then
    case "${flutter_conclusion}" in
      success|failure|skipped)
        echo "CI test-flutter completed (conclusion=${flutter_conclusion}) — proceeding"
        exit 0
        ;;
      cancelled)
        # Stay off Mac until a non-cancelled attempt exists for this head SHA.
        echo "CI test-flutter cancelled — waiting for Flutter re-run / in_progress"
        sleep "$POLL_SEC"
        continue
        ;;
      *)
        echo "CI test-flutter completed conclusion=${flutter_conclusion:-none}; sleeping ${POLL_SEC}s"
        sleep "$POLL_SEC"
        continue
        ;;
    esac
  fi

  # Path-filter skip: job never scheduled (missing) or explicitly skipped.
  if [ "$flutter_status" = "missing" ] && [ "$ci_status" = "completed" ]; then
    echo "CI finished without test-flutter job (path-skipped) — proceeding"
    exit 0
  fi
  if [ "$flutter_status" = "completed" ] && [ "$flutter_conclusion" = "skipped" ]; then
    echo "CI test-flutter skipped by path filter — proceeding"
    exit 0
  fi
  # Job still listed as skipped while run completes
  if [ "$flutter_conclusion" = "skipped" ]; then
    echo "CI test-flutter skipped — proceeding"
    exit 0
  fi

  # queued / waiting / pending / requested — wait before starting Mac smoke
  echo "CI test-flutter not ready (status=${flutter_status}); sleeping ${POLL_SEC}s"
  sleep "$POLL_SEC"
done

echo "::error::Timed out waiting for CI test-flutter on ${SHA} before smoke Mac job"
exit 1
