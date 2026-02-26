import Foundation

struct WorkoutTemplate: Identifiable {
    let id: UUID
    let name: String
    let sport: SportType
    let tags: [String]
    let segments: [WorkoutSegment]

    init(id: UUID = UUID(), name: String, sport: SportType, tags: [String], segments: [WorkoutSegment]) {
        self.id = id
        self.name = name
        self.sport = sport
        self.tags = tags
        self.segments = segments
    }
}

enum WorkoutTemplateLibrary {
    static let templates: [WorkoutTemplate] = [
        WorkoutTemplate(
            name: "Base Endurance 90",
            sport: .cycling,
            tags: ["Base", "Endurance"],
            segments: [
                WorkoutSegment(minutes: 15, intensityPercentFTP: 55, note: "Warm-up"),
                WorkoutSegment(minutes: 50, intensityPercentFTP: 68, note: "Steady Z2"),
                WorkoutSegment(minutes: 15, intensityPercentFTP: 75, note: "High Z2"),
                WorkoutSegment(minutes: 10, intensityPercentFTP: 50, note: "Cool-down")
            ]
        ),
        WorkoutTemplate(
            name: "Threshold 4x8",
            sport: .cycling,
            tags: ["Threshold", "Key"],
            segments: [
                WorkoutSegment(minutes: 12, intensityPercentFTP: 58, note: "Warm-up"),
                WorkoutSegment(minutes: 8, intensityPercentFTP: 102, note: "Rep #1"),
                WorkoutSegment(minutes: 4, intensityPercentFTP: 55, note: "Recover"),
                WorkoutSegment(minutes: 8, intensityPercentFTP: 102, note: "Rep #2"),
                WorkoutSegment(minutes: 4, intensityPercentFTP: 55, note: "Recover"),
                WorkoutSegment(minutes: 8, intensityPercentFTP: 102, note: "Rep #3"),
                WorkoutSegment(minutes: 4, intensityPercentFTP: 55, note: "Recover"),
                WorkoutSegment(minutes: 8, intensityPercentFTP: 102, note: "Rep #4"),
                WorkoutSegment(minutes: 10, intensityPercentFTP: 50, note: "Cool-down")
            ]
        ),
        WorkoutTemplate(
            name: "VO2 6x3",
            sport: .cycling,
            tags: ["VO2", "Anaerobic"],
            segments: [
                WorkoutSegment(minutes: 15, intensityPercentFTP: 58, note: "Warm-up"),
                WorkoutSegment(minutes: 3, intensityPercentFTP: 118, note: "Rep #1"),
                WorkoutSegment(minutes: 3, intensityPercentFTP: 50, note: "Recover"),
                WorkoutSegment(minutes: 3, intensityPercentFTP: 118, note: "Rep #2"),
                WorkoutSegment(minutes: 3, intensityPercentFTP: 50, note: "Recover"),
                WorkoutSegment(minutes: 3, intensityPercentFTP: 118, note: "Rep #3"),
                WorkoutSegment(minutes: 3, intensityPercentFTP: 50, note: "Recover"),
                WorkoutSegment(minutes: 3, intensityPercentFTP: 118, note: "Rep #4"),
                WorkoutSegment(minutes: 3, intensityPercentFTP: 50, note: "Recover"),
                WorkoutSegment(minutes: 3, intensityPercentFTP: 118, note: "Rep #5"),
                WorkoutSegment(minutes: 3, intensityPercentFTP: 50, note: "Recover"),
                WorkoutSegment(minutes: 3, intensityPercentFTP: 118, note: "Rep #6"),
                WorkoutSegment(minutes: 10, intensityPercentFTP: 50, note: "Cool-down")
            ]
        ),
        WorkoutTemplate(
            name: "Running Tempo Progression",
            sport: .running,
            tags: ["Running", "Tempo"],
            segments: [
                WorkoutSegment(minutes: 12, intensityPercentFTP: 60, note: "Warm-up jog"),
                WorkoutSegment(minutes: 10, intensityPercentFTP: 88, note: "Tempo 1"),
                WorkoutSegment(minutes: 4, intensityPercentFTP: 62, note: "Easy"),
                WorkoutSegment(minutes: 10, intensityPercentFTP: 92, note: "Tempo 2"),
                WorkoutSegment(minutes: 4, intensityPercentFTP: 62, note: "Easy"),
                WorkoutSegment(minutes: 10, intensityPercentFTP: 95, note: "Tempo 3"),
                WorkoutSegment(minutes: 8, intensityPercentFTP: 55, note: "Cool-down" )
            ]
        ),
        WorkoutTemplate(
            name: "Brick Day (Bike + Run)",
            sport: .cycling,
            tags: ["Multi-sport", "Race-specific"],
            segments: [
                WorkoutSegment(minutes: 20, intensityPercentFTP: 58, note: "Bike warm-up"),
                WorkoutSegment(minutes: 40, intensityPercentFTP: 85, note: "Steady bike"),
                WorkoutSegment(minutes: 15, intensityPercentFTP: 92, note: "Bike tempo"),
                WorkoutSegment(minutes: 5, intensityPercentFTP: 45, note: "Transition jog")
            ]
        ),
        WorkoutTemplate(
            name: "Lactate Threshold Step Test (Bike)",
            sport: .cycling,
            tags: ["Testing", "Lactate", "Threshold"],
            segments: [
                WorkoutSegment(minutes: 15, intensityPercentFTP: 55, note: "Warm-up + 3 x 10s spin-up"),
                WorkoutSegment(minutes: 5, intensityPercentFTP: 75, note: "Stage 1 · 末30秒采血"),
                WorkoutSegment(minutes: 2, intensityPercentFTP: 45, note: "Easy roll · 记录乳酸"),
                WorkoutSegment(minutes: 5, intensityPercentFTP: 82, note: "Stage 2 · 末30秒采血"),
                WorkoutSegment(minutes: 2, intensityPercentFTP: 45, note: "Easy roll · 记录乳酸"),
                WorkoutSegment(minutes: 5, intensityPercentFTP: 88, note: "Stage 3 · 末30秒采血"),
                WorkoutSegment(minutes: 2, intensityPercentFTP: 45, note: "Easy roll · 记录乳酸"),
                WorkoutSegment(minutes: 5, intensityPercentFTP: 94, note: "Stage 4 · 末30秒采血"),
                WorkoutSegment(minutes: 2, intensityPercentFTP: 45, note: "Easy roll · 记录乳酸"),
                WorkoutSegment(minutes: 5, intensityPercentFTP: 100, note: "Stage 5 · 末30秒采血"),
                WorkoutSegment(minutes: 2, intensityPercentFTP: 45, note: "Easy roll · 记录乳酸"),
                WorkoutSegment(minutes: 5, intensityPercentFTP: 106, note: "Stage 6 · 若乳酸已明显超阈可结束"),
                WorkoutSegment(minutes: 10, intensityPercentFTP: 50, note: "Cool-down")
            ]
        ),
        WorkoutTemplate(
            name: "Lactate Threshold Step Test (Run)",
            sport: .running,
            tags: ["Testing", "Lactate", "Threshold"],
            segments: [
                WorkoutSegment(minutes: 15, intensityPercentFTP: 62, note: "Warm-up jog + drills"),
                WorkoutSegment(minutes: 4, intensityPercentFTP: 78, note: "Stage 1 · 末30秒采血"),
                WorkoutSegment(minutes: 1, intensityPercentFTP: 58, note: "Easy jog · 记录乳酸"),
                WorkoutSegment(minutes: 4, intensityPercentFTP: 84, note: "Stage 2 · 末30秒采血"),
                WorkoutSegment(minutes: 1, intensityPercentFTP: 58, note: "Easy jog · 记录乳酸"),
                WorkoutSegment(minutes: 4, intensityPercentFTP: 90, note: "Stage 3 · 末30秒采血"),
                WorkoutSegment(minutes: 1, intensityPercentFTP: 58, note: "Easy jog · 记录乳酸"),
                WorkoutSegment(minutes: 4, intensityPercentFTP: 96, note: "Stage 4 · 末30秒采血"),
                WorkoutSegment(minutes: 1, intensityPercentFTP: 58, note: "Easy jog · 记录乳酸"),
                WorkoutSegment(minutes: 4, intensityPercentFTP: 102, note: "Stage 5 · 末30秒采血"),
                WorkoutSegment(minutes: 1, intensityPercentFTP: 58, note: "Easy jog · 记录乳酸"),
                WorkoutSegment(minutes: 4, intensityPercentFTP: 108, note: "Stage 6 · 若乳酸已明显超阈可结束"),
                WorkoutSegment(minutes: 10, intensityPercentFTP: 55, note: "Cool-down")
            ]
        ),
        WorkoutTemplate(
            name: "Norwegian Double Threshold AM (Bike)",
            sport: .cycling,
            tags: ["Norwegian", "Double Threshold", "AM"],
            segments: [
                WorkoutSegment(minutes: 18, intensityPercentFTP: 58, note: "Warm-up"),
                WorkoutSegment(minutes: 6, intensityPercentFTP: 94, note: "LT Rep #1"),
                WorkoutSegment(minutes: 2, intensityPercentFTP: 55, note: "Recover"),
                WorkoutSegment(minutes: 6, intensityPercentFTP: 94, note: "LT Rep #2"),
                WorkoutSegment(minutes: 2, intensityPercentFTP: 55, note: "Recover"),
                WorkoutSegment(minutes: 6, intensityPercentFTP: 94, note: "LT Rep #3"),
                WorkoutSegment(minutes: 2, intensityPercentFTP: 55, note: "Recover"),
                WorkoutSegment(minutes: 6, intensityPercentFTP: 94, note: "LT Rep #4"),
                WorkoutSegment(minutes: 2, intensityPercentFTP: 55, note: "Recover"),
                WorkoutSegment(minutes: 6, intensityPercentFTP: 94, note: "LT Rep #5"),
                WorkoutSegment(minutes: 10, intensityPercentFTP: 50, note: "Cool-down")
            ]
        ),
        WorkoutTemplate(
            name: "Norwegian Double Threshold PM (Bike)",
            sport: .cycling,
            tags: ["Norwegian", "Double Threshold", "PM"],
            segments: [
                WorkoutSegment(minutes: 15, intensityPercentFTP: 58, note: "Warm-up"),
                WorkoutSegment(minutes: 10, intensityPercentFTP: 92, note: "LT Block #1"),
                WorkoutSegment(minutes: 3, intensityPercentFTP: 55, note: "Recover"),
                WorkoutSegment(minutes: 10, intensityPercentFTP: 92, note: "LT Block #2"),
                WorkoutSegment(minutes: 3, intensityPercentFTP: 55, note: "Recover"),
                WorkoutSegment(minutes: 10, intensityPercentFTP: 92, note: "LT Block #3"),
                WorkoutSegment(minutes: 10, intensityPercentFTP: 50, note: "Cool-down")
            ]
        ),
        WorkoutTemplate(
            name: "Norwegian Double Threshold AM (Run)",
            sport: .running,
            tags: ["Norwegian", "Double Threshold", "AM"],
            segments: [
                WorkoutSegment(minutes: 15, intensityPercentFTP: 62, note: "Warm-up jog"),
                WorkoutSegment(minutes: 6, intensityPercentFTP: 92, note: "Threshold Rep #1"),
                WorkoutSegment(minutes: 1, intensityPercentFTP: 60, note: "Float"),
                WorkoutSegment(minutes: 6, intensityPercentFTP: 92, note: "Threshold Rep #2"),
                WorkoutSegment(minutes: 1, intensityPercentFTP: 60, note: "Float"),
                WorkoutSegment(minutes: 6, intensityPercentFTP: 92, note: "Threshold Rep #3"),
                WorkoutSegment(minutes: 1, intensityPercentFTP: 60, note: "Float"),
                WorkoutSegment(minutes: 6, intensityPercentFTP: 92, note: "Threshold Rep #4"),
                WorkoutSegment(minutes: 1, intensityPercentFTP: 60, note: "Float"),
                WorkoutSegment(minutes: 6, intensityPercentFTP: 92, note: "Threshold Rep #5"),
                WorkoutSegment(minutes: 10, intensityPercentFTP: 55, note: "Cool-down")
            ]
        ),
        WorkoutTemplate(
            name: "Norwegian Double Threshold PM (Run)",
            sport: .running,
            tags: ["Norwegian", "Double Threshold", "PM"],
            segments: [
                WorkoutSegment(minutes: 15, intensityPercentFTP: 62, note: "Warm-up jog"),
                WorkoutSegment(minutes: 5, intensityPercentFTP: 90, note: "Threshold Rep #1"),
                WorkoutSegment(minutes: 1, intensityPercentFTP: 60, note: "Float"),
                WorkoutSegment(minutes: 5, intensityPercentFTP: 90, note: "Threshold Rep #2"),
                WorkoutSegment(minutes: 1, intensityPercentFTP: 60, note: "Float"),
                WorkoutSegment(minutes: 5, intensityPercentFTP: 90, note: "Threshold Rep #3"),
                WorkoutSegment(minutes: 1, intensityPercentFTP: 60, note: "Float"),
                WorkoutSegment(minutes: 5, intensityPercentFTP: 90, note: "Threshold Rep #4"),
                WorkoutSegment(minutes: 1, intensityPercentFTP: 60, note: "Float"),
                WorkoutSegment(minutes: 5, intensityPercentFTP: 90, note: "Threshold Rep #5"),
                WorkoutSegment(minutes: 1, intensityPercentFTP: 60, note: "Float"),
                WorkoutSegment(minutes: 5, intensityPercentFTP: 90, note: "Threshold Rep #6"),
                WorkoutSegment(minutes: 10, intensityPercentFTP: 55, note: "Cool-down")
            ]
        )
    ]
}

