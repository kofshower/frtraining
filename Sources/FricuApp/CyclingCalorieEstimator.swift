import Foundation

protocol GrossEfficiencyModel {
    func efficiency(powerWatts: Double, ftpWatts: Double) -> Double
}

struct ExponentialGrossEfficiencyModel: GrossEfficiencyModel {
    func efficiency(powerWatts: Double, ftpWatts: Double) -> Double {
        let intensity = powerWatts / ftpWatts

        // Cycling gross efficiency usually sits around 20%-25% and rises with intensity.
        let efficiency = 0.20 + 0.05 * (1.0 - exp(-intensity / 0.65))
        return min(max(efficiency, 0.20), 0.25)
    }
}

final class CyclingCalorieEngine {
    static let joulesPerKilocalorie = 4_184.0

    struct StepEstimate {
        let mechanicalWorkKJ: Double
        let metabolicKCal: Double
        let grossEfficiency: Double
    }

    private let efficiencyModel: GrossEfficiencyModel

    init(efficiencyModel: GrossEfficiencyModel) {
        self.efficiencyModel = efficiencyModel
    }

    func estimateStep(
        powerWatts: Double,
        durationSec: TimeInterval,
        ftpWatts: Int
    ) -> StepEstimate {
        let safePower = max(0, powerWatts)
        let safeDuration = max(0, durationSec)
        let efficiency = grossEfficiency(powerWatts: safePower, ftpWatts: ftpWatts)
        guard safePower > 0, safeDuration > 0 else {
            return StepEstimate(mechanicalWorkKJ: 0, metabolicKCal: 0, grossEfficiency: efficiency)
        }

        let workJ = safePower * safeDuration
        let metabolicKCal = workJ / (efficiency * Self.joulesPerKilocalorie)
        return StepEstimate(
            mechanicalWorkKJ: workJ / 1_000.0,
            metabolicKCal: metabolicKCal,
            grossEfficiency: efficiency
        )
    }

    func grossEfficiency(powerWatts: Double, ftpWatts: Int) -> Double {
        let safePower = max(0, powerWatts)
        let safeFTP = max(120.0, Double(ftpWatts))
        return efficiencyModel.efficiency(powerWatts: safePower, ftpWatts: safeFTP)
    }
}

enum CyclingCalorieEstimator {
    typealias StepEstimate = CyclingCalorieEngine.StepEstimate

    private static let defaultEngine = CyclingCalorieEngine(efficiencyModel: ExponentialGrossEfficiencyModel())

    static func estimateStep(
        powerWatts: Double,
        durationSec: TimeInterval,
        ftpWatts: Int
    ) -> StepEstimate {
        defaultEngine.estimateStep(powerWatts: powerWatts, durationSec: durationSec, ftpWatts: ftpWatts)
    }

    static func grossEfficiency(powerWatts: Double, ftpWatts: Int) -> Double {
        defaultEngine.grossEfficiency(powerWatts: powerWatts, ftpWatts: ftpWatts)
    }
}
