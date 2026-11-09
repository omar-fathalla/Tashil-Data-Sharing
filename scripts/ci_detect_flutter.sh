#!/usr/bin/env bash
# Prefer a preinstalled Flutter matching FLUTTER_VERSION (default 3.41.2).
# Writes use_action=true|false to GITHUB_OUTPUT. Exit 0 always for the workflow.
set -euo pipefail

WANT="${FLUTTER_VERSION:-3.41.2}"
HOME_DIR="${HOME:-$(eval echo "~$(id -un)")}"
TOOLCHAINS="${HOME_DIR}/toolchains"

# Ensure known install locations are on PATH for this step (GITHUB_PATH applies next step).
for flutter_bin in \
  "${TOOLCHAINS}/flutter/bin" \
  "${HOME_DIR}/flutter/bin" \
  "${HOME_DIR}/fvm/default/bin" \
  "${TOOLCHAINS}/bin"; do
  if [[ -x "${flutter_bin}/flutter" ]]; then
    export PATH="${flutter_bin}:${PATH}"
    if [[ -n "${GITHUB_PATH:-}" ]]; then
      echo "${flutter_bin}" >>"${GITHUB_PATH}"
    fi
  fi
done

if ! command -v flutter >/dev/null 2>&1; then
  echo "use_action=true" >>"${GITHUB_OUTPUT:?}"
  echo "Preinstalled Flutter ${WANT} not found on PATH; will use flutter-action"
  exit 0
fi

flutter --version || true
if flutter --version 2>/dev/null | grep -q "${WANT}"; then
  echo "use_action=false" >>"${GITHUB_OUTPUT:?}"
  echo "Reusing preinstalled Flutter ${WANT} at $(command -v flutter)"
  exit 0
fi

echo "use_action=true" >>"${GITHUB_OUTPUT:?}"
echo "Found flutter at $(command -v flutter) but not ${WANT}; will use flutter-action"