struct PlanAdherenceReport {
    var plannedCount: Int
    var completedCount: Int
    var onTimeCount: Int
    var completionRate: Double
    var onTimeRate: Double
    var norwegianDoubleThresholdDays: Int
    var norwegianControlledDays: Int
    var norwegianRiskDays: Int
    var norwegianThresholdSessions: Int
}

enum PlanAdherenceEngine {
    static func evaluate(
        workouts: [PlannedWorkout],
        activities: [Activity],
        profile: AthleteProfile,
        trailingDays: Int = 42
    ) -> PlanAdherenceReport {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let start = calendar.date(byAdding: .day, value: -max(7, trailingDays), to: today) ?? today

        let planned = workouts
            .filter { workout in
                guard let day = workout.scheduledDate.map({ calendar.startOfDay(for: $0) }) else { return false }
                return day >= start && day <= today
            }

        var completed = 0
        var onTime = 0

        for workout in planned {
            guard let day = workout.scheduledDate.map({ calendar.startOfDay(for: $0) }) else { continue }
            let sameDay = activities.filter {
                calendar.isDate($0.date, inSameDayAs: day) && $0.sport == workout.sport
            }
            guard !sameDay.isEmpty else { continue }

            let targetDuration = Double(max(1, workout.totalMinutes * 60))
            let targetTSS = Double(max(1, workout.segments.reduce(0) { partial, segment in
                partial + Int(Double(segment.minutes) * Double(segment.intensityPercentFTP) / 100.0)
            }))

            let best = sameDay.max { lhs, rhs in
                activityMatchScore(activity: lhs, targetDuration: targetDuration, targetTSS: targetTSS)
                    < activityMatchScore(activity: rhs, targetDuration: targetDuration, targetTSS: targetTSS)
            }

            if let best {
                let durationRatio = Double(best.durationSec) / targetDuration
                let tssRatio = Double(best.tss) / max(1, targetTSS)
                let completion = max(0.0, min(1.4, 0.6 * durationRatio + 0.4 * tssRatio))
                if completion >= 0.7 {
                    completed += 1
                }
                if completion >= 0.85 {
                    onTime += 1
                }
            }
        }

        let plannedCount = planned.count
        let completionRate = plannedCount > 0 ? Double(completed) / Double(plannedCount) : 0
        let onTimeRate = plannedCount > 0 ? Double(onTime) / Double(plannedCount) : 0
        let norwegian = evaluateNorwegianDoubleThreshold(
            activities: activities,
            profile: profile,
            trailingDays: trailingDays
        )
        return PlanAdherenceReport(
            plannedCount: plannedCount,
            completedCount: completed,
            onTimeCount: onTime,
            completionRate: completionRate,
            onTimeRate: onTimeRate,
            norwegianDoubleThresholdDays: norwegian.doubleDays,
            norwegianControlledDays: norwegian.controlledDays,
            norwegianRiskDays: norwegian.riskDays,
            norwegianThresholdSessions: norwegian.thresholdSessions
        )
    }

