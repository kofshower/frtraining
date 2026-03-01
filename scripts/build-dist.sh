#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_CONFIG="${BUILD_CONFIG:-release}"

if [[ "$BUILD_CONFIG" != "release" && "$BUILD_CONFIG" != "debug" ]]; then
  echo "Invalid BUILD_CONFIG: $BUILD_CONFIG (expected: release|debug)" >&2
  exit 1
fi

cd "$ROOT_DIR"
swift build -c "$BUILD_CONFIG" -Xswiftc -gnone

APP_BUNDLE="$("$ROOT_DIR/scripts/make-app-bundle.sh" "$BUILD_CONFIG")"
DIST_DIR="$ROOT_DIR/dist/$BUILD_CONFIG"
DIST_BIN="$DIST_DIR/FricuApp"
SERVER_DIST_BIN="$DIST_DIR/fricu-server"

SERVER_CFLAGS=""
if [[ "$BUILD_CONFIG" == "debug" ]]; then
  SERVER_CFLAGS='-O0 -g -Wall -Wextra -Werror -std=c11 -pthread'
fi

if [[ -n "$SERVER_CFLAGS" ]]; then
  make -C "$ROOT_DIR/server" CFLAGS="$SERVER_CFLAGS"
else
  make -C "$ROOT_DIR/server"
fi

mkdir -p "$DIST_DIR"
install -m 0755 "$ROOT_DIR/server/fricu-server" "$SERVER_DIST_BIN"

echo "Built bundle: $APP_BUNDLE"
echo "Built binary: $DIST_BIN"
echo "Built server binary: $SERVER_DIST_BIN"
