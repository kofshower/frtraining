#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HOST="${FRICU_SERVER_HOST:-127.0.0.1}"
PORT="${FRICU_SERVER_PORT:-8787}"
DB_FILE="${FRICU_SERVER_DB_FILE:-${FRICU_SERVER_DATA_FILE:-$ROOT_DIR/server/data/fricu.db}}"

mkdir -p "$(dirname "$DB_FILE")"

echo "Starting Fricu backend on http://$HOST:$PORT"
echo "SQLite DB: $DB_FILE"
exec python3 "$ROOT_DIR/server/fricu_server.py" --host "$HOST" --port "$PORT" --db-file "$DB_FILE"