    private static func activityMatchScore(activity: Activity, targetDuration: Double, targetTSS: Double) -> Double {
        let durationError = abs(Double(activity.durationSec) - targetDuration) / max(600, targetDuration)
        let tssError = abs(Double(activity.tss) - targetTSS) / max(20, targetTSS)
        return 1.0 / (1.0 + durationError + tssError)
    }

    private static func evaluateNorwegianDoubleThreshold(
        activities: [Activity],
        profile: AthleteProfile,
        trailingDays: Int
    ) -> (doubleDays: Int, controlledDays: Int, riskDays: Int, thresholdSessions: Int) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let start = calendar.date(byAdding: .day, value: -max(7, trailingDays), to: today) ?? today
        let recent = activities.filter {
            let day = calendar.startOfDay(for: $0.date)
            return day >= start && day <= today
        }
        let grouped = Dictionary(grouping: recent) { calendar.startOfDay(for: $0.date) }

        var thresholdSessions = 0
        var doubleDays = 0
        var controlledDays = 0
        var riskDays = 0

        for (_, dayActivities) in grouped {
            let sessions = dayActivities.map { norwegianSessionClass(activity: $0, profile: profile) }
            let threshold = sessions.filter { $0.isThreshold }
            thresholdSessions += threshold.count

            if threshold.count >= 2 {
                doubleDays += 1
                let hasRisk = threshold.contains(where: { $0.isHighIntensityLeak || $0.durationMin > 95 }) || threshold.count >= 3
                if hasRisk {
                    riskDays += 1
                } else {
                    controlledDays += 1
                }
            }
        }

        return (doubleDays, controlledDays, riskDays, thresholdSessions)
    }

    private static func norwegianSessionClass(
        activity: Activity,
        profile: AthleteProfile
    ) -> (isThreshold: Bool, isHighIntensityLeak: Bool, durationMin: Double) {
        let durationMin = Double(max(1, activity.durationSec)) / 60.0
        guard durationMin >= 20 else {
            return (false, false, durationMin)
        }

        let thresholdIF: Double?
        if let np = activity.normalizedPower {
            thresholdIF = Double(np) / Double(max(1, profile.ftpWatts(for: activity.sport)))
        } else if let hr = activity.avgHeartRate {
            thresholdIF = Double(hr) / Double(max(1, profile.thresholdHeartRate(for: activity.sport, on: activity.date)))
        } else {
            thresholdIF = nil
        }

        guard let ifValue = thresholdIF else {
            return (false, false, durationMin)
        }

        let isThreshold = ifValue >= 0.88 && ifValue <= 1.02
        let isLeak = ifValue > 1.04
        return (isThreshold, isLeak, durationMin)
    }
}

struct DetectedInterval: Identifiable, Hashable {
    let id: UUID
    let activityID: UUID
    let activityDate: Date
    let sport: SportType
    let index: Int
    let startSec: Int
    let endSec: Int
    let durationSec: Int
    let avgPower: Double
    let avgHeartRate: Double?
    let intensityFactor: Double
    let label: String

    init(
        id: UUID = UUID(),
        activityID: UUID,
        activityDate: Date,
        sport: SportType,
        index: Int,
        startSec: Int,
        endSec: Int,
        durationSec: Int,
        avgPower: Double,
        avgHeartRate: Double?,
        intensityFactor: Double,
        label: String
    ) {
        self.id = id
        self.activityID = activityID
        self.activityDate = activityDate
        self.sport = sport
        self.index = index
        self.startSec = startSec
        self.endSec = endSec
        self.durationSec = durationSec
        self.avgPower = avgPower
        self.avgHeartRate = avgHeartRate
        self.intensityFactor = intensityFactor
        self.label = label
    }
}

struct SimilarIntervalHit: Identifiable {
    let id = UUID()
    let interval: DetectedInterval
    let similarity: Double
}

enum IntervalLabEngine {
    static func detectIntervals(activities: [Activity], profile: AthleteProfile) -> [DetectedInterval] {
        activities.flatMap { detectIntervals(activity: $0, profile: profile) }
    }

    static func detectIntervals(activity: Activity, profile: AthleteProfile) -> [DetectedInterval] {
        let ftp = max(1, profile.ftpWatts(for: activity.sport))
        let lthr = max(1, profile.thresholdHeartRate(for: activity.sport, on: activity.date))
        let samples = powerAndHeartTimeline(activity: activity)
        guard samples.count >= 40 else { return [] }

        var intervals: [DetectedInterval] = []
        var currentStart: Int?

        func flush(endIndex: Int) {
            guard let start = currentStart else { return }
            let duration = endIndex - start
            guard duration >= 45 else {
                currentStart = nil
                return
            }

            let slice = samples[start..<endIndex]
            let powerMean = slice.map(\.power).reduce(0, +) / Double(slice.count)
            let hrValues = slice.compactMap(\.heartRate)
            let hrMean = hrValues.isEmpty ? nil : hrValues.reduce(0, +) / Double(hrValues.count)
            let ifValue = powerMean / Double(ftp)

            let label: String
            switch ifValue {
            case ..<0.75:
                label = "耐力段"
            case 0.75..<0.9:
                label = "节奏段"
            case 0.9..<1.05:
                label = "阈值段"
            case 1.05..<1.2:
                label = "VO2段"
            default:
                label = "无氧段"
            }

            intervals.append(
                DetectedInterval(
                    activityID: activity.id,
                    activityDate: activity.date,
                    sport: activity.sport,
                    index: intervals.count + 1,
                    startSec: start,
                    endSec: endIndex,
                    durationSec: duration,
                    avgPower: powerMean,
                    avgHeartRate: hrMean,
                    intensityFactor: ifValue,
                    label: label
                )
            )
            currentStart = nil
        }

        let triggerPower = Double(ftp) * 0.82
        for idx in samples.indices {
            let sample = samples[idx]
            let hrOK: Bool
            if let hr = sample.heartRate {
                hrOK = hr >= Double(lthr) * 0.75
            } else {
                hrOK = true
            }
            let hardEnough = sample.power >= triggerPower && hrOK
            if hardEnough {
                if currentStart == nil {
                    currentStart = idx
                }
            } else if currentStart != nil {
                flush(endIndex: idx)
            }
        }

        if currentStart != nil {
            flush(endIndex: samples.count)
        }

        if intervals.isEmpty {
            let fallback = syntheticFromPlannedIntervals(activity: activity, ftp: ftp)
            return fallback
        }

        return intervals
    }

    static func findSimilarIntervals(
        target: DetectedInterval,
        activities: [Activity],
        profile: AthleteProfile,
        limit: Int = 8
    ) -> [SimilarIntervalHit] {
        let all = detectIntervals(activities: activities, profile: profile)
        return findSimilarIntervals(target: target, intervals: all, limit: limit)
    }

