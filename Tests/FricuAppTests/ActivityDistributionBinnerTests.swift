import XCTest
@testable import FricuApp

final class ActivityDistributionBinnerTests: XCTestCase {
    func testNarrowIntegerRangeDoesNotCreateInvertedLabels() {
        let bins = ActivityDistributionBinner.buildBins(
            values: [83.0, 83.1, 83.2, 83.4, 83.7, 83.9],
            requestedBinCount: 12
        )

        XCTAssertFalse(bins.isEmpty)
        XCTAssertLessThanOrEqual(bins.count, 1)
        XCTAssertEqual(bins.first?.rangeLabel, "83-84")
        XCTAssertEqual(bins.first?.sampleCount, 6)
    }

    func testFlatSeriesCollapsesIntoSingleBin() {
        let bins = ActivityDistributionBinner.buildBins(
            values: [83.0, 83.0, 83.0, 83.0],
            requestedBinCount: 12
        )

        XCTAssertEqual(bins.count, 1)
        XCTAssertEqual(bins[0].lowerBound, 83)
        XCTAssertEqual(bins[0].upperBound, 83)
        XCTAssertEqual(bins[0].rangeLabel, "83")
        XCTAssertEqual(bins[0].sampleCount, 4)
        XCTAssertEqual(bins[0].fraction, 1.0, accuracy: 0.0001)
    }
}
