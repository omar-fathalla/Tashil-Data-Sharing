#!/usr/bin/env bash
# Safe CI wrapper around ~/mac-resources/mac-lock.sh on fathalla-mac.
#
# NEVER exec the live file in place: another agent may rewrite
# ~/mac-resources/mac-lock.sh while we wait, and bash then reads a shifted
# offset (seen as a bogus "syntax error" after "acquired"). Always copy to
# $RUNNER_TEMP (or TMPDIR) first and run the copy.
#
# Does NOT modify shared ~/mac-resources — only reads/copies the script and
# calls acquire/release/status against LOCK.d via that copy.
#
# On ubuntu-latest / missing script: skip gracefully (exit 0).
set -euo pipefail

SRC="${MAC_LOCK_SRC:-${HOME}/mac-resources/mac-lock.sh}"
cmd="${1:-}"
shift || true

if [[ ! -f "$SRC" ]]; then
  echo "mac-lock.sh not found at ${SRC} — skipping (ubuntu/github-hosted fallback or unset Mac)"
  exit 0
fi

tmp_root="${RUNNER_TEMP:-${TMPDIR:-/tmp}}"
COPY="${MAC_LOCK_COPY:-${tmp_root}/mac-lock-ci-copy.sh}"

# Refresh the private copy unless the caller pinned MAC_LOCK_COPY to an existing file.
if [[ -z "${MAC_LOCK_COPY:-}" || ! -f "$COPY" ]]; then
  cp "$SRC" "$COPY"
fi

case "$cmd" in
  acquire)
    # Usage: acquire "<agent>" "<repo>" "<task>" <eta_min> [wait_max_min]
    bash "$COPY" acquire "$@"
    ;;
  release)
    # Ownership-based: release only if status output contains our agent name.
    # Do not trust a prior GITHUB_OUTPUT "acquired" flag — acquire can exit
    # non-zero after mkdir succeeded (e.g. live script rewritten mid-wait).
    agent="${1:-}"
    if [[ -z "$agent" ]]; then
      echo "usage: $0 release \"<agent>\"" >&2
      exit 2
    fi
    status="$(bash "$COPY" status 2>/dev/null || true)"
    if printf '%s\n' "$status" | grep -Fq -- "$agent"; then
      bash "$COPY" release "$agent"
    else
      echo "lock not held by this agent (${agent}); status=${status:-free} — skip release"
    fi
    ;;
  status)
    bash "$COPY" status "$@"
    ;;
  *)
    echo "usage: $0 acquire|release|status ..." >&2
    exit 2
    ;;
esac
