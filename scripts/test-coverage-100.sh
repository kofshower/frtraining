#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

CODECOV_JSON="$(swift test --enable-code-coverage --show-codecov-path --filter 'FricuCoreTests')"

if [[ ! -f "$CODECOV_JSON" ]]; then
  echo "Coverage JSON not found: $CODECOV_JSON" >&2
  exit 1
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
    .filter { $0.filename.contains("/Sources/FricuCore/") && $0.filename.hasSuffix(".swift") }

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
