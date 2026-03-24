import Foundation
import XCTest
@testable import FricuApp

final class ActivityDetailDerivedCacheKeyTests: XCTestCase {
    func testCacheKeyStaysStableForSameActivityAndSamples() {
        let activity = makeActivity()
        let samples = makeSamples()

        let lhs = ActivityDetailDerivedCacheKey(activity: activity, sensorSamples: samples)
        let rhs = ActivityDetailDerivedCacheKey(activity: activity, sensorSamples: samples)

        XCTAssertEqual(lhs, rhs)
    }

    func testCacheKeyChangesWhenSensorTimelineChanges() {
        let activity = makeActivity()
        let lhs = ActivityDetailDerivedCacheKey(activity: activity, sensorSamples: makeSamples())
        let rhs = ActivityDetailDerivedCacheKey(
            activity: activity,
            sensorSamples: makeSamples() + [
                ActivitySensorSample(
                    timeSec: 3,
                    power: 260,
                    heartRate: 150,
                    altitudeMeters: nil,
                    balanceLeftPercent: nil,
                    balanceRightPercent: nil
                )
            ]
        )

        XCTAssertNotEqual(lhs, rhs)
    }

    func testCacheKeyChangesWhenIntervalsChange() {
        let samples = makeSamples()
        let base = makeActivity()
        var modified = base
        modified.intervals.append(
            IntervalEffort(name: "extra", durationSec: 90, targetPower: 280, actualPower: 275)
        )

        XCTAssertNotEqual(
            ActivityDetailDerivedCacheKey(activity: base, sensorSamples: samples),
            ActivityDetailDerivedCacheKey(activity: modified, sensorSamples: samples)
        )
    }

    private func makeActivity() -> Activity {
        Activity(
            id: UUID(uuidString: "2B0A16AB-64E4-4D94-A359-D53C7CC8A3A3")!,
            date: Date(timeIntervalSince1970: 1_742_000_000),
            sport: .cycling,
            athleteName: "tester",
            durationSec: 3600,
            distanceKm: 40,
            tss: 80,
            normalizedPower: 220,
            avgHeartRate: 145,
            intervals: [
                IntervalEffort(name: "steady", durationSec: 300, targetPower: 230, actualPower: 228)
            ],
            notes: ""
        )
    }

    private func makeSamples() -> [ActivitySensorSample] {
        [
            ActivitySensorSample(
                timeSec: 0,
                power: 210,
                heartRate: 140,
                altitudeMeters: nil,
                balanceLeftPercent: nil,
                balanceRightPercent: nil
            ),
            ActivitySensorSample(
                timeSec: 1,
                power: 215,
                heartRate: 142,
                altitudeMeters: nil,
                balanceLeftPercent: nil,
                balanceRightPercent: nil
            ),
            ActivitySensorSample(
                timeSec: 2,
                power: 220,
                heartRate: 144,
                altitudeMeters: nil,
                balanceLeftPercent: nil,
                balanceRightPercent: nil
            )
        ]
    }
}
