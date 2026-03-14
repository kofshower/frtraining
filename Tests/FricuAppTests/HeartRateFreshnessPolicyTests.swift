import Foundation
import XCTest
import FricuCore
@testable import FricuApp

final class HeartRateFreshnessPolicyTests: XCTestCase {
    func testResolvedHeartRateReturnsRecentValue() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let policy = HeartRateFreshnessPolicy(staleAfter: 5)

        let resolved = policy.resolvedHeartRate(
            liveHeartRateBPM: 148,
            lastUpdatedAt: now.addingTimeInterval(-4.5),
            now: now
        )

        XCTAssertEqual(resolved, 148)
    }

    func testResolvedHeartRateDropsExpiredOrInvalidValues() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let policy = HeartRateFreshnessPolicy(staleAfter: 5)

        XCTAssertNil(policy.resolvedHeartRate(liveHeartRateBPM: nil, lastUpdatedAt: now, now: now))
        XCTAssertNil(policy.resolvedHeartRate(liveHeartRateBPM: 0, lastUpdatedAt: now, now: now))
        XCTAssertNil(policy.resolvedHeartRate(liveHeartRateBPM: 148, lastUpdatedAt: nil, now: now))
        XCTAssertNil(policy.resolvedHeartRate(
            liveHeartRateBPM: 148,
            lastUpdatedAt: now.addingTimeInterval(-5.1),
            now: now
        ))
    }

    func testMonitorFreshHeartRateBPMUsesLastMeasurementTimestamp() {
        let monitor = HeartRateMonitorManager()
        let receivedAt = Date(timeIntervalSince1970: 1_700_000_100)
        let measurement = HeartRateMeasurement(
            flags: HeartRateMeasurementFlags(rawValue: 0),
            heartRateBPM: 83,
            valueIsUInt16: false,
            sensorContactSupported: false,
            sensorContactDetected: false,
            energyExpendedKJ: nil,
            rrIntervals1024: [],
            rrIntervalsMS: [],
            latestRRIntervalMS: nil
        )

        monitor.ingestHeartRateMeasurement(measurement, receivedAt: receivedAt)

        XCTAssertEqual(monitor.freshHeartRateBPM(at: receivedAt.addingTimeInterval(4.9)), 83)
        XCTAssertNil(monitor.freshHeartRateBPM(at: receivedAt.addingTimeInterval(5.1)))
    }
}
