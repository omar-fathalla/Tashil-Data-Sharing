#!/usr/bin/env bash
# Run Firestore emulator product-match tests in a fully isolated per-job sandbox.
#
# Hard rules for a Mac shared with other bots/runners (including other accounts):
#   - Never assume ports 8080/4000/4400/9150 are free — probe each time
#   - Never kill by process name — only the PID tree this script started
#   - Unique demo project id + per-job temp dir (no clash with other users)
#   - CPU capped (GOMAXPROCS) for the go test under the emulator
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RUN_ID="${GITHUB_RUN_ID:-local}"
ATTEMPT="${GITHUB_RUN_ATTEMPT:-0}"
JOB_NAME="${GITHUB_JOB:-job}"

# demo- prefix required for emulator demo mode; keep ≤30 chars.
PROJECT="demo-ci-${RUN_ID}-${ATTEMPT}"
PROJECT="$(echo "$PROJECT" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9-' | cut -c1-30)"
case "$PROJECT" in
  demo-*) ;;
  *) PROJECT="demo-ci-$$" ;;
esac

JOB_DIR="${RUNNER_TEMP:-/tmp}/tashil-emu-${RUN_ID}-${JOB_NAME}-$$"
mkdir -p "$JOB_DIR/tmp" "$JOB_DIR/home/.cache/firebase"
PIDFILE="$JOB_DIR/wrapper.pid"
CFG="$JOB_DIR/firebase.json"
LOG="$JOB_DIR/emulator.log"

REAL_HOME="$(eval echo "~$(id -un)")"
# Isolate Java/Firebase temp+config from other users/jobs; reuse shared JAR cache.
# Keep Go/npm caches on the real home so we do not re-download modules per job.
export TMPDIR="$JOB_DIR/tmp"
export HOME="$JOB_DIR/home"
export GOMODCACHE="${GOMODCACHE:-$REAL_HOME/go/pkg/mod}"
if [[ -d "$REAL_HOME/Library/Caches/go-build" ]]; then
  export GOCACHE="${GOCACHE:-$REAL_HOME/Library/Caches/go-build}"
else
  export GOCACHE="${GOCACHE:-$REAL_HOME/.cache/go-build}"
fi
export npm_config_cache="${npm_config_cache:-$REAL_HOME/.npm}"
if [[ -d "$REAL_HOME/.cache/firebase/emulators" ]]; then
  ln -sfn "$REAL_HOME/.cache/firebase/emulators" "$JOB_DIR/home/.cache/firebase/emulators"
fi

read -r FS_PORT HUB_PORT LOG_PORT <<<"$(python3 "$ROOT/scripts/pick_free_ports.py" -n 3)"
echo "Isolated emulator: firestore=127.0.0.1:${FS_PORT} hub=${HUB_PORT} logging=${LOG_PORT} project=${PROJECT}"
echo "job_dir=${JOB_DIR}"

cat >"$CFG" <<EOF
{
  "emulators": {
    "firestore": { "host": "127.0.0.1", "port": ${FS_PORT} },
    "ui": { "enabled": false },
    "hub": { "host": "127.0.0.1", "port": ${HUB_PORT} },
    "logging": { "host": "127.0.0.1", "port": ${LOG_PORT} }
  }
}
EOF

cleanup() {
  local ec=$?
  if [[ -f "$PIDFILE" ]]; then
    local pid
    pid="$(cat "$PIDFILE" 2>/dev/null || true)"
    if [[ -n "${pid:-}" ]] && kill -0 "$pid" 2>/dev/null; then
      echo "Stopping this job's emulator wrapper PID ${pid} only (no name-based kills)"
      # Prefer process-group kill when the wrapper was started in its own group.
      kill -- "-${pid}" 2>/dev/null || kill "${pid}" 2>/dev/null || true
      sleep 1
      kill -9 -- "-${pid}" 2>/dev/null || kill -9 "${pid}" 2>/dev/null || true
      # Also stop direct children of the wrapper if still alive (still PID-based).
      if command -v pgrep >/dev/null 2>&1; then
        pgrep -P "${pid}" 2>/dev/null | while read -r cpid; do
          kill "${cpid}" 2>/dev/null || true
          kill -9 "${cpid}" 2>/dev/null || true
        done
      fi
    fi
  fi
  rm -rf "$JOB_DIR" 2>/dev/null || true
  exit "$ec"
}
trap cleanup EXIT INT TERM

cd "$ROOT"

# Own process group so EXIT only tears down this job's tree.
set -m
npx --yes firebase-tools@13.29.1 emulators:exec \
  --only firestore \
  --project "$PROJECT" \
  --config "$CFG" \
  "cd backend-go && \
    export FIRESTORE_EMULATOR_PROJECT=$PROJECT GCLOUD_PROJECT=$PROJECT GOOGLE_CLOUD_PROJECT=$PROJECT && \
    echo FIRESTORE_EMULATOR_HOST=\$FIRESTORE_EMULATOR_HOST PROJECT=$PROJECT && \
    GOMAXPROCS=2 go test ./internal/service/firestore/ -count=1 -timeout 10m -parallel 1 -run Emulator" \
  >"$LOG" 2>&1 &
echo $! >"$PIDFILE"
set +m

if wait "$(cat "$PIDFILE")"; then
  ec=0
else
  ec=$?
fi
echo "----- emulator log (tail) -----"
tail -n 100 "$LOG" || true
exit "$ec"
