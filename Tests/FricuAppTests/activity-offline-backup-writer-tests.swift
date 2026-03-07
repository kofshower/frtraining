import Foundation
import XCTest
@testable import FricuApp

/// Tests `ActivityOfflineBackupWriter` to guarantee offline activity persistence.
final class ActivityOfflineBackupWriterTests: XCTestCase {
    /// Verifies that a FIT backup file is produced for activities missing FIT payloads.
    func testBackupWritesFitForUnsyncedActivity() throws {
        let directory = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let writer = ActivityOfflineBackupWriter(backupDirectory: directory)
        let activity = Activity(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            date: Date(timeIntervalSince1970: 1_700_000_000),
            sport: .cycling,
            durationSec: 3600,
            distanceKm: 40,
            tss: 70,
            normalizedPower: 220,
            avgHeartRate: 145
        )

        let urls = try writer.backup(activities: [activity])
        XCTAssertEqual(urls.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: urls[0].path))

        let data = try Data(contentsOf: urls[0])
        XCTAssertGreaterThan(data.count, 32)
    }

    /// Verifies that activities already carrying FIT payloads are skipped.
    func testBackupSkipsActivityWithEmbeddedFitPayload() throws {
        let directory = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let writer = ActivityOfflineBackupWriter(backupDirectory: directory)
        let activity = Activity(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            date: Date(timeIntervalSince1970: 1_700_000_100),
            sport: .running,
            durationSec: 1800,
            distanceKm: 5,
            tss: 40,
            normalizedPower: nil,
            avgHeartRate: 160,
            sourceFileName: "run.fit",
            sourceFileType: "fit",
            sourceFileBase64: Data("fit".utf8).base64EncodedString()
        )

        let urls = try writer.backup(activities: [activity])
        XCTAssertEqual(urls.count, 0)
        let written = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertEqual(written.count, 0)
    }

    /// Verifies zero-duration activities are clamped and still produce valid backups.
    func testBackupSupportsZeroDurationActivity() throws {
        let directory = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let writer = ActivityOfflineBackupWriter(backupDirectory: directory)
        let activity = Activity(
            id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
            date: Date(timeIntervalSince1970: 1_700_000_200),
            sport: .swimming,
            durationSec: 0,
            distanceKm: 0,
            tss: 0
        )

        let urls = try writer.backup(activities: [activity])
        XCTAssertEqual(urls.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: urls[0].path))
    }

    /// Verifies backup errors are surfaced for invalid filesystem targets.
    func testBackupThrowsForNonDirectoryTarget() throws {
        let tempRoot = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let fileTarget = tempRoot.appendingPathComponent("not-a-directory")
        try Data("x".utf8).write(to: fileTarget)

        let writer = ActivityOfflineBackupWriter(backupDirectory: fileTarget)
        let activity = Activity(
            date: Date(timeIntervalSince1970: 1_700_000_300),
            sport: .cycling,
            durationSec: 900,
            distanceKm: 10,
            tss: 30
        )

        XCTAssertThrowsError(try writer.backup(activities: [activity]))
    }

    /// Creates an isolated temporary directory for deterministic IO tests.
    private func makeTemporaryDirectory() -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
