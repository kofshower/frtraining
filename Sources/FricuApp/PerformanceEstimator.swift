import Foundation

struct SportPerformanceEstimate {
    let cycling: CyclingPerformanceEstimate
    let running: RunningPerformanceEstimate
}

struct CyclingPerformanceEstimate {
    let estimatedHourPower: Int
    let readinessScore: Int
    let method: String
    let parameters: [String]
    let confidence: String
}

struct RunningPerformanceEstimate {
    let estimatedThresholdPaceMinPerKm: Double?
    let estimated10kTimeSec: Int?
    let readinessScore: Int
    let method: String
    let parameters: [String]
    let confidence: String
}

struct SportProfileEstimate: Identifiable {
    var id: String { sport.rawValue }
    let sport: SportType
    let ftpWatts: Int
    let thresholdHeartRate: Int
    let ftpConfidence: String
    let thresholdConfidence: String
    let ftpSamples: Int
    let thresholdSamples: Int
    let methodSummary: String
}

struct ProfilePhysioEstimate {
    let generatedAt: Date
    let items: [SportProfileEstimate]
}

enum SportPerformanceEstimator {
    static func estimate(
        activities: [Activity],
        loadSeries: [DailyLoadPoint],
        profile: AthleteProfile,
        wellness: [WellnessSample]
    ) -> SportPerformanceEstimate {
        let tsb = loadSeries.last?.tsb ?? 0
        let latestHRV = wellness.sorted { $0.date > $1.date }.compactMap { $0.hrv }.first ?? profile.hrvToday
        let hrvBaseline = max(1.0, profile.hrvBaseline)
        let hrvRatio = latestHRV / hrvBaseline
        let readinessFactor = readinessFactor(tsb: tsb, hrvRatio: hrvRatio)
        let readinessScore = readinessScore(tsb: tsb, hrvRatio: hrvRatio)

        let cycling = estimateCycling(
            activities: activities,
            profile: profile,
            tsb: tsb,
            latestHRV: latestHRV,
            hrvBaseline: hrvBaseline,
            hrvRatio: hrvRatio,
            readinessFactor: readinessFactor,
            readinessScore: readinessScore
        )

        let running = estimateRunning(
            activities: activities,
            profile: profile,
            tsb: tsb,
            latestHRV: latestHRV,
            hrvBaseline: hrvBaseline,
            hrvRatio: hrvRatio,
            readinessFactor: readinessFactor,
            readinessScore: readinessScore
        )

        return SportPerformanceEstimate(cycling: cycling, running: running)
    }

    private static func estimateCycling(
        activities: [Activity],
        profile: AthleteProfile,
        tsb: Double,
        latestHRV: Double,
        hrvBaseline: Double,
        hrvRatio: Double,
        readinessFactor: Double,
        readinessScore: Int
    ) -> CyclingPerformanceEstimate {
        let cyclingFTP = profile.ftpWatts(for: .cycling)
        let recent = activitiesWithin(days: 14, sport: .cycling, activities: activities)
        let volumeHours = recent.reduce(0.0) { $0 + Double($1.durationSec) / 3600.0 }
        let ifValues = recent.compactMap { activity -> Double? in
            guard let np = activity.normalizedPower, cyclingFTP > 0 else { return nil }
            return Double(np) / Double(cyclingFTP)
        }
        let avgIF = ifValues.isEmpty ? nil : ifValues.reduce(0, +) / Double(ifValues.count)

        let specificityAdj = bounded((volumeHours - 6.0) / 100.0, min: -0.04, max: 0.04)
        let ifAdj = bounded(((avgIF ?? 0.82) - 0.82) * 0.08, min: -0.02, max: 0.02)
        let totalFactor = bounded(readinessFactor * (1 + specificityAdj + ifAdj), min: 0.82, max: 1.08)
        let estimatedPower = Int((Double(cyclingFTP) * totalFactor).rounded())

        let confidence: String
        if volumeHours >= 7, avgIF != nil {
            confidence = "High"
        } else if volumeHours >= 3 {
            confidence = "Medium"
        } else {
            confidence = "Low"
        }

        var parameters: [String] = [
            "FTP=\(cyclingFTP)W",
            String(format: "TSB=%.1f", tsb),
            String(format: "HRV=%.1f/%.1f (%.0f%%)", latestHRV, hrvBaseline, hrvRatio * 100),
            String(format: "CyclingVolume14d=%.1fh", volumeHours),
            String(format: "ReadyFactor=%.3f", readinessFactor)
        ]
        if let avgIF {
            parameters.append(String(format: "AvgIF14d=%.2f", avgIF))
        }

        return CyclingPerformanceEstimate(
            estimatedHourPower: max(1, estimatedPower),
            readinessScore: readinessScore,
            method: "P60 = FTP × ReadyFactor × (1 + VolumeAdj + IntensityAdj)",
            parameters: parameters,
            confidence: confidence
        )
    }

