import Foundation

public enum CoreSport: String, CaseIterable, Codable {
    case cycling
    case running
    case swimming
    case strength
}

public struct CoreLoadPoint: Equatable {
    public let dayIndex: Int
    public let tss: Double
    public let ctl: Double
    public let atl: Double
    public let tsb: Double

    public init(dayIndex: Int, tss: Double, ctl: Double, atl: Double, tsb: Double) {
        self.dayIndex = dayIndex
        self.tss = tss
        self.ctl = ctl
        self.atl = atl
        self.tsb = tsb
    }
}

public enum TrainingLoadMath {
    public static func nextCTL(previous: Double, tss: Double, tauDays: Double = 42.0) -> Double {
        guard tauDays > 0 else { return previous }
        return previous + (tss - previous) / tauDays
    }

    public static func nextATL(previous: Double, tss: Double, tauDays: Double = 7.0) -> Double {
        guard tauDays > 0 else { return previous }
        return previous + (tss - previous) / tauDays
    }

    public static func nextTSB(currentCTL: Double, currentATL: Double) -> Double {
        currentCTL - currentATL
    }

    public static func buildSeries(
        dailyTSS: [Double],
        seedCTL: Double = 45.0,
        seedATL: Double = 50.0,
        ctlTauDays: Double = 42.0,
        atlTauDays: Double = 7.0
    ) -> [CoreLoadPoint] {
        var ctl = seedCTL
        var atl = seedATL
        var result: [CoreLoadPoint] = []
        result.reserveCapacity(dailyTSS.count)

        for (idx, tss) in dailyTSS.enumerated() {
            ctl = nextCTL(previous: ctl, tss: tss, tauDays: ctlTauDays)
            atl = nextATL(previous: atl, tss: tss, tauDays: atlTauDays)
            result.append(
                CoreLoadPoint(
                    dayIndex: idx,
                    tss: tss,
                    ctl: ctl,
                    atl: atl,
                    tsb: nextTSB(currentCTL: ctl, currentATL: atl)
                )
            )
        }

        return result
    }
}

public enum ReadinessMath {
    public static func score(tsb: Double, hrvToday: Double, hrvBaseline: Double) -> Int {
        let baseline = max(1.0, hrvBaseline)
        let ratio = hrvToday / baseline
        var value = 70.0

        if tsb < -25 { value -= 30 }
        else if tsb < -15 { value -= 18 }
        else if tsb < -5 { value -= 8 }
        else if tsb <= 15 { value += 8 }
        else { value += 2 }

        if ratio < 0.85 { value -= 24 }
        else if ratio < 0.92 { value -= 12 }
        else if ratio > 1.08 { value += 4 }

        if value < 1 { return 1 }
        if value > 100 { return 100 }
        return Int(value.rounded())
    }

    public static func todayFocus(tsb: Double, hrvToday: Double, hrvBaseline: Double) -> String {
        let ratio = hrvToday / max(1.0, hrvBaseline)
        if ratio < 0.9 || tsb < -20 {
            return "Recovery"
        }
        if tsb <= 10 {
            return "Quality"
        }
        return "Fresh-Key"
    }
}

public enum DecouplingMath {
    public static func percent(efFirst: Double, efSecond: Double) -> Double? {
        guard efFirst > 0 else { return nil }
        return ((efFirst - efSecond) / efFirst) * 100.0
    }

    public static func qualityBand(decouplingPercent: Double?) -> String {
        guard let value = decouplingPercent else { return "N/A" }
        let absV = abs(value)
        if absV < 5 { return "Excellent" }
        if absV < 10 { return "Good" }
        if absV < 15 { return "Watch" }
        return "Risk"
    }
}

public enum PowerCurveMath {
    public static func peakAverage(samples: [Int], windowSec: Int) -> Int? {
        guard windowSec > 0, samples.count >= windowSec else { return nil }
        var rolling = 0
        var best = 0

        for idx in samples.indices {
            rolling += samples[idx]
            if idx >= windowSec {
                rolling -= samples[idx - windowSec]
            }
            if idx + 1 >= windowSec {
                let avg = Int((Double(rolling) / Double(windowSec)).rounded())
                if avg > best {
                    best = avg
                }
            }
        }

        return best
    }
}
