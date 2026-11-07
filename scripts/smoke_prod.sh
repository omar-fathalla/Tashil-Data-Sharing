#!/usr/bin/env bash
# Smoke-check the Tashil Data Sharing production/staging web surface.
# Default baseURL: https://www.data.sw-point.com
#
# Usage:
#   ./scripts/smoke_prod.sh
#   BASE_URL=https://www.data.sw-point.com ./scripts/smoke_prod.sh
#   set -a && source scripts/smoke.env && set +a && ./scripts/smoke_prod.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -f "$ROOT/scripts/smoke.env" ]]; then
  # shellcheck disable=SC1091
  set -a && source "$ROOT/scripts/smoke.env" && set +a
fi

BASE_URL="${BASE_URL:-https://www.data.sw-point.com}"
BASE_URL="${BASE_URL%/}"
TIMEOUT="${SMOKE_TIMEOUT:-20}"
fail=0

check() {
  local path="$1"
  local expect="$2"
  local label="$3"
  local code
  code="$(curl -sS -o /tmp/tashil-smoke-body -w "%{http_code}" -L --max-time "$TIMEOUT" "${BASE_URL}${path}" || echo "000")"
  if [[ "$code" == "$expect" ]]; then
    echo "OK  HTTP $code  $label  (${BASE_URL}${path})"
  else
    echo "FAIL expected HTTP $expect got $code  $label  (${BASE_URL}${path})"
    fail=1
  fi
}

echo "Tashil smoke → $BASE_URL"
check "/" "200" "web shell (index.html)"
check "/api/v1/version" "200" "backend version via hosting rewrite"
# Auth-gated route should reject anonymous callers (proves API wiring + JWT gate).
check "/api/v1/tenants" "401" "tenants requires JWT"

if [[ "$fail" -ne 0 ]]; then
  echo "Smoke FAILED"
  exit 1
fi
echo "Smoke PASSED"
