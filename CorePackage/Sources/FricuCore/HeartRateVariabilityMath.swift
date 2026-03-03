import Foundation

public struct HeartRateVariabilityMetrics: Equatable, Sendable {
    public let sampleCount: Int
    public let meanRRMS: Double
    public let rmssdMS: Double
    public let sdnnMS: Double
    public let pnn50Percent: Double
    public let minRRMS: Double
    public let maxRRMS: Double

    public init(
        sampleCount: Int,
        meanRRMS: Double,
        rmssdMS: Double,
        sdnnMS: Double,
        pnn50Percent: Double,
        minRRMS: Double,
        maxRRMS: Double
    ) {
        self.sampleCount = sampleCount
        self.meanRRMS = meanRRMS
        self.rmssdMS = rmssdMS
        self.sdnnMS = sdnnMS
        self.pnn50Percent = pnn50Percent
        self.minRRMS = minRRMS
        self.maxRRMS = maxRRMS
    }
}

public enum HeartRateVariabilityMath {
    private struct RRRunningStats {
        var count = 0
        var sum = 0.0
        var sumSquares = 0.0
        var diffSquareSum = 0.0
        var nn50Count = 0
        var minValue = Double.greatestFiniteMagnitude
        var maxValue = -Double.greatestFiniteMagnitude
        var previous: Double?

        mutating func append(_ value: Double) {
            count += 1
            sum += value
            sumSquares += value * value
            minValue = Swift.min(minValue, value)
            maxValue = Swift.max(maxValue, value)

            if let previous {
                let diff = value - previous
                diffSquareSum += diff * diff
                if abs(diff) > 50 {
                    nn50Count += 1
                }
            }
            previous = value
        }

        var mean: Double {
            guard count > 0 else { return 0 }
            return sum / Double(count)
        }

        var sampleVariance: Double {
            guard count > 1 else { return 0 }
            let mean = self.mean
            let centeredSquareSum = sumSquares - Double(count) * mean * mean
            return Swift.max(0, centeredSquareSum / Double(count - 1))
        }

        var min: Double { count > 0 ? minValue : 0 }
        var max: Double { count > 0 ? maxValue : 0 }
    }

    public static func sanitizeRRIntervals(
        _ rrIntervalsMS: [Double],
        minRRMS: Double = 300,
        maxRRMS: Double = 2000,
        maxAdjacentDeltaMS: Double = 250
    ) -> [Double] {
        guard !rrIntervalsMS.isEmpty else { return [] }
        var clean: [Double] = []
        clean.reserveCapacity(rrIntervalsMS.count)

        for rr in rrIntervalsMS {
            guard rr.isFinite, rr >= minRRMS, rr <= maxRRMS else { continue }
            if let last = clean.last, abs(rr - last) > maxAdjacentDeltaMS {
                continue
            }
            clean.append(rr)
        }
        return clean
    }

    public static func metrics(
        rrIntervalsMS: [Double],
        minimumCount: Int = 5
    ) -> HeartRateVariabilityMetrics? {
        let rr = sanitizeRRIntervals(rrIntervalsMS)
        guard rr.count >= minimumCount else { return nil }
        guard !rr.isEmpty else {
            return HeartRateVariabilityMetrics(
                sampleCount: 0,
                meanRRMS: 0,
                rmssdMS: 0,
                sdnnMS: 0,
                pnn50Percent: 0,
                minRRMS: 0,
                maxRRMS: 0
            )
        }

        var stats = RRRunningStats()
        for interval in rr {
            stats.append(interval)
        }

        let meanRR = stats.mean
        let sdnn = sqrt(stats.sampleVariance)
        let diffCount = max(0, stats.count - 1)
        let rmssd = diffCount > 0 ? sqrt(Swift.max(0, stats.diffSquareSum / Double(diffCount))) : 0
        let pnn50 = diffCount > 0 ? (100.0 * Double(stats.nn50Count) / Double(diffCount)) : 0

        return HeartRateVariabilityMetrics(
            sampleCount: stats.count,
            meanRRMS: meanRR,
            rmssdMS: rmssd,
            sdnnMS: sdnn,
            pnn50Percent: pnn50,
            minRRMS: stats.min,
            maxRRMS: stats.max
        )
    }
}
