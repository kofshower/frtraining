#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

echo "[verify] macOS compatibility build"
xcodebuild -scheme FricuApp -destination 'platform=macOS' -derivedDataPath /tmp/fricu-verify-mac build CODE_SIGNING_ALLOWED=NO

echo "[verify] iOS Simulator compatibility build"
xcodebuild -scheme FricuApp -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/fricu-verify-ios build CODE_SIGNING_ALLOWED=NO

echo "[verify] server unit tests"
make -C "$ROOT_DIR/server" test

echo "[verify] server perf test"
make -C "$ROOT_DIR/server" perf-test

echo "[verify] core coverage gate"
"$ROOT_DIR/scripts/test-coverage-100.sh"

echo "[verify] app regression and chaos tests"
swift test --filter 'RemoteHTTPRepositoryActivitiesFallbackTests|ActivityDetailDerivedCacheKeyTests|VideoFittingChaosTests'

echo "[verify] bike keypoint self-train smoke test"
bash "$ROOT_DIR/scripts/test-bike-keypoint-selftrain.sh"

echo "[verify] release checks passed"
