#!/bin/bash
# CI Go test runner for shared Mac / ubuntu fallback (bash 3.2+ / macOS OK).
#
# - Caps package parallelism (-p) and GOMAXPROCS (configurable).
# - Runs each package with its own -timeout (avoids one slow package killing
#   the whole `go test ./...` wall clock).
# - Emits go test -json and prints the slowest tests at the end.
# - Optional overall wall clock (CI_GO_TEST_WALL_MIN) + heartbeat diagnostics so
#   Mac thrash / runner-drop investigations leave breadcrumbs before job death.
#
# Env (all optional):
#   CI_GO_TEST_P                 max packages in parallel (default: 2 on Darwin/self-hosted)
#   CI_GO_TEST_GOMAXPROCS        GOMAXPROCS per package (default: same as -p)
#   CI_GO_TEST_PKG_TIMEOUT_MIN   per-package timeout minutes (default: 15)
#   CI_GO_TEST_WALL_MIN          overall wall minutes (default: 35; 0 disables)
#   CI_GO_TEST_HEARTBEAT_SEC     heartbeat interval seconds (default: 60; 0 disables)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

cores="$(sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo 4)"
uname_s="$(uname -s)"

if [ "$uname_s" = "Darwin" ] || [ "${RUNNER_ENVIRONMENT:-}" = "self-hosted" ]; then
  default_p=2
else
  default_p=4
fi

p="${CI_GO_TEST_P:-$default_p}"
if [ "$uname_s" = "Darwin" ] && [ "$p" -gt 3 ]; then
  p=3
fi
if [ "$p" -lt 1 ]; then p=1; fi

g="${CI_GO_TEST_GOMAXPROCS:-$p}"
pkg_timeout_min="${CI_GO_TEST_PKG_TIMEOUT_MIN:-15}"
wall_min="${CI_GO_TEST_WALL_MIN:-35}"
# CI_GO_TEST_WALL_SEC overrides minutes (used by unit tests; unset in production).
wall_sec="${CI_GO_TEST_WALL_SEC:-}"
heartbeat_sec="${CI_GO_TEST_HEARTBEAT_SEC:-60}"

if [[ -n "$wall_sec" ]]; then
  echo "go test CI: -p=$p GOMAXPROCS=$g pkg_timeout=${pkg_timeout_min}m wall=${wall_sec}s heartbeat=${heartbeat_sec}s (cores=$cores)"
else
  echo "go test CI: -p=$p GOMAXPROCS=$g pkg_timeout=${pkg_timeout_min}m wall=${wall_min}m heartbeat=${heartbeat_sec}s (cores=$cores)"
fi

tmpdir="${RUNNER_TEMP:-${TMPDIR:-/tmp}}"
json_out="${tmpdir}/go-test-ci-$$.jsonl"
progress_file="${tmpdir}/go-test-ci-$$.progress"
wall_flag="${tmpdir}/go-test-ci-$$.wall"
: >"$json_out"
: >"$progress_file"
rm -f "$wall_flag"
export GO_TEST_CI_JSON_OUT="$json_out"
export GO_TEST_CI_GOMAXPROCS="$g"
export GO_TEST_CI_PKG_TIMEOUT_MIN="$pkg_timeout_min"
export GO_TEST_CI_PROGRESS_FILE="$progress_file"

diag="$ROOT/scripts/ci_mac_diag.sh"
chmod +x "$diag" 2>/dev/null || true

heartbeat_pid=""
wall_pid=""
xargs_pid=""

cleanup_watchers() {
  if [[ -n "${heartbeat_pid:-}" ]] && kill -0 "$heartbeat_pid" 2>/dev/null; then
    kill "$heartbeat_pid" 2>/dev/null || true
    wait "$heartbeat_pid" 2>/dev/null || true
  fi
  if [[ -n "${wall_pid:-}" ]] && kill -0 "$wall_pid" 2>/dev/null; then
    kill "$wall_pid" 2>/dev/null || true
    wait "$wall_pid" 2>/dev/null || true
  fi
}

trap 'cleanup_watchers' EXIT

start_heartbeat() {
  if [[ "$heartbeat_sec" =~ ^[0-9]+$ ]] && [[ "$heartbeat_sec" -gt 0 ]]; then
    (
      while true; do
        sleep "$heartbeat_sec"
        bash "$diag" heartbeat "go-test" 2>/dev/null || echo "ci-mac-diag heartbeat label=go-test"
        if [[ -s "$progress_file" ]]; then
          echo "go-test progress(tail): $(tail -n 3 "$progress_file" | tr '\n' '; ')"
        else
          echo "go-test progress: (none yet)"
        fi
      done
    ) &
    heartbeat_pid=$!
  fi
}

