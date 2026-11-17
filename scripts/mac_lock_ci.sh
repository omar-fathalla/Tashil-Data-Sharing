#!/usr/bin/env bash
# Safe CI wrapper for the shared Mac lock (fathalla-mac / tashil-mac).
#
# Does NOT modify ~/mac-resources — only reads LOCK.d / USAGE_LOG and may copy
# mac-lock.sh for release compatibility. (Reclaim may remove a *stale* LOCK.d.)
#
# Guards:
# 1) Never exec the live mac-lock.sh for long waits (copy or native wait loop).
# 2) Opt-in via MAC_SHARED_LOCK=1 (unset/0 → skip). Recommend =1 while 2+ runners
#    share one Mac (cross-repo). PR/test heavies have no shared job concurrency
#    group (pending-slot eviction); deploys use tashil-deploy only.
# 3) Parent-alive: while waiting, and again after acquire, abort/release if the
#    GHA Runner.Worker / $PPID chain looks dead (avoids orphan LOCK.d after cancel).
# 4) Stale reclaim: if LOCK.d outlives eta (+ grace), remove it so a runner-drop
#    orphan does not block the next heavy job (common when release never runs).
#
# Env:
#   MAC_SHARED_LOCK=1            required to enable
#   MAC_RESOURCES_DIR            override lock root (default: $HOME/mac-resources).
#                                Point all runner users at one shared path when
#                                tashil-mac* span multiple $HOME values.
#   MAC_LOCK_STALE_GRACE_MIN     minutes after eta before reclaim (default: 10)
#
# Usage:
#   mac_lock_ci.sh acquire "<agent>" "<repo>" "<task>" <eta_min> [wait_max_min]
#   mac_lock_ci.sh release "<agent>"
#   mac_lock_ci.sh status
set -euo pipefail

MAC_DIR="${MAC_RESOURCES_DIR:-${HOME}/mac-resources}"
SRC="${MAC_LOCK_SRC:-${MAC_DIR}/mac-lock.sh}"
LOCK_D="${MAC_DIR}/LOCK.d"
USAGE_LOG="${MAC_DIR}/USAGE_LOG.md"
STALE_GRACE_MIN="${MAC_LOCK_STALE_GRACE_MIN:-10}"
cmd="${1:-}"
shift || true

mac_shared_lock_enabled() {
  case "${MAC_SHARED_LOCK:-}" in
    1|true|TRUE|yes|YES) return 0 ;;
    *) return 1 ;;
  esac
}

if ! mac_shared_lock_enabled; then
  echo "MAC_SHARED_LOCK unset/false — skipping mac lock (${cmd:-noop})"
  exit 0
fi

if [[ ! -d "$MAC_DIR" ]] && [[ ! -f "$SRC" ]]; then
  echo "mac-resources missing — skipping (ubuntu/github-hosted fallback)"
  exit 0
fi

tmp_root="${RUNNER_TEMP:-${TMPDIR:-/tmp}}"
COPY="${MAC_LOCK_COPY:-${tmp_root}/mac-lock-ci-copy.sh}"
if [[ -f "$SRC" ]] && { [[ -z "${MAC_LOCK_COPY:-}" ]] || [[ ! -f "$COPY" ]]; }; then
  cp "$SRC" "$COPY"
fi

now_cairo() { TZ=Africa/Cairo date '+%Y-%m-%d %H:%M'; }

epoch_now() { date +%s; }

file_mtime() {
  local path="$1"
  if [[ ! -e "$path" ]]; then
    echo 0
    return 0
  fi
  if stat -f %m "$path" >/dev/null 2>&1; then
    stat -f %m "$path"
  else
    stat -c %Y "$path"
  fi
}

# True if this step's parent process tree still looks like a live Actions job.
parent_job_alive() {
  if ! kill -0 "${PPID:-0}" 2>/dev/null; then
    echo "parent_job_alive: PPID ${PPID:-?} is dead" >&2
    return 1
  fi

  # Outside GHA (unit tests): PPID check is enough.
  if [[ -z "${GITHUB_ACTIONS:-}" ]]; then
    return 0
  fi

  local pid=$$
  local depth=0
  local saw_runner=0
  while [[ $depth -lt 24 ]]; do
    local pp cmd
    pp="$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ' || true)"
    [[ -n "$pp" && "$pp" =~ ^[0-9]+$ && "$pp" -gt 1 ]] || break
    if ! kill -0 "$pp" 2>/dev/null; then
      echo "parent_job_alive: ancestor pid $pp dead" >&2
      return 1
    fi
    cmd="$(ps -o command= -p "$pp" 2>/dev/null || true)"
    case "$cmd" in
      *Runner.Worker*|*Runner.Listener*|*actions-runner*)
        saw_runner=1
        ;;
    esac
    pid=$pp
    depth=$((depth + 1))
  done

  if [[ "$saw_runner" -eq 1 ]]; then
    return 0
  fi

  # Fallback: GITHUB_* still set and PPID alive (some runner builds rename the binary).
  if [[ -n "${GITHUB_RUN_ID:-}" && -n "${GITHUB_JOB:-}" ]]; then
    return 0
  fi
  echo "parent_job_alive: no Runner.Worker in PPID chain and GITHUB_* incomplete" >&2
  return 1
}

