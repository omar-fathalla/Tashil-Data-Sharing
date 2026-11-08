#!/usr/bin/env python3
"""Unit tests for parse_live_backend_commit fail-safe behavior."""

from __future__ import annotations

import unittest

from parse_live_backend_commit import parse_live_backend_commit


class ParseLiveBackendCommitTest(unittest.TestCase):
    def test_empty(self) -> None:
        self.assertEqual(parse_live_backend_commit(""), "")
        self.assertEqual(parse_live_backend_commit("{}"), "")

    def test_malformed(self) -> None:
        self.assertEqual(parse_live_backend_commit("{not-json"), "")
        self.assertEqual(parse_live_backend_commit("[]"), "")
        self.assertEqual(parse_live_backend_commit("null"), "")

    def test_unknown(self) -> None:
        self.assertEqual(parse_live_backend_commit('{"git_commit":"unknown"}'), "unknown")

    def test_valid(self) -> None:
        raw = '{"release":"x","git_commit":"abc123def","revision":"tashil-backend-00061-nw6"}'
        self.assertEqual(parse_live_backend_commit(raw), "abc123def")


if __name__ == "__main__":
    unittest.main()
