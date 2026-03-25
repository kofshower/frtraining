import XCTest
@testable import FricuApp

final class MotionBERTPythonResolverTests: XCTestCase {
    func testResolveInvocationPrefersNamedCondaEnvironmentOverBaseCondaPrefix() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let homeDirectory = tempRoot.appendingPathComponent("home", isDirectory: true)
        let preferredPython = homeDirectory
            .appendingPathComponent("miniconda3/envs/mmpose-mac/bin/python", isDirectory: false)
        let basePython = tempRoot
            .appendingPathComponent("conda-base/bin/python", isDirectory: false)
        try makeExecutable(at: preferredPython)
        try makeExecutable(at: basePython)

        defer {
            try? FileManager.default.removeItem(at: tempRoot)
        }

        let invocation = VideoJointAngleAnalyzer.PythonPoseProcessRunner.resolveInvocation(
            preferredEnvironmentVariables: ["FRICU_MMPPOSE_PYTHON"],
            preferredCondaEnvironment: "mmpose-mac",
            environment: [
                "HOME": homeDirectory.path,
                "CONDA_PREFIX": tempRoot.appendingPathComponent("conda-base", isDirectory: true).path
            ]
        )

        XCTAssertEqual(invocation.executableURL.path, preferredPython.path)
    }

    func testResolveInvocationUsesCondaPrefixWhenPreferredCondaEnvironmentIsMissing() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let homeDirectory = tempRoot.appendingPathComponent("home", isDirectory: true)
        let basePython = tempRoot
            .appendingPathComponent("conda-base/bin/python", isDirectory: false)
        try makeExecutable(at: basePython)

        defer {
            try? FileManager.default.removeItem(at: tempRoot)
        }

        let invocation = VideoJointAngleAnalyzer.PythonPoseProcessRunner.resolveInvocation(
            preferredEnvironmentVariables: ["FRICU_MMPPOSE_PYTHON"],
            preferredCondaEnvironment: "mmpose-mac",
            environment: [
                "HOME": homeDirectory.path,
                "CONDA_PREFIX": tempRoot.appendingPathComponent("conda-base", isDirectory: true).path
            ]
        )

        XCTAssertEqual(invocation.executableURL.path, basePython.path)
    }

    func testResolveInvocationPrefersExplicitEnvironmentVariableOverNamedCondaEnvironment() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let homeDirectory = tempRoot.appendingPathComponent("home", isDirectory: true)
        let preferredPython = homeDirectory
            .appendingPathComponent("miniconda3/envs/mmpose-mac/bin/python", isDirectory: false)
        let explicitPython = tempRoot
            .appendingPathComponent("custom-python/bin/python", isDirectory: false)
        try makeExecutable(at: preferredPython)
        try makeExecutable(at: explicitPython)

        defer {
            try? FileManager.default.removeItem(at: tempRoot)
        }

        let invocation = VideoJointAngleAnalyzer.PythonPoseProcessRunner.resolveInvocation(
            preferredEnvironmentVariables: ["FRICU_MMPPOSE_PYTHON"],
            preferredCondaEnvironment: "mmpose-mac",
            environment: [
                "HOME": homeDirectory.path,
                "FRICU_MMPPOSE_PYTHON": explicitPython.path
            ]
        )

        XCTAssertEqual(invocation.executableURL.path, explicitPython.path)
    }

    func testResolveInvocationPrefersBundledRuntimeOverExplicitEnvironmentVariable() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fakeAppBundle = tempRoot.appendingPathComponent("fr-training.app", isDirectory: true)
        let bundledPython = fakeAppBundle
            .appendingPathComponent("Contents/Resources/\(MotionBERTRuntimeLocator.runtimeDirectoryName)/bin/python3", isDirectory: false)
        let explicitPython = tempRoot
            .appendingPathComponent("custom-python/bin/python", isDirectory: false)
        try makeExecutable(at: bundledPython)
        try makeExecutable(at: explicitPython)

        defer {
            try? FileManager.default.removeItem(at: tempRoot)
        }

        let bundle = try XCTUnwrap(Bundle(path: fakeAppBundle.path))
        let invocation = VideoJointAngleAnalyzer.PythonPoseProcessRunner.resolveInvocation(
            preferredEnvironmentVariables: ["FRICU_MEDIAPIPE_PYTHON"],
            preferredCondaEnvironment: "mmpose-mac",
            bundledRuntimeLocator: MotionBERTRuntimeLocator(),
            bundle: bundle,
            environment: [
                "FRICU_MEDIAPIPE_PYTHON": explicitPython.path
            ]
        )

        XCTAssertEqual(invocation.executableURL.path, bundledPython.path)
    }

    private func makeExecutable(at url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "#!/bin/sh\nexit 0\n".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }
}
