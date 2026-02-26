#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_CONFIG="${BUILD_CONFIG:-release}"
APP_BUNDLE="$ROOT_DIR/dist/$BUILD_CONFIG/FricuApp.app"
APP_EXEC="$APP_BUNDLE/Contents/MacOS/FricuApp"

if [[ "$BUILD_CONFIG" != "release" && "$BUILD_CONFIG" != "debug" ]]; then
  echo "Invalid BUILD_CONFIG: $BUILD_CONFIG (expected: release|debug)" >&2
  exit 1
fi

cd "$ROOT_DIR"

swift build -c "$BUILD_CONFIG" -Xswiftc -gnone >/dev/null
"$ROOT_DIR/scripts/make-app-bundle.sh" "$BUILD_CONFIG" >/dev/null

if [[ ! -x "$APP_EXEC" ]]; then
  echo "Cannot find bundled executable for config: $BUILD_CONFIG" >&2
  exit 1
fi

# Kill stale instances from this workspace.
pkill -f "$APP_EXEC" 2>/dev/null || true

# Optional: also kill Xcode-launched build if explicitly requested.
if [[ "${KILL_XCODE_RUN:-0}" == "1" ]]; then
  pkill -f 'DerivedData/.*/fricu-.*/Build/Products/.*/FricuApp' 2>/dev/null || true
fi

sleep 1

open -n "$APP_BUNDLE"
sleep 1
APP_PID="$(pgrep -f "$APP_EXEC" | head -n 1 || true)"

if [[ -n "$APP_PID" ]]; then
  echo "FricuApp started in background ($BUILD_CONFIG, pid: $APP_PID)"
else
  echo "FricuApp launch requested in background ($BUILD_CONFIG)."
fi
