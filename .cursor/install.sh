#!/usr/bin/env bash
# Idempotent dependency sync for Cursor cloud-agent builds.
# Toolchains are installed in the image; this only refreshes lockfile caches.
# Safe to re-run: pub get, go mod download, npm ci, and playwright install
# leave an existing cache in place and do not rewrite lockfiles.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

export GOTOOLCHAIN="${GOTOOLCHAIN:-local}"
export PUB_CACHE="${PUB_CACHE:-${HOME:-/home/ubuntu}/.pub-cache}"

echo "cursor install: repo=${ROOT}"
flutter --version
go version
node --version

if [[ -f tashil_web/pubspec.yaml ]]; then
  (cd tashil_web && flutter pub get)
fi

if [[ -f backend-go/go.mod ]]; then
  (cd backend-go && go mod download)
fi

if [[ -f e2e/package-lock.json ]]; then
  (cd e2e && npm ci)
  if [[ "${TASHIL_SKIP_PLAYWRIGHT_BROWSERS:-0}" != "1" ]]; then
    (cd e2e && npx playwright install chromium)
  fi
fi

echo "cursor install: done"
