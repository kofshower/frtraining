import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

protocol DataRepository {
    func loadActivities() throws -> [Activity]
    func saveActivities(_ activities: [Activity]) throws
    func loadActivityMetricInsights() throws -> [ActivityMetricInsight]
    func saveActivityMetricInsights(_ insights: [ActivityMetricInsight]) throws
    func loadDailyMealPlans() throws -> [DailyMealPlan]
    func saveDailyMealPlans(_ plans: [DailyMealPlan]) throws
    func loadCustomFoods() throws -> [CustomFoodLibraryItem]
    func saveCustomFoods(_ foods: [CustomFoodLibraryItem]) throws
    func loadWorkouts() throws -> [PlannedWorkout]
    func saveWorkouts(_ workouts: [PlannedWorkout]) throws
    func loadCalendarEvents() throws -> [CalendarEvent]
    func saveCalendarEvents(_ events: [CalendarEvent]) throws
    func loadProfile() throws -> AthleteProfile
    func saveProfile(_ profile: AthleteProfile) throws
    func loadLactateHistoryRecords() throws -> [LactateHistoryRecord]
    func saveLactateHistoryRecords(_ records: [LactateHistoryRecord]) throws
}

extension DataRepository {
    func loadLactateHistoryRecords() throws -> [LactateHistoryRecord] {
        []
    }

    func saveLactateHistoryRecords(_ records: [LactateHistoryRecord]) throws {
        _ = records
    }
}

enum RepositoryError: Error {
    case appSupportUnavailable
    case invalidServerURL
    case httpError(Int)
    case noResponse
}

final class RemoteHTTPRepository: DataRepository {
    private let baseURL: URL
    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(baseURL: URL? = nil) throws {
        if let baseURL {
            self.baseURL = baseURL
        } else if let env = ProcessInfo.processInfo.environment["FRICU_SERVER_URL"],
                  let parsed = URL(string: env) {
            self.baseURL = parsed
        } else if let fallback = URL(string: "http://127.0.0.1:8080") {
            self.baseURL = fallback
        } else {
            throw RepositoryError.invalidServerURL
        }

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: config)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    private func endpoint(_ key: String) -> URL {
        baseURL.appendingPathComponent("v1/data/\(key)")
    }

    private func fetch<T: Decodable>(_ key: String, as type: T.Type) throws -> T {
        var req = URLRequest(url: endpoint(key))
        req.httpMethod = "GET"
        let data = try execute(req)
        return try decoder.decode(T.self, from: data)
    }

    private func push<T: Encodable>(_ key: String, value: T) throws {
        var req = URLRequest(url: endpoint(key))
        req.httpMethod = "PUT"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try encoder.encode(value)
        _ = try execute(req)
    }

    private func execute(_ req: URLRequest) throws -> Data {
        let semaphore = DispatchSemaphore(value: 0)
        var responseData = Data()
        var responseError: Error?
        var statusCode: Int?

        let task = session.dataTask(with: req) { data, response, error in
            responseData = data ?? Data()
            responseError = error
            statusCode = (response as? HTTPURLResponse)?.statusCode
            semaphore.signal()
        }
        task.resume()
        semaphore.wait()

        if let responseError {
            throw responseError
        }

        guard let statusCode else {
            throw RepositoryError.noResponse
        }

        guard (200..<300).contains(statusCode) else {
            throw RepositoryError.httpError(statusCode)
        }

        return responseData
    }

    func loadActivities() throws -> [Activity] {
        try fetch("activities", as: [Activity].self).sorted { $0.date > $1.date }
    }

    func saveActivities(_ activities: [Activity]) throws {
        try push("activities", value: activities)
    }

    func loadActivityMetricInsights() throws -> [ActivityMetricInsight] {
        try fetch("activity_metric_insights", as: [ActivityMetricInsight].self)
            .sorted { $0.activityDate > $1.activityDate }
    }

    func saveActivityMetricInsights(_ insights: [ActivityMetricInsight]) throws {
        try push("activity_metric_insights", value: insights)
    }