    static func findSimilarIntervals(
        target: DetectedInterval,
        intervals: [DetectedInterval],
        limit: Int = 8
    ) -> [SimilarIntervalHit] {
        let scored = intervals
            .filter { $0.activityID != target.activityID || $0.index != target.index }
            .map { candidate -> SimilarIntervalHit in
                let sim = intervalSimilarity(lhs: target, rhs: candidate)
                return SimilarIntervalHit(interval: candidate, similarity: sim)
            }
            .sorted { $0.similarity > $1.similarity }

        return Array(scored.prefix(max(1, limit)))
    }

    private static func syntheticFromPlannedIntervals(activity: Activity, ftp: Int) -> [DetectedInterval] {
        guard !activity.intervals.isEmpty else { return [] }

        var cursor = 0
        var rows: [DetectedInterval] = []
        for effort in activity.intervals {
            let duration = max(1, effort.durationSec)
            let power = Double(effort.actualPower ?? effort.targetPower ?? activity.normalizedPower ?? ftp)
            let ifValue = power / Double(ftp)
            rows.append(
                DetectedInterval(
                    activityID: activity.id,
                    activityDate: activity.date,
                    sport: activity.sport,
                    index: rows.count + 1,
                    startSec: cursor,
                    endSec: cursor + duration,
                    durationSec: duration,
                    avgPower: power,
                    avgHeartRate: activity.avgHeartRate.map(Double.init),
                    intensityFactor: ifValue,
                    label: ifValue >= 0.9 ? "强度段" : "稳态段"
                )
            )
            cursor += duration
        }
        return rows
    }

    private struct IntervalSample {
        var power: Double
        var heartRate: Double?
    }

    private static func powerAndHeartTimeline(activity: Activity) -> [IntervalSample] {
        if !activity.intervals.isEmpty {
            var rows: [IntervalSample] = []
            rows.reserveCapacity(max(1, activity.durationSec))
            let fallbackPower = Double(activity.normalizedPower ?? 0)
            let fallbackHR = activity.avgHeartRate.map(Double.init)

            for effort in activity.intervals {
                let duration = max(1, effort.durationSec)
                let power = Double(effort.actualPower ?? effort.targetPower ?? activity.normalizedPower ?? 0)
                let hr: Double?
                if let avgHR = fallbackHR, let np = activity.normalizedPower, np > 0 {
                    hr = clip(avgHR + (power - Double(np)) * 0.08, min: 65, max: 205)
                } else {
                    hr = fallbackHR
                }
                rows.append(contentsOf: repeatElement(IntervalSample(power: max(30, power), heartRate: hr), count: duration))
            }

            if rows.count < activity.durationSec {
                rows.append(contentsOf: repeatElement(IntervalSample(power: max(30, fallbackPower), heartRate: fallbackHR), count: activity.durationSec - rows.count))
            }
            return rows
        }

        guard let np = activity.normalizedPower else { return [] }
        let duration = max(60, activity.durationSec)
        let avgHR = activity.avgHeartRate.map(Double.init)
        var rows: [IntervalSample] = []
        rows.reserveCapacity(duration)

        for sec in 0..<duration {
            let ratio = Double(sec) / Double(duration)
            let wave1 = sin(ratio * 2.0 * .pi * 6.0)
            let wave2 = sin(ratio * 2.0 * .pi * 17.0)
            let surge = (sec % 780 < 120) ? 0.15 : 0.0
            let power = Double(np) * (1.0 + 0.10 * wave1 + 0.035 * wave2 + surge)
            let hr = avgHR.map { base in
                clip(base + 6.0 * wave1 + surge * 16.0, min: 70, max: 205)
            }
            rows.append(IntervalSample(power: max(30, power), heartRate: hr))
        }
        return rows
    }

    private static func intervalSimilarity(lhs: DetectedInterval, rhs: DetectedInterval) -> Double {
        let durationGap = abs(Double(lhs.durationSec - rhs.durationSec)) / Double(max(lhs.durationSec, rhs.durationSec, 1))
        let powerGap = abs(lhs.avgPower - rhs.avgPower) / max(lhs.avgPower, rhs.avgPower, 1)
        let ifGap = abs(lhs.intensityFactor - rhs.intensityFactor) / max(lhs.intensityFactor, rhs.intensityFactor, 0.01)

        let raw = 1.0 - (0.45 * durationGap + 0.35 * powerGap + 0.20 * ifGap)
        return clip(raw, min: 0, max: 1)
    }

    private static func clip(_ value: Double, min: Double, max: Double) -> Double {
        Swift.max(min, Swift.min(max, value))
    }
}

enum MetricAggregation: String, CaseIterable, Identifiable {
    case day
    case week
    case month

    var id: String { rawValue }

    var title: String {
        switch self {
        case .day: return "Day"
        case .week: return "Week"
        case .month: return "Month"
        }
    }
}

enum MetricAggregationStyle {
    case sum
    case mean
    case last
}

enum MetricScope: String, CaseIterable, Identifiable {
    case activity
    case trends
    case wellness

    var id: String { rawValue }

    var title: String {
        switch self {
        case .activity: return "Activity"
        case .trends: return "Trends"
        case .wellness: return "Wellness"
        }
    }
}

private enum MetricComputation {
    case direct((MetricDayContext) -> Double)
}

struct ChartMetricDefinition: Identifiable {
    let id: String
    let name: String
    let unit: String
    let style: MetricAggregationStyle
    let scope: MetricScope
    fileprivate let compute: MetricComputation
}

struct MetricDayContext {
    let date: Date
    let activities: [Activity]
    let load: DailyLoadPoint?
    let profile: AthleteProfile
    private let activitiesBySport: [SportType: [Activity]]
    private let meanIFAllSports: Double
    private let meanIFBySport: [SportType: Double]

    init(date: Date, activities: [Activity], load: DailyLoadPoint?, profile: AthleteProfile) {
        self.date = date
        self.activities = activities
        self.load = load
        self.profile = profile
        let groupedBySport = Dictionary(grouping: activities) { $0.sport }
        self.activitiesBySport = groupedBySport
        self.meanIFAllSports = Self.averageIntensityFactor(activities: activities, profile: profile)

        var perSport: [SportType: Double] = [:]
        perSport.reserveCapacity(SportType.allCases.count)
        for sport in SportType.allCases {
            perSport[sport] = Self.averageIntensityFactor(activities: groupedBySport[sport] ?? [], profile: profile)
        }
        self.meanIFBySport = perSport
    }

    var tss: Double { activities.reduce(0.0) { $0 + Double($1.tss) } }
    var distanceKm: Double { activities.reduce(0.0) { $0 + $1.distanceKm } }
    var durationMin: Double { activities.reduce(0.0) { $0 + Double($1.durationSec) / 60.0 } }
    var count: Double { Double(activities.count) }

    var npMean: Double {
        let samples = activities.compactMap { $0.normalizedPower.map(Double.init) }
        guard !samples.isEmpty else { return 0 }
        return samples.reduce(0, +) / Double(samples.count)
    }

    var hrMean: Double {
        let samples = activities.compactMap { $0.avgHeartRate.map(Double.init) }
        guard !samples.isEmpty else { return 0 }
        return samples.reduce(0, +) / Double(samples.count)
    }

    var workKJ: Double {
        activities.reduce(0) { partial, activity in
            guard let np = activity.normalizedPower else { return partial }
            return partial + Double(np * activity.durationSec) / 1000.0
        }
    }

    func forSport(_ sport: SportType) -> [Activity] {
        activitiesBySport[sport] ?? []
    }

    func meanIF(sport: SportType? = nil) -> Double {
        if let sport {
            return meanIFBySport[sport] ?? 0
        }
        return meanIFAllSports
    }

