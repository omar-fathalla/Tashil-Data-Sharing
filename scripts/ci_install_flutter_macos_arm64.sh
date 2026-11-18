#!/usr/bin/env bash
# Install native macOS arm64 Flutter for tashil-mac self-hosted runners.
#
# Root cause addressed: Apple Silicon hosts with a darwin-x64 (Rosetta) SDK
# thrash under parallel test-flutter + smoke (high loadavg). Prefer a native
# arm64 flutter_tester.
#
# Default install path (sibling of the legacy SDK):
#   $HOME/toolchains/flutter-arm64
#
# CI selects it via scripts/ci_detect_flutter.sh / ci_runner_env.sh on arm64
# Darwin (flutter-arm64 before toolchains/flutter).
#
# Usage (on the Mac as the runner user, e.g. tashil-ci):
#   bash scripts/ci_install_flutter_macos_arm64.sh
#   bash scripts/ci_install_flutter_macos_arm64.sh --version 3.41.2
#   bash scripts/ci_install_flutter_macos_arm64.sh --promote   # also point toolchains/flutter → arm64
#   bash scripts/ci_install_flutter_macos_arm64.sh --dry-run
#
# Env:
#   FLUTTER_VERSION   default 3.41.2 (must match workflow env.FLUTTER_VERSION)
#   HOME              toolchain prefix parent ($HOME/toolchains)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/ci_flutter_arch.sh
source "${ROOT}/scripts/ci_flutter_arch.sh"

VERSION="${FLUTTER_VERSION:-3.41.2}"
PREFIX=""
PROMOTE=0
DRY_RUN=0

usage() {
  sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      VERSION="${2:?}"
      shift 2
      ;;
    --prefix)
      PREFIX="${2:?}"
      shift 2
      ;;
    --promote)
      PROMOTE=1
      shift
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    -h|--help)
      usage 0
      ;;
    *)
      echo "Unknown arg: $1" >&2
      usage 1
      ;;
  esac
done

HOME_DIR="${HOME:-$(eval echo "~$(id -un)")}"
PREFIX="${PREFIX:-${HOME_DIR}/toolchains}"
TARGET="${PREFIX}/flutter-arm64"
LEGACY="${PREFIX}/flutter"
BACKUP_X64="${PREFIX}/flutter-x64"
ARCHIVE_NAME="flutter_macos_arm64_${VERSION}-stable.zip"
ARCHIVE_URL="https://storage.googleapis.com/flutter_infra_release/releases/stable/macos/${ARCHIVE_NAME}"

host="$(ci_flutter_host_arch)"

echo "ci_install_flutter_macos_arm64: version=${VERSION}"
echo "  url=${ARCHIVE_URL}"
echo "  target=${TARGET}"
echo "  promote=${PROMOTE} dry_run=${DRY_RUN} host=$(uname -s)/${host}"

if [[ "${DRY_RUN}" -eq 1 ]]; then
  echo "dry-run: would download, extract to ${TARGET}, verify arm64 dart/flutter_tester"
  if [[ "${PROMOTE}" -eq 1 ]]; then
    echo "dry-run: would promote ${TARGET} → ${LEGACY} (backup x64 to ${BACKUP_X64} if needed)"
  fi
  exit 0
fi

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "error: this installer is for macOS only (got $(uname -s))" >&2
  exit 1
fi
if [[ "${host}" != "arm64" ]]; then
  echo "error: host arch is ${host}; need Apple Silicon (arm64)" >&2
  exit 1
fi

mkdir -p "${PREFIX}"
tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/flutter-arm64-install.XXXXXX")"
cleanup() { rm -rf "${tmpdir}"; }
trap cleanup EXIT

zip_path="${tmpdir}/${ARCHIVE_NAME}"
echo "Downloading ${ARCHIVE_URL} ..."
curl -fL --retry 3 --retry-delay 2 -o "${zip_path}" "${ARCHIVE_URL}"

echo "Extracting ..."
# Official zip contains a top-level "flutter/" directory.
rm -rf "${tmpdir}/extract"
mkdir -p "${tmpdir}/extract"
unzip -q "${zip_path}" -d "${tmpdir}/extract"
if [[ ! -x "${tmpdir}/extract/flutter/bin/flutter" ]]; then
  echo "error: archive missing flutter/bin/flutter" >&2
  exit 1
fi

# Atomic-ish replace of target dir.
rm -rf "${TARGET}.new"
mv "${tmpdir}/extract/flutter" "${TARGET}.new"
rm -rf "${TARGET}.old"
if [[ -d "${TARGET}" ]]; then
  mv "${TARGET}" "${TARGET}.old"
fi
mv "${TARGET}.new" "${TARGET}"
rm -rf "${TARGET}.old"

export PATH="${TARGET}/bin:${PATH}"
echo "Warming dart/flutter tooling (precache macOS host artifacts) ..."
# Pull host engine (flutter_tester) without Android/iOS SDKs.
flutter --version
flutter precache --macos || flutter precache

# Arch comes from lipo/file on dart / flutter_tester — NOT from darwin-x64 folder names
# (official arm64 zips still use engine/darwin-x64/ for host artifacts).
arch="$(ci_flutter_sdk_arch "${TARGET}")"
tester="$(ci_flutter_tester_path "${TARGET}" || true)"
dart_bin="${TARGET}/bin/cache/dart-sdk/bin/dart"
echo "Installed SDK arch=${arch} root=${TARGET}"
if [[ -e "${dart_bin}" ]]; then
  echo "dart=${dart_bin} cpu=$(ci_flutter_binary_cpu "${dart_bin}")"
  if command -v file >/dev/null 2>&1; then
    file "${dart_bin}" || true
  fi
fi
if [[ -n "${tester}" ]]; then
  echo "flutter_tester=${tester} cpu=$(ci_flutter_binary_cpu "${tester}")"
  if command -v file >/dev/null 2>&1; then
    file "${tester}" || true
  fi
fi
if [[ "${arch}" != "arm64" ]]; then
  echo "error: expected arm64 SDK after install (got ${arch} via binary sniff; ignore darwin-* dir names)" >&2
  exit 1
fi

if [[ "${PROMOTE}" -eq 1 ]]; then
  echo "Promoting ${TARGET} → ${LEGACY}"
  if [[ -e "${LEGACY}" || -L "${LEGACY}" ]]; then
    legacy_arch="$(ci_flutter_sdk_arch "${LEGACY}" || echo unknown)"
    if [[ "${legacy_arch}" == "x64" || "${legacy_arch}" == "unknown" ]]; then
      if [[ -e "${BACKUP_X64}" || -L "${BACKUP_X64}" ]]; then
        echo "warning: ${BACKUP_X64} already exists; leaving it in place"
      else
        mv "${LEGACY}" "${BACKUP_X64}"
        echo "Moved previous SDK to ${BACKUP_X64} (arch=${legacy_arch})"
      fi
    elif [[ "${legacy_arch}" == "arm64" ]]; then
      rm -rf "${LEGACY}"
    fi
  fi
  # Relative symlink so the whole toolchains tree remains relocatable.
  ln -sfn "flutter-arm64" "${LEGACY}"
  echo "Linked ${LEGACY} -> flutter-arm64"
fi

echo "OK: native arm64 Flutter ${VERSION} ready at ${TARGET}"
echo "CI will prefer \$HOME/toolchains/flutter-arm64 on Apple Silicon (see docs/ci-self-hosted.md)."
echo "No workflow re-run required after install — next Mac Flutter/smoke job picks it up."
