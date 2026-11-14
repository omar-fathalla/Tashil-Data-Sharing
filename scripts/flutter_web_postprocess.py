#!/usr/bin/env python3
"""Make a Flutter web build take over from a stale service worker.

Copies the kill-switch SW, writes app_version into version.json, stamps
index.html, and removes Flutter's serviceWorkerSettings so the new page
does not re-register a worker.
"""
from __future__ import annotations

import json
import re
import shutil
import sys
from pathlib import Path


def postprocess(build_web: Path, app_version: str, kill_switch: Path) -> None:
    if not build_web.is_dir():
        raise SystemExit(f"build dir missing: {build_web}")
    if not str(app_version).isdigit():
        raise SystemExit(f"APP_VERSION must be a number, got {app_version!r}")
    if not kill_switch.is_file():
        raise SystemExit(f"kill-switch SW missing: {kill_switch}")

    dest_sw = build_web / "flutter_service_worker.js"
    shutil.copyfile(kill_switch, dest_sw)

    version_path = build_web / "version.json"
    data = {}
    if version_path.is_file():
        try:
            data = json.loads(version_path.read_text(encoding="utf-8"))
            if not isinstance(data, dict):
                data = {}
        except json.JSONDecodeError:
            data = {}
    data["app_version"] = str(app_version)
    version_path.write_text(json.dumps(data, separators=(",", ":")), encoding="utf-8")

    index = build_web / "index.html"
    if index.is_file():
        html = index.read_text(encoding="utf-8")
        html = html.replace("__TASHIL_APP_VERSION__", str(app_version))
        index.write_text(html, encoding="utf-8")

    bootstrap = build_web / "flutter_bootstrap.js"
    if bootstrap.is_file():
        js = bootstrap.read_text(encoding="utf-8")
        js2, n = re.subn(
            r"\s*serviceWorkerSettings:\s*\{.*?\},?",
            "",
            js,
            count=1,
            flags=re.S,
        )
        if n:
            bootstrap.write_text(js2, encoding="utf-8")


def main(argv: list[str]) -> int:
    if len(argv) != 4:
        print("usage: flutter_web_postprocess.py <build/web> <APP_VERSION> <kill-switch.js>", file=sys.stderr)
        return 2
    postprocess(Path(argv[1]), argv[2], Path(argv[3]))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
