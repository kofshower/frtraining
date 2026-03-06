import XCTest
@testable import FricuApp

/// Unit tests for selecting the embedded playback engine.
final class EmbeddedPlaybackEngineSelectorTests: XCTestCase {
    /// Verifies libVLC is selected on macOS when the runtime has VLCKit symbols.
    func testPreferredEngineSelectsLibVLCOnMacOSWhenAvailable() {
        let selector = EmbeddedPlaybackEngineSelector()

        let selected = selector.preferredEngine(isMacOSPlatform: true, isLibVLCAvailable: true)

        XCTAssertEqual(selected, .libVLC)
    }

    /// Verifies AVPlayer is selected on macOS when libVLC is not linked.
    func testPreferredEngineFallsBackToAVPlayerWhenLibVLCMissingOnMacOS() {
        let selector = EmbeddedPlaybackEngineSelector()

        let selected = selector.preferredEngine(isMacOSPlatform: true, isLibVLCAvailable: false)

        XCTAssertEqual(selected, .avPlayer)
    }

    /// Verifies non-macOS platforms always use AVPlayer regardless of libVLC availability.
    func testPreferredEngineUsesAVPlayerOutsideMacOSBoundaryCase() {
        let selector = EmbeddedPlaybackEngineSelector()

        let selected = selector.preferredEngine(isMacOSPlatform: false, isLibVLCAvailable: true)

        XCTAssertEqual(selected, .avPlayer)
    }
}
