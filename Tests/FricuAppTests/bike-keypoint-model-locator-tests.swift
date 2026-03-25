import XCTest
@testable import FricuApp

final class BikeKeypointModelLocatorTests: XCTestCase {
    override func tearDown() {
        super.tearDown()
        UserDefaults.standard.removeObject(forKey: BikeKeypointModelLocator.preferredCheckpointDefaultsKey)
    }

    func testResolveBundledCheckpointURLReturnsPackagedBestCheckpoint() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let checkpointURL = tempRoot
            .appendingPathComponent(BikeKeypointModelLocator.modelDirectoryName, isDirectory: true)
            .appendingPathComponent("best.pt", isDirectory: false)
        try FileManager.default.createDirectory(
            at: checkpointURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("bike".utf8).write(to: checkpointURL)

        defer {
            try? FileManager.default.removeItem(at: tempRoot)
        }

        let locator = BikeKeypointModelLocator()
        let resolved = locator.resolveBundledCheckpointURL(
            bundle: .main,
            fallbackSearchRoots: [tempRoot]
        )

        XCTAssertEqual(resolved?.path, checkpointURL.path)
    }

    func testResolveCheckpointURLPrefersNewestDevelopmentCheckpoint() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let searchRoot = tempRoot.appendingPathComponent(".runtime/BikeKeypointSelfTrain", isDirectory: true)
        let olderCheckpoint = searchRoot
            .appendingPathComponent("road-bike-v1/run-old/best.pt", isDirectory: false)
        let newerCheckpoint = searchRoot
            .appendingPathComponent("road-bike-v2/run-new/best.pt", isDirectory: false)

        try FileManager.default.createDirectory(
            at: olderCheckpoint.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: newerCheckpoint.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("old".utf8).write(to: olderCheckpoint)
        Thread.sleep(forTimeInterval: 0.02)
        try Data("new".utf8).write(to: newerCheckpoint)

        defer {
            try? FileManager.default.removeItem(at: tempRoot)
        }

        let locator = BikeKeypointModelLocator()
        let resolved = locator.resolveCheckpointURL(
            bundle: .main,
            environment: [:],
            currentDirectoryPath: tempRoot.path
        )

        XCTAssertEqual(
            resolved?.resolvingSymlinksInPath().path,
            newerCheckpoint.resolvingSymlinksInPath().path
        )
    }

    func testResolveCheckpointURLPrefersUserDefaultsOverrideWhenPresent() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let preferredCheckpoint = tempRoot.appendingPathComponent("manual/best.pt", isDirectory: false)
        try FileManager.default.createDirectory(
            at: preferredCheckpoint.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("preferred".utf8).write(to: preferredCheckpoint)

        defer {
            try? FileManager.default.removeItem(at: tempRoot)
        }

        UserDefaults.standard.set(
            preferredCheckpoint.path,
            forKey: BikeKeypointModelLocator.preferredCheckpointDefaultsKey
        )

        let locator = BikeKeypointModelLocator()
        let resolved = locator.resolveCheckpointURL(
            bundle: .main,
            environment: [:],
            currentDirectoryPath: tempRoot.path
        )

        XCTAssertEqual(resolved?.path, preferredCheckpoint.path)
    }
}
