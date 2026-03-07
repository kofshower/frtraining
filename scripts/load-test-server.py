#!/usr/bin/env python3
from __future__ import annotations

import argparse
import asyncio
import statistics
import time
from typing import List, Tuple


def build_request(host: str, endpoint: str) -> bytes:
    return (
        f"GET {endpoint} HTTP/1.1\r\n"
        f"Host: {host}\r\n"
        "Connection: close\r\n"
        "Accept: application/json\r\n"
        "\r\n"
    ).encode("utf-8")


async def single_request(host: str, port: int, endpoint: str, timeout: float) -> Tuple[bool, float, str]:
    start = time.perf_counter()
    try:
        reader, writer = await asyncio.wait_for(asyncio.open_connection(host, port), timeout=timeout)
        writer.write(build_request(host, endpoint))
        await writer.drain()
        raw = await asyncio.wait_for(reader.read(-1), timeout=timeout)
        writer.close()
        try:
            await writer.wait_closed()
        except Exception:
            pass

        elapsed_ms = (time.perf_counter() - start) * 1000.0
        first_line = raw.split(b"\r\n", 1)[0].decode("iso-8859-1", errors="replace") if raw else ""
        ok = first_line.startswith("HTTP/1.1 200")
        return ok, elapsed_ms, first_line
    except Exception as exc:
        elapsed_ms = (time.perf_counter() - start) * 1000.0
        return False, elapsed_ms, str(exc)


async def run_load(host: str, port: int, endpoint: str, concurrency: int, requests: int, timeout: float) -> None:
    sem = asyncio.Semaphore(concurrency)
    latencies: List[float] = []
    failures: List[str] = []

    async def worker() -> None:
        async with sem:
            ok, latency, detail = await single_request(host, port, endpoint, timeout)
            latencies.append(latency)
            if not ok:
                failures.append(detail)

    start = time.perf_counter()
    await asyncio.gather(*(worker() for _ in range(requests)))
    total_sec = time.perf_counter() - start

    success = requests - len(failures)
    rps = success / total_sec if total_sec > 0 else 0.0
    p50 = statistics.median(latencies) if latencies else 0.0
    p95 = sorted(latencies)[int(len(latencies) * 0.95) - 1] if latencies else 0.0
    p99 = sorted(latencies)[int(len(latencies) * 0.99) - 1] if latencies else 0.0

    print(f"requests={requests} success={success} failed={len(failures)} total_sec={total_sec:.3f} rps={rps:.1f}")
    print(f"latency_ms p50={p50:.2f} p95={p95:.2f} p99={p99:.2f}")
    if failures:
        print("sample_failures:")
        for line in failures[:10]:
            print(f"- {line}")


def main() -> None:
    parser = argparse.ArgumentParser(description="Simple async HTTP load test for Fricu local backend")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8787)
    parser.add_argument("--endpoint", default="/health")
    parser.add_argument("--concurrency", type=int, default=1000)
    parser.add_argument("--requests", type=int, default=5000)
    parser.add_argument("--timeout", type=float, default=5.0)
    args = parser.parse_args()

    if args.concurrency <= 0 or args.requests <= 0:
        raise SystemExit("--concurrency and --requests must be > 0")

    asyncio.run(
        run_load(
            host=args.host,
            port=args.port,
            endpoint=args.endpoint,
            concurrency=args.concurrency,
            requests=args.requests,
            timeout=args.timeout,
        )
    )


if __name__ == "__main__":
    main()
