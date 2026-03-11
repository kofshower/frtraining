#!/usr/bin/env python3
from __future__ import annotations

import argparse
import asyncio
import json
import os
import sqlite3
import sys
import time
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Optional

MAX_HEADER_BYTES = 64 * 1024
MAX_BODY_BYTES = 64 * 1024 * 1024
DEFAULT_RC_LOCKED = 5
DEFAULT_EXT_LOCKED = 5

LIST_KEYS = {
    "activities",
    "activity_metric_insights",
    "meal_plans",
    "custom_foods",
    "workouts",
    "events",
    "wellness_samples",
    "lactate_history_records",
}
OBJECT_KEYS = {"profile", "app_settings"}

STATUS_TEXT = {
    200: "OK",
    202: "Accepted",
    204: "No Content",
    400: "Bad Request",
    401: "Unauthorized",
    404: "Not Found",
    405: "Method Not Allowed",
    413: "Payload Too Large",
    500: "Internal Server Error",
}


def log(level: str, message: str) -> None:
    ts = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    print(f"[{ts}] [{level}] {message}", file=sys.stderr, flush=True)



def log_info(message: str) -> None:
    log("INFO", message)



def log_warn(message: str) -> None:
    log("WARN", message)



def log_error(message: str) -> None:
    log("ERROR", message)



def sanitize_log_id(value: str | None) -> str:
    if not value:
        return ""
    return "".join(ch for ch in value if ch.isalnum() or ch in "-_ .:").replace(" ", "")[:96]



def sanitize_log_id_for_filename(value: str | None) -> str:
    if not value:
        return ""
    chars = []
    for ch in value:
        chars.append(ch if (ch.isalnum() or ch in "-_") else "_")
    return "".join(chars)[:96]



def sanitize_account_id(value: str | None) -> str:
    if not value:
        return ""
    return "".join(ch for ch in value if ch.isalnum() or ch in "-_.")[:128]



def is_valid_key(key: str) -> bool:
    return key in LIST_KEYS or key in OBJECT_KEYS or key.startswith("exported_file_") and len(key) > len("exported_file_")



def default_payload_for_key(key: str) -> str:
    return "{}" if key in OBJECT_KEYS or key.startswith("exported_file_") else "[]"



def build_storage_key(account_id: str, logical_key: str) -> str:
    if not account_id or not logical_key:
        raise ValueError("invalid account key")
    return f"{account_id}::{logical_key}"



def json_error(message: str) -> bytes:
    return json.dumps({"error": message}, ensure_ascii=False, separators=(",", ":")).encode("utf-8")



def sqlite_error_code(exc: BaseException, fallback: int) -> int:
    return int(getattr(exc, "sqlite_errorcode", fallback) or fallback)



def sqlite_error_name(exc: BaseException) -> str:
    return str(getattr(exc, "sqlite_errorname", "unknown"))


@dataclass
class RequestContext:
    log_id: str
    account_id: str
    retry_attempt: int = 0


@dataclass
class HTTPRequest:
    method: str
    path: str
    headers: dict[str, str]
    body: bytes