    func loadDailyMealPlans() throws -> [DailyMealPlan] {
        try fetch("meal_plans", as: [DailyMealPlan].self).sorted { $0.date > $1.date }
    }

    func saveDailyMealPlans(_ plans: [DailyMealPlan]) throws {
        try push("meal_plans", value: plans)
    }

    func loadCustomFoods() throws -> [CustomFoodLibraryItem] {
        try fetch("custom_foods", as: [CustomFoodLibraryItem].self).sorted { $0.createdAt > $1.createdAt }
    }

    func saveCustomFoods(_ foods: [CustomFoodLibraryItem]) throws {
        try push("custom_foods", value: foods)
    }

    func loadWorkouts() throws -> [PlannedWorkout] {
        try fetch("workouts", as: [PlannedWorkout].self).sorted { $0.createdAt > $1.createdAt }
    }

    func saveWorkouts(_ workouts: [PlannedWorkout]) throws {
        try push("workouts", value: workouts)
    }

    func loadCalendarEvents() throws -> [CalendarEvent] {
        try fetch("events", as: [CalendarEvent].self).sorted { $0.startDate > $1.startDate }
    }

    func saveCalendarEvents(_ events: [CalendarEvent]) throws {
        try push("events", value: events)
    }

    func loadProfile() throws -> AthleteProfile {
        do {
            return try fetch("profile", as: AthleteProfile.self)
        } catch {
            return .default
        }
    }

    func saveProfile(_ profile: AthleteProfile) throws {
        try push("profile", value: profile)
    }

    func loadLactateHistoryRecords() throws -> [LactateHistoryRecord] {
        try fetch("lactate_history_records", as: [LactateHistoryRecord].self)
            .sorted { $0.createdAt > $1.createdAt }
    }

    func saveLactateHistoryRecords(_ records: [LactateHistoryRecord]) throws {
        try push("lactate_history_records", value: records)
    }
}

final class LocalJSONRepository: DataRepository {
    private let activitiesURL: URL
    private let activityMetricInsightsURL: URL
    private let mealPlansURL: URL
    private let customFoodsURL: URL
    private let workoutsURL: URL
    private let eventsURL: URL
    private let profileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init() throws {
        let fm = FileManager.default
        guard let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw RepositoryError.appSupportUnavailable
        }

        let root = appSupport.appendingPathComponent("Fricu", isDirectory: true)
        if !fm.fileExists(atPath: root.path) {
            try fm.createDirectory(at: root, withIntermediateDirectories: true)
        }

        self.activitiesURL = root.appendingPathComponent("activities.json")
        self.activityMetricInsightsURL = root.appendingPathComponent("activity_metric_insights.json")
        self.mealPlansURL = root.appendingPathComponent("meal_plans.json")
        self.customFoodsURL = root.appendingPathComponent("custom_foods.json")
        self.workoutsURL = root.appendingPathComponent("workouts.json")
        self.eventsURL = root.appendingPathComponent("events.json")
        self.profileURL = root.appendingPathComponent("profile.json")

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func loadActivities() throws -> [Activity] {
        if FileManager.default.fileExists(atPath: activitiesURL.path) {
            let data = try Data(contentsOf: activitiesURL)
            return try decoder.decode([Activity].self, from: data).sorted { $0.date > $1.date }
        }

        let demo = DemoDataFactory.generateActivities(days: 160)
        try saveActivities(demo)
        return demo.sorted { $0.date > $1.date }
    }

    func saveActivities(_ activities: [Activity]) throws {
        let data = try encoder.encode(activities)
        try data.write(to: activitiesURL, options: .atomic)
    }

    func loadActivityMetricInsights() throws -> [ActivityMetricInsight] {
        if FileManager.default.fileExists(atPath: activityMetricInsightsURL.path) {
            let data = try Data(contentsOf: activityMetricInsightsURL)
            return try decoder.decode([ActivityMetricInsight].self, from: data)
                .sorted { $0.activityDate > $1.activityDate }
        }
        return []
    }

