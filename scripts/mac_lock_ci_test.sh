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

assert_file() {
  local path="$1" msg="$2"
  if [[ -f "$path" ]]; then
    PASS=$((PASS + 1))
    echo "ok - $msg"
  else
    FAIL=$((FAIL + 1))
    echo "FAIL - $msg (missing file $path)" >&2
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
assert_file "$HOME/mac-resources/LOCK.d/acquired_epoch" "acquire writes acquired_epoch"
assert_file "$HOME/mac-resources/LOCK.d/eta_deadline_epoch" "acquire writes eta_deadline_epoch"
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

# --- MAC_RESOURCES_DIR override ---
export MAC_SHARED_LOCK=1
alt="$tmpdir/shared-mac-resources"
mkdir -p "$alt"
export MAC_RESOURCES_DIR="$alt"
out="$("$WRAPPER" acquire "ci-agent-dir" "repo" "task" 1 1)"
assert_contains "$out" "acquired" "acquire honors MAC_RESOURCES_DIR"
assert_file "$alt/LOCK.d/owner" "lock lives under MAC_RESOURCES_DIR"
"$WRAPPER" release "ci-agent-dir" >/dev/null
unset MAC_RESOURCES_DIR

# --- stale reclaim: expired eta_deadline_epoch + grace=0 ---
export MAC_LOCK_STALE_GRACE_MIN=0
mkdir -p "$HOME/mac-resources/LOCK.d"
echo "agent=dead-orphan | repo=r | task=t | start=old Cairo | eta=1 min | pid=1" \
  >"$HOME/mac-resources/LOCK.d/owner"
echo "1" >"$HOME/mac-resources/LOCK.d/acquired_epoch"
echo "1" >"$HOME/mac-resources/LOCK.d/eta_deadline_epoch"  # long expired
out="$("$WRAPPER" acquire "ci-agent-reclaim" "repo" "task" 1 1 2>&1)"
assert_contains "$out" "reclaiming stale Mac lock" "stale lock is reclaimed"
assert_contains "$out" "acquired" "acquire succeeds after reclaim"
st="$("$WRAPPER" status)"
assert_contains "$st" "ci-agent-reclaim" "reclaimer owns lock"
"$WRAPPER" release "ci-agent-reclaim" >/dev/null
unset MAC_LOCK_STALE_GRACE_MIN

# --- fresh lock is NOT reclaimed (long eta, grace high) ---
export MAC_LOCK_STALE_GRACE_MIN=60
"$WRAPPER" acquire "ci-agent-fresh" "repo" "task" 60 1 >/dev/null
# Second acquire with short wait should fail (lock still fresh).
set +e
out="$("$WRAPPER" acquire "ci-agent-waiter" "repo" "task" 1 0 2>&1)"
rc=$?
set -e
assert_eq "1" "$rc" "fresh lock blocks second acquire"
assert_contains "$out" "LOCK busy" "fresh lock reports busy"
"$WRAPPER" release "ci-agent-fresh" >/dev/null
unset MAC_LOCK_STALE_GRACE_MIN

echo ""
echo "passed=$PASS failed=$FAIL"
[[ "$FAIL" -eq 0 ]]
