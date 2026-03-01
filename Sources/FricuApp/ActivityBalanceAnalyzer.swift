import Foundation

struct ActivityBalanceSummary: Equatable {
    enum Verdict: String, Equatable {
        case balanced
        case mildImbalance
        case imbalanced

        var label: String {
            switch self {
            case .balanced:
                return "平衡"
            case .mildImbalance:
                return "轻度偏移"
            case .imbalanced:
                return "明显偏移"
            }
        }
    }

    let sampleCount: Int
    let averageLeftPercent: Double
    let averageRightPercent: Double
    let endLeftPercent: Double
    let endRightPercent: Double
    let averageDeviationFromCenter: Double
    let endDeviationFromCenter: Double
    let verdict: Verdict
}

enum ActivityBalanceAnalyzer {
    static let balancedDeviationThreshold = 2.0
    static let mildDeviationThreshold = 4.0

    static func summary(from samples: [ActivitySensorSample]) -> ActivityBalanceSummary? {
        let pairs = samples.compactMap { normalizePair(left: $0.balanceLeftPercent, right: $0.balanceRightPercent) }
        guard !pairs.isEmpty else { return nil }

        let avgLeft = pairs.map(\.left).reduce(0, +) / Double(pairs.count)
        let avgRight = 100.0 - avgLeft
        guard let end = pairs.last else { return nil }

        let avgDeviation = abs(avgLeft - 50.0)
        let endDeviation = abs(end.left - 50.0)
        let verdict = classify(max(avgDeviation, endDeviation))

        return ActivityBalanceSummary(
            sampleCount: pairs.count,
            averageLeftPercent: avgLeft,
            averageRightPercent: avgRight,
            endLeftPercent: end.left,
            endRightPercent: end.right,
            averageDeviationFromCenter: avgDeviation,
            endDeviationFromCenter: endDeviation,
            verdict: verdict
        )
    }

    static func classify(_ deviationFromCenter: Double) -> ActivityBalanceSummary.Verdict {
        if deviationFromCenter <= balancedDeviationThreshold {
            return .balanced
        }
        if deviationFromCenter <= mildDeviationThreshold {
            return .mildImbalance
        }
        return .imbalanced
    }

    private static func normalizePair(left: Double?, right: Double?) -> (left: Double, right: Double)? {
        guard let left, let right else { return nil }
        guard left.isFinite, right.isFinite else { return nil }
        guard left >= 0, right >= 0 else { return nil }
        let sum = left + right
        guard sum > 0 else { return nil }

        let normalizedLeft = (left / sum) * 100.0
        let normalizedRight = 100.0 - normalizedLeft
        guard normalizedLeft >= 0, normalizedLeft <= 100 else { return nil }
        return (normalizedLeft, normalizedRight)
    }
}
