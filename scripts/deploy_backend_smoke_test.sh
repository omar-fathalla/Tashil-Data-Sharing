#!/usr/bin/env bash
# Unit test for scripts/deploy_backend_smoke.sh (mock HTTP server; no network to prod).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SMOKE="${ROOT}/scripts/deploy_backend_smoke.sh"
chmod +x "$SMOKE"

py_server="$(mktemp)"
cleanup() {
  if [[ -n "${SERVER_PID:-}" ]]; then
    kill "$SERVER_PID" 2>/dev/null || true
    wait "$SERVER_PID" 2>/dev/null || true
  fi
  rm -f "$py_server"
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
  # Wait until accepting
  for _ in $(seq 1 50); do
    if curl -fsS --max-time 1 "http://127.0.0.1:${port}/api/v1/version" >/dev/null 2>&1 \
      || [[ "$mode" == "bad_version" ]]; then
      # For bad_version, any response (incl 404) means server is up.
      if curl -sS --max-time 1 -o /dev/null -w "%{http_code}" "http://127.0.0.1:${port}/api/v1/version" | grep -qE '^[0-9]+$'; then
        break
      fi
    fi
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
    echo "PASS mode=$mode (hard-fail rc=$rc)"
  fi
}

run_case ok 1
run_case bad_livez 0
run_case bad_health 0
run_case bad_version 0
echo "deploy_backend_smoke_test: all cases passed"