    func saveActivityMetricInsights(_ insights: [ActivityMetricInsight]) throws {
        let data = try encoder.encode(insights)
        try data.write(to: activityMetricInsightsURL, options: .atomic)
    }

    func loadDailyMealPlans() throws -> [DailyMealPlan] {
        if FileManager.default.fileExists(atPath: mealPlansURL.path) {
            let data = try Data(contentsOf: mealPlansURL)
            return try decoder.decode([DailyMealPlan].self, from: data).sorted { $0.date > $1.date }
        }
        return []
    }

    func saveDailyMealPlans(_ plans: [DailyMealPlan]) throws {
        let data = try encoder.encode(plans)
        try data.write(to: mealPlansURL, options: .atomic)
    }

    func loadCustomFoods() throws -> [CustomFoodLibraryItem] {
        if FileManager.default.fileExists(atPath: customFoodsURL.path) {
            let data = try Data(contentsOf: customFoodsURL)
            return try decoder.decode([CustomFoodLibraryItem].self, from: data)
                .sorted { $0.createdAt > $1.createdAt }
        }
        return []
    }

    func saveCustomFoods(_ foods: [CustomFoodLibraryItem]) throws {
        let data = try encoder.encode(foods)
        try data.write(to: customFoodsURL, options: .atomic)
    }

    func loadWorkouts() throws -> [PlannedWorkout] {
        if FileManager.default.fileExists(atPath: workoutsURL.path) {
            let data = try Data(contentsOf: workoutsURL)
            return try decoder.decode([PlannedWorkout].self, from: data).sorted { $0.createdAt > $1.createdAt }
        }

        let demo: [PlannedWorkout] = [
            PlannedWorkout(
                name: "Threshold Build 4x8",
                sport: .cycling,
                segments: [
                    WorkoutSegment(minutes: 10, intensityPercentFTP: 60, note: "Warm-up"),
                    WorkoutSegment(minutes: 8, intensityPercentFTP: 102, note: "Threshold"),
                    WorkoutSegment(minutes: 4, intensityPercentFTP: 55, note: "Recovery"),
                    WorkoutSegment(minutes: 8, intensityPercentFTP: 102, note: "Threshold"),
                    WorkoutSegment(minutes: 4, intensityPercentFTP: 55, note: "Recovery"),
                    WorkoutSegment(minutes: 8, intensityPercentFTP: 102, note: "Threshold"),
                    WorkoutSegment(minutes: 4, intensityPercentFTP: 55, note: "Recovery"),
                    WorkoutSegment(minutes: 8, intensityPercentFTP: 102, note: "Threshold"),
                    WorkoutSegment(minutes: 10, intensityPercentFTP: 50, note: "Cool-down")
                ]
            )
        ]
        try saveWorkouts(demo)
        return demo
    }

    func saveWorkouts(_ workouts: [PlannedWorkout]) throws {
        let data = try encoder.encode(workouts)
        try data.write(to: workoutsURL, options: .atomic)
    }

    func loadCalendarEvents() throws -> [CalendarEvent] {
        if FileManager.default.fileExists(atPath: eventsURL.path) {
            let data = try Data(contentsOf: eventsURL)
            return try decoder.decode([CalendarEvent].self, from: data).sorted { $0.startDate > $1.startDate }
        }

        let empty: [CalendarEvent] = []
        try saveCalendarEvents(empty)
        return empty
    }

    func saveCalendarEvents(_ events: [CalendarEvent]) throws {
        let data = try encoder.encode(events)
        try data.write(to: eventsURL, options: .atomic)
    }

    func loadProfile() throws -> AthleteProfile {
        if FileManager.default.fileExists(atPath: profileURL.path) {
            let data = try Data(contentsOf: profileURL)
            return try decoder.decode(AthleteProfile.self, from: data)
        }
        let profile = AthleteProfile.default
        try saveProfile(profile)
        return profile
    }

