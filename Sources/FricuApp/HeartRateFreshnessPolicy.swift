import Foundation

struct HeartRateFreshnessPolicy {
    let staleAfter: TimeInterval

    static let recording = HeartRateFreshnessPolicy(staleAfter: 5)

    func resolvedHeartRate(
        liveHeartRateBPM: Int?,
        lastUpdatedAt: Date?,
        now: Date
    ) -> Int? {
        guard let liveHeartRateBPM, liveHeartRateBPM > 0 else { return nil }
        guard let lastUpdatedAt else { return nil }
        let age = max(0, now.timeIntervalSince(lastUpdatedAt))
        guard age <= staleAfter else { return nil }
        return liveHeartRateBPM
    }
}