class SQLiteKVStore:
    def __init__(self, db_path: Path, state_dir: Path) -> None:
        self.db_path = db_path
        self.state_dir = state_dir
        self.pending_dir = state_dir / "pending_writes"
        self.failed_dir = state_dir / "failed_writes"
        self.db_path.parent.mkdir(parents=True, exist_ok=True)
        self.pending_dir.mkdir(parents=True, exist_ok=True)
        self.failed_dir.mkdir(parents=True, exist_ok=True)
        self._bootstrap()
        self._replay_pending_writes()

    def _connect(self) -> sqlite3.Connection:
        conn = sqlite3.connect(self.db_path, timeout=5.0, check_same_thread=False, isolation_level=None)
        conn.row_factory = sqlite3.Row
        conn.execute("PRAGMA journal_mode=WAL")
        conn.execute("PRAGMA synchronous=FULL")
        conn.execute("PRAGMA fullfsync=ON")
        conn.execute("PRAGMA checkpoint_fullfsync=ON")
        conn.execute("PRAGMA temp_store=MEMORY")
        conn.execute("PRAGMA mmap_size=268435456")
        conn.execute("PRAGMA cache_size=-32768")
        conn.execute("PRAGMA busy_timeout=5000")
        return conn

    def _bootstrap(self) -> None:
        with self._connect() as conn:
            conn.execute(
                """
                CREATE TABLE IF NOT EXISTS kv_store (
                    data_key TEXT PRIMARY KEY,
                    data_value TEXT NOT NULL,
                    updated_at INTEGER NOT NULL
                )
                """
            )

    def get(self, storage_key: str) -> Optional[str]:
        with self._connect() as conn:
            row = conn.execute("SELECT data_value FROM kv_store WHERE data_key = ?", (storage_key,)).fetchone()
            if row is None:
                return None
            return str(row[0])

    def put(
        self,
        storage_key: str,
        payload: str,
        retry_attempt: int = 0,
        *,
        logical_key: str = "-",
        account_id: str = "-",
        log_id: str = "-",
    ) -> tuple[str, int, int]:
        attempt_used = retry_attempt
        with self._connect() as conn:
            for attempt in range(0, 9):
                attempt_used = attempt
                try:
                    conn.execute(
                        """
                        INSERT INTO kv_store (data_key, data_value, updated_at)
                        VALUES (?, ?, strftime('%s', 'now'))
                        ON CONFLICT(data_key) DO UPDATE
                        SET data_value = excluded.data_value,
                            updated_at = excluded.updated_at
                        """,
                        (storage_key, payload),
                    )
                    return "stored", attempt_used, 0
                except sqlite3.OperationalError as exc:
                    message = str(exc).lower()
                    if ("locked" in message or "busy" in message) and attempt < 8:
                        log_warn(
                            f"DATA WRITE retrying key={logical_key} account={account_id} logid={log_id} "
                            f"attempt={attempt + 1} rc={sqlite_error_code(exc, DEFAULT_RC_LOCKED)} bytes={len(payload.encode('utf-8'))}"
                        )
                        time.sleep(0.002 * (attempt + 1))
                        continue
                    raise

    def _replay_pending_writes(self) -> None:
        for pending_file in sorted(self.pending_dir.glob("*.json")):
            extracted = self._extract_pending_key_from_name(pending_file.name)
            if extracted is None:
                continue
            storage_key, log_id = extracted
            log_info(f"DATA WRITE replaying key={storage_key} pending={pending_file} logid={log_id or '-'}")
            payload = pending_file.read_text(encoding="utf-8")
            try:
                self.put(storage_key, payload)
                pending_file.unlink()
                log_info(f"DATA WRITE replayed key={storage_key} status=stored pending={pending_file} logid={log_id or '-'}")
            except Exception as exc:
                raise RuntimeError(f"failed to replay pending write {pending_file}: {exc}") from exc

    def create_pending_write(self, storage_key: str, payload: str, log_id: str) -> Path:
        now_ns = time.time_ns()
        pid = os.getpid()
        file_log_id = sanitize_log_id_for_filename(log_id) or "none"
        filename = f"{storage_key}-{pid}-{now_ns // 1_000_000_000}-{now_ns % 1_000_000_000}-lid-{file_log_id}.json"
        target = self.pending_dir / filename
        tmp = self.pending_dir / (filename + ".tmp")
        tmp.write_text(payload, encoding="utf-8")
        os.replace(tmp, target)
        return target

    def remove_pending_write(self, path: Path) -> None:
        path.unlink()

    def persist_failed_payload(self, logical_key: str, payload: str, rc: int, ext: int) -> Path:
        now_ns = time.time_ns()
        filename = f"{logical_key}-{os.getpid()}-{now_ns % 1_000_000_000}-rc{rc}-ext{ext}.json"
        target = self.failed_dir / filename
        target.write_text(payload, encoding="utf-8")
        return target

    @staticmethod
    def _extract_pending_key_from_name(name: str) -> tuple[str, str] | None:
        if not name.endswith(".json"):
            return None
        stem = name[:-5]
        log_id = ""
        if "-lid-" in stem:
            stem, log_id = stem.split("-lid-", 1)
        parts = stem.rsplit("-", 3)
        if len(parts) != 4:
            return None
        storage_key, _, _, _ = parts
        if "::" not in storage_key:
            return None
        account_id, logical_key = storage_key.split("::", 1)
        if not sanitize_account_id(account_id) or not is_valid_key(logical_key):
            return None
        return storage_key, log_id


