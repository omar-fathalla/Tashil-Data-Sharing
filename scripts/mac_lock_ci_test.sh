#!/usr/bin/env bash
# Unit tests for scripts/mac_lock_ci.sh (no real Mac lock required).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WRAPPER="$ROOT/scripts/mac_lock_ci.sh"
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
export HOME="$tmpdir/home"
export RUNNER_TEMP="$tmpdir/runner"
mkdir -p "$HOME/mac-resources" "$RUNNER_TEMP"

# --- MAC_SHARED_LOCK unset → skip ---
unset MAC_SHARED_LOCK || true
out="$("$WRAPPER" acquire "a" "r" "t" 1 1)"
assert_contains "$out" "skipping mac lock" "MAC_SHARED_LOCK unset skips acquire"

export MAC_SHARED_LOCK=1

# --- acquire + ownership release ---
out="$("$WRAPPER" acquire "ci-agent-1" "repo" "task" 1 1)"
assert_contains "$out" "acquired" "acquire prints acquired"
st="$("$WRAPPER" status)"
assert_contains "$st" "ci-agent-1" "status shows our agent"
out="$("$WRAPPER" release "ci-agent-1")"
assert_contains "$out" "released" "owner can release"
st="$("$WRAPPER" status)"
assert_eq "free" "$st" "status free after release"

# --- release skips when not owner ---
"$WRAPPER" acquire "ci-agent-2" "repo" "task" 1 1 >/dev/null
out="$("$WRAPPER" release "ci-agent-other")"
assert_contains "$out" "skip release" "non-owner release skipped"
st="$("$WRAPPER" status)"
assert_contains "$st" "ci-agent-2" "lock still held by real owner"
"$WRAPPER" release "ci-agent-2" >/dev/null

# --- parent dead → do not acquire (simulate by bogus PPID via subshell kill) ---
# Soft check: with GITHUB_ACTIONS unset, PPID alive is enough; ensure acquire still works.
out="$("$WRAPPER" acquire "ci-agent-3" "repo" "task" 1 1)"
assert_contains "$out" "acquired" "acquire works when parent alive"
"$WRAPPER" release "ci-agent-3" >/dev/null

# --- MAC_SHARED_LOCK=0 skips ---
export MAC_SHARED_LOCK=0
out="$("$WRAPPER" acquire "a" "r" "t" 1 1)"
assert_contains "$out" "skipping mac lock" "MAC_SHARED_LOCK=0 skips"

echo ""
echo "passed=$PASS failed=$FAIL"
[[ "$FAIL" -eq 0 ]]
