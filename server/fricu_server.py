#!/usr/bin/env python3
from __future__ import annotations

import argparse
import asyncio
import json
import os
import sqlite3
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, Optional, Tuple

MAX_HEADER_BYTES = 64 * 1024
MAX_BODY_BYTES = 50 * 1024 * 1024

STATUS_TEXT = {
    200: "OK",
    204: "No Content",
    400: "Bad Request",
    404: "Not Found",
    405: "Method Not Allowed",
    413: "Payload Too Large",
    500: "Internal Server Error",
    503: "Service Unavailable",
}


def iso_now() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def default_snapshot() -> Dict[str, Any]:
    return {
        "activities": [],
        "activityMetricInsights": [],
        "dailyMealPlans": [],
        "customFoods": [],
        "workouts": [],
        "calendarEvents": [],
        "profile": {},
        "updatedAt": iso_now(),
    }


def normalize_snapshot(data: Dict[str, Any]) -> Dict[str, Any]:
    base = default_snapshot()
    if not isinstance(data, dict):
        return base

    for key in (
        "activities",
        "activityMetricInsights",
        "dailyMealPlans",
        "customFoods",
        "workouts",
        "calendarEvents",
    ):
        value = data.get(key, [])
        base[key] = value if isinstance(value, list) else []

    profile = data.get("profile", {})
    base["profile"] = profile if isinstance(profile, dict) else {}

    updated_at = data.get("updatedAt")
    base["updatedAt"] = updated_at if isinstance(updated_at, str) and updated_at else iso_now()
    return base


def encode_json(payload: Dict[str, Any]) -> bytes:
    return json.dumps(payload, ensure_ascii=False, separators=(",", ":")).encode("utf-8")


