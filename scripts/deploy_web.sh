#!/usr/bin/env bash
# Build + deploy the Flutter web app to Firebase Hosting, bumping the deploy
# version shown in the sidebar. Usage: scripts/deploy_web.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VFILE="$ROOT/tashil_web/deploy_version.txt"
PROJECT="tashil-data-sharing"

OLD="$(tr -dc '0-9' < "$VFILE")"; OLD="${OLD:-0}"
NEW=$((OLD + 1))
echo "$NEW" > "$VFILE"
restore() { echo "$OLD" > "$VFILE"; echo "Deploy failed; version restored to $OLD" >&2; }
trap restore ERR

echo "==> Building web v$NEW"
bash "$ROOT/scripts/flutter_build_web.sh" "$NEW"
echo "==> Deploying to Firebase Hosting ($PROJECT)"
(cd "$ROOT" && firebase deploy --only hosting --project "$PROJECT")
trap - ERR

(cd "$ROOT" && git add tashil_web/deploy_version.txt && git commit -m "chore: web deploy v$NEW" -- tashil_web/deploy_version.txt)
echo "==> Deployed v$NEW (committed, not pushed)"
