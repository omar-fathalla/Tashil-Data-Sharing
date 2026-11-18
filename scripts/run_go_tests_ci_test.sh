#!/usr/bin/env bash
# Unit tests for scripts/run_go_tests_ci.sh wall/heartbeat self-test mode.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RUNNER="$ROOT/scripts/run_go_tests_ci.sh"
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

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT
export RUNNER_TEMP="$tmpdir"

head_out="$(head -n 25 "$RUNNER")"
assert_contains "$head_out" "CI_GO_TEST_WALL_MIN" "script documents WALL_MIN"
assert_contains "$head_out" "CI_GO_TEST_HEARTBEAT_SEC" "script documents HEARTBEAT_SEC"

# Live self-test: 2s wall kills a long sleep fan-out → exit 124.
set +e
out="$(CI_GO_TEST_SELF_TEST=1 CI_GO_TEST_WALL_SEC=2 CI_GO_TEST_HEARTBEAT_SEC=0 \
  bash "$RUNNER" 2>&1)"
rc=$?
set -e
assert_eq "124" "$rc" "self-test wall kill exits 124"
assert_contains "$out" "SELF_TEST_WALL_OK" "self-test prints WALL_OK"
assert_contains "$out" "wall=2s" "banner shows WALL_SEC override"
assert_contains "$out" "wall clock exceeded" "emits wall exceeded error"

echo ""
echo "passed=$PASS failed=$FAIL"
[[ "$FAIL" -eq 0 ]]
