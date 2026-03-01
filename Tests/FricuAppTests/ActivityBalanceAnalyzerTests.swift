import Foundation
import XCTest
@testable import FricuApp

final class ActivityBalanceAnalyzerTests: XCTestCase {
    func testSummaryBalancedWhenAverageAndFinishCloseToCenter() throws {
        let samples: [ActivitySensorSample] = [
            .init(timeSec: 0, power: 180, heartRate: 130, altitudeMeters: nil, balanceLeftPercent: 50, balanceRightPercent: 50),
            .init(timeSec: 60, power: 190, heartRate: 135, altitudeMeters: nil, balanceLeftPercent: 51, balanceRightPercent: 49),
            .init(timeSec: 120, power: 200, heartRate: 140, altitudeMeters: nil, balanceLeftPercent: 50, balanceRightPercent: 50)
        ]

        let summary = try XCTUnwrap(ActivityBalanceAnalyzer.summary(from: samples))
        XCTAssertEqual(summary.sampleCount, 3)
        XCTAssertEqual(summary.averageLeftPercent, 50.3333, accuracy: 0.001)
        XCTAssertEqual(summary.endLeftPercent, 50, accuracy: 0.001)
        XCTAssertEqual(summary.verdict, .balanced)
    }

    func testSummaryDetectsImbalance() throws {
        let samples: [ActivitySensorSample] = [
            .init(timeSec: 0, power: 180, heartRate: 130, altitudeMeters: nil, balanceLeftPercent: 57, balanceRightPercent: 43),
            .init(timeSec: 60, power: 190, heartRate: 135, altitudeMeters: nil, balanceLeftPercent: 56, balanceRightPercent: 44),
            .init(timeSec: 120, power: 200, heartRate: 140, altitudeMeters: nil, balanceLeftPercent: 58, balanceRightPercent: 42)
        ]

        let summary = try XCTUnwrap(ActivityBalanceAnalyzer.summary(from: samples))
        XCTAssertEqual(summary.averageLeftPercent, 57, accuracy: 0.001)
        XCTAssertEqual(summary.endLeftPercent, 58, accuracy: 0.001)
        XCTAssertEqual(summary.verdict, .imbalanced)
    }

    func testSummaryNormalizesNonHundredPairs() throws {
        let samples: [ActivitySensorSample] = [
            .init(timeSec: 0, power: 200, heartRate: 140, altitudeMeters: nil, balanceLeftPercent: 520, balanceRightPercent: 480)
        ]

        let summary = try XCTUnwrap(ActivityBalanceAnalyzer.summary(from: samples))
        XCTAssertEqual(summary.averageLeftPercent, 52, accuracy: 0.001)
        XCTAssertEqual(summary.averageRightPercent, 48, accuracy: 0.001)
        XCTAssertEqual(summary.verdict, .balanced)
    }

    func testFitWriterAndParserRoundTripLeftRightBalance() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let end = start.addingTimeInterval(120)
        let rideSamples: [LiveRideSample] = [
            .init(
                timestamp: start,
                powerWatts: 200,
                heartRateBPM: 140,
                cadenceRPM: 90,
                speedKPH: 32,
                distanceMeters: 0,
                leftBalancePercent: 52,
                rightBalancePercent: 48
            ),
            .init(
                timestamp: end,
                powerWatts: 210,
                heartRateBPM: 145,
                cadenceRPM: 91,
                speedKPH: 33,
                distanceMeters: 1000,
                leftBalancePercent: 53,
                rightBalancePercent: 47
            )
        ]

        let summary = LiveRideSummary(
            startDate: start,
            endDate: end,
            sport: .cycling,
            totalElapsedSec: 120,
            totalTimerSec: 120,
            totalDistanceMeters: 1000,
            averageHeartRate: 143,
            maxHeartRate: 150,
            averagePower: 205,
            maxPower: 220,
            normalizedPower: 208
        )

        let fitData = LiveRideFITWriter.export(samples: rideSamples, summary: summary)
        let parsed = try FITActivityParser.parseSensorSamples(data: fitData)
        XCTAssertEqual(parsed.count, 2)
        XCTAssertEqual(try XCTUnwrap(parsed[0].balanceLeftPercent), 52, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(parsed[0].balanceRightPercent), 48, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(parsed[1].balanceLeftPercent), 53, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(parsed[1].balanceRightPercent), 47, accuracy: 0.001)
    }
}
