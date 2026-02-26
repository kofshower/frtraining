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

        let meanRR = rr.reduce(0, +) / Double(rr.count)

        let variance: Double
        if rr.count > 1 {
            let squares = rr.reduce(0) { partial, value in
                let delta = value - meanRR
                return partial + delta * delta
            }
            variance = squares / Double(rr.count - 1)
        } else {
            variance = 0
        }
        let sdnn = sqrt(max(0, variance))

        let diffs = zip(rr.dropFirst(), rr).map(-)
        let diffCount = diffs.count
        let rmssd: Double
        let pnn50: Double
        if diffCount > 0 {
            let sqMean = diffs.reduce(0) { partial, diff in
                partial + diff * diff
            } / Double(diffCount)
            rmssd = sqrt(max(0, sqMean))
            let nn50 = diffs.reduce(0) { partial, diff in
                partial + (abs(diff) > 50 ? 1 : 0)
            }
            pnn50 = 100.0 * Double(nn50) / Double(diffCount)
        } else {
            rmssd = 0
            pnn50 = 0
        }

        return HeartRateVariabilityMetrics(
            sampleCount: rr.count,
            meanRRMS: meanRR,
            rmssdMS: rmssd,
            sdnnMS: sdnn,
            pnn50Percent: pnn50,
            minRRMS: rr.min() ?? meanRR,
            maxRRMS: rr.max() ?? meanRR
        )
    }
}