    func estimatedPowerZoneMinutes(zone: Int, sport: SportType? = nil) -> Double {
        guard (1...7).contains(zone) else { return 0 }
        let source = sport.map(forSport) ?? activities
        guard !source.isEmpty else { return 0 }

        var total = 0.0
        for activity in source {
            let minutes = Double(activity.durationSec) / 60.0
            if minutes <= 0 { continue }
            let ifValue: Double
            if let np = activity.normalizedPower {
                ifValue = Double(np) / Double(max(1, profile.ftpWatts(for: activity.sport)))
            } else {
                ifValue = meanIFBySport[activity.sport] ?? 0
            }

            let bucket = powerZone(for: ifValue)
            if bucket == zone {
                total += minutes
            } else if abs(bucket - zone) == 1 {
                total += minutes * 0.25
            }
        }
        return total
    }

    private static func averageIntensityFactor(activities: [Activity], profile: AthleteProfile) -> Double {
        guard !activities.isEmpty else { return 0 }
        let values = activities.map { activity -> Double in
            if let np = activity.normalizedPower {
                return Double(np) / Double(max(1, profile.ftpWatts(for: activity.sport)))
            }
            if let hr = activity.avgHeartRate {
                return Double(hr) / Double(max(1, profile.thresholdHeartRate(for: activity.sport, on: activity.date)))
            }
            return sqrt(max(1.0, Double(activity.tss)) / max(1.0, Double(activity.durationSec) / 36.0)) / 10.0
        }
        return values.reduce(0, +) / Double(values.count)
    }

    func estimatedHeartZoneMinutes(zone: Int, sport: SportType? = nil) -> Double {
        guard (1...7).contains(zone) else { return 0 }
        let source = sport.map(forSport) ?? activities
        guard !source.isEmpty else { return 0 }
        var total = 0.0

        for activity in source {
            guard let hr = activity.avgHeartRate else { continue }
            let threshold = max(1, profile.thresholdHeartRate(for: activity.sport, on: activity.date))
            let ratio = Double(hr) / Double(threshold)
            let minutes = Double(activity.durationSec) / 60.0
            let bucket = heartZone(for: ratio)
            if bucket == zone {
                total += minutes
            } else if abs(bucket - zone) == 1 {
                total += minutes * 0.22
            }
        }

        return total
    }

    private func powerZone(for ifValue: Double) -> Int {
        switch ifValue {
        case ..<0.56: return 1
        case ..<0.76: return 2
        case ..<0.91: return 3
        case ..<1.06: return 4
        case ..<1.21: return 5
        case ..<1.50: return 6
        default: return 7
        }
    }

    private func heartZone(for hrRatio: Double) -> Int {
        switch hrRatio {
        case ..<0.68: return 1
        case ..<0.78: return 2
        case ..<0.85: return 3
        case ..<0.92: return 4
        case ..<1.00: return 5
        case ..<1.06: return 6
        default: return 7
        }
    }
}

enum ChartMetricCatalog {
    static let all: [ChartMetricDefinition] = build()

    private static func build() -> [ChartMetricDefinition] {
        var rows: [ChartMetricDefinition] = [
            make("daily_tss", "Daily TSS", "", .sum, scope: .trends) { $0.tss },
            make("daily_distance", "Daily Distance", "km", .sum, scope: .trends) { $0.distanceKm },
            make("daily_duration", "Daily Duration", "min", .sum, scope: .trends) { $0.durationMin },
            make("daily_count", "Activity Count", "", .sum, scope: .trends) { $0.count },
            make("daily_np_mean", "Daily Mean NP", "W", .mean, scope: .activity) { $0.npMean },
            make("daily_hr_mean", "Daily Mean HR", "bpm", .mean, scope: .activity) { $0.hrMean },
            make("daily_if_mean", "Daily Mean IF", "", .mean, scope: .activity) { $0.meanIF() },
            make("daily_work", "Daily Work", "kJ", .sum, scope: .activity) { $0.workKJ },
            make("ctl", "Coggan CTL", "", .last, scope: .trends) { $0.load?.ctl ?? 0 },
            make("atl", "Coggan ATL", "", .last, scope: .trends) { $0.load?.atl ?? 0 },
            make("tsb", "Coggan TSB", "", .last, scope: .trends) { $0.load?.tsb ?? 0 },
            make("aer_tiss", "Aerobic TISS", "", .sum, scope: .activity) { $0.load?.aerobicTISS ?? 0 },
            make("ana_tiss", "Anaerobic TISS", "", .sum, scope: .activity) { $0.load?.anaerobicTISS ?? 0 },
            make("aer_lts", "Aerobic Long Term Stress", "", .last, scope: .trends) { $0.load?.aerobicLongTermStress ?? 0 },
            make("ana_lts", "Anaerobic Long Term Stress", "", .last, scope: .trends) { $0.load?.anaerobicLongTermStress ?? 0 },
            make("aer_sts", "Aerobic Short Term Stress", "", .last, scope: .trends) { $0.load?.aerobicShortTermStress ?? 0 },
            make("ana_sts", "Anaerobic Short Term Stress", "", .last, scope: .trends) { $0.load?.anaerobicShortTermStress ?? 0 },
            make("decoupling_est", "Decoupling Estimate", "%", .mean, scope: .activity) {
                let ifValue = $0.meanIF()
                let base = max(0.0, (ifValue - 0.75) * 9.0)
                let fatigue = max(0.0, (($0.load?.atl ?? 0) - ($0.load?.ctl ?? 0)) * 0.18)
                return min(15.0, base + fatigue)
            }
        ]

        for sport in SportType.allCases {
            rows.append(make("\(sport.rawValue)_tss", "\(sport.label) TSS", "", .sum, scope: .activity) {
                $0.forSport(sport).reduce(0.0) { $0 + Double($1.tss) }
            })
            rows.append(make("\(sport.rawValue)_distance", "\(sport.label) Distance", "km", .sum, scope: .activity) {
                $0.forSport(sport).reduce(0.0) { $0 + $1.distanceKm }
            })
            rows.append(make("\(sport.rawValue)_duration", "\(sport.label) Duration", "min", .sum, scope: .activity) {
                $0.forSport(sport).reduce(0.0) { $0 + Double($1.durationSec) / 60.0 }
            })
            rows.append(make("\(sport.rawValue)_count", "\(sport.label) Count", "", .sum, scope: .activity) {
                Double($0.forSport(sport).count)
            })
            rows.append(make("\(sport.rawValue)_np_mean", "\(sport.label) NP Mean", "W", .mean, scope: .activity) {
                let values = $0.forSport(sport).compactMap { $0.normalizedPower.map(Double.init) }
                guard !values.isEmpty else { return 0 }
                return values.reduce(0, +) / Double(values.count)
            })
            rows.append(make("\(sport.rawValue)_hr_mean", "\(sport.label) HR Mean", "bpm", .mean, scope: .activity) {
                let values = $0.forSport(sport).compactMap { $0.avgHeartRate.map(Double.init) }
                guard !values.isEmpty else { return 0 }
                return values.reduce(0, +) / Double(values.count)
            })
            rows.append(make("\(sport.rawValue)_if", "\(sport.label) IF", "", .mean, scope: .activity) {
                $0.meanIF(sport: sport)
            })
            rows.append(make("\(sport.rawValue)_work", "\(sport.label) Work", "kJ", .sum, scope: .activity) {
                $0.forSport(sport).reduce(0.0) { partial, activity in
                    guard let np = activity.normalizedPower else { return partial }
                    return partial + Double(np * activity.durationSec) / 1000.0
                }
            })
        }

        for zone in 1...7 {
            rows.append(make("power_z\(zone)", "Power Zone Z\(zone)", "min", .sum, scope: .activity) {
                $0.estimatedPowerZoneMinutes(zone: zone)
            })
            rows.append(make("hr_z\(zone)", "Heart Zone Z\(zone)", "min", .sum, scope: .activity) {
                $0.estimatedHeartZoneMinutes(zone: zone)
            })

            rows.append(make("cycling_power_z\(zone)", "Cycling Power Zone Z\(zone)", "min", .sum, scope: .activity) {
                $0.estimatedPowerZoneMinutes(zone: zone, sport: .cycling)
            })
            rows.append(make("running_power_z\(zone)", "Running Power Zone Z\(zone)", "min", .sum, scope: .activity) {
                $0.estimatedPowerZoneMinutes(zone: zone, sport: .running)
            })
            rows.append(make("cycling_hr_z\(zone)", "Cycling HR Zone Z\(zone)", "min", .sum, scope: .activity) {
                $0.estimatedHeartZoneMinutes(zone: zone, sport: .cycling)
            })
            rows.append(make("running_hr_z\(zone)", "Running HR Zone Z\(zone)", "min", .sum, scope: .activity) {
                $0.estimatedHeartZoneMinutes(zone: zone, sport: .running)
            })
        }

        let existingIDs = Set(rows.map(\.id))
        for spec in GoldenCheetahMetricCatalog.all where !existingIDs.contains(spec.id) {
            rows.append(
                make(spec.id, "GC \(spec.name)", spec.unit, spec.style, scope: spec.scope) { context in
                    GoldenCheetahMetricCatalog.value(symbol: spec.symbol, context: context)
                }
            )
        }

        return rows
    }

