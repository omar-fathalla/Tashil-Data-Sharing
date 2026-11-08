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

# Fake lock script: records invocations; can rewrite itself mid-acquire to
# simulate the production failure mode (live file mutated under bash).
cat > "$HOME/mac-resources/mac-lock.sh" <<'EOF'
#!/bin/bash
# Fake mac-lock for tests. LOCK.d under $HOME/mac-resources.
D="$HOME/mac-resources"; L="$D/LOCK.d"
case "$1" in
  acquire)
    agent="$2"; repo="$3"; task="$4"
    # Simulate another agent rewriting the live script while a waiter runs.
    if [[ "${REWRITE_SELF:-0}" == "1" ]]; then
      cat > "$0" <<'BROKEN'
#!/bin/bash
echo "rewritten underfoot"
      *) echo "not owner (held by: broken)"; exit 1;; esac;;
BROKEN
      # Continue using *this* process's already-read/copied text if caller
      # executed a private copy; if they exec'd $0 live, further lines may
      # be garbage. We still take the lock so ownership release can be tested.
    fi
    mkdir "$L"
    echo "agent=$agent | repo=$repo | task=$task | start=test | eta=1 min | pid=$$" > "$L/owner"
    echo "acquired"
    ;;
  release)
    owner=$(cat "$L/owner" 2>/dev/null || true)
    case "$owner" in
      *"agent=$2 "*) rm -rf "$L"; echo "released";;
      *) echo "not owner (held by: $owner)"; exit 1;;
    esac
    ;;
  status)
    if [[ -d "$L" ]]; then cat "$L/owner"; else echo "free"; fi
    ;;
  *) echo "usage"; exit 2;;
esac
EOF
chmod +x "$HOME/mac-resources/mac-lock.sh"

# --- missing script skips ---
rm -f "$HOME/mac-resources/mac-lock.sh"
out="$("$WRAPPER" acquire "a" "r" "t" 1 1)"
assert_contains "$out" "skipping" "missing script skips acquire"
# restore fake
cat > "$HOME/mac-resources/mac-lock.sh" <<'EOF'
#!/bin/bash
D="$HOME/mac-resources"; L="$D/LOCK.d"
case "$1" in
  acquire)
    agent="$2"; repo="$3"; task="$4"
    if [[ "${REWRITE_SELF:-0}" == "1" ]]; then
      printf '%s\n' '#!/bin/bash' 'echo rewritten' '      *) echo "not owner (held by: x)"; exit 1;; esac;;' > "$0"
    fi
    mkdir -p "$D"
    mkdir "$L"
    echo "agent=$agent | repo=$repo | task=$task | start=test | eta=1 min | pid=$$" > "$L/owner"
    echo "acquired"
    ;;
  release)
    owner=$(cat "$L/owner" 2>/dev/null || true)
    case "$owner" in
      *"agent=$2 "*) rm -rf "$L"; echo "released";;
      *) echo "not owner (held by: $owner)"; exit 1;;
    esac
    ;;
  status)
    if [[ -d "$L" ]]; then cat "$L/owner"; else echo "free"; fi
    ;;
  *) echo "usage"; exit 2;;
esac
EOF

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

# --- rewrite-underfoot: live SRC mutates; private copy still acquires ---
export REWRITE_SELF=1
out="$(REWRITE_SELF=1 "$WRAPPER" acquire "ci-agent-3" "repo" "task" 1 1)"
assert_contains "$out" "acquired" "acquire via copy survives live rewrite"
# Live file should now be broken garbage; wrapper must still release via its copy.
out="$("$WRAPPER" release "ci-agent-3")"
assert_contains "$out" "released" "release via copy after live rewrite"
unset REWRITE_SELF

echo ""
echo "passed=$PASS failed=$FAIL"
[[ "$FAIL" -eq 0 ]]
