#!/usr/bin/env python3
"""One-time migration: move legacy/global activities into account-scoped key.

Default behavior:
  - target key: "<account_id>::activities"
  - source keys: "activities", "__anonymous__::activities"
  - merge + dedupe rows into target key
  - keep source keys unchanged unless --delete-source-keys is passed

Account ID can be passed explicitly via --account-id, otherwise this script
tries to read it from:
  ~/Library/Application Support/fricu/auth/session.json
"""

from __future__ import annotations

import argparse
import json
import sqlite3
import sys
import time
from pathlib import Path
from typing import Any


def _load_json_array(raw: str, key: str) -> list[dict[str, Any]]:
    try:
        payload = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise ValueError(f"invalid JSON for key={key}: {exc}") from exc
    if not isinstance(payload, list):
        raise ValueError(f"payload for key={key} is not a JSON array")
    rows: list[dict[str, Any]] = []
    for idx, row in enumerate(payload):
        if not isinstance(row, dict):
            continue
        rows.append(row)
        if idx > 2_000_000:
            break
    return rows


def _row_score(row: dict[str, Any]) -> tuple[int, int]:
    important_fields = [
        "powerSeries",
        "heartRateSeries",
        "cadenceSeries",
        "distanceSeries",
        "sensorSamples",
        "sourceFileBase64",
        "platformPayloadJSON",
        "notes",
        "normalizedPower",
        "avgPower",
        "avgHeartRate",
        "maxHeartRate",
        "movingDurationSec",
    ]
    non_empty = 0
    for key in important_fields:
        value = row.get(key)
        if value in (None, "", [], {}):
            continue
        non_empty += 1
    encoded_len = len(json.dumps(row, ensure_ascii=False, separators=(",", ":"), sort_keys=True))
    return non_empty, encoded_len


def _dedupe_key(row: dict[str, Any]) -> tuple[Any, ...]:
    row_id = row.get("id")
    if isinstance(row_id, str) and row_id.strip():
        return ("id", row_id.strip())

    external_id = row.get("externalID")
    if isinstance(external_id, str) and external_id.strip():
        return ("externalID", external_id.strip())

    source_file = row.get("sourceFileName")
    sport = row.get("sport")
    date = row.get("date")
    if isinstance(source_file, str) and source_file.strip():
        return ("source", source_file.strip(), str(date), str(sport))

    return (
        "fallback",
        str(row.get("date")),
        str(row.get("sport")),
        str(row.get("durationSec")),
        str(row.get("distanceKm")),
        str(row.get("tss")),
        str(row.get("notes")),
    )