    private static func make(
        _ id: String,
        _ name: String,
        _ unit: String,
        _ style: MetricAggregationStyle,
        scope: MetricScope = .trends,
        compute: @escaping (MetricDayContext) -> Double
    ) -> ChartMetricDefinition {
        ChartMetricDefinition(
            id: id,
            name: name,
            unit: unit,
            style: style,
            scope: scope,
            compute: .direct(compute)
        )
    }
}

struct MetricChartPoint: Identifiable {
    let date: Date
    let value: Double
    let label: String

    var id: String {
        "\(label)-\(Int(date.timeIntervalSince1970))"
    }
}

struct MetricLabResult {
    let primary: [MetricChartPoint]
    let secondary: [MetricChartPoint]
    let comparison: [MetricChartPoint]
}

enum MetricLabEngine {
    static func build(
        activities: [Activity],
        loadSeries: [DailyLoadPoint],
        profile: AthleteProfile,
        primary: ChartMetricDefinition,
        secondary: ChartMetricDefinition?,
        days: Int,
        aggregation: MetricAggregation,
        sportFilter: SportType?,
        comparePrevious: Bool
    ) -> MetricLabResult {
        let calendar = Calendar.current
        let dayCount = max(14, days)
        let end = calendar.startOfDay(for: Date())
        let start = calendar.date(byAdding: .day, value: -dayCount + 1, to: end) ?? end

        let daySeries = buildDailyContexts(
            activities: activities,
            loadSeries: loadSeries,
            profile: profile,
            start: start,
            end: end,
            sportFilter: sportFilter
        )

        let primaryRaw = aggregate(contexts: daySeries, metric: primary, aggregation: aggregation)
        let primaryPoints = normalizedSeries(primaryRaw)
        let secondaryPoints = secondary.map {
            normalizedSeries(
                aggregate(contexts: daySeries, metric: $0, aggregation: aggregation)
            )
        } ?? []

        var comparisonPoints: [MetricChartPoint] = []
        if comparePrevious {
            let previousEnd = calendar.date(byAdding: .day, value: -1, to: start) ?? start
            let previousStart = calendar.date(byAdding: .day, value: -dayCount + 1, to: previousEnd) ?? previousEnd
            let previousContexts = buildDailyContexts(
                activities: activities,
                loadSeries: loadSeries,
                profile: profile,
                start: previousStart,
                end: previousEnd,
                sportFilter: sportFilter
            )
            let rawComparison = normalizedSeries(
                aggregate(contexts: previousContexts, metric: primary, aggregation: aggregation)
            )
            comparisonPoints = alignedComparisonSeries(
                current: primaryPoints,
                previous: rawComparison
            )
        }

        return MetricLabResult(primary: primaryPoints, secondary: secondaryPoints, comparison: comparisonPoints)
    }

    private static func normalizedSeries(_ points: [MetricChartPoint]) -> [MetricChartPoint] {
        guard !points.isEmpty else { return [] }
        let calendar = Calendar.current
        let sorted = points.sorted { lhs, rhs in
            if lhs.date == rhs.date {
                return lhs.label < rhs.label
            }
            return lhs.date < rhs.date
        }

        var result: [MetricChartPoint] = []
        result.reserveCapacity(sorted.count)

        for point in sorted {
            let day = calendar.startOfDay(for: point.date)
            if let last = result.last, calendar.isDate(last.date, inSameDayAs: day) {
                result[result.count - 1] = MetricChartPoint(
                    date: day,
                    value: point.value,
                    label: point.label
                )
                continue
            }

            result.append(
                MetricChartPoint(
                    date: day,
                    value: point.value,
                    label: point.label
                )
            )
        }

        return result
    }

    private static func alignedComparisonSeries(
        current: [MetricChartPoint],
        previous: [MetricChartPoint]
    ) -> [MetricChartPoint] {
        guard !current.isEmpty, !previous.isEmpty else { return [] }
        let count = min(current.count, previous.count)
        guard count > 0 else { return [] }

        let currentTail = current.suffix(count)
        let previousTail = previous.suffix(count)

        return zip(currentTail, previousTail).map { currentPoint, previousPoint in
            MetricChartPoint(
                date: currentPoint.date,
                value: previousPoint.value,
                label: currentPoint.label
            )
        }
    }

    private static func buildDailyContexts(
        activities: [Activity],
        loadSeries: [DailyLoadPoint],
        profile: AthleteProfile,
        start: Date,
        end: Date,
        sportFilter: SportType?
    ) -> [MetricDayContext] {
        let calendar = Calendar.current
        let filteredActivities = activities.filter { activity in
            if let sportFilter {
                return activity.sport == sportFilter
            }
            return true
        }

        let byDay = Dictionary(grouping: filteredActivities) { calendar.startOfDay(for: $0.date) }
        let loadByDay = Dictionary(uniqueKeysWithValues: loadSeries.map { (calendar.startOfDay(for: $0.date), $0) })

        var rows: [MetricDayContext] = []
        var cursor = start
        while cursor <= end {
            rows.append(
                MetricDayContext(
                    date: cursor,
                    activities: byDay[cursor] ?? [],
                    load: loadByDay[cursor],
                    profile: profile
                )
            )
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }

        return rows
    }

    private static func aggregate(
        contexts: [MetricDayContext],
        metric: ChartMetricDefinition,
        aggregation: MetricAggregation
    ) -> [MetricChartPoint] {
        guard !contexts.isEmpty else { return [] }
        let calendar = Calendar.current

        let sourceContexts: [MetricDayContext]
        switch metric.scope {
        case .activity:
            // For activity metrics, skip empty days to avoid misleading sawtooth zero lines.
            sourceContexts = contexts.filter { !$0.activities.isEmpty }
        case .trends, .wellness:
            // For trend "last-value" metrics (CTL/ATL/TSB etc.), drop days without load context.
            // Otherwise missing-history days are plotted as zero and create false baseline/vertical jumps.
            if metric.scope == .trends && metric.style == .last {
                sourceContexts = contexts.filter { $0.load != nil }
            } else {
                sourceContexts = contexts
            }
        }
        guard !sourceContexts.isEmpty else { return [] }

        let dailyValues: [(Date, Double)] = sourceContexts.compactMap { context in
            let value: Double
            switch metric.compute {
            case let .direct(block):
                value = block(context)
            }
            guard value.isFinite else { return nil }
            return (context.date, value)
        }
        guard !dailyValues.isEmpty else { return [] }

        switch aggregation {
        case .day:
            return dailyValues.map { date, value in
                MetricChartPoint(date: date, value: value, label: date.formatted(date: .abbreviated, time: .omitted))
            }
        case .week, .month:
            var rows: [MetricChartPoint] = []
            rows.reserveCapacity(max(1, dailyValues.count / 7))

            var currentPeriodKey: Date?
            var runningSum = 0.0
            var runningCount = 0
            var runningLast = 0.0

            func flush() {
                guard let period = currentPeriodKey, runningCount > 0 else { return }
                let value: Double
                switch metric.style {
                case .sum:
                    value = runningSum
                case .mean:
                    value = runningSum / Double(runningCount)
                case .last:
                    value = runningLast
                }
                rows.append(
                    MetricChartPoint(
                        date: period,
                        value: value,
                        label: period.formatted(date: aggregation == .week ? .abbreviated : .numeric, time: .omitted)
                    )
                )
            }

            for (date, value) in dailyValues {
                let periodKey: Date
                if aggregation == .week {
                    let comps = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
                    periodKey = calendar.date(from: comps) ?? date
                } else {
                    let comps = calendar.dateComponents([.year, .month], from: date)
                    periodKey = calendar.date(from: comps) ?? date
                }

                if currentPeriodKey != periodKey {
                    flush()
                    currentPeriodKey = periodKey
                    runningSum = 0
                    runningCount = 0
                    runningLast = 0
                }

                runningSum += value
                runningCount += 1
                runningLast = value
            }
            flush()
            return rows
        }
    }
}

