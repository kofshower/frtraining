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

protocol ActivityBalanceClassifying {
    func classify(_ deviationFromCenter: Double) -> ActivityBalanceSummary.Verdict
}

struct ThresholdActivityBalanceClassifier: ActivityBalanceClassifying {
    let balancedDeviationThreshold: Double
    let mildDeviationThreshold: Double

    func classify(_ deviationFromCenter: Double) -> ActivityBalanceSummary.Verdict {
        if deviationFromCenter <= balancedDeviationThreshold {
            return .balanced
        }
        if deviationFromCenter <= mildDeviationThreshold {
            return .mildImbalance
        }
        return .imbalanced
    }
}

final class ActivityBalanceSummarizer {
    private struct Accumulator {
        var sampleCount: Int = 0
        var totalLeft: Double = 0
        var endLeft: Double = 0

        mutating func append(left: Double) {
            sampleCount += 1
            totalLeft += left
            endLeft = left
        }
    }

    private let classifier: ActivityBalanceClassifying

    init(classifier: ActivityBalanceClassifying) {
        self.classifier = classifier
    }

    func summary(from samples: [ActivitySensorSample]) -> ActivityBalanceSummary? {
        var accumulator = Accumulator()

        for sample in samples {
            guard let pair = Self.normalizePair(left: sample.balanceLeftPercent, right: sample.balanceRightPercent) else {
                continue
            }
            accumulator.append(left: pair.left)
        }

        guard accumulator.sampleCount > 0 else { return nil }

        let averageLeft = accumulator.totalLeft / Double(accumulator.sampleCount)
        let averageRight = 100.0 - averageLeft
        let endLeft = accumulator.endLeft
        let endRight = 100.0 - endLeft

        let averageDeviation = abs(averageLeft - 50.0)
        let endDeviation = abs(endLeft - 50.0)
        let verdict = classifier.classify(max(averageDeviation, endDeviation))

        return ActivityBalanceSummary(
            sampleCount: accumulator.sampleCount,
            averageLeftPercent: averageLeft,
            averageRightPercent: averageRight,
            endLeftPercent: endLeft,
            endRightPercent: endRight,
            averageDeviationFromCenter: averageDeviation,
            endDeviationFromCenter: endDeviation,
            verdict: verdict
        )
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

enum ActivityBalanceAnalyzer {
    static let balancedDeviationThreshold = 2.0
    static let mildDeviationThreshold = 4.0

    private static let defaultSummarizer = ActivityBalanceSummarizer(
        classifier: ThresholdActivityBalanceClassifier(
            balancedDeviationThreshold: balancedDeviationThreshold,
            mildDeviationThreshold: mildDeviationThreshold
        )
    )

    static func summary(from samples: [ActivitySensorSample]) -> ActivityBalanceSummary? {
        defaultSummarizer.summary(from: samples)
    }

    static func classify(_ deviationFromCenter: Double) -> ActivityBalanceSummary.Verdict {
        ThresholdActivityBalanceClassifier(
            balancedDeviationThreshold: balancedDeviationThreshold,
            mildDeviationThreshold: mildDeviationThreshold
        ).classify(deviationFromCenter)
    }
}
