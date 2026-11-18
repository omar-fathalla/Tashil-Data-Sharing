#!/usr/bin/env bash
# Unit tests for scripts/ci_mac_diag.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIAG="$ROOT/scripts/ci_mac_diag.sh"
PASS=0
FAIL=0

assert_eq() {
  local want="$1" got="$2" msg="$3"
  if [[ "$want" == "$got" ]]; then
    PASS=$((PASS + 1))
    echo "ok - $msg"
  else
    FAIL=$((FAIL + 1))
    echo "FAIL - $msg (want=$want got=$got)" >&2
  fi
}

assert_contains() {
  local hay="$1" needle="$2" msg="$3"
  if printf '%s' "$hay" | grep -Fq -- "$needle"; then
    PASS=$((PASS + 1))
    echo "ok - $msg"
  else
    FAIL=$((FAIL + 1))
    echo "FAIL - $msg (missing '$needle' in: $hay)" >&2
  fi
}

assert_gt() {
  local a="$1" b="$2" msg="$3"
  if [[ "$a" -gt "$b" ]]; then
    PASS=$((PASS + 1))
    echo "ok - $msg"
  else
    FAIL=$((FAIL + 1))
    echo "FAIL - $msg ($a !> $b)" >&2
  fi
}

epoch="$("$DIAG" epoch_now)"
assert_gt "$epoch" 1700000000 "epoch_now returns unix seconds"

load="$("$DIAG" loadavg)"
[[ -n "$load" ]]
PASS=$((PASS + 1))
echo "ok - loadavg non-empty ($load)"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT
echo x >"$tmpdir/f"
mt="$("$DIAG" file_mtime "$tmpdir/f")"
assert_gt "$mt" 0 "file_mtime of existing file"
mt0="$("$DIAG" file_mtime "$tmpdir/missing")"
assert_eq "0" "$mt0" "file_mtime missing → 0"

export RUNNER_NAME="tashil-mac-test" GITHUB_JOB="unit" GITHUB_RUN_ID="123"
out="$("$DIAG" heartbeat "go-test")"
assert_contains "$out" "ci-mac-diag heartbeat" "heartbeat prefix"
assert_contains "$out" "label=go-test" "heartbeat label"
assert_contains "$out" "runner=tashil-mac-test" "heartbeat runner"
assert_contains "$out" "loadavg=" "heartbeat loadavg"

echo ""
echo "passed=$PASS failed=$FAIL"
[[ "$FAIL" -eq 0 ]]
