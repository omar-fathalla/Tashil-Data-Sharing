#!/usr/bin/env bash
# Build the Flutter web app so a new deploy replaces a stale service worker.
# Usage: scripts/flutter_build_web.sh <APP_VERSION>
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
N="${1:?APP_VERSION required (integer)}"
if [[ ! "$N" =~ ^[0-9]+$ ]]; then
  echo "APP_VERSION must be an integer, got: $N" >&2
  exit 2
fi
cd "$ROOT/tashil_web"
flutter build web --release --pwa-strategy=none --dart-define=APP_VERSION="$N"
python3 "$ROOT/scripts/flutter_web_postprocess.py" \
  "$ROOT/tashil_web/build/web" \
  "$N" \
  "$ROOT/tashil_web/web/flutter_service_worker.js"
