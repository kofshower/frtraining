import XCTest
@testable import FricuApp

final class AthleteIdentityNormalizerTests: XCTestCase {
    func testCanonicalNameTrimsWhitespace() {
        XCTAssertEqual(AthleteIdentityNormalizer.canonicalName("  柴君钧  "), "柴君钧")
    }

    func testCanonicalNameKeepsLiteralName() {
        XCTAssertEqual(AthleteIdentityNormalizer.canonicalName("柴君钧---来自Fricu"), "柴君钧---来自Fricu")
    }

    func testPanelIDLowercasesCanonicalName() {
        XCTAssertEqual(AthleteIdentityNormalizer.panelID(from: "AthleteA"), "athletea")
    }

    func testDisplayNameFallsBackWhenNameUnavailable() {
        XCTAssertEqual(
            AthleteIdentityNormalizer.displayName(rawName: nil, fallback: "未分配运动员"),
            "未分配运动员"
        )
    }
}
