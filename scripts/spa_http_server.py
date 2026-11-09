#!/usr/bin/env python3
"""Serve a static directory with SPA fallback (missing paths → index.html).

Used by Playwright smoke on self-hosted Mac runners. Avoids npx `serve`,
which has failed there with `ERROR invalid addKeywords parameters`.

Usage:
  python3 scripts/spa_http_server.py --root tashil_web/build/web --port 5600
"""

from __future__ import annotations

import argparse
import http.server
import os
import socketserver
import sys
from pathlib import Path


class SpaRequestHandler(http.server.SimpleHTTPRequestHandler):
    """SimpleHTTPRequestHandler that falls back to index.html for GETs."""

    def __init__(self, *args, directory: str | None = None, **kwargs):
        super().__init__(*args, directory=directory, **kwargs)

    def send_head(self):
        path = self.translate_path(self.path)
        # Absolute filesystem paths that exist (files or dirs with index) use
        # the default handler. Everything else gets SPA index.html so Flutter
        # path-URL routes like /adeco load the app shell.
        if os.path.isdir(path):
            for index in ("index.html", "index.htm"):
                index_path = os.path.join(path, index)
                if os.path.isfile(index_path):
                    return super().send_head()
            return self._send_spa_index()
        if os.path.isfile(path):
            return super().send_head()
        return self._send_spa_index()

    def _send_spa_index(self):
        index = Path(self.directory) / "index.html"
        if not index.is_file():
            self.send_error(404, "File not found")
            return None
        try:
            f = open(index, "rb")
        except OSError:
            self.send_error(404, "File not found")
            return None
        try:
            fs = os.fstat(f.fileno())
            self.send_response(200)
            self.send_header("Content-type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(fs.st_size))
            self.send_header("Last-Modified", self.date_time_string(fs.st_mtime))
            self.end_headers()
            return f
        except Exception:
            f.close()
            raise

    def log_message(self, format: str, *args) -> None:
        sys.stderr.write("%s - %s\n" % (self.address_string(), format % args))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--root",
        required=True,
        help="Directory to serve (Flutter web build output)",
    )
    parser.add_argument(
        "--port",
        type=int,
        required=True,
        help="TCP port to bind on 127.0.0.1",
    )
    parser.add_argument(
        "--bind",
        default="127.0.0.1",
        help="Bind address (default 127.0.0.1)",
    )
    args = parser.parse_args()

    root = Path(args.root).resolve()
    if not root.is_dir():
        print(f"error: root is not a directory: {root}", file=sys.stderr)
        return 1
    if not (root / "index.html").is_file():
        print(f"error: index.html missing under {root}", file=sys.stderr)
        return 1

    handler = lambda *a, **k: SpaRequestHandler(*a, directory=str(root), **k)
    socketserver.TCPServer.allow_reuse_address = True
    with socketserver.TCPServer((args.bind, args.port), handler) as httpd:
        print(f"spa_http_server serving {root} on http://{args.bind}:{args.port}/", flush=True)
        httpd.serve_forever()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
