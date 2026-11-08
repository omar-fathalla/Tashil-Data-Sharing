#!/usr/bin/env python3
"""Pick N distinct free TCP ports on 127.0.0.1 (never assume fixed ports)."""

from __future__ import annotations

import argparse
import socket
import sys


def pick_one() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        s.bind(("127.0.0.1", 0))
        return int(s.getsockname()[1])


def pick_many(n: int) -> list[int]:
    ports: list[int] = []
    # Hold sockets open until we have N distinct ports so the OS does not
    # hand back the same ephemeral port twice in a tight loop.
    holders: list[socket.socket] = []
    try:
        for _ in range(n):
            s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            s.bind(("127.0.0.1", 0))
            port = int(s.getsockname()[1])
            if port in ports:
                s.close()
                continue
            ports.append(port)
            holders.append(s)
            if len(ports) >= n:
                break
        # Retry until full (extremely unlikely to need many loops).
        while len(ports) < n:
            s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            s.bind(("127.0.0.1", 0))
            port = int(s.getsockname()[1])
            if port not in ports:
                ports.append(port)
                holders.append(s)
            else:
                s.close()
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
    p.add_argument("--self-test", action="store_true", help="assert two picks are free+distinct")
    args = p.parse_args()
    if args.self_test:
        a = pick_many(3)
        b = pick_many(3)
        assert len(set(a)) == 3, a
        assert len(set(b)) == 3, b
        # Concurrent-style: two batches should not collide while held — we
        # only check each batch is internally distinct (ports freed after).
        for port in a + b:
            with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
                # Port should be free again after holders closed.
                s.bind(("127.0.0.1", port))
        print(f"self-test ok: batch_a={a} batch_b={b}")
        return 0
    ports = pick_many(max(1, args.n))
    print(" ".join(str(x) for x in ports))
    return 0


if __name__ == "__main__":
    sys.exit(main())
