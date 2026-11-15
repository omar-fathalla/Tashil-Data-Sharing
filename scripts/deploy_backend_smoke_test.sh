#!/usr/bin/env bash
# Unit test for scripts/deploy_backend_smoke.sh (mock HTTP server; no network to prod).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SMOKE="${ROOT}/scripts/deploy_backend_smoke.sh"
chmod +x "$SMOKE"

py_server="$(mktemp)"
fake_curl_dir=""
cleanup() {
  if [[ -n "${SERVER_PID:-}" ]]; then
    kill "$SERVER_PID" 2>/dev/null || true
    wait "$SERVER_PID" 2>/dev/null || true
  fi
  rm -f "$py_server"
  if [[ -n "$fake_curl_dir" ]]; then
    rm -rf "$fake_curl_dir"
  fi
}
trap cleanup EXIT

# Args: mode=ok|bad_livez|bad_health|bad_version
cat >"$py_server" <<'PY'
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

mode = sys.argv[1] if len(sys.argv) > 1 else "ok"

class H(BaseHTTPRequestHandler):
    def do_GET(self):
        code = 200
        if self.path.startswith("/livez") and mode == "bad_livez":
            code = 503
        elif self.path.startswith("/api/v1/health") and mode == "bad_health":
            code = 500
        elif self.path.startswith("/api/v1/version") and mode == "bad_version":
            code = 404
        body = b'{"status":"healthy"}' if code == 200 else b'{"status":"unhealthy"}'
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *_args):
        return

HTTPServer(("127.0.0.1", int(sys.argv[2])), H).serve_forever()
PY

pick_port() {
  python3 - <<'PY'
import socket
s = socket.socket()
s.bind(("127.0.0.1", 0))
print(s.getsockname()[1])
s.close()
PY
}

run_case() {
  local mode="$1"
  local expect_ok="$2"
  local port
  port="$(pick_port)"
  python3 "$py_server" "$mode" "$port" &
  SERVER_PID=$!
  # Wait until accepting (no pipe-to-head; write code to a file).
  for _ in $(seq 1 50); do
    local probe_code_file
    probe_code_file="$(mktemp "${TMPDIR:-/tmp}/smoke-probe.XXXXXX")"
    set +e
    curl -sS --max-time 1 -o /dev/null -w "%{http_code}" \
      "http://127.0.0.1:${port}/api/v1/version" >"$probe_code_file" 2>/dev/null
    set -e
    if grep -qE '^[0-9]{3}$' "$probe_code_file" 2>/dev/null; then
      rm -f "$probe_code_file"
      break
    fi
    rm -f "$probe_code_file"
    sleep 0.05
  done

  export SMOKE_TIMEOUT=2 SMOKE_RETRIES=1 SMOKE_RETRY_DELAY=0
  set +e
  out="$("$SMOKE" "http://127.0.0.1:${port}" 2>&1)"
  rc=$?
  set -e
  kill "$SERVER_PID" 2>/dev/null || true
  wait "$SERVER_PID" 2>/dev/null || true
  SERVER_PID=

  if [[ "$expect_ok" == "1" ]]; then
    if [[ "$rc" -ne 0 ]]; then
      echo "FAIL mode=$mode expected success, rc=$rc out=$out" >&2
      exit 1
    fi
    echo "PASS mode=$mode (success)"
  else
    if [[ "$rc" -eq 0 ]]; then
      echo "FAIL mode=$mode expected failure, got success out=$out" >&2
      exit 1
    fi
    # Must report a clean 3-digit code, never a concatenated fallback like 200000.
    if echo "$out" | grep -qE 'got [0-9]{4,}'; then
      echo "FAIL mode=$mode concatenated/invalid HTTP code in out=$out" >&2
      exit 1
    fi
    echo "PASS mode=$mode (hard-fail rc=$rc)"
  fi
}

