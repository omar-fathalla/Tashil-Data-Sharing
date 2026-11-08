#!/usr/bin/env bash
# Per-runner env for tashil-ci / tashil-mac self-hosted jobs.
# Do not hardcode /Users/fathalla — use $HOME and ANDROID_HOME.
#
# Toolchains live at $HOME/toolchains on tashil-ci.
# ADB server ports are unique per runner so parallel jobs do not clash.
# Android emulator consoles stay in 5600+ (other bot owns 5570–5580).
set -euo pipefail

HOME_DIR="${HOME:-$(eval echo "~$(id -un)")}"
TOOLCHAINS="${HOME_DIR}/toolchains"

# Prefer toolchains on PATH when present (Go/Flutter/Java/Android SDK wrappers).
if [[ -d "${TOOLCHAINS}/bin" ]]; then
  echo "${TOOLCHAINS}/bin" >>"${GITHUB_PATH:-/dev/null}"
  export PATH="${TOOLCHAINS}/bin:${PATH}"
fi

# Flutter SDK lives at $HOME/toolchains/flutter (not always symlinked into toolchains/bin).
# Missing this path forces flutter-action downloads that have starved self-hosted Mac runners
# ("lost communication with the server" mid-setup).
for flutter_bin in \
  "${TOOLCHAINS}/flutter/bin" \
  "${HOME_DIR}/flutter/bin" \
  "${HOME_DIR}/fvm/default/bin"; do
  if [[ -x "${flutter_bin}/flutter" ]]; then
    echo "${flutter_bin}" >>"${GITHUB_PATH:-/dev/null}"
    export PATH="${flutter_bin}:${PATH}"
    break
  fi
done

# Shared pub cache on the Mac home disk (same idea as local GOMODCACHE).
# Remote actions/cache for ~/.pub-cache stalls / fights concurrent Flutter jobs;
# point PUB_CACHE at a stable toolchains path instead.
PUB_CACHE_DIR="${PUB_CACHE:-${TOOLCHAINS}/pub-cache}"
mkdir -p "${PUB_CACHE_DIR}"
export PUB_CACHE="${PUB_CACHE_DIR}"
if [[ -n "${GITHUB_ENV:-}" ]]; then
  echo "PUB_CACHE=${PUB_CACHE}" >>"${GITHUB_ENV}"
fi

# Android SDK: honor existing ANDROID_HOME, else $HOME/toolchains/android-sdk.
if [[ -z "${ANDROID_HOME:-}" ]]; then
  if [[ -d "${TOOLCHAINS}/android-sdk" ]]; then
    export ANDROID_HOME="${TOOLCHAINS}/android-sdk"
  elif [[ -d "${HOME_DIR}/Library/Android/sdk" ]]; then
    export ANDROID_HOME="${HOME_DIR}/Library/Android/sdk"
  fi
fi
if [[ -n "${ANDROID_HOME:-}" ]]; then
  echo "ANDROID_HOME=${ANDROID_HOME}" >>"${GITHUB_ENV:-/dev/null}"
fi

# Stable per-runner ADB server port (avoid default 5037 collisions across runners).
runner="${RUNNER_NAME:-unknown}"
case "$runner" in
  *mac-3*|*runner-3*) adb_port=5039 ;;
  *mac-2*|*runner-2*) adb_port=5038 ;;
  *) adb_port=5037 ;;
esac
export ANDROID_ADB_SERVER_PORT="${ANDROID_ADB_SERVER_PORT:-$adb_port}"
export ADB_SERVER_SOCKET="${ADB_SERVER_SOCKET:-tcp:localhost:${ANDROID_ADB_SERVER_PORT}}"
if [[ -n "${GITHUB_ENV:-}" ]]; then
  {
    echo "ANDROID_ADB_SERVER_PORT=${ANDROID_ADB_SERVER_PORT}"
    echo "ADB_SERVER_SOCKET=${ADB_SERVER_SOCKET}"
  } >>"$GITHUB_ENV"
fi

echo "ci_runner_env: HOME=${HOME_DIR} runner=${runner} ANDROID_HOME=${ANDROID_HOME:-unset} ADB=${ANDROID_ADB_SERVER_PORT} PUB_CACHE=${PUB_CACHE}"
