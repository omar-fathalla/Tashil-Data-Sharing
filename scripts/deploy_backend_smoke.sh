#!/usr/bin/env bash
# Post-deploy Cloud Run smoke: hard-fail unless every probe returns HTTP 200.
# Expects /livez + /api/v1/health from the public-livez health change (#53).
# /healthz is intentionally not used (Cloud Run ingress reserves it).
set -euo pipefail

BASE_URL="${1:-}"
if [[ -z "$BASE_URL" ]]; then
  echo "usage: $0 <cloud-run-service-url>" >&2
  exit 2
fi
BASE_URL="${BASE_URL%/}"

TIMEOUT="${SMOKE_TIMEOUT:-20}"
RETRIES="${SMOKE_RETRIES:-5}"
RETRY_DELAY="${SMOKE_RETRY_DELAY:-10}"

check_200() {
  local path="$1"
  local label="$2"
  local code
  # --fail-with-body exits non-zero on HTTP >=400; we also assert the code is exactly 200.
  code="$(curl -sS -o /tmp/tashil-deploy-smoke-body \
    -w "%{http_code}" \
    --connect-timeout "$TIMEOUT" \
    --max-time "$TIMEOUT" \
    --retry "$RETRIES" \
    --retry-delay "$RETRY_DELAY" \
    --retry-all-errors \
    "${BASE_URL}${path}" || echo "000")"
  if [[ "$code" != "200" ]]; then
    echo "FAIL expected HTTP 200 got ${code}  GET ${label}  (${BASE_URL}${path})" >&2
    if [[ -f /tmp/tashil-deploy-smoke-body ]]; then
      head -c 500 /tmp/tashil-deploy-smoke-body >&2 || true
      echo >&2
    fi
    exit 1
  fi
  echo "OK  HTTP 200  GET ${label}  (${BASE_URL}${path})"
}

echo "Deploy backend smoke → ${BASE_URL}"
check_200 "/api/v1/version" "version"
check_200 "/livez" "livez (Cloud Run-safe readiness)"
check_200 "/api/v1/health" "api health"
echo "Deploy backend smoke PASSED"
