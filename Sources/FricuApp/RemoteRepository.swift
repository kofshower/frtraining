import Foundation

enum RemoteRepositoryError: Error, LocalizedError {
    case invalidBaseURL(String)
    case invalidResponse
    case serverStatus(Int, String)
    case requestTimedOut
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL(let raw):
            return "Invalid server URL: \(raw)"
        case .invalidResponse:
            return "Invalid response from server"
        case .serverStatus(let code, let body):
            return "Server returned HTTP \(code): \(body)"
        case .requestTimedOut:
            return "Server request timed out"
        case .transport(let message):
            return "Network transport error: \(message)"
        }
    }
}

struct RemoteRepositoryConfig {
    let baseURL: URL
    let hydrateTimeout: TimeInterval
    let uploadTimeout: TimeInterval
    let uploadDebounceSeconds: TimeInterval

    static func resolve() -> RemoteRepositoryConfig? {
        let env = ProcessInfo.processInfo.environment
        let raw =
            env["FRICU_SERVER_BASE_URL"] ??
            env["FRICU_API_BASE_URL"] ??
            Bundle.main.object(forInfoDictionaryKey: "FricuServerBaseURL") as? String

        guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        let normalized: String
        if raw.contains("://") {
            normalized = raw
        } else {
            normalized = "http://\(raw)"
        }

        guard let url = URL(string: normalized) else {
            return nil
        }

        return RemoteRepositoryConfig(
            baseURL: url,
            hydrateTimeout: 0.8,
            uploadTimeout: 2.0,
            uploadDebounceSeconds: 0.8
        )
    }
}

private struct RemoteDataSnapshot: Codable {
    var activities: [Activity]
    var activityMetricInsights: [ActivityMetricInsight]
    var dailyMealPlans: [DailyMealPlan]
    var customFoods: [CustomFoodLibraryItem]
    var workouts: [PlannedWorkout]
    var calendarEvents: [CalendarEvent]
    var profile: AthleteProfile
    var updatedAt: Date

    var hasContent: Bool {
        !activities.isEmpty ||
            !activityMetricInsights.isEmpty ||
            !dailyMealPlans.isEmpty ||
            !customFoods.isEmpty ||
            !workouts.isEmpty ||
            !calendarEvents.isEmpty
    }
}

private final class FricuServerClient {
    private let config: RemoteRepositoryConfig
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let session: URLSession

    init(config: RemoteRepositoryConfig) {
        self.config = config
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
        self.session = .shared
    }

    func fetchSnapshot(timeout: TimeInterval) throws -> RemoteDataSnapshot {
        let requestURL = config.baseURL.appending(path: "v1/snapshot")
        var request = URLRequest(url: requestURL)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout

        let (data, response) = try perform(request: request, timeout: timeout)
        guard let http = response as? HTTPURLResponse else {
            throw RemoteRepositoryError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "<non-utf8 body>"
            throw RemoteRepositoryError.serverStatus(http.statusCode, body)
        }
        return try decoder.decode(RemoteDataSnapshot.self, from: data)
    }

    func pushSnapshot(_ snapshot: RemoteDataSnapshot, timeout: TimeInterval) throws {
        let requestURL = config.baseURL.appending(path: "v1/snapshot")
        var request = URLRequest(url: requestURL)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = timeout
        request.httpBody = try encoder.encode(snapshot)

        let (data, response) = try perform(request: request, timeout: timeout)
        guard let http = response as? HTTPURLResponse else {
            throw RemoteRepositoryError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "<non-utf8 body>"
            throw RemoteRepositoryError.serverStatus(http.statusCode, body)
        }
    }

