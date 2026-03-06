import XCTest
@testable import FricuApp

/// Unit tests for validating supported video download URL inputs.
final class VideoDownloaderPageValidatorTests: XCTestCase {
    /// Verifies that a standard YouTube URL is accepted as valid input.
    func testValidateReturnsValidForYouTubeURL() {
        let validator = VideoDownloadRequestValidator()

        let result = validator.validate(rawText: "https://www.youtube.com/watch?v=abc123")

        guard case .valid(let platform, let normalizedURL) = result else {
            return XCTFail("Expected valid result for YouTube URL")
        }

        XCTAssertEqual(platform, .youtube)
        XCTAssertEqual(normalizedURL.absoluteString, "https://www.youtube.com/watch?v=abc123")
    }

    /// Verifies that a standard Instagram URL is accepted as valid input.
    func testValidateReturnsValidForInstagramURL() {
        let validator = VideoDownloadRequestValidator()

        let result = validator.validate(rawText: "https://instagram.com/reel/xyz/")

        guard case .valid(let platform, _) = result else {
            return XCTFail("Expected valid result for Instagram URL")
        }

        XCTAssertEqual(platform, .instagram)
    }

    /// Verifies empty and whitespace-only input is rejected.
    func testValidateReturnsEmptyInputForWhitespaceText() {
        let validator = VideoDownloadRequestValidator()

        let result = validator.validate(rawText: "   \n  ")

        XCTAssertEqual(result, .emptyInput)
    }

    /// Verifies malformed URL text is rejected.
    func testValidateReturnsInvalidURLForMalformedText() {
        let validator = VideoDownloadRequestValidator()

        let result = validator.validate(rawText: "not-a-url")

        XCTAssertEqual(result, .invalidURL)
    }

    /// Verifies non-supported platforms are rejected.
    func testValidateReturnsUnsupportedPlatformForOtherHosts() {
        let validator = VideoDownloadRequestValidator()

        let result = validator.validate(rawText: "https://vimeo.com/123456")

        XCTAssertEqual(result, .unsupportedPlatform)
    }

    /// Verifies subdomains of accepted hosts are considered valid.
    func testValidateAcceptsSubdomainForYouTube() {
        let validator = VideoDownloadRequestValidator()

        let result = validator.validate(rawText: "https://music.youtube.com/watch?v=abc")

        guard case .valid(let platform, _) = result else {
            return XCTFail("Expected valid result for YouTube subdomain")
        }

        XCTAssertEqual(platform, .youtube)
    }
}