class FricuPythonServer:
    def __init__(self, db_path: Path, state_dir: Path) -> None:
        self.store = SQLiteKVStore(db_path=db_path, state_dir=state_dir)

    async def handle_client(self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter) -> None:
        request: HTTPRequest | None = None
        ctx = RequestContext(log_id=self.generate_server_log_id(), account_id="", retry_attempt=0)
        status_code = 500
        payload_bytes = 0
        try:
            request = await self.parse_request(reader)
            if request is None:
                status_code = 400
                await self.write_response(writer, status_code, json_error("empty request"), ctx)
                return

            ctx = self.build_context(request.headers)
            payload_bytes = len(request.body)

            if request.method == "OPTIONS":
                status_code = 204
                await self.write_response(writer, status_code, b"", ctx, content_type="text/plain; charset=utf-8")
                return

            if request.method == "GET" and request.path == "/health":
                status_code = 200
                await self.write_response(writer, status_code, b'{"status":"ok"}', ctx)
                return

            prefix = "/v1/data/"
            if not request.path.startswith(prefix):
                status_code = 404
                await self.write_response(writer, status_code, json_error("not found"), ctx)
                return

            logical_key = request.path[len(prefix):]
            if not is_valid_key(logical_key):
                status_code = 404
                await self.write_response(writer, status_code, json_error("unknown key"), ctx)
                return

            if not ctx.account_id:
                status_code = 401
                await self.write_response(writer, status_code, json_error("missing X-Account-Id"), ctx)
                return

            if request.method == "GET":
                status_code = await self.handle_get(writer, logical_key, ctx)
                return

            if request.method == "PUT":
                status_code = await self.handle_put(writer, logical_key, request.body, ctx)
                return

            status_code = 405
            await self.write_response(writer, status_code, json_error("method not allowed"), ctx)
        except OverflowError:
            status_code = 413
            await self.write_response(writer, status_code, json_error("invalid request body size"), ctx)
        except ValueError as exc:
            status_code = 400
            await self.write_response(writer, status_code, json_error(str(exc)), ctx)
        except Exception as exc:
            status_code = 500
            await self.write_response(writer, status_code, json_error(f"unhandled server error: {exc}"), ctx)
            log_error(f"Unhandled server error: {exc}")
        finally:
            method = request.method if request else "UNKNOWN"
            path = request.path if request else "/"
            self.log_http_request(method, path, status_code, payload_bytes, ctx)
            writer.close()
            try:
                await writer.wait_closed()
            except Exception:
                pass

    async def parse_request(self, reader: asyncio.StreamReader) -> HTTPRequest | None:
        try:
            raw_header = await reader.readuntil(b"\r\n\r\n")
        except asyncio.IncompleteReadError:
            return None
        except asyncio.LimitOverrunError as exc:
            raise ValueError(f"header too large: {exc}") from exc

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
        path = parts[1].split("?", 1)[0]
        headers: dict[str, str] = {}
        for line in lines[1:]:
            if not line or ":" not in line:
                continue
            key, value = line.split(":", 1)
            headers[key.strip().lower()] = value.strip()

        body = b""
        raw_length = headers.get("content-length")
        if raw_length:
            try:
                content_length = int(raw_length)
            except ValueError as exc:
                raise ValueError("invalid content-length") from exc
            if content_length < 0:
                raise ValueError("invalid content-length")
            if content_length > MAX_BODY_BYTES:
                raise OverflowError("payload too large")
            if content_length > 0:
                body = await reader.readexactly(content_length)

        return HTTPRequest(method=method, path=path, headers=headers, body=body)

    def build_context(self, headers: dict[str, str]) -> RequestContext:
        log_id = sanitize_log_id(headers.get("x-log-id")) or self.generate_server_log_id()
        account_id = sanitize_account_id(headers.get("x-account-id"))
        retry_attempt = 0
        raw_retry = headers.get("x-retry-attempt")
        if raw_retry:
            try:
                retry_attempt = max(0, min(int(raw_retry), 100000))
            except ValueError:
                retry_attempt = 0
        return RequestContext(log_id=log_id, account_id=account_id, retry_attempt=retry_attempt)

    async def handle_get(self, writer: asyncio.StreamWriter, logical_key: str, ctx: RequestContext) -> int:
        storage_key = build_storage_key(ctx.account_id, logical_key)
        value = self.store.get(storage_key)
        if value is None:
            value = default_payload_for_key(logical_key)
            log_info(f"DATA READ key={logical_key} source=default account={ctx.account_id} logid={ctx.log_id}")
        else:
            log_info(f"DATA READ key={logical_key} source=db account={ctx.account_id} logid={ctx.log_id}")
        await self.write_response(writer, 200, value.encode("utf-8"), ctx)
        return 200

    async def handle_put(self, writer: asyncio.StreamWriter, logical_key: str, body: bytes, ctx: RequestContext) -> int:
        payload = body.decode("utf-8")
        try:
            json.loads(payload)
        except Exception:
            await self.write_response(writer, 400, json_error("invalid json payload"), ctx)
            log_warn(f"DATA WRITE rejected key={logical_key} reason=invalid_json bytes={len(body)} logid={ctx.log_id}")
            return 400

        storage_key = build_storage_key(ctx.account_id, logical_key)
        pending_path = self.store.create_pending_write(storage_key, payload, ctx.log_id)

        try:
            _, retries, _ = self.store.put(
                storage_key,
                payload,
                retry_attempt=ctx.retry_attempt,
                logical_key=logical_key,
                account_id=ctx.account_id,
                log_id=ctx.log_id,
            )
        except sqlite3.OperationalError as exc:
            rc = sqlite_error_code(exc, DEFAULT_RC_LOCKED)
            ext = sqlite_error_code(exc, DEFAULT_EXT_LOCKED)
            if "locked" in str(exc).lower() or "busy" in str(exc).lower():
                response = json.dumps(
                    {
                        "status": "queued",
                        "logid": ctx.log_id,
                        "pending": str(pending_path),
                        "rc": rc,
                        "ext": ext,
                    },
                    ensure_ascii=False,
                    separators=(",", ":"),
                ).encode("utf-8")
                await self.write_response(writer, 202, response, ctx)
                log_warn(
                    f"DATA WRITE queued key={logical_key} reason=sqlite_lock rc={rc} ext={ext} bytes={len(body)} "
                    f"pending={pending_path} account={ctx.account_id} logid={ctx.log_id}"
                )
                return 202

            backup_path = self.store.persist_failed_payload(logical_key, payload, rc, ext)
            await self.write_response(
                writer,
                500,
                json.dumps(
                    {"error": "database error", "rc": rc, "ext": ext, "backup": str(backup_path)},
                    ensure_ascii=False,
                    separators=(",", ":"),
                ).encode("utf-8"),
                ctx,
            )
            log_error(
                f"DATA WRITE failed key={logical_key} reason=sqlite_step_error rc={rc} rc_name={sqlite_error_name(exc)} "
                f"ext={ext} ext_name={sqlite_error_name(exc)} errmsg={exc} bytes={len(body)} backup={backup_path} "
                f"account={ctx.account_id} logid={ctx.log_id}"
            )
            return 500
        except Exception as exc:
            backup_path = self.store.persist_failed_payload(logical_key, payload, 1, 1)
            await self.write_response(
                writer,
                500,
                json.dumps(
                    {"error": "database error", "backup": str(backup_path)},
                    ensure_ascii=False,
                    separators=(",", ":"),
                ).encode("utf-8"),
                ctx,
            )
            log_error(
                f"DATA WRITE failed key={logical_key} reason=unexpected_error errmsg={exc} bytes={len(body)} backup={backup_path} "
                f"account={ctx.account_id} logid={ctx.log_id}"
            )
            return 500

        try:
            self.store.remove_pending_write(pending_path)
        except Exception:
            await self.write_response(writer, 500, json_error("durable journal cleanup error"), ctx)
            log_error(
                f"DATA WRITE failed key={logical_key} reason=pending_write_cleanup_failed path={pending_path} "
                f"account={ctx.account_id} logid={ctx.log_id}"
            )
            return 500

        await self.write_response(writer, 204, b"", ctx)
        log_info(
            f"DATA WRITE key={logical_key} status=stored bytes={len(body)} account={ctx.account_id} logid={ctx.log_id} retries={retries}"
        )
        return 204

    async def write_response(
        self,
        writer: asyncio.StreamWriter,
        status_code: int,
        body: bytes,
        ctx: RequestContext,
        content_type: str = "application/json",
    ) -> None:
        reason = STATUS_TEXT.get(status_code, "OK")
        headers = [
            f"HTTP/1.1 {status_code} {reason}\r\n",
            f"Content-Type: {content_type}\r\n",
            f"X-Log-Id: {ctx.log_id}\r\n",
            f"Content-Length: {len(body)}\r\n",
            "Connection: close\r\n",
            "\r\n",
        ]
        writer.write("".join(headers).encode("utf-8"))
        if body:
            writer.write(body)
        await writer.drain()

    def log_http_request(self, method: str, path: str, status_code: int, payload_bytes: int, ctx: RequestContext) -> None:
        message = (
            f"HTTP {method} {path} -> {status_code} ({payload_bytes} bytes) account={ctx.account_id or '-'} "
            f"logid={ctx.log_id or '-'} retry={ctx.retry_attempt}"
        )
        if status_code >= 500:
            log_error(message)
        elif status_code >= 400:
            log_warn(message)
        else:
            log_info(message)

    @staticmethod
    def generate_server_log_id() -> str:
        now_ns = time.time_ns()
        return f"srv-{now_ns // 1_000_000_000}-{now_ns % 1_000_000_000}-{os.getpid()}"


