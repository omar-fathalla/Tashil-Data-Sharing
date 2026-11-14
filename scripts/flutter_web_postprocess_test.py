#!/usr/bin/env python3
import json
import tempfile
import unittest
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
from flutter_web_postprocess import postprocess


class PostprocessTest(unittest.TestCase):
    def test_stamps_version_copies_sw_and_strips_registration(self):
        with tempfile.TemporaryDirectory() as tmp:
            build = Path(tmp) / "web"
            build.mkdir()
            sw_src = Path(tmp) / "kill.js"
            sw_src.write_text("/*kill*/\nself.skipWaiting();\ncaches.delete;\nunregister;\n", encoding="utf-8")
            (build / "version.json").write_text('{"app_name":"tashil_web","version":"1.0.0"}', encoding="utf-8")
            (build / "index.html").write_text(
                '<html data-app-version="__TASHIL_APP_VERSION__"><body></body></html>',
                encoding="utf-8",
            )
            (build / "flutter_bootstrap.js").write_text(
                '_flutter.loader.load({\n  serviceWorkerSettings: {\n    serviceWorkerVersion: "123" /* dep */\n  }\n});\n',
                encoding="utf-8",
            )
            postprocess(build, "171", sw_src)
            self.assertIn("unregister", (build / "flutter_service_worker.js").read_text(encoding="utf-8"))
            self.assertIn("caches.delete", (build / "flutter_service_worker.js").read_text(encoding="utf-8"))
            ver = json.loads((build / "version.json").read_text(encoding="utf-8"))
            self.assertEqual(ver["app_version"], "171")
            self.assertEqual(ver["app_name"], "tashil_web")
            html = (build / "index.html").read_text(encoding="utf-8")
            self.assertIn('data-app-version="171"', html)
            self.assertNotIn("__TASHIL_APP_VERSION__", html)
            boot = (build / "flutter_bootstrap.js").read_text(encoding="utf-8")
            self.assertNotIn("serviceWorkerSettings", boot)
            self.assertIn("_flutter.loader.load({", boot)

    def test_rejects_non_numeric_version(self):
        with tempfile.TemporaryDirectory() as tmp:
            build = Path(tmp) / "web"
            build.mkdir()
            sw_src = Path(tmp) / "kill.js"
            sw_src.write_text("x", encoding="utf-8")
            with self.assertRaises(SystemExit):
                postprocess(build, "nope", sw_src)


if __name__ == "__main__":
    unittest.main()
