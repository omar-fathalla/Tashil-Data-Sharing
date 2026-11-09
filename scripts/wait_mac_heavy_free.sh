#!/usr/bin/env bash
# Serialize joining concurrency group tashil-mac-heavy.
#
# GitHub keeps only ONE pending job per concurrency group even when
# cancel-in-progress: false (that flag only protects the *running* job).
# A second pending job cancels the first (pending-slot eviction).
#
# Run on GitHub-hosted ubuntu *before* a Mac job sets
# concurrency.group: tashil-mac-heavy.
set -euo pipefail

REPO="${GITHUB_REPOSITORY:?}"
DEADLINE_MIN="${WAIT_MAC_HEAVY_DEADLINE_MIN:-120}"
POLL_SEC="${WAIT_MAC_HEAVY_POLL_SEC:-30}"
SELF_RUN_ID="${GITHUB_RUN_ID:-}"

if [ -z "${GH_TOKEN:-${GITHUB_TOKEN:-}}" ]; then
  echo "::error::GH_TOKEN/GITHUB_TOKEN required"
  exit 1
fi
export GH_TOKEN="${GH_TOKEN:-$GITHUB_TOKEN}"

echo "Waiting until tashil-mac-heavy holders are idle (deadline ${DEADLINE_MIN}m)"
deadline=$((SECONDS + DEADLINE_MIN * 60))

while (( SECONDS < deadline )); do
  # Merge in_progress + queued workflow runs (pending concurrency often shows queued).
  inprog="$(gh run list --repo "$REPO" --status in_progress --limit 30 \
    --json databaseId,name,headBranch,status)"
  queued="$(gh run list --repo "$REPO" --status queued --limit 20 \
    --json databaseId,name,headBranch,status 2>/dev/null || echo '[]')"
  runs_json="$(jq -s 'add | unique_by(.databaseId)' <(printf '%s' "$inprog") <(printf '%s' "$queued"))"

  busy_lines=""
  while read -r rid; do
    [ -z "$rid" ] && continue
    if [ -n "$SELF_RUN_ID" ] && [ "$rid" = "$SELF_RUN_ID" ]; then
      continue
    fi
    jobs="$(gh api "repos/${REPO}/actions/runs/${rid}/jobs" --jq \
      '[.jobs[] | select(
          (.name == "test-flutter" or .name == "smoke-run"
           or .name == "deploy-backend" or .name == "deploy-web")
          and (.status == "in_progress" or .status == "queued"
               or .status == "waiting" or .status == "pending"
               or .status == "requested")
        ) | "\(.name):\(.status)"] | .[]' 2>/dev/null || true)"
    if [ -n "$jobs" ]; then
      branch="$(printf '%s' "$runs_json" | jq -r --argjson id "$rid" \
        '.[] | select(.databaseId == $id) | .headBranch // "?"')"
      busy_lines="${busy_lines} run=${rid} branch=${branch} ${jobs}"$'\n'
    fi
  done < <(printf '%s' "$runs_json" | jq -r '.[].databaseId')

  if [ -z "$busy_lines" ]; then
    echo "Mac heavies idle — safe to join tashil-mac-heavy"
    exit 0
  fi

  echo "Mac busy (do not join concurrency group yet):"
  printf '%s' "$busy_lines"
  echo "sleeping ${POLL_SEC}s"
  sleep "$POLL_SEC"
done

echo "::error::Timed out waiting for Mac heavies to free before joining tashil-mac-heavy"
exit 1
