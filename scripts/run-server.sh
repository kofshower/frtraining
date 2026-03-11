#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HOST="${FRICU_SERVER_HOST:-127.0.0.1}"
PORT="${FRICU_SERVER_PORT:-8080}"
DB_FILE="${FRICU_DB_PATH:-$ROOT_DIR/fricu_server.db}"
SERVER_BIN="$ROOT_DIR/server/fricu-server"

mkdir -p "$(dirname "$DB_FILE")"

cd "$ROOT_DIR"

if [ ! -x "$SERVER_BIN" ]; then
  echo "Building Fricu C backend..."
  make -C "$ROOT_DIR/server"
fi

echo "Starting Fricu C backend on http://$HOST:$PORT"
echo "SQLite DB: $DB_FILE"
export FRICU_SERVER_BIND="$HOST:$PORT"
export FRICU_DB_PATH="$DB_FILE"
exec "$SERVER_BIN"
