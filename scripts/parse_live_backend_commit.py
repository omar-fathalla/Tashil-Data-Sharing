#!/usr/bin/env python3
"""Extract git_commit from a live /api/v1/version JSON body.

Always exits 0. Prints the commit on stdout when parseable; prints nothing when
the payload is empty, malformed, or missing git_commit so callers fail-safe to
redeploy (deploy=true).
"""

from __future__ import annotations

import json
import sys


def parse_live_backend_commit(raw: str) -> str:
    try:
        data = json.loads(raw or "{}")
    except Exception:
        return ""
    if not isinstance(data, dict):
        return ""
    commit = data.get("git_commit")
    if commit is None:
        return ""
    return str(commit).strip()


def main(argv: list[str]) -> int:
    if len(argv) > 1:
        raw = argv[1]
    else:
        raw = sys.stdin.read()
    commit = parse_live_backend_commit(raw)
    if commit:
        sys.stdout.write(commit)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
