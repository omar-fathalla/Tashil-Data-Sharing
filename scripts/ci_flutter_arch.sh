#!/usr/bin/env bash
# Shared helpers: host CPU arch + Flutter SDK / flutter_tester arch for tashil-mac.
# Sourced by detect / assert / install scripts. Safe under bash 3.2 (macOS).
#
# IMPORTANT: Official macOS arm64 Flutter zips still place host engine artifacts
# under bin/cache/artifacts/engine/darwin-x64/. Never infer CPU arch from that
# folder name — inspect the Mach-O with lipo/file instead.
#
# Env overrides (tests / dry diagnostics only):
#   CI_FLUTTER_FORCE_HOST_ARCH=arm64|x86_64
#   CI_FLUTTER_FORCE_SDK_ARCH=arm64|x64|unknown

ci_flutter_host_arch() {
  if [[ -n "${CI_FLUTTER_FORCE_HOST_ARCH:-}" ]]; then
    printf '%s\n' "${CI_FLUTTER_FORCE_HOST_ARCH}"
    return 0
  fi
  uname -m
}

# Prefer native arm64 SDK on Apple Silicon; keep x64 path as fallback.
# Prints candidate bin dirs (absolute), one per line, highest preference first.
ci_flutter_candidate_bins() {
  local home_dir toolchains host
  home_dir="${1:-${HOME:-$(eval echo "~$(id -un)")}}"
  toolchains="${home_dir}/toolchains"
  host="$(ci_flutter_host_arch)"

  # Prefer flutter-arm64 on Apple Silicon. CI_FLUTTER_FORCE_HOST_ARCH=arm64 also
  # enables the sibling path (unit tests on Linux agents).
  if [[ "${host}" == "arm64" ]]; then
    if [[ "$(uname -s 2>/dev/null || echo unknown)" == "Darwin" || -n "${CI_FLUTTER_FORCE_HOST_ARCH:-}" ]]; then
      printf '%s\n' "${toolchains}/flutter-arm64/bin"
    fi
  fi
  printf '%s\n' \
    "${toolchains}/flutter/bin" \
    "${home_dir}/flutter/bin" \
    "${home_dir}/fvm/default/bin" \
    "${toolchains}/bin"
}

# Resolve Flutter SDK root from a flutter binary on PATH (or empty).
ci_flutter_sdk_root() {
  local flutter_bin root
  flutter_bin="$(command -v flutter 2>/dev/null || true)"
  if [[ -z "${flutter_bin}" ]]; then
    return 0
  fi
  # Prefer physical path when symlink (promoted flutter → flutter-arm64).
  if command -v realpath >/dev/null 2>&1; then
    flutter_bin="$(realpath "${flutter_bin}" 2>/dev/null || printf '%s' "${flutter_bin}")"
  elif command -v readlink >/dev/null 2>&1; then
    local linked
    linked="$(readlink "${flutter_bin}" 2>/dev/null || true)"
    if [[ -n "${linked}" && "${linked}" != /* ]]; then
      linked="$(cd "$(dirname "${flutter_bin}")" && pwd)/${linked}"
    fi
    if [[ -n "${linked}" ]]; then
      flutter_bin="${linked}"
    fi
  fi
  root="$(cd "$(dirname "${flutter_bin}")/.." && pwd)"
  printf '%s\n' "${root}"
}

# CPU arch of one binary: arm64 | x64 | unknown
# Uses lipo -archs / file. Never uses parent directory names.
# Unit-test stub: a non-Mach-O file whose first line is "# ci_flutter_cpu: arm64|x64".
ci_flutter_binary_cpu() {
  local bin="${1:-}"
  if [[ -z "${bin}" || ! -e "${bin}" ]]; then
    echo "unknown"
    return 0
  fi

  local info=""
  if command -v lipo >/dev/null 2>&1; then
    info="$(lipo -archs "${bin}" 2>/dev/null || true)"
  fi
  if [[ -z "${info}" ]] && command -v file >/dev/null 2>&1; then
    info="$(file -b "${bin}" 2>/dev/null || true)"
  fi
  case "${info}" in
    *arm64*) echo "arm64"; return 0 ;;
    *x86_64*|*x86-64*) echo "x64"; return 0 ;;
  esac

  local line
  line="$(head -n1 "${bin}" 2>/dev/null || true)"
  case "${line}" in
    "# ci_flutter_cpu: arm64") echo "arm64"; return 0 ;;
    "# ci_flutter_cpu: x64") echo "x64"; return 0 ;;
  esac

  echo "unknown"
}

# Locate flutter_tester under the SDK (folder may be darwin-x64 even for arm64).
ci_flutter_tester_path() {
  local root="${1:-}"
  local p
  if [[ -z "${root}" ]]; then
    root="$(ci_flutter_sdk_root)"
  fi
  if [[ -z "${root}" ]]; then
    return 0
  fi
  # Prefer darwin-arm64 if present; else darwin-x64 (common for arm64 SDK zips).
  for p in \
    "${root}/bin/cache/artifacts/engine/darwin-arm64/flutter_tester" \
    "${root}/bin/cache/artifacts/engine/darwin-x64/flutter_tester"; do
    if [[ -e "${p}" ]]; then
      printf '%s\n' "${p}"
      return 0
    fi
  done
}

# Detect SDK CPU arch: arm64 | x64 | unknown — from binaries only.
ci_flutter_sdk_arch() {
  local root="${1:-}"
  if [[ -n "${CI_FLUTTER_FORCE_SDK_ARCH:-}" ]]; then
    printf '%s\n' "${CI_FLUTTER_FORCE_SDK_ARCH}"
    return 0
  fi
  if [[ -z "${root}" ]]; then
    root="$(ci_flutter_sdk_root)"
  fi
  if [[ -z "${root}" || ! -d "${root}" ]]; then
    echo "unknown"
    return 0
  fi

  local dart_bin tester cpu
  dart_bin="${root}/bin/cache/dart-sdk/bin/dart"
  if [[ -e "${dart_bin}" ]]; then
    cpu="$(ci_flutter_binary_cpu "${dart_bin}")"
    if [[ "${cpu}" != "unknown" ]]; then
      printf '%s\n' "${cpu}"
      return 0
    fi
  fi

  tester="$(ci_flutter_tester_path "${root}" || true)"
  if [[ -n "${tester}" ]]; then
    cpu="$(ci_flutter_binary_cpu "${tester}")"
    if [[ "${cpu}" != "unknown" ]]; then
      printf '%s\n' "${cpu}"
      return 0
    fi
  fi

  echo "unknown"
}
