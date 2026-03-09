import XCTest
@testable import FricuApp

final class AthleteIdentityNormalizerTests: XCTestCase {
    func testCanonicalNameStripsLegacySuffixWithoutSpace() {
        XCTAssertEqual(AthleteIdentityNormalizer.canonicalName("柴君钧---来自Fricu"), "柴君钧")
    }

    func testCanonicalNameStripsLegacySuffixWithSpace() {
        XCTAssertEqual(AthleteIdentityNormalizer.canonicalName("范芮---来自 Fricu"), "范芮")
    }

    func testExtractNameFromLegacyNotesSupportsTrainerRideText() {
        let notes = "柴君钧---来自Fricu · Trainer ride · 2026-03-07T00:00:00"
        XCTAssertEqual(AthleteIdentityNormalizer.extractName(fromLegacyText: notes), "柴君钧")
    }

    func testPanelIDKeepsAthleteConsistentAcrossLegacyAndCleanNames() {
        let clean = AthleteIdentityNormalizer.panelID(from: "柴君钧")
        let legacy = AthleteIdentityNormalizer.panelID(from: "柴君钧---来自Fricu")
        XCTAssertEqual(clean, legacy)
    }

    func testDisplayNameFallsBackWhenNameUnavailable() {
        XCTAssertEqual(
            AthleteIdentityNormalizer.displayName(rawName: nil, notes: "", fallback: "未分配运动员"),
            "未分配运动员"
        )
    }
}
