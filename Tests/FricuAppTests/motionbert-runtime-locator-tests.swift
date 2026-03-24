import XCTest
@testable import FricuApp

final class MotionBERTRuntimeLocatorTests: XCTestCase {
    func testResolveBundledPythonPathReturnsFallbackExecutableWhenPresent() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let binDirectory = tempRoot
            .appendingPathComponent(MotionBERTRuntimeLocator.runtimeDirectoryName, isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: binDirectory, withIntermediateDirectories: true)

        let executableURL = binDirectory.appendingPathComponent("python3")
        try "#!/bin/sh\necho motionbert\n".write(to: executableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executableURL.path)

        defer {
            try? FileManager.default.removeItem(at: tempRoot)
        }

        let locator = MotionBERTRuntimeLocator()
        let resolved = locator.resolveBundledPythonPath(bundle: .main, fallbackSearchRoots: [tempRoot])

        XCTAssertEqual(resolved, executableURL.path)
    }

    func testResolveBundledCacheRootURLReturnsNilWhenCacheIsMissing() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let runtimeRoot = tempRoot.appendingPathComponent(MotionBERTRuntimeLocator.runtimeDirectoryName, isDirectory: true)
        try FileManager.default.createDirectory(at: runtimeRoot, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempRoot)
        }

        let locator = MotionBERTRuntimeLocator()
        XCTAssertNil(locator.resolveBundledCacheRootURL(bundle: .main, fallbackSearchRoots: [tempRoot]))
    }

    func testResolveBundledCacheRootURLReturnsCacheDirectoryWhenKnownCacheExists() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let cacheDirectory = tempRoot
            .appendingPathComponent(MotionBERTRuntimeLocator.runtimeDirectoryName, isDirectory: true)
            .appendingPathComponent("cache/openmmlab", isDirectory: true)
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempRoot)
        }

        let locator = MotionBERTRuntimeLocator()
        let resolved = locator.resolveBundledCacheRootURL(bundle: .main, fallbackSearchRoots: [tempRoot])

        XCTAssertEqual(resolved?.path, cacheDirectory.deletingLastPathComponent().path)
    }

    func testResolveBundledCacheRootURLReturnsCacheDirectoryWhenTorchCacheExists() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let cacheDirectory = tempRoot
            .appendingPathComponent(MotionBERTRuntimeLocator.runtimeDirectoryName, isDirectory: true)
            .appendingPathComponent("cache/torch", isDirectory: true)
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempRoot)
        }

        let locator = MotionBERTRuntimeLocator()
        let resolved = locator.resolveBundledCacheRootURL(bundle: .main, fallbackSearchRoots: [tempRoot])

        XCTAssertEqual(resolved?.path, cacheDirectory.deletingLastPathComponent().path)
    }
}