    private static func estimateRunning(
        activities: [Activity],
        profile: AthleteProfile,
        tsb: Double,
        latestHRV: Double,
        hrvBaseline: Double,
        hrvRatio: Double,
        readinessFactor: Double,
        readinessScore: Int
    ) -> RunningPerformanceEstimate {
        let runningThresholdHR = profile.thresholdHeartRate(for: .running, on: Date())
        let recent = activitiesWithin(days: 28, sport: .running, activities: activities)
            .filter { $0.distanceKm >= 3.0 && $0.durationSec >= 20 * 60 }

        let thresholdCandidates = recent.filter { activity in
            let thresholdHR = profile.thresholdHeartRate(for: .running, on: activity.date)
            guard let hr = activity.avgHeartRate, thresholdHR > 0 else { return false }
            let ratio = Double(hr) / Double(thresholdHR)
            return ratio >= 0.90 && ratio <= 1.03
        }

        let baseThresholdPace: Double?
        if thresholdCandidates.count >= 2 {
            baseThresholdPace = weightedPace(thresholdCandidates)
        } else if recent.count >= 3 {
            baseThresholdPace = weightedPace(recent).map { $0 * 0.93 }
        } else {
            baseThresholdPace = nil
        }

        let runKm28 = recent.reduce(0.0) { $0 + $1.distanceKm }
        let volumeAdj = bounded((runKm28 - 35.0) / 700.0, min: -0.03, max: 0.03)
        let readinessAdj = bounded((readinessFactor - 1.0) * 0.5, min: -0.08, max: 0.06)

        let estimatedThresholdPace: Double?
        if let baseThresholdPace {
            let adjusted = baseThresholdPace * (1.0 - volumeAdj - readinessAdj)
            estimatedThresholdPace = bounded(adjusted, min: 2.6, max: 9.0)
        } else {
            estimatedThresholdPace = nil
        }

        let estimated10kTimeSec: Int?
        if let pace = estimatedThresholdPace {
            estimated10kTimeSec = Int((pace * 10.0 * 60.0 * 1.04).rounded())
        } else {
            estimated10kTimeSec = nil
        }

        let confidence: String
        if thresholdCandidates.count >= 2 && recent.count >= 6 {
            confidence = "High"
        } else if recent.count >= 3 {
            confidence = "Medium"
        } else {
            confidence = "Low"
        }

        var parameters: [String] = [
            String(format: "LTHR=%dbpm", runningThresholdHR),
            String(format: "TSB=%.1f", tsb),
            String(format: "HRV=%.1f/%.1f (%.0f%%)", latestHRV, hrvBaseline, hrvRatio * 100),
            String(format: "RunKm28d=%.1fkm", runKm28),
            String(format: "ReadyFactor=%.3f", readinessFactor),
            "RunSamples=\(recent.count)"
        ]
        if !thresholdCandidates.isEmpty {
            parameters.append("ThresholdHRSamples=\(thresholdCandidates.count)")
        }

        return RunningPerformanceEstimate(
            estimatedThresholdPaceMinPerKm: estimatedThresholdPace,
            estimated10kTimeSec: estimated10kTimeSec,
            readinessScore: readinessScore,
            method: "ThresholdPace = BasePace × (1 - VolumeAdj - ReadinessAdj); 10k ≈ ThresholdPace × 1.04",
            parameters: parameters,
            confidence: confidence
        )
    }

    private static func activitiesWithin(days: Int, sport: SportType, activities: [Activity]) -> [Activity] {
        let start = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        return activities.filter { $0.sport == sport && $0.date >= start }
    }

