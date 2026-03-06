import XCTest
@testable import FricuApp

/// Unit tests for localized playback compatibility explanations.
final class VideoPlaybackCompatibilityAdvisorTests: XCTestCase {
    private let languageStorageKey = AppLanguageOption.storageKey

    override func setUp() {
        super.setUp()
        UserDefaults.standard.set(AppLanguageOption.english.rawValue, forKey: languageStorageKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: languageStorageKey)
        super.tearDown()
    }

    /// Verifies that the generic message explains system decoder limits without media details.
    func testLocalUnplayableReasonWithoutDetailsIncludesSystemDecoderLimit() {
        let advisor = VideoPlaybackCompatibilityAdvisor()

        let reason = advisor.localUnplayableReason(details: nil)

        XCTAssertTrue(reason.contains("cannot decode this media format"))
        XCTAssertTrue(reason.contains("bundled open-source decoder pipeline"))
    }

    /// Verifies that codec/container diagnostics are included when probe details are available.
    func testLocalUnplayableReasonWithDetailsIncludesCodecSummary() {
        let advisor = VideoPlaybackCompatibilityAdvisor()
        let details = MediaProbeDetails(
            container: "matroska",
            videoCodec: "vp9",
            audioCodec: "opus",
            pixelFormat: "yuv420p",
            resolution: "1920x1080"
        )

        let reason = advisor.localUnplayableReason(details: details)

        XCTAssertTrue(reason.contains("container matroska"))
        XCTAssertTrue(reason.contains("video vp9 (1920x1080, yuv420p)"))
        XCTAssertTrue(reason.contains("audio opus"))
    }

    /// Verifies that generated reason remains non-empty for edge-case unknown metadata values.
    func testLocalUnplayableReasonWithUnknownDetailsStillReturnsReadableText() {
        let advisor = VideoPlaybackCompatibilityAdvisor()
        let details = MediaProbeDetails(
            container: "unknown",
            videoCodec: "unknown",
            audioCodec: "unknown",
            pixelFormat: "unknown",
            resolution: "unknown"
        )

        let reason = advisor.localUnplayableReason(details: details)

        XCTAssertFalse(reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
}
