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
DIST_BIN="$ROOT_DIR/dist/$BUILD_CONFIG/FricuApp"

echo "Built bundle: $APP_BUNDLE"
echo "Built binary: $DIST_BIN"