    private func perform(request: URLRequest, timeout: TimeInterval) throws -> (Data, URLResponse) {
        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<(Data, URLResponse), Error>?

        let task = session.dataTask(with: request) { data, response, error in
            defer { semaphore.signal() }
            if let error {
                result = .failure(error)
                return
            }
            guard let data, let response else {
                result = .failure(RemoteRepositoryError.invalidResponse)
                return
            }
            result = .success((data, response))
        }
        task.resume()

        let wait = semaphore.wait(timeout: .now() + timeout)
        if wait == .timedOut {
            task.cancel()
            throw RemoteRepositoryError.requestTimedOut
        }

        guard let result else {
            throw RemoteRepositoryError.invalidResponse
        }

        switch result {
        case .success(let output):
            return output
        case .failure(let error):
            throw RemoteRepositoryError.transport(error.localizedDescription)
        }
    }
}

final class RemoteFirstRepository: DataRepository {
    private let local: LocalJSONRepository
    private let client: FricuServerClient
    private let config: RemoteRepositoryConfig
    private let uploadQueue = DispatchQueue(label: "fricu.remote.repository.upload", qos: .utility)
    private let offlineBackupWriter: ActivityOfflineBackupWriter
    private let hydrateLock = NSLock()
    private var didHydrateFromServer = false
    private var pendingUploadWorkItem: DispatchWorkItem?
    private var retryTimer: DispatchSourceTimer?
    private var hasPendingUploadFailure = false

    init(config: RemoteRepositoryConfig, local: LocalJSONRepository) {
        self.config = config
        self.local = local
        self.client = FricuServerClient(config: config)
        let backupDirectory: URL
        do {
            backupDirectory = try LocalJSONRepository.dataDirectoryURL().appendingPathComponent("offline-activity-backups", isDirectory: true)
        } catch {
            backupDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent("fricu-offline-activity-backups", isDirectory: true)
        }
        self.offlineBackupWriter = ActivityOfflineBackupWriter(
            backupDirectory: backupDirectory
        )
    }

    func loadActivities() throws -> [Activity] {
        hydrateFromServerIfNeeded()
        return try local.loadActivities()
    }

    func saveActivities(_ activities: [Activity]) throws {
        try local.saveActivities(activities)
        scheduleUpload()
    }

    func loadActivityMetricInsights() throws -> [ActivityMetricInsight] {
        hydrateFromServerIfNeeded()
        return try local.loadActivityMetricInsights()
    }

    func saveActivityMetricInsights(_ insights: [ActivityMetricInsight]) throws {
        try local.saveActivityMetricInsights(insights)
        scheduleUpload()
    }

    func loadDailyMealPlans() throws -> [DailyMealPlan] {
        hydrateFromServerIfNeeded()
        return try local.loadDailyMealPlans()
    }

    func saveDailyMealPlans(_ plans: [DailyMealPlan]) throws {
        try local.saveDailyMealPlans(plans)
        scheduleUpload()
    }

    func loadCustomFoods() throws -> [CustomFoodLibraryItem] {
        hydrateFromServerIfNeeded()
        return try local.loadCustomFoods()
    }

    func saveCustomFoods(_ foods: [CustomFoodLibraryItem]) throws {
        try local.saveCustomFoods(foods)
        scheduleUpload()
    }

    func loadWorkouts() throws -> [PlannedWorkout] {
        hydrateFromServerIfNeeded()
        return try local.loadWorkouts()
    }

    func saveWorkouts(_ workouts: [PlannedWorkout]) throws {
        try local.saveWorkouts(workouts)
        scheduleUpload()
    }

    func loadCalendarEvents() throws -> [CalendarEvent] {
        hydrateFromServerIfNeeded()
        return try local.loadCalendarEvents()
    }

    func saveCalendarEvents(_ events: [CalendarEvent]) throws {
        try local.saveCalendarEvents(events)
        scheduleUpload()
    }

    func loadProfile() throws -> AthleteProfile {
        hydrateFromServerIfNeeded()
        return try local.loadProfile()
    }

    func saveProfile(_ profile: AthleteProfile) throws {
        try local.saveProfile(profile)
        scheduleUpload()
    }

