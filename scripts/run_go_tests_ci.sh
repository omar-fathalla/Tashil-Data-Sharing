#!/bin/bash
# CI Go test runner for shared Mac / ubuntu fallback (bash 3.2+ / macOS OK).
#
# - Caps package parallelism (-p) and GOMAXPROCS (configurable).
# - Runs each package with its own -timeout (avoids one slow package killing
#   the whole `go test ./...` wall clock).
# - Emits go test -json and prints the slowest tests at the end.
#
# Env (all optional):
#   CI_GO_TEST_P                 max packages in parallel (default: 2 on Darwin/self-hosted)
#   CI_GO_TEST_GOMAXPROCS        GOMAXPROCS per package (default: same as -p)
#   CI_GO_TEST_PKG_TIMEOUT_MIN   per-package timeout minutes (default: 15)
set -euo pipefail

cd "$(dirname "$0")/../backend-go"

cores="$(sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo 4)"
uname_s="$(uname -s)"

if [ "$uname_s" = "Darwin" ] || [ "${RUNNER_ENVIRONMENT:-}" = "self-hosted" ]; then
  default_p=2
else
  default_p=4
fi

p="${CI_GO_TEST_P:-$default_p}"
if [ "$uname_s" = "Darwin" ] && [ "$p" -gt 3 ]; then
  p=3
fi
if [ "$p" -lt 1 ]; then p=1; fi

g="${CI_GO_TEST_GOMAXPROCS:-$p}"
pkg_timeout_min="${CI_GO_TEST_PKG_TIMEOUT_MIN:-15}"

echo "go test CI: -p=$p GOMAXPROCS=$g pkg_timeout=${pkg_timeout_min}m (cores=$cores)"

tmpdir="${RUNNER_TEMP:-${TMPDIR:-/tmp}}"
json_out="${tmpdir}/go-test-ci-$$.jsonl"
: >"$json_out"
export GO_TEST_CI_JSON_OUT="$json_out"
export GO_TEST_CI_GOMAXPROCS="$g"
export GO_TEST_CI_PKG_TIMEOUT_MIN="$pkg_timeout_min"

run_one() {
  pkg="$1"
  echo "=== BEGIN $pkg ==="
  # Intentionally allow go test failure to surface via xargs exit status.
  if ! GOMAXPROCS="$GO_TEST_CI_GOMAXPROCS" go test "$pkg" -count=1 \
      -timeout "${GO_TEST_CI_PKG_TIMEOUT_MIN}m" -json \
      | tee -a "$GO_TEST_CI_JSON_OUT"; then
    echo "FAIL package: $pkg" >&2
    return 1
  fi
  echo "=== END $pkg ==="
  return 0
}
export -f run_one

# xargs -P: parallel packages, each with its own timeout.
set +e
go list ./... | xargs -P "$p" -n1 -I{} bash -c 'run_one "$@"' _ {}
rc=$?
set -e

echo ""
echo "=== Slowest tests (from -json) ==="
python3 - "$json_out" <<'PY'
import json, sys
path = sys.argv[1]
rows = []
with open(path, encoding="utf-8", errors="replace") as f:
    for line in f:
        line = line.strip()
        if not line.startswith("{"):
            continue
        try:
            ev = json.loads(line)
        except json.JSONDecodeError:
            continue
        if ev.get("Action") == "pass" and ev.get("Test") and "Elapsed" in ev:
            rows.append((float(ev["Elapsed"]), ev.get("Package", ""), ev["Test"]))
rows.sort(reverse=True)
for elapsed, pkg, test in rows[:25]:
    print(f"{elapsed:8.3f}s  {pkg}  {test}")
if not rows:
    print("(no per-test timing events found)")
PY

exit "$rc"
