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

# Fetch URL into body_file; set CURL_HTTP_CODE to exactly one 3-digit code (000 on
# transport / parse failure) and CURL_HTTP_CODE_RC to curl's exit status.
# Never append a fallback onto a real code: `code="$(curl … || echo 000)"` becomes
# "200000" when curl writes %{http_code} then exits non-zero (e.g. macOS curl 23 write error).
# Uses a code file (not command-substitution pipe / head) so macOS and Linux agree.
curl_http_code() {
  local url="$1"
  local body_file="$2"
  local code_file raw

  code_file="$(mktemp "${TMPDIR:-/tmp}/tashil-deploy-smoke-code.XXXXXX")"
  # Write body to body_file; write %{http_code} to code_file (not a pipe to head).
  set +e
  curl -sS -o "$body_file" \
    -w "%{http_code}" \
    --connect-timeout "$TIMEOUT" \
    --max-time "$TIMEOUT" \
    --retry "$RETRIES" \
    --retry-delay "$RETRY_DELAY" \
    --retry-all-errors \
    "$url" >"$code_file"
  CURL_HTTP_CODE_RC=$?
  set -e

  raw="$(tr -d '[:space:]' <"$code_file" 2>/dev/null || true)"
  rm -f "$code_file"

  if [[ "$raw" =~ ^[0-9]{3}$ ]]; then
    CURL_HTTP_CODE="$raw"
  else
    CURL_HTTP_CODE="000"
  fi
}

check_200() {
  local path="$1"
  local label="$2"
  local body_file
  body_file="$(mktemp "${TMPDIR:-/tmp}/tashil-deploy-smoke-body.XXXXXX")"
  CURL_HTTP_CODE="000"
  CURL_HTTP_CODE_RC=0
  curl_http_code "${BASE_URL}${path}" "$body_file"
  if [[ "$CURL_HTTP_CODE" != "200" ]]; then
    echo "FAIL expected HTTP 200 got ${CURL_HTTP_CODE} (curl_rc=${CURL_HTTP_CODE_RC})  GET ${label}  (${BASE_URL}${path})" >&2
    if [[ -f "$body_file" ]]; then
      head -c 500 "$body_file" >&2 || true
      echo >&2
    fi
    rm -f "$body_file"
    exit 1
  fi
  rm -f "$body_file"
  echo "OK  HTTP 200  GET ${label}  (${BASE_URL}${path})"
}

echo "Deploy backend smoke → ${BASE_URL}"
check_200 "/api/v1/version" "version"
check_200 "/livez" "livez (Cloud Run-safe readiness)"
check_200 "/api/v1/health" "api health"
echo "Deploy backend smoke PASSED"
