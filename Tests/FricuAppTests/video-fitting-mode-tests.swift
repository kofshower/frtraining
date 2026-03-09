import AVFoundation
import XCTest
@testable import FricuApp

/// Unit tests for embedded video fitting mode behavior.
final class VideoFittingModeTests: XCTestCase {
    /// Verifies fitting mode maps to expected AVPlayer gravity values.
    func testFittingModeMapsToExpectedAVVideoGravity() {
        XCTAssertEqual(VideoFittingMode.fit.avVideoGravity, .resizeAspect)
        XCTAssertEqual(VideoFittingMode.fill.avVideoGravity, .resizeAspectFill)
        XCTAssertEqual(VideoFittingMode.stretch.avVideoGravity, .resize)
    }

    /// Verifies non-fit modes explicitly require AVPlayer rendering path.
    func testRequiresAVPlayerMatchesExpectedModes() {
        XCTAssertFalse(VideoFittingMode.fit.requiresAVPlayer)
        XCTAssertTrue(VideoFittingMode.fill.requiresAVPlayer)
        XCTAssertTrue(VideoFittingMode.stretch.requiresAVPlayer)
    }
}
