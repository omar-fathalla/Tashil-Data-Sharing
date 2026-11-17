#!/usr/bin/env bash
# Unit tests for wait_ci_flutter_before_smoke.sh defaults / heartbeat wiring.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT/scripts/wait_ci_flutter_before_smoke.sh"
PASS=0
FAIL=0

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

src="$(cat "$SCRIPT")"
assert_contains "$src" "WAIT_CI_FLUTTER_DEADLINE_MIN:-40" "default deadline 40m (≤ job timeout)"
assert_contains "$src" "ci_mac_diag.sh" "uses ci_mac_diag heartbeat"
assert_contains "$src" "wait-ci-flutter-poll-" "heartbeat label per poll"

# Missing token fails fast (no hang).
set +e
out="$(GITHUB_REPOSITORY=o/r GITHUB_SHA=abc123 env -u GH_TOKEN -u GITHUB_TOKEN \
  bash "$SCRIPT" 2>&1)"
rc=$?
set -e
assert_contains "$out" "GH_TOKEN/GITHUB_TOKEN required" "requires token"
[[ "$rc" -ne 0 ]]
PASS=$((PASS + 1))
echo "ok - exits non-zero without token"

echo ""
echo "passed=$PASS failed=$FAIL"
[[ "$FAIL" -eq 0 ]]
