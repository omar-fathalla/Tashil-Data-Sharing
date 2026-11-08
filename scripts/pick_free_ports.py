#!/usr/bin/env python3
"""Pick N distinct free TCP ports on 127.0.0.1 (never assume fixed ports).

Default range starts at 5600 so we stay clear of the other bot's Android
emulator band (5570–5580). Override with --min / --max.
"""

from __future__ import annotations

import argparse
import socket
import sys

# Other bot on the shared Mac uses 5570–5580 for emulators — never allocate there.
RESERVED_RANGES: list[tuple[int, int]] = [(5570, 5580)]
DEFAULT_MIN = 5600
DEFAULT_MAX = 5899


def _reserved(port: int) -> bool:
    for lo, hi in RESERVED_RANGES:
        if lo <= port <= hi:
            return True
    return False


def _bind(port: int) -> socket.socket | None:
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    try:
        s.bind(("127.0.0.1", port))
        return s
    except OSError:
        s.close()
        return None


def pick_many(n: int, min_port: int = DEFAULT_MIN, max_port: int = DEFAULT_MAX) -> list[int]:
    if n < 1:
        raise ValueError("n must be >= 1")
    if min_port > max_port:
        raise ValueError("min_port > max_port")

    ports: list[int] = []
    holders: list[socket.socket] = []
    try:
        for candidate in range(min_port, max_port + 1):
            if _reserved(candidate) or candidate in ports:
                continue
            sock = _bind(candidate)
            if sock is None:
                continue
            ports.append(candidate)
            holders.append(sock)
            if len(ports) >= n:
                break
        if len(ports) < n:
            raise RuntimeError(
                f"could only allocate {len(ports)}/{n} free ports in "
                f"[{min_port},{max_port}] excluding {RESERVED_RANGES}"
            )
    finally:
        for s in holders:
            try:
                s.close()
            except OSError:
                pass
    return ports


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("-n", type=int, default=1, help="number of distinct free ports")
    p.add_argument("--min", type=int, default=DEFAULT_MIN, dest="min_port")
    p.add_argument("--max", type=int, default=DEFAULT_MAX, dest="max_port")
    p.add_argument("--self-test", action="store_true", help="assert picks are free+distinct+in-range")
    args = p.parse_args()
    if args.self_test:
        a = pick_many(3, args.min_port, args.max_port)
        b = pick_many(3, args.min_port, args.max_port)
        assert len(set(a)) == 3, a
        assert len(set(b)) == 3, b
        for port in a + b:
            assert port >= args.min_port and port <= args.max_port, port
            assert not _reserved(port), port
            with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
                s.bind(("127.0.0.1", port))
        # Explicitly ensure reserved band is rejected by the helper logic.
        assert _reserved(5575)
        assert not _reserved(5600)
        print(f"self-test ok: batch_a={a} batch_b={b}")
        return 0
    ports = pick_many(max(1, args.n), args.min_port, args.max_port)
    print(" ".join(str(x) for x in ports))
    return 0


if __name__ == "__main__":
    sys.exit(main())
