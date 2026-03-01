import SwiftUI
import Charts
import MapKit

private struct WhooshRouteSegment: Identifiable {
    let id = UUID()
    let name: String
    let distanceKm: Double
    let gradePercent: Double
}

private struct WhooshElevationPoint: Identifiable {
    let id = UUID()
    let distanceKm: Double
    let elevationM: Double
}

private struct WhooshLivePoint: Identifiable {
    let id = UUID()
    let timestamp: Date
    let elapsedSec: Double
    let speedKPH: Double
    let powerW: Double
    let gradePercent: Double
}

private struct RealMapLivePoint: Identifiable {
    let id = UUID()
    let timestamp: Date
    let elapsedSec: Double
    let distanceKm: Double
    let speedKPH: Double
    let powerW: Double
    let gradePercent: Double
}

private struct WhooshBotState: Identifiable {
    let id: String
    let name: String
    let targetWKg: Double
    let tint: Color
    let red: Double
    let green: Double
    let blue: Double
    var distanceKm: Double
    var speedKPH: Double

    static let lineup: [WhooshBotState] = [
        WhooshBotState(
            id: "bot_1",
            name: "Pacer 2.2",
            targetWKg: 2.2,
            tint: .mint,
            red: 0.10,
            green: 0.76,
            blue: 0.63,
            distanceKm: 0.022, // 22m staggered start
            speedKPH: 0
        ),
        WhooshBotState(
            id: "bot_2",
            name: "Pacer 2.8",
            targetWKg: 2.8,
            tint: .orange,
            red: 0.95,
            green: 0.59,
            blue: 0.18,
            distanceKm: 0.050, // 50m staggered start
            speedKPH: 0
        ),
        WhooshBotState(
            id: "bot_3",
            name: "Pacer 3.3",
            targetWKg: 3.3,
            tint: .red,
            red: 0.88,
            green: 0.20,
            blue: 0.26,
            distanceKm: 0.078, // 78m staggered start
            speedKPH: 0
        )
    ]
}

private struct WhooshLeaderboardEntry: Identifiable {
    let id: String
    let name: String
    let tint: Color
    let distanceKm: Double
    let speedKPH: Double
}

private enum WhooshRoutePreset: String, CaseIterable, Identifiable {
    case cityCircuit
    case rollingValley
    case summitRing

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cityCircuit:
            return L10n.choose(simplifiedChinese: "城市环线", english: "City Circuit")
        case .rollingValley:
            return L10n.choose(simplifiedChinese: "丘陵谷地", english: "Rolling Valley")
        case .summitRing:
            return L10n.choose(simplifiedChinese: "山顶环", english: "Summit Ring")
        }
    }

    var subtitle: String {
        switch self {
        case .cityCircuit:
            return L10n.choose(simplifiedChinese: "低坡度高速巡航", english: "Fast urban cruising")
        case .rollingValley:
            return L10n.choose(simplifiedChinese: "频繁起伏，节奏变化", english: "Frequent rollers and tempo shifts")
        case .summitRing:
            return L10n.choose(simplifiedChinese: "长坡耐力与下坡恢复", english: "Long climbs with downhill recovery")
        }
    }

    var segments: [WhooshRouteSegment] {
        switch self {
        case .cityCircuit:
            return [
                .init(name: "Boulevard", distanceKm: 2.0, gradePercent: 0.5),
                .init(name: "River Front", distanceKm: 1.8, gradePercent: -0.8),
                .init(name: "Bridge Rise", distanceKm: 1.0, gradePercent: 2.6),
                .init(name: "Old Town", distanceKm: 2.2, gradePercent: 0.2),
                .init(name: "Park Descent", distanceKm: 1.2, gradePercent: -2.0),
                .init(name: "City Sprint", distanceKm: 1.8, gradePercent: 0.0)
            ]
        case .rollingValley:
            return [
                .init(name: "Valley Gate", distanceKm: 2.4, gradePercent: 0.8),
                .init(name: "Ramp A", distanceKm: 1.2, gradePercent: 4.8),
                .init(name: "Drop A", distanceKm: 1.1, gradePercent: -3.2),
                .init(name: "Mid Ridge", distanceKm: 2.0, gradePercent: 2.5),
                .init(name: "Drop B", distanceKm: 1.3, gradePercent: -2.7),
                .init(name: "Tempo Flats", distanceKm: 2.6, gradePercent: 0.4)
            ]
        case .summitRing:
            return [
                .init(name: "Warm Valley", distanceKm: 2.0, gradePercent: 0.3),
                .init(name: "Main Climb", distanceKm: 3.8, gradePercent: 5.4),
                .init(name: "Sky Shelf", distanceKm: 1.5, gradePercent: 1.0),
                .init(name: "Summit Push", distanceKm: 1.2, gradePercent: 6.3),
                .init(name: "Cold Descent", distanceKm: 2.4, gradePercent: -4.1),
                .init(name: "Return Road", distanceKm: 1.9, gradePercent: 0.1)
            ]
        }
    }

    var totalDistanceKm: Double {
        max(0.1, segments.reduce(0) { $0 + $1.distanceKm })
    }

    private func wrapped(_ distanceKm: Double) -> Double {
        let loop = totalDistanceKm
        guard loop > 0 else { return 0 }
        let mod = distanceKm.truncatingRemainder(dividingBy: loop)
        return mod >= 0 ? mod : (mod + loop)
    }

    func distanceOnRoute(for totalDistanceKm: Double) -> Double {
        wrapped(totalDistanceKm)
    }

    func segment(at totalDistanceKm: Double) -> WhooshRouteSegment {
        let target = wrapped(totalDistanceKm)
        var cursor = 0.0
        for segment in segments {
            let next = cursor + segment.distanceKm
            if target <= next || next >= self.totalDistanceKm {
                return segment
            }
            cursor = next
        }
        return segments.last ?? .init(name: "Route", distanceKm: 1, gradePercent: 0)
    }

    func grade(at totalDistanceKm: Double) -> Double {
        segment(at: totalDistanceKm).gradePercent
    }

    func elevation(at totalDistanceKm: Double) -> Double {
        let target = wrapped(totalDistanceKm)
        var cursor = 0.0
        var elevation = 0.0
        for segment in segments {
            let next = cursor + segment.distanceKm
            if target >= next {
                elevation += segment.distanceKm * segment.gradePercent * 10.0
            } else {
                let partial = max(0, target - cursor)
                elevation += partial * segment.gradePercent * 10.0
                break
            }
            cursor = next
        }
        return elevation
    }

    func elevationProfile(stepKm: Double = 0.2) -> [WhooshElevationPoint] {
        let step = max(0.05, stepKm)
        var points: [WhooshElevationPoint] = []
        var distance = 0.0
        while distance <= totalDistanceKm {
            points.append(WhooshElevationPoint(distanceKm: distance, elevationM: elevation(at: distance)))
            distance += step
        }
        if (points.last?.distanceKm ?? 0) < totalDistanceKm {
            points.append(WhooshElevationPoint(distanceKm: totalDistanceKm, elevationM: elevation(at: totalDistanceKm)))
        }
        let minElevation = points.map(\.elevationM).min() ?? 0
        return points.map { WhooshElevationPoint(distanceKm: $0.distanceKm, elevationM: $0.elevationM - minElevation) }
    }
}

struct TrainerControlPanel: View {
    @Environment(\.appChartDisplayMode) private var chartDisplayMode
    @EnvironmentObject private var store: AppStore
    let session: TrainerRiderSession
    @ObservedObject private var trainer: SmartTrainerManager
    @ObservedObject private var heartRateMonitor: HeartRateMonitorManager
    @ObservedObject private var powerMeter: PowerMeterManager
    private static let whooshMiniGameEnabled = false

    @State private var executionMode: TrainerExecutionMode = .erg
    @State private var targetPowerText = "200"
    @State private var gradeText = "0.0"
    @State private var selectedProgramWorkoutID: UUID?
    @State private var selectedSimulationActivityID: UUID?
    @State private var simulationSpeedText = "8"
    @State private var bikeComputerTrace: [BikeComputerTracePoint] = []
    @State private var bikeComputerSessionStartedAt: Date?
    @State private var bikeComputerLastIntegrationAt: Date?
    @State private var bikeComputerCumulativeMechanicalWorkKJ: Double = 0
    @State private var bikeComputerCumulativeCaloriesKCal: Double = 0
    @State private var bikeComputerCumulativeLeftWorkKJ: Double = 0
    @State private var bikeComputerCumulativeRightWorkKJ: Double = 0
    @State private var bikeComputerCumulativeLeftPercentSum: Double = 0
    @State private var bikeComputerCumulativeRightPercentSum: Double = 0
    @State private var bikeComputerCumulativeBalanceSamples: Int = 0
    @State private var bikeComputerAllPowerSamples: [Double] = []
    @State private var bikeComputerLapPowerSamples: [Double] = []
    @State private var bikeComputerLapStartedAtSec: Int = 0
    @State private var bikeComputerLapPowerSum: Double = 0
    @State private var bikeComputerLapPowerCount: Int = 0
    @State private var bikeComputerLapHeartRateSum: Double = 0
    @State private var bikeComputerLapHeartRateCount: Int = 0
    @State private var bikeComputerPowerZoneSec: [Int] = Array(repeating: 0, count: 7)
    @State private var bikeComputerHeartRateZoneSec: [Int] = Array(repeating: 0, count: 7)
    @State private var bikeComputerTargetDeviationSec: TimeInterval = 0
    @State private var bikeComputerTargetAlertUntil: Date?
    @State private var bikeComputerHydrationReminderUntil: Date?
    @State private var bikeComputerCarbReminderUntil: Date?
    @State private var bikeComputerHRAlertUntil: Date?
    @State private var bikeComputerHRAboveThresholdSec: TimeInterval = 0
    @State private var bikeComputerNextHydrationMarkSec: Int = 15 * 60
    @State private var bikeComputerNextCarbMarkSec: Int = 30 * 60
    @State private var bikeComputerAutoLapEnabled = true
    @State private var bikeComputerAutoLapEverySec: Int = 10 * 60
    @State private var isTrainerFTMSFieldsExpanded = false
    @State private var isTrainerCPSFieldsExpanded = false
    @State private var isPowerMeterCPSFieldsExpanded = false
    @State private var selectedRealMapActivityID: UUID?
    @State private var realMapRoute: RealMapRoute?
    @State private var realMapLoading = false
    @State private var realMapStatusMessage: String?
    @State private var realMapCameraPosition: MapCameraPosition = .automatic
    @State private var realMapFollowRider = true
    @State private var realMapIsRunning = false
    @State private var realMapSyncGradeToTrainer = false
    @State private var realMapElapsedSec: Double = 0
    @State private var realMapDistanceKm: Double = 0
    @State private var realMapElevationGainM: Double = 0
    @State private var realMapCurrentGradePercent: Double = 0
    @State private var realMapCurrentSpeedKPH: Double = 0
    @State private var realMapCurrentPowerW: Double = 0
    @State private var realMapLastTickAt: Date?
    @State private var realMapLastAppliedGradePercent: Double?
    @State private var realMapLastAppliedGradeAt: Date?
    @State private var realMapLiveTrace: [RealMapLivePoint] = []
    @State private var whooshRoute: WhooshRoutePreset = .cityCircuit
    @State private var whooshIsRunning = false
    @State private var whooshSyncGradeToTrainer = false
    @State private var whooshElapsedSec: Double = 0
    @State private var whooshDistanceKm: Double = 0
    @State private var whooshElevationGainM: Double = 0
    @State private var whooshCurrentGradePercent: Double = 0
    @State private var whooshCurrentSpeedKPH: Double = 0
    @State private var whooshCurrentPowerW: Double = 0
    @State private var whooshLastTickAt: Date?
    @State private var whooshLastAppliedGradePercent: Double?
    @State private var whooshLastAppliedGradeAt: Date?
    @State private var whooshLiveTrace: [WhooshLivePoint] = []
    @State private var whooshBots: [WhooshBotState] = WhooshBotState.lineup
    @State private var whooshCameraMode: Whoosh3DCameraMode = .chase
    @State private var whooshCameraZoom: Double = 1.0
    @State private var whooshCameraRecenterToken: Int = 0
    @State private var whooshRoadWidthMeters: Double = 1.1
    @State private var whooshGuardRailHeightMeters: Double = 0.24
    @State private var whooshPlayerModelQualityMode: WhooshPlayerModelQualityMode = .high
    @State private var isWhooshShibaAppearanceExpanded = false

    private let bikeComputerTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private let bikeComputerWindowSeconds: TimeInterval = 10 * 60
    private let realMapWindowSeconds: TimeInterval = 10 * 60
    private let whooshWindowSeconds: TimeInterval = 10 * 60
    private var riderProfile: AthleteProfile { store.profileForAthlete(named: session.name) }

    private var programWorkouts: [PlannedWorkout] {
        store.workoutsForAthlete(named: session.name).filter { !$0.segments.isEmpty }
    }

    private var simulationActivities: [Activity] {
        store.activitiesForAthlete(named: session.name)
            .filter { !$0.intervals.isEmpty || $0.normalizedPower != nil }
            .sorted { $0.date > $1.date }
    }

    private var realMapActivities: [Activity] {
        store.activitiesForAthlete(named: session.name)
            .filter {
                guard
                    let fileType = $0.sourceFileType?.lowercased(),
                    $0.sourceFileBase64 != nil
                else { return false }
                return fileType == "fit" || fileType == "tcx" || fileType == "gpx"
            }
            .sorted { $0.date > $1.date }
    }

    private var bikeComputerPowerWatts: Int? {
        trainer.livePowerWatts ?? powerMeter.livePowerWatts
    }