# Emit stale deadline epoch for this lock (0 if unknown / not stale-checkable).
lock_stale_after_epoch() {
  local deadline=0 eta=60 acquired=0 owner=""
  if [[ -f "${LOCK_D}/eta_deadline_epoch" ]]; then
    deadline="$(tr -d '[:space:]' <"${LOCK_D}/eta_deadline_epoch" 2>/dev/null || echo 0)"
    if [[ "$deadline" =~ ^[0-9]+$ ]] && [[ "$deadline" -gt 0 ]]; then
      echo "$((deadline + STALE_GRACE_MIN * 60))"
      return 0
    fi
  fi

  owner="$(cat "${LOCK_D}/owner" 2>/dev/null || true)"
  if printf '%s' "$owner" | grep -Eq 'eta=[0-9]+'; then
    eta="$(printf '%s' "$owner" | sed -nE 's/.*eta=([0-9]+) min.*/\1/p' | head -1)"
  fi
  [[ "$eta" =~ ^[0-9]+$ ]] || eta=60

  if [[ -f "${LOCK_D}/acquired_epoch" ]]; then
    acquired="$(tr -d '[:space:]' <"${LOCK_D}/acquired_epoch" 2>/dev/null || echo 0)"
  else
    acquired="$(file_mtime "${LOCK_D}/owner")"
    if [[ "$acquired" -eq 0 ]]; then
      acquired="$(file_mtime "$LOCK_D")"
    fi
  fi
  if [[ ! "$acquired" =~ ^[0-9]+$ ]] || [[ "$acquired" -le 0 ]]; then
    echo 0
    return 0
  fi
  echo "$((acquired + eta * 60 + STALE_GRACE_MIN * 60))"
}

# If LOCK.d is past eta+grace, remove it so the waiter can acquire.
# Returns 0 when lock was reclaimed (or already gone), 1 when still held fresh.
maybe_reclaim_stale_lock() {
  if [[ ! -d "$LOCK_D" ]]; then
    return 0
  fi
  local stale_after now owner
  stale_after="$(lock_stale_after_epoch)"
  now="$(epoch_now)"
  if [[ ! "$stale_after" =~ ^[0-9]+$ ]] || [[ "$stale_after" -le 0 ]]; then
    return 1
  fi
  if [[ "$now" -lt "$stale_after" ]]; then
    return 1
  fi
  owner="$(cat "${LOCK_D}/owner" 2>/dev/null || echo unknown)"
  echo "reclaiming stale Mac lock (past eta+${STALE_GRACE_MIN}m grace): ${owner}" >&2
  rm -rf "$LOCK_D"
  echo "$(now_cairo) Cairo | reclaim-stale | removed orphan LOCK.d (was: ${owner})" >>"$USAGE_LOG" 2>/dev/null || true
  return 0
}

release_if_owner() {
  local agent="$1"
  if [[ ! -d "$LOCK_D" ]]; then
    echo "lock free — nothing to release"
    return 0
  fi
  local owner
  owner="$(cat "${LOCK_D}/owner" 2>/dev/null || true)"
  if printf '%s\n' "$owner" | grep -Fq -- "$agent"; then
    rm -rf "$LOCK_D"
    echo "$(now_cairo) Cairo | $agent | released" >>"$USAGE_LOG" 2>/dev/null || true
    echo "released"
  else
    echo "lock not held by this agent (${agent}); status=${owner:-free} — skip release"
  fi
}

acquire_native() {
  local agent="$1" repo="$2" task="$3" eta="${4:-60}" maxw="${5:-120}"
  local waited=0 now
  mkdir -p "$MAC_DIR"

  until mkdir "$LOCK_D" 2>/dev/null; do
    if ! parent_job_alive; then
      echo "parent job gone while waiting — exit WITHOUT acquiring" >&2
      exit 1
    fi
    if maybe_reclaim_stale_lock; then
      # Stale removed — retry mkdir immediately.
      continue
    fi
    if [[ "$waited" -ge $((maxw * 60)) ]]; then
      echo "LOCK busy: $(cat "${LOCK_D}/owner" 2>/dev/null || echo unknown)" >&2
      exit 1
    fi
    if [[ $((waited % 300)) -eq 0 ]]; then
      echo "waiting for lock held by: $(cat "${LOCK_D}/owner" 2>/dev/null || echo unknown)"
    fi
    sleep 30
    waited=$((waited + 30))
  done

  now="$(epoch_now)"
  echo "agent=$agent | repo=$repo | task=$task | start=$(now_cairo) Cairo | eta=$eta min | pid=$$" >"${LOCK_D}/owner"
  echo "$now" >"${LOCK_D}/acquired_epoch"
  echo "$((now + eta * 60))" >"${LOCK_D}/eta_deadline_epoch"
  echo "$(now_cairo) Cairo | $agent | $repo | $task | start" >>"$USAGE_LOG" 2>/dev/null || true
  echo "acquired"

  if ! parent_job_alive; then
    echo "parent job gone immediately after acquire — releasing" >&2
    release_if_owner "$agent"
    exit 1
  fi
}

case "$cmd" in
  acquire)
    # Prefer native wait loop (parent-alive). Do not call live/copied acquire for the wait.
    acquire_native "$@"
    ;;
  release)
    agent="${1:-}"
    if [[ -z "$agent" ]]; then
      echo "usage: $0 release \"<agent>\"" >&2
      exit 2
    fi
    release_if_owner "$agent"
    ;;
  status)
    if [[ -d "$LOCK_D" ]]; then
      cat "${LOCK_D}/owner"
    else
      echo "free"
    fi
    ;;
  *)
    echo "usage: $0 acquire|release|status ..." >&2
    exit 2
    ;;
esac
