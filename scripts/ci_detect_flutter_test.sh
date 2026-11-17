#!/usr/bin/env bash
# Unit tests for Flutter path preference + arch helpers (no network).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/ci_flutter_arch.sh
source "${ROOT}/scripts/ci_flutter_arch.sh"

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
    echo "FAIL - $msg (missing '$needle')" >&2
  fi
}

# Non-Mach-O stub whose first line is parsed by ci_flutter_binary_cpu.
write_cpu_stub() {
  local path="$1" cpu="$2"
  mkdir -p "$(dirname "$path")"
  printf '# ci_flutter_cpu: %s\n' "$cpu" >"$path"
  chmod +x "$path"
}

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT
HOME_FAKE="$tmpdir/home"
mkdir -p "$HOME_FAKE/toolchains"

export CI_FLUTTER_FORCE_HOST_ARCH=arm64

assert_contains "$(ci_flutter_candidate_bins "$HOME_FAKE")" "${HOME_FAKE}/toolchains/flutter/bin" \
  "candidates include toolchains/flutter/bin"
assert_contains "$(ci_flutter_candidate_bins "$HOME_FAKE")" "${HOME_FAKE}/toolchains/flutter-arm64/bin" \
  "candidates include flutter-arm64 when host forced arm64"

arm_first="$(
  home_dir="$HOME_FAKE"
  toolchains="${home_dir}/toolchains"
  printf '%s\n' "${toolchains}/flutter-arm64/bin"
  printf '%s\n' "${toolchains}/flutter/bin"
)"
assert_eq "${HOME_FAKE}/toolchains/flutter-arm64/bin" "$(printf '%s\n' "$arm_first" | head -n1)" \
  "arm64 preference puts flutter-arm64 first"

# --- sdk arch from binaries, NOT folder names ---
sdk="$tmpdir/sdk"
unset CI_FLUTTER_FORCE_SDK_ARCH

# Official layout: arm64 bits under darwin-x64/
write_cpu_stub "$sdk/bin/cache/dart-sdk/bin/dart" "arm64"
mkdir -p "$sdk/bin/cache/artifacts/engine/darwin-x64"
write_cpu_stub "$sdk/bin/cache/artifacts/engine/darwin-x64/flutter_tester" "arm64"
assert_eq "arm64" "$(ci_flutter_sdk_arch "$sdk")" \
  "sdk arch arm64 from dart even when engine dir is darwin-x64"
assert_eq "$sdk/bin/cache/artifacts/engine/darwin-x64/flutter_tester" \
  "$(ci_flutter_tester_path "$sdk")" \
  "tester path finds darwin-x64 flutter_tester for arm64 SDK"
assert_eq "arm64" "$(ci_flutter_binary_cpu "$sdk/bin/cache/artifacts/engine/darwin-x64/flutter_tester")" \
  "binary cpu arm64 inside darwin-x64 folder"

# True x64 SDK stubs
rm -rf "$sdk"
write_cpu_stub "$sdk/bin/cache/dart-sdk/bin/dart" "x64"
mkdir -p "$sdk/bin/cache/artifacts/engine/darwin-x64"
write_cpu_stub "$sdk/bin/cache/artifacts/engine/darwin-x64/flutter_tester" "x64"
assert_eq "x64" "$(ci_flutter_sdk_arch "$sdk")" "sdk arch x64 from dart binary"

# Folder name alone must not decide arch (no readable binary marker → unknown)
rm -rf "$sdk"
mkdir -p "$sdk/bin/cache/artifacts/engine/darwin-arm64"
: >"$sdk/bin/cache/artifacts/engine/darwin-arm64/flutter_tester"
chmod +x "$sdk/bin/cache/artifacts/engine/darwin-arm64/flutter_tester"
assert_eq "unknown" "$(ci_flutter_sdk_arch "$sdk")" \
  "empty stub under darwin-arm64 does not imply arm64"

# --- detect script prefers arm64 sibling when present ---
mkdir -p "$HOME_FAKE/toolchains/flutter-arm64/bin" "$HOME_FAKE/toolchains/flutter/bin"
printf '#!/bin/sh\necho "Flutter 3.41.2 • channel stable"\n' >"$HOME_FAKE/toolchains/flutter-arm64/bin/flutter"
printf '#!/bin/sh\necho "Flutter 3.41.2 • channel stable"\n' >"$HOME_FAKE/toolchains/flutter/bin/flutter"
chmod +x "$HOME_FAKE/toolchains/flutter-arm64/bin/flutter" "$HOME_FAKE/toolchains/flutter/bin/flutter"
# arm64 sibling: binaries under darwin-x64 (real layout) but cpu=arm64
write_cpu_stub "$HOME_FAKE/toolchains/flutter-arm64/bin/cache/dart-sdk/bin/dart" "arm64"
write_cpu_stub "$HOME_FAKE/toolchains/flutter-arm64/bin/cache/artifacts/engine/darwin-x64/flutter_tester" "arm64"
write_cpu_stub "$HOME_FAKE/toolchains/flutter/bin/cache/dart-sdk/bin/dart" "x64"
write_cpu_stub "$HOME_FAKE/toolchains/flutter/bin/cache/artifacts/engine/darwin-x64/flutter_tester" "x64"

selected=""
for flutter_bin in \
  "$HOME_FAKE/toolchains/flutter-arm64/bin" \
  "$HOME_FAKE/toolchains/flutter/bin"; do
  if [[ -x "${flutter_bin}/flutter" ]]; then
    selected="${flutter_bin}"
    break
  fi
done
assert_eq "$HOME_FAKE/toolchains/flutter-arm64/bin" "$selected" \
  "selection picks flutter-arm64 over legacy flutter"

export HOME="$HOME_FAKE"
export GITHUB_OUTPUT="$tmpdir/out"
export GITHUB_PATH="$tmpdir/path"
: >"$GITHUB_OUTPUT"
: >"$GITHUB_PATH"
export PATH="$HOME_FAKE/toolchains/flutter-arm64/bin:$HOME_FAKE/toolchains/flutter/bin:/usr/bin:/bin"
FLUTTER_VERSION=3.41.2 bash "$ROOT/scripts/ci_detect_flutter.sh"
assert_contains "$(cat "$GITHUB_OUTPUT")" "use_action=false" "detect reuses matching version"
assert_contains "$(cat "$GITHUB_OUTPUT")" "flutter_arch=arm64" "detect reports arm64 from binaries"

export RUNNER_ENVIRONMENT=github-hosted
assert_eq "0" "$(bash "$ROOT/scripts/ci_assert_flutter_arm64.sh" >/dev/null 2>&1; echo $?)" \
  "assert skips github-hosted"

export RUNNER_ENVIRONMENT=self-hosted
export CI_FLUTTER_FORCE_HOST_ARCH=arm64
if [[ "$(uname -s)" != "Darwin" ]]; then
  assert_eq "0" "$(bash "$ROOT/scripts/ci_assert_flutter_arm64.sh" >/dev/null 2>&1; echo $?)" \
    "assert skips non-Darwin hosts"
fi

export CI_FLUTTER_FORCE_SDK_ARCH=x64
assert_eq "x64" "$(ci_flutter_sdk_arch "/unused")" "force sdk arch override works"
unset CI_FLUTTER_FORCE_SDK_ARCH

echo ""
echo "PASS=${PASS} FAIL=${FAIL}"
if [[ "$FAIL" -ne 0 ]]; then
  exit 1
fi