class SQLiteSnapshotStore:
    def __init__(self, path: Path) -> None:
        self.path = path
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self._bootstrap()

    def load_snapshot(self) -> Dict[str, Any]:
        with self._connect() as conn:
            row = conn.execute(
                """
                SELECT
                  activities,
                  activity_metric_insights,
                  daily_meal_plans,
                  custom_foods,
                  workouts,
                  calendar_events,
                  profile,
                  updated_at
                FROM snapshot_store
                WHERE id = 1
                """
            ).fetchone()

        if row is None:
            self._bootstrap()
            return default_snapshot()

        snapshot = default_snapshot()
        snapshot["activities"] = self._decode_array(row["activities"])
        snapshot["activityMetricInsights"] = self._decode_array(row["activity_metric_insights"])
        snapshot["dailyMealPlans"] = self._decode_array(row["daily_meal_plans"])
        snapshot["customFoods"] = self._decode_array(row["custom_foods"])
        snapshot["workouts"] = self._decode_array(row["workouts"])
        snapshot["calendarEvents"] = self._decode_array(row["calendar_events"])
        snapshot["profile"] = self._decode_object(row["profile"])
        updated_at = row["updated_at"]
        snapshot["updatedAt"] = updated_at if isinstance(updated_at, str) and updated_at else iso_now()
        return snapshot

    def persist_snapshot(self, snapshot: Dict[str, Any]) -> None:
        normalized = normalize_snapshot(snapshot)
        with self._connect() as conn:
            conn.execute("BEGIN IMMEDIATE")
            conn.execute(
                """
                UPDATE snapshot_store
                SET
                  activities = ?,
                  activity_metric_insights = ?,
                  daily_meal_plans = ?,
                  custom_foods = ?,
                  workouts = ?,
                  calendar_events = ?,
                  profile = ?,
                  updated_at = ?
                WHERE id = 1
                """,
                (
                    self._to_json(normalized["activities"]),
                    self._to_json(normalized["activityMetricInsights"]),
                    self._to_json(normalized["dailyMealPlans"]),
                    self._to_json(normalized["customFoods"]),
                    self._to_json(normalized["workouts"]),
                    self._to_json(normalized["calendarEvents"]),
                    self._to_json(normalized["profile"]),
                    normalized["updatedAt"],
                ),
            )
            conn.execute("COMMIT")

    def _bootstrap(self) -> None:
        with self._connect() as conn:
            conn.execute(
                """
                CREATE TABLE IF NOT EXISTS snapshot_store (
                  id INTEGER PRIMARY KEY CHECK (id = 1),
                  activities TEXT NOT NULL,
                  activity_metric_insights TEXT NOT NULL,
                  daily_meal_plans TEXT NOT NULL,
                  custom_foods TEXT NOT NULL,
                  workouts TEXT NOT NULL,
                  calendar_events TEXT NOT NULL,
                  profile TEXT NOT NULL,
                  updated_at TEXT NOT NULL
                )
                """
            )

            seed = default_snapshot()
            conn.execute(
                """
                INSERT OR IGNORE INTO snapshot_store (
                  id,
                  activities,
                  activity_metric_insights,
                  daily_meal_plans,
                  custom_foods,
                  workouts,
                  calendar_events,
                  profile,
                  updated_at
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    1,
                    self._to_json(seed["activities"]),
                    self._to_json(seed["activityMetricInsights"]),
                    self._to_json(seed["dailyMealPlans"]),
                    self._to_json(seed["customFoods"]),
                    self._to_json(seed["workouts"]),
                    self._to_json(seed["calendarEvents"]),
                    self._to_json(seed["profile"]),
                    seed["updatedAt"],
                ),
            )

    def _connect(self) -> sqlite3.Connection:
        conn = sqlite3.connect(self.path, timeout=8.0, check_same_thread=False, isolation_level=None)
        conn.row_factory = sqlite3.Row
        conn.execute("PRAGMA journal_mode = WAL")
        conn.execute("PRAGMA synchronous = NORMAL")
        conn.execute("PRAGMA temp_store = MEMORY")
        conn.execute("PRAGMA busy_timeout = 8000")
        return conn

    @staticmethod
    def _to_json(value: Any) -> str:
        return json.dumps(value, ensure_ascii=False, separators=(",", ":"))

    @staticmethod
    def _decode_array(raw: str) -> list[Any]:
        try:
            value = json.loads(raw)
            return value if isinstance(value, list) else []
        except Exception:
            return []

    @staticmethod
    def _decode_object(raw: str) -> Dict[str, Any]:
        try:
            value = json.loads(raw)
            return value if isinstance(value, dict) else {}
        except Exception:
            return {}


@dataclass
class HTTPRequest:
    method: str
    path: str
    body: bytes


class SnapshotState:
    def __init__(
        self,
        initial_snapshot: Dict[str, Any],
        store: SQLiteSnapshotStore,
        write_ack_mode: str,
        queue_max_size: int,
        write_timeout_sec: float,
    ) -> None:
        self.store = store
        self.write_ack_mode = write_ack_mode
        self.write_timeout_sec = write_timeout_sec
        self.snapshot = normalize_snapshot(initial_snapshot)
        self.snapshot_bytes = encode_json(self.snapshot)
        self.write_queue: asyncio.Queue[Tuple[Dict[str, Any], Optional[asyncio.Future[Any]]]] = asyncio.Queue(
            maxsize=queue_max_size
        )
        self._writer_task: Optional[asyncio.Task[Any]] = None

    async def start(self) -> None:
        self._writer_task = asyncio.create_task(self._writer_loop(), name="fricu-db-writer")

    async def stop(self) -> None:
        if self._writer_task is None:
            return
        await self.write_queue.put(({}, None))
        await self._writer_task

    async def current_snapshot_bytes(self) -> bytes:
        return self.snapshot_bytes

    async def update_snapshot(self, payload: Dict[str, Any]) -> Dict[str, Any]:
        normalized = normalize_snapshot(payload)
        normalized["updatedAt"] = iso_now()
        self.snapshot = normalized
        self.snapshot_bytes = encode_json(normalized)

        if self.write_ack_mode == "durable":
            fut: asyncio.Future[Any] = asyncio.get_running_loop().create_future()
            await self.write_queue.put((normalized, fut))
            try:
                await asyncio.wait_for(fut, timeout=self.write_timeout_sec)
            except asyncio.TimeoutError as exc:
                raise TimeoutError("database persistence timeout") from exc
        else:
            try:
                self.write_queue.put_nowait((normalized, None))
            except asyncio.QueueFull:
                # For snapshot semantics, keeping the newest payload is more useful than preserving stale writes.
                try:
                    dropped, dropped_fut = self.write_queue.get_nowait()
                    _ = dropped
                    if dropped_fut is not None and not dropped_fut.done():
                        dropped_fut.set_result(None)
                except asyncio.QueueEmpty:
                    pass
                try:
                    self.write_queue.put_nowait((normalized, None))
                except asyncio.QueueFull as exc:
                    raise TimeoutError("write queue full") from exc

        return normalized

    async def _writer_loop(self) -> None:
        while True:
            payload, future = await self.write_queue.get()
            if not payload and future is None:
                break
            try:
                await asyncio.to_thread(self.store.persist_snapshot, payload)
                if future is not None and not future.done():
                    future.set_result(None)
            except Exception as exc:
                if future is not None and not future.done():
                    future.set_exception(exc)


async def parse_request(reader: asyncio.StreamReader) -> Optional[HTTPRequest]:
    try:
        raw_header = await reader.readuntil(b"\r\n\r\n")
    except asyncio.IncompleteReadError:
        return None
    except asyncio.LimitOverrunError as exc:
        raise ValueError(f"header too large: {exc}")

    if len(raw_header) > MAX_HEADER_BYTES:
        raise ValueError("header too large")

    header_text = raw_header.decode("iso-8859-1")
    lines = header_text.split("\r\n")
    request_line = lines[0].strip()
    if not request_line:
        return None

    parts = request_line.split(" ")
    if len(parts) < 2:
        raise ValueError("invalid request line")

    method = parts[0].upper()
    target = parts[1]
    path = target.split("?", 1)[0]

    headers: Dict[str, str] = {}
    for line in lines[1:]:
        if not line:
            continue
        if ":" not in line:
            continue
        key, value = line.split(":", 1)
        headers[key.strip().lower()] = value.strip()

    body = b""
    content_length_raw = headers.get("content-length")
    if content_length_raw:
        try:
            content_length = int(content_length_raw)
        except ValueError as exc:
            raise ValueError("invalid content-length") from exc
        if content_length < 0:
            raise ValueError("invalid content-length")
        if content_length > MAX_BODY_BYTES:
            raise OverflowError("payload too large")
        if content_length > 0:
            body = await reader.readexactly(content_length)

    return HTTPRequest(method=method, path=path, body=body)


def json_error_body(message: str) -> bytes:
    return encode_json({"error": message})


async def write_response(
    writer: asyncio.StreamWriter,
    status_code: int,
    body: bytes,
    content_type: str = "application/json; charset=utf-8",
) -> None:
    reason = STATUS_TEXT.get(status_code, "OK")
    status_line = f"HTTP/1.1 {status_code} {reason}\r\n"

    headers = [
        status_line,
        f"Content-Type: {content_type}\r\n",
        f"Content-Length: {len(body)}\r\n",
        "Access-Control-Allow-Origin: *\r\n",
        "Access-Control-Allow-Methods: GET, PUT, OPTIONS\r\n",
        "Access-Control-Allow-Headers: Content-Type\r\n",
        "Connection: close\r\n",
        "\r\n",
    ]
    writer.write("".join(headers).encode("utf-8"))
    if body:
        writer.write(body)
    await writer.drain()


async def handle_client(
    reader: asyncio.StreamReader,
    writer: asyncio.StreamWriter,
    state: SnapshotState,
) -> None:
    try:
        request = await parse_request(reader)
        if request is None:
            await write_response(writer, 400, json_error_body("Empty request"))
            return

        if request.method == "OPTIONS":
            await write_response(writer, 204, b"", content_type="text/plain; charset=utf-8")
            return

        if request.method == "GET" and request.path == "/health":
            health = {
                "status": "ok",
                "updatedAt": iso_now(),
                "writeAckMode": state.write_ack_mode,
                "pendingWriteQueue": state.write_queue.qsize(),
            }
            await write_response(writer, 200, encode_json(health))
            return

        if request.method == "GET" and request.path == "/v1/snapshot":
            payload = await state.current_snapshot_bytes()
            await write_response(writer, 200, payload)
            return

        if request.method == "PUT" and request.path == "/v1/snapshot":
            if not request.body:
                await write_response(writer, 400, json_error_body("Invalid request body size"))
                return
            try:
                decoded = json.loads(request.body.decode("utf-8"))
            except Exception as exc:
                await write_response(writer, 400, json_error_body(f"Invalid JSON body: {exc}"))
                return
            if not isinstance(decoded, dict):
                await write_response(writer, 400, json_error_body("Body must be a JSON object"))
                return

            try:
                updated = await state.update_snapshot(decoded)
            except TimeoutError as exc:
                await write_response(writer, 503, json_error_body(str(exc)))
                return
            except Exception as exc:
                await write_response(writer, 500, json_error_body(f"Persistence failed: {exc}"))
                return

            await write_response(writer, 200, encode_json(updated))
            return

        if request.method not in ("GET", "PUT", "OPTIONS"):
            await write_response(writer, 405, json_error_body("Method not allowed"))
            return

        await write_response(writer, 404, json_error_body("Not found"))

    except OverflowError:
        await write_response(writer, 413, json_error_body("Invalid request body size"))
    except ValueError as exc:
        await write_response(writer, 400, json_error_body(str(exc)))
    except Exception as exc:
        await write_response(writer, 500, json_error_body(f"Unhandled server error: {exc}"))
    finally:
        writer.close()
        try:
            await writer.wait_closed()
        except Exception:
            pass


async def run_server(args: argparse.Namespace) -> None:
    store = SQLiteSnapshotStore(Path(args.db_file))
    initial = await asyncio.to_thread(store.load_snapshot)

    state = SnapshotState(
        initial_snapshot=initial,
        store=store,
        write_ack_mode=args.write_ack_mode,
        queue_max_size=args.write_queue_max,
        write_timeout_sec=args.write_timeout_sec,
    )
    await state.start()

    server = await asyncio.start_server(
        lambda r, w: handle_client(r, w, state),
        host=args.host,
        port=args.port,
        backlog=args.backlog,
        limit=max(MAX_HEADER_BYTES * 2, 128 * 1024),
    )

    print(f"Fricu async server listening on http://{args.host}:{args.port}")
    print(f"SQLite DB: {Path(args.db_file).resolve()}")
    print(f"Write ack mode: {args.write_ack_mode}")
    print(f"Write queue max: {args.write_queue_max}")
    print(f"Socket backlog: {args.backlog}")

    try:
        async with server:
            await server.serve_forever()
    finally:
        await state.stop()


def main() -> None:
    parser = argparse.ArgumentParser(description="Fricu async local backend server")
    parser.add_argument("--host", default=os.environ.get("FRICU_SERVER_HOST", "127.0.0.1"))
    parser.add_argument("--port", type=int, default=int(os.environ.get("FRICU_SERVER_PORT", "8787")))
    parser.add_argument(
        "--db-file",
        default=os.environ.get(
            "FRICU_SERVER_DB_FILE",
            os.environ.get("FRICU_SERVER_DATA_FILE", str(Path(__file__).resolve().parent / "data" / "fricu.db")),
        ),
    )
    parser.add_argument(
        "--write-ack-mode",
        choices=["eventual", "durable"],
        default=os.environ.get("FRICU_SERVER_WRITE_ACK_MODE", "eventual"),
        help="eventual = prioritize throughput, durable = wait for SQLite commit",
    )
    parser.add_argument(
        "--write-queue-max",
        type=int,
        default=int(os.environ.get("FRICU_SERVER_WRITE_QUEUE_MAX", "4096")),
    )
    parser.add_argument(
        "--write-timeout-sec",
        type=float,
        default=float(os.environ.get("FRICU_SERVER_WRITE_TIMEOUT_SEC", "6")),
    )
    parser.add_argument(
        "--backlog",
        type=int,
        default=int(os.environ.get("FRICU_SERVER_BACKLOG", "8192")),
    )
    args = parser.parse_args()

    if args.write_queue_max <= 0:
        raise SystemExit("--write-queue-max must be > 0")
    if args.backlog <= 0:
        raise SystemExit("--backlog must be > 0")

    try:
        asyncio.run(run_server(args))
    except KeyboardInterrupt:
        print("\nShutting down Fricu server...")


if __name__ == "__main__":
    main()
