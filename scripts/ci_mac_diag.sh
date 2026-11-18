#!/usr/bin/env bash
# Lightweight Mac CI diagnostics / heartbeat helpers (bash 3.2+ / macOS OK).
#
# Usage:
#   ci_mac_diag.sh heartbeat "<label>"
#   ci_mac_diag.sh loadavg
#   ci_mac_diag.sh epoch_now
#   ci_mac_diag.sh file_mtime <path>
set -euo pipefail

cmd="${1:-}"
shift || true

epoch_now() {
  date +%s
}

file_mtime() {
  local path="$1"
  if [[ ! -e "$path" ]]; then
    echo 0
    return 0
  fi
  if stat -f %m "$path" >/dev/null 2>&1; then
    stat -f %m "$path"
  else
    stat -c %Y "$path"
  fi
}

loadavg_line() {
  if [[ -r /proc/loadavg ]]; then
    # Linux
    awk '{print $1" "$2" "$3}' /proc/loadavg
    return 0
  fi
  # macOS: "12:00  up ..., load averages: 1.23 1.45 1.67"
  local line
  line="$(uptime 2>/dev/null || true)"
  if printf '%s' "$line" | grep -Eq 'load averages?:'; then
    printf '%s\n' "$line" | sed -E 's/.*load averages?:[[:space:]]*//' | tr -d ','
    return 0
  fi
  echo "unknown"
}

heartbeat() {
  local label="${1:-ci}"
  local load runner job run
  load="$(loadavg_line)"
  runner="${RUNNER_NAME:-local}"
  job="${GITHUB_JOB:-none}"
  run="${GITHUB_RUN_ID:-none}"
  echo "ci-mac-diag heartbeat label=${label} runner=${runner} job=${job} run=${run} loadavg=${load} epoch=$(epoch_now)"
}

case "$cmd" in
  heartbeat)
    heartbeat "${1:-ci}"
    ;;
  loadavg)
    loadavg_line
    ;;
  epoch_now)
    epoch_now
    ;;
  file_mtime)
    if [[ -z "${1:-}" ]]; then
      echo "usage: $0 file_mtime <path>" >&2
      exit 2
    fi
    file_mtime "$1"
    ;;
  *)
    echo "usage: $0 heartbeat|loadavg|epoch_now|file_mtime ..." >&2
    exit 2
    ;;
esac
