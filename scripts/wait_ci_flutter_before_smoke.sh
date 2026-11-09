#!/usr/bin/env bash
# Avoid GitHub concurrency pending-eviction on group tashil-mac-heavy.
#
# GitHub allows only one pending job per concurrency group; a newer pending job
# cancels the previous pending one (even with cancel-in-progress: false). When
# deploy holds the group, CI test-flutter and Playwright smoke-run both try to
# queue — smoke would cancel Flutter. This helper runs on ubuntu *before*
# smoke-run joins tashil-mac-heavy, waiting until CI Flutter for the same SHA is
# in_progress, terminal, or skipped/absent after CI finished.
set -euo pipefail

REPO="${GITHUB_REPOSITORY:?}"
SHA="${GITHUB_SHA:?}"
# Default 90m: Mac Flutter can wait behind deploy (30m) + run (35m).
DEADLINE_MIN="${WAIT_CI_FLUTTER_DEADLINE_MIN:-90}"
POLL_SEC="${WAIT_CI_FLUTTER_POLL_SEC:-30}"

if [ -z "${GH_TOKEN:-${GITHUB_TOKEN:-}}" ]; then
  echo "::error::GH_TOKEN/GITHUB_TOKEN required"
  exit 1
fi
export GH_TOKEN="${GH_TOKEN:-$GITHUB_TOKEN}"

echo "Waiting for CI tests / test-flutter on ${SHA} (deadline ${DEADLINE_MIN}m) before joining tashil-mac-heavy"
deadline=$((SECONDS + DEADLINE_MIN * 60))

while (( SECONDS < deadline )); do
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
  flutter_status="$(printf '%s' "$jobs_json" | jq -r \
    '[.jobs[] | select(.name == "test-flutter")] | if length == 0 then "missing" else .[0].status end')"
  flutter_conclusion="$(printf '%s' "$jobs_json" | jq -r \
    '[.jobs[] | select(.name == "test-flutter")] | if length == 0 then "" else (.[0].conclusion // "") end')"

  echo "CI run=${run_id} status=${ci_status} conclusion=${ci_conclusion:-none}; test-flutter status=${flutter_status} conclusion=${flutter_conclusion:-none}"

  if [ "$flutter_status" = "in_progress" ]; then
    echo "CI test-flutter in progress — safe to queue smoke as the single tashil-mac-heavy pending"
    exit 0
  fi

  if [ "$flutter_status" = "completed" ]; then
    if [ "$flutter_conclusion" = "cancelled" ]; then
      # Eviction already happened; do not block smoke forever. CI Flutter gate stays red.
      echo "CI test-flutter already cancelled; proceeding with smoke (re-run CI for Flutter green)"
      exit 0
    fi
    echo "CI test-flutter completed (conclusion=${flutter_conclusion:-none}) — proceeding"
    exit 0
  fi

  if [ "$flutter_status" = "missing" ] && [ "$ci_status" = "completed" ]; then
    echo "CI finished without test-flutter job (path-skipped) — proceeding"
    exit 0
  fi

  # queued / waiting / pending / requested — do not join tashil-mac-heavy yet
  echo "CI test-flutter not ready (status=${flutter_status}); sleeping ${POLL_SEC}s"
  sleep "$POLL_SEC"
done

echo "::error::Timed out waiting for CI test-flutter on ${SHA} before smoke Mac job"
exit 1
