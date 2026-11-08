#!/usr/bin/env bash
# Static guard: every backend Cloud Run deploy in workflows must pin exactly one instance.
# Stopgap until shared storage lands (#37); remove/relax after that.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
fail=0
found=0

check_file() {
  local file="$1"
  [[ -f "$file" ]] || return 0

  # Strip YAML comments so commented examples do not satisfy (or confuse) the guard.
  local body
  body="$(sed -E 's/#.*$//' "$file")"

  if ! grep -qE 'gcloud[[:space:]]+run[[:space:]]+deploy' <<<"$body"; then
    return 0
  fi

  # Flatten line continuations so flags on following lines are visible per deploy invocation.
  local flat
  flat="$(printf '%s\n' "$body" | awk '
    {
      line=$0
      sub(/\\[[:space:]]*$/, "", line)
      printf "%s", line
      if ($0 ~ /\\[[:space:]]*$/) printf " "
      else print ""
    }
  ')"

  while IFS= read -r cmd; do
    [[ "$cmd" =~ gcloud[[:space:]]+run[[:space:]]+deploy ]] || continue
    found=$((found + 1))
    if ! grep -qE -- '--min-instances=1([^0-9]|$)' <<<"$cmd"; then
      echo "FAIL: $file: gcloud run deploy missing --min-instances=1" >&2
      fail=1
    fi
    if ! grep -qE -- '--max-instances=1([^0-9]|$)' <<<"$cmd"; then
      echo "FAIL: $file: gcloud run deploy missing --max-instances=1" >&2
      fail=1
    fi
    if grep -qE -- '--min-instances=([02-9]|[1-9][0-9]+)' <<<"$cmd"; then
      echo "FAIL: $file: gcloud run deploy has non-1 --min-instances (stopgap until #37)" >&2
      fail=1
    fi
    if grep -qE -- '--max-instances=([02-9]|[1-9][0-9]+)' <<<"$cmd"; then
      echo "FAIL: $file: gcloud run deploy has non-1 --max-instances (stopgap until #37)" >&2
      fail=1
    fi
  done <<<"$flat"
}

while IFS= read -r -d '' f; do
  check_file "$f"
done < <(find "$root/.github/workflows" -type f \( -name '*.yml' -o -name '*.yaml' \) -print0)

if [[ "$found" -lt 1 ]]; then
  echo "FAIL: no gcloud run deploy found under .github/workflows" >&2
  exit 1
fi

if [[ "$fail" -ne 0 ]]; then
  echo "Cloud Run one-instance pin violated. Keep --min-instances=1 --max-instances=1 until #37." >&2
  exit 1
fi

echo "OK: $found gcloud run deploy command(s) pin --min-instances=1 --max-instances=1"