# Regression: curl prints a real %{http_code} then exits non-zero (macOS curl 23).
# Old pattern `code="$(curl … || echo 000)"` yielded "200000" and failed a healthy probe.
run_curl_exit_23_still_200() {
  fake_curl_dir="$(mktemp -d "${TMPDIR:-/tmp}/fake-curl.XXXXXX")"
  cat >"${fake_curl_dir}/curl" <<'EOS'
#!/usr/bin/env bash
# Minimal curl stand-in: honor -o <file>, emit 200 via -w path (stdout), exit 23.
out_file=""
args=("$@")
i=0
while [[ $i -lt ${#args[@]} ]]; do
  if [[ "${args[$i]}" == "-o" ]]; then
    i=$((i + 1))
    out_file="${args[$i]}"
  fi
  i=$((i + 1))
done
if [[ -n "$out_file" ]]; then
  printf '%s' '{"status":"healthy"}' >"$out_file"
fi
printf '%s' '200'
exit 23
EOS
  chmod +x "${fake_curl_dir}/curl"

  export SMOKE_TIMEOUT=2 SMOKE_RETRIES=0 SMOKE_RETRY_DELAY=0
  set +e
  out="$(PATH="${fake_curl_dir}:$PATH" "$SMOKE" "http://127.0.0.1:9" 2>&1)"
  rc=$?
  set -e
  rm -rf "$fake_curl_dir"
  fake_curl_dir=""

  if [[ "$rc" -ne 0 ]]; then
    echo "FAIL curl_exit_23 expected success (HTTP 200 captured), rc=$rc out=$out" >&2
    exit 1
  fi
  if echo "$out" | grep -q '200000'; then
    echo "FAIL curl_exit_23 concatenated code 200000 in out=$out" >&2
    exit 1
  fi
  echo "PASS curl_exit_23 (HTTP 200 kept; no 000 append)"
}

# Regression: empty/invalid code file must become 000 — not append onto garbage.
run_curl_transport_failure() {
  fake_curl_dir="$(mktemp -d "${TMPDIR:-/tmp}/fake-curl.XXXXXX")"
  cat >"${fake_curl_dir}/curl" <<'EOS'
#!/usr/bin/env bash
# No http_code on stdout; non-zero exit (connect failure).
exit 7
EOS
  chmod +x "${fake_curl_dir}/curl"

  export SMOKE_TIMEOUT=2 SMOKE_RETRIES=0 SMOKE_RETRY_DELAY=0
  set +e
  out="$(PATH="${fake_curl_dir}:$PATH" "$SMOKE" "http://127.0.0.1:9" 2>&1)"
  rc=$?
  set -e
  rm -rf "$fake_curl_dir"
  fake_curl_dir=""

  if [[ "$rc" -eq 0 ]]; then
    echo "FAIL curl_transport expected failure, got success out=$out" >&2
    exit 1
  fi
  if ! echo "$out" | grep -qE 'got 000'; then
    echo "FAIL curl_transport expected got 000, out=$out" >&2
    exit 1
  fi
  if echo "$out" | grep -qE 'got [0-9]{4,}'; then
    echo "FAIL curl_transport concatenated code in out=$out" >&2
    exit 1
  fi
  echo "PASS curl_transport (clean 000, no append)"
}

# Unit-level proof the old bash pattern concatenates (documents the bug we fixed).
run_old_pattern_documents_bug() {
  local code
  code="$(printf '%s' '200'; false || echo '000')"
  if [[ "$code" != "200000" ]]; then
    echo "FAIL old_pattern expected 200000 got [$code] (test harness broken?)" >&2
    exit 1
  fi
  echo "PASS old_pattern documents concat bug (200 + 000 → 200000)"
}

run_old_pattern_documents_bug
run_curl_exit_23_still_200
run_curl_transport_failure
run_case ok 1
run_case bad_livez 0
run_case bad_health 0
run_case bad_version 0
echo "deploy_backend_smoke_test: all cases passed"
