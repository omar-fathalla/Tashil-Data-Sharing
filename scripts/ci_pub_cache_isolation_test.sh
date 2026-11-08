#!/usr/bin/env bash
# PUB_CACHE isolation checks for scripts/ci_runner_env.sh.
#
# Usage:
#   bash scripts/ci_pub_cache_isolation_test.sh           # unit tests
#   bash scripts/ci_pub_cache_isolation_test.sh --assert  # live job: PUB_CACHE under RUNNER_TEMP
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT/scripts/ci_runner_env.sh"

assert_live() {
  if [[ -z "${RUNNER_TEMP:-}" ]]; then
    echo "ci_pub_cache_isolation: RUNNER_TEMP unset; skip live assert" >&2
    exit 1
  fi
  want="${RUNNER_TEMP}/pub-cache"
  got="${PUB_CACHE:-}"
  if [[ "$got" != "$want" ]]; then
    echo "FAIL: PUB_CACHE must be ${want} (got=${got:-unset})" >&2
    exit 1
  fi
  case "$got" in
    */.pub-cache|*/toolchains/pub-cache)
      echo "FAIL: PUB_CACHE looks shared: ${got}" >&2
      exit 1
      ;;
  esac
  if [[ ! -d "$got" ]]; then
    echo "FAIL: PUB_CACHE dir missing: ${got}" >&2
    exit 1
  fi
  echo "ok - live PUB_CACHE isolated at ${got}"
  exit 0
}

if [[ "${1:-}" == "--assert" ]]; then
  assert_live
fi

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

run_env() {
  local envfile="$1"
  (
    export HOME="$TEST_HOME"
    export GITHUB_ENV="$envfile"
    export GITHUB_PATH="${envfile}.path"
    : >"$GITHUB_PATH"
    bash "$SCRIPT"
  )
}

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT
TEST_HOME="$tmpdir/home"
mkdir -p "$TEST_HOME/toolchains"

# --- With RUNNER_TEMP: force $RUNNER_TEMP/pub-cache ---
envfile="$tmpdir/env1"
: >"$envfile"
export RUNNER_TEMP="$tmpdir/runner-a"
mkdir -p "$RUNNER_TEMP"
unset PUB_CACHE || true
out="$(run_env "$envfile")"
got="$(grep '^PUB_CACHE=' "$envfile" | cut -d= -f2-)"
assert_eq "${RUNNER_TEMP}/pub-cache" "$got" "RUNNER_TEMP forces isolated PUB_CACHE"
assert_contains "$out" "PUB_CACHE=${RUNNER_TEMP}/pub-cache" "stdout logs isolated PUB_CACHE"
if [[ -d "${RUNNER_TEMP}/pub-cache" ]]; then
  PASS=$((PASS + 1))
  echo "ok - creates RUNNER_TEMP/pub-cache dir"
else
  FAIL=$((FAIL + 1))
  echo "FAIL - missing RUNNER_TEMP/pub-cache dir" >&2
fi

# --- Pre-set shared PUB_CACHE is ignored when RUNNER_TEMP is set ---
envfile="$tmpdir/env2"
: >"$envfile"
export RUNNER_TEMP="$tmpdir/runner-b"
mkdir -p "$RUNNER_TEMP"
shared="$TEST_HOME/toolchains/pub-cache"
mkdir -p "$shared"
export PUB_CACHE="$shared"
out="$(run_env "$envfile")"
got="$(grep '^PUB_CACHE=' "$envfile" | cut -d= -f2-)"
assert_eq "${RUNNER_TEMP}/pub-cache" "$got" "ignores pre-set shared PUB_CACHE"
assert_contains "$out" "ignoring pre-set PUB_CACHE=${shared}" "logs override of pre-set PUB_CACHE"
assert_contains "$out" "forcing ${RUNNER_TEMP}/pub-cache" "logs forced RUNNER_TEMP path"

# --- Pre-set ~/.pub-cache style path also ignored ---
envfile="$tmpdir/env3"
: >"$envfile"
export RUNNER_TEMP="$tmpdir/runner-c"
mkdir -p "$RUNNER_TEMP"
export PUB_CACHE="$TEST_HOME/.pub-cache"
out="$(run_env "$envfile")"
got="$(grep '^PUB_CACHE=' "$envfile" | cut -d= -f2-)"
assert_eq "${RUNNER_TEMP}/pub-cache" "$got" "ignores pre-set ~/.pub-cache"
assert_contains "$out" "ignoring pre-set PUB_CACHE=" "logs ignore for ~/.pub-cache preset"

# --- Without RUNNER_TEMP: per-runner toolchains fallback ---
envfile="$tmpdir/env4"
: >"$envfile"
unset RUNNER_TEMP || true
unset PUB_CACHE || true
export RUNNER_NAME="tashil-mac-2"
out="$(run_env "$envfile")"
got="$(grep '^PUB_CACHE=' "$envfile" | cut -d= -f2-)"
want="$TEST_HOME/toolchains/pub-cache/tashil-mac-2"
assert_eq "$want" "$got" "no RUNNER_TEMP → per-runner toolchains pub-cache"
if [[ -d "$want" ]]; then
  PASS=$((PASS + 1))
  echo "ok - creates per-runner toolchains pub-cache dir"
else
  FAIL=$((FAIL + 1))
  echo "FAIL - missing per-runner toolchains pub-cache dir" >&2
fi

echo ""
echo "passed=$PASS failed=$FAIL"
[[ "$FAIL" -eq 0 ]]