    func saveProfile(_ profile: AthleteProfile) throws {
        let data = try encoder.encode(profile)
        try data.write(to: profileURL, options: .atomic)
    }

    func loadLactateHistoryRecords() throws -> [LactateHistoryRecord] {
        []
    }

    func saveLactateHistoryRecords(_ records: [LactateHistoryRecord]) throws {
    }
}

enum DemoDataFactory {
    static func generateActivities(days: Int) -> [Activity] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var rows: [Activity] = []

        for offset in 0..<days {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }

            // Rest day every 5 days.
            if offset % 5 == 0 { continue }

            let hard = offset % 9 == 0
            let long = offset % 7 == 0
            let duration = hard ? 95 * 60 : (long ? 150 * 60 : 70 * 60)
            let tss = hard ? 115 : (long ? 145 : 68)
            let distance = hard ? 41.0 : (long ? 92.0 : 33.0)
            let np = hard ? 286 : (long ? 238 : 210)

            var intervals: [IntervalEffort] = []
            if hard {
                intervals = [
                    IntervalEffort(name: "Warm-up", durationSec: 15 * 60, targetPower: 165, actualPower: 170),
                    IntervalEffort(name: "VO2 #1", durationSec: 4 * 60, targetPower: 355, actualPower: 349),
                    IntervalEffort(name: "Recovery", durationSec: 4 * 60, targetPower: 150, actualPower: 148),
                    IntervalEffort(name: "VO2 #2", durationSec: 4 * 60, targetPower: 355, actualPower: 360)
                ]
            }

            rows.append(
                Activity(
                    date: day,
                    sport: .cycling,
                    durationSec: duration,
                    distanceKm: distance,
                    tss: tss,
                    normalizedPower: np,
                    avgHeartRate: hard ? 163 : 146,
                    intervals: intervals,
                    notes: hard ? "Key quality session" : "Base/endurance"
                )
            )
        }

        return rows.sorted { $0.date > $1.date }
    }
}

enum LoadCalculator {
    struct TISSSplitEstimate {
        var aerobic: Double
        var anaerobic: Double
        var intensityFactor: Double
        var anaerobicShare: Double

        static let zero = TISSSplitEstimate(aerobic: 0, anaerobic: 0, intensityFactor: 0, anaerobicShare: 0)

        var total: Double { aerobic + anaerobic }
    }

    static func buildSeries(activities: [Activity], profile: AthleteProfile = .default, days: Int = 120) -> [DailyLoadPoint] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let start = calendar.date(byAdding: .day, value: -days + 1, to: today) else { return [] }

        let tissByDay = Dictionary(grouping: activities) { calendar.startOfDay(for: $0.date) }
            .mapValues { dayActivities in
                dayActivities.reduce(into: TISSSplitEstimate.zero) { partial, activity in
                    let split = estimateTISSSplit(activity: activity, profile: profile)
                    partial.aerobic += split.aerobic
                    partial.anaerobic += split.anaerobic
                }
            }

        let hasAnyLoadInWindow = tissByDay.contains { key, split in
            key >= start && key <= today && split.total > 0.0
        }

        var ctl = hasAnyLoadInWindow ? 45.0 : 0.0
        var atl = hasAnyLoadInWindow ? 50.0 : 0.0
        let ctlTau = 42.0
        let atlTau = 7.0
        var aerobicLongTermStress = hasAnyLoadInWindow ? 32.0 : 0.0
        var anaerobicLongTermStress = hasAnyLoadInWindow ? 13.0 : 0.0
        var aerobicShortTermStress = hasAnyLoadInWindow ? 35.0 : 0.0
        var anaerobicShortTermStress = hasAnyLoadInWindow ? 15.0 : 0.0

