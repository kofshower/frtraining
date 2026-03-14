import XCTest
@testable import FricuApp

final class BikeComputerLightRendererTests: XCTestCase {
    func testTimeSeriesLineDashPatternEmptyWhenSolid() {
        XCTAssertEqual(LightTimeSeriesRendererStyle.lineDashPattern(dashed: false), [])
    }

    func testTimeSeriesLineDashPatternMatchesRendererToken() {
        XCTAssertEqual(LightTimeSeriesRendererStyle.lineDashPattern(dashed: true), [5, 4])
    }

    func testTimeSeriesLineStrokeStyleUsesRoundedCapsAndDashedPattern() {
        let style = LightTimeSeriesRendererStyle.lineStrokeStyle(width: 2.1, dashed: true)
        XCTAssertEqual(style.lineWidth, 2.1, accuracy: 0.001)
        XCTAssertEqual(style.dash, [5, 4])
        XCTAssertEqual(style.lineCap, .round)
        XCTAssertEqual(style.lineJoin, .round)
    }

    func testScatterBandRectMapsInteriorBandIntoPlotCoordinates() {
        let band = LightScatterBand(
            id: "z3",
            lowerX: 100,
            upperX: 200,
            lowerY: 80,
            upperY: 140,
            tint: .orange,
            opacity: 0.16
        )

        let rect = LightScatterRendererLayout.bandRect(
            for: band,
            size: CGSize(width: 300, height: 200),
            xDomain: 0...500,
            yDomain: 50...150
        )

        XCTAssertEqual(rect.origin.x, 63.6, accuracy: 0.2)
        XCTAssertEqual(rect.origin.y, 26.4, accuracy: 0.2)
        XCTAssertEqual(rect.width, 57.6, accuracy: 0.2)
        XCTAssertEqual(rect.height, 110.4, accuracy: 0.2)
    }

    func testScatterBandRectClampsToChartBounds() {
        let band = LightScatterBand(
            id: "overflow",
            lowerX: -50,
            upperX: 700,
            lowerY: 10,
            upperY: 300,
            tint: .red,
            opacity: 0.12
        )

        let rect = LightScatterRendererLayout.bandRect(
            for: band,
            size: CGSize(width: 300, height: 200),
            xDomain: 0...500,
            yDomain: 50...150
        )

        XCTAssertEqual(rect.origin.x, 6, accuracy: 0.001)
        XCTAssertEqual(rect.origin.y, 8, accuracy: 0.001)
        XCTAssertEqual(rect.width, 288, accuracy: 0.001)
        XCTAssertEqual(rect.height, 184, accuracy: 0.001)
    }

    func testTimeSeriesSegmentsSplitOnNonFiniteValues() {
        let base = Date(timeIntervalSinceReferenceDate: 10_000)
        let points = [
            LightTimeSeriesPoint(timestamp: base, value: 10),
            LightTimeSeriesPoint(timestamp: base.addingTimeInterval(60), value: 11),
            LightTimeSeriesPoint(timestamp: base.addingTimeInterval(120), value: .nan),
            LightTimeSeriesPoint(timestamp: base.addingTimeInterval(180), value: 13),
            LightTimeSeriesPoint(timestamp: base.addingTimeInterval(240), value: 14)
        ]

        let segments = LightTimeSeriesLayout.segments(
            for: points,
            in: CGSize(width: 320, height: 180),
            yDomain: 0...20
        )

        XCTAssertEqual(segments.count, 2)
        XCTAssertEqual(segments[0].count, 2)
        XCTAssertEqual(segments[1].count, 2)
    }

    func testTimeSeriesSegmentsSplitAcrossLargeTimestampGaps() {
        let base = Date(timeIntervalSinceReferenceDate: 20_000)
        let points = [
            LightTimeSeriesPoint(timestamp: base, value: 8),
            LightTimeSeriesPoint(timestamp: base.addingTimeInterval(60), value: 9),
            LightTimeSeriesPoint(timestamp: base.addingTimeInterval(120), value: 10),
            LightTimeSeriesPoint(timestamp: base.addingTimeInterval(600), value: 11),
            LightTimeSeriesPoint(timestamp: base.addingTimeInterval(660), value: 12)
        ]

        let segments = LightTimeSeriesLayout.segments(
            for: points,
            in: CGSize(width: 320, height: 180),
            yDomain: 0...20
        )

        XCTAssertEqual(segments.count, 2)
        XCTAssertEqual(segments[0].count, 3)
        XCTAssertEqual(segments[1].count, 2)
    }
}
