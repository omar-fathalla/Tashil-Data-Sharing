#!/usr/bin/env bash
# Prefer a preinstalled Flutter matching FLUTTER_VERSION (default 3.41.2).
# On Apple Silicon, prefer $HOME/toolchains/flutter-arm64 (native) over
# $HOME/toolchains/flutter (often a legacy darwin-x64 / Rosetta install).
# Writes use_action=true|false and flutter_arch=… to GITHUB_OUTPUT. Exit 0 always for the workflow.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/ci_flutter_arch.sh
source "${ROOT}/scripts/ci_flutter_arch.sh"

WANT="${FLUTTER_VERSION:-3.41.2}"
HOME_DIR="${HOME:-$(eval echo "~$(id -un)")}"

write_output() {
  local key="$1" val="$2"
  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    echo "${key}=${val}" >>"${GITHUB_OUTPUT}"
  fi
}

# First existing candidate wins (arm64 sibling before legacy flutter on Apple Silicon).
# Only prepend that one bin dir — later candidates must not shadow it on PATH.
selected_bin=""
while IFS= read -r flutter_bin; do
  [[ -z "${flutter_bin}" ]] && continue
  if [[ -x "${flutter_bin}/flutter" ]]; then
    selected_bin="${flutter_bin}"
    break
  fi
done < <(ci_flutter_candidate_bins "${HOME_DIR}")
if [[ -n "${selected_bin}" ]]; then
  export PATH="${selected_bin}:${PATH}"
  if [[ -n "${GITHUB_PATH:-}" ]]; then
    echo "${selected_bin}" >>"${GITHUB_PATH}"
  fi
fi

if ! command -v flutter >/dev/null 2>&1; then
  write_output use_action true
  write_output flutter_arch unknown
  echo "Preinstalled Flutter ${WANT} not found on PATH; will use flutter-action"
  exit 0
fi

sdk_root="$(ci_flutter_sdk_root)"
sdk_arch="$(ci_flutter_sdk_arch "${sdk_root}")"
write_output flutter_arch "${sdk_arch}"
echo "Selected Flutter at $(command -v flutter) root=${sdk_root} arch=${sdk_arch}"

flutter --version || true
if flutter --version 2>/dev/null | grep -q "${WANT}"; then
  write_output use_action false
  echo "Reusing preinstalled Flutter ${WANT} at $(command -v flutter) (arch=${sdk_arch})"
  exit 0
fi

write_output use_action true
echo "Found flutter at $(command -v flutter) but not ${WANT}; will use flutter-action"