    private static func weightedPace(_ activities: [Activity]) -> Double? {
        var numerator = 0.0
        var denominator = 0.0
        for activity in activities {
            guard activity.distanceKm > 0, activity.durationSec > 0 else { continue }
            let pace = (Double(activity.durationSec) / 60.0) / activity.distanceKm
            numerator += pace * activity.distanceKm
            denominator += activity.distanceKm
        }
        guard denominator > 0 else { return nil }
        return numerator / denominator
    }

    private static func readinessFactor(tsb: Double, hrvRatio: Double) -> Double {
        let fatiguePenalty = bounded(((-tsb - 5.0) / 25.0), min: 0, max: 0.25)
        let freshnessBoost = bounded((tsb - 5.0) / 20.0, min: 0, max: 0.08)
        let hrvPenalty = bounded((0.98 - hrvRatio) / 0.20, min: 0, max: 0.20)
        let hrvBoost = bounded((hrvRatio - 1.0) / 0.20, min: 0, max: 0.08)
        return bounded(1.0 - fatiguePenalty - hrvPenalty + freshnessBoost + hrvBoost, min: 0.75, max: 1.12)
    }

    private static func readinessScore(tsb: Double, hrvRatio: Double) -> Int {
        var score = 68.0
        score += bounded((tsb + 10.0) * 1.2, min: -24, max: 18)
        score += bounded((hrvRatio - 1.0) * 60.0, min: -24, max: 12)
        return Int(bounded(score, min: 1, max: 99).rounded())
    }
}

enum AthleteProfileAutoEstimator {
    private struct WeightedSample {
        let value: Double
        let weight: Double
    }

    static func evaluate(
        activities: [Activity],
        profile: AthleteProfile,
        now: Date = Date()
    ) -> ProfilePhysioEstimate {
        let items = SportType.allCases.map { sport in
            estimateSport(sport: sport, activities: activities, profile: profile, now: now)
        }
        return ProfilePhysioEstimate(generatedAt: now, items: items)
    }

    private static func estimateSport(
        sport: SportType,
        activities: [Activity],
        profile: AthleteProfile,
        now: Date
    ) -> SportProfileEstimate {
        let recent = activitiesWithin(days: 120, sport: sport, activities: activities)
            .sorted { $0.date > $1.date }

        let ftp = estimateFTP(sport: sport, activities: recent, profile: profile, now: now)
        let threshold = estimateThresholdHR(
            sport: sport,
            activities: recent,
            profile: profile,
            ftpEstimate: ftp.value,
            now: now
        )

        return SportProfileEstimate(
            sport: sport,
            ftpWatts: max(1, Int(ftp.value.rounded())),
            thresholdHeartRate: max(1, Int(threshold.value.rounded())),
            ftpConfidence: confidenceLabel(sampleCount: ftp.samples),
            thresholdConfidence: confidenceLabel(sampleCount: threshold.samples),
            ftpSamples: ftp.samples,
            thresholdSamples: threshold.samples,
            methodSummary: "FTP: NP+时长+TSS反推加权；LTHR: 阈值强度心率样本加权"
        )
    }

    private static func activitiesWithin(days: Int, sport: SportType, activities: [Activity]) -> [Activity] {
        let start = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        return activities.filter { $0.sport == sport && $0.date >= start }
    }

    private static func estimateFTP(
        sport: SportType,
        activities: [Activity],
        profile: AthleteProfile,
        now: Date
    ) -> (value: Double, samples: Int) {
        let currentFTP = Double(max(profile.ftpWatts(for: sport), 1))
        var candidates: [WeightedSample] = []

        for activity in activities {
            guard let np = activity.normalizedPower, np > 0 else { continue }
            guard activity.durationSec >= 15 * 60 else { continue }

            let durationMin = Double(activity.durationSec) / 60.0
            let hours = max(Double(activity.durationSec) / 3600.0, 1.0 / 60.0)

            let durationAdjustedFTP: Double
            switch durationMin {
            case ..<20:
                durationAdjustedFTP = Double(np) * 0.90
            case ..<35:
                durationAdjustedFTP = Double(np) * 0.93
            case ..<50:
                durationAdjustedFTP = Double(np) * 0.97
            case ..<85:
                durationAdjustedFTP = Double(np)
            default:
                durationAdjustedFTP = Double(np) * 1.02
            }

            var merged = durationAdjustedFTP
            if activity.tss > 0 {
                let ifFromTSS = sqrt(Double(activity.tss) / (100.0 * hours))
                if ifFromTSS.isFinite, ifFromTSS >= 0.55, ifFromTSS <= 1.35 {
                    let ftpFromTSS = Double(np) / max(0.55, ifFromTSS)
                    merged = durationAdjustedFTP * 0.7 + ftpFromTSS * 0.3
                }
            }

            let weight = recencyWeight(activity.date, now: now) * max(0.6, durationMin / 40.0)
            candidates.append(WeightedSample(value: merged, weight: weight))
        }

        guard !candidates.isEmpty else {
            return (currentFTP, 0)
        }

        let value = weightedAverage(candidates)
        let boundedValue = bounded(value, min: currentFTP * 0.7, max: currentFTP * 1.4)
        return (boundedValue, candidates.count)
    }