    private func hydrateFromServerIfNeeded() {
        hydrateLock.lock()
        if didHydrateFromServer {
            hydrateLock.unlock()
            return
        }
        didHydrateFromServer = true
        hydrateLock.unlock()

        do {
            let remoteSnapshot = try client.fetchSnapshot(timeout: config.hydrateTimeout)
            let localSnapshot = try makeLocalSnapshot()

            if remoteSnapshot.hasContent {
                try persistLocally(remoteSnapshot)
            } else if localSnapshot.hasContent {
                try client.pushSnapshot(localSnapshot, timeout: config.uploadTimeout)
            }
        } catch {
            print("Remote repository hydrate skipped: \(error.localizedDescription)")
        }
    }

    private func scheduleUpload() {
        uploadQueue.async { [weak self] in
            guard let self else { return }
            self.pendingUploadWorkItem?.cancel()

            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.attemptUploadNow()
            }

            self.pendingUploadWorkItem = work
            self.uploadQueue.asyncAfter(deadline: .now() + self.config.uploadDebounceSeconds, execute: work)
        }
    }

    /// Attempts one immediate upload and manages offline backup + retry loop.
    private func attemptUploadNow() {
        do {
            let snapshot = try self.makeLocalSnapshot()
            try self.client.pushSnapshot(snapshot, timeout: self.config.uploadTimeout)
            self.hasPendingUploadFailure = false
            stopRetryTimerIfNeeded()
        } catch {
            self.hasPendingUploadFailure = true
            backupActivitiesForOfflineRecovery()
            startRetryTimerIfNeeded()
            print("Remote repository upload failed: \(error.localizedDescription)")
        }
    }

    /// Writes deterministic FIT backups so failed server uploads never lose activity data.
    private func backupActivitiesForOfflineRecovery() {
        do {
            let activities = try local.loadActivities()
            let backupURLs = try offlineBackupWriter.backup(activities: activities)
            if !backupURLs.isEmpty {
                print("Wrote \(backupURLs.count) offline FIT backups")
            }
        } catch {
            print("Offline FIT backup failed: \(error.localizedDescription)")
        }
    }

    /// Starts a lightweight periodic retry for pending failed uploads.
    private func startRetryTimerIfNeeded() {
        guard retryTimer == nil else { return }

        let timer = DispatchSource.makeTimerSource(queue: uploadQueue)
        timer.schedule(deadline: .now() + 5.0, repeating: 15.0)
        timer.setEventHandler { [weak self] in
            guard let self, self.hasPendingUploadFailure else { return }
            self.attemptUploadNow()
        }
        timer.resume()
        retryTimer = timer
    }

    /// Stops the retry timer once pending upload failures are resolved.
    private func stopRetryTimerIfNeeded() {
        guard let retryTimer else { return }
        retryTimer.cancel()
        self.retryTimer = nil
    }

    private func makeLocalSnapshot() throws -> RemoteDataSnapshot {
        RemoteDataSnapshot(
            activities: try local.loadActivities(),
            activityMetricInsights: try local.loadActivityMetricInsights(),
            dailyMealPlans: try local.loadDailyMealPlans(),
            customFoods: try local.loadCustomFoods(),
            workouts: try local.loadWorkouts(),
            calendarEvents: try local.loadCalendarEvents(),
            profile: try local.loadProfile(),
            updatedAt: Date()
        )
    }

    private func persistLocally(_ snapshot: RemoteDataSnapshot) throws {
        try local.saveActivities(snapshot.activities)
        try local.saveActivityMetricInsights(snapshot.activityMetricInsights)
        try local.saveDailyMealPlans(snapshot.dailyMealPlans)
        try local.saveCustomFoods(snapshot.customFoods)
        try local.saveWorkouts(snapshot.workouts)
        try local.saveCalendarEvents(snapshot.calendarEvents)
        try local.saveProfile(snapshot.profile)
    }
}