def _dedupe_activities(rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    picked: dict[tuple[Any, ...], dict[str, Any]] = {}
    for row in rows:
        key = _dedupe_key(row)
        existing = picked.get(key)
        if existing is None:
            picked[key] = row
            continue
        if _row_score(row) > _row_score(existing):
            picked[key] = row
    deduped = list(picked.values())
    deduped.sort(key=lambda r: str(r.get("date", "")), reverse=True)
    return deduped


def _read_active_session_account_id(explicit_account_id: str) -> str:
    trimmed = explicit_account_id.strip()
    if trimmed:
        return trimmed
    session_path = (
        Path.home()
        / "Library"
        / "Application Support"
        / "fricu"
        / "auth"
        / "session.json"
    )
    if not session_path.exists():
        raise ValueError(
            "account id not provided and session.json not found. "
            "pass --account-id explicitly."
        )
    try:
        payload = json.loads(session_path.read_text(encoding="utf-8"))
    except Exception as exc:
        raise ValueError(f"failed to parse session file: {session_path} ({exc})") from exc
    account_id = str(payload.get("accountID", "")).strip()
    if not account_id:
        raise ValueError(
            "session.json has no accountID. pass --account-id explicitly."
        )
    return account_id


def _list_existing_activity_keys(conn: sqlite3.Connection) -> list[str]:
    rows = conn.execute(
        "SELECT data_key FROM kv_store WHERE data_key = 'activities' OR data_key LIKE '%::activities'"
    ).fetchall()
    keys = []
    for row in rows:
        value = row[0]
        if isinstance(value, str):
            keys.append(value)
    return sorted(set(keys))


def _load_rows_for_key(conn: sqlite3.Connection, key: str) -> list[dict[str, Any]]:
    row = conn.execute(
        "SELECT data_value FROM kv_store WHERE data_key = ? LIMIT 1",
        (key,),
    ).fetchone()
    if row is None:
        return []
    raw = row[0]
    if not isinstance(raw, str):
        return []
    return _load_json_array(raw, key)


def _build_source_keys(
    all_activity_keys: list[str],
    target_key: str,
    explicit_from_keys: list[str],
    source_mode: str,
) -> list[str]:
    keys = []
    for key in explicit_from_keys:
        trimmed = key.strip()
        if trimmed and trimmed != target_key:
            keys.append(trimmed)

    if source_mode == "legacy":
        for key in ("activities", "__anonymous__::activities"):
            if key != target_key:
                keys.append(key)
    elif source_mode == "all":
        for key in all_activity_keys:
            if key != target_key:
                keys.append(key)
    else:
        raise ValueError(f"unsupported source mode: {source_mode}")

    unique: list[str] = []
    seen: set[str] = set()
    for key in keys:
        if key in seen:
            continue
        seen.add(key)
        unique.append(key)
    return unique


def run(args: argparse.Namespace) -> int:
    db_path = Path(args.db).expanduser().resolve()
    if not db_path.exists():
        print(f"[ERROR] DB file not found: {db_path}")
        return 2

    try:
        account_id = _read_active_session_account_id(args.account_id)
    except ValueError as exc:
        print(f"[ERROR] {exc}")
        return 2

    target_key = f"{account_id}::activities"
    conn = sqlite3.connect(str(db_path))
    try:
        table_exists = conn.execute(
            "SELECT 1 FROM sqlite_master WHERE type='table' AND name='kv_store'"
        ).fetchone()
        if not table_exists:
            print("[ERROR] kv_store table not found")
            return 2

        all_activity_keys = _list_existing_activity_keys(conn)
        source_keys = _build_source_keys(
            all_activity_keys=all_activity_keys,
            target_key=target_key,
            explicit_from_keys=args.from_key,
            source_mode=args.source_mode,
        )

        target_rows = _load_rows_for_key(conn, target_key)
        source_rows_by_key: dict[str, list[dict[str, Any]]] = {}
        for key in source_keys:
            try:
                source_rows_by_key[key] = _load_rows_for_key(conn, key)
            except ValueError as exc:
                print(f"[WARN] {exc}")
                source_rows_by_key[key] = []

        merged_raw = list(target_rows)
        for key in source_keys:
            merged_raw.extend(source_rows_by_key.get(key, []))
        merged_rows = _dedupe_activities(merged_raw)

        source_total = sum(len(rows) for rows in source_rows_by_key.values())
        print(f"[INFO] db={db_path}")
        print(f"[INFO] account_id={account_id}")
        print(f"[INFO] target_key={target_key} existing_rows={len(target_rows)}")
        print(f"[INFO] source_mode={args.source_mode} source_keys={len(source_keys)} source_rows={source_total}")
        for key in source_keys:
            print(f"[INFO] source {key}: rows={len(source_rows_by_key.get(key, []))}")
        print(f"[INFO] merged_rows_raw={len(merged_raw)} merged_rows_deduped={len(merged_rows)}")

        if args.dry_run:
            print("[INFO] dry-run complete (no writes)")
            return 0

        timestamp = time.strftime("%Y%m%d-%H%M%S")
        backup_path = (
            Path(args.backup).expanduser().resolve()
            if args.backup.strip()
            else db_path.with_suffix(f".backup-activities-scope-{timestamp}.db")
        )
        backup_conn = sqlite3.connect(str(backup_path))
        try:
            conn.backup(backup_conn)
        finally:
            backup_conn.close()
        print(f"[INFO] backup created: {backup_path}")

        now = int(time.time())
        encoded = json.dumps(merged_rows, ensure_ascii=False, separators=(",", ":"))

        conn.execute("BEGIN")
        try:
            conn.execute(
                """
                INSERT INTO kv_store (data_key, data_value, updated_at)
                VALUES (?, ?, ?)
                ON CONFLICT(data_key) DO UPDATE SET
                    data_value=excluded.data_value,
                    updated_at=excluded.updated_at
                """,
                (target_key, encoded, now),
            )
            if args.delete_source_keys:
                for key in source_keys:
                    conn.execute("DELETE FROM kv_store WHERE data_key = ?", (key,))
            conn.execute("COMMIT")
        except Exception:
            conn.execute("ROLLBACK")
            raise

        print(f"[INFO] wrote target key: {target_key} rows={len(merged_rows)}")
        if args.delete_source_keys and source_keys:
            print(f"[INFO] deleted source keys: {', '.join(source_keys)}")
        print("[INFO] migration complete")
        return 0
    finally:
        conn.close()


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Migrate legacy/global activities into account-scoped activities key."
    )
    parser.add_argument(
        "--db",
        default="fricu_server.db",
        help="Path to SQLite DB (default: ./fricu_server.db)",
    )
    parser.add_argument(
        "--account-id",
        default="",
        help="Target account ID. If omitted, read from session.json.",
    )
    parser.add_argument(
        "--source-mode",
        choices=["legacy", "all"],
        default="legacy",
        help="legacy: only activities + __anonymous__::activities; all: all *::activities keys except target.",
    )
    parser.add_argument(
        "--from-key",
        action="append",
        default=[],
        help="Extra source key(s) to include (repeatable).",
    )
    parser.add_argument(
        "--delete-source-keys",
        action="store_true",
        help="Delete source keys after successful merge into target.",
    )
    parser.add_argument(
        "--backup",
        default="",
        help="Optional explicit backup DB path.",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Preview only; do not write DB.",
    )
    return run(parser.parse_args())


if __name__ == "__main__":
    sys.exit(main())
