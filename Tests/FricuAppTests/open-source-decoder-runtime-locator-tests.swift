import XCTest
@testable import FricuApp

/// Unit tests for resolving bundled open-source decoder binaries.
final class OpenSourceDecoderRuntimeLocatorTests: XCTestCase {
    /// Verifies that resolver returns an executable from fallback search roots.
    func testResolveBundledToolPathReturnsFallbackExecutableWhenPresent() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let binDirectory = tempRoot.appendingPathComponent("OpenSourceDecoder/bin", isDirectory: true)
        try FileManager.default.createDirectory(at: binDirectory, withIntermediateDirectories: true)

        let executableURL = binDirectory.appendingPathComponent("ffmpeg")
        let executableContent = "#!/bin/sh\necho decoder\n"
        try executableContent.write(to: executableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executableURL.path)

        defer {
            try? FileManager.default.removeItem(at: tempRoot)
        }

        let locator = OpenSourceDecoderRuntimeLocator()
        let resolved = locator.resolveBundledToolPath(
            toolName: "ffmpeg",
            bundle: .main,
            fallbackSearchRoots: [tempRoot]
        )

        XCTAssertEqual(resolved, executableURL.path)
    }

    /// Verifies that resolver returns nil when executable is unavailable in all search roots.
    func testResolveBundledToolPathReturnsNilWhenMissing() {
        let locator = OpenSourceDecoderRuntimeLocator()

        let resolved = locator.resolveBundledToolPath(
            toolName: "ffmpeg-nonexistent-tool",
            bundle: .main,
            fallbackSearchRoots: []
        )

        XCTAssertNil(resolved)
    }
}
