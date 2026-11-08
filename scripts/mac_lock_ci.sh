#!/usr/bin/env bash
# Thin CI wrapper around ~/mac-resources/mac-lock.sh on fathalla-mac.
# Does NOT modify shared ~/mac-resources — only invokes the installed script.
# On ubuntu-latest / missing script: skip gracefully (exit 0).
set -euo pipefail

LOCK="${HOME}/mac-resources/mac-lock.sh"
cmd="${1:-}"
shift || true

if [[ ! -f "$LOCK" ]]; then
  echo "mac-lock.sh not found at ${LOCK} — skipping (ubuntu/github-hosted fallback or unset Mac)"
  exit 0
fi

case "$cmd" in
  acquire|release|status)
    exec bash "$LOCK" "$cmd" "$@"
    ;;
  *)
    echo "usage: $0 acquire|release|status ..." >&2
    exit 2
    ;;
esac