        var result: [DailyLoadPoint] = []
        var cursor = start
        while cursor <= today {
            let split = tissByDay[cursor] ?? .zero
            let tss = split.total
            ctl += (tss - ctl) / ctlTau
            atl += (tss - atl) / atlTau
            aerobicLongTermStress += (split.aerobic - aerobicLongTermStress) / ctlTau
            anaerobicLongTermStress += (split.anaerobic - anaerobicLongTermStress) / ctlTau
            aerobicShortTermStress += (split.aerobic - aerobicShortTermStress) / atlTau
            anaerobicShortTermStress += (split.anaerobic - anaerobicShortTermStress) / atlTau
            result.append(
                DailyLoadPoint(
                    date: cursor,
                    tss: tss,
                    aerobicTISS: split.aerobic,
                    anaerobicTISS: split.anaerobic,
                    ctl: ctl,
                    atl: atl,
                    tsb: ctl - atl,
                    aerobicLongTermStress: aerobicLongTermStress,
                    anaerobicLongTermStress: anaerobicLongTermStress,
                    aerobicShortTermStress: aerobicShortTermStress,
                    anaerobicShortTermStress: anaerobicShortTermStress
                )
            )

            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }

        return result
    }

    static func estimateTISSSplit(activity: Activity, profile: AthleteProfile) -> TISSSplitEstimate {
        let tss = max(0.0, Double(activity.tss))
        guard tss > 0 else { return .zero }
        let intensityFactor = estimateIntensityFactor(activity: activity, profile: profile, tss: tss)
        let anaerobicRatio = anaerobicShare(intensityFactor: intensityFactor)
        return TISSSplitEstimate(
            aerobic: tss * (1 - anaerobicRatio),
            anaerobic: tss * anaerobicRatio,
            intensityFactor: intensityFactor,
            anaerobicShare: anaerobicRatio
        )
    }

    private static func estimateIntensityFactor(activity: Activity, profile: AthleteProfile, tss: Double) -> Double {
        if let np = activity.normalizedPower, np > 0 {
            let ftp = max(profile.ftpWatts(for: activity.sport), 1)
            return clamp(Double(np) / Double(ftp), min: 0.3, max: 1.8)
        }

        if let avgHR = activity.avgHeartRate, avgHR > 0 {
            let thresholdHR = max(profile.thresholdHeartRate(for: activity.sport, on: activity.date), 1)
            return clamp(Double(avgHR) / Double(thresholdHR), min: 0.3, max: 1.5)
        }

        let durationHours = max(Double(activity.durationSec) / 3600.0, 0.05)
        let inferredIF = sqrt(tss / (100.0 * durationHours))
        return clamp(inferredIF, min: 0.3, max: 1.5)
    }

    private static func anaerobicShare(intensityFactor: Double) -> Double {
        // IF <= 0.75 is treated mostly aerobic; high IF progressively contributes anaerobic stress.
        let normalized = clamp((intensityFactor - 0.75) / 0.45, min: 0, max: 1)
        return pow(normalized, 1.3)
    }

    private static func clamp(_ value: Double, min: Double, max: Double) -> Double {
        Swift.max(min, Swift.min(value, max))
    }

    static func summary(activities: [Activity], series: [DailyLoadPoint]) -> DashboardSummary {
        let calendar = Calendar.current
        let now = Date()

        guard !activities.isEmpty else {
            return DashboardSummary(weeklyTSS: 0, monthlyDistanceKm: 0, currentCTL: 0, currentATL: 0, currentTSB: 0)
        }

        let weeklyTSS = activities
            .filter { calendar.isDate($0.date, equalTo: now, toGranularity: .weekOfYear) }
            .reduce(0) { $0 + $1.tss }

        let monthlyDistance = activities
            .filter { calendar.isDate($0.date, equalTo: now, toGranularity: .month) }
            .reduce(0.0) { $0 + $1.distanceKm }

        let latest = series.last

        return DashboardSummary(
            weeklyTSS: weeklyTSS,
            monthlyDistanceKm: monthlyDistance,
            currentCTL: latest?.ctl ?? 0,
            currentATL: latest?.atl ?? 0,
            currentTSB: latest?.tsb ?? 0
        )
    }
}