struct PowerCurvePoint: Identifiable {
    let id = UUID()
    let durationSec: Int
    let power: Double
}

struct CPModelFit {
    let name: String
    let cp: Double
    let wPrime: Double
    let pMax: Double
    let tau: Double?
    let r2: Double
    let curve: [PowerCurvePoint]
}

enum RiderPersona: String {
    case sprinter = "Sprinter"
    case pursuiter = "Pursuiter"
    case allRounder = "All-rounder"
    case climber = "Climber"
}

struct WkgRankingResult {
    let ftpWkg: Double
    let ageBand: String
    let percentile: Double
    let rankIn1000: Int
    let persona: RiderPersona
}

struct PowerCurveAnalysis {
    let observed: [PowerCurvePoint]
    let monod: CPModelFit?
    let morton3P: CPModelFit?
    let submax: CPModelFit?
    let comparisonObserved: [PowerCurvePoint]
    let ranking: WkgRankingResult

    static let empty = PowerCurveAnalysis(
        observed: [],
        monod: nil,
        morton3P: nil,
        submax: nil,
        comparisonObserved: [],
        ranking: WkgRankingResult(
            ftpWkg: 0,
            ageBand: "N/A",
            percentile: 0,
            rankIn1000: 1000,
            persona: .allRounder
        )
    )
}

enum PowerCurveEngine {
    private static let durations = [1, 10, 15, 20, 30, 60, 120, 180, 300, 600, 1200, 1800, 2400, 3600]
    private static let modelCurveDurations = durations.filter { $0 >= 10 }

    static func analyze(
        activities: [Activity],
        profile: AthleteProfile,
        athleteAge: Int,
        athleteWeightKg: Double
    ) -> PowerCurveAnalysis {
        let sorted = activities.sorted { $0.date > $1.date }
        let recent = Array(sorted.prefix(90))
        let previous = Array(sorted.dropFirst(90).prefix(90))

        let observed = maximalMeanPower(from: recent)
        let previousObserved = maximalMeanPower(from: previous)

        let monod = fitMonod(from: observed)
        let morton = fitMorton3P(from: observed)
        let submax = fitSubmax(from: observed)

        let ranking = RiderRankingEngine.evaluate(
            profile: profile,
            observed: observed,
            age: athleteAge,
            weightKg: athleteWeightKg
        )

        return PowerCurveAnalysis(
            observed: observed,
            monod: monod,
            morton3P: morton,
            submax: submax,
            comparisonObserved: previousObserved,
            ranking: ranking
        )
    }

    private static func maximalMeanPower(from activities: [Activity]) -> [PowerCurvePoint] {
        guard !activities.isEmpty else { return [] }

        var bestByDuration: [Int: Double] = [:]
        for activity in activities {
            let samples = powerSamples(activity: activity, stepSec: 5)
            guard !samples.isEmpty else { continue }

            for duration in durations {
                let candidate: Double?
                if duration == 1 {
                    candidate = samples.max()
                } else {
                    candidate = rollingMaxMean(samples: samples, windowSec: duration, stepSec: 5)
                }
                if let candidate {
                    bestByDuration[duration] = max(bestByDuration[duration] ?? 0, candidate)
                }
            }
        }

        return durations.compactMap { duration in
            guard let power = bestByDuration[duration], power > 0 else { return nil }
            return PowerCurvePoint(durationSec: duration, power: power)
        }
    }

    private static func powerSamples(activity: Activity, stepSec: Int) -> [Double] {
        let step = max(1, stepSec)

        if !activity.intervals.isEmpty {
            var rows: [Double] = []
            let fallback = Double(activity.normalizedPower ?? 0)
            for effort in activity.intervals {
                let duration = max(step, effort.durationSec)
                let count = max(1, duration / step)
                let power = Double(effort.actualPower ?? effort.targetPower ?? activity.normalizedPower ?? 0)
                rows.append(contentsOf: repeatElement(max(40, power), count: count))
            }
            if rows.isEmpty, fallback > 0 {
                let count = max(1, activity.durationSec / step)
                rows.append(contentsOf: repeatElement(fallback, count: count))
            }
            return rows
        }

        guard let np = activity.normalizedPower else { return [] }
        let count = max(8, activity.durationSec / step)
        return Array(repeating: max(40.0, Double(np)), count: count)
    }

    private static func rollingMaxMean(samples: [Double], windowSec: Int, stepSec: Int) -> Double? {
        let window = max(1, windowSec / max(1, stepSec))
        guard samples.count >= window else { return nil }

        var rolling = samples[0..<window].reduce(0, +)
        var best = rolling

        if samples.count > window {
            for idx in window..<samples.count {
                rolling += samples[idx] - samples[idx - window]
                if rolling > best {
                    best = rolling
                }
            }
        }

        return best / Double(window)
    }

    private static func fitMonod(from points: [PowerCurvePoint]) -> CPModelFit? {
        let usable = points.filter { $0.durationSec >= 120 }
        guard usable.count >= 3 else { return nil }

        let xs = usable.map { 1.0 / Double($0.durationSec) }
        let ys = usable.map(\.power)
        guard let reg = linearRegression(x: xs, y: ys) else { return nil }

        let cp = max(40.0, reg.intercept)
        let pMax = points.map(\.power).max() ?? cp
        let wPrimeCap = robustWPrimeCap(points: usable, cp: cp)
        let wPrime = min(max(1000.0, reg.slope), wPrimeCap)

        let curveUpperBound = curveUpperBound(pMax: pMax, cp: cp)
        let curve = modelCurveDurations.map { duration -> PowerCurvePoint in
            let raw = cp + wPrime / Double(duration)
            let power = sanitizeCurvePower(raw, cp: cp, upperBound: curveUpperBound)
            return PowerCurvePoint(durationSec: duration, power: power)
        }

        return CPModelFit(name: "Monod-Scherrer", cp: cp, wPrime: wPrime, pMax: pMax, tau: nil, r2: reg.r2, curve: curve)
    }

    private static func fitMorton3P(from points: [PowerCurvePoint]) -> CPModelFit? {
        let usable = points.filter { $0.durationSec >= 30 }
        guard usable.count >= 4 else { return nil }

        var best: (tau: Double, cp: Double, wPrime: Double, r2: Double, sse: Double)?

        for tau in stride(from: 5.0, through: 480.0, by: 5.0) {
            let xs = usable.map { 1.0 / (Double($0.durationSec) + tau) }
            let ys = usable.map(\.power)
            guard let reg = linearRegression(x: xs, y: ys) else { continue }

            let cp = max(40.0, reg.intercept)
            let wPrimeCap = robustWPrimeCap(points: usable, cp: cp)
            let wPrime = min(max(500.0, reg.slope), wPrimeCap)
            let sse = zip(usable, xs).reduce(0.0) { partial, tuple in
                let predicted = cp + wPrime * tuple.1
                let error = tuple.0.power - predicted
                return partial + error * error
            }

            if let bestCurrent = best {
                if sse < bestCurrent.sse {
                    best = (tau, cp, wPrime, reg.r2, sse)
                }
            } else {
                best = (tau, cp, wPrime, reg.r2, sse)
            }
        }

        guard let best else { return nil }
        let pMax = points.map(\.power).max() ?? best.cp
        let curveUpperBound = curveUpperBound(pMax: pMax, cp: best.cp)
        let curve = modelCurveDurations.map { duration -> PowerCurvePoint in
            let raw = best.cp + best.wPrime / (Double(duration) + best.tau)
            let power = sanitizeCurvePower(raw, cp: best.cp, upperBound: curveUpperBound)
            return PowerCurvePoint(durationSec: duration, power: power)
        }

        return CPModelFit(name: "Morton 3P", cp: best.cp, wPrime: best.wPrime, pMax: pMax, tau: best.tau, r2: best.r2, curve: curve)
    }

