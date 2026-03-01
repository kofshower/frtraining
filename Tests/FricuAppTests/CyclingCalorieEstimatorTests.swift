import Foundation
import XCTest
@testable import FricuApp

final class CyclingCalorieEstimatorTests: XCTestCase {
    func testEstimateStepReturnsZeroWhenPowerOrDurationMissing() {
        let zeroPower = CyclingCalorieEstimator.estimateStep(powerWatts: 0, durationSec: 60, ftpWatts: 260)
        XCTAssertEqual(zeroPower.mechanicalWorkKJ, 0)
        XCTAssertEqual(zeroPower.metabolicKCal, 0)

        let zeroDuration = CyclingCalorieEstimator.estimateStep(powerWatts: 250, durationSec: 0, ftpWatts: 260)
        XCTAssertEqual(zeroDuration.mechanicalWorkKJ, 0)
        XCTAssertEqual(zeroDuration.metabolicKCal, 0)
    }

    func testEstimateStepOneHourAtTwoHundredWattsMatchesExpectedRange() {
        let estimate = CyclingCalorieEstimator.estimateStep(powerWatts: 200, durationSec: 3600, ftpWatts: 260)

        XCTAssertEqual(estimate.mechanicalWorkKJ, 720, accuracy: 0.001)
        XCTAssertEqual(estimate.metabolicKCal, 733.4, accuracy: 3.0)
        XCTAssertEqual(estimate.grossEfficiency, 0.2346, accuracy: 0.002)
    }

    func testGrossEfficiencyIncreasesWithRelativeIntensity() {
        let easy = CyclingCalorieEstimator.grossEfficiency(powerWatts: 120, ftpWatts: 260)
        let threshold = CyclingCalorieEstimator.grossEfficiency(powerWatts: 260, ftpWatts: 260)
        let supra = CyclingCalorieEstimator.grossEfficiency(powerWatts: 360, ftpWatts: 260)

        XCTAssertGreaterThan(threshold, easy)
        XCTAssertGreaterThan(supra, threshold)
        XCTAssertLessThanOrEqual(supra, 0.25)
        XCTAssertGreaterThanOrEqual(easy, 0.20)
    }

    func testGrossEfficiencyUsesSafeFtpFloor() {
        let withInvalidFTP = CyclingCalorieEstimator.estimateStep(powerWatts: 180, durationSec: 1800, ftpWatts: 0)
        let withFloorFTP = CyclingCalorieEstimator.estimateStep(powerWatts: 180, durationSec: 1800, ftpWatts: 120)

        XCTAssertEqual(withInvalidFTP.mechanicalWorkKJ, withFloorFTP.mechanicalWorkKJ, accuracy: 0.0001)
        XCTAssertEqual(withInvalidFTP.metabolicKCal, withFloorFTP.metabolicKCal, accuracy: 0.0001)
        XCTAssertEqual(withInvalidFTP.grossEfficiency, withFloorFTP.grossEfficiency, accuracy: 0.0001)
    }
}