    private static func estimateThresholdHR(
        sport: SportType,
        activities: [Activity],
        profile: AthleteProfile,
        ftpEstimate: Double,
        now: Date
    ) -> (value: Double, samples: Int) {
        let currentThreshold = Double(max(profile.thresholdHeartRate(for: sport, on: now), 1))
        var candidates: [WeightedSample] = []

        for activity in activities {
            guard let avgHR = activity.avgHeartRate, avgHR > 0 else { continue }
            guard activity.durationSec >= 20 * 60 else { continue }
            let hours = max(Double(activity.durationSec) / 3600.0, 1.0 / 60.0)

            let intensity: Double?
            if let np = activity.normalizedPower, np > 0, ftpEstimate > 0 {
                intensity = Double(np) / ftpEstimate
            } else if activity.tss > 0 {
                let ifFromTSS = sqrt(Double(activity.tss) / (100.0 * hours))
                intensity = ifFromTSS.isFinite ? ifFromTSS : nil
            } else {
                intensity = nil
            }

            guard let intensity, intensity >= 0.85, intensity <= 1.06 else { continue }

            var adjustedHR = Double(avgHR)
            if intensity < 0.92 {
                adjustedHR += 2.0
            } else if intensity > 1.00 {
                adjustedHR -= 2.0
            }

            let weight = recencyWeight(activity.date, now: now) * max(0.7, hours / 0.9)
            candidates.append(WeightedSample(value: adjustedHR, weight: weight))
        }

        if candidates.isEmpty {
            let fallback = fallbackThresholdHRCandidates(activities: activities, now: now)
            candidates.append(contentsOf: fallback)
        }

        guard !candidates.isEmpty else {
            return (currentThreshold, 0)
        }

        let value = weightedAverage(candidates)
        let boundedValue = bounded(value, min: 120, max: 210)
        return (boundedValue, candidates.count)
    }

    private static func fallbackThresholdHRCandidates(
        activities: [Activity],
        now: Date
    ) -> [WeightedSample] {
        let rows = activities
            .filter { $0.avgHeartRate != nil && $0.durationSec >= 20 * 60 }
            .sorted { ($0.avgHeartRate ?? 0) > ($1.avgHeartRate ?? 0) }

        return rows.prefix(3).compactMap { activity in
            guard let avgHR = activity.avgHeartRate else { return nil }
            let hours = max(Double(activity.durationSec) / 3600.0, 1.0 / 60.0)
            let density = Double(activity.tss) / hours
            guard density >= 60 else { return nil }
            let weight = recencyWeight(activity.date, now: now)
            return WeightedSample(value: Double(avgHR), weight: weight)
        }
    }

    private static func confidenceLabel(sampleCount: Int) -> String {
        if sampleCount >= 6 { return "High" }
        if sampleCount >= 3 { return "Medium" }
        return "Low"
    }

    private static func weightedAverage(_ rows: [WeightedSample]) -> Double {
        let denominator = rows.reduce(0.0) { $0 + max(0.01, $1.weight) }
        guard denominator > 0 else { return rows.last?.value ?? 0 }
        let numerator = rows.reduce(0.0) { $0 + $1.value * max(0.01, $1.weight) }
        return numerator / denominator
    }

    private static func recencyWeight(_ date: Date, now: Date) -> Double {
        let daysAgo = max(0.0, now.timeIntervalSince(date) / 86_400.0)
        return exp(-daysAgo / 45.0)
    }
}

private func bounded(_ value: Double, min lower: Double, max upper: Double) -> Double {
    Swift.max(lower, Swift.min(upper, value))
}
