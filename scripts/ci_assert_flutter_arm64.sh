#!/usr/bin/env bash
# On Apple Silicon self-hosted runners, require a native arm64 Flutter SDK.
# Exit 0 on non-Darwin, non-arm64 hosts, or github-hosted runners.
#
# Usage:
#   bash scripts/ci_assert_flutter_arm64.sh
#
# Env:
#   CI_ASSERT_FLUTTER_ARM64=0   skip (emergency bypass)
#   RUNNER_ENVIRONMENT          Actions sets self-hosted | github-hosted
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/ci_flutter_arch.sh
source "${ROOT}/scripts/ci_flutter_arch.sh"

if [[ "${CI_ASSERT_FLUTTER_ARM64:-1}" == "0" ]]; then
  echo "ci_assert_flutter_arm64: skipped (CI_ASSERT_FLUTTER_ARM64=0)"
  exit 0
fi

# Only enforce on self-hosted (github-hosted ubuntu uses flutter-action).
if [[ "${RUNNER_ENVIRONMENT:-}" == "github-hosted" ]]; then
  echo "ci_assert_flutter_arm64: skip (github-hosted)"
  exit 0
fi

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "ci_assert_flutter_arm64: skip (not Darwin)"
  exit 0
fi

host="$(ci_flutter_host_arch)"
if [[ "${host}" != "arm64" ]]; then
  echo "ci_assert_flutter_arm64: skip (host=${host})"
  exit 0
fi

if ! command -v flutter >/dev/null 2>&1; then
  echo "::error::flutter not on PATH; install via scripts/ci_install_flutter_macos_arm64.sh"
  exit 1
fi

sdk_root="$(ci_flutter_sdk_root)"
arch="$(ci_flutter_sdk_arch "${sdk_root}")"
tester="$(ci_flutter_tester_path "${sdk_root}" || true)"

echo "ci_assert_flutter_arm64: host=${host} sdk_root=${sdk_root} sdk_arch=${arch}"
if [[ -n "${tester}" && -e "${tester}" ]]; then
  echo "flutter_tester=${tester}"
  if command -v file >/dev/null 2>&1; then
    file "${tester}" || true
  fi
fi

if [[ "${arch}" == "arm64" ]]; then
  echo "ok - native arm64 Flutter SDK"
  exit 0
fi

cat <<EOF
::error::Flutter SDK on this Apple Silicon runner is ${arch} (want arm64). darwin-x64/Rosetta flutter_tester thrash under parallel Mac CI.
Install native arm64 Flutter as the runner user (tashil-ci), then re-run:

  bash scripts/ci_install_flutter_macos_arm64.sh
  # optional: also point \$HOME/toolchains/flutter at the arm64 install
  bash scripts/ci_install_flutter_macos_arm64.sh --promote

Default path: \$HOME/toolchains/flutter-arm64 (preferred by ci_detect_flutter.sh).
See docs/ci-self-hosted.md § Flutter SDK (arm64).
EOF
exit 1
