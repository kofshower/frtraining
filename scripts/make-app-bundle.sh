#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_CONFIG="${1:-${BUILD_CONFIG:-release}}"

if [[ "$BUILD_CONFIG" != "release" && "$BUILD_CONFIG" != "debug" ]]; then
  echo "Invalid build config: $BUILD_CONFIG (expected: release|debug)" >&2
  exit 1
fi

BUILD_DIR="$ROOT_DIR/.build/arm64-apple-macosx/$BUILD_CONFIG"
APP_BIN="$BUILD_DIR/FricuApp"
APP_BUNDLE="$BUILD_DIR/FricuApp.app"
APP_EXEC="$APP_BUNDLE/Contents/MacOS/FricuApp"
INFO_PLIST_SRC="$ROOT_DIR/Sources/FricuApp/Info.plist"
RESOURCE_BUNDLE="$BUILD_DIR/Fricu_FricuApp.bundle"
DIST_DIR="$ROOT_DIR/dist/$BUILD_CONFIG"
DIST_BIN="$DIST_DIR/FricuApp"
DIST_BUNDLE="$DIST_DIR/FricuApp.app"
DIST_ROOT_BIN="$ROOT_DIR/dist/FricuApp"
DIST_ROOT_BUNDLE="$ROOT_DIR/dist/FricuApp.app"

if [[ ! -x "$APP_BIN" ]]; then
  echo "Missing app binary: $APP_BIN" >&2
  exit 1
fi

if [[ ! -f "$INFO_PLIST_SRC" ]]; then
  echo "Missing Info.plist template: $INFO_PLIST_SRC" >&2
  exit 1
fi

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"

cp "$APP_BIN" "$APP_EXEC"
chmod +x "$APP_EXEC"
cp "$INFO_PLIST_SRC" "$APP_BUNDLE/Contents/Info.plist"

if [[ -d "$RESOURCE_BUNDLE" ]]; then
  cp -R "$RESOURCE_BUNDLE" "$APP_BUNDLE/Fricu_FricuApp.bundle"
  cp -R "$RESOURCE_BUNDLE" "$APP_BUNDLE/Contents/Resources/Fricu_FricuApp.bundle"
fi

mkdir -p "$DIST_DIR"
rm -rf "$DIST_BUNDLE"
cp "$APP_BIN" "$DIST_BIN"
chmod +x "$DIST_BIN"
cp -R "$APP_BUNDLE" "$DIST_BUNDLE"

cp "$DIST_BIN" "$DIST_ROOT_BIN"
chmod +x "$DIST_ROOT_BIN"
rm -rf "$DIST_ROOT_BUNDLE"
cp -R "$DIST_BUNDLE" "$DIST_ROOT_BUNDLE"

echo "$DIST_BUNDLE"