    private var bikeComputerCadenceRPM: Double? {
        trainer.liveCadenceRPM ?? powerMeter.liveCadenceRPM
    }

    private var bikeComputerHeartRateBPM: Int? {
        heartRateMonitor.liveHeartRateBPM
    }

    private var bikeComputerBalancePair: (left: Double, right: Double)? {
        if let pair = normalizedBalancePair(
            left: powerMeter.liveLeftBalancePercent,
            right: powerMeter.liveRightBalancePercent
        ) {
            return pair
        }
        return normalizedBalancePair(
            left: trainer.liveLeftBalancePercent,
            right: trainer.liveRightBalancePercent
        )
    }

    private var bikeComputerBalanceLeftPercent: Double? {
        bikeComputerBalancePair?.left
    }

    private var bikeComputerBalanceRightPercent: Double? {
        bikeComputerBalancePair?.right
    }

    private var bikeComputerBalanceText: String {
        let left = bikeComputerBalanceLeftPercent
        let right = bikeComputerBalanceRightPercent
        guard let left, let right else { return "--" }
        return String(format: "L%.0f%% / R%.0f%%", left, right)
    }

    private var recordingStatus: TrainerRecordingStatus {
        store.trainerRecordingStatus(for: session.id)
    }

    private var recordingActive: Bool {
        session.supportsRecording && recordingStatus.isActive
    }

    private var recordingElapsedSec: Int {
        recordingActive ? recordingStatus.elapsedSec : 0
    }

    private var recordingSampleCount: Int {
        recordingActive ? recordingStatus.sampleCount : 0
    }

    private var recordingElevationGainMeters: Double {
        recordingActive ? recordingStatus.elevationGainMeters : 0
    }

    private var bikeComputerElapsedSec: Int {
        if recordingActive {
            return recordingElapsedSec
        }
        return bikeComputerTrace.last?.elapsedSec ?? 0
    }

    private var bikeComputerElapsedText: String {
        bikeComputerElapsedSec > 0 ? bikeComputerElapsedSec.asDuration : "--"
    }

    private var bikeComputerSpeedText: String {
        trainer.liveSpeedKPH.map { String(format: "%.1f km/h", $0) } ?? "--"
    }

    private var bikeComputerCadenceText: String {
        bikeComputerCadenceRPM.map { String(format: "%.0f rpm", $0) } ?? "--"
    }

    private var bikeComputerRolling3sPowerText: String {
        rollingPowerText(windowSec: 3)
    }

    private var bikeComputerRolling10sPowerText: String {
        rollingPowerText(windowSec: 10)
    }

    private var bikeComputerLapElapsedSec: Int {
        max(0, bikeComputerElapsedSec - bikeComputerLapStartedAtSec)
    }

    private var bikeComputerLapElapsedText: String {
        bikeComputerLapElapsedSec.asDuration
    }

    private var bikeComputerLapPowerText: String {
        guard bikeComputerLapPowerCount > 0 else { return "--" }
        let avg = bikeComputerLapPowerSum / Double(bikeComputerLapPowerCount)
        return String(format: "%.0f W", avg)
    }

    private var bikeComputerLapHeartRateText: String {
        guard bikeComputerLapHeartRateCount > 0 else { return "--" }
        let avg = bikeComputerLapHeartRateSum / Double(bikeComputerLapHeartRateCount)
        return String(format: "%.0f bpm", avg)
    }

    private var bikeComputerLiveNP: Int? {
        normalizedPower(from: bikeComputerAllPowerSamples)
    }

    private var bikeComputerLapNP: Int? {
        normalizedPower(from: bikeComputerLapPowerSamples)
    }

    private var bikeComputerIF: Double? {
        let ftp = riderProfile.ftpWatts(for: .cycling)
        guard ftp > 0, let np = bikeComputerLiveNP else { return nil }
        return Double(np) / Double(ftp)
    }

    private var bikeComputerIFText: String {
        bikeComputerIF.map { String(format: "%.2f", $0) } ?? "--"
    }

    private var bikeComputerEstimatedTSSText: String {
        guard let ifValue = bikeComputerIF else { return "--" }
        let hours = Double(max(0, bikeComputerElapsedSec)) / 3600.0
        let tss = max(0, hours * ifValue * ifValue * 100)
        return String(format: "%.1f", tss)
    }

    private var bikeComputerLiveNPText: String {
        bikeComputerLiveNP.map { "\($0) W" } ?? "--"
    }

    private var bikeComputerLapNPText: String {
        bikeComputerLapNP.map { "\($0) W" } ?? "--"
    }

    private var bikeComputerZoneSummaryText: String {
        bikeComputerPowerZoneSec
            .enumerated()
            .map { index, sec in "Z\(index + 1) \(sec.asDuration)" }
            .joined(separator: " · ")
    }

    private var bikeComputerHeartRateZoneSummaryText: String {
        bikeComputerHeartRateZoneSec
            .enumerated()
            .map { index, sec in "Z\(index + 1) \(sec.asDuration)" }
            .joined(separator: " · ")
    }

    private var bikeComputerZoneRows: [(name: String, seconds: Int, percent: Double)] {
        let total = max(1, bikeComputerPowerZoneSec.reduce(0, +))
        return bikeComputerPowerZoneSec.enumerated().map { index, sec in
            (name: "Z\(index + 1)", seconds: sec, percent: Double(sec) / Double(total))
        }
    }

    private var bikeComputerHeartRateZoneRows: [(name: String, seconds: Int, percent: Double)] {
        let total = max(1, bikeComputerHeartRateZoneSec.reduce(0, +))
        return bikeComputerHeartRateZoneSec.enumerated().map { index, sec in
            (name: "Z\(index + 1)", seconds: sec, percent: Double(sec) / Double(total))
        }
    }

    private var bikeComputerBest5sPowerText: String {
        bestRollingPower(window: 5, from: bikeComputerAllPowerSamples)
            .map { String(format: "%.0f W", $0) } ?? "--"
    }

    private var bikeComputerBest1mPowerText: String {
        bestRollingPower(window: 60, from: bikeComputerAllPowerSamples)
            .map { String(format: "%.0f W", $0) } ?? "--"
    }

    private var bikeComputerBest5mPowerText: String {
        bestRollingPower(window: 300, from: bikeComputerAllPowerSamples)
            .map { String(format: "%.0f W", $0) } ?? "--"
    }

    private var bikeComputerTargetPower: Int? {
        if let erg = trainer.ergTargetWatts, erg > 0 {
            return erg
        }
        return nil
    }

    private var bikeComputerTargetAlertText: String? {
        guard let alertUntil = bikeComputerTargetAlertUntil, alertUntil >= Date(), let target = bikeComputerTargetPower else {
            return nil
        }
        return L10n.choose(
            simplifiedChinese: "功率偏离目标 \(target)W 超过 ±5%（持续 8 秒）",
            english: "Power deviated from target \(target)W by ±5% for 8s"
        )
    }

    private var bikeComputerHydrationAlertText: String? {
        guard let until = bikeComputerHydrationReminderUntil, until >= Date() else { return nil }
        return L10n.choose(simplifiedChinese: "补水提醒：建议现在喝水", english: "Hydration reminder: drink now")
    }

    private var bikeComputerCarbAlertText: String? {
        guard let until = bikeComputerCarbReminderUntil, until >= Date() else { return nil }
        return L10n.choose(simplifiedChinese: "补给提醒：建议摄入碳水", english: "Fuel reminder: take carbs now")
    }

    private var bikeComputerHRAlertText: String? {
        guard let until = bikeComputerHRAlertUntil, until >= Date() else { return nil }
        return L10n.choose(
            simplifiedChinese: "心率连续超阈值，建议降强/恢复",
            english: "Heart rate stayed above threshold, back off and recover"
        )
    }

    private var bikeComputerCaloriesText: String {
        guard bikeComputerCumulativeCaloriesKCal > 0 else { return "--" }
        return String(format: "%.0f kcal", bikeComputerCumulativeCaloriesKCal)
    }

    private var bikeComputerCaloriesContextText: String {
        guard bikeComputerCumulativeMechanicalWorkKJ > 0 else {
            return "功率估算"
        }
        return String(format: "做功 %.0f kJ", bikeComputerCumulativeMechanicalWorkKJ)
    }

    private var bikeComputerCumulativeBalanceLeftPercent: Double? {
        let totalWork = bikeComputerCumulativeLeftWorkKJ + bikeComputerCumulativeRightWorkKJ
        if totalWork > 0 {
            return (bikeComputerCumulativeLeftWorkKJ / totalWork) * 100.0
        }
        guard bikeComputerCumulativeBalanceSamples > 0 else { return nil }
        return bikeComputerCumulativeLeftPercentSum / Double(bikeComputerCumulativeBalanceSamples)
    }

    private var bikeComputerCumulativeBalanceRightPercent: Double? {
        let totalWork = bikeComputerCumulativeLeftWorkKJ + bikeComputerCumulativeRightWorkKJ
        if totalWork > 0 {
            return (bikeComputerCumulativeRightWorkKJ / totalWork) * 100.0
        }
        guard bikeComputerCumulativeBalanceSamples > 0 else { return nil }
        return bikeComputerCumulativeRightPercentSum / Double(bikeComputerCumulativeBalanceSamples)
    }

    private func bikeComputerBalanceContextText(from series: BikeComputerSparklineSeries) -> String {
        let left1m = series.balanceLeft.oneMinuteAverage
        let right1m = series.balanceRight.oneMinuteAverage
        let minuteText: String
        if let left1m, let right1m {
            minuteText = String(format: "均值 L%.0f%% / R%.0f%%", left1m, right1m)
        } else {
            minuteText = "均值 --"
        }
        let cumulativeText: String
        if let left = bikeComputerCumulativeBalanceLeftPercent,
           let right = bikeComputerCumulativeBalanceRightPercent {
            cumulativeText = String(format: "累计 L%.1f%% / R%.1f%%", left, right)
        } else {
            cumulativeText = "累计 --"
        }
        return "\(minuteText) · \(cumulativeText)"
    }

    private var traceNow: Date {
        bikeComputerTrace.last?.timestamp ?? Date()
    }

    private var bikeComputerWindowTitle: String {
        "最近 \(Int(bikeComputerWindowSeconds / 60)) 分钟"
    }

    private var whooshDistanceOnRouteKm: Double {
        whooshRoute.distanceOnRoute(for: whooshDistanceKm)
    }

    private var selectedRealMapActivity: Activity? {
        guard let id = selectedRealMapActivityID else { return realMapActivities.first }
        return realMapActivities.first(where: { $0.id == id }) ?? realMapActivities.first
    }

    private var realMapDistanceOnRouteKm: Double {
        realMapRoute?.distanceOnRoute(for: realMapDistanceKm) ?? 0
    }

    private var realMapLap: Int {
        let loop = realMapRoute?.totalDistanceKm ?? 0
        guard loop > 0 else { return 1 }
        return max(1, Int(floor(realMapDistanceKm / loop)) + 1)
    }

    private var realMapRouteProgress: Double {
        let loop = realMapRoute?.totalDistanceKm ?? 0
        guard loop > 0 else { return 0 }
        return min(max(realMapDistanceOnRouteKm / loop, 0), 1)
    }

    private var realMapCoordinate: CLLocationCoordinate2D? {
        realMapRoute?.coordinate(at: realMapDistanceKm)
    }

    private var realMapEffectivePowerW: Double {
        if let live = bikeComputerPowerWatts, live > 0 {
            return Double(live)
        }
        if let target = trainer.ergTargetWatts, target > 0 {
            return Double(target)
        }
        return max(100, Double(riderProfile.ftpWatts(for: .cycling)) * 0.55)
    }

    private var realMapRecentTrace: [RealMapLivePoint] {
        guard let latest = realMapLiveTrace.last?.timestamp else { return [] }
        let cutoff = latest.addingTimeInterval(-realMapWindowSeconds)
        return realMapLiveTrace.filter { $0.timestamp >= cutoff }
    }

    private var realMapSpeedSparkline: [SparklinePoint] {
        realMapRecentTrace.map { SparklinePoint(timestamp: $0.timestamp, value: $0.speedKPH) }
    }

    private var realMapPowerSparkline: [SparklinePoint] {
        realMapRecentTrace.map { SparklinePoint(timestamp: $0.timestamp, value: $0.powerW) }
    }

    private var realMapGradeSparkline: [SparklinePoint] {
        realMapRecentTrace.map { SparklinePoint(timestamp: $0.timestamp, value: $0.gradePercent) }
    }

    private var realMapAltitudeSparkline: [SparklinePoint] {
        guard let route = realMapRoute else { return [] }
        return realMapRecentTrace.compactMap { point in
            guard let altitude = route.elevation(at: point.distanceKm) else {
                return nil
            }
            return SparklinePoint(timestamp: point.timestamp, value: altitude)
        }
    }

    @ViewBuilder
    private var realMapModeView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Picker(
                    L10n.choose(simplifiedChinese: "真实路线", english: "Real Route"),
                    selection: $selectedRealMapActivityID
                ) {
                    ForEach(realMapActivities.prefix(250)) { activity in
                        Text("\(activity.date.formatted(date: .abbreviated, time: .omitted)) · \(activity.sport.label) · \(activity.durationSec.asDuration)")
                            .tag(Optional(activity.id))
                    }
                }
                .appDropdownTheme()
                .frame(maxWidth: 430)
                .disabled(realMapActivities.isEmpty)

                Button(L10n.choose(simplifiedChinese: "重新加载路线", english: "Reload Route")) {
                    loadRealMapRoute(for: selectedRealMapActivity)
                }
                .disabled(selectedRealMapActivity == nil || realMapLoading)

