import XCTest
@testable import FricuApp

/// Unit tests for playback progress and timestamp formatting helpers.
final class VideoPlaybackProgressFormatterTests: XCTestCase {
    /// Verifies progress is computed correctly in standard playable range.
    func testClampedProgressReturnsExpectedRatio() {
        let progress = VideoPlaybackProgressFormatter.clampedProgress(currentSeconds: 30, durationSeconds: 120)

        XCTAssertEqual(progress, 0.25, accuracy: 0.0001)
    }

    /// Verifies progress falls back to zero when duration is invalid or unavailable.
    func testClampedProgressReturnsZeroForInvalidDuration() {
        XCTAssertEqual(
            VideoPlaybackProgressFormatter.clampedProgress(currentSeconds: 20, durationSeconds: 0),
            0
        )
        XCTAssertEqual(
            VideoPlaybackProgressFormatter.clampedProgress(currentSeconds: 20, durationSeconds: .infinity),
            0
        )
    }

    /// Verifies timestamp formatter renders minute-second labels for short videos.
    func testFormatTimestampReturnsMinuteSecondFormat() {
        XCTAssertEqual(VideoPlaybackProgressFormatter.formatTimestamp(seconds: 125), "02:05")
    }

    /// Verifies timestamp formatter renders hour labels for long media durations.
    func testFormatTimestampReturnsHourFormatWhenNeeded() {
        XCTAssertEqual(VideoPlaybackProgressFormatter.formatTimestamp(seconds: 3661), "1:01:01")
    }

    /// Verifies timestamp formatter safely handles negative edge-case values.
    func testFormatTimestampReturnsZeroForNegativeInput() {
        XCTAssertEqual(VideoPlaybackProgressFormatter.formatTimestamp(seconds: -1), "00:00")
    }

    /// Verifies seek time is clamped to duration bounds.
    func testSeekTimeClampsProgressWithinBounds() {
        XCTAssertEqual(
            VideoPlaybackProgressFormatter.seekTime(progress: -0.5, durationSeconds: 100),
            0,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            VideoPlaybackProgressFormatter.seekTime(progress: 1.5, durationSeconds: 100),
            100,
            accuracy: 0.0001
        )
    }
}
