#!/usr/bin/env python3
"""One-time migration: ensure model rows always carry a normalized athleteName.

This script rewrites kv_store JSON payloads for:
  - activities
  - workouts
  - events
  - wellness_samples
  - meal_plans

It normalizes legacy athlete-name suffixes, fills missing/blank athleteName fields,
and stores updated JSON back into SQLite.
"""

from __future__ import annotations

import argparse
import collections
import json
import re
import sqlite3
import sys
import time
from pathlib import Path
from typing import Any


TARGET_SUFFIXES = {
    "activities",
    "workouts",
    "events",
    "wellness_samples",
    "meal_plans",
}

LEGACY_SEPARATORS = [
    "---来自Fricu",
    "---来自 Fricu",
    "---fromFricu",
    "---from Fricu",
    " · Trainer ride",
    " · 训练骑行",
    "• Trainer ride",
    "• 训练骑行",
]

UUID_RE = re.compile(
    r"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"
)


def split_data_key(data_key: str) -> tuple[str, str]:
    if "::" not in data_key:
        return "__global__", data_key
    namespace, suffix = data_key.split("::", 1)
    return namespace, suffix


def _strip_legacy_suffix(text: str) -> str:
    candidate = text.strip()
    if not candidate:
        return ""
    lowered = candidate.lower()
    for separator in LEGACY_SEPARATORS:
        idx = lowered.find(separator.lower())
        if idx == -1:
            continue
        prefix = candidate[:idx].strip()
        if prefix:
            return prefix
    return candidate


def normalize_athlete_name(raw: Any) -> str:
    if not isinstance(raw, str):
        return ""
    candidate = _strip_legacy_suffix(raw)
    if not candidate:
        return ""
    if "::" in candidate:
        left, right = candidate.split("::", 1)
        left = left.strip()
        right = right.strip()
        if right and (UUID_RE.match(left) or left.startswith("__") or left.lower().startswith("athlete_")):
            candidate = right
    return candidate.strip()


def infer_from_notes(raw_notes: Any) -> str:
    if not isinstance(raw_notes, str):
        return ""
    return normalize_athlete_name(raw_notes)


def choose_namespace_default(
    namespace: str,
    counts: collections.Counter[str],
    fallback_name: str,
) -> str:
    if counts:
        return counts.most_common(1)[0][0]
    if namespace == "__anonymous__":
        return fallback_name
    if namespace == "__global__":
        return fallback_name
    return fallback_name


def parse_rows(conn: sqlite3.Connection) -> list[tuple[str, str, str, list[Any], str]]:
    rows = conn.execute("SELECT data_key, data_value FROM kv_store").fetchall()
    parsed: list[tuple[str, str, str, list[Any], str]] = []
    for data_key, data_value in rows:
        if not isinstance(data_key, str):
            continue
        namespace, suffix = split_data_key(data_key)
        if suffix not in TARGET_SUFFIXES:
            continue
        try:
            payload = json.loads(data_value)
        except json.JSONDecodeError:
            print(f"[WARN] skip invalid JSON: {data_key}")
            continue
        if not isinstance(payload, list):
            print(f"[WARN] skip non-array payload: {data_key}")
            continue
        parsed.append((data_key, namespace, suffix, payload, data_value))
    return parsed


def build_namespace_name_hints(
    parsed_rows: list[tuple[str, str, str, list[Any], str]]
) -> dict[str, collections.Counter[str]]:
    hints: dict[str, collections.Counter[str]] = collections.defaultdict(collections.Counter)
    for _, namespace, suffix, payload, _ in parsed_rows:
        counter = hints[namespace]
        for row in payload:
            if not isinstance(row, dict):
                continue
            direct = normalize_athlete_name(row.get("athleteName"))
            if direct:
                counter[direct] += 1
                continue
            if suffix == "activities":
                from_notes = infer_from_notes(row.get("notes"))
                if from_notes:
                    counter[from_notes] += 1
    return hints