                Toggle(
                    L10n.choose(simplifiedChinese: "跟随骑手", english: "Follow rider"),
                    isOn: $realMapFollowRider
                )
                .toggleStyle(.switch)

                Toggle(
                    L10n.choose(
                        simplifiedChinese: "同步坡度到骑行台",
                        english: "Sync grade to trainer"
                    ),
                    isOn: $realMapSyncGradeToTrainer
                )
                .toggleStyle(.switch)
                .disabled(!trainer.isConnected || !trainer.ergAvailable)

                Spacer()

                Button(
                    realMapIsRunning
                        ? L10n.choose(simplifiedChinese: "暂停", english: "Pause")
                        : L10n.choose(simplifiedChinese: "开始", english: "Start")
                ) {
                    if realMapIsRunning {
                        pauseRealMapRide()
                    } else {
                        startRealMapRide()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(realMapRoute == nil && realMapActivities.isEmpty)

                Button(L10n.choose(simplifiedChinese: "重置", english: "Reset")) {
                    resetRealMapRide()
                }
                .buttonStyle(.bordered)
            }

            if let message = realMapStatusMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(realMapRoute == nil ? .orange : .secondary)
            }

            if realMapActivities.isEmpty {
                Text(
                    L10n.choose(
                        simplifiedChinese: "未找到带原始 FIT/TCX/GPX 文件的活动。请先导入包含轨迹的文件。",
                        english: "No activity with raw FIT/TCX/GPX source found. Import a file with GPS track first."
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            } else if let route = realMapRoute {
                HStack(spacing: 10) {
                    LiveMetricChip(
                        title: L10n.choose(simplifiedChinese: "路线", english: "Route"),
                        value: route.activityName
                    )
                    LiveMetricChip(
                        title: L10n.choose(simplifiedChinese: "距离", english: "Distance"),
                        value: String(format: "%.2f km", realMapDistanceKm)
                    )
                    LiveMetricChip(
                        title: L10n.choose(simplifiedChinese: "圈数", english: "Lap"),
                        value: "\(realMapLap)"
                    )
                    LiveMetricChip(
                        title: L10n.choose(simplifiedChinese: "坡度", english: "Grade"),
                        value: String(format: "%.1f%%", realMapCurrentGradePercent)
                    )
                    LiveMetricChip(
                        title: L10n.choose(simplifiedChinese: "速度", english: "Speed"),
                        value: String(format: "%.1f km/h", realMapCurrentSpeedKPH)
                    )
                    LiveMetricChip(
                        title: L10n.choose(simplifiedChinese: "功率", english: "Power"),
                        value: String(format: "%.0f W", realMapCurrentPowerW)
                    )
                    LiveMetricChip(
                        title: L10n.choose(simplifiedChinese: "累计爬升", english: "Elevation Gain"),
                        value: String(format: "%.0f m", realMapElevationGainM)
                    )
                }

                HStack(spacing: 10) {
                    ProgressView(value: realMapRouteProgress)
                        .tint(.blue)
                    Text(
                        L10n.choose(
                            simplifiedChinese: "本圈 \(Int((realMapRouteProgress * 100).rounded()))%",
                            english: "Lap \(Int((realMapRouteProgress * 100).rounded()))%"
                        )
                    )
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    Text(
                        String(
                            format: "%.0f m",
                            route.elevation(at: realMapDistanceKm) ?? 0
                        )
                    )
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    Text(
                        L10n.choose(
                            simplifiedChinese: "3D 地形已开启",
                            english: "3D terrain enabled"
                        )
                    )
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.blue.opacity(0.12), in: Capsule())
                }

                Map(position: $realMapCameraPosition) {
                    MapPolyline(coordinates: route.polylineCoordinates)
                        .stroke(.blue, lineWidth: 3)

                    if let start = route.polylineCoordinates.first {
                        Marker(
                            L10n.choose(simplifiedChinese: "起点", english: "Start"),
                            coordinate: start
                        )
                        .tint(.green)
                    }

                    if let rider = realMapCoordinate {
                        Annotation(
                            L10n.choose(simplifiedChinese: "骑手", english: "Rider"),
                            coordinate: rider
                        ) {
                            ZStack {
                                Circle()
                                    .fill(.blue.opacity(0.2))
                                    .frame(width: 24, height: 24)
                                Image(systemName: "bicycle.circle.fill")
                                    .font(.title3)
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                }
                .mapStyle(.standard(elevation: .realistic))
                .frame(height: 280)
                .clipShape(RoundedRectangle(cornerRadius: 12))

                Chart(sampledRealMapProfile(route.points, maxCount: 650)) { point in
                    let elevation = max(0, point.altitudeMeters ?? 0)
                    switch chartDisplayMode {
                    case .line:
                        AreaMark(
                            x: .value("Distance", point.cumulativeDistanceKm),
                            y: .value("Elevation", elevation)
                        )
                        .interpolationMethod(.monotone)
                        .foregroundStyle(.blue.opacity(0.15))

                        LineMark(
                            x: .value("Distance", point.cumulativeDistanceKm),
                            y: .value("Elevation", elevation)
                        )
                        .interpolationMethod(.monotone)
                        .foregroundStyle(.blue)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                    case .bar:
                        BarMark(
                            x: .value("Distance", point.cumulativeDistanceKm),
                            y: .value("Elevation", elevation)
                        )
                        .foregroundStyle(.blue.opacity(0.8))
                    case .pie:
                        SectorMark(
                            angle: .value("Elevation", elevation),
                            innerRadius: .ratio(0.55),
                            angularInset: 0.8
                        )
                        .foregroundStyle(.blue.opacity(0.75))
                    case .flame:
                        BarMark(
                            x: .value("Distance", point.cumulativeDistanceKm),
                            y: .value("Elevation", elevation)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.yellow, .orange, .red],
                                startPoint: .bottom,
                                endPoint: .top
                            )
                        )
                    }
                }
                .chartXAxisLabel(
                    L10n.choose(simplifiedChinese: "路线距离 (km)", english: "Route Distance (km)")
                )
                .chartYAxisLabel(
                    L10n.choose(simplifiedChinese: "海拔 (m)", english: "Elevation (m)")
                )
                .cartesianHoverTip(
                    xTitle: L10n.choose(simplifiedChinese: "距离", english: "Distance"),
                    yTitle: L10n.choose(simplifiedChinese: "海拔", english: "Elevation")
                )
                .frame(height: 170)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    BikeComputerSparklineCard(
                        label: L10n.choose(simplifiedChinese: "速度", english: "Speed"),
                        value: String(format: "%.1f km/h", realMapCurrentSpeedKPH),
                        averageText: oneMinuteAverage(from: realMapSpeedSparkline).map {
                            String(format: "1m %.1f km/h", $0)
                        } ?? "1m --",
                        tint: .mint,
                        points: realMapSpeedSparkline
                    )
                    BikeComputerSparklineCard(
                        label: L10n.choose(simplifiedChinese: "功率", english: "Power"),
                        value: String(format: "%.0f W", realMapCurrentPowerW),
                        averageText: oneMinuteAverage(from: realMapPowerSparkline).map {
                            String(format: "1m %.0f W", $0)
                        } ?? "1m --",
                        tint: .orange,
                        points: realMapPowerSparkline
                    )
                    BikeComputerSparklineCard(
                        label: L10n.choose(simplifiedChinese: "坡度", english: "Grade"),
                        value: String(format: "%.1f%%", realMapCurrentGradePercent),
                        averageText: oneMinuteAverage(from: realMapGradeSparkline).map {
                            String(format: "1m %.1f%%", $0)
                        } ?? "1m --",
                        tint: .purple,
                        points: realMapGradeSparkline
                    )
                    BikeComputerSparklineCard(
                        label: L10n.choose(simplifiedChinese: "海拔", english: "Elevation"),
                        value: String(format: "%.0f m", route.elevation(at: realMapDistanceKm) ?? 0),
                        averageText: oneMinuteAverage(from: realMapAltitudeSparkline).map {
                            String(format: "1m %.0f m", $0)
                        } ?? "1m --",
                        tint: .blue,
                        points: realMapAltitudeSparkline
                    )
                }
            }
        }
    }

    private var whooshLap: Int {
        let loop = whooshRoute.totalDistanceKm
        guard loop > 0 else { return 1 }
        return max(1, Int(floor(whooshDistanceKm / loop)) + 1)
    }

    private var whooshRouteProgress: Double {
        let loop = whooshRoute.totalDistanceKm
        guard loop > 0 else { return 0 }
        return min(max(whooshDistanceOnRouteKm / loop, 0), 1)
    }

    private var whooshSegmentName: String {
        whooshRoute.segment(at: whooshDistanceKm).name
    }

    private var whooshProfilePoints: [WhooshElevationPoint] {
        whooshRoute.elevationProfile(stepKm: 0.18)
    }

    private var whooshPlayerAltitudeM: Double {
        let normalizedMin = whooshProfilePoints.map(\.elevationM).min() ?? 0
        return max(0, whooshRoute.elevation(at: whooshDistanceKm) - normalizedMin)
    }

    private var whooshEffectivePowerW: Double {
        if let live = bikeComputerPowerWatts, live > 0 {
            return Double(live)
        }
        if let target = trainer.ergTargetWatts, target > 0 {
            return Double(target)
        }
        return max(100, Double(riderProfile.ftpWatts(for: .cycling)) * 0.55)
    }

    private var whooshRecentTrace: [WhooshLivePoint] {
        guard let latest = whooshLiveTrace.last?.timestamp else { return [] }
        let cutoff = latest.addingTimeInterval(-whooshWindowSeconds)
        return whooshLiveTrace.filter { $0.timestamp >= cutoff }
    }

    private var whooshLeaderboard: [WhooshLeaderboardEntry] {
        var rows: [WhooshLeaderboardEntry] = [
            WhooshLeaderboardEntry(
                id: "player",
                name: session.name,
                tint: .blue,
                distanceKm: whooshDistanceKm,
                speedKPH: whooshCurrentSpeedKPH
            )
        ]
        rows.append(contentsOf: whooshBots.map { bot in
            WhooshLeaderboardEntry(
                id: bot.id,
                name: bot.name,
                tint: bot.tint,
                distanceKm: bot.distanceKm,
                speedKPH: bot.speedKPH
            )
        })
        return rows.sorted { lhs, rhs in
            if lhs.distanceKm != rhs.distanceKm { return lhs.distanceKm > rhs.distanceKm }
            return lhs.id < rhs.id
        }
    }

    private var whooshSpeedSparkline: [SparklinePoint] {
        whooshRecentTrace.map { point in
            SparklinePoint(timestamp: point.timestamp, value: point.speedKPH)
        }
    }

    private var whoosh3DProfile: [Whoosh3DProfilePoint] {
        whooshProfilePoints.map { point in
            Whoosh3DProfilePoint(distanceKm: point.distanceKm, elevationM: point.elevationM)
        }
    }

    private var currentPlayerAppearance: TrainerRiderAppearance {
        store.trainerRiderAppearance(for: session.id)
    }

    private var whooshRunnerModelOptions: [WhooshRunnerModelOption] {
        let blockedIDs = Set(["shiba_pup_run_colored"])
        return WhooshRunnerModelCatalog.availableModels(
            preferredExtensions: ["usdz"],
            includeDefaultFallback: false
        )
        .filter { !blockedIDs.contains($0.id.lowercased()) }
    }

    private var currentWhooshRunnerModelID: String {
        let selected = currentPlayerAppearance.whooshRunnerModelID
        if let match = whooshRunnerModelOptions.first(where: { $0.id.caseInsensitiveCompare(selected) == .orderedSame }) {
            return match.id
        }
        if let colored = whooshRunnerModelOptions.first(where: { $0.id.caseInsensitiveCompare("shiba_pup_run_colored") == .orderedSame }) {
            return colored.id
        }
        if selected.localizedCaseInsensitiveContains("shiba"),
           let anyShiba = whooshRunnerModelOptions.first(where: { $0.id.localizedCaseInsensitiveContains("shiba") }) {
            return anyShiba.id
        }
        return whooshRunnerModelOptions.first?.id ?? selected
    }

    private func updateCurrentPlayerAppearance(_ mutate: (inout TrainerRiderAppearance) -> Void) {
        var appearance = currentPlayerAppearance
        mutate(&appearance)
        store.updateTrainerRiderAppearance(for: session.id, appearance: appearance)
    }

    private func appearanceBinding<Value>(
        _ keyPath: WritableKeyPath<TrainerRiderAppearance, Value>
    ) -> Binding<Value> {
        Binding(
            get: { currentPlayerAppearance[keyPath: keyPath] },
            set: { newValue in
                updateCurrentPlayerAppearance { $0[keyPath: keyPath] = newValue }
            }
        )
    }

    private var whoosh3DRiders: [Whoosh3DRiderSnapshot] {
        var rows: [Whoosh3DRiderSnapshot] = [
            Whoosh3DRiderSnapshot(
                id: "player",
                name: session.name,
                distanceKm: whooshDistanceKm,
                isPlayer: true,
                red: 0.12,
                green: 0.52,
                blue: 0.98
            )
        ]
        rows.append(
            contentsOf: whooshBots.map { bot in
                Whoosh3DRiderSnapshot(
                    id: bot.id,
                    name: bot.name,
                    distanceKm: bot.distanceKm,
                    isPlayer: false,
                    red: bot.red,
                    green: bot.green,
                    blue: bot.blue
                )
            }
        )
        return rows
    }

    private var whooshPowerSparkline: [SparklinePoint] {
        whooshRecentTrace.map { point in
            SparklinePoint(timestamp: point.timestamp, value: point.powerW)
        }
    }

    private var whooshGradeSparkline: [SparklinePoint] {
        whooshRecentTrace.map { point in
            SparklinePoint(timestamp: point.timestamp, value: point.gradePercent)
        }
    }

    private var bikeComputerSparklineSeries: BikeComputerSparklineSeries {
        let minuteCutoff = traceNow.addingTimeInterval(-60)
        var series = BikeComputerSparklineSeries()

        for point in bikeComputerTrace {
            let timestamp = point.timestamp
            if let value = point.powerWatts {
                series.power.append(value, timestamp: timestamp, minuteCutoff: minuteCutoff)
            }
            if let value = point.heartRateBPM {
                series.heartRate.append(value, timestamp: timestamp, minuteCutoff: minuteCutoff)
            }
            if let value = point.cadenceRPM {
                series.cadence.append(value, timestamp: timestamp, minuteCutoff: minuteCutoff)
            }
            if let value = point.balanceLeftPercent {
                series.balanceLeft.append(value, timestamp: timestamp, minuteCutoff: minuteCutoff)
            }
            if let value = point.balanceRightPercent {
                series.balanceRight.append(value, timestamp: timestamp, minuteCutoff: minuteCutoff)
            }
            if let value = point.rrIntervalMS {
                series.rr.append(value, timestamp: timestamp, minuteCutoff: minuteCutoff)
            }
            if let value = point.hrvRMSSDMS {
                series.hrv.append(value, timestamp: timestamp, minuteCutoff: minuteCutoff)
            }
            if let value = point.estimatedCaloriesKCal {
                series.calories.append(value, timestamp: timestamp, minuteCutoff: minuteCutoff)
            }
        }
        return series
    }

    private func oneMinuteAverage(from points: [SparklinePoint]) -> Double? {
        guard !points.isEmpty else { return nil }
        let cutoff = traceNow.addingTimeInterval(-60)
        let values = points.filter { $0.timestamp >= cutoff }.map(\.value)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private func rollingPowerText(windowSec: TimeInterval) -> String {
        let cutoff = traceNow.addingTimeInterval(-windowSec)
        let values = bikeComputerTrace.compactMap { point -> Double? in
            guard point.timestamp >= cutoff else { return nil }
            return point.powerWatts
        }
        guard !values.isEmpty else { return "--" }
        let avg = values.reduce(0, +) / Double(values.count)
        return String(format: "%.0f W", avg)
    }

    private func normalizedPower(from powers: [Double]) -> Int? {
        guard powers.count >= 10 else { return nil }
        let avgFourth = powers.reduce(0.0) { $0 + pow($1, 4) } / Double(powers.count)
        return Int(pow(avgFourth, 0.25).rounded())
    }

    private func bestRollingPower(window: Int, from powers: [Double]) -> Double? {
        guard window > 0, powers.count >= window else { return nil }
        var sum = powers.prefix(window).reduce(0, +)
        var best = sum / Double(window)
        if powers.count == window {
            return best
        }
        for index in window..<powers.count {
            sum += powers[index] - powers[index - window]
            best = max(best, sum / Double(window))
        }
        return best
    }

    private func powerZoneIndex(for watts: Int, ftp: Int) -> Int {
        guard ftp > 0 else { return 0 }
        let ratio = Double(watts) / Double(ftp)
        switch ratio {
        case ..<0.56: return 0
        case ..<0.76: return 1
        case ..<0.91: return 2
        case ..<1.06: return 3
        case ..<1.21: return 4
        case ..<1.51: return 5
        default: return 6
        }
    }

    private func heartRateZoneIndex(for heartRate: Int, threshold: Int) -> Int {
        guard threshold > 0 else { return 0 }
        let ratio = Double(heartRate) / Double(threshold)
        switch ratio {
        case ..<0.68: return 0
        case ..<0.78: return 1
        case ..<0.87: return 2
        case ..<0.95: return 3
        case ..<1.03: return 4
        case ..<1.10: return 5
        default: return 6
        }
    }

    private func markBikeComputerLap() {
        bikeComputerLapStartedAtSec = bikeComputerElapsedSec
        bikeComputerLapPowerSamples = []
        bikeComputerLapPowerSum = 0
        bikeComputerLapPowerCount = 0
        bikeComputerLapHeartRateSum = 0
        bikeComputerLapHeartRateCount = 0
    }

    private func normalizedBalancePair(left: Double?, right: Double?) -> (left: Double, right: Double)? {
        let leftValue = left?.isFinite == true ? left : nil
        let rightValue = right?.isFinite == true ? right : nil

        switch (leftValue, rightValue) {
        case let (l?, r?):
            guard (0...100).contains(l), (0...100).contains(r) else { return nil }
            let sum = l + r
            guard sum > 0 else { return nil }
            let normalizedLeft = max(0, min(100, (l / sum) * 100))
            return (normalizedLeft, 100 - normalizedLeft)
        case let (l?, nil):
            guard (0...100).contains(l) else { return nil }
            return (l, 100 - l)
        case let (nil, r?):
            guard (0...100).contains(r) else { return nil }
            return (100 - r, r)
        default:
            return nil
        }
    }

    private func appendBikeComputerTraceSample(at timestamp: Date = Date()) {
        if bikeComputerSessionStartedAt == nil {
            bikeComputerSessionStartedAt = timestamp
        }

        if let left = bikeComputerBalanceLeftPercent,
           let right = bikeComputerBalanceRightPercent,
           left.isFinite,
           right.isFinite {
            let sum = left + right
            if sum > 0 {
                let normalizedLeft = max(0, min(100, (left / sum) * 100))
                let normalizedRight = max(0, min(100, (right / sum) * 100))
                bikeComputerCumulativeLeftPercentSum += normalizedLeft
                bikeComputerCumulativeRightPercentSum += normalizedRight
                bikeComputerCumulativeBalanceSamples += 1
            }
        }

        if let previous = bikeComputerLastIntegrationAt {
            let deltaSec = max(0, timestamp.timeIntervalSince(previous))
            let delta = Int(max(1, deltaSec.rounded()))
            if deltaSec > 0, let hr = bikeComputerHeartRateBPM {
                let threshold = riderProfile.thresholdHeartRate(for: .cycling, on: Date())
                let zone = heartRateZoneIndex(for: hr, threshold: threshold)
                bikeComputerHeartRateZoneSec[zone] += delta
            }
            if deltaSec > 0, let watts = bikeComputerPowerWatts, watts > 0 {
                let estimate = CyclingCalorieEstimator.estimateStep(
                    powerWatts: Double(watts),
                    durationSec: deltaSec,
                    ftpWatts: riderProfile.ftpWatts(for: .cycling)
                )
                bikeComputerCumulativeMechanicalWorkKJ += estimate.mechanicalWorkKJ
                bikeComputerCumulativeCaloriesKCal += estimate.metabolicKCal

                if let left = bikeComputerBalanceLeftPercent,
                   let right = bikeComputerBalanceRightPercent,
                   left.isFinite,
                   right.isFinite {
                    let sum = left + right
                    if sum > 0 {
                        let normalizedLeft = max(0, min(1, left / sum))
                        let normalizedRight = max(0, min(1, right / sum))
                        bikeComputerCumulativeLeftWorkKJ += estimate.mechanicalWorkKJ * normalizedLeft
                        bikeComputerCumulativeRightWorkKJ += estimate.mechanicalWorkKJ * normalizedRight
                    }
                }

                bikeComputerAllPowerSamples.append(Double(watts))
                bikeComputerLapPowerSamples.append(Double(watts))
                bikeComputerLapPowerSum += Double(watts)
                bikeComputerLapPowerCount += 1

                let ftp = riderProfile.ftpWatts(for: .cycling)
                let zone = powerZoneIndex(for: watts, ftp: ftp)
                bikeComputerPowerZoneSec[zone] += delta

                if let target = bikeComputerTargetPower, target > 0 {
                    let lower = Double(target) * 0.95
                    let upper = Double(target) * 1.05
                    if Double(watts) < lower || Double(watts) > upper {
                        bikeComputerTargetDeviationSec += deltaSec
                        if bikeComputerTargetDeviationSec >= 8 {
                            bikeComputerTargetAlertUntil = timestamp.addingTimeInterval(6)
                        }
                    } else {
                        bikeComputerTargetDeviationSec = 0
                    }
                } else {
                    bikeComputerTargetDeviationSec = 0
                }
            }
        }
        bikeComputerLastIntegrationAt = timestamp

        let elapsedSec: Int
        if recordingActive {
            elapsedSec = recordingElapsedSec
        } else if let startedAt = bikeComputerSessionStartedAt {
            elapsedSec = max(0, Int(timestamp.timeIntervalSince(startedAt).rounded()))
        } else {
            elapsedSec = 0
        }

        if bikeComputerAutoLapEnabled,
           bikeComputerAutoLapEverySec > 0,
           elapsedSec > 0,
           (elapsedSec - bikeComputerLapStartedAtSec) >= bikeComputerAutoLapEverySec {
            markBikeComputerLap()
        }

        while elapsedSec >= bikeComputerNextHydrationMarkSec {
            bikeComputerHydrationReminderUntil = timestamp.addingTimeInterval(10)
            bikeComputerNextHydrationMarkSec += 15 * 60
        }

        while elapsedSec >= bikeComputerNextCarbMarkSec {
            bikeComputerCarbReminderUntil = timestamp.addingTimeInterval(10)
            bikeComputerNextCarbMarkSec += 30 * 60
        }

        let sample = BikeComputerTracePoint(
            timestamp: timestamp,
            elapsedSec: elapsedSec,
            powerWatts: bikeComputerPowerWatts.map(Double.init),
            cadenceRPM: bikeComputerCadenceRPM,
            heartRateBPM: bikeComputerHeartRateBPM.map(Double.init),
            speedKPH: trainer.liveSpeedKPH,
            elevationMeters: recordingActive ? recordingElevationGainMeters : nil,
            balanceLeftPercent: bikeComputerBalanceLeftPercent,
            balanceRightPercent: bikeComputerBalanceRightPercent,
            rrIntervalMS: heartRateMonitor.liveRRIntervalMS,
            hrvRMSSDMS: heartRateMonitor.liveHRVRMSSDMS,
            energyExpendedKJ: heartRateMonitor.liveEnergyExpendedKJ.map(Double.init),
            estimatedCaloriesKCal: bikeComputerCumulativeCaloriesKCal > 0 ? bikeComputerCumulativeCaloriesKCal : nil
        )

        if let hr = sample.heartRateBPM {
            bikeComputerLapHeartRateSum += hr
            bikeComputerLapHeartRateCount += 1

            let threshold = riderProfile.thresholdHeartRate(for: .cycling, on: Date())
            if threshold > 0 {
                let cap = Double(threshold + 5)
                if hr > cap {
                    bikeComputerHRAboveThresholdSec += 1
                    if bikeComputerHRAboveThresholdSec >= 8 {
                        bikeComputerHRAlertUntil = timestamp.addingTimeInterval(6)
                    }
                } else {
                    bikeComputerHRAboveThresholdSec = 0
                }
            }
        } else {
            bikeComputerHRAboveThresholdSec = 0
        }

        bikeComputerTrace.append(sample)

        let cutoff = timestamp.addingTimeInterval(-bikeComputerWindowSeconds)
        bikeComputerTrace.removeAll { $0.timestamp < cutoff }
    }

    private func resetBikeComputerSessionState(at timestamp: Date = Date()) {
        bikeComputerTrace = []
        bikeComputerSessionStartedAt = timestamp
        bikeComputerLastIntegrationAt = timestamp
        bikeComputerCumulativeMechanicalWorkKJ = 0
        bikeComputerCumulativeCaloriesKCal = 0
        bikeComputerCumulativeLeftWorkKJ = 0
        bikeComputerCumulativeRightWorkKJ = 0
        bikeComputerCumulativeLeftPercentSum = 0
        bikeComputerCumulativeRightPercentSum = 0
        bikeComputerCumulativeBalanceSamples = 0
        bikeComputerAllPowerSamples = []
        bikeComputerLapPowerSamples = []
        bikeComputerLapStartedAtSec = 0
        bikeComputerLapPowerSum = 0
        bikeComputerLapPowerCount = 0
        bikeComputerLapHeartRateSum = 0
        bikeComputerLapHeartRateCount = 0
        bikeComputerPowerZoneSec = Array(repeating: 0, count: 7)
        bikeComputerHeartRateZoneSec = Array(repeating: 0, count: 7)
        bikeComputerTargetDeviationSec = 0
        bikeComputerTargetAlertUntil = nil
        bikeComputerHydrationReminderUntil = nil
        bikeComputerCarbReminderUntil = nil
        bikeComputerHRAlertUntil = nil
        bikeComputerHRAboveThresholdSec = 0
        bikeComputerNextHydrationMarkSec = 15 * 60
        bikeComputerNextCarbMarkSec = 30 * 60
    }

    private func configureRealMapCamera(followRider: Bool = false) {
        guard let route = realMapRoute else {
            realMapCameraPosition = .automatic
            return
        }
        let center: CLLocationCoordinate2D
        if followRider, let rider = realMapCoordinate {
            center = rider
        } else {
            center = route.centerCoordinate
        }
        let distance = followRider
            ? max(450, route.recommendedCameraDistanceMeters * 0.35)
            : route.recommendedCameraDistanceMeters
        realMapCameraPosition = .camera(
            MapCamera(
                centerCoordinate: center,
                distance: distance,
                heading: 0,
                pitch: 58
            )
        )
    }

    private func loadRealMapRoute(for activity: Activity?) {
        guard let activity else {
            realMapRoute = nil
            realMapStatusMessage = nil
            return
        }
        realMapLoading = true
        realMapStatusMessage = L10n.choose(
            simplifiedChinese: "正在加载真实路线…",
            english: "Loading real route..."
        )
        let currentSelection = activity.id
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try RealMapRouteBuilder.route(for: activity) }
            DispatchQueue.main.async {
                guard selectedRealMapActivityID == currentSelection else { return }
                realMapLoading = false
                switch result {
                case let .success(route):
                    realMapRoute = route
                    realMapStatusMessage = L10n.choose(
                        simplifiedChinese: "已加载路线（本地缓存轨迹+坡度，不缓存地图瓦片）",
                        english: "Route loaded (track+grade cached locally, map tiles not cached)."
                    )
                    if realMapDistanceKm >= route.totalDistanceKm {
                        realMapDistanceKm = route.distanceOnRoute(for: realMapDistanceKm)
                    }
                    realMapCurrentGradePercent = route.grade(at: realMapDistanceKm)
                    configureRealMapCamera(followRider: false)
                case let .failure(error):
                    realMapRoute = nil
                    realMapStatusMessage = error.localizedDescription
                }
            }
        }
    }

    private func startRealMapRide() {
        guard !realMapIsRunning else { return }
        guard realMapRoute != nil else {
            loadRealMapRoute(for: selectedRealMapActivity)
            return
        }
        executionMode = .realMap
        trainer.stopPGMFProgram()
        trainer.stopActivitySimulation()
        pauseWhooshRide()
        realMapIsRunning = true
        realMapLastTickAt = nil
        realMapCurrentPowerW = realMapEffectivePowerW
        realMapCurrentGradePercent = realMapRoute?.grade(at: realMapDistanceKm) ?? 0
        if realMapLiveTrace.isEmpty {
            realMapLiveTrace.append(
                RealMapLivePoint(
                    timestamp: Date(),
                    elapsedSec: 0,
                    distanceKm: 0,
                    speedKPH: 0,
                    powerW: realMapCurrentPowerW,
                    gradePercent: realMapCurrentGradePercent
                )
            )
        }
    }

    private func pauseRealMapRide() {
        realMapIsRunning = false
        realMapLastTickAt = nil
    }

    private func resetRealMapRide() {
        pauseRealMapRide()
        realMapElapsedSec = 0
        realMapDistanceKm = 0
        realMapElevationGainM = 0
        realMapCurrentSpeedKPH = 0
        realMapCurrentPowerW = realMapEffectivePowerW
        realMapCurrentGradePercent = realMapRoute?.grade(at: 0) ?? 0
        realMapLastAppliedGradePercent = nil
        realMapLastAppliedGradeAt = nil
        realMapLiveTrace = []
        configureRealMapCamera(followRider: false)
    }

    private func maybeApplyRealMapGradeToTrainer(at timestamp: Date, gradePercent: Double) {
        guard realMapSyncGradeToTrainer else { return }
        guard trainer.isConnected, trainer.ergAvailable else { return }
        guard executionMode == .realMap else { return }

        let shouldApply: Bool
        if let lastGrade = realMapLastAppliedGradePercent {
            shouldApply = abs(lastGrade - gradePercent) >= 0.3
        } else {
            shouldApply = true
        }
        guard shouldApply else { return }

        if let last = realMapLastAppliedGradeAt, timestamp.timeIntervalSince(last) < 1.5 {
            return
        }
        trainer.setCRSGrade(percent: gradePercent)
        realMapLastAppliedGradePercent = gradePercent
        realMapLastAppliedGradeAt = timestamp
    }

    private func tickRealMap(at timestamp: Date) {
        guard realMapIsRunning else {
            realMapLastTickAt = timestamp
            return
        }
        guard let route = realMapRoute else {
            realMapIsRunning = false
            return
        }

        let previousTick = realMapLastTickAt ?? timestamp
        let dt = min(2.5, max(0.2, timestamp.timeIntervalSince(previousTick)))
        realMapLastTickAt = timestamp
        guard dt > 0 else { return }

        let grade = route.grade(at: realMapDistanceKm)
        let power = realMapEffectivePowerW
        let speed = whooshSpeedKPH(
            powerWatts: power,
            gradePercent: grade,
            cadenceRPM: bikeComputerCadenceRPM
        )
        let deltaKm = speed * dt / 3600.0

        realMapElapsedSec += dt
        realMapDistanceKm += deltaKm
        realMapCurrentGradePercent = grade
        realMapCurrentPowerW = power
        realMapCurrentSpeedKPH = speed
        if grade > 0 {
            realMapElevationGainM += deltaKm * 1000.0 * grade / 100.0
        }
        maybeApplyRealMapGradeToTrainer(at: timestamp, gradePercent: grade)

        realMapLiveTrace.append(
            RealMapLivePoint(
                timestamp: timestamp,
                elapsedSec: realMapElapsedSec,
                distanceKm: realMapDistanceKm,
                speedKPH: speed,
                powerW: power,
                gradePercent: grade
            )
        )
        let cutoff = timestamp.addingTimeInterval(-realMapWindowSeconds)
        realMapLiveTrace.removeAll { $0.timestamp < cutoff }
        if realMapLiveTrace.count > 1200 {
            realMapLiveTrace = Array(realMapLiveTrace.suffix(1200))
        }

        if realMapFollowRider, Int(realMapElapsedSec.rounded()) % 2 == 0 {
            configureRealMapCamera(followRider: true)
        }
    }

    private func whooshProfileElevation(at totalDistanceKm: Double) -> Double {
        let routeDistance = whooshRoute.distanceOnRoute(for: totalDistanceKm)
        guard !whooshProfilePoints.isEmpty else { return 0 }
        guard let nearest = whooshProfilePoints.min(by: {
            abs($0.distanceKm - routeDistance) < abs($1.distanceKm - routeDistance)
        }) else {
            return 0
        }
        return nearest.elevationM
    }

    private func sampledRealMapProfile(_ points: [RealMapRoutePoint], maxCount: Int) -> [RealMapRoutePoint] {
        guard points.count > maxCount, maxCount > 2 else { return points }
        let strideValue = max(1, Int(ceil(Double(points.count) / Double(maxCount))))
        var sampled: [RealMapRoutePoint] = []
        sampled.reserveCapacity(maxCount + 2)
        for (index, point) in points.enumerated() where index % strideValue == 0 || index == points.count - 1 {
            sampled.append(point)
        }
        return sampled
    }

    private func whooshSpeedKPH(powerWatts: Double, gradePercent: Double, cadenceRPM: Double?) -> Double {
        let riderMass = max(45.0, riderProfile.athleteWeightKg)
        let totalMass = riderMass + 9.5
        let grade = gradePercent / 100.0
        let crr = 0.0045
        let rho = 1.226
        let cda = 0.33
        let gravity = 9.80665
        let cadenceFactor: Double
        if let cadenceRPM {
            cadenceFactor = min(max(cadenceRPM / 85.0, 0.86), 1.12)
        } else {
            cadenceFactor = 1.0
        }
        let power = max(60.0, powerWatts * cadenceFactor)

        func requiredPower(at speedMps: Double) -> Double {
            let slopeAngle = atan(grade)
            let rollingForce = crr * totalMass * gravity * cos(slopeAngle)
            let gravityForce = totalMass * gravity * sin(slopeAngle)
            let aeroForce = 0.5 * rho * cda * speedMps * speedMps
            let totalForce = max(-80.0, rollingForce + gravityForce + aeroForce)
            return totalForce * speedMps
        }

        var low = 0.8
        var high = 23.0
        for _ in 0..<28 {
            let mid = (low + high) / 2.0
            if requiredPower(at: mid) > power {
                high = mid
            } else {
                low = mid
            }
        }
        var speedKPH = ((low + high) / 2.0) * 3.6
        if gradePercent < -2.0 {
            speedKPH = max(speedKPH, 26.0 + abs(gradePercent) * 1.8)
        }
        return min(max(speedKPH, 4.5), 75.0)
    }

    private func startWhooshRide() {
        guard !whooshIsRunning else { return }
        whooshIsRunning = true
        whooshLastTickAt = nil
        whooshCurrentGradePercent = whooshRoute.grade(at: whooshDistanceKm)
        whooshCurrentPowerW = whooshEffectivePowerW
        if whooshLiveTrace.isEmpty {
            whooshLiveTrace.append(
                WhooshLivePoint(
                    timestamp: Date(),
                    elapsedSec: 0,
                    speedKPH: 0,
                    powerW: whooshEffectivePowerW,
                    gradePercent: whooshRoute.grade(at: 0)
                )
            )
        }
    }

    private func pauseWhooshRide() {
        whooshIsRunning = false
        whooshLastTickAt = nil
    }

    private func resetWhooshRide() {
        pauseWhooshRide()
        whooshElapsedSec = 0
        whooshDistanceKm = 0
        whooshElevationGainM = 0
        whooshCurrentGradePercent = whooshRoute.grade(at: 0)
        whooshCurrentSpeedKPH = 0
        whooshCurrentPowerW = whooshEffectivePowerW
        whooshLastAppliedGradePercent = nil
        whooshLastAppliedGradeAt = nil
        whooshLiveTrace = []
        whooshBots = WhooshBotState.lineup
    }

    private func maybeApplyWhooshGradeToTrainer(at timestamp: Date, gradePercent: Double) {
        guard whooshSyncGradeToTrainer else { return }
        guard trainer.isConnected, trainer.ergAvailable else { return }
        guard executionMode == .crs else { return }

        let shouldApply: Bool
        if let lastGrade = whooshLastAppliedGradePercent {
            shouldApply = abs(lastGrade - gradePercent) >= 0.3
        } else {
            shouldApply = true
        }
        guard shouldApply else { return }

        if let last = whooshLastAppliedGradeAt, timestamp.timeIntervalSince(last) < 1.5 {
            return
        }
        trainer.setCRSGrade(percent: gradePercent)
        whooshLastAppliedGradePercent = gradePercent
        whooshLastAppliedGradeAt = timestamp
    }

    private func tickWhoosh(at timestamp: Date) {
        guard whooshIsRunning else {
            whooshLastTickAt = timestamp
            return
        }

        let previousTick = whooshLastTickAt ?? timestamp
        let dt = min(2.5, max(0.2, timestamp.timeIntervalSince(previousTick)))
        whooshLastTickAt = timestamp
        guard dt > 0 else { return }

        let grade = whooshRoute.grade(at: whooshDistanceKm)
        let power = whooshEffectivePowerW
        let speed = whooshSpeedKPH(
            powerWatts: power,
            gradePercent: grade,
            cadenceRPM: bikeComputerCadenceRPM
        )
        let deltaKm = speed * dt / 3600.0

        whooshElapsedSec += dt
        whooshDistanceKm += deltaKm
        whooshCurrentGradePercent = grade
        whooshCurrentPowerW = power
        whooshCurrentSpeedKPH = speed
        if grade > 0 {
            whooshElevationGainM += deltaKm * 1000.0 * grade / 100.0
        }
        maybeApplyWhooshGradeToTrainer(at: timestamp, gradePercent: grade)

        let riderWeight = max(45.0, riderProfile.athleteWeightKg)
        for index in whooshBots.indices {
            let botGrade = whooshRoute.grade(at: whooshBots[index].distanceKm)
            let botPower = riderWeight * whooshBots[index].targetWKg
            let baseSpeed = whooshSpeedKPH(powerWatts: botPower, gradePercent: botGrade, cadenceRPM: nil)
            let wave = sin((whooshElapsedSec + Double(index) * 21.0) / 95.0)
            let botSpeed = min(max(baseSpeed * (1.0 + 0.05 * wave), 8.0), 68.0)
            whooshBots[index].speedKPH = botSpeed
            whooshBots[index].distanceKm += botSpeed * dt / 3600.0
        }

        whooshLiveTrace.append(
            WhooshLivePoint(
                timestamp: timestamp,
                elapsedSec: whooshElapsedSec,
                speedKPH: whooshCurrentSpeedKPH,
                powerW: whooshCurrentPowerW,
                gradePercent: whooshCurrentGradePercent
            )
        )
        let cutoff = timestamp.addingTimeInterval(-whooshWindowSeconds)
        whooshLiveTrace.removeAll { $0.timestamp < cutoff }
        if whooshLiveTrace.count > 1200 {
            whooshLiveTrace = Array(whooshLiveTrace.suffix(1200))
        }
    }

    @ViewBuilder
    private var executionModePanel: some View {
        switch executionMode {
        case .erg:
            HStack {
                TextField("Target watts", text: $targetPowerText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)

                Button("Set ERG") {
                    if let watts = Int(targetPowerText) {
                        trainer.setErgTargetPower(watts)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!trainer.ergAvailable)

                Button("ERG -10") {
                    let current = Int(targetPowerText) ?? (trainer.ergTargetWatts ?? 200)
                    let next = max(0, current - 10)
                    targetPowerText = "\(next)"
                    trainer.setErgTargetPower(next)
                }
                .disabled(!trainer.ergAvailable)

                Button("ERG +10") {
                    let current = Int(targetPowerText) ?? (trainer.ergTargetWatts ?? 200)
                    let next = min(2000, current + 10)
                    targetPowerText = "\(next)"
                    trainer.setErgTargetPower(next)
                }
                .disabled(!trainer.ergAvailable)

                Button("Stop ERG") {
                    trainer.stopErg()
                }
                .disabled(!trainer.ergAvailable)
            }
        case .crs:
            HStack {
                TextField("Grade %", text: $gradeText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)

                Button("Set CRS") {
                    if let grade = Double(gradeText) {
                        trainer.setCRSGrade(percent: grade)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!trainer.ergAvailable)

                if let current = trainer.targetGradePercent {
                    Text(String(format: "Current grade %.1f%%", current))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        case .pgmf:
            HStack {
                Picker("Program", selection: Binding(
                    get: { selectedProgramWorkoutID ?? programWorkouts.first?.id ?? UUID() },
                    set: { selectedProgramWorkoutID = $0 }
                )) {
                    ForEach(programWorkouts) { workout in
                        Text("\(workout.name) · \(workout.totalMinutes)min").tag(workout.id)
                    }
                }
                .appDropdownTheme()

                Button("Start PGMF") {
                    guard let id = selectedProgramWorkoutID ?? programWorkouts.first?.id else { return }
                    guard let workout = programWorkouts.first(where: { $0.id == id }) else { return }
                    trainer.startPGMFProgram(
                        segments: workout.segments,
                        ftpWatts: riderProfile.ftpWatts(for: workout.sport)
                    )
                }
                .buttonStyle(.borderedProminent)
                .disabled(!trainer.ergAvailable || programWorkouts.isEmpty)

                Button("Stop PGMF") {
                    trainer.stopPGMFProgram()
                }
            }
        case .simulation:
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Picker("Activity", selection: Binding(
                        get: { selectedSimulationActivityID ?? simulationActivities.first?.id ?? UUID() },
                        set: { selectedSimulationActivityID = $0 }
                    )) {
                        ForEach(simulationActivities.prefix(200)) { activity in
                            Text("\(activity.date.formatted(date: .abbreviated, time: .omitted)) · \(activity.sport.label) · \(activity.durationSec.asDuration)")
                                .tag(activity.id)
                        }
                    }
                    .appDropdownTheme()

                    TextField("x Speed", text: $simulationSpeedText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 90)

                    Button("Start SIM") {
                        guard let id = selectedSimulationActivityID ?? simulationActivities.first?.id else { return }
                        guard let activity = simulationActivities.first(where: { $0.id == id }) else { return }
                        let speed = Double(simulationSpeedText) ?? 8
                        trainer.startActivitySimulation(
                            activity: activity,
                            fallbackFTPWatts: riderProfile.ftpWatts(for: activity.sport),
                            speedMultiplier: speed
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!trainer.ergAvailable || simulationActivities.isEmpty)

                    Button("Stop SIM") {
                        trainer.stopActivitySimulation()
                    }
                }

                if simulationActivities.isEmpty {
                    Text("需要活动包含区间或功率字段才能模拟。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                ProgressView(value: trainer.simulationProgress)
                    .tint(.blue)
                Text(String(format: "SIM speed x%.1f", trainer.simulationSpeedMultiplier))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        case .realMap:
            realMapModeView
        }
    }

    @ViewBuilder
    private var whooshModeView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Picker(
                    L10n.choose(simplifiedChinese: "路线", english: "Route"),
                    selection: $whooshRoute
                ) {
                    ForEach(WhooshRoutePreset.allCases) { route in
                        Text("\(route.title) · \(String(format: "%.1f km", route.totalDistanceKm))")
                            .tag(route)
                    }
                }
                .appDropdownTheme()
                .frame(maxWidth: 340)

                Toggle(
                    L10n.choose(
                        simplifiedChinese: "同步坡度到骑行台",
                        english: "Sync grade to trainer"
                    ),
                    isOn: $whooshSyncGradeToTrainer
                )
                .toggleStyle(.switch)
                .disabled(!trainer.isConnected || !trainer.ergAvailable || executionMode != .crs)

                Spacer()

                Button(
                    whooshIsRunning
                        ? L10n.choose(simplifiedChinese: "暂停", english: "Pause")
                        : L10n.choose(simplifiedChinese: "开始", english: "Start")
                ) {
                    if whooshIsRunning {
                        pauseWhooshRide()
                    } else {
                        startWhooshRide()
                    }
                }
                .buttonStyle(.borderedProminent)

                Button(L10n.choose(simplifiedChinese: "重置", english: "Reset")) {
                    resetWhooshRide()
                }
                .buttonStyle(.bordered)
            }

            Text("\(whooshRoute.subtitle) · \(whooshSegmentName)")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.choose(simplifiedChinese: "视角", english: "View"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("", selection: $whooshCameraMode) {
                        ForEach(Whoosh3DCameraMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .appDropdownTheme()
                    .frame(maxWidth: 220)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(L10n.choose(simplifiedChinese: "缩放", english: "Zoom"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(String(format: "%.2fx", whooshCameraZoom))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 8) {
                        Slider(value: $whooshCameraZoom, in: 0.6...2.4, step: 0.05)
                            .tint(.blue)
                        Button(L10n.choose(simplifiedChinese: "重置", english: "Reset")) {
                            whooshCameraZoom = 1.0
                        }
                        .buttonStyle(.bordered)
                        Button(L10n.choose(simplifiedChinese: "找到玩家", english: "Find Player")) {
                            whooshCameraRecenterToken &+= 1
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }

            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(L10n.choose(simplifiedChinese: "路宽", english: "Road Width"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(String(format: "%.1f m", whooshRoadWidthMeters))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $whooshRoadWidthMeters, in: 0.8...2.4, step: 0.1)
                        .tint(.blue)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(L10n.choose(simplifiedChinese: "护栏高度", english: "Rail Height"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(String(format: "%.2f m", whooshGuardRailHeightMeters))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $whooshGuardRailHeightMeters, in: 0.12...0.9, step: 0.02)
                        .tint(.mint)
                }
            }

            DisclosureGroup(
                L10n.choose(
                    simplifiedChinese: "角色模型",
                    english: "Runner Model"
                ),
                isExpanded: $isWhooshShibaAppearanceExpanded
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.choose(simplifiedChinese: "玩家模型性能模式", english: "Player Model Quality"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Picker("", selection: $whooshPlayerModelQualityMode) {
                            ForEach(WhooshPlayerModelQualityMode.allCases) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .labelsHidden()
                        .appDropdownTheme()
                        .frame(maxWidth: 220)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.choose(simplifiedChinese: "玩家模型", english: "Player Model"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Picker(
                            "",
                            selection: Binding(
                                get: { currentWhooshRunnerModelID },
                                set: { newValue in
                                    updateCurrentPlayerAppearance { $0.whooshRunnerModelID = newValue }
                                }
                            )
                        ) {
                            ForEach(whooshRunnerModelOptions) { option in
                                Text(option.displayName).tag(option.id)
                            }
                        }
                        .labelsHidden()
                        .appDropdownTheme()
                        .disabled(whooshRunnerModelOptions.isEmpty)

                        if !whooshRunnerModelOptions.isEmpty {
                            Text(
                                L10n.choose(
                                    simplifiedChinese: "机器人将从剩余模型中随机选择（稳定分配）。",
                                    english: "Bots will use stable random picks from the remaining models."
                                )
                            )
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.top, 6)
            }

            WhooshRealityKitView(
                profile: whoosh3DProfile,
                totalDistanceKm: whooshRoute.totalDistanceKm,
                riders: whoosh3DRiders,
                playerAppearance: currentPlayerAppearance,
                currentSpeedKPH: whooshCurrentSpeedKPH,
                currentPowerW: whooshCurrentPowerW,
                currentGradePercent: whooshCurrentGradePercent,
                currentLap: whooshLap,
                followPlayer: true,
                cameraMode: whooshCameraMode,
                cameraZoom: $whooshCameraZoom,
                recenterToken: whooshCameraRecenterToken,
                roadWidthMeters: whooshRoadWidthMeters,
                guardRailHeightMeters: whooshGuardRailHeightMeters,
                playerModelQualityMode: whooshPlayerModelQualityMode
            )

            HStack(spacing: 10) {
                ProgressView(value: whooshRouteProgress)
                    .tint(.blue)
                Text(
                    L10n.choose(
                        simplifiedChinese: "本圈 \(Int((whooshRouteProgress * 100).rounded()))%",
                        english: "Lap \(Int((whooshRouteProgress * 100).rounded()))%"
                    )
                )
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                Text(String(format: "%.0f m", whooshPlayerAltitudeM))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                LiveMetricChip(
                    title: L10n.choose(simplifiedChinese: "距离", english: "Distance"),
                    value: String(format: "%.2f km", whooshDistanceKm)
                )
                LiveMetricChip(
                    title: L10n.choose(simplifiedChinese: "圈数", english: "Lap"),
                    value: "\(whooshLap)"
                )
                LiveMetricChip(
                    title: L10n.choose(simplifiedChinese: "坡度", english: "Grade"),
                    value: String(format: "%.1f%%", whooshCurrentGradePercent)
                )
                LiveMetricChip(
                    title: L10n.choose(simplifiedChinese: "速度", english: "Speed"),
                    value: String(format: "%.1f km/h", whooshCurrentSpeedKPH)
                )
                LiveMetricChip(
                    title: L10n.choose(simplifiedChinese: "功率", english: "Power"),
                    value: String(format: "%.0f W", whooshCurrentPowerW)
                )
                LiveMetricChip(
                    title: L10n.choose(simplifiedChinese: "爬升", english: "Elevation Gain"),
                    value: String(format: "%.0f m", whooshElevationGainM)
                )
            }

            Chart {
                ForEach(whooshProfilePoints) { point in
                    let elevation = max(0, point.elevationM)
                    switch chartDisplayMode {
                    case .line:
                        AreaMark(
                            x: .value("Distance", point.distanceKm),
                            y: .value("Elevation", elevation)
                        )
                        .interpolationMethod(.monotone)
                        .foregroundStyle(.blue.opacity(0.13))

                        LineMark(
                            x: .value("Distance", point.distanceKm),
                            y: .value("Elevation", elevation)
                        )
                        .interpolationMethod(.monotone)
                        .foregroundStyle(.blue)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                    case .bar:
                        BarMark(
                            x: .value("Distance", point.distanceKm),
                            y: .value("Elevation", elevation)
                        )
                        .foregroundStyle(.blue.opacity(0.85))
                    case .pie:
                        SectorMark(
                            angle: .value("Elevation", elevation),
                            innerRadius: .ratio(0.55),
                            angularInset: 0.8
                        )
                        .foregroundStyle(.blue.opacity(0.75))
                    case .flame:
                        BarMark(
                            x: .value("Distance", point.distanceKm),
                            y: .value("Elevation", elevation)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.yellow, .orange, .red],
                                startPoint: .bottom,
                                endPoint: .top
                            )
                        )
                    }
                }

                if chartDisplayMode != .pie {
                    RuleMark(x: .value("Player", whooshDistanceOnRouteKm))
                        .foregroundStyle(.blue.opacity(0.35))
                        .lineStyle(StrokeStyle(lineWidth: 1.4, dash: [4, 4]))

                    PointMark(
                        x: .value("Player Distance", whooshDistanceOnRouteKm),
                        y: .value("Player Elevation", whooshProfileElevation(at: whooshDistanceKm))
                    )
                    .foregroundStyle(.blue)
                    .symbolSize(85)

                    ForEach(whooshBots) { bot in
                        let botDistance = whooshRoute.distanceOnRoute(for: bot.distanceKm)
                        PointMark(
                            x: .value("Bot Distance", botDistance),
                            y: .value("Bot Elevation", whooshProfileElevation(at: bot.distanceKm))
                        )
                        .foregroundStyle(bot.tint.opacity(0.9))
                        .symbolSize(45)
                    }
                }
            }
            .chartXAxisLabel(
                L10n.choose(simplifiedChinese: "路线距离 (km)", english: "Route Distance (km)")
            )
            .chartYAxisLabel(
                L10n.choose(simplifiedChinese: "海拔 (m)", english: "Elevation (m)")
            )
            .chartYScale(domain: 0...(whooshProfilePoints.map(\.elevationM).max() ?? 1.0) + 20.0)
            .cartesianHoverTip(
                xTitle: L10n.choose(simplifiedChinese: "距离", english: "Distance"),
                yTitle: L10n.choose(simplifiedChinese: "海拔", english: "Elevation")
            )
            .frame(height: 170)
            .padding(.vertical, 4)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                BikeComputerSparklineCard(
                    label: L10n.choose(simplifiedChinese: "速度", english: "Speed"),
                    value: String(format: "%.1f km/h", whooshCurrentSpeedKPH),
                    averageText: oneMinuteAverage(from: whooshSpeedSparkline).map {
                        String(format: "1m %.1f km/h", $0)
                    } ?? "1m --",
                    tint: .mint,
                    points: whooshSpeedSparkline
                )
                BikeComputerSparklineCard(
                    label: L10n.choose(simplifiedChinese: "功率", english: "Power"),
                    value: String(format: "%.0f W", whooshCurrentPowerW),
                    averageText: oneMinuteAverage(from: whooshPowerSparkline).map {
                        String(format: "1m %.0f W", $0)
                    } ?? "1m --",
                    tint: .orange,
                    points: whooshPowerSparkline
                )
                BikeComputerSparklineCard(
                    label: L10n.choose(simplifiedChinese: "坡度", english: "Grade"),
                    value: String(format: "%.1f%%", whooshCurrentGradePercent),
                    averageText: oneMinuteAverage(from: whooshGradeSparkline).map {
                        String(format: "1m %.1f%%", $0)
                    } ?? "1m --",
                    tint: .purple,
                    points: whooshGradeSparkline
                )
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.choose(simplifiedChinese: "本地排行榜", english: "Local Leaderboard"))
                    .font(.subheadline.bold())
                ForEach(Array(whooshLeaderboard.enumerated()), id: \.element.id) { index, row in
                    let rowLap = max(1, Int(floor(row.distanceKm / whooshRoute.totalDistanceKm)) + 1)
                    let rowOnRoute = whooshRoute.distanceOnRoute(for: row.distanceKm)
                    HStack(spacing: 8) {
                        Text("#\(index + 1)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 26, alignment: .leading)
                        Circle()
                            .fill(row.tint)
                            .frame(width: 8, height: 8)
                        Text(row.name)
                            .font(.subheadline)
                        Spacer()
                        Text("L\(rowLap)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Text(String(format: "%.2f km", rowOnRoute))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Text(String(format: "%.1f km/h", row.speedKPH))
                            .font(.caption.monospacedDigit())
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    init(session: TrainerRiderSession) {
        self.session = session
        _trainer = ObservedObject(wrappedValue: session.trainer)
        _heartRateMonitor = ObservedObject(wrappedValue: session.heartRateMonitor)
        _powerMeter = ObservedObject(wrappedValue: session.powerMeter)
    }

    var body: some View {
        GroupBox("Smart Trainer (Wahoo / Garmin / FTMS)") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("State: \(trainer.bluetoothStateText)")
                        .font(.subheadline)
                    Spacer()
                    if trainer.isConnected {
                        Text("Connected: \(trainer.connectedDeviceName ?? "Trainer") · \(trainer.connectedVendor.label)")
                            .font(.subheadline.bold())
                            .foregroundStyle(.green)
                    }
                }

                HStack {
                    Button(trainer.isScanning ? "Scanning..." : "Scan Trainers") {
                        trainer.startScan()
                    }
                    .disabled(trainer.isScanning)

                    if trainer.isScanning {
                        Button("Stop Scan") {
                            trainer.stopScan()
                        }
                    }

                    if trainer.isConnected {
                        Button("Disconnect", role: .destructive) {
                            trainer.disconnect()
                        }
                    }
                }

                if !trainer.discoveredDevices.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Discovered")
                            .font(.headline)
                        ForEach(trainer.discoveredDevices) { device in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(device.name)
                                    HStack(spacing: 6) {
                                        Text(device.vendor.label)
                                            .font(.caption2)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(.blue.opacity(0.12), in: Capsule())
                                        if device.supportsERG {
                                            Text("ERG")
                                                .font(.caption2)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(.green.opacity(0.15), in: Capsule())
                                        }
                                        if device.supportsPower {
                                            Text("Power")
                                                .font(.caption2)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(.orange.opacity(0.15), in: Capsule())
                                        }
                                    }
                                }
                                Spacer()
                                Text("RSSI \(device.rssi)")
                                    .foregroundStyle(.secondary)
                                Button(device.isConnected ? "Connected" : "Connect") {
                                    trainer.connect(deviceID: device.id)
                                }
                                .disabled(device.isConnected)
                            }
                            .font(.subheadline)
                        }
                    }
                }

                if trainer.isConnected {
                    Divider()

                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 10) {
                            if session.supportsRecording && recordingActive {
                                Label("Recording", systemImage: "record.circle.fill")
                                    .foregroundStyle(.red)
                                Text("Elapsed \(recordingElapsedSec.asDuration) · Samples \(recordingSampleCount)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            } else {
                                Label("Not recording", systemImage: "record.circle")
                                    .foregroundStyle(.secondary)
                            }
                        }

                        HStack(spacing: 8) {
                            if session.supportsRecording && !recordingActive {
                                Button("Start Recording") {
                                    store.startTrainerRecordingNow(for: session.id)
                                }
                                .buttonStyle(.bordered)
                            } else if session.supportsRecording {
                                Button("结束并保存 FIT") {
                                    Task { await store.stopTrainerRecordingNow(for: session.id) }
                                }
                                .buttonStyle(.borderedProminent)
                            } else {
                                Text("Recording disabled for this rider")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    Picker("Mode", selection: $executionMode) {
                        ForEach(TrainerExecutionMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .appDropdownTheme()

                    HStack(spacing: 10) {
                        Text("Telemetry: \(trainer.powerTelemetryAvailable ? "Available" : "Unavailable")")
                            .font(.caption)
                            .foregroundStyle(trainer.powerTelemetryAvailable ? .green : .orange)
                        Text("ERG: \(trainer.ergAvailable ? "Available" : "Unavailable")")
                            .font(.caption)
                            .foregroundStyle(trainer.ergAvailable ? .green : .orange)
                    }

                    HStack(spacing: 14) {
                        LiveMetricChip(title: "Power", value: bikeComputerPowerWatts.map { "\($0) W" } ?? "--")
                        LiveMetricChip(title: "3s Power", value: bikeComputerRolling3sPowerText)
                        LiveMetricChip(title: "10s Power", value: bikeComputerRolling10sPowerText)
                        LiveMetricChip(title: "Speed", value: bikeComputerSpeedText)
                        LiveMetricChip(title: "Cadence", value: bikeComputerCadenceRPM.map { String(format: "%.0f rpm", $0) } ?? "--")
                        LiveMetricChip(title: "Heart Rate", value: bikeComputerHeartRateBPM.map { "\($0) bpm" } ?? "--")
                    }

                    DisclosureGroup(
                        L10n.choose(
                            simplifiedChinese: "展开骑行台 Service 字段 (FTMS)",
                            english: "Show Trainer Service Fields (FTMS)"
                        ),
                        isExpanded: $isTrainerFTMSFieldsExpanded
                    ) {
                        FitnessMachineFieldsView(
                            indoorBikeData: trainer.liveIndoorBikeData,
                            statusEvent: trainer.liveFitnessMachineStatus,
                            trainingStatus: trainer.liveTrainingStatus,
                            featureSet: trainer.fitnessMachineFeatureSet,
                            resistanceRange: trainer.fitnessMachineSupportedResistanceRange,
                            powerRange: trainer.fitnessMachineSupportedPowerRange,
                            rawCharacteristicHex: trainer.fitnessMachineRawCharacteristicHex
                        )
                        .padding(.top, 6)
                    }

                    if let cps = trainer.liveCyclingPowerMeasurement {
                        DisclosureGroup(
                            L10n.choose(
                                simplifiedChinese: "展开骑行台 CPS 字段",
                                english: "Show Trainer CPS Fields"
                            ),
                            isExpanded: $isTrainerCPSFieldsExpanded
                        ) {
                            CyclingPowerFieldsView(
                                title: L10n.choose(
                                    simplifiedChinese: "骑行台 CPS 字段（2A63）",
                                    english: "Trainer CPS Fields (2A63)"
                                ),
                                measurement: cps
                            )
                            .padding(.top, 6)
                        }
                    }

                    if powerMeter.isConnected, let cps = powerMeter.liveCyclingPowerMeasurement {
                        DisclosureGroup(
                            L10n.choose(
                                simplifiedChinese: "展开功率计 CPS 字段",
                                english: "Show Power Meter CPS Fields"
                            ),
                            isExpanded: $isPowerMeterCPSFieldsExpanded
                        ) {
                            CyclingPowerFieldsView(
                                title: L10n.choose(
                                    simplifiedChinese: "功率计 CPS 字段（2A63）",
                                    english: "Power Meter CPS Fields (2A63)"
                                ),
                                measurement: cps
                            )
                            .padding(.top, 6)
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        let series = bikeComputerSparklineSeries
                        HStack(alignment: .firstTextBaseline) {
                            Text("实时码表")
                                .font(.subheadline.bold())
                            Spacer()
                            Text("骑行时间 \(bikeComputerElapsedText)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        HStack(spacing: 8) {
                            LiveMetricChip(title: "Lap Time", value: bikeComputerLapElapsedText)
                            LiveMetricChip(title: "Lap Power", value: bikeComputerLapPowerText)
                            LiveMetricChip(title: "Lap HR", value: bikeComputerLapHeartRateText)
                            LiveMetricChip(title: "Lap NP", value: bikeComputerLapNPText)
                            Button {
                                markBikeComputerLap()
                            } label: {
                                Label("Lap", systemImage: "flag.checkered")
                            }
                            .buttonStyle(.bordered)
                        }
                        HStack(spacing: 8) {
                            LiveMetricChip(title: "NP", value: bikeComputerLiveNPText)
                            LiveMetricChip(title: "IF", value: bikeComputerIFText)
                            LiveMetricChip(title: "Est. TSS", value: bikeComputerEstimatedTSSText)
                        }
                        HStack(spacing: 8) {
                            LiveMetricChip(title: "Best 5s", value: bikeComputerBest5sPowerText)
                            LiveMetricChip(title: "Best 1m", value: bikeComputerBest1mPowerText)
                            LiveMetricChip(title: "Best 5m", value: bikeComputerBest5mPowerText)
                        }
                        HStack(spacing: 12) {
                            Toggle("Auto Lap", isOn: $bikeComputerAutoLapEnabled)
                                .toggleStyle(.switch)
                            Text("每 \(bikeComputerAutoLapEverySec / 60) 分钟")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if let alert = bikeComputerTargetAlertText {
                            Label(alert, systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                        if let alert = bikeComputerHRAlertText {
                            Label(alert, systemImage: "heart.fill")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                        if let alert = bikeComputerHydrationAlertText {
                            Label(alert, systemImage: "drop.fill")
                                .font(.caption)
                                .foregroundStyle(.blue)
                        }
                        if let alert = bikeComputerCarbAlertText {
                            Label(alert, systemImage: "fork.knife")
                                .font(.caption)
                                .foregroundStyle(.mint)
                        }
                        HStack(alignment: .top, spacing: 12) {
                            BikeComputerZoneBreakdownView(
                                title: "功率分区",
                                summaryText: bikeComputerZoneSummaryText,
                                rows: bikeComputerZoneRows,
                                tint: .orange
                            )
                            BikeComputerZoneBreakdownView(
                                title: "心率分区",
                                summaryText: bikeComputerHeartRateZoneSummaryText,
                                rows: bikeComputerHeartRateZoneRows,
                                tint: .red
                            )
                        }
                        Text(bikeComputerWindowTitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                            BikeComputerSparklineCard(
                                label: "功率",
                                value: bikeComputerPowerWatts.map { "\($0) W" } ?? "--",
                                averageText: series.power.oneMinuteAverage.map { String(format: "均值 %.0f W", $0) } ?? "均值 --",
                                tint: .orange,
                                points: series.power.points
                            )
                            BikeComputerSparklineCard(
                                label: "心率",
                                value: bikeComputerHeartRateBPM.map { "\($0) bpm" } ?? "--",
                                averageText: series.heartRate.oneMinuteAverage.map { String(format: "均值 %.0f bpm", $0) } ?? "均值 --",
                                tint: .red,
                                points: series.heartRate.points
                            )
                            BikeComputerSparklineCard(
                                label: "踏频",
                                value: bikeComputerCadenceText,
                                averageText: series.cadence.oneMinuteAverage.map { String(format: "均值 %.0f rpm", $0) } ?? "均值 --",
                                tint: .green,
                                points: series.cadence.points
                            )
                            BikeComputerBalanceCompositeCard(
                                label: "左右平衡",
                                value: bikeComputerBalanceText,
                                detailText: bikeComputerBalanceContextText(from: series),
                                leftPoints: series.balanceLeft.points,
                                rightPoints: series.balanceRight.points,
                                cumulativeLeftPercent: bikeComputerCumulativeBalanceLeftPercent,
                                cumulativeRightPercent: bikeComputerCumulativeBalanceRightPercent
                            )
                            .gridCellColumns(2)
                            BikeComputerSparklineCard(
                                label: "RR 间期",
                                value: heartRateMonitor.liveRRIntervalMS.map { String(format: "%.0f ms", $0) } ?? "--",
                                averageText: series.rr.oneMinuteAverage.map { String(format: "均值 %.0f ms", $0) } ?? "均值 --",
                                tint: .pink,
                                points: series.rr.points
                            )
                            BikeComputerSparklineCard(
                                label: "HRV RMSSD",
                                value: heartRateMonitor.liveHRVRMSSDMS.map { String(format: "%.1f ms", $0) } ?? "--",
                                averageText: series.hrv.oneMinuteAverage.map { String(format: "均值 %.1f ms", $0) } ?? "均值 --",
                                tint: .teal,
                                points: series.hrv.points
                            )
                            BikeComputerSparklineCard(
                                label: "累计消耗",
                                value: bikeComputerCaloriesText,
                                averageText: bikeComputerCaloriesContextText,
                                tint: .brown,
                                points: series.calories.points
                            )
                        }
                    }

                    executionModePanel
                    if Self.whooshMiniGameEnabled {
                        whooshModeView
                    }

                    if let target = trainer.ergTargetWatts {
                        Text("Current ERG Target: \(target) W")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let phase = trainer.programPhase {
                        Text(phase)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let message = trainer.lastMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if session.supportsRecording, let fitPath = recordingStatus.lastFitPath {
                    Text("Last FIT: \(fitPath)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .textSelection(.enabled)
                }
                if session.supportsRecording, let syncSummary = recordingStatus.lastSyncSummary {
                    Text(syncSummary)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
        }
        .onAppear {
            if let target = trainer.ergTargetWatts {
                targetPowerText = "\(target)"
            }
            let trainerMode = trainer.executionMode
            executionMode = trainerMode
            if let currentGrade = trainer.targetGradePercent {
                gradeText = String(format: "%.1f", currentGrade)
            }
            if selectedProgramWorkoutID == nil {
                selectedProgramWorkoutID = programWorkouts.first?.id
            }
            if selectedSimulationActivityID == nil {
                selectedSimulationActivityID = simulationActivities.first?.id
            }
            if selectedRealMapActivityID == nil {
                selectedRealMapActivityID = realMapActivities.first?.id
            }
            if Self.whooshMiniGameEnabled {
                whooshCurrentGradePercent = whooshRoute.grade(at: whooshDistanceKm)
                whooshCurrentPowerW = whooshEffectivePowerW
            } else {
                whooshIsRunning = false
                whooshSyncGradeToTrainer = false
            }
            realMapCurrentPowerW = realMapEffectivePowerW
            realMapCurrentGradePercent = realMapRoute?.grade(at: realMapDistanceKm) ?? 0
            if executionMode == .realMap {
                loadRealMapRoute(for: selectedRealMapActivity)
            }
            resetBikeComputerSessionState()
            appendBikeComputerTraceSample()
        }
        .onChange(of: recordingActive) { wasActive, isActive in
            guard !wasActive, isActive else { return }
            resetBikeComputerSessionState()
            appendBikeComputerTraceSample()
        }
        .onChange(of: executionMode) { _, mode in
            if mode != .realMap {
                pauseRealMapRide()
                realMapSyncGradeToTrainer = false
            }
            if mode == .realMap {
                trainer.stopPGMFProgram()
                trainer.stopActivitySimulation()
                if realMapRoute == nil {
                    loadRealMapRoute(for: selectedRealMapActivity)
                } else {
                    realMapCurrentGradePercent = realMapRoute?.grade(at: realMapDistanceKm) ?? 0
                    realMapCurrentPowerW = realMapEffectivePowerW
                    configureRealMapCamera(followRider: false)
                }
            }
            if mode != .crs {
                whooshSyncGradeToTrainer = false
            }
        }
        .onChange(of: selectedRealMapActivityID) { _, _ in
            resetRealMapRide()
            loadRealMapRoute(for: selectedRealMapActivity)
        }
        .onChange(of: realMapActivities.map(\.id)) { _, ids in
            if let selected = selectedRealMapActivityID {
                if !ids.contains(selected) {
                    selectedRealMapActivityID = ids.first
                }
            } else {
                selectedRealMapActivityID = ids.first
            }
        }
        .onChange(of: realMapFollowRider) { _, isOn in
            guard executionMode == .realMap else { return }
            configureRealMapCamera(followRider: isOn)
        }
        .onChange(of: whooshRoute) { _, _ in
            guard Self.whooshMiniGameEnabled else { return }
            whooshCurrentGradePercent = whooshRoute.grade(at: whooshDistanceKm)
        }
        .onReceive(bikeComputerTimer) { timestamp in
            appendBikeComputerTraceSample(at: timestamp)
            tickRealMap(at: timestamp)
            if Self.whooshMiniGameEnabled {
                tickWhoosh(at: timestamp)
            }
        }
    }
}

private struct BikeComputerTracePoint: Identifiable {
    let id = UUID()
    let timestamp: Date
    let elapsedSec: Int
    let powerWatts: Double?
    let cadenceRPM: Double?
    let heartRateBPM: Double?
    let speedKPH: Double?
    let elevationMeters: Double?
    let balanceLeftPercent: Double?
    let balanceRightPercent: Double?
    let rrIntervalMS: Double?
    let hrvRMSSDMS: Double?
    let energyExpendedKJ: Double?
    let estimatedCaloriesKCal: Double?
}

private struct SparklinePoint: Identifiable {
    let timestamp: Date
    let value: Double
    var id: Date { timestamp }
}

private struct BikeComputerSparklineSeries {
    struct MetricSeries {
        private(set) var points: [SparklinePoint] = []
        private var oneMinuteSum: Double = 0
        private var oneMinuteCount: Int = 0

        mutating func append(_ value: Double, timestamp: Date, minuteCutoff: Date) {
            points.append(SparklinePoint(timestamp: timestamp, value: value))
            if timestamp >= minuteCutoff {
                oneMinuteSum += value
                oneMinuteCount += 1
            }
        }

        var oneMinuteAverage: Double? {
            guard oneMinuteCount > 0 else { return nil }
            return oneMinuteSum / Double(oneMinuteCount)
        }
    }

    var power = MetricSeries()
    var heartRate = MetricSeries()
    var cadence = MetricSeries()
    var balanceLeft = MetricSeries()
    var balanceRight = MetricSeries()
    var rr = MetricSeries()
    var hrv = MetricSeries()
    var calories = MetricSeries()
}

private struct ChartModeMenuButton: View {
    @Binding var selection: AppChartDisplayMode

    var body: some View {
        Menu {
            ForEach(AppChartDisplayMode.allCases) { mode in
                Button {
                    selection = mode
                } label: {
                    Label(mode.title, systemImage: mode.symbol)
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: selection.symbol)
                    .font(.caption.weight(.semibold))
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.semibold))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(.regularMaterial, in: Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(.secondary.opacity(0.22), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct BikeComputerZoneBreakdownView: View {
    let title: String
    let summaryText: String
    let rows: [(name: String, seconds: Int, percent: Double)]
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.bold())
                .foregroundStyle(tint)
            Text(summaryText)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            VStack(spacing: 6) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 8) {
                        Text(row.name)
                            .font(.caption2.monospacedDigit())
                            .frame(width: 28, alignment: .leading)
                        ProgressView(value: row.percent)
                            .tint(tint)
                        Text(row.seconds.asDuration)
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 54, alignment: .trailing)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

private struct BikeComputerSparklineCard: View {
    @State private var chartDisplayMode: AppChartDisplayMode = .line
    let label: String
    let value: String
    let averageText: String
    let tint: Color
    let points: [SparklinePoint]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                ChartModeMenuButton(selection: $chartDisplayMode)
            }
            HStack(alignment: .firstTextBaseline) {
                Text(value)
                    .font(.subheadline.monospacedDigit().bold())
                Spacer()
                Text(averageText)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if points.count >= 1 {
                let renderPoints = Array(points.suffix(60))
                let chartPoints = chartDisplayMode == .pie ? Array(renderPoints.suffix(24)) : renderPoints
                let lineDomain = chartDisplayMode == .line ? lineYDomain(points: renderPoints) : nil
                let chart = Chart(chartPoints) { point in
                    switch chartDisplayMode {
                    case .line:
                        LineMark(
                            x: .value("Time", point.timestamp),
                            y: .value("Value", point.value)
                        )
                        .foregroundStyle(tint)
                        .interpolationMethod(.linear)
                        .lineStyle(StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                        if renderPoints.count == 1 {
                            PointMark(
                                x: .value("Time", point.timestamp),
                                y: .value("Value", point.value)
                            )
                            .foregroundStyle(tint)
                            .symbolSize(26)
                        }
                    case .bar:
                        BarMark(
                            x: .value("Time", point.timestamp),
                            y: .value("Value", max(0, point.value))
                        )
                        .foregroundStyle(tint.opacity(0.85))
                    case .pie:
                        SectorMark(
                            angle: .value("Value", max(0, point.value)),
                            innerRadius: .ratio(0.56),
                            angularInset: 1.0
                        )
                        .foregroundStyle(tint.opacity(0.75))
                    case .flame:
                        BarMark(
                            x: .value("Time", point.timestamp),
                            y: .value("Value", max(0, point.value))
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.yellow, .orange, tint],
                                startPoint: .bottom,
                                endPoint: .top
                            )
                        )
                    }
                }
                Group {
                    if chartDisplayMode == .line, let domain = lineDomain {
                        chart.chartYScale(domain: domain)
                    } else {
                        chart
                    }
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .chartPlotStyle { plotArea in
                    plotArea
                        .background(tint.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .cartesianHoverTip(
                    xTitle: L10n.choose(simplifiedChinese: "时间", english: "Time"),
                    yTitle: label
                )
                .frame(height: 48)
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(tint.opacity(0.08))
                    .frame(height: 48)
                    .overlay(
                        Text("等待数据")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    )
            }
        }
        .padding(8)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    private func lineYDomain(points: [SparklinePoint]) -> ClosedRange<Double>? {
        guard !points.isEmpty else { return nil }
        var minValue = points[0].value
        var maxValue = points[0].value
        for point in points.dropFirst() {
            minValue = min(minValue, point.value)
            maxValue = max(maxValue, point.value)
        }
        if abs(maxValue - minValue) < 0.0001 {
            let pad = max(1, abs(maxValue) * 0.06)
            return (minValue - pad)...(maxValue + pad)
        }
        let pad = (maxValue - minValue) * 0.12
        return (minValue - pad)...(maxValue + pad)
    }
}

private struct BalancePieSlice: Identifiable {
    let label: String
    let percent: Double
    let color: Color
    var id: String { label }
}

private struct BikeComputerBalanceCompositeCard: View {
    @State private var chartDisplayMode: AppChartDisplayMode = .line
    let label: String
    let value: String
    let detailText: String
    let leftPoints: [SparklinePoint]
    let rightPoints: [SparklinePoint]
    let cumulativeLeftPercent: Double?
    let cumulativeRightPercent: Double?

    private var pieSlices: [BalancePieSlice] {
        guard let left = cumulativeLeftPercent,
              let right = cumulativeRightPercent else { return [] }
        return [
            BalancePieSlice(label: "Left", percent: left, color: .purple),
            BalancePieSlice(label: "Right", percent: right, color: .indigo)
        ]
    }

    private var pieSummaryText: String {
        guard let left = cumulativeLeftPercent,
              let right = cumulativeRightPercent else {
            return "累计 --"
        }
        return String(format: "累计 L%.1f%% / R%.1f%%", left, right)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                ChartModeMenuButton(selection: $chartDisplayMode)
            }
            HStack(alignment: .firstTextBaseline) {
                Text(value)
                    .font(.subheadline.monospacedDigit().bold())
                Spacer()
                Text(detailText)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                if !leftPoints.isEmpty || !rightPoints.isEmpty {
                    let leftRender = Array(leftPoints.suffix(60))
                    let rightRender = Array(rightPoints.suffix(60))
                    Chart {
                        switch chartDisplayMode {
                        case .line:
                            ForEach(leftRender) { point in
                                LineMark(
                                    x: .value("Time", point.timestamp),
                                    y: .value("Left", point.value)
                                )
                                .foregroundStyle(.purple)
                                .interpolationMethod(.linear)
                                .lineStyle(StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                            }
                            if leftRender.count == 1, let point = leftRender.first {
                                PointMark(
                                    x: .value("Time", point.timestamp),
                                    y: .value("Left", point.value)
                                )
                                .foregroundStyle(.purple)
                                .symbolSize(22)
                            }

                            ForEach(rightRender) { point in
                                LineMark(
                                    x: .value("Time", point.timestamp),
                                    y: .value("Right", point.value)
                                )
                                .foregroundStyle(.indigo)
                                .interpolationMethod(.linear)
                                .lineStyle(StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                            }
                            if rightRender.count == 1, let point = rightRender.first {
                                PointMark(
                                    x: .value("Time", point.timestamp),
                                    y: .value("Right", point.value)
                                )
                                .foregroundStyle(.indigo)
                                .symbolSize(22)
                            }
                        case .bar:
                            ForEach(leftRender) { point in
                                BarMark(
                                    x: .value("Time", point.timestamp),
                                    y: .value("Left", max(0, point.value))
                                )
                                .foregroundStyle(.purple.opacity(0.85))
                            }
                            ForEach(rightRender) { point in
                                BarMark(
                                    x: .value("Time", point.timestamp),
                                    y: .value("Right", max(0, point.value))
                                )
                                .foregroundStyle(.indigo.opacity(0.65))
                            }
                        case .pie:
                            let leftMean = leftRender.isEmpty ? 0 : leftRender.map(\.value).reduce(0, +) / Double(leftRender.count)
                            let rightMean = rightRender.isEmpty ? 0 : rightRender.map(\.value).reduce(0, +) / Double(rightRender.count)
                            SectorMark(
                                angle: .value("Left", max(0, leftMean)),
                                innerRadius: .ratio(0.56),
                                angularInset: 1
                            )
                            .foregroundStyle(.purple)
                            SectorMark(
                                angle: .value("Right", max(0, rightMean)),
                                innerRadius: .ratio(0.56),
                                angularInset: 1
                            )
                            .foregroundStyle(.indigo)
                        case .flame:
                            ForEach(leftRender) { point in
                                BarMark(
                                    x: .value("Time", point.timestamp),
                                    y: .value("Left", max(0, point.value))
                                )
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [.yellow, .orange, .purple],
                                        startPoint: .bottom,
                                        endPoint: .top
                                    )
                                )
                            }
                            ForEach(rightRender) { point in
                                BarMark(
                                    x: .value("Time", point.timestamp),
                                    y: .value("Right", max(0, point.value))
                                )
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [.yellow, .orange, .indigo],
                                        startPoint: .bottom,
                                        endPoint: .top
                                    )
                                )
                            }
                        }

                        RuleMark(y: .value("Center", 50))
                            .foregroundStyle(.secondary.opacity(0.35))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    }
                    .chartXAxis(.hidden)
                    .chartYAxis(.hidden)
                    .chartYScale(domain: 0...100)
                    .chartPlotStyle { plotArea in
                        plotArea
                            .background(Color.purple.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .cartesianHoverTip(
                        xTitle: L10n.choose(simplifiedChinese: "时间", english: "Time"),
                        yTitle: label
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: 74)
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.purple.opacity(0.08))
                        .frame(maxWidth: .infinity)
                        .frame(height: 74)
                        .overlay(
                            Text("等待数据")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        )
                }

                VStack(spacing: 4) {
                    if pieSlices.isEmpty {
                        Circle()
                            .fill(.secondary.opacity(0.18))
                            .frame(width: 64, height: 64)
                            .overlay(
                                Text("--")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            )
                    } else {
                        Chart(pieSlices) { slice in
                            SectorMark(
                                angle: .value("Percent", slice.percent),
                                innerRadius: .ratio(0.56),
                                angularInset: 1
                            )
                            .foregroundStyle(slice.color)
                        }
                        .chartLegend(.hidden)
                        .frame(width: 64, height: 64)
                    }

                    Text(pieSummaryText)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(width: 132)
            }
        }
        .padding(8)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct LiveMetricChip: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline.monospacedDigit())
        }
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }
}
