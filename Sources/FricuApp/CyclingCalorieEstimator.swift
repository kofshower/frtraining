import Foundation

enum CyclingCalorieEstimator {
    static let joulesPerKilocalorie = 4_184.0

    struct StepEstimate {
        let mechanicalWorkKJ: Double
        let metabolicKCal: Double
        let grossEfficiency: Double
    }

    static func estimateStep(
        powerWatts: Double,
        durationSec: TimeInterval,
        ftpWatts: Int
    ) -> StepEstimate {
        let safePower = max(0, powerWatts)
        let safeDuration = max(0, durationSec)
        guard safePower > 0, safeDuration > 0 else {
            return StepEstimate(mechanicalWorkKJ: 0, metabolicKCal: 0, grossEfficiency: grossEfficiency(powerWatts: 0, ftpWatts: ftpWatts))
        }

        let workJ = safePower * safeDuration
        let efficiency = grossEfficiency(powerWatts: safePower, ftpWatts: ftpWatts)
        let metabolicKCal = workJ / (efficiency * joulesPerKilocalorie)
        return StepEstimate(
            mechanicalWorkKJ: workJ / 1_000.0,
            metabolicKCal: metabolicKCal,
            grossEfficiency: efficiency
        )
    }

    static func grossEfficiency(powerWatts: Double, ftpWatts: Int) -> Double {
        let safePower = max(0, powerWatts)
        let ftp = max(120.0, Double(ftpWatts))
        let intensity = safePower / ftp

        // Cycling gross efficiency usually sits around 20%-25% and rises with intensity.
        let efficiency = 0.20 + 0.05 * (1.0 - exp(-intensity / 0.65))
        return min(max(efficiency, 0.20), 0.25)
    }
}
