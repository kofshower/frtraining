#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

# Build + run core tests with coverage first.
swift test --package-path CorePackage --enable-code-coverage --filter 'FricuCoreTests' >/dev/null

CODECOV_JSON="$(swift test --package-path CorePackage --enable-code-coverage --show-codecov-path --filter 'FricuCoreTests')"

if [[ ! -f "$CODECOV_JSON" ]]; then
  # Swift 6 Linux may not materialize the JSON file. Fallback to llvm-cov export.
  PROF_PATH="CorePackage/.build/x86_64-unknown-linux-gnu/debug/codecov/default.profdata"
  BIN_PATH="CorePackage/.build/x86_64-unknown-linux-gnu/debug/FricuCorePackageTests.xctest"
  if [[ -f "$PROF_PATH" && -f "$BIN_PATH" ]]; then
    CODECOV_JSON="$(mktemp)"
    llvm-cov export -instr-profile "$PROF_PATH" "$BIN_PATH" > "$CODECOV_JSON"
  else
    echo "Coverage artifacts not found (json/profdata)." >&2
    exit 1
  fi
fi

swift - "$CODECOV_JSON" <<'SWIFT'
import Foundation

struct SummaryLines: Decodable {
    let percent: Double
}

struct Summary: Decodable {
    let lines: SummaryLines
}

struct CoverageFile: Decodable {
    let filename: String
    let summary: Summary
}

struct CoverageDatum: Decodable {
    let files: [CoverageFile]
}

struct CoverageRoot: Decodable {
    let data: [CoverageDatum]
}

let jsonPath = CommandLine.arguments[1]
let url = URL(fileURLWithPath: jsonPath)
let data = try Data(contentsOf: url)
let root = try JSONDecoder().decode(CoverageRoot.self, from: data)

let coreFiles = root.data
    .flatMap(\.files)
    .filter {
        ($0.filename.contains("/CorePackage/Sources/FricuCore/") || $0.filename.contains("/Sources/FricuCore/"))
            && $0.filename.hasSuffix(".swift")
    }

guard !coreFiles.isEmpty else {
    fputs("No FricuCore source files found in coverage report.\n", stderr)
    exit(2)
}

var failed = false
for file in coreFiles.sorted(by: { $0.filename < $1.filename }) {
    let pct = file.summary.lines.percent
    let pctText = String(format: "%.2f", pct)
    print("[coverage] \(pctText)% \(file.filename)")
    if pct < 100.0 {
        failed = true
    }
}

if failed {
    fputs("Coverage gate failed: FricuCore line coverage must be 100% for every source file.\n", stderr)
    exit(3)
}

print("Coverage gate passed: FricuCore is 100% line-covered.")
SWIFT
