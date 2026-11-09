#!/usr/bin/env bash
# Smoke-check the Tashil Data Sharing production/staging web surface.
# Default baseURL: https://www.data.sw-point.com
# Default tenant path: /adeco
#
# READ-ONLY / NON-DESTRUCTIVE: only GET requests. No deletes, uploads,
# commits, password resets, or other mutating calls. Do not expand this
# script into write paths without Mohamed's explicit approval.
#
# Usage:
#   ./scripts/smoke_prod.sh
#   BASE_URL=https://www.data.sw-point.com TENANT_PATH=/adeco ./scripts/smoke_prod.sh
#   set -a && source scripts/smoke.env && set +a && ./scripts/smoke_prod.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -f "$ROOT/scripts/smoke.env" ]]; then
  # shellcheck disable=SC1091
  set -a && source "$ROOT/scripts/smoke.env" && set +a
fi

BASE_URL="${BASE_URL:-https://www.data.sw-point.com}"
BASE_URL="${BASE_URL%/}"
# Canonical Adeco tenant portal path on prod (leading slash, no trailing slash).
TENANT_PATH="${TENANT_PATH:-/adeco}"
TENANT_PATH="/${TENANT_PATH#/}"
TENANT_PATH="${TENANT_PATH%/}"
TIMEOUT="${SMOKE_TIMEOUT:-20}"
fail=0

check_get() {
  local path="$1"
  local expect="$2"
  local label="$3"
  local code
  code="$(curl -sS -o /tmp/tashil-smoke-body -w "%{http_code}" -L --max-time "$TIMEOUT" -X GET "${BASE_URL}${path}" || echo "000")"
  if [[ "$code" == "$expect" ]]; then
    echo "OK  HTTP $code  GET  $label  (${BASE_URL}${path})"
  else
    echo "FAIL expected HTTP $expect got $code  GET  $label  (${BASE_URL}${path})"
    fail=1
  fi
}

echo "Tashil smoke (read-only) → $BASE_URL  tenant=$TENANT_PATH"
check_get "/" "200" "web shell (index.html)"
check_get "${TENANT_PATH}" "200" "tenant portal shell (${TENANT_PATH})"
# Public readiness via hosting /api/** rewrite (not /livez — that misses the rewrite).
check_get "/api/v1/health" "200" "backend health via hosting rewrite"
check_get "/api/v1/version" "200" "backend version via hosting rewrite"
# Auth-gated route should reject anonymous callers (proves API wiring + JWT gate).
check_get "/api/v1/tenants" "401" "tenants requires JWT"

if [[ "$fail" -ne 0 ]]; then
  echo "Smoke FAILED"
  exit 1
fi
echo "Smoke PASSED (read-only)"