resolve_wall_seconds() {
  if [[ -n "$wall_sec" ]] && [[ "$wall_sec" =~ ^[0-9]+$ ]] && [[ "$wall_sec" -gt 0 ]]; then
    echo "$wall_sec"
    return 0
  fi
  if [[ "$wall_min" =~ ^[0-9]+$ ]] && [[ "$wall_min" -gt 0 ]]; then
    echo $((wall_min * 60))
    return 0
  fi
  echo 0
}

start_wall_watchdog() {
  local target_pid="$1"
  local secs
  secs="$(resolve_wall_seconds)"
  if [[ "$secs" -gt 0 ]]; then
    (
      sleep "$secs"
      echo "::error::go test CI wall clock exceeded (${secs}s) — killing package fan-out" >&2
      bash "$diag" heartbeat "go-test-wall-exceeded" 2>/dev/null || true
      if [[ -s "$progress_file" ]]; then
        echo "go-test progress at wall kill:" >&2
        cat "$progress_file" >&2 || true
      fi
      : >"$wall_flag"
      if [[ -n "$target_pid" ]] && kill -0 "$target_pid" 2>/dev/null; then
        kill -TERM "-$target_pid" 2>/dev/null || kill -TERM "$target_pid" 2>/dev/null || true
        sleep 1
        kill -KILL "-$target_pid" 2>/dev/null || kill -KILL "$target_pid" 2>/dev/null || true
      fi
    ) &
    wall_pid=$!
  fi
}

# Self-test: prove wall watchdog kills a long fan-out (no real go test).
if [[ "${CI_GO_TEST_SELF_TEST:-}" == "1" ]]; then
  start_heartbeat
  set +e
  sleep 600 &
  xargs_pid=$!
  echo "BEGIN fake/pkg $(date +%s)" >>"$progress_file"
  start_wall_watchdog "$xargs_pid"
  wait "$xargs_pid"
  rc=$?
  set -e
  cleanup_watchers
  trap - EXIT
  if [[ -f "$wall_flag" ]]; then
    echo "go test CI aborted by wall clock ($(resolve_wall_seconds)s)" >&2
    echo "SELF_TEST_WALL_OK"
    exit 124
  fi
  echo "SELF_TEST_WALL_MISS rc=$rc" >&2
  exit 1
fi

cd "$ROOT/backend-go"

run_one() {
  pkg="$1"
  echo "=== BEGIN $pkg ==="
  echo "BEGIN $pkg $(date +%s)" >>"${GO_TEST_CI_PROGRESS_FILE:-/dev/null}" 2>/dev/null || true
  # Intentionally allow go test failure to surface via xargs exit status.
  if ! GOMAXPROCS="$GO_TEST_CI_GOMAXPROCS" go test "$pkg" -count=1 \
      -timeout "${GO_TEST_CI_PKG_TIMEOUT_MIN}m" -json \
      | tee -a "$GO_TEST_CI_JSON_OUT"; then
    echo "FAIL package: $pkg" >&2
    echo "FAIL $pkg $(date +%s)" >>"${GO_TEST_CI_PROGRESS_FILE:-/dev/null}" 2>/dev/null || true
    return 1
  fi
  echo "=== END $pkg ==="
  echo "END $pkg $(date +%s)" >>"${GO_TEST_CI_PROGRESS_FILE:-/dev/null}" 2>/dev/null || true
  return 0
}
export -f run_one

start_heartbeat

# xargs -P: parallel packages, each with its own timeout.
set +e
go list ./... | xargs -P "$p" -n1 -I{} bash -c 'run_one "$@"' _ {} &
xargs_pid=$!
start_wall_watchdog "$xargs_pid"

wait "$xargs_pid"
rc=$?
set -e

cleanup_watchers
trap - EXIT

if [[ -f "$wall_flag" ]]; then
  echo "go test CI aborted by wall clock ($(resolve_wall_seconds)s)" >&2
  rc=124
fi

echo ""
echo "=== Slowest tests (from -json) ==="
python3 - "$json_out" <<'PY'
import json, sys
path = sys.argv[1]
rows = []
with open(path, encoding="utf-8", errors="replace") as f:
    for line in f:
        line = line.strip()
        if not line.startswith("{"):
            continue
        try:
            ev = json.loads(line)
        except json.JSONDecodeError:
            continue
        if ev.get("Action") == "pass" and ev.get("Test") and "Elapsed" in ev:
            rows.append((float(ev["Elapsed"]), ev.get("Package", ""), ev["Test"]))
rows.sort(reverse=True)
for elapsed, pkg, test in rows[:25]:
    print(f"{elapsed:8.3f}s  {pkg}  {test}")
if not rows:
    print("(no per-test timing events found)")
PY

exit "$rc"