    private static func fitSubmax(from points: [PowerCurvePoint]) -> CPModelFit? {
        let submax = points.filter { $0.durationSec >= 300 && $0.durationSec <= 2400 }
        guard submax.count >= 3 else { return nil }

        let cp = submax.map(\.power).reduce(0, +) / Double(submax.count)
        let pMax = points.map(\.power).max() ?? cp
        let wPrime = max(5000.0, (pMax - cp) * 220.0)
        let curveUpperBound = curveUpperBound(pMax: pMax, cp: cp)

        let curve = modelCurveDurations.map { duration -> PowerCurvePoint in
            let raw = cp + (pMax - cp) * exp(-Double(duration) / 300.0)
            let power = sanitizeCurvePower(raw, cp: cp, upperBound: curveUpperBound)
            return PowerCurvePoint(durationSec: duration, power: power)
        }

        return CPModelFit(name: "Submax Envelope", cp: cp, wPrime: wPrime, pMax: pMax, tau: 300.0, r2: 0.76, curve: curve)
    }

    private static func robustWPrimeCap(points: [PowerCurvePoint], cp: Double) -> Double {
        let candidates = points
            .filter { $0.durationSec >= 120 && $0.durationSec <= 1800 }
            .map { point in
                max(0.0, (point.power - cp) * Double(point.durationSec))
            }
            .filter { $0 > 0 && $0.isFinite }
            .sorted()

        guard !candidates.isEmpty else { return 60_000.0 }
        let p75 = candidates[Int(Double(candidates.count - 1) * 0.75)]
        let p90 = candidates[Int(Double(candidates.count - 1) * 0.90)]
        let cap = max(8_000.0, p75 * 2.0, p90 * 1.4)
        return min(cap, 80_000.0)
    }

    private static func curveUpperBound(pMax: Double, cp: Double) -> Double {
        let peak = max(pMax, cp)
        return max(500.0, peak * 1.7)
    }

    private static func sanitizeCurvePower(_ power: Double, cp: Double, upperBound: Double) -> Double {
        guard power.isFinite else { return cp }
        return min(max(power, 20.0), upperBound)
    }

    private static func linearRegression(x: [Double], y: [Double]) -> (slope: Double, intercept: Double, r2: Double)? {
        guard x.count == y.count, x.count >= 2 else { return nil }

        let meanX = x.reduce(0, +) / Double(x.count)
        let meanY = y.reduce(0, +) / Double(y.count)

        var numerator = 0.0
        var denominator = 0.0
        for (xx, yy) in zip(x, y) {
            numerator += (xx - meanX) * (yy - meanY)
            denominator += (xx - meanX) * (xx - meanX)
        }

        guard denominator != 0 else { return nil }
        let slope = numerator / denominator
        let intercept = meanY - slope * meanX

        var ssTot = 0.0
        var ssRes = 0.0
        for (xx, yy) in zip(x, y) {
            let pred = intercept + slope * xx
            ssTot += (yy - meanY) * (yy - meanY)
            ssRes += (yy - pred) * (yy - pred)
        }

        let r2 = ssTot > 0 ? max(0.0, 1.0 - ssRes / ssTot) : 0
        return (slope, intercept, r2)
    }
}

enum RiderRankingEngine {
    static func evaluate(profile: AthleteProfile, observed: [PowerCurvePoint], age: Int, weightKg: Double) -> WkgRankingResult {
        let ftp = Double(profile.cyclingFTPWatts)
        let normalizedWeight = max(35.0, weightKg)
        let ftpWkg = ftp / normalizedWeight

        let ageBand: String
        let thresholds: [Double]
        switch age {
        case ..<20:
            ageBand = "U20"
            thresholds = [2.4, 2.9, 3.4, 3.9, 4.5, 5.1]
        case 20..<30:
            ageBand = "20-29"
            thresholds = [2.5, 3.0, 3.5, 4.0, 4.6, 5.2]
        case 30..<40:
            ageBand = "30-39"
            thresholds = [2.4, 2.9, 3.3, 3.8, 4.3, 4.9]
        case 40..<50:
            ageBand = "40-49"
            thresholds = [2.2, 2.7, 3.1, 3.6, 4.1, 4.7]
        case 50..<60:
            ageBand = "50-59"
            thresholds = [2.0, 2.4, 2.9, 3.4, 3.9, 4.4]
        default:
            ageBand = "60+"
            thresholds = [1.8, 2.2, 2.6, 3.1, 3.6, 4.1]
        }

        let percentiles = [10.0, 25.0, 40.0, 60.0, 80.0, 92.0]
        let percentile = percentileFor(value: ftpWkg, thresholds: thresholds, percentiles: percentiles)
        let rank = max(1, Int((1.0 - percentile / 100.0) * 1000.0))

        let persona = personaFor(profile: profile, observed: observed)
        return WkgRankingResult(
            ftpWkg: ftpWkg,
            ageBand: ageBand,
            percentile: percentile,
            rankIn1000: rank,
            persona: persona
        )
    }

    private static func percentileFor(value: Double, thresholds: [Double], percentiles: [Double]) -> Double {
        guard thresholds.count == percentiles.count, !thresholds.isEmpty else { return 50 }

        if value <= thresholds[0] {
            return max(1, percentiles[0] * value / max(0.1, thresholds[0]))
        }

        for idx in 1..<thresholds.count {
            if value <= thresholds[idx] {
                let x0 = thresholds[idx - 1]
                let x1 = thresholds[idx]
                let y0 = percentiles[idx - 1]
                let y1 = percentiles[idx]
                let ratio = (value - x0) / max(1e-6, x1 - x0)
                return y0 + (y1 - y0) * ratio
            }
        }

        let top = thresholds[thresholds.count - 1]
        let overflow = min(8.0, (value - top) * 6.0)
        return min(99.5, percentiles[percentiles.count - 1] + overflow)
    }

    private static func personaFor(profile: AthleteProfile, observed: [PowerCurvePoint]) -> RiderPersona {
        func power(at duration: Int) -> Double {
            observed.first(where: { $0.durationSec == duration })?.power ?? 0
        }

        let p1 = power(at: 60)
        let p5 = power(at: 300)
        let p20 = power(at: 1200)
        let ftp = Double(max(1, profile.cyclingFTPWatts))

        let oneMinRatio = p1 / ftp
        let fiveMinRatio = p5 / ftp
        let twentyMinRatio = p20 / ftp

        if oneMinRatio > 1.9 && fiveMinRatio > 1.45 {
            return .sprinter
        }
        if twentyMinRatio > 1.02 && fiveMinRatio > 1.20 {
            return .climber
        }
        if twentyMinRatio > 0.95 && oneMinRatio < 1.6 {
            return .pursuiter
        }
        return .allRounder
    }
}

private func clip(_ value: Double, min: Double, max: Double) -> Double {
    Swift.max(min, Swift.min(max, value))
}

private extension BinaryInteger {
    static func max(_ a: Self, _ b: Self, _ c: Self) -> Self {
        Swift.max(a, Swift.max(b, c))
    }
}