async def run_server(host: str, port: int, db_file: Path, state_dir: Path, backlog: int) -> None:
    app = FricuPythonServer(db_path=db_file, state_dir=state_dir)
    server = await asyncio.start_server(
        app.handle_client,
        host=host,
        port=port,
        backlog=backlog,
        limit=max(MAX_HEADER_BYTES * 2, 128 * 1024),
    )
    log_info(f"fricu-python-server listening on http://{host}:{port}")
    log_info(f"SQLite DB: {db_file}")
    log_info(f"State dir: {state_dir}")
    async with server:
        await server.serve_forever()



def main() -> None:
    root_dir = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description="Fricu Python backend server")
    parser.add_argument("--host", default=os.environ.get("FRICU_SERVER_HOST", "127.0.0.1"))
    parser.add_argument("--port", type=int, default=int(os.environ.get("FRICU_SERVER_PORT", "8080")))
    parser.add_argument(
        "--db-file",
        default=os.environ.get("FRICU_SERVER_DB_FILE", os.environ.get("FRICU_DB_PATH", str(root_dir / "fricu_server.db"))),
    )
    parser.add_argument(
        "--state-dir",
        default=os.environ.get("FRICU_SERVER_STATE_DIR", str(root_dir)),
    )
    parser.add_argument(
        "--backlog",
        type=int,
        default=int(os.environ.get("FRICU_SERVER_BACKLOG", "4096")),
    )
    args = parser.parse_args()

    if not (1 <= args.port <= 65535):
        raise SystemExit("--port must be in 1..65535")
    if args.backlog <= 0:
        raise SystemExit("--backlog must be > 0")

    try:
        asyncio.run(
            run_server(
                host=args.host,
                port=args.port,
                db_file=Path(args.db_file).resolve(),
                state_dir=Path(args.state_dir).resolve(),
                backlog=args.backlog,
            )
        )
    except KeyboardInterrupt:
        print("\nShutting down Fricu Python server...", file=sys.stderr)


if __name__ == "__main__":
    main()
