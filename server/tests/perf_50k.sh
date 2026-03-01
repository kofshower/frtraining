#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
SERVER_DIR="$ROOT_DIR/server"

cd "$SERVER_DIR"
make >/dev/null
make build-perf-client >/dev/null

FRICU_SERVER_WORKERS=${FRICU_SERVER_WORKERS:-128} FRICU_SERVER_QUEUE=${FRICU_SERVER_QUEUE:-131072} ./fricu-server >/tmp/fricu_server_perf.log 2>&1 &
SERVER_PID=$!
trap 'kill $SERVER_PID 2>/dev/null || true' EXIT

sleep 1

OUTPUT=$(./perf-client 50000 512)
echo "$OUTPUT"

echo "$OUTPUT" | rg -q '^failed=0$'
SUCCESS=$(echo "$OUTPUT" | awk -F= '/^success=/{print $2}')
if [[ "$SUCCESS" -lt 50000 ]]; then
  echo "expected success >= 50000, got $SUCCESS" >&2
  exit 1
fi

RPS=$(echo "$OUTPUT" | awk -F= '/^rps=/{print $2}')
echo "perf test passed: success=$SUCCESS rps=$RPS"