def migrate_payload(
    suffix: str,
    payload: list[Any],
    fallback_athlete: str,
) -> tuple[list[Any], int, int]:
    changed = 0
    filled_missing = 0
    for row in payload:
        if not isinstance(row, dict):
            continue
        original = normalize_athlete_name(row.get("athleteName"))
        candidate = original
        if not candidate and suffix == "activities":
            candidate = infer_from_notes(row.get("notes"))
        if not candidate:
            candidate = fallback_athlete
        row_changed = ("athleteName" not in row) or (row.get("athleteName") != candidate)
        if row_changed:
            changed += 1
            if not original:
                filled_missing += 1
            row["athleteName"] = candidate
    return payload, changed, filled_missing


def run(args: argparse.Namespace) -> int:
    db_path = Path(args.db).expanduser().resolve()
    if not db_path.exists():
        print(f"[ERROR] DB file not found: {db_path}")
        return 2

    conn = sqlite3.connect(str(db_path))
    try:
        table_exists = conn.execute(
            "SELECT 1 FROM sqlite_master WHERE type='table' AND name='kv_store'"
        ).fetchone()
        if not table_exists:
            print("[ERROR] kv_store table not found")
            return 2

        parsed_rows = parse_rows(conn)
        namespace_hints = build_namespace_name_hints(parsed_rows)
        namespace_defaults = {
            namespace: choose_namespace_default(namespace, counts, args.default_athlete)
            for namespace, counts in namespace_hints.items()
        }

        updates: list[tuple[str, str, int, int]] = []
        total_rows = 0
        total_changed = 0
        total_filled = 0
        for data_key, namespace, suffix, payload, _ in parsed_rows:
            total_rows += len(payload)
            fallback = namespace_defaults.get(namespace, args.default_athlete)
            migrated, changed, filled = migrate_payload(suffix, payload, fallback)
            if changed == 0:
                continue
            updates.append(
                (
                    data_key,
                    json.dumps(migrated, ensure_ascii=False, separators=(",", ":")),
                    changed,
                    filled,
                )
            )
            total_changed += changed
            total_filled += filled

        print(f"[INFO] scanned keys={len(parsed_rows)} rows={total_rows}")
        print(f"[INFO] candidate updates keys={len(updates)} rows_changed={total_changed} rows_filled={total_filled}")

        if not updates:
            print("[INFO] no migration needed")
            return 0

        if args.dry_run:
            for data_key, _, changed, filled in updates:
                print(f"[DRY-RUN] {data_key}: changed={changed} filled_missing={filled}")
            return 0

        timestamp = time.strftime("%Y%m%d-%H%M%S")
        backup_path = Path(args.backup) if args.backup else db_path.with_suffix(f".backup-athlete-name-v2-{timestamp}.db")
        backup_conn = sqlite3.connect(str(backup_path))
        try:
            conn.backup(backup_conn)
        finally:
            backup_conn.close()
        print(f"[INFO] backup created: {backup_path}")

        now = int(time.time())
        conn.execute("BEGIN")
        try:
            for data_key, data_value, changed, filled in updates:
                conn.execute(
                    "UPDATE kv_store SET data_value = ?, updated_at = ? WHERE data_key = ?",
                    (data_value, now, data_key),
                )
                print(f"[INFO] updated {data_key}: changed={changed} filled_missing={filled}")
            conn.execute("COMMIT")
        except Exception:
            conn.execute("ROLLBACK")
            raise

        print("[INFO] migration complete")
        return 0
    finally:
        conn.close()


def main() -> int:
    parser = argparse.ArgumentParser(
        description="One-time athleteName migration for Fricu model v2."
    )
    parser.add_argument(
        "--db",
        default="fricu_server.db",
        help="Path to SQLite DB (default: ./fricu_server.db)",
    )
    parser.add_argument(
        "--default-athlete",
        default="Default Athlete",
        help="Fallback athleteName when no hint can be inferred.",
    )
    parser.add_argument(
        "--backup",
        default="",
        help="Optional explicit backup DB path.",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Preview changes without writing.",
    )
    return run(parser.parse_args())


if __name__ == "__main__":
    sys.exit(main())
