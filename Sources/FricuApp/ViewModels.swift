import Foundation
import Combine
#if canImport(SwiftUI)
import SwiftUI
#endif
#if canImport(AppKit)
import AppKit
#endif

struct TrainerRiderSession: Identifiable {
    let id: UUID
    var name: String
    let trainer: SmartTrainerManager
    let heartRateMonitor: HeartRateMonitorManager
    let powerMeter: PowerMeterManager
    let supportsRecording: Bool

    init(
        id: UUID = UUID(),
        name: String,
        trainer: SmartTrainerManager,
        heartRateMonitor: HeartRateMonitorManager,
        powerMeter: PowerMeterManager,
        supportsRecording: Bool
    ) {
        self.id = id
        self.name = name
        self.trainer = trainer
        self.heartRateMonitor = heartRateMonitor
        self.powerMeter = powerMeter
        self.supportsRecording = supportsRecording
    }
}

struct TrainerRecordingStatus {
    var isActive: Bool = false
    var elapsedSec: Int = 0
    var movingSec: Int = 0
    var sampleCount: Int = 0
    var elevationGainMeters: Double = 0
    var lastFitPath: String?
    var lastSyncSummary: String?
}

private struct TrainerRiderConnectionMemory: Codable {
    var id: UUID
    var name: String
    var preferredTrainerDeviceID: UUID?
    var preferredTrainerDeviceName: String?
    var preferredHeartRateDeviceID: UUID?
    var preferredPowerMeterDeviceID: UUID?
    var appearance: TrainerRiderAppearance?
}

private struct TrainerRiderConnectionStore: Codable {
    var primarySessionID: UUID?
    var riders: [TrainerRiderConnectionMemory]
}

enum AthletePanel {
    static let singleID = "__athlete_single__"
    static let allID = singleID
    static let unknownAthleteToken = "__default_athlete__"
}

struct ActivityRecoveryDiagnosticsSnapshot: Equatable {
    var accountID: String
    var serverEndpoint: String
    var remoteCount: Int?
    var localCacheCount: Int
    var repositoryLocalCacheCount: Int
    var remoteError: String?
    var isLoading: Bool
    var updatedAt: Date?

    static func initial(accountID: String, serverEndpoint: String) -> ActivityRecoveryDiagnosticsSnapshot {
        ActivityRecoveryDiagnosticsSnapshot(
            accountID: accountID,
            serverEndpoint: serverEndpoint,
            remoteCount: nil,
            localCacheCount: 0,
            repositoryLocalCacheCount: 0,
            remoteError: nil,
            isLoading: false,
            updatedAt: nil
        )
    }
}

@MainActor
final class AppStore: ObservableObject {
    @Published private(set) var activities: [Activity] = []
    @Published private(set) var dailyMealPlans: [DailyMealPlan] = []
    @Published private(set) var customFoodLibrary: [CustomFoodLibraryItem] = []
    @Published private(set) var plannedWorkouts: [PlannedWorkout] = []
    @Published private(set) var wellnessSamples: [WellnessSample] = []
    @Published private(set) var intervalsCalendarEvents: [CalendarEvent] = []
    @Published private(set) var lactateHistoryRecords: [LactateHistoryRecord] = []
    @Published var profile: AthleteProfile = .default {
        didSet {
            cacheProfileForSelectedAthlete()
        }
    }
    let trainer = SmartTrainerManager()
    let heartRateMonitor = HeartRateMonitorManager()
    let powerMeter = PowerMeterManager()
    @Published private(set) var trainerRiderSessions: [TrainerRiderSession] = []
    @Published private(set) var primaryTrainerSessionID: UUID?
    @Published private(set) var currentAccountID: String = "__anonymous__"
    @Published private(set) var currentAccountDisplayName: String = L10n.choose(
        simplifiedChinese: "未登录用户",
        english: "Anonymous"
    )

    @Published var selectedAthletePanelID: String = AthletePanel.singleID {
        didSet {
            guard selectedAthletePanelID != oldValue else { return }
            applySelectedAthleteProfileIfNeeded()
            markDerivedStateDirty()
        }
    }
    @Published var selectedSportFilter: SportType? = .cycling
    @Published var selectedScenario: TrainingScenario = .dailyDecision
    @Published var selectedEnduranceFocus: EnduranceFocus = .cardiacFilling
    @Published private(set) var aiCoachSource: String = "GPT"
    @Published private(set) var aiCoachStatus: String?
    @Published private(set) var aiCoachUpdatedAt: Date?
    @Published var isRefreshingAICoach = false
    @Published var lastError: String? {
        didSet {
            guard let lastError, !lastError.isEmpty, lastError != oldValue else { return }
            appendClientLog(level: "ERROR", message: lastError)
        }
    }
    @Published var syncStatus: String? {
        didSet {
            guard let syncStatus, !syncStatus.isEmpty, syncStatus != oldValue else { return }
            appendClientLog(level: "INFO", message: syncStatus)
        }
    }
    @Published var isSyncing = false
    @Published private(set) var clientLogLines: [String] = []
    @Published private(set) var athleteScopedActivitiesCache: [Activity] = []
    @Published private(set) var athleteScopedDailyMealPlansCache: [DailyMealPlan] = []
    @Published private(set) var athleteScopedPlannedWorkoutsCache: [PlannedWorkout] = []
    @Published private(set) var athleteScopedWellnessSamplesCache: [WellnessSample] = []
    @Published private(set) var athleteScopedCalendarEventsCache: [CalendarEvent] = []
    @Published private(set) var filteredActivitiesCache: [Activity] = []
    @Published private(set) var loadSeriesCache: [DailyLoadPoint] = []
    @Published private(set) var summaryCache: DashboardSummary = DashboardSummary(
        weeklyTSS: 0,
        monthlyDistanceKm: 0,
        currentCTL: 0,
        currentATL: 0,
        currentTSB: 0
    )
    @Published private(set) var metricStoriesCache: [MetricStory] = []
    @Published private(set) var scenarioMetricPackCache: ScenarioMetricPack = ScenarioMetricPack(
        scenario: .dailyDecision,
        headline: "",
        items: [],
        actions: []
    )
    @Published private(set) var activityMetricInsightsCache: [UUID: ActivityMetricInsight] = [:]
    @Published private(set) var refreshingActivityInsightIDs: Set<UUID> = []
    @Published private(set) var trainerRecordingIsActive = false
    @Published private(set) var trainerRecordingElapsedSec = 0
    @Published private(set) var trainerRecordingMovingSec = 0
    @Published private(set) var trainerRecordingSampleCount = 0
    @Published private(set) var trainerRecordingElevationGainMeters: Double = 0
    @Published private(set) var trainerRecordingLastFitPath: String?
    @Published private(set) var trainerRecordingLastSyncSummary: String?
    @Published private(set) var trainerRecordingStatusBySession: [UUID: TrainerRecordingStatus] = [:]
    @Published private(set) var activityRecoveryDiagnostics: ActivityRecoveryDiagnosticsSnapshot = .initial(
        accountID: "__anonymous__",
        serverEndpoint: "http://127.0.0.1:8080"
    )

    @Published var serverHost: String = "127.0.0.1"
    @Published var serverPort: String = "8080"
    @Published var connectionWarningMessage: String?
    private var gptRecommendation: AIRecommendation?
    private var didAttemptAICoachBootstrap = false
    private var repository: DataRepository?
    private var cancellables: Set<AnyCancellable> = []
    private var derivedRefreshToken: UInt64 = 0
    private var derivedRefreshWorkItem: DispatchWorkItem?
    private var derivedComputationGeneration: UInt64 = 0
    private let derivedComputationQueue = DispatchQueue(
        label: "fricu.derived.compute",
        qos: .userInitiated,
        attributes: [.concurrent]
    )
    private var trainerRecordingTimerTaskBySession: [UUID: Task<Void, Never>] = [:]
    private var trainerRecordingFinalizationTaskBySession: [UUID: Task<Void, Never>] = [:]
    private var trainerRecordingSessionByRider: [UUID: TrainerRecordingSession] = [:]
    private var isFinalizingTrainerRecordingBySession: Set<UUID> = []
    private var trainerConnectionCancellableBySession: [UUID: AnyCancellable] = [:]
    private var heartRateConnectionCancellableBySession: [UUID: AnyCancellable] = [:]
    private var powerMeterConnectionCancellableBySession: [UUID: AnyCancellable] = [:]
    private var trainerPowerCancellableBySession: [UUID: AnyCancellable] = [:]
    private var powerMeterPowerCancellableBySession: [UUID: AnyCancellable] = [:]
    private var trainerRiderConnectionMemoryBySessionID: [UUID: TrainerRiderConnectionMemory] = [:]
    private var activityRecoveryDiagnosticsRefreshGeneration: UInt64 = 0
    private let trainerRiderConnectionStoreDefaultsKey = "fricu.trainer.rider.connection.store.v1"
    private let serverHostDefaultsKey = "fricu.server.host.v1"
    private let serverPortDefaultsKey = "fricu.server.port.v1"
    private let nutritionUSDAAPIKeyDefaultsKey = "nutrition.usda.apiKey"
    private let stravaPullRecentDaysDefaultsKey = "fricu.strava.pull.recent.days.v1"
    private var isApplyingServerBackedSettings = false
    private var lastAppSettingsSyncedDigest: UInt64?
    private var lastAppSettingsFailedDigest: UInt64?
    private var lastAppSettingsFailedAt: Date?
    private let trainerRecordingCheckpointWriteIntervalSec: TimeInterval = 5
    private static let clientLogTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
    private var isAnonymousAccount: Bool {
        currentAccountID == "__anonymous__"
    }

    private var canonicalCurrentAccountAthleteName: String {
        AthleteIdentityNormalizer.canonicalName(currentAccountDisplayName) ?? currentAccountDisplayName
    }

    init() {
        loadServerEndpointFromDefaults()
        configureRepository()
        configureInitialTrainerSessions()
        setupAppSettingsSyncPipeline()
        setupDerivedRefreshPipeline()
        setupTrainerRecordingPipeline()
        markDerivedStateDirty()
    }

    func activateAuthenticatedAccount(accountID: String, displayName: String) {
        let normalizedID = accountID.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedDisplayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedID.isEmpty else {
            lastError = L10n.choose(simplifiedChinese: "账号 ID 不能为空", english: "Account ID cannot be empty")
            return
        }
        let resolvedDisplayName = normalizedDisplayName.isEmpty
            ? L10n.choose(simplifiedChinese: "未命名账号", english: "Unnamed Account")
            : normalizedDisplayName

        let changed = currentAccountID != normalizedID
        currentAccountID = normalizedID
        currentAccountDisplayName = resolvedDisplayName
        selectedAthletePanelID = AthletePanel.singleID
        clearClientLogs()
        lastError = nil
        syncStatus = nil
        configureRepository()
        configureInitialTrainerSessions()

        if changed {
            activities = []
            dailyMealPlans = []
            customFoodLibrary = []
            plannedWorkouts = []
            wellnessSamples = []
            intervalsCalendarEvents = []
            lactateHistoryRecords = []
            activityMetricInsightsCache = [:]
        }
        refreshAthletePanelsAndSelection(preferSpecificSelection: false)
        markDerivedStateDirty()
    }

    private func loadServerEndpointFromDefaults() {
        let defaults = UserDefaults.standard
        let storedHost = defaults.string(forKey: serverHostDefaultsKey)?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let storedHost, !storedHost.isEmpty {
            serverHost = storedHost
        } else {
            serverHost = "127.0.0.1"
        }

        let storedPort = defaults.integer(forKey: serverPortDefaultsKey)
        serverPort = (1...65535).contains(storedPort) ? String(storedPort) : "8080"
    }

    private func appendClientLog(level: String, message: String) {
        let line = "[\(Self.clientLogTimeFormatter.string(from: Date()))] [\(level)] \(message)"
        clientLogLines.append(line)
        if clientLogLines.count > 300 {
            clientLogLines.removeFirst(clientLogLines.count - 300)
        }
    }

    func clearClientLogs() {
        clientLogLines = []
    }

    /// Persists `Data` to `UserDefaults` only when bytes change.
    /// - Parameters:
    ///   - data: Encoded payload to persist.
    ///   - key: Target `UserDefaults` key.
    /// - Returns: `true` if the value changed and was written, otherwise `false`.
    private func saveDefaultsDataIfChanged(_ data: Data, forKey key: String) -> Bool {
        let defaults = UserDefaults.standard
        if let existing = defaults.data(forKey: key), existing == data {
            return false
        }
        defaults.set(data, forKey: key)
        return true
    }

    private func hashDataFNV1a64(_ data: Data) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in data {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        return hash
    }

    private func detailedErrorDescription(_ error: Error) -> String {
        let nsError = error as NSError
        let domain = nsError.domain
        let code = nsError.code
        let message = nsError.localizedDescription
        if let failingURL = nsError.userInfo[NSURLErrorFailingURLStringErrorKey] as? String {
            return "\(message) [domain=\(domain) code=\(code) url=\(failingURL)]"
        }
        return "\(message) [domain=\(domain) code=\(code)]"
    }

    private var resolvedServerEndpointText: String {
        let host = serverHost.trimmingCharacters(in: .whitespacesAndNewlines)
        let port = serverPort.trimmingCharacters(in: .whitespacesAndNewlines)
        if host.isEmpty || port.isEmpty {
            return "-"
        }
        return "http://\(host):\(port)"
    }

    private func localActivitiesCacheCount(for accountID: String) -> Int {
        do {
            let url = try Self.activitiesLocalCacheURL(for: accountID, createDirectory: false)
            guard FileManager.default.fileExists(atPath: url.path) else {
                return 0
            }
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let rows = try decoder.decode([Activity].self, from: data)
            return rows.count
        } catch {
            appendClientLog(
                level: "WARN",
                message: "Failed to read local activity cache count for diagnostics: \(detailedErrorDescription(error))"
            )
            return 0
        }
    }

    func refreshActivityRecoveryDiagnostics() {
        activityRecoveryDiagnosticsRefreshGeneration &+= 1
        let generation = activityRecoveryDiagnosticsRefreshGeneration
        let snapshotAccountID = currentAccountID
        let snapshotEndpoint = resolvedServerEndpointText
        let appLocalCacheCount = localActivitiesCacheCount(for: snapshotAccountID)

        activityRecoveryDiagnostics = ActivityRecoveryDiagnosticsSnapshot(
            accountID: snapshotAccountID,
            serverEndpoint: snapshotEndpoint,
            remoteCount: nil,
            localCacheCount: appLocalCacheCount,
            repositoryLocalCacheCount: 0,
            remoteError: nil,
            isLoading: true,
            updatedAt: nil
        )

        guard let remoteRepository = repository as? RemoteHTTPRepository else {
            activityRecoveryDiagnostics = ActivityRecoveryDiagnosticsSnapshot(
                accountID: snapshotAccountID,
                serverEndpoint: snapshotEndpoint,
                remoteCount: nil,
                localCacheCount: appLocalCacheCount,
                repositoryLocalCacheCount: 0,
                remoteError: "Repository unavailable",
                isLoading: false,
                updatedAt: Date()
            )
            return
        }

        DispatchQueue.global(qos: .utility).async { [weak self] in
            let repositoryDiagnostics = remoteRepository.activityRecoveryDiagnostics()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                guard generation == self.activityRecoveryDiagnosticsRefreshGeneration else { return }
                let latestLocalCount = self.localActivitiesCacheCount(for: snapshotAccountID)
                self.activityRecoveryDiagnostics = ActivityRecoveryDiagnosticsSnapshot(
                    accountID: snapshotAccountID,
                    serverEndpoint: repositoryDiagnostics.endpoint,
                    remoteCount: repositoryDiagnostics.remoteCount,
                    localCacheCount: latestLocalCount,
                    repositoryLocalCacheCount: repositoryDiagnostics.localCacheCount,
                    remoteError: repositoryDiagnostics.remoteError,
                    isLoading: false,
                    updatedAt: Date()
                )
            }
        }
    }

    private func currentAppSettingsSnapshot() -> AppSettingsSnapshot {
        let defaults = UserDefaults.standard
        let normalizedHost = defaults.string(forKey: serverHostDefaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let snapshotHost: String?
        if let normalizedHost, !normalizedHost.isEmpty {
            snapshotHost = normalizedHost
        } else {
            let fallback = serverHost.trimmingCharacters(in: .whitespacesAndNewlines)
            snapshotHost = fallback.isEmpty ? nil : fallback
        }

        let storedPort = defaults.integer(forKey: serverPortDefaultsKey)
        let snapshotPort: Int?
        if (1...65535).contains(storedPort) {
            snapshotPort = storedPort
        } else if let parsedPort = Int(serverPort.trimmingCharacters(in: .whitespacesAndNewlines)),
                  (1...65535).contains(parsedPort) {
            snapshotPort = parsedPort
        } else {
            snapshotPort = nil
        }

        let rawServerBaseURL = defaults.string(forKey: RemoteHTTPRepository.serverURLDefaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let snapshotBaseURL = (rawServerBaseURL?.isEmpty == false) ? rawServerBaseURL : nil
        let stravaPullRecentDays = defaults.integer(forKey: stravaPullRecentDaysDefaultsKey)
        let snapshotStravaPullRecentDays: Int?
        if stravaPullRecentDays > 0 {
            snapshotStravaPullRecentDays = stravaPullRecentDays
        } else {
            snapshotStravaPullRecentDays = nil
        }

        return AppSettingsSnapshot(
            trainerRiderConnectionStoreData: defaults.data(forKey: trainerRiderConnectionStoreDefaultsKey),
            appLanguageRawValue: defaults.string(forKey: AppLanguageOption.storageKey),
            chartDisplayModeRawValue: defaults.string(forKey: AppChartDisplayMode.storageKey),
            chartDisplayModesByStorageKey: currentPerChartDisplayModeSnapshot(defaults: defaults),
            nutritionUSDAAPIKey: defaults.string(forKey: nutritionUSDAAPIKeyDefaultsKey),
            stravaPullRecentDays: snapshotStravaPullRecentDays,
            serverHost: snapshotHost,
            serverPort: snapshotPort,
            serverBaseURL: snapshotBaseURL
        )
    }

    private func applyAppSettingsSnapshot(_ snapshot: AppSettingsSnapshot) {
        let defaults = UserDefaults.standard
        isApplyingServerBackedSettings = true
        defer { isApplyingServerBackedSettings = false }

        var shouldReconfigureEndpoint = false
        var shouldReloadTrainerSessions = false

        if let data = snapshot.trainerRiderConnectionStoreData {
            defaults.set(data, forKey: trainerRiderConnectionStoreDefaultsKey)
            shouldReloadTrainerSessions = true
        }
        if let appLanguageRawValue = snapshot.appLanguageRawValue {
            defaults.set(appLanguageRawValue, forKey: AppLanguageOption.storageKey)
        }
        if let chartDisplayModeRawValue = snapshot.chartDisplayModeRawValue {
            defaults.set(chartDisplayModeRawValue, forKey: AppChartDisplayMode.storageKey)
        }
        if let chartDisplayModesByStorageKey = snapshot.chartDisplayModesByStorageKey {
            applyPerChartDisplayModeSnapshot(chartDisplayModesByStorageKey, defaults: defaults)
        }
        if let nutritionUSDAAPIKey = snapshot.nutritionUSDAAPIKey {
            defaults.set(nutritionUSDAAPIKey, forKey: nutritionUSDAAPIKeyDefaultsKey)
        }
        if let stravaPullRecentDays = snapshot.stravaPullRecentDays, stravaPullRecentDays > 0 {
            defaults.set(stravaPullRecentDays, forKey: stravaPullRecentDaysDefaultsKey)
        }
        if let serverBaseURL = snapshot.serverBaseURL,
           !serverBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            defaults.set(serverBaseURL, forKey: RemoteHTTPRepository.serverURLDefaultsKey)
        }

        if let host = snapshot.serverHost?.trimmingCharacters(in: .whitespacesAndNewlines),
           !host.isEmpty {
            if host != serverHost {
                shouldReconfigureEndpoint = true
            }
            serverHost = host
            defaults.set(host, forKey: serverHostDefaultsKey)
        }
        if let port = snapshot.serverPort, (1...65535).contains(port) {
            let nextPort = String(port)
            if nextPort != serverPort {
                shouldReconfigureEndpoint = true
            }
            serverPort = nextPort
            defaults.set(port, forKey: serverPortDefaultsKey)
        }

        if shouldReloadTrainerSessions {
            configureInitialTrainerSessions()
        }
        if shouldReconfigureEndpoint {
            configureRepository()
        }
    }

    private func currentPerChartDisplayModeSnapshot(defaults: UserDefaults) -> [String: String]? {
        let entries = defaults.dictionaryRepresentation().reduce(into: [String: String]()) { partial, entry in
            guard PersistedChartDisplayModeKeys.isPersistedKey(entry.key) else { return }
            guard let rawValue = entry.value as? String, !rawValue.isEmpty else { return }
            partial[entry.key] = rawValue
        }
        return entries.isEmpty ? nil : entries
    }

    private func applyPerChartDisplayModeSnapshot(_ snapshot: [String: String], defaults: UserDefaults) {
        let existingKeys = defaults.dictionaryRepresentation().keys.filter(PersistedChartDisplayModeKeys.isPersistedKey)
        for key in existingKeys {
            defaults.removeObject(forKey: key)
        }
        for (key, rawValue) in snapshot where PersistedChartDisplayModeKeys.isPersistedKey(key) && !rawValue.isEmpty {
            defaults.set(rawValue, forKey: key)
        }
    }

    private func hydrateAppSettingsFromRepository() {
        guard !isAnonymousAccount else { return }
        guard let repository else { return }
        do {
            if let serverSettings = try repository.loadAppSettings(), !serverSettings.isEmpty {
                applyAppSettingsSnapshot(serverSettings)
                let payloadBytes = (try? JSONEncoder().encode(serverSettings).count) ?? 0
                appendClientLog(
                    level: "INFO",
                    message: "Loaded app settings from server (bytes=\(payloadBytes), host=\(serverSettings.serverHost ?? "-"), port=\(serverSettings.serverPort.map(String.init) ?? "-"))."
                )
            } else {
                appendClientLog(level: "INFO", message: "Server app settings empty. Seeding from local settings...")
                persistAppSettingsToRepository(reason: "seedRemoteSettingsOnEmpty")
            }
        } catch RepositoryError.httpError(404) {
            // Older servers may not support app_settings yet.
            appendClientLog(level: "WARN", message: "Server does not support app_settings endpoint (HTTP 404).")
        } catch {
            appendClientLog(
                level: "ERROR",
                message: "App settings hydrate failed: \(detailedErrorDescription(error))"
            )
            lastError = "Failed to sync app settings: \(error.localizedDescription)"
        }
    }

    private func persistAppSettingsToRepository(reason: String = "unspecified") {
        guard !isAnonymousAccount else { return }
        guard !isApplyingServerBackedSettings else {
            appendClientLog(level: "INFO", message: "Skip app settings sync (\(reason)): applying server-backed settings.")
            return
        }
        guard let repository else {
            appendClientLog(level: "WARN", message: "Skip app settings sync (\(reason)): repository unavailable.")
            return
        }

        let snapshot = currentAppSettingsSnapshot()
        guard let payload = try? JSONEncoder().encode(snapshot) else {
            appendClientLog(level: "ERROR", message: "Failed to encode app settings payload (\(reason)).")
            return
        }
        let digest = hashDataFNV1a64(payload)
        let digestText = String(format: "%016llx", digest)

        if lastAppSettingsSyncedDigest == digest {
            appendClientLog(level: "INFO", message: "Skip app settings sync (\(reason)): payload unchanged [\(digestText)].")
            return
        }

        if lastAppSettingsFailedDigest == digest,
           let failedAt = lastAppSettingsFailedAt,
           Date().timeIntervalSince(failedAt) < 8 {
            appendClientLog(
                level: "WARN",
                message: "Skip app settings retry (\(reason)): same payload failed recently [\(digestText)]."
            )
            return
        }

        appendClientLog(
            level: "INFO",
            message: "Syncing app settings (\(reason)) bytes=\(payload.count) digest=\(digestText) host=\(snapshot.serverHost ?? "-") port=\(snapshot.serverPort.map(String.init) ?? "-") baseURL=\(snapshot.serverBaseURL ?? "-")."
        )

        do {
            try repository.saveAppSettings(snapshot)
            lastAppSettingsSyncedDigest = digest
            lastAppSettingsFailedDigest = nil
            lastAppSettingsFailedAt = nil
            appendClientLog(level: "INFO", message: "App settings sync succeeded (\(reason)) [\(digestText)].")
        } catch RepositoryError.httpError(404) {
            // Older servers may not support app_settings yet.
            appendClientLog(level: "WARN", message: "Skip saving app settings: server endpoint unavailable (HTTP 404).")
        } catch {
            lastAppSettingsFailedDigest = digest
            lastAppSettingsFailedAt = Date()
            appendClientLog(
                level: "ERROR",
                message: "App settings sync failed (\(reason)) [\(digestText)]: \(detailedErrorDescription(error))"
            )
            lastError = "Failed to save app settings: \(error.localizedDescription)"
        }
    }

    private func configureRepository() {
        do {
            let host = serverHost.trimmingCharacters(in: .whitespacesAndNewlines)
            let port = serverPort.trimmingCharacters(in: .whitespacesAndNewlines)
            let base = "http://\(host):\(port)"
            guard let url = URL(string: base) else {
                throw RepositoryError.invalidServerURL
            }
            self.repository = try RemoteHTTPRepository(
                baseURL: url,
                accountID: currentAccountID
            )
            appendClientLog(
                level: "INFO",
                message: "Configured server repository: \(base) account=\(currentAccountID)"
            )
            refreshActivityRecoveryDiagnostics()
        } catch {
            self.repository = nil
            self.lastError = "Failed to initialize repository: \(error.localizedDescription)"
            self.activityRecoveryDiagnostics = ActivityRecoveryDiagnosticsSnapshot(
                accountID: currentAccountID,
                serverEndpoint: resolvedServerEndpointText,
                remoteCount: nil,
                localCacheCount: localActivitiesCacheCount(for: currentAccountID),
                repositoryLocalCacheCount: 0,
                remoteError: detailedErrorDescription(error),
                isLoading: false,
                updatedAt: Date()
            )
        }
    }

    func updateServerEndpoint(host: String, port: String) {
        let normalizedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPort = port.trimmingCharacters(in: .whitespacesAndNewlines)
        appendClientLog(level: "INFO", message: "Applying server endpoint: \(normalizedHost):\(normalizedPort)")
        guard !normalizedHost.isEmpty,
              let parsedPort = Int(normalizedPort),
              (1...65535).contains(parsedPort) else {
            lastError = "Invalid server host or port"
            return
        }

        serverHost = normalizedHost
        serverPort = String(parsedPort)
        UserDefaults.standard.set(normalizedHost, forKey: serverHostDefaultsKey)
        UserDefaults.standard.set(parsedPort, forKey: serverPortDefaultsKey)
        configureRepository()
        persistAppSettingsToRepository(reason: "updateServerEndpoint")
        bootstrap()
        syncStatus = "Server endpoint updated to \(normalizedHost):\(parsedPort)"
    }

    private func configureInitialTrainerSessions() {
        let restoredStore = loadTrainerRiderConnectionStore()
        let restoredRiders = (restoredStore?.riders ?? [])
            .filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let preferredPrimaryID = resolvedPrimarySessionID(in: restoredRiders, preferred: restoredStore?.primarySessionID)
        var primary = restoredRiders.first(where: { $0.id == preferredPrimaryID }) ?? restoredRiders.first ?? TrainerRiderConnectionMemory(
            id: UUID(),
            name: currentAccountDisplayName,
            preferredTrainerDeviceID: nil,
            preferredTrainerDeviceName: nil,
            preferredHeartRateDeviceID: nil,
            preferredPowerMeterDeviceID: nil,
            appearance: .default
        )
        primary.name = canonicalCurrentAccountAthleteName

        trainerRiderConnectionMemoryBySessionID = [primary.id: primary]
        trainerRiderSessions = [makeTrainerRiderSession(from: primary, useSharedManagers: true)]
        primaryTrainerSessionID = primary.id

        trainerRecordingStatusBySession = Dictionary(
            uniqueKeysWithValues: trainerRiderSessions.map { ($0.id, TrainerRecordingStatus()) }
        )
        refreshPrimaryTrainerRecordingSnapshot()
        setupTrainerRecordingPipeline()
        persistTrainerRiderConnectionStore()
    }

    private func makeTrainerRiderSession(
        from memory: TrainerRiderConnectionMemory,
        useSharedManagers: Bool
    ) -> TrainerRiderSession {
        let session = TrainerRiderSession(
            id: memory.id,
            name: memory.name,
            trainer: useSharedManagers ? trainer : SmartTrainerManager(),
            heartRateMonitor: useSharedManagers ? heartRateMonitor : HeartRateMonitorManager(),
            powerMeter: useSharedManagers ? powerMeter : PowerMeterManager(),
            supportsRecording: true
        )
        applyDevicePreferences(memory: memory, to: session)
        installConnectionPersistenceCallbacks(for: session)
        return session
    }

    private func applyDevicePreferences(memory: TrainerRiderConnectionMemory, to session: TrainerRiderSession) {
        session.trainer.setPreferredAutoConnectDeviceID(memory.preferredTrainerDeviceID)
        session.trainer.setPreferredAutoConnectDeviceName(memory.preferredTrainerDeviceName)
        session.heartRateMonitor.setPreferredAutoConnectDeviceID(memory.preferredHeartRateDeviceID)
        session.powerMeter.setPreferredAutoConnectDeviceID(memory.preferredPowerMeterDeviceID)
    }

    private func installConnectionPersistenceCallbacks(for session: TrainerRiderSession) {
        let sessionID = session.id
        session.trainer.onConnectedDeviceChanged = { [weak self] deviceID, deviceName in
            Task { @MainActor in
                self?.rememberConnectedTrainerDevice(sessionID: sessionID, deviceID: deviceID, deviceName: deviceName)
            }
        }
        session.heartRateMonitor.onConnectedDeviceChanged = { [weak self] deviceID, _ in
            Task { @MainActor in
                self?.rememberConnectedHeartRateDevice(sessionID: sessionID, deviceID: deviceID)
            }
        }
        session.powerMeter.onConnectedDeviceChanged = { [weak self] deviceID, _ in
            Task { @MainActor in
                self?.rememberConnectedPowerMeterDevice(sessionID: sessionID, deviceID: deviceID)
            }
        }
    }

    private func resolvedPrimarySessionID(
        in riders: [TrainerRiderConnectionMemory],
        preferred: UUID?
    ) -> UUID {
        if let preferred, riders.contains(where: { $0.id == preferred }) {
            return preferred
        }
        return riders.first?.id ?? UUID()
    }

    private func loadTrainerRiderConnectionStore() -> TrainerRiderConnectionStore? {
        guard let data = UserDefaults.standard.data(forKey: trainerRiderConnectionStoreDefaultsKey) else {
            return nil
        }
        do {
            return try JSONDecoder().decode(TrainerRiderConnectionStore.self, from: data)
        } catch {
            lastError = "Failed to load saved rider devices: \(error.localizedDescription)"
            return nil
        }
    }

    private func persistTrainerRiderConnectionStore() {
        guard let session = trainerRiderSessions.first else {
            return
        }
        var memory = trainerRiderConnectionMemoryBySessionID[session.id]
            ?? TrainerRiderConnectionMemory(
                id: session.id,
                name: session.name,
                preferredTrainerDeviceID: nil,
                preferredTrainerDeviceName: nil,
                preferredHeartRateDeviceID: nil,
                preferredPowerMeterDeviceID: nil,
                appearance: .default
            )
        memory.name = canonicalCurrentAccountAthleteName
        if memory.appearance == nil {
            memory.appearance = .default
        }
        trainerRiderConnectionMemoryBySessionID = [session.id: memory]
        let riders = [memory]
        let payload = TrainerRiderConnectionStore(primarySessionID: primaryTrainerSessionID, riders: riders)
        do {
            let data = try JSONEncoder().encode(payload)
            guard saveDefaultsDataIfChanged(data, forKey: trainerRiderConnectionStoreDefaultsKey) else {
                return
            }
            persistAppSettingsToRepository(reason: "persistTrainerRiderConnectionStore")
        } catch {
            lastError = "Failed to save rider devices: \(error.localizedDescription)"
        }
    }

    private func baseConnectionMemory(for sessionID: UUID) -> TrainerRiderConnectionMemory {
        if let existing = trainerRiderConnectionMemoryBySessionID[sessionID] {
            return existing
        }
        let fallbackName = trainerRiderSession(id: sessionID)?.name ?? "Athlete"
        return TrainerRiderConnectionMemory(
            id: sessionID,
            name: fallbackName,
            preferredTrainerDeviceID: nil,
            preferredTrainerDeviceName: nil,
            preferredHeartRateDeviceID: nil,
            preferredPowerMeterDeviceID: nil,
            appearance: .default
        )
    }

    private func rememberConnectedTrainerDevice(sessionID: UUID, deviceID: UUID, deviceName: String?) {
        var memory = baseConnectionMemory(for: sessionID)
        memory.name = trainerRiderSession(id: sessionID)?.name ?? memory.name
        memory.preferredTrainerDeviceID = deviceID
        if let normalizedName = normalizedNonEmptyString(deviceName) {
            memory.preferredTrainerDeviceName = normalizedName
        }
        trainerRiderConnectionMemoryBySessionID[sessionID] = memory
        persistTrainerRiderConnectionStore()
    }

    private func rememberConnectedHeartRateDevice(sessionID: UUID, deviceID: UUID) {
        var memory = baseConnectionMemory(for: sessionID)
        memory.name = trainerRiderSession(id: sessionID)?.name ?? memory.name
        memory.preferredHeartRateDeviceID = deviceID
        trainerRiderConnectionMemoryBySessionID[sessionID] = memory
        persistTrainerRiderConnectionStore()
    }

    private func rememberConnectedPowerMeterDevice(sessionID: UUID, deviceID: UUID) {
        var memory = baseConnectionMemory(for: sessionID)
        memory.name = trainerRiderSession(id: sessionID)?.name ?? memory.name
        memory.preferredPowerMeterDeviceID = deviceID
        trainerRiderConnectionMemoryBySessionID[sessionID] = memory
        persistTrainerRiderConnectionStore()
    }

    func ensureTrainerRiderAutoReconnect() {
        guard let session = trainerRiderSessions.first else { return }
        session.trainer.startAutoConnectIfPossible()
        session.heartRateMonitor.startAutoConnectIfPossible()
        session.powerMeter.startAutoConnectIfPossible()
    }

    func trainerRiderAppearance(for sessionID: UUID) -> TrainerRiderAppearance {
        trainerRiderConnectionMemoryBySessionID[sessionID]?.appearance ?? .default
    }

    func updateTrainerRiderAppearance(for sessionID: UUID, appearance: TrainerRiderAppearance) {
        var memory = baseConnectionMemory(for: sessionID)
        memory.name = trainerRiderSession(id: sessionID)?.name ?? memory.name
        memory.appearance = appearance
        trainerRiderConnectionMemoryBySessionID[sessionID] = memory
        persistTrainerRiderConnectionStore()
    }

    private func trainerRiderSession(id: UUID) -> TrainerRiderSession? {
        trainerRiderSessions.first { $0.id == id }
    }

    func trainerRecordingStatus(for sessionID: UUID) -> TrainerRecordingStatus {
        trainerRecordingStatusBySession[sessionID] ?? TrainerRecordingStatus()
    }

    private func updateTrainerRecordingStatus(_ status: TrainerRecordingStatus, for sessionID: UUID) {
        var next = trainerRecordingStatusBySession
        next[sessionID] = status
        trainerRecordingStatusBySession = next
        refreshPrimaryTrainerRecordingSnapshot()
    }

    private func refreshPrimaryTrainerRecordingSnapshot() {
        guard let primaryID = primaryTrainerSessionID else {
            trainerRecordingIsActive = false
            trainerRecordingElapsedSec = 0
            trainerRecordingMovingSec = 0
            trainerRecordingSampleCount = 0
            trainerRecordingElevationGainMeters = 0
            trainerRecordingLastFitPath = nil
            trainerRecordingLastSyncSummary = nil
            return
        }
        let status = trainerRecordingStatus(for: primaryID)
        trainerRecordingIsActive = status.isActive
        trainerRecordingElapsedSec = status.elapsedSec
        trainerRecordingMovingSec = status.movingSec
        trainerRecordingSampleCount = status.sampleCount
        trainerRecordingElevationGainMeters = status.elevationGainMeters
        trainerRecordingLastFitPath = status.lastFitPath
        trainerRecordingLastSyncSummary = status.lastSyncSummary
    }

    private func cacheProfileForSelectedAthlete() {
        persistAppSettingsToRepository(reason: "profileChanged")
    }

    private func applySelectedAthleteProfileIfNeeded() {
        // Single-athlete mode: profile is account-scoped.
    }

    private func refreshAthletePanelsAndSelection(preferSpecificSelection: Bool) {
        _ = preferSpecificSelection
        if selectedAthletePanelID != AthletePanel.singleID {
            selectedAthletePanelID = AthletePanel.singleID
        }
    }

    func bootstrap() {
        do {
            let startedAt = Date()
            appendClientLog(level: "INFO", message: "Bootstrap started: loading settings and repository data.")
            hydrateAppSettingsFromRepository()
            var loadedProfile: AthleteProfile = .default
                if let repository {
                    do {
                        try repository.flushPendingWrites()
                        appendClientLog(level: "INFO", message: "Flushed pending remote writes before bootstrap load.")
                    } catch {
                        appendClientLog(level: "WARN", message: "Failed to flush pending remote writes: \(detailedErrorDescription(error))")
                    }
                    do {
                        self.activities = try repository.loadActivities()
                    } catch {
                        appendClientLog(
                            level: "WARN",
                            message: "Failed to load remote activities: \(detailedErrorDescription(error))"
                        )
                        if let cached = loadActivitiesFromLocalCache(), !cached.isEmpty {
                            self.activities = deduplicateActivities(cached)
                            appendClientLog(
                                level: "WARN",
                                message: "Recovered \(self.activities.count) activities from local cache after remote load failure."
                            )
                        } else {
                            throw error
                        }
                    }
                    if self.activities.isEmpty,
                       let cached = loadActivitiesFromLocalCache(),
                       !cached.isEmpty {
                        self.activities = deduplicateActivities(cached)
                        appendClientLog(
                            level: "WARN",
                            message: "Remote activities empty. Restored \(self.activities.count) activities from local cache."
                        )
                        do {
                            try repository.saveActivities(self.activities)
                            appendClientLog(
                                level: "INFO",
                                message: "Rehydrated remote activities from local cache (\(self.activities.count))."
                            )
                        } catch {
                            appendClientLog(
                                level: "WARN",
                                message: "Failed to rehydrate remote activities: \(detailedErrorDescription(error))"
                            )
                        }
                    }
                    if self.activities.isEmpty {
                        appendClientLog(
                            level: "WARN",
                            message: "Remote activities empty for account=\(currentAccountID). If server should have data, verify login account/session matches stored account scope."
                        )
                    }
                    self.activities = deduplicateActivities(self.activities)
                    persistActivitiesToLocalCache(self.activities)
                    self.dailyMealPlans = try repository.loadDailyMealPlans()
                    self.customFoodLibrary = try repository.loadCustomFoods()
                    self.plannedWorkouts = try repository.loadWorkouts()
                    self.wellnessSamples = try repository.loadWellnessSamples()
                    self.intervalsCalendarEvents = try repository.loadCalendarEvents()
                self.lactateHistoryRecords = try repository.loadLactateHistoryRecords()
                loadedProfile = try repository.loadProfile()
                self.activityMetricInsightsCache = Dictionary(
                    uniqueKeysWithValues: try repository.loadActivityMetricInsights().map { ($0.activityID, $0) }
                )
            } else {
                self.activities = DemoDataFactory.generateActivities(days: 120)
                self.dailyMealPlans = []
                self.customFoodLibrary = []
                self.plannedWorkouts = []
                self.wellnessSamples = []
                self.intervalsCalendarEvents = []
                self.lactateHistoryRecords = []
                loadedProfile = .default
                self.activityMetricInsightsCache = [:]
            }

            self.profile = loadedProfile
            refreshAthletePanelsAndSelection(preferSpecificSelection: true)
            applySelectedAthleteProfileIfNeeded()
            pruneActivityMetricInsights()
            applyDefaultCredentialsIfNeeded()
            ensureTrainerRiderAutoReconnect()
            let elapsedText = String(format: "%.2f", Date().timeIntervalSince(startedAt))
            appendClientLog(
                level: "INFO",
                message: "Bootstrap complete in \(elapsedText)s (activities \(activities.count), workouts \(plannedWorkouts.count), wellness \(wellnessSamples.count))."
            )
            refreshActivityRecoveryDiagnostics()
        } catch {
            self.lastError = "Failed to load server data: \(error.localizedDescription)"
            refreshActivityRecoveryDiagnostics()
        }
    }

    func addLactateHistoryRecord(type: LactateTestType, points: [LactateSamplePoint]) {
        let name = selectedAthleteNameForWrite.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !points.isEmpty else { return }
        let record = LactateHistoryRecord(tester: name, type: type, createdAt: .now, points: points)
        var updated = lactateHistoryRecords
        updated.append(record)
        updated.sort { $0.createdAt > $1.createdAt }
        lactateHistoryRecords = updated
        do {
            if let repository {
                try repository.saveLactateHistoryRecords(updated)
            }
        } catch {
            lastError = "Failed to save lactate history record: \(error.localizedDescription)"
        }
    }

    func deleteLactateHistoryRecord(recordID: UUID) {
        let updated = lactateHistoryRecords.filter { $0.id != recordID }
        guard updated.count != lactateHistoryRecords.count else { return }
        lactateHistoryRecords = updated
        do {
            if let repository {
                try repository.saveLactateHistoryRecords(updated)
            }
        } catch {
            lastError = "Failed to delete lactate history record: \(error.localizedDescription)"
        }
    }

    var filteredActivities: [Activity] {
        filteredActivitiesCache
    }

    var athleteScopedActivities: [Activity] {
        athleteScopedActivitiesCache
    }

    var athleteScopedDailyMealPlans: [DailyMealPlan] {
        athleteScopedDailyMealPlansCache
    }

    var athleteScopedPlannedWorkouts: [PlannedWorkout] {
        athleteScopedPlannedWorkoutsCache
    }

    var athleteScopedWellnessSamples: [WellnessSample] {
        athleteScopedWellnessSamplesCache
    }

    var athleteScopedCalendarEvents: [CalendarEvent] {
        athleteScopedCalendarEventsCache
    }

    var trainerRiderSessionsForSelectedAthlete: [TrainerRiderSession] {
        guard let primaryID = primaryTrainerSessionID,
              let session = trainerRiderSessions.first(where: { $0.id == primaryID }) else {
            return trainerRiderSessions.isEmpty ? [] : [trainerRiderSessions[0]]
        }
        return [session]
    }

    var selectedAthleteTitle: String {
        canonicalCurrentAccountAthleteName
    }

    var selectedAthleteNameForWrite: String {
        canonicalCurrentAccountAthleteName
    }

    var selectedAthleteNameForFilter: String? {
        canonicalCurrentAccountAthleteName
    }

    func profileForAthlete(named athleteName: String?) -> AthleteProfile {
        _ = athleteName
        return profile
    }

    func activitiesForAthlete(named athleteName: String?) -> [Activity] {
        guard let athleteName = normalizedNonEmptyString(athleteName) else {
            return activities.sorted { $0.date > $1.date }
        }
        let panelID = athletePanelID(forName: athleteName)
        return activities
            .filter { athletePanelID(for: $0) == panelID }
            .sorted { $0.date > $1.date }
    }

    func workoutsForAthlete(named athleteName: String?) -> [PlannedWorkout] {
        guard let athleteName = normalizedNonEmptyString(athleteName) else {
            return plannedWorkouts.sorted { $0.createdAt > $1.createdAt }
        }
        let panelID = athletePanelID(forName: athleteName)
        return plannedWorkouts
            .filter { athletePanelID(forName: $0.athleteName) == panelID }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func mealPlansForAthlete(named athleteName: String?) -> [DailyMealPlan] {
        guard let athleteName = normalizedNonEmptyString(athleteName) else {
            return dailyMealPlans.sorted { $0.date > $1.date }
        }
        let panelID = athletePanelID(forName: athleteName)
        return dailyMealPlans
            .filter { athletePanelID(forName: $0.athleteName) == panelID }
            .sorted { $0.date > $1.date }
    }

    func wellnessSamplesForAthlete(named athleteName: String?) -> [WellnessSample] {
        guard let athleteName = normalizedNonEmptyString(athleteName) else {
            return wellnessSamples.sorted { $0.date > $1.date }
        }
        let panelID = athletePanelID(forName: athleteName)
        return wellnessSamples
            .filter { athletePanelID(forName: $0.athleteName) == panelID }
            .sorted { $0.date > $1.date }
    }

    func dailyMealPlanForSelectedAthlete(on date: Date) -> DailyMealPlan? {
        let day = Calendar.current.startOfDay(for: date)
        return athleteScopedDailyMealPlansCache.first {
            Calendar.current.isDate($0.date, inSameDayAs: day)
        }
    }

    func saveDailyMealPlanForSelectedAthlete(_ plan: DailyMealPlan) {
        var normalized = plan
        normalized.date = Calendar.current.startOfDay(for: plan.date)
        normalized.athleteName = selectedAthleteNameForWrite
        if normalized.items.isEmpty {
            normalized.items = DailyMealPlan.defaultTemplateItems()
        }

        var updated = dailyMealPlans.filter { row in
            !(athletePanelID(forName: row.athleteName) == athletePanelID(forName: normalized.athleteName)
                && Calendar.current.isDate(row.date, inSameDayAs: normalized.date))
        }
        updated.append(normalized)
        updated.sort { $0.date > $1.date }

        do {
            try persistDailyMealPlans(updated)
            syncStatus = L10n.choose(
                simplifiedChinese: "已保存 \(selectedAthleteTitle) 的饮食记录（\(normalized.date.formatted(date: .abbreviated, time: .omitted))）",
                english: "Saved nutrition log for \(selectedAthleteTitle) (\(normalized.date.formatted(date: .abbreviated, time: .omitted)))."
            )
        } catch {
            lastError = "Failed to save meal plan: \(error.localizedDescription)"
        }
    }

    @discardableResult
    func copyDailyMealPlanTemplateForSelectedAthlete(from sourceDate: Date, to targetDate: Date) -> DailyMealPlan? {
        let sourceDay = Calendar.current.startOfDay(for: sourceDate)
        let targetDay = Calendar.current.startOfDay(for: targetDate)
        guard sourceDay != targetDay else { return dailyMealPlanForSelectedAthlete(on: targetDay) }

        guard var copied = dailyMealPlanForSelectedAthlete(on: sourceDay) else {
            return nil
        }
        copied.id = UUID()
        copied.date = targetDay
        copied.athleteName = selectedAthleteNameForWrite
        saveDailyMealPlanForSelectedAthlete(copied)
        return copied
    }

    var allNutritionFoodLibraryItems: [FoodLibraryItem] {
        FoodLibraryItem.commonLibrary + customFoodLibrary.map { $0.asFoodLibraryItem() }
    }

    func upsertCustomNutritionFood(_ item: CustomFoodLibraryItem) {
        var updated = customFoodLibrary
        if let existingIndex = updated.firstIndex(where: { $0.id == item.id }) {
            updated[existingIndex] = item
        } else if let barcode = item.barcode?.trimmingCharacters(in: .whitespacesAndNewlines), !barcode.isEmpty,
                  let existingIndex = updated.firstIndex(where: { $0.barcode == barcode }) {
            updated[existingIndex] = item
        } else {
            updated.insert(item, at: 0)
        }
        updated.sort { $0.createdAt > $1.createdAt }
        do {
            try persistCustomFoodLibrary(updated)
            syncStatus = L10n.choose(simplifiedChinese: "已保存自定义食品：\(item.displayName)", english: "Saved custom food: \(item.displayName)")
        } catch {
            lastError = "Failed to save custom food: \(error.localizedDescription)"
        }
    }

    func removeCustomNutritionFood(id: UUID) {
        let updated = customFoodLibrary.filter { $0.id != id }
        do {
            try persistCustomFoodLibrary(updated)
            syncStatus = L10n.choose(simplifiedChinese: "已删除自定义食品", english: "Deleted custom food.")
        } catch {
            lastError = "Failed to delete custom food: \(error.localizedDescription)"
        }
    }

    func customFoodByBarcode(_ barcode: String) -> CustomFoodLibraryItem? {
        let normalized = barcode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        return customFoodLibrary.first(where: { $0.barcode == normalized })
    }

    func generateNutritionPlanDraftWithGPT(from source: DailyMealPlan) async throws -> (DailyMealPlan, DailyNutritionPlanPayload) {
        let key = profile.openAIAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            throw OpenAICoachError.missingAPIKey
        }

        var draft = source
        let mealTargets = draft.mainMealTargets
        let dailyTargetKcal = max(
            1,
            mealTargets.reduce(0) { $0 + max(0, $1.calories) }
                + draft.items.filter { ![.breakfast, .lunch, .dinner].contains($0.slot) }.reduce(0) { $0 + max(0, $1.plannedCalories) }
        )
        let fridgeFoods = draft.fridgeItems.map { entry in
            let lookup = FoodLibraryItem.lookup(code: entry.foodCode)
            let customLookup = customFoodLibrary.first(where: { $0.id.uuidString == entry.foodCode })
            return NutritionFoodAvailabilityInput(
                name: entry.foodName,
                servings: max(0.1, entry.servings),
                caloriesPerServing: entry.caloriesPerServing ?? lookup?.calories ?? customLookup?.calories,
                proteinPerServing: entry.proteinPerServing ?? lookup?.protein ?? customLookup?.protein,
                carbsPerServing: entry.carbsPerServing ?? lookup?.carbs ?? customLookup?.carbs,
                fatPerServing: entry.fatPerServing ?? lookup?.fat ?? customLookup?.fat
            )
        }

        let input = DailyNutritionPlannerInput(
            date: IntervalsDateFormatter.day.string(from: Calendar.current.startOfDay(for: draft.date)),
            athleteName: selectedAthleteTitle,
            sportFocus: (selectedSportFilter ?? .cycling).label,
            athleteWeightKg: profile.athleteWeightKg,
            basalMetabolicRateKcal: profile.basalMetabolicRateKcal,
            nutritionActivityFactor: profile.nutritionActivityFactor,
            estimatedMaintenanceCalories: profile.estimatedDailyMaintenanceCalories,
            nutritionGoalProfile: draft.goalProfile.label,
            goalGuidance: draft.goalProfile.guidanceHint,
            dailyCalorieTarget: dailyTargetKcal,
            hydrationTargetLiters: draft.hydrationTargetLiters,
            mealTargets: mealTargets.map {
                NutritionMealTargetInput(
                    slot: $0.slot.rawValue,
                    calories: $0.calories,
                    protein: $0.protein,
                    carbs: $0.carbs,
                    fat: $0.fat
                )
            },
            fridgeFoods: fridgeFoods,
            notes: draft.notes
        )

        let client = OpenAICoachClient(apiKey: key)
        let response = try await client.planDailyNutrition(input: input)
        let suggestionsBySlot = Dictionary(uniqueKeysWithValues: response.meals.map { ($0.slot.lowercased(), $0) })

        for index in draft.items.indices {
            let slot = draft.items[index].slot
            let key = slot.rawValue.lowercased()
            guard let suggestion = suggestionsBySlot[key] else { continue }
            if !suggestion.foods.isEmpty {
                draft.items[index].plannedFood = suggestion.foods.joined(separator: " + ")
            }
            if let calories = suggestion.calories { draft.items[index].plannedCalories = max(0, calories) }
            if let protein = suggestion.protein { draft.items[index].plannedProtein = max(0, protein) }
            if let carbs = suggestion.carbs { draft.items[index].plannedCarbs = max(0, carbs) }
            if let fat = suggestion.fat { draft.items[index].plannedFat = max(0, fat) }
        }

        // Keep a concise generation summary in notes without erasing manual notes.
        let summaryLines = ([response.summary] + response.notes).map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }
        if !summaryLines.isEmpty {
            let header = L10n.choose(simplifiedChinese: "GPT 饮食计划建议", english: "GPT Nutrition Plan")
            let generatedNote = ([header + ":", summaryLines.joined(separator: "\n• ")]).joined(separator: "\n• ")
            let base = draft.notes.trimmingCharacters(in: .whitespacesAndNewlines)
            draft.notes = base.isEmpty ? generatedNote : "\(base)\n\n\(generatedNote)"
        }

        return (draft, response)
    }

    var loadSeries: [DailyLoadPoint] {
        loadSeriesCache
    }

    var summary: DashboardSummary {
        summaryCache
    }

    var recommendation: AIRecommendation? {
        gptRecommendation
    }

    var metricStories: [MetricStory] {
        metricStoriesCache
    }

    var scenarioMetricPack: ScenarioMetricPack {
        scenarioMetricPackCache
    }

    func activityMetricInsight(for activityID: UUID) -> ActivityMetricInsight? {
        activityMetricInsightsCache[activityID]
    }

    func isRefreshingActivityMetricInsight(for activityID: UUID) -> Bool {
        refreshingActivityInsightIDs.contains(activityID)
    }

    var totalWorkoutMinutes: Int {
        athleteScopedPlannedWorkoutsCache.reduce(0) { $0 + $1.totalMinutes }
    }

    var activitiesCount: Int {
        athleteScopedActivitiesCache.count
    }

    private struct TrainerRecordingSession {
        var startedAt: Date
        var lastSampleAt: Date
        var movingDurationSec: TimeInterval
        var lastCheckpointWriteAt: Date?
        var samples: [LiveRideSample]
        var cumulativeDistanceMeters: Double
        var cumulativeElevationGainMeters: Double
    }

    private struct RideDistanceDelta {
        var elapsedSec: TimeInterval
        var distanceMeters: Double
        var elevationGainMeters: Double
    }

    func persistProfile() {
        cacheProfileForSelectedAthlete()
        do {
            if let repository {
                try repository.saveProfile(profile)
            }
        } catch {
            self.lastError = "Failed to save profile: \(error.localizedDescription)"
        }
    }

    func startTrainerRecordingNow() {
        guard let primaryID = primaryTrainerSessionID else { return }
        startTrainerRecordingNow(for: primaryID)
    }

    func startTrainerRecordingNow(for sessionID: UUID) {
        startTrainerRecording(for: sessionID, reason: "Manual start")
    }

    func stopTrainerRecordingNow() async {
        guard let primaryID = primaryTrainerSessionID else { return }
        await stopTrainerRecordingNow(for: primaryID)
    }

    func stopTrainerRecordingNow(for sessionID: UUID) async {
        await finalizeTrainerRecording(for: sessionID, reason: "Manual stop")
    }

    private func setupTrainerRecordingPipeline() {
        for session in trainerRiderSessions {
            observeTrainerConnection(for: session)
            observeHeartRateConnection(for: session)
            observePowerMeterConnection(for: session)
            observeTrainerPower(for: session)
            observePowerMeterPower(for: session)
        }
    }

    private func emitConnectionDropWarning(
        for session: TrainerRiderSession,
        deviceName: String,
        reconnectAction: @escaping () -> Void
    ) {
        let riderName = session.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? currentAccountDisplayName
            : session.name
        let message = L10n.choose(
            simplifiedChinese: "\(riderName) 的\(deviceName)已断开，正在自动重连。",
            english: "\(deviceName) disconnected for \(riderName). Auto-reconnecting."
        )
        connectionWarningMessage = message
        appendClientLog(level: "WARN", message: message)
        reconnectAction()
    }

    private func observeTrainerConnection(for session: TrainerRiderSession) {
        let sessionID = session.id
        trainerConnectionCancellableBySession[sessionID]?.cancel()
        var previousConnected = session.trainer.isConnected
        trainerConnectionCancellableBySession[sessionID] = session.trainer.$isConnected
            .removeDuplicates()
            .sink { [weak self] connected in
                guard let self else { return }
                defer { previousConnected = connected }
                if !previousConnected && connected {
                    self.connectionWarningMessage = nil
                    self.appendClientLog(level: "INFO", message: "骑行台已恢复连接。")
                }
                if previousConnected && !connected {
                    self.emitConnectionDropWarning(for: session, deviceName: "骑行台") {
                        session.trainer.startAutoConnectIfPossible()
                        if !session.trainer.isConnected && !session.trainer.isScanning {
                            session.trainer.startScan()
                        }
                    }
                }
            }
    }

    private func observeHeartRateConnection(for session: TrainerRiderSession) {
        let sessionID = session.id
        heartRateConnectionCancellableBySession[sessionID]?.cancel()
        var previousConnected = session.heartRateMonitor.isConnected
        heartRateConnectionCancellableBySession[sessionID] = session.heartRateMonitor.$isConnected
            .removeDuplicates()
            .sink { [weak self] connected in
                guard let self else { return }
                defer { previousConnected = connected }
                if !previousConnected && connected {
                    self.connectionWarningMessage = nil
                    self.appendClientLog(level: "INFO", message: "心率带已恢复连接。")
                }
                if previousConnected && !connected {
                    self.emitConnectionDropWarning(for: session, deviceName: "心率带") {
                        session.heartRateMonitor.startAutoConnectIfPossible()
                        if !session.heartRateMonitor.isConnected && !session.heartRateMonitor.isScanning {
                            session.heartRateMonitor.startScan()
                        }
                    }
                }
            }
    }

    private func observePowerMeterConnection(for session: TrainerRiderSession) {
        let sessionID = session.id
        powerMeterConnectionCancellableBySession[sessionID]?.cancel()
        var previousConnected = session.powerMeter.isConnected
        powerMeterConnectionCancellableBySession[sessionID] = session.powerMeter.$isConnected
            .removeDuplicates()
            .sink { [weak self] connected in
                guard let self else { return }
                defer { previousConnected = connected }
                if !previousConnected && connected {
                    self.connectionWarningMessage = nil
                    self.appendClientLog(level: "INFO", message: "功率计已恢复连接。")
                }
                if previousConnected && !connected {
                    self.emitConnectionDropWarning(for: session, deviceName: "功率计") {
                        session.powerMeter.startAutoConnectIfPossible()
                        if !session.powerMeter.isConnected && !session.powerMeter.isScanning {
                            session.powerMeter.startScan()
                        }
                    }
                }
            }
    }

    private func observeTrainerPower(for session: TrainerRiderSession) {
        let sessionID = session.id
        trainerPowerCancellableBySession[sessionID]?.cancel()
        trainerPowerCancellableBySession[sessionID] = session.trainer.$livePowerWatts
            .removeDuplicates()
            .sink { [weak self] watts in
                guard let self else { return }
                guard let watts, watts > 0 else { return }
                self.startTrainerRecording(for: sessionID, reason: "Power detected")
            }
    }

    private func observePowerMeterPower(for session: TrainerRiderSession) {
        let sessionID = session.id
        powerMeterPowerCancellableBySession[sessionID]?.cancel()
        powerMeterPowerCancellableBySession[sessionID] = session.powerMeter.$livePowerWatts
            .removeDuplicates()
            .sink { [weak self] watts in
                guard let self else { return }
                guard let watts, watts > 0 else { return }
                self.startTrainerRecording(for: sessionID, reason: "Power meter detected")
            }
    }

    private func startTrainerRecording(for sessionID: UUID, reason: String) {
        guard let rider = trainerRiderSession(id: sessionID), rider.supportsRecording else { return }
        guard rider.trainer.isConnected else { return }
        guard !trainerRecordingStatus(for: sessionID).isActive else { return }

        trainerRecordingFinalizationTaskBySession[sessionID]?.cancel()
        trainerRecordingFinalizationTaskBySession[sessionID] = nil
        trainerRecordingTimerTaskBySession[sessionID]?.cancel()
        trainerRecordingTimerTaskBySession[sessionID] = nil
        isFinalizingTrainerRecordingBySession.remove(sessionID)

        let now = Date()
        trainerRecordingSessionByRider[sessionID] = TrainerRecordingSession(
            startedAt: now,
            lastSampleAt: now,
            movingDurationSec: 0,
            lastCheckpointWriteAt: nil,
            samples: [],
            cumulativeDistanceMeters: 0,
            cumulativeElevationGainMeters: 0
        )
        removeTrainerRecordingCheckpointFIT(for: sessionID)

        var status = trainerRecordingStatus(for: sessionID)
        status.isActive = true
        status.elapsedSec = 0
        status.movingSec = 0
        status.sampleCount = 0
        status.elevationGainMeters = 0
        status.lastFitPath = nil
        status.lastSyncSummary = "\(reason)。开始记录骑行台数据。"
        updateTrainerRecordingStatus(status, for: sessionID)
        syncStatus = status.lastSyncSummary

        captureTrainerRecordingSample(for: sessionID, at: now)
        trainerRecordingTimerTaskBySession[sessionID] = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                self.captureTrainerRecordingSample(for: sessionID)
            }
        }
    }

    private func trainerDistanceDelta(
        for sessionID: UUID,
        since previousTimestamp: Date,
        to timestamp: Date
    ) -> RideDistanceDelta {
        let dt = max(0, timestamp.timeIntervalSince(previousTimestamp))
        guard dt > 0, let rider = trainerRiderSession(id: sessionID) else {
            return RideDistanceDelta(elapsedSec: 0, distanceMeters: 0, elevationGainMeters: 0)
        }
        guard let speedKPH = rider.trainer.liveSpeedKPH, speedKPH > 0 else {
            return RideDistanceDelta(elapsedSec: dt, distanceMeters: 0, elevationGainMeters: 0)
        }

        let distanceMeters = (speedKPH / 3.6) * dt
        let elevationGainMeters: Double
        if let gradePercent = rider.trainer.targetGradePercent, gradePercent > 0 {
            elevationGainMeters = distanceMeters * (gradePercent / 100.0)
        } else {
            elevationGainMeters = 0
        }
        return RideDistanceDelta(elapsedSec: dt, distanceMeters: distanceMeters, elevationGainMeters: elevationGainMeters)
    }

    private func makeLiveRideSample(
        for sessionID: UUID,
        at timestamp: Date,
        distanceMeters: Double
    ) -> LiveRideSample {
        guard let rider = trainerRiderSession(id: sessionID) else {
            return LiveRideSample(
                timestamp: timestamp,
                powerWatts: nil,
                heartRateBPM: nil,
                cadenceRPM: nil,
                speedKPH: nil,
                distanceMeters: max(0, distanceMeters),
                leftBalancePercent: nil,
                rightBalancePercent: nil
            )
        }
        let sampledPower = rider.trainer.livePowerWatts ?? rider.powerMeter.livePowerWatts
        let effectivePower = sampledPower.flatMap { $0 > 0 ? $0 : nil }
        return LiveRideSample(
            timestamp: timestamp,
            powerWatts: effectivePower,
            heartRateBPM: rider.heartRateMonitor.liveHeartRateBPM,
            cadenceRPM: rider.trainer.liveCadenceRPM ?? rider.powerMeter.liveCadenceRPM,
            speedKPH: rider.trainer.liveSpeedKPH,
            distanceMeters: max(0, distanceMeters),
            leftBalancePercent: rider.powerMeter.liveLeftBalancePercent ?? rider.trainer.liveLeftBalancePercent,
            rightBalancePercent: rider.powerMeter.liveRightBalancePercent ?? rider.trainer.liveRightBalancePercent
        )
    }

    private func appendTrainerRecordingSample(
        for sessionID: UUID,
        to session: inout TrainerRecordingSession,
        at timestamp: Date
    ) {
        let delta = trainerDistanceDelta(for: sessionID, since: session.lastSampleAt, to: timestamp)
        session.cumulativeDistanceMeters += delta.distanceMeters
        session.cumulativeElevationGainMeters += delta.elevationGainMeters
        let sample = makeLiveRideSample(for: sessionID, at: timestamp, distanceMeters: session.cumulativeDistanceMeters)
        session.samples.append(sample)
        if isTrainerRideMoving(sample: sample) {
            session.movingDurationSec += delta.elapsedSec
        }
        session.lastSampleAt = timestamp
    }

    private func isTrainerRideMoving(sample: LiveRideSample) -> Bool {
        if let power = sample.powerWatts {
            return power > 0
        }
        return false
    }

    private func trainerRecordingCheckpointURL(for sessionID: UUID) throws -> URL {
        let dir = try resolveWritableTrainerRecordingDirectory()
        return dir.appendingPathComponent("in-progress-\(sessionID.uuidString.lowercased()).fit")
    }

    private func removeTrainerRecordingCheckpointFIT(for sessionID: UUID) {
        guard let url = try? trainerRecordingCheckpointURL(for: sessionID) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    private func maybeWriteTrainerRecordingCheckpointFIT(
        for sessionID: UUID,
        session: inout TrainerRecordingSession,
        at timestamp: Date
    ) {
        if let last = session.lastCheckpointWriteAt,
           timestamp.timeIntervalSince(last) < trainerRecordingCheckpointWriteIntervalSec {
            return
        }
        guard !session.samples.isEmpty else { return }

        let samples = session.samples.sorted { $0.timestamp < $1.timestamp }
        let powerValues = samples.compactMap { $0.powerWatts }.filter { $0 > 0 }
        let hrValues = samples.compactMap { $0.heartRateBPM }.filter { $0 > 0 }
        let avgPower = powerValues.isEmpty ? nil : Int((Double(powerValues.reduce(0, +)) / Double(powerValues.count)).rounded())
        let maxPower = powerValues.max()
        let normalizedPower = TSSEstimator.normalizedPower(from: powerValues.map(Double.init)) ?? avgPower
        let avgHeartRate = hrValues.isEmpty ? nil : Int((Double(hrValues.reduce(0, +)) / Double(hrValues.count)).rounded())
        let maxHeartRate = hrValues.max()
        let elapsedSec = max(1, Int(timestamp.timeIntervalSince(session.startedAt).rounded()))
        let movingSec = max(0, Int(session.movingDurationSec.rounded()))
        let summary = LiveRideSummary(
            startDate: session.startedAt,
            endDate: timestamp,
            sport: .cycling,
            totalElapsedSec: elapsedSec,
            totalTimerSec: movingSec,
            totalDistanceMeters: max(0, session.cumulativeDistanceMeters),
            averageHeartRate: avgHeartRate,
            maxHeartRate: maxHeartRate,
            averagePower: avgPower,
            maxPower: maxPower,
            normalizedPower: normalizedPower
        )

        do {
            let fitData = LiveRideFITWriter.export(samples: samples, summary: summary)
            let target = try trainerRecordingCheckpointURL(for: sessionID)
            try fitData.write(to: target, options: .atomic)
            session.lastCheckpointWriteAt = timestamp
        } catch {
            appendClientLog(
                level: "WARN",
                message: "Failed to write trainer checkpoint FIT: \(detailedErrorDescription(error))"
            )
        }
    }

    private func captureTrainerRecordingSample(for sessionID: UUID, at timestamp: Date = Date()) {
        guard trainerRecordingStatus(for: sessionID).isActive else { return }
        guard var session = trainerRecordingSessionByRider[sessionID] else { return }

        appendTrainerRecordingSample(for: sessionID, to: &session, at: timestamp)
        maybeWriteTrainerRecordingCheckpointFIT(for: sessionID, session: &session, at: timestamp)
        trainerRecordingSessionByRider[sessionID] = session

        var status = trainerRecordingStatus(for: sessionID)
        status.elapsedSec = max(0, Int(timestamp.timeIntervalSince(session.startedAt).rounded()))
        status.movingSec = max(0, Int(session.movingDurationSec.rounded()))
        status.sampleCount = session.samples.count
        status.elevationGainMeters = max(0, session.cumulativeElevationGainMeters)
        updateTrainerRecordingStatus(status, for: sessionID)
    }

    private func finalizeTrainerRecording(for sessionID: UUID, reason: String) async {
        guard trainerRecordingSessionByRider[sessionID] != nil else {
            var status = trainerRecordingStatus(for: sessionID)
            status.isActive = false
            status.elapsedSec = 0
            status.movingSec = 0
            status.sampleCount = 0
            status.elevationGainMeters = 0
            updateTrainerRecordingStatus(status, for: sessionID)
            return
        }
        guard !isFinalizingTrainerRecordingBySession.contains(sessionID) else { return }

        isFinalizingTrainerRecordingBySession.insert(sessionID)
        trainerRecordingFinalizationTaskBySession[sessionID]?.cancel()
        trainerRecordingFinalizationTaskBySession[sessionID] = nil
        trainerRecordingTimerTaskBySession[sessionID]?.cancel()
        trainerRecordingTimerTaskBySession[sessionID] = nil
        captureTrainerRecordingSample(for: sessionID)

        defer {
            trainerRecordingSessionByRider[sessionID] = nil
            isFinalizingTrainerRecordingBySession.remove(sessionID)
            removeTrainerRecordingCheckpointFIT(for: sessionID)
            var status = trainerRecordingStatus(for: sessionID)
            status.isActive = false
            status.elapsedSec = 0
            status.movingSec = 0
            status.sampleCount = 0
            status.elevationGainMeters = 0
            updateTrainerRecordingStatus(status, for: sessionID)
        }

        guard var session = trainerRecordingSessionByRider[sessionID] else { return }
        let end = Date()
        if end > session.lastSampleAt {
            appendTrainerRecordingSample(for: sessionID, to: &session, at: end)
        }
        trainerRecordingSessionByRider[sessionID] = session

        var inProgressStatus = trainerRecordingStatus(for: sessionID)
        inProgressStatus.elevationGainMeters = max(0, session.cumulativeElevationGainMeters)
        inProgressStatus.movingSec = max(0, Int(session.movingDurationSec.rounded()))
        updateTrainerRecordingStatus(inProgressStatus, for: sessionID)

        let samples = session.samples.sorted { $0.timestamp < $1.timestamp }
        let elapsedSec = max(1, Int(end.timeIntervalSince(session.startedAt).rounded()))
        let movingSec = max(0, Int(session.movingDurationSec.rounded()))
        let totalDistanceMeters = max(0, session.cumulativeDistanceMeters)

        let powerValues = samples.compactMap { $0.powerWatts }.filter { $0 > 0 }
        let hrValues = samples.compactMap { $0.heartRateBPM }.filter { $0 > 0 }
        let avgPower = powerValues.isEmpty ? nil : Int((Double(powerValues.reduce(0, +)) / Double(powerValues.count)).rounded())
        let maxPower = powerValues.max()
        let normalizedPower = TSSEstimator.normalizedPower(from: powerValues.map(Double.init)) ?? avgPower
        let avgHeartRate = hrValues.isEmpty ? nil : Int((Double(hrValues.reduce(0, +)) / Double(hrValues.count)).rounded())
        let maxHeartRate = hrValues.max()
        let missingPowerData = powerValues.isEmpty

        let summary = LiveRideSummary(
            startDate: session.startedAt,
            endDate: end,
            sport: .cycling,
            totalElapsedSec: elapsedSec,
            totalTimerSec: movingSec,
            totalDistanceMeters: totalDistanceMeters,
            averageHeartRate: avgHeartRate,
            maxHeartRate: maxHeartRate,
            averagePower: avgPower,
            maxPower: maxPower,
            normalizedPower: normalizedPower
        )

        let riderName = trainerRiderSession(id: sessionID)?.name ?? "Rider"
        var savedFitPath: String?
        var savedFitName: String?

        do {
            let fitData = LiveRideFITWriter.export(samples: samples, summary: summary)
            let fitURL = try saveTrainerFITToDist(
                fitData: fitData,
                startDate: session.startedAt,
                sessionID: sessionID
            )
            savedFitPath = fitURL.path
            savedFitName = fitURL.lastPathComponent
            let bikeComputerSnapshot = try await captureTrainerBikeComputerSnapshot(
                samples: samples,
                riderName: riderName,
                startDate: session.startedAt,
                endDate: end,
                elapsedSec: elapsedSec,
                movingSec: movingSec
            )
            let fitUploadedToServer = uploadExportedFileToRepository(
                category: "trainer_fit",
                athleteName: riderName,
                fileName: fitURL.lastPathComponent,
                mimeType: "application/fit",
                sourcePath: fitURL.path,
                payload: fitData,
                createdAt: session.startedAt
            )
            let screenshotUploadedToServer = bikeComputerSnapshot.map { snapshot in
                uploadExportedFileToRepository(
                    category: "bike_computer_screenshot",
                    athleteName: riderName,
                    fileName: snapshot.fileName,
                    mimeType: snapshot.mimeType,
                    sourcePath: snapshot.savedPath,
                    payload: snapshot.data,
                    createdAt: end
                )
            }

            let baseNote = "\(riderName) · Trainer ride · \(IntervalsDateFormatter.dateTimeLocal.string(from: session.startedAt))"
            let note = missingPowerData
                ? baseNote + " · WARNING: missing power telemetry"
                : baseNote

            var activity = Activity(
                date: session.startedAt,
                sport: .cycling,
                athleteName: riderName,
                durationSec: elapsedSec,
                distanceKm: totalDistanceMeters / 1000.0,
                tss: TSSEstimator.estimate(
                    durationSec: elapsedSec,
                    sport: .cycling,
                    avgPower: avgPower,
                    normalizedPower: normalizedPower,
                    avgHeartRate: avgHeartRate,
                    profile: profile,
                    date: session.startedAt
                ),
                normalizedPower: normalizedPower,
                avgHeartRate: avgHeartRate,
                intervals: [],
                notes: note,
                externalID: "fricu:trainer:\(sessionID.uuidString):\(Int(session.startedAt.timeIntervalSince1970))",
                sourceFileName: fitURL.lastPathComponent,
                sourceFileType: "fit",
                sourceFileBase64: fitData.base64EncodedString(),
                bikeComputerScreenshotBase64: bikeComputerSnapshot?.data.base64EncodedString(),
                bikeComputerScreenshotFileName: bikeComputerSnapshot?.fileName,
                bikeComputerScreenshotMimeType: bikeComputerSnapshot?.mimeType
            )

            let persistenceResult = try persistTrainerActivityWithServerFallback(
                activity,
                fitFileName: fitURL.lastPathComponent
            )
            activity = persistenceResult.activity

            let syncSummary = await pushTrainerRideToClouds(
                activity: activity,
                fitData: fitData,
                fitFileName: fitURL.lastPathComponent
            )
            let snapshotSummary = bikeComputerSnapshot?.savedPath.map { "已保存码表截图：\($0)" } ?? "未生成码表截图"
            let uploadSummary: String = {
                let fitState = fitUploadedToServer ? "已上传" : "未上传"
                if let screenshotUploadedToServer {
                    let screenshotState = screenshotUploadedToServer ? "已上传" : "未上传"
                    return "导出上传：FIT \(fitState)，截图 \(screenshotState)"
                }
                return "导出上传：FIT \(fitState)"
            }()
            let powerWarningSummary = missingPowerData
                ? "警告：本次记录未采集到功率，已使用骑行台回退链路仍为空。请检查骑行台功率广播设置。"
                : ""
            if missingPowerData {
                appendClientLog(
                    level: "WARN",
                    message: "Trainer recording finalized without power telemetry (\(riderName), file=\(fitURL.lastPathComponent))."
                )
            }
            let finalSummary = "\(riderName) · \(reason)。总时长 \(elapsedSec)s，移动时长 \(movingSec)s。已保存 FIT：\(fitURL.lastPathComponent)。\(persistenceResult.summary)。\(snapshotSummary)。\(uploadSummary)。\(syncSummary)\(powerWarningSummary.isEmpty ? "" : "。\(powerWarningSummary)")"

            var status = trainerRecordingStatus(for: sessionID)
            status.lastFitPath = fitURL.path
            status.lastSyncSummary = finalSummary
            updateTrainerRecordingStatus(status, for: sessionID)
            syncStatus = finalSummary
            lastError = nil
        } catch {
            let message = "Trainer recording finalize failed (\(riderName)): \(error.localizedDescription)"
            let fitSavedSummary: String
            if let savedFitName {
                fitSavedSummary = "FIT 已保存：\(savedFitName)。"
            } else {
                fitSavedSummary = ""
            }
            let failureSummary = "\(riderName) · \(reason)。\(fitSavedSummary)保存失败：\(error.localizedDescription)"
            var status = trainerRecordingStatus(for: sessionID)
            if let savedFitPath {
                status.lastFitPath = savedFitPath
            }
            status.lastSyncSummary = failureSummary
            updateTrainerRecordingStatus(status, for: sessionID)
            syncStatus = failureSummary
            lastError = message
        }
    }

    private func persistTrainerActivityWithServerFallback(
        _ activity: Activity,
        fitFileName: String
    ) throws -> (activity: Activity, summary: String) {
        let merged = mergeActivities(imported: [activity])
        do {
            try persistActivities(merged)
            if let externalID = activity.externalID,
               let saved = activities.first(where: { $0.externalID == externalID }) {
                return (saved, "活动已保存")
            }
            if let saved = activities.first(where: { $0.sourceFileName == fitFileName }) {
                return (saved, "活动已保存")
            }
            return (activity, "活动已保存")
        } catch {
            if repository is RemoteHTTPRepository, isRetryableRemoteWriteError(error) {
                // RemoteHTTPRepository persists payload to durable pending queue before network PUT.
                self.activities = deduplicateActivities(merged)
                persistActivitiesToLocalCache(self.activities)
                pruneActivityMetricInsights()
                appendClientLog(
                    level: "WARN",
                    message: "Activity queued for later server sync: \(detailedErrorDescription(error))"
                )
                return (activity, "活动已写入本地待同步队列")
            }
            throw error
        }
    }

    private func isRetryableRemoteWriteError(_ error: Error) -> Bool {
        if let repoError = error as? RepositoryError {
            switch repoError {
            case .httpError, .noResponse:
                return true
            default:
                return false
            }
        }
        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain
    }

    private func saveTrainerFITToDist(fitData: Data, startDate: Date, sessionID: UUID?) throws -> URL {
        let fm = FileManager.default
        let distDir = try resolveWritableTrainerRecordingDirectory()

        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"

        var base = "trainer-\(formatter.string(from: startDate))"
        if let sessionID {
            base += "-s\(sessionID.uuidString.lowercased())"
        }
        var candidate = distDir.appendingPathComponent("\(base).fit")
        var suffix = 1
        while fm.fileExists(atPath: candidate.path) {
            candidate = distDir.appendingPathComponent("\(base)-\(suffix).fit")
            suffix += 1
        }

        try fitData.write(to: candidate, options: .atomic)
        return candidate
    }

    private struct TrainerBikeComputerSnapshot {
        let data: Data
        let fileName: String
        let mimeType: String
        let savedPath: String?
    }

    private func captureTrainerBikeComputerSnapshot(
        samples: [LiveRideSample],
        riderName: String,
        startDate: Date,
        endDate: Date,
        elapsedSec: Int,
        movingSec: Int
    ) async throws -> TrainerBikeComputerSnapshot? {
        #if canImport(SwiftUI) && canImport(AppKit)
        let sortedSamples = samples.sorted { $0.timestamp < $1.timestamp }
        let powerValues = sortedSamples.compactMap(\.powerWatts).filter { $0 > 0 }
        let heartRateValues = sortedSamples.compactMap(\.heartRateBPM).filter { $0 > 0 }
        let cadenceValues = sortedSamples.compactMap(\.cadenceRPM).filter { $0 > 0 }
        let speedValues = sortedSamples.compactMap(\.speedKPH).filter { $0 > 0 }
        let distanceKm = max(0, (sortedSamples.last?.distanceMeters ?? 0) / 1000.0)
        let elapsedHours = Double(max(1, elapsedSec)) / 3600.0
        let averagePower = powerValues.isEmpty ? nil : Int((Double(powerValues.reduce(0, +)) / Double(powerValues.count)).rounded())
        let maxPower = powerValues.max()
        let normalizedPower = TSSEstimator.normalizedPower(from: powerValues.map(Double.init))
        let averageHeartRate = heartRateValues.isEmpty ? nil : Int((Double(heartRateValues.reduce(0, +)) / Double(heartRateValues.count)).rounded())
        let maxHeartRate = heartRateValues.max()
        let averageCadence = cadenceValues.isEmpty ? nil : Int((cadenceValues.reduce(0, +) / Double(cadenceValues.count)).rounded())
        let averageSpeedKPH = distanceKm > 0 ? distanceKm / elapsedHours : nil
        let maxSpeedKPH = speedValues.max()

        let averageBalance: (left: Double, right: Double)? = {
            let pairs = sortedSamples.compactMap { sample -> (Double, Double)? in
                guard let left = sample.leftBalancePercent, let right = sample.rightBalancePercent else {
                    return nil
                }
                guard left.isFinite, right.isFinite, (0...100).contains(left), (0...100).contains(right) else {
                    return nil
                }
                let total = left + right
                guard total > 0 else { return nil }
                return ((left / total) * 100.0, (right / total) * 100.0)
            }
            guard !pairs.isEmpty else { return nil }
            let leftAvg = pairs.reduce(0.0) { $0 + $1.0 } / Double(pairs.count)
            let rightAvg = pairs.reduce(0.0) { $0 + $1.1 } / Double(pairs.count)
            return (leftAvg, rightAvg)
        }()

        var powerZoneSec = Array(repeating: 0, count: 7)
        var heartRateZoneSec = Array(repeating: 0, count: 7)
        var estimatedCaloriesKCal = 0.0
        let ftp = max(profile.ftpWatts(for: .cycling), 1)
        let maxHeartRateForZones = snapshotMaxHeartRateForZones(on: endDate)

        for index in sortedSamples.indices {
            guard index > 0 else { continue }
            let previous = sortedSamples[index - 1]
            let current = sortedSamples[index]
            let deltaSec = max(0, current.timestamp.timeIntervalSince(previous.timestamp))
            guard deltaSec > 0 else { continue }
            let seconds = Int(max(1, deltaSec.rounded()))

            if let power = current.powerWatts, power > 0 {
                let zone = snapshotPowerZoneIndex(for: power, ftp: ftp)
                powerZoneSec[zone] += seconds
                let estimate = CyclingCalorieEstimator.estimateStep(
                    powerWatts: Double(power),
                    durationSec: deltaSec,
                    ftpWatts: ftp
                )
                estimatedCaloriesKCal += estimate.metabolicKCal
            }
            if let hr = current.heartRateBPM, hr > 0 {
                let zone = snapshotHeartRateZoneIndex(for: hr, maxHeartRate: maxHeartRateForZones)
                heartRateZoneSec[zone] += seconds
            }
        }

        let payload = TrainerBikeComputerSnapshotPayload(
            riderName: riderName,
            startDate: startDate,
            endDate: endDate,
            elapsedSec: elapsedSec,
            movingSec: movingSec,
            latestPower: sortedSamples.last?.powerWatts,
            maxPower: maxPower,
            latestHeartRate: sortedSamples.last?.heartRateBPM,
            maxHeartRate: maxHeartRate,
            latestCadence: sortedSamples.last?.cadenceRPM.map { Int($0.rounded()) },
            averagePower: averagePower,
            normalizedPower: normalizedPower,
            power5s: snapshotBestRollingPower(window: 5, from: powerValues.map(Double.init)),
            power30s: snapshotBestRollingPower(window: 30, from: powerValues.map(Double.init)),
            power1m: snapshotBestRollingPower(window: 60, from: powerValues.map(Double.init)),
            power20m: snapshotBestRollingPower(window: 1_200, from: powerValues.map(Double.init)),
            power60m: snapshotBestRollingPower(window: 3_600, from: powerValues.map(Double.init)),
            averageHeartRate: averageHeartRate,
            maxHeartRateForZones: maxHeartRateForZones,
            averageCadence: averageCadence,
            latestSpeedKPH: sortedSamples.last?.speedKPH,
            averageSpeedKPH: averageSpeedKPH,
            maxSpeedKPH: maxSpeedKPH,
            distanceKm: distanceKm,
            estimatedCaloriesKCal: estimatedCaloriesKCal > 0 ? estimatedCaloriesKCal : nil,
            balanceLeftPercent: averageBalance?.left,
            balanceRightPercent: averageBalance?.right,
            powerZoneSec: powerZoneSec,
            heartRateZoneSec: heartRateZoneSec,
            powerTrace: Array(sortedSamples.suffix(180)).compactMap(\.powerWatts).map(Double.init),
            heartRateTrace: Array(sortedSamples.suffix(180)).compactMap(\.heartRateBPM).map(Double.init),
            cadenceTrace: Array(sortedSamples.suffix(180)).compactMap { $0.cadenceRPM }
        )

        guard let imageData = await MainActor.run(body: {
            Self.renderTrainerBikeComputerSnapshot(payload: payload)
        }) else {
            return nil
        }

        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let fileName = "bike-computer-\(formatter.string(from: startDate)).png"

        var savedPath: String?
        do {
            let screenshotURL = try saveTrainerSnapshotToDist(imageData: imageData, preferredFileName: fileName)
            savedPath = screenshotURL.path
        } catch {
            savedPath = nil
        }

        return TrainerBikeComputerSnapshot(
            data: imageData,
            fileName: fileName,
            mimeType: "image/png",
            savedPath: savedPath
        )
        #else
        return nil
        #endif
    }

    private func snapshotPowerZoneIndex(for watts: Int, ftp: Int) -> Int {
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

    private func snapshotHeartRateZoneIndex(for heartRate: Int, maxHeartRate: Int) -> Int {
        guard maxHeartRate > 0 else { return 0 }
        let ratio = Double(heartRate) / Double(maxHeartRate)
        switch ratio {
        case ..<0.60: return 0
        case ..<0.70: return 1
        case ..<0.80: return 2
        case ..<0.87: return 3
        case ..<0.93: return 4
        case ..<1.00: return 5
        default: return 6
        }
    }

    private func snapshotBestRollingPower(window: Int, from powers: [Double]) -> Double? {
        guard window > 0, powers.count >= window else { return nil }
        var sum = powers.prefix(window).reduce(0, +)
        var best = sum / Double(window)
        if powers.count == window {
            return best
        }
        for idx in window..<powers.count {
            sum += powers[idx] - powers[idx - window]
            best = max(best, sum / Double(window))
        }
        return best
    }

    private func snapshotMaxHeartRateForZones(on date: Date) -> Int {
        if let configured = profile.maxHeartRate(for: .cycling, on: date), configured > 0 {
            return configured
        }
        let age = max(1, profile.athleteAgeYears)
        let estimate = 208.0 - 0.7 * Double(age)
        return max(140, Int(estimate.rounded()))
    }

    private func saveTrainerSnapshotToDist(imageData: Data, preferredFileName: String) throws -> URL {
        let fm = FileManager.default
        let distDir = try resolveWritableTrainerRecordingDirectory()
        let sanitizedName = preferredFileName.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseName = sanitizedName.isEmpty ? "bike-computer.png" : sanitizedName
        let ext = (baseName as NSString).pathExtension.isEmpty ? "png" : (baseName as NSString).pathExtension
        let stem = (baseName as NSString).deletingPathExtension

        var candidate = distDir.appendingPathComponent("\(stem).\(ext)")
        var suffix = 1
        while fm.fileExists(atPath: candidate.path) {
            candidate = distDir.appendingPathComponent("\(stem)-\(suffix).\(ext)")
            suffix += 1
        }

        try imageData.write(to: candidate, options: .atomic)
        return candidate
    }

    private func uploadExportedFileToRepository(
        category: String,
        athleteName: String?,
        fileName: String,
        mimeType: String,
        sourcePath: String?,
        payload: Data,
        createdAt: Date
    ) -> Bool {
        guard let repository else { return false }
        let upload = ExportedFileUpload(
            id: UUID(),
            category: category,
            athleteName: athleteName,
            fileName: fileName,
            mimeType: mimeType,
            createdAt: createdAt,
            sourcePath: sourcePath,
            payload: payload
        )
        do {
            try repository.uploadExportedFile(upload)
            appendClientLog(
                level: "INFO",
                message: "Uploaded export \(category): \(fileName) (\(payload.count) bytes)."
            )
            return true
        } catch {
            if repository is RemoteHTTPRepository, isRetryableRemoteWriteError(error) {
                appendClientLog(
                    level: "WARN",
                    message: "Queued export for retry \(category) \(fileName): \(detailedErrorDescription(error))"
                )
                return true
            }
            appendClientLog(
                level: "ERROR",
                message: "Failed to upload export \(category) \(fileName): \(error.localizedDescription)"
            )
            return false
        }
    }

    private func resolveWritableTrainerRecordingDirectory() throws -> URL {
        let fm = FileManager.default

        var roots: [URL] = []
        #if os(iOS)
        if let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            roots.append(appSupport.appendingPathComponent("Fricu", isDirectory: true))
        }
        if let documents = fm.urls(for: .documentDirectory, in: .userDomainMask).first {
            roots.append(documents.appendingPathComponent("Fricu", isDirectory: true))
        }
        #else
        roots.append(URL(fileURLWithPath: fm.currentDirectoryPath, isDirectory: true))
        if let documents = fm.urls(for: .documentDirectory, in: .userDomainMask).first {
            roots.append(documents.appendingPathComponent("Fricu", isDirectory: true))
        }
        if let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            roots.append(appSupport.appendingPathComponent("Fricu", isDirectory: true))
        }
        #endif

        var attemptNotes: [String] = []
        for root in roots {
            let dir = root.appendingPathComponent("dist/recordings", isDirectory: true)
            do {
                if !fm.fileExists(atPath: dir.path) {
                    try fm.createDirectory(at: dir, withIntermediateDirectories: true)
                }
                guard isDirectoryWritable(dir) else {
                    attemptNotes.append("\(dir.path): not writable")
                    continue
                }
                return dir
            } catch {
                attemptNotes.append("\(dir.path): \(error.localizedDescription)")
                continue
            }
        }

        // Last-resort fallback: keep FIT export available even in restrictive sandboxes.
        let fallback = fm.temporaryDirectory.appendingPathComponent("fricu/dist/recordings", isDirectory: true)
        do {
            if !fm.fileExists(atPath: fallback.path) {
                try fm.createDirectory(at: fallback, withIntermediateDirectories: true)
            }
            if isDirectoryWritable(fallback) {
                return fallback
            }
            attemptNotes.append("\(fallback.path): not writable")
        } catch {
            attemptNotes.append("\(fallback.path): \(error.localizedDescription)")
        }

        throw NSError(
            domain: "Fricu.TrainerRecording",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "No writable directory for trainer FIT export. " + attemptNotes.joined(separator: " | ")]
        )
    }

    private func isDirectoryWritable(_ dir: URL) -> Bool {
        let fm = FileManager.default
        let probe = dir.appendingPathComponent(".write-test-\(UUID().uuidString)")
        let data = Data("ok".utf8)
        do {
            try data.write(to: probe, options: .atomic)
            try? fm.removeItem(at: probe)
            return true
        } catch {
            return false
        }
    }

    private func resolveWritableActivitiesExportDirectory() throws -> URL {
        let fm = FileManager.default
        var roots: [URL] = []
        #if os(iOS)
        if let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            roots.append(appSupport.appendingPathComponent("Fricu", isDirectory: true))
        }
        if let documents = fm.urls(for: .documentDirectory, in: .userDomainMask).first {
            roots.append(documents.appendingPathComponent("Fricu", isDirectory: true))
        }
        #else
        roots.append(URL(fileURLWithPath: fm.currentDirectoryPath, isDirectory: true))
        if let documents = fm.urls(for: .documentDirectory, in: .userDomainMask).first {
            roots.append(documents.appendingPathComponent("Fricu", isDirectory: true))
        }
        if let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            roots.append(appSupport.appendingPathComponent("Fricu", isDirectory: true))
        }
        #endif

        var attemptNotes: [String] = []
        for root in roots {
            let dir = root.appendingPathComponent("dist/exports", isDirectory: true)
            do {
                if !fm.fileExists(atPath: dir.path) {
                    try fm.createDirectory(at: dir, withIntermediateDirectories: true)
                }
                guard isDirectoryWritable(dir) else {
                    attemptNotes.append("\(dir.path): not writable")
                    continue
                }
                return dir
            } catch {
                attemptNotes.append("\(dir.path): \(error.localizedDescription)")
            }
        }

        throw NSError(
            domain: "Fricu.ActivityExport",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "No writable directory for activity export. " + attemptNotes.joined(separator: " | ")]
        )
    }

    private func pushTrainerRideToClouds(
        activity: Activity,
        fitData: Data,
        fitFileName: String
    ) async -> String {
        var rows: [String] = []

        let intervalsKey = profile.intervalsAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !intervalsKey.isEmpty {
            do {
                let client = try makeIntervalsClient()
                _ = try await client.uploadActivity(activity)
                rows.append("Intervals.icu: OK")
            } catch {
                rows.append("Intervals.icu: \(error.localizedDescription)")
            }
        } else {
            rows.append("Intervals.icu: skipped (no API key)")
        }

        do {
            _ = try await pushActivityPayloadToStrava(
                activity: activity,
                payload: (fitData, "fit", fitFileName),
                description: "Uploaded from Fricu smart trainer",
                externalIDPrefix: "fricu-fit"
            )
            rows.append("Strava: OK")
        } catch {
            let isMissing: Bool
            if let stravaError = error as? StravaAPIError {
                switch stravaError {
                case .missingRefreshConfig, .missingAccessToken:
                    isMissing = true
                default:
                    isMissing = false
                }
            } else {
                isMissing = false
            }
            rows.append(isMissing ? "Strava: skipped (no token)" : "Strava: \(error.localizedDescription)")
        }

        let garminToken = profile.garminConnectAccessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        if !garminToken.isEmpty {
            do {
                let client = GarminConnectAPIClient()
                _ = try await client.uploadActivityFile(
                    accessToken: profile.garminConnectAccessToken,
                    connectCSRFToken: profile.garminConnectCSRFToken,
                    fileData: fitData,
                    fileExtension: "fit",
                    fileName: fitFileName
                )
                rows.append("Garmin: OK")
            } catch {
                rows.append("Garmin: \(error.localizedDescription)")
            }
        } else {
            rows.append("Garmin: skipped (no token)")
        }

        return rows.joined(separator: " | ")
    }

    private func uploadPayload(for activity: Activity) -> (data: Data, `extension`: String, fileName: String) {
        if
            let encoded = activity.sourceFileBase64,
            let decoded = Data(base64Encoded: encoded),
            !decoded.isEmpty
        {
            let fileName = activity.sourceFileName?.trimmingCharacters(in: .whitespacesAndNewlines)
            let ext = resolvedUploadDataType(
                sourceType: activity.sourceFileType,
                sourceFileName: fileName,
                fileData: decoded
            )
            return (decoded, ext, (fileName?.isEmpty == false ? fileName! : "activity.\(ext)"))
        }

        let tcxData = TCXWriter.export(activity: activity)
        let fallbackName = "activity-\(IntervalsDateFormatter.day.string(from: activity.date)).tcx"
        return (tcxData, "tcx", fallbackName)
    }

    private func sanitizedUploadExtension(_ source: String?) -> String {
        let ext = source?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        if ["fit", "fit.gz", "tcx", "tcx.gz", "gpx", "gpx.gz"].contains(ext) {
            return ext
        }
        return ""
    }

    private func resolvedUploadDataType(
        sourceType: String?,
        sourceFileName: String?,
        fileData: Data
    ) -> String {
        if let explicit = nonEmptyUploadDataType(from: sourceType) {
            return explicit
        }
        if let fromName = nonEmptyUploadDataTypeFromFileName(sourceFileName) {
            return fromName
        }
        if isFITData(fileData) {
            return "fit"
        }
        if isTCXData(fileData) {
            return "tcx"
        }
        if isGPXData(fileData) {
            return "gpx"
        }
        // Keep binary payloads as FIT by default; this avoids forcing binary data through TCX uploads.
        return "fit"
    }

    private func nonEmptyUploadDataType(from source: String?) -> String? {
        let ext = sanitizedUploadExtension(source)
        return ext.isEmpty ? nil : ext
    }

    private func nonEmptyUploadDataTypeFromFileName(_ sourceFileName: String?) -> String? {
        guard let sourceFileName else { return nil }
        let lower = sourceFileName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if lower.hasSuffix(".fit.gz") { return "fit.gz" }
        if lower.hasSuffix(".tcx.gz") { return "tcx.gz" }
        if lower.hasSuffix(".gpx.gz") { return "gpx.gz" }
        if lower.hasSuffix(".fit") { return "fit" }
        if lower.hasSuffix(".tcx") { return "tcx" }
        if lower.hasSuffix(".gpx") { return "gpx" }
        return nil
    }

    private func isFITData(_ data: Data) -> Bool {
        guard data.count >= 12 else { return false }
        let signature = Data([0x2E, 0x46, 0x49, 0x54]) // ".FIT"
        return data.subdata(in: 8..<12) == signature
    }

    private func isTCXData(_ data: Data) -> Bool {
        guard let head = String(data: data.prefix(512), encoding: .utf8)?.lowercased() else { return false }
        return head.contains("<trainingcenterdatabase")
    }

    private func isGPXData(_ data: Data) -> Bool {
        guard let head = String(data: data.prefix(512), encoding: .utf8)?.lowercased() else { return false }
        return head.contains("<gpx")
    }

    private func shouldFallbackFITToTCX(
        _ error: Error,
        originalDataType: String
    ) -> Bool {
        guard originalDataType == "fit" || originalDataType == "fit.gz" else {
            return false
        }
        guard case let StravaAPIError.requestFailed(code, body) = error else {
            return false
        }
        guard code == 400 || code == 422 else { return false }
        let lowerBody = body.lowercased()
        return lowerBody.contains("fit") ||
            lowerBody.contains("malformed") ||
            lowerBody.contains("corrupt") ||
            lowerBody.contains("invalid")
    }

    private func uploadToStravaWithAuthRetry(
        client: StravaAPIClient,
        auth: inout StravaAuthUpdate,
        payload: (data: Data, ext: String),
        name: String,
        description: String,
        externalID: String
    ) async throws -> String {
        do {
            return try await client.uploadActivityFile(
                accessToken: auth.accessToken,
                fileData: payload.data,
                fileExtension: payload.ext,
                name: name,
                description: description,
                externalID: externalID
            )
        } catch let StravaAPIError.requestFailed(code, _) where code == 401 {
            auth = try await client.forceRefreshAccessToken(profile: profile)
            applyStravaAuthUpdate(auth)
            return try await client.uploadActivityFile(
                accessToken: auth.accessToken,
                fileData: payload.data,
                fileExtension: payload.ext,
                name: name,
                description: description,
                externalID: externalID
            )
        }
    }

    private func uploadScreenshotToStravaWithAuthRetry(
        client: StravaAPIClient,
        auth: inout StravaAuthUpdate,
        activityID: Int,
        screenshotData: Data,
        fileName: String,
        mimeType: String,
        caption: String
    ) async throws {
        var didRefreshAuth = false
        var retry404Count = 0

        while true {
            do {
                try await client.uploadActivityPhoto(
                    accessToken: auth.accessToken,
                    activityID: activityID,
                    photoData: screenshotData,
                    fileName: fileName,
                    mimeType: mimeType,
                    caption: caption
                )
                return
            } catch let StravaAPIError.requestFailed(code, _) where code == 401 && !didRefreshAuth {
                auth = try await client.forceRefreshAccessToken(profile: profile)
                applyStravaAuthUpdate(auth)
                didRefreshAuth = true
                continue
            } catch let StravaAPIError.requestFailed(code, body) where code == 404 && retry404Count < 3 {
                let lowered = body.lowercased()
                if (lowered.contains("invalid") && lowered.contains("path")) || lowered.contains("record not found") {
                    appendClientLog(
                        level: "WARN",
                        message: "Strava activity \(activityID) uploaded, but screenshot endpoint is unavailable for this app/token. Skipped photo upload. body=\(body)"
                    )
                    return
                }
                retry404Count += 1
                appendClientLog(
                    level: "WARN",
                    message: "Strava photo upload pending for activity \(activityID) (attempt \(retry404Count)): \(body)"
                )
                let waitSec = UInt64(2 * retry404Count)
                try await Task.sleep(nanoseconds: waitSec * 1_000_000_000)
                continue
            } catch let StravaAPIError.requestFailed(code, body)
                where code == 400 || code == 404 || code == 409 || code == 422 {
                appendClientLog(
                    level: "WARN",
                    message: "Strava activity \(activityID) uploaded, but screenshot upload was skipped (\(code)): \(body)"
                )
                return
            } catch {
                throw error
            }
        }
    }

    private func extractStravaActivityID(from externalID: String) -> Int? {
        guard externalID.hasPrefix("strava:") else { return nil }
        let raw = String(externalID.dropFirst("strava:".count))
        if raw.hasPrefix("upload:") { return nil }
        return Int(raw)
    }

    private func pushActivityPayloadToStrava(
        activity: Activity,
        payload: (data: Data, `extension`: String, fileName: String),
        description: String,
        externalIDPrefix: String = "fricu"
    ) async throws -> String {
        let client = StravaAPIClient()
        var auth = try await client.ensureAccessToken(profile: profile)
        applyStravaAuthUpdate(auth)

        let activityName = activity.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = activityName.isEmpty ? "Fricu Activity" : activityName
        let externalID = "\(externalIDPrefix)-\(activity.id.uuidString)"
        let dataType = payload.extension.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        let uploadedExternalID: String
        do {
            uploadedExternalID = try await uploadToStravaWithAuthRetry(
                client: client,
                auth: &auth,
                payload: (payload.data, dataType),
                name: title,
                description: description,
                externalID: externalID
            )
        } catch {
            guard shouldFallbackFITToTCX(error, originalDataType: dataType) else {
                throw error
            }
            let tcx = TCXWriter.export(activity: activity)
            uploadedExternalID = try await uploadToStravaWithAuthRetry(
                client: client,
                auth: &auth,
                payload: (tcx, "tcx"),
                name: title,
                description: description + " (fallback: tcx)",
                externalID: externalID + "-tcx"
            )
        }

        if
            let screenshotBase64 = activity.bikeComputerScreenshotBase64,
            let screenshotData = Data(base64Encoded: screenshotBase64),
            !screenshotData.isEmpty,
            let stravaActivityID = extractStravaActivityID(from: uploadedExternalID)
        {
            let fileName = activity.bikeComputerScreenshotFileName ?? "bike-computer.png"
            let mimeType = activity.bikeComputerScreenshotMimeType ?? "image/png"
            try await uploadScreenshotToStravaWithAuthRetry(
                client: client,
                auth: &auth,
                activityID: stravaActivityID,
                screenshotData: screenshotData,
                fileName: fileName,
                mimeType: mimeType,
                caption: "Fricu 实时码表截图"
            )
        }

        return uploadedExternalID
    }

    func ensureAICoachReady() async {
        guard !didAttemptAICoachBootstrap else { return }
        didAttemptAICoachBootstrap = true
        await refreshAIRecommendationFromGPT()
    }

    func refreshAIRecommendationFromGPT() async {
        if isRefreshingAICoach { return }
        isRefreshingAICoach = true
        aiCoachStatus = "Refreshing GPT coach..."
        defer { isRefreshingAICoach = false }

        let key = profile.openAIAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            gptRecommendation = nil
            aiCoachSource = "GPT"
            aiCoachStatus = "GPT key missing. Configure API key first."
            markDerivedStateDirty()
            return
        }

        do {
            let client = OpenAICoachClient(apiKey: key)
            let input = buildGPTCoachInput()
            let response = try await client.recommend(input: input)
            gptRecommendation = response
            aiCoachSource = "GPT"
            aiCoachUpdatedAt = Date()
            aiCoachStatus = "GPT coach updated."
            markDerivedStateDirty()
        } catch {
            aiCoachSource = gptRecommendation == nil ? "GPT" : "GPT (stale)"
            aiCoachStatus = "GPT request failed: \(error.localizedDescription)"
            markDerivedStateDirty()
        }
    }

    func ensureActivityMetricInsightCached(for activity: Activity) async {
        let fingerprint = activityInsightFingerprint(activity)
        if let cached = activityMetricInsightsCache[activity.id], cached.fingerprint == fingerprint {
            return
        }
        await refreshActivityMetricInsight(for: activity, force: true)
    }

    func refreshActivityMetricInsight(for activity: Activity, force: Bool = false) async {
        let fingerprint = activityInsightFingerprint(activity)
        if !force, let cached = activityMetricInsightsCache[activity.id], cached.fingerprint == fingerprint {
            return
        }
        if refreshingActivityInsightIDs.contains(activity.id) {
            return
        }

        let key = profile.openAIAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            lastError = "GPT key missing. Configure API key first."
            return
        }

        refreshingActivityInsightIDs.insert(activity.id)
        defer { refreshingActivityInsightIDs.remove(activity.id) }

        do {
            let client = OpenAICoachClient(apiKey: key)
            let payload = try await client.interpretActivityMetrics(input: buildActivityMetricInsightInput(activity))
            let insight = ActivityMetricInsight(
                activityID: activity.id,
                activityDate: activity.date,
                generatedAt: Date(),
                model: "gpt-4o-mini",
                fingerprint: fingerprint,
                summary: payload.summary,
                keyFindings: payload.keyFindings,
                actions: payload.actions
            )
            activityMetricInsightsCache[activity.id] = insight
            try persistActivityMetricInsights()
            syncStatus = "Saved GPT metric insight for \(activity.sport.label) \(IntervalsDateFormatter.day.string(from: activity.date))."
        } catch {
            lastError = "Failed to generate activity metric GPT insight: \(error.localizedDescription)"
        }
    }

    func saveWorkout(name: String, sport: SportType, segments: [WorkoutSegment], scheduledDate: Date?) {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard !segments.isEmpty else { return }

        var updated = plannedWorkouts
        updated.insert(
            PlannedWorkout(
                name: name,
                sport: sport,
                athleteName: selectedAthleteNameForWrite,
                segments: segments,
                scheduledDate: scheduledDate
            ),
            at: 0
        )

        do {
            if let repository {
                try repository.saveWorkouts(updated)
            }
            self.plannedWorkouts = updated
        } catch {
            self.lastError = "Failed to save workout: \(error.localizedDescription)"
        }
    }

    func deleteWorkout(_ workout: PlannedWorkout) {
        var updated = plannedWorkouts
        updated.removeAll { $0.id == workout.id }

        do {
            if let repository {
                try repository.saveWorkouts(updated)
            }
            self.plannedWorkouts = updated
        } catch {
            self.lastError = "Failed to delete workout: \(error.localizedDescription)"
        }
    }

    func rescheduleWorkout(id: UUID, to day: Date?) {
        var updated = plannedWorkouts
        guard let index = updated.firstIndex(where: { $0.id == id }) else { return }
        updated[index].scheduledDate = day.map { Calendar.current.startOfDay(for: $0) }

        do {
            if let repository {
                try repository.saveWorkouts(updated)
            }
            self.plannedWorkouts = updated.sorted { lhs, rhs in
                let left = lhs.scheduledDate ?? lhs.createdAt
                let right = rhs.scheduledDate ?? rhs.createdAt
                return left > right
            }
        } catch {
            self.lastError = "Failed to reschedule workout: \(error.localizedDescription)"
        }
    }

    func instantiateTemplate(_ template: WorkoutTemplate, startDate: Date, repeatWeeks: Int) {
        let calendar = Calendar.current
        let weekCount = max(1, repeatWeeks)
        var updated = plannedWorkouts

        for week in 0..<weekCount {
            guard let date = calendar.date(byAdding: .day, value: week * 7, to: startDate) else { continue }
            let workout = PlannedWorkout(
                name: "\(template.name) · W\(week + 1)",
                sport: template.sport,
                athleteName: selectedAthleteNameForWrite,
                segments: template.segments,
                scheduledDate: calendar.startOfDay(for: date)
            )
            updated.insert(workout, at: 0)
        }

        do {
            if let repository {
                try repository.saveWorkouts(updated)
            }
            self.plannedWorkouts = updated
            self.syncStatus = "Added \(weekCount) workout(s) from template."
        } catch {
            self.lastError = "Failed to apply template: \(error.localizedDescription)"
        }
    }

    func addNorwegianDoubleThresholdDay(sport: SportType, date: Date) {
        let day = Calendar.current.startOfDay(for: date)
        let sessions = norwegianDoubleThresholdSessions(for: sport)
        guard sessions.count == 2 else { return }

        var updated = plannedWorkouts
        updated.insert(
            PlannedWorkout(
                name: sessions[1].name,
                sport: sport,
                athleteName: selectedAthleteNameForWrite,
                segments: sessions[1].segments,
                scheduledDate: day
            ),
            at: 0
        )
        updated.insert(
            PlannedWorkout(
                name: sessions[0].name,
                sport: sport,
                athleteName: selectedAthleteNameForWrite,
                segments: sessions[0].segments,
                scheduledDate: day
            ),
            at: 0
        )

        do {
            if let repository {
                try repository.saveWorkouts(updated)
            }
            self.plannedWorkouts = updated
            self.syncStatus = "Added Norwegian double-threshold day (\(sport.label)) on \(IntervalsDateFormatter.day.string(from: day))."
        } catch {
            self.lastError = "Failed to add Norwegian double-threshold day: \(error.localizedDescription)"
        }
    }

    func bulkAdjustActivitiesPower(activityIDs: Set<UUID>, deltaPercent: Double, overwriteMissing: Bool) {
        guard !activityIDs.isEmpty else { return }
        var updated = activities
        let factor = max(0.2, 1.0 + deltaPercent / 100.0)
        var touched = 0

        for index in updated.indices where activityIDs.contains(updated[index].id) {
            var row = updated[index]
            let originalPower = row.normalizedPower
            if let np = originalPower {
                row.normalizedPower = Int((Double(np) * factor).rounded())
            } else if overwriteMissing {
                let fallback = max(80, profile.ftpWatts(for: row.sport))
                row.normalizedPower = Int((Double(fallback) * factor * 0.72).rounded())
            } else {
                continue
            }

            row.tss = TSSEstimator.estimate(
                durationSec: row.durationSec,
                sport: row.sport,
                avgPower: row.normalizedPower,
                normalizedPower: row.normalizedPower,
                avgHeartRate: row.avgHeartRate,
                profile: profile,
                date: row.date
            )
            updated[index] = row
            touched += 1
        }

        do {
            try persistActivities(updated)
            self.syncStatus = "Batch corrected \(touched) activities."
        } catch {
            self.lastError = "Failed to batch update activities: \(error.localizedDescription)"
        }
    }

    func importActivityFiles(urls: [URL]) {
        do {
            let imported = try urls.map { try ActivityFileImporter.importFile(at: $0, profile: profile) }
            guard !imported.isEmpty else { return }

            let merged = mergeActivities(imported: imported)
            try persistActivities(merged)
            self.syncStatus = "Imported \(imported.count) file(s)."
        } catch {
            self.lastError = "Failed to import files: \(error.localizedDescription)"
        }
    }

    func clearAllActivities() {
        let updated = [Activity]()
        let removedCount = activities.count

        do {
            try persistActivities(updated)
            self.syncStatus = "Cleared \(removedCount) activities for \(selectedAthleteTitle)."
            self.lastError = nil
        } catch {
            self.lastError = "Failed to clear activities: \(error.localizedDescription)"
        }
    }

    func deleteActivities(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        let updated = activities.filter { !ids.contains($0.id) }
        do {
            try persistActivities(updated)
            self.syncStatus = "Deleted \(ids.count) activities."
        } catch {
            self.lastError = "Failed to delete selected activities: \(error.localizedDescription)"
        }
    }

    func repairActivities(ids: Set<UUID>, mode: ActivityRepairMode) {
        guard !ids.isEmpty else { return }
        var updated = activities
        var touched = 0

        for index in updated.indices where ids.contains(updated[index].id) {
            let repaired = ActivityRepairEngine.repaired(activity: updated[index], mode: mode, profile: profile)
            updated[index] = repaired
            touched += 1
        }

        do {
            try persistActivities(updated)
            syncStatus = "Applied \(mode.title) to \(touched) activities."
        } catch {
            lastError = "Failed to repair activities: \(error.localizedDescription)"
        }
    }

    func exportActivitiesToDist(ids: Set<UUID>) {
        let selected: [Activity]
        if ids.isEmpty {
            selected = activities
        } else {
            selected = activities.filter { ids.contains($0.id) }
        }

        do {
            let exportDir = try resolveWritableActivitiesExportDirectory()
            let output = try ActivityExporter.exportActivitiesJSON(activities: selected, to: exportDir)
            syncStatus = "Exported \(selected.count) activities to \(output.path)"
            lastError = nil
        } catch {
            lastError = "Failed to export activities: \(error.localizedDescription)"
        }
    }

    func importGarminConnectJSON(urls: [URL]) {
        do {
            var imported: [Activity] = []
            for url in urls {
                imported.append(contentsOf: try GarminConnectExportImporter.importJSON(at: url, profile: profile))
            }

            guard !imported.isEmpty else {
                syncStatus = "No Garmin activities parsed."
                return
            }

            let merged = mergeActivities(imported: imported)
            try persistActivities(merged)
            syncStatus = "Imported \(imported.count) Garmin activities."
        } catch {
            lastError = "Failed to import Garmin JSON: \(error.localizedDescription)"
        }
    }

    func syncPullActivitiesFromIntervals(days: Int = 180) async {
        await runSync("Pulling activities from Intervals.icu...") {
            let client = try self.makeIntervalsClient()
            let end = Date()
            let start = Calendar.current.date(byAdding: .day, value: -days, to: end) ?? end
            let pulled = try await client.fetchActivities(oldest: start, newest: end, profile: self.profile)
            let merged = self.mergeActivities(imported: pulled)
            try self.persistActivities(merged)
            self.syncStatus = "Pulled \(pulled.count) activities from Intervals.icu."
        }
    }

    func syncAuthorizeStravaOAuth(
        redirectURI: String = "http://127.0.0.1:53682/callback",
        openBrowser: @escaping (URL) -> Void
    ) async {
        await runSync("Authorizing Strava OAuth...") {
            let clientID = self.profile.stravaClientID.trimmingCharacters(in: .whitespacesAndNewlines)
            let clientSecret = self.profile.stravaClientSecret.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clientID.isEmpty, !clientSecret.isEmpty else {
                throw StravaAPIError.missingClientConfig
            }

            let client = StravaAPIClient()
            let state = UUID().uuidString.replacingOccurrences(of: "-", with: "")
            guard let authURL = client.buildAuthorizationURL(
                clientID: clientID,
                redirectURI: redirectURI,
                state: state
            ) else {
                throw StravaAPIError.badResponse
            }

            let callbackServer = try StravaOAuthLocalCallbackServer(redirectURI: redirectURI)
            async let callbackPayload = callbackServer.awaitCallback()

            openBrowser(authURL)

            let callback = try await callbackPayload
            if let oauthError = callback.error, !oauthError.isEmpty {
                let detail = callback.errorDescription?.removingPercentEncoding ?? callback.errorDescription ?? oauthError
                throw StravaAPIError.oauthDenied(detail)
            }
            guard callback.state == state else {
                throw StravaAPIError.oauthStateMismatch
            }
            guard let code = callback.code, !code.isEmpty else {
                throw StravaAPIError.oauthMissingCode
            }

            let auth = try await client.exchangeAuthorizationCode(
                clientID: clientID,
                clientSecret: clientSecret,
                code: code,
                redirectURI: redirectURI
            )
            self.applyStravaAuthUpdate(auth)
            self.syncStatus = "Strava OAuth succeeded."
        }
    }

    func syncPullActivitiesFromStrava(days: Int = 180) async {
        await runSync("Pulling activities from Strava...") {
            let client = StravaAPIClient()
            var auth = try await client.ensureAccessToken(profile: self.profile)
            self.applyStravaAuthUpdate(auth)

            let end = Date()
            let start = Calendar.current.date(byAdding: .day, value: -days, to: end) ?? end
            let pulled: [Activity]
            do {
                pulled = try await client.fetchActivities(
                    accessToken: auth.accessToken,
                    oldest: start,
                    newest: end,
                    profile: self.profile
                )
            } catch let StravaAPIError.requestFailed(code, _) where code == 401 {
                auth = try await client.forceRefreshAccessToken(profile: self.profile)
                self.applyStravaAuthUpdate(auth)
                pulled = try await client.fetchActivities(
                    accessToken: auth.accessToken,
                    oldest: start,
                    newest: end,
                    profile: self.profile
                )
            }

            let merged = self.mergeActivities(imported: pulled)
            try self.persistActivities(merged)
            self.syncStatus = "Pulled \(pulled.count) activities from Strava."
        }
    }

    func syncPullActivitiesFromGarminConnect(days: Int = 180) async {
        await runSync("Pulling activities from Garmin Connect...") {
            let client = GarminConnectAPIClient()
            let end = Date()
            let start = Calendar.current.date(byAdding: .day, value: -days, to: end) ?? end
            let pulled = try await client.fetchActivities(
                accessToken: self.profile.garminConnectAccessToken,
                connectCSRFToken: self.profile.garminConnectCSRFToken,
                oldest: start,
                newest: end,
                profile: self.profile
            )

            let merged = self.mergeActivities(imported: pulled)
            try self.persistActivities(merged)
            self.syncStatus = "Pulled \(pulled.count) activities from Garmin Connect."
        }
    }

    func syncPushActivitiesToIntervals() async {
        await runSync("Pushing activities to Intervals.icu...") {
            let client = try self.makeIntervalsClient()
            var updated = self.activities
            var pushedCount = 0
            let targetIndexes = Array(updated.indices)

            for index in targetIndexes {
                if updated[index].externalID?.hasPrefix("intervals:") == true {
                    continue
                }

                let external = try await client.uploadActivity(updated[index])
                updated[index].externalID = external
                pushedCount += 1
            }

            try self.persistActivities(updated)
            self.syncStatus = "Pushed \(pushedCount) activities to Intervals.icu for \(self.selectedAthleteTitle)."
        }
    }

    func syncPushActivityToIntervals(activityID: UUID) async {
        await runSync("Pushing selected activity to Intervals.icu...") {
            guard let idx = self.activities.firstIndex(where: { $0.id == activityID }) else {
                throw NSError(domain: "Fricu.Sync", code: 404, userInfo: [
                    NSLocalizedDescriptionKey: "Selected activity not found."
                ])
            }
            let client = try self.makeIntervalsClient()
            var updated = self.activities
            let external = try await client.uploadActivity(updated[idx])
            updated[idx].externalID = external
            try self.persistActivities(updated)
            self.syncStatus = "Pushed selected activity to Intervals.icu."
        }
    }

    func syncPushActivityToStrava(activityID: UUID) async {
        await runSync("Pushing selected activity to Strava...") {
            guard let activity = self.activities.first(where: { $0.id == activityID }) else {
                throw NSError(domain: "Fricu.Sync", code: 404, userInfo: [
                    NSLocalizedDescriptionKey: "Selected activity not found."
                ])
            }
            let payload = self.uploadPayload(for: activity)
            _ = try await self.pushActivityPayloadToStrava(
                activity: activity,
                payload: payload,
                description: "Uploaded from Fricu"
            )
            self.syncStatus = "Pushed selected activity to Strava."
        }
    }

    func syncPushActivityToGarminConnect(activityID: UUID) async {
        await runSync("Pushing selected activity to Garmin Connect...") {
            guard let activity = self.activities.first(where: { $0.id == activityID }) else {
                throw NSError(domain: "Fricu.Sync", code: 404, userInfo: [
                    NSLocalizedDescriptionKey: "Selected activity not found."
                ])
            }
            let payload = self.uploadPayload(for: activity)
            let client = GarminConnectAPIClient()
            _ = try await client.uploadActivityFile(
                accessToken: self.profile.garminConnectAccessToken,
                connectCSRFToken: self.profile.garminConnectCSRFToken,
                fileData: payload.data,
                fileExtension: payload.extension,
                fileName: payload.fileName
            )
            self.syncStatus = "Pushed selected activity to Garmin Connect."
        }
    }

    func syncPushActivityToConnectedPlatforms(activityID: UUID) async {
        await runSync("Pushing selected activity to connected platforms...") {
            guard let idx = self.activities.firstIndex(where: { $0.id == activityID }) else {
                throw NSError(domain: "Fricu.Sync", code: 404, userInfo: [
                    NSLocalizedDescriptionKey: "Selected activity not found."
                ])
            }

            var rows: [String] = []
            var updated = self.activities
            let activity = updated[idx]
            let payload = self.uploadPayload(for: activity)

            do {
                let client = try self.makeIntervalsClient()
                let external = try await client.uploadActivity(activity)
                updated[idx].externalID = external
                rows.append("Intervals.icu: OK")
            } catch {
                rows.append("Intervals.icu: \(error.localizedDescription)")
            }

            do {
                _ = try await self.pushActivityPayloadToStrava(
                    activity: activity,
                    payload: payload,
                    description: "Uploaded from Fricu"
                )
                rows.append("Strava: OK")
            } catch {
                rows.append("Strava: \(error.localizedDescription)")
            }

            do {
                let client = GarminConnectAPIClient()
                _ = try await client.uploadActivityFile(
                    accessToken: self.profile.garminConnectAccessToken,
                    connectCSRFToken: self.profile.garminConnectCSRFToken,
                    fileData: payload.data,
                    fileExtension: payload.extension,
                    fileName: payload.fileName
                )
                rows.append("Garmin: OK")
            } catch {
                rows.append("Garmin: \(error.localizedDescription)")
            }

            try self.persistActivities(updated)
            self.syncStatus = rows.joined(separator: " | ")
        }
    }

    func syncPullWorkoutsFromIntervals(days: Int = 120) async {
        await runSync("Pulling workouts from Intervals.icu...") {
            let client = try self.makeIntervalsClient()
            let end = Date()
            let start = Calendar.current.date(byAdding: .day, value: -days, to: end) ?? end
            let pulled = try await client.fetchWorkouts(oldest: start, newest: end).map { row -> PlannedWorkout in
                var tagged = row
                if self.normalizedNonEmptyString(tagged.athleteName) == nil {
                    tagged.athleteName = self.selectedAthleteNameForWrite
                }
                return tagged
            }
            let merged = self.mergeWorkouts(imported: pulled)
            try self.persistWorkouts(merged)
            self.syncStatus = "Pulled \(pulled.count) workouts from Intervals.icu."
        }
    }

    func syncPushWorkoutsToIntervals() async {
        await runSync("Pushing workouts to Intervals.icu...") {
            let client = try self.makeIntervalsClient()
            let scoped = self.athleteScopedPlannedWorkouts
            try await client.upsertWorkouts(scoped)
            var updated = self.plannedWorkouts
            let scopedIDs = Set(scoped.map(\.id))
            for index in updated.indices where scopedIDs.contains(updated[index].id) {
                if updated[index].externalID == nil {
                    updated[index].externalID = "fricu-workout-\(updated[index].id.uuidString)"
                }
            }
            try self.persistWorkouts(updated)
            self.syncStatus = "Upserted \(scoped.count) workouts to Intervals.icu."
        }
    }

    func syncPullWellnessFromIntervals(days: Int = 30) async {
        await runSync("Pulling HRV/wellness from Intervals.icu...") {
            let client = try self.makeIntervalsClient()
            let end = Date()
            let start = Calendar.current.date(byAdding: .day, value: -days, to: end) ?? end
            let wellness = try await client.fetchWellness(oldest: start, newest: end)
            try self.applyWellnessSamples(wellness, mergeWithExisting: false, baselineWindowDays: days)
            self.syncStatus = "Pulled \(wellness.count) wellness entries from Intervals.icu."
        }
    }

    func syncPullWellnessFromOura(days: Int = 30) async {
        await runSync("Pulling wellness from Oura...") {
            let end = Date()
            let start = Calendar.current.date(byAdding: .day, value: -days, to: end) ?? end
            let client = OuraAPIClient()
            let pulled = try await client.fetchWellness(
                accessToken: self.profile.ouraPersonalAccessToken,
                start: start,
                end: end
            )
            try self.applyWellnessSamples(pulled, mergeWithExisting: true, baselineWindowDays: 28)
            self.syncStatus = "Pulled \(pulled.count) wellness samples from Oura."
        }
    }

    func syncPullWellnessFromWhoop(days: Int = 30) async {
        await runSync("Pulling wellness from WHOOP...") {
            let end = Date()
            let start = Calendar.current.date(byAdding: .day, value: -days, to: end) ?? end
            let client = WhoopAPIClient()
            let pulled = try await client.fetchWellness(
                accessToken: self.profile.whoopAccessToken,
                start: start,
                end: end
            )
            try self.applyWellnessSamples(pulled, mergeWithExisting: true, baselineWindowDays: 28)
            self.syncStatus = "Pulled \(pulled.count) wellness samples from WHOOP."
        }
    }

    func syncPullWellnessFromGarmin(days: Int = 30) async {
        await runSync("Pulling wellness from Garmin Connect...") {
            let end = Date()
            let start = Calendar.current.date(byAdding: .day, value: -days, to: end) ?? end
            let client = GarminConnectAPIClient()
            let pulled = try await client.fetchWellness(
                accessToken: self.profile.garminConnectAccessToken,
                connectCSRFToken: self.profile.garminConnectCSRFToken,
                start: start,
                end: end
            )
            try self.applyWellnessSamples(pulled, mergeWithExisting: true, baselineWindowDays: 28)
            self.syncStatus = "Pulled \(pulled.count) wellness samples from Garmin."
        }
    }

    func syncPullEventsFromIntervals(days: Int = 180) async {
        await runSync("Pulling calendar events from Intervals.icu...") {
            let client = try self.makeIntervalsClient()
            let end = Date()
            let start = Calendar.current.date(byAdding: .day, value: -days, to: end) ?? end
            let pulled = try await client.fetchEvents(oldest: start, newest: end).map { row -> CalendarEvent in
                var tagged = row
                if self.normalizedNonEmptyString(tagged.athleteName) == nil {
                    tagged.athleteName = self.selectedAthleteNameForWrite
                }
                return tagged
            }
            let merged = self.mergeCalendarEvents(imported: pulled)
            try self.persistCalendarEvents(merged)
            self.syncStatus = "Pulled \(pulled.count) calendar events from Intervals.icu."
        }
    }

    func syncPullEverythingFromIntervals(
        activityDays: Int = 180,
        workoutDays: Int = 120,
        wellnessDays: Int = 60,
        eventDays: Int = 180
    ) async {
        await runSync("Pulling all Intervals.icu data...") {
            let client = try self.makeIntervalsClient()
            let activityCount = try await self.pullActivitiesFromIntervals(client: client, days: activityDays)
            let workoutCount = try await self.pullWorkoutsFromIntervals(client: client, days: workoutDays)
            let wellnessCount = try await self.pullWellnessFromIntervals(client: client, days: wellnessDays)
            let eventCount = try await self.pullEventsFromIntervals(client: client, days: eventDays)
            self.syncStatus = "Intervals full pull complete. Activities \(activityCount), Workouts \(workoutCount), Wellness \(wellnessCount), Events \(eventCount)."
        }
    }

    func syncBidirectionalIntervals(
        activityDays: Int = 180,
        workoutDays: Int = 120,
        wellnessDays: Int = 60,
        eventDays: Int = 180
    ) async {
        await runSync("Bi-directional syncing with Intervals.icu...") {
            let client = try self.makeIntervalsClient()
            let pushedActivities = try await self.pushActivitiesToIntervals(client: client)
            let pushedWorkouts = try await self.pushWorkoutsToIntervals(client: client)
            let pulledActivities = try await self.pullActivitiesFromIntervals(client: client, days: activityDays)
            let pulledWorkouts = try await self.pullWorkoutsFromIntervals(client: client, days: workoutDays)
            let pulledWellness = try await self.pullWellnessFromIntervals(client: client, days: wellnessDays)
            let pulledEvents = try await self.pullEventsFromIntervals(client: client, days: eventDays)
            self.syncStatus = "Intervals bi-sync complete. Pushed A/W \(pushedActivities)/\(pushedWorkouts), Pulled A/W/Wellness/Events \(pulledActivities)/\(pulledWorkouts)/\(pulledWellness)/\(pulledEvents)."
        }
    }

    private func runSync(_ status: String, action: () async throws -> Void) async {
        let startedAt = Date()
        self.isSyncing = true
        self.syncStatus = status
        self.lastError = nil

        do {
            try await action()
            let elapsedText = String(format: "%.2f", Date().timeIntervalSince(startedAt))
            appendClientLog(level: "INFO", message: "Completed: \(status) (\(elapsedText)s)")
        } catch {
            let elapsedText = String(format: "%.2f", Date().timeIntervalSince(startedAt))
            appendClientLog(level: "ERROR", message: "Failed: \(status) (\(elapsedText)s) - \(error.localizedDescription)")
            self.lastError = error.localizedDescription
        }

        self.isSyncing = false
    }

    private func buildExternalIDIndex<T>(
        for rows: [T],
        externalID: (T) -> String?
    ) -> [String: Int] {
        var index: [String: Int] = [:]
        index.reserveCapacity(rows.count)
        for (rowIndex, row) in rows.enumerated() {
            if let ext = normalizedExternalID(externalID(row)) {
                index[ext] = rowIndex
            }
        }
        return index
    }

    private func mergeImportedRows<T>(
        existing: [T],
        imported: [T],
        externalID: (T) -> String?,
        naturalKey: (T) -> String,
        replace: (T, T) -> T
    ) -> [T] {
        var merged = existing
        var keys = Set(merged.map(naturalKey))
        var externalIndex = buildExternalIDIndex(for: merged, externalID: externalID)

        for remote in imported {
            if let ext = normalizedExternalID(externalID(remote)),
               let idx = externalIndex[ext] {
                let existingRow = merged[idx]
                let replacement = replace(existingRow, remote)
                merged[idx] = replacement

                let oldExt = normalizedExternalID(externalID(existingRow))
                let newExt = normalizedExternalID(externalID(replacement))
                if oldExt != newExt, let oldExt {
                    externalIndex.removeValue(forKey: oldExt)
                }
                if let newExt {
                    externalIndex[newExt] = idx
                }
                keys.insert(naturalKey(replacement))
                continue
            }

            let key = naturalKey(remote)
            if !keys.contains(key) {
                merged.append(remote)
                keys.insert(key)
                if let ext = normalizedExternalID(externalID(remote)) {
                    externalIndex[ext] = merged.count - 1
                }
            }
        }

        return merged
    }

    private func mergeActivities(imported: [Activity]) -> [Activity] {
        let normalizedImported = imported.map { row -> Activity in
            var tagged = row
            if normalizedNonEmptyString(tagged.athleteName) == nil {
                tagged.athleteName = selectedAthleteNameForWrite
            }
            return tagged
        }
        let merged = mergeImportedRows(
            existing: self.activities,
            imported: normalizedImported,
            externalID: { $0.externalID },
            naturalKey: { self.activityKey($0) },
            replace: { existing, remote in
                var replacement = remote
                replacement.id = existing.id
                replacement.athleteName = self.firstNonEmptyRequired(replacement.athleteName, existing.athleteName)
                replacement.sourceFileName = self.firstNonEmpty(replacement.sourceFileName, existing.sourceFileName)
                replacement.sourceFileType = self.firstNonEmpty(replacement.sourceFileType, existing.sourceFileType)
                if replacement.sourceFileBase64 == nil {
                    replacement.sourceFileBase64 = existing.sourceFileBase64
                }
                if replacement.platformPayloadJSON == nil || replacement.platformPayloadJSON?.isEmpty == true {
                    replacement.platformPayloadJSON = existing.platformPayloadJSON
                }
                return replacement
            }
        )
        return deduplicateActivities(merged)
    }

    private func persistActivities(_ rows: [Activity]) throws {
        let deduped = deduplicateActivities(rows)
        let previousByID = Dictionary(uniqueKeysWithValues: activities.map { ($0.id, $0) })
        if let repository = self.repository {
            try repository.saveActivities(deduped)
        }
        self.activities = deduped
        invalidateActivitySensorSampleCache(previousByID: previousByID, updated: deduped)
        persistActivitiesToLocalCache(deduped)
        pruneActivityMetricInsights()
    }

    private func invalidateActivitySensorSampleCache(
        previousByID: [UUID: Activity],
        updated: [Activity]
    ) {
        for activity in updated {
            guard let previous = previousByID[activity.id] else {
                ActivitySourceDataDecoder.invalidateCache(for: activity.id)
                continue
            }
            if previous.sourceFileBase64 != activity.sourceFileBase64 ||
                previous.sourceFileType != activity.sourceFileType ||
                previous.sourceFileName != activity.sourceFileName
            {
                ActivitySourceDataDecoder.invalidateCache(for: activity.id)
            }
        }
    }

    private func loadActivitiesFromLocalCache() -> [Activity]? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let fm = FileManager.default

        if let accountURL = try? activitiesLocalCacheURL(),
           fm.fileExists(atPath: accountURL.path) {
            do {
                let data = try Data(contentsOf: accountURL)
                return try decoder.decode([Activity].self, from: data)
            } catch {
                appendClientLog(
                    level: "WARN",
                    message: "Failed to decode account activity cache: \(detailedErrorDescription(error)) path=\(accountURL.path)"
                )
            }
        }

        for legacyURL in legacyActivitiesCacheCandidateURLs() where fm.fileExists(atPath: legacyURL.path) {
            do {
                let data = try Data(contentsOf: legacyURL)
                let decoded = try decoder.decode([Activity].self, from: data)
                guard !decoded.isEmpty else { continue }
                appendClientLog(
                    level: "WARN",
                    message: "Recovered \(decoded.count) activities from legacy cache path \(legacyURL.path)."
                )
                persistActivitiesToLocalCache(decoded)
                return decoded
            } catch {
                appendClientLog(
                    level: "WARN",
                    message: "Failed to decode legacy activity cache: \(detailedErrorDescription(error)) path=\(legacyURL.path)"
                )
            }
        }
        return nil
    }

    private func persistActivitiesToLocalCache(_ rows: [Activity]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]

        do {
            let targetURL = try activitiesLocalCacheURL()
            let data = try encoder.encode(rows.sorted { $0.date > $1.date })
            try data.write(to: targetURL, options: .atomic)
        } catch {
            appendClientLog(
                level: "WARN",
                message: "Failed to persist local activity cache: \(detailedErrorDescription(error))"
            )
        }
    }

    private func activitiesLocalCacheURL() throws -> URL {
        try Self.activitiesLocalCacheURL(for: currentAccountID, createDirectory: true)
    }

    private static func activitiesLocalCacheURL(for accountID: String, createDirectory: Bool) throws -> URL {
        let fm = FileManager.default
        let appSupport = try fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let accountDir = appSupport
            .appendingPathComponent("fricu", isDirectory: true)
            .appendingPathComponent("accounts", isDirectory: true)
            .appendingPathComponent(Self.sanitizeAccountIDForPath(accountID), isDirectory: true)
        if createDirectory, !fm.fileExists(atPath: accountDir.path) {
            try fm.createDirectory(at: accountDir, withIntermediateDirectories: true)
        }
        return accountDir.appendingPathComponent("activities-cache.json")
    }

    private func legacyActivitiesCacheCandidateURLs() -> [URL] {
        let fm = FileManager.default
        var urls: [URL] = []
        if let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            urls.append(
                appSupport
                    .appendingPathComponent("Fricu", isDirectory: true)
                    .appendingPathComponent("activities.json")
            )
            urls.append(
                appSupport
                    .appendingPathComponent("fricu", isDirectory: true)
                    .appendingPathComponent("activities.json")
            )
        }
        #if os(iOS)
        if let documents = fm.urls(for: .documentDirectory, in: .userDomainMask).first {
            urls.append(
                documents
                    .appendingPathComponent("Fricu", isDirectory: true)
                    .appendingPathComponent("activities.json")
            )
        }
        #endif
        return urls
    }

    private static func sanitizeAccountIDForPath(_ accountID: String) -> String {
        let mapped = accountID.map { character -> Character in
            if character.isASCII && (character.isLetter || character.isNumber || character == "-" || character == "_") {
                return character
            }
            return "_"
        }
        let text = String(mapped)
        return text.isEmpty ? "account" : text
    }

    private func deduplicateActivities(_ rows: [Activity]) -> [Activity] {
        let sorted = rows.sorted { $0.date > $1.date }
        var retained: [Activity] = []
        retained.reserveCapacity(sorted.count)
        var retainedByExternalID: [String: Int] = [:]
        var bucketToRetainedIndexes: [ActivityDedupBucket: [Int]] = [:]

        for candidate in sorted {
            if let externalID = normalizedExternalID(candidate.externalID),
               let idx = retainedByExternalID[externalID] {
                let existing = retained[idx]
                let replacement = preferredActivity(existing, candidate)
                retained[idx] = replacement
                let existingExternalID = normalizedExternalID(existing.externalID)
                let replacementExternalID = normalizedExternalID(replacement.externalID)
                if existingExternalID != replacementExternalID, let existingExternalID {
                    retainedByExternalID.removeValue(forKey: existingExternalID)
                }
                if let replacementExternalID {
                    retainedByExternalID[replacementExternalID] = idx
                }
                reindexDedupBucketIfNeeded(
                    old: existing,
                    replacement: replacement,
                    retainedIndex: idx,
                    bucketToIndexes: &bucketToRetainedIndexes
                )
                continue
            }

            if let idx = fuzzyDuplicateIndex(
                for: candidate,
                retained: retained,
                bucketToIndexes: bucketToRetainedIndexes
            ) {
                let existing = retained[idx]
                let replacement = preferredActivity(existing, candidate)
                retained[idx] = replacement
                let existingExternalID = normalizedExternalID(existing.externalID)
                let replacementExternalID = normalizedExternalID(replacement.externalID)
                if existingExternalID != replacementExternalID, let existingExternalID {
                    retainedByExternalID.removeValue(forKey: existingExternalID)
                }
                if let replacementExternalID {
                    retainedByExternalID[replacementExternalID] = idx
                }
                reindexDedupBucketIfNeeded(
                    old: existing,
                    replacement: replacement,
                    retainedIndex: idx,
                    bucketToIndexes: &bucketToRetainedIndexes
                )
            } else {
                retained.append(candidate)
                let retainedIndex = retained.count - 1
                if let externalID = normalizedExternalID(candidate.externalID) {
                    retainedByExternalID[externalID] = retainedIndex
                }
                bucketToRetainedIndexes[dedupBucket(for: candidate), default: []].append(retainedIndex)
            }
        }

        retained.sort { $0.date > $1.date }
        return retained
    }

    private struct ActivityDedupBucket: Hashable {
        let sport: SportType
        let athleteToken: String
        let timeBucket: Int
        let durationBucket: Int
    }

    private func normalizedExternalID(_ externalID: String?) -> String? {
        guard let normalized = normalizedNonEmptyString(externalID) else { return nil }
        return normalized.lowercased()
    }

    private func normalizedNonEmptyString(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }

    private func firstNonEmpty(_ preferred: String?, _ fallback: String?) -> String? {
        normalizedNonEmptyString(preferred) ?? normalizedNonEmptyString(fallback)
    }

    private func firstNonEmptyRequired(_ preferred: String, _ fallback: String) -> String {
        firstNonEmpty(preferred, fallback) ?? ""
    }

    private func athletePanelID(forName name: String?) -> String {
        _ = name
        return AthletePanel.singleID
    }

    private func athletePanelID(for activity: Activity) -> String {
        athletePanelID(forName: activity.athleteName)
    }

    private func dedupBucket(for activity: Activity) -> ActivityDedupBucket {
        let timeBucket = Int(activity.date.timeIntervalSince1970 / 300.0) // 5-minute buckets.
        let durationBucket = max(0, activity.durationSec / 120) // 2-minute buckets.
        return ActivityDedupBucket(
            sport: activity.sport,
            athleteToken: dedupAthleteToken(for: activity),
            timeBucket: timeBucket,
            durationBucket: durationBucket
        )
    }

    private func dedupAthleteToken(for activity: Activity) -> String {
        athletePanelID(for: activity)
    }

    private func fuzzyDuplicateIndex(
        for candidate: Activity,
        retained: [Activity],
        bucketToIndexes: [ActivityDedupBucket: [Int]]
    ) -> Int? {
        let base = dedupBucket(for: candidate)
        for timeOffset in -2...2 {
            for durationOffset in -1...1 {
                let bucket = ActivityDedupBucket(
                    sport: base.sport,
                    athleteToken: base.athleteToken,
                    timeBucket: base.timeBucket + timeOffset,
                    durationBucket: max(0, base.durationBucket + durationOffset)
                )
                guard let indexes = bucketToIndexes[bucket] else { continue }
                for index in indexes where retained.indices.contains(index) {
                    if isLikelyDuplicateActivity(retained[index], candidate) {
                        return index
                    }
                }
            }
        }
        return nil
    }

    private func reindexDedupBucketIfNeeded(
        old: Activity,
        replacement: Activity,
        retainedIndex: Int,
        bucketToIndexes: inout [ActivityDedupBucket: [Int]]
    ) {
        let oldBucket = dedupBucket(for: old)
        let newBucket = dedupBucket(for: replacement)
        guard oldBucket != newBucket else { return }

        if var oldIndexes = bucketToIndexes[oldBucket] {
            oldIndexes.removeAll { $0 == retainedIndex }
            if oldIndexes.isEmpty {
                bucketToIndexes.removeValue(forKey: oldBucket)
            } else {
                bucketToIndexes[oldBucket] = oldIndexes
            }
        }
        bucketToIndexes[newBucket, default: []].append(retainedIndex)
    }

    private func isLikelyDuplicateActivity(_ lhs: Activity, _ rhs: Activity) -> Bool {
        guard lhs.sport == rhs.sport else { return false }
        guard dedupAthleteToken(for: lhs) == dedupAthleteToken(for: rhs) else { return false }
        let dt = abs(lhs.date.timeIntervalSince(rhs.date))
        if dt > 8 * 60 { return false }

        let durationDelta = abs(lhs.durationSec - rhs.durationSec)
        if durationDelta > max(120, Int(Double(max(lhs.durationSec, rhs.durationSec)) * 0.05)) {
            return false
        }

        let distanceDelta = abs(lhs.distanceKm - rhs.distanceKm)
        if distanceDelta > max(0.4, max(lhs.distanceKm, rhs.distanceKm) * 0.04) {
            return false
        }

        let tssDelta = abs(lhs.tss - rhs.tss)
        if tssDelta > max(6, Int(Double(max(lhs.tss, rhs.tss)) * 0.08)) {
            return false
        }

        return true
    }

    private func preferredActivity(_ a: Activity, _ b: Activity) -> Activity {
        let scoreA = activityDataQualityScore(a)
        let scoreB = activityDataQualityScore(b)
        let preferred: Activity
        let fallback: Activity

        if scoreA == scoreB {
            let sourceRankA = activitySourceRank(a)
            let sourceRankB = activitySourceRank(b)
            if sourceRankA == sourceRankB {
                if a.date >= b.date {
                    preferred = a
                    fallback = b
                } else {
                    preferred = b
                    fallback = a
                }
            } else if sourceRankA >= sourceRankB {
                preferred = a
                fallback = b
            } else {
                preferred = b
                fallback = a
            }
        } else if scoreA >= scoreB {
            preferred = a
            fallback = b
        } else {
            preferred = b
            fallback = a
        }

        var merged = preferred
        merged.athleteName = firstNonEmptyRequired(preferred.athleteName, fallback.athleteName)
        merged.externalID = firstNonEmpty(preferred.externalID, fallback.externalID)
        merged.sourceFileName = firstNonEmpty(preferred.sourceFileName, fallback.sourceFileName)
        merged.sourceFileType = firstNonEmpty(preferred.sourceFileType, fallback.sourceFileType)
        if merged.sourceFileBase64 == nil {
            merged.sourceFileBase64 = fallback.sourceFileBase64
        }
        if merged.bikeComputerScreenshotBase64 == nil {
            merged.bikeComputerScreenshotBase64 = fallback.bikeComputerScreenshotBase64
        }
        merged.bikeComputerScreenshotFileName = firstNonEmpty(
            merged.bikeComputerScreenshotFileName,
            fallback.bikeComputerScreenshotFileName
        )
        merged.bikeComputerScreenshotMimeType = firstNonEmpty(
            merged.bikeComputerScreenshotMimeType,
            fallback.bikeComputerScreenshotMimeType
        )
        if normalizedNonEmptyString(merged.platformPayloadJSON) == nil {
            merged.platformPayloadJSON = fallback.platformPayloadJSON
        }
        if normalizedNonEmptyString(merged.notes) == nil {
            merged.notes = fallback.notes
        }
        return merged
    }

    private func activityDataQualityScore(_ activity: Activity) -> Int {
        var score = 0
        if activity.normalizedPower != nil { score += 3 }
        if activity.avgHeartRate != nil { score += 2 }
        if !activity.intervals.isEmpty { score += 2 }
        if activity.sourceFileBase64 != nil { score += 2 }
        if activity.platformPayloadJSON != nil { score += 1 }
        if let ext = activity.externalID, !ext.isEmpty { score += 1 }
        if !activity.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { score += 1 }
        return score
    }

    private func activitySourceRank(_ activity: Activity) -> Int {
        let ext = activity.externalID?.lowercased() ?? ""
        if activity.sourceFileBase64 != nil { return 4 }
        if ext.hasPrefix("garmin") { return 3 }
        if ext.hasPrefix("strava") { return 2 }
        if ext.hasPrefix("intervals") { return 1 }
        return 0
    }

    private func persistCalendarEvents(_ rows: [CalendarEvent]) throws {
        if let repository = self.repository {
            try repository.saveCalendarEvents(rows)
        }
        self.intervalsCalendarEvents = rows
    }

    private func persistWorkouts(_ rows: [PlannedWorkout]) throws {
        if let repository = self.repository {
            try repository.saveWorkouts(rows)
        }
        self.plannedWorkouts = rows
    }

    private func persistDailyMealPlans(_ rows: [DailyMealPlan]) throws {
        if let repository = self.repository {
            try repository.saveDailyMealPlans(rows)
        }
        self.dailyMealPlans = rows
    }

    private func persistWellnessSamples(_ rows: [WellnessSample]) throws {
        let sorted = rows.sorted { $0.date > $1.date }
        if let repository = self.repository {
            try repository.saveWellnessSamples(sorted)
        }
        self.wellnessSamples = sorted
        appendClientLog(level: "INFO", message: "Persisted wellness samples: \(sorted.count)")
    }

    private func persistCustomFoodLibrary(_ rows: [CustomFoodLibraryItem]) throws {
        if let repository = self.repository {
            try repository.saveCustomFoods(rows)
        }
        self.customFoodLibrary = rows
    }

    private func mergeWorkouts(imported: [PlannedWorkout]) -> [PlannedWorkout] {
        var merged = mergeImportedRows(
            existing: self.plannedWorkouts,
            imported: imported,
            externalID: { $0.externalID },
            naturalKey: { workoutNaturalKey($0) },
            replace: { existing, remote in
                var replacement = remote
                replacement.id = existing.id
                replacement.athleteName = self.firstNonEmptyRequired(replacement.athleteName, existing.athleteName)
                return replacement
            }
        )
        merged.sort { $0.createdAt > $1.createdAt }
        return merged
    }

    private func workoutNaturalKey(_ workout: PlannedWorkout) -> String {
        let day = Calendar.current.startOfDay(for: workout.createdAt).timeIntervalSince1970
        let athlete = athletePanelID(forName: workout.athleteName)
        return "\(Int(day))|\(workout.sport.rawValue)|\(workout.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())|\(workout.totalMinutes)|\(athlete)"
    }

    private func normalizeWorkoutExternalIDs(_ rows: [PlannedWorkout]) -> [PlannedWorkout] {
        var updated = rows
        for idx in updated.indices where updated[idx].externalID == nil {
            updated[idx].externalID = "fricu-workout-\(updated[idx].id.uuidString)"
        }
        return updated
    }

    private func applyWellnessSamples(
        _ samples: [WellnessSample],
        mergeWithExisting: Bool,
        baselineWindowDays: Int
    ) throws {
        let taggedIncoming = samples.map { sample -> WellnessSample in
            var tagged = sample
            if normalizedNonEmptyString(tagged.athleteName) == nil {
                tagged.athleteName = selectedAthleteNameForWrite
            }
            return tagged
        }

        let normalized: [WellnessSample]
        if mergeWithExisting {
            normalized = mergeWellnessSamples(self.wellnessSamples + taggedIncoming)
        } else {
            let currentAthletePanelID = athletePanelID(forName: selectedAthleteNameForWrite)
            let retainedOthers = self.wellnessSamples.filter {
                athletePanelID(forName: $0.athleteName) != currentAthletePanelID
            }
            normalized = mergeWellnessSamples(retainedOthers + taggedIncoming)
        }
        try persistWellnessSamples(normalized)

        let scoped = normalized
        if let latestHRV = scoped.first(where: { $0.hrv != nil })?.hrv {
            self.profile.hrvToday = latestHRV
        }

        let baselineCandidates = Array(scoped.prefix(max(1, baselineWindowDays))).compactMap { $0.hrv }
        if !baselineCandidates.isEmpty {
            self.profile.hrvBaseline = baselineCandidates.reduce(0, +) / Double(baselineCandidates.count)
        }

        if let repository = self.repository {
            try repository.saveProfile(self.profile)
        }
    }

    private func mergeCalendarEvents(imported: [CalendarEvent]) -> [CalendarEvent] {
        var merged = mergeImportedRows(
            existing: self.intervalsCalendarEvents,
            imported: imported,
            externalID: { $0.externalID },
            naturalKey: { self.calendarEventKey($0) },
            replace: { existing, remote in
                var replacement = remote
                replacement.id = existing.id
                replacement.athleteName = self.firstNonEmptyRequired(replacement.athleteName, existing.athleteName)
                return replacement
            }
        )
        merged.sort { $0.startDate > $1.startDate }
        return merged
    }

    private func pullActivitiesFromIntervals(client: IntervalsAPIClient, days: Int) async throws -> Int {
        let end = Date()
        let start = Calendar.current.date(byAdding: .day, value: -days, to: end) ?? end
        let pulled = try await client.fetchActivities(oldest: start, newest: end, profile: self.profile)
        let merged = self.mergeActivities(imported: pulled)
        try self.persistActivities(merged)
        return pulled.count
    }

    private func pullWorkoutsFromIntervals(client: IntervalsAPIClient, days: Int) async throws -> Int {
        let end = Date()
        let start = Calendar.current.date(byAdding: .day, value: -days, to: end) ?? end
        let pulled = try await client.fetchWorkouts(oldest: start, newest: end).map { row -> PlannedWorkout in
            var tagged = row
            if normalizedNonEmptyString(tagged.athleteName) == nil {
                tagged.athleteName = selectedAthleteNameForWrite
            }
            return tagged
        }
        let merged = self.mergeWorkouts(imported: pulled)
        try self.persistWorkouts(merged)
        return pulled.count
    }

    private func pullWellnessFromIntervals(client: IntervalsAPIClient, days: Int) async throws -> Int {
        let end = Date()
        let start = Calendar.current.date(byAdding: .day, value: -days, to: end) ?? end
        let wellness = try await client.fetchWellness(oldest: start, newest: end)
        try self.applyWellnessSamples(wellness, mergeWithExisting: false, baselineWindowDays: days)
        return wellness.count
    }

    private func pullEventsFromIntervals(client: IntervalsAPIClient, days: Int) async throws -> Int {
        let end = Date()
        let start = Calendar.current.date(byAdding: .day, value: -days, to: end) ?? end
        let pulled = try await client.fetchEvents(oldest: start, newest: end).map { row -> CalendarEvent in
            var tagged = row
            if normalizedNonEmptyString(tagged.athleteName) == nil {
                tagged.athleteName = selectedAthleteNameForWrite
            }
            return tagged
        }
        let merged = self.mergeCalendarEvents(imported: pulled)
        try self.persistCalendarEvents(merged)
        return pulled.count
    }

    private func pushActivitiesToIntervals(client: IntervalsAPIClient) async throws -> Int {
        var updated = self.activities
        var pushedCount = 0

        for index in updated.indices {
            if updated[index].externalID?.hasPrefix("intervals:") == true {
                continue
            }

            let external = try await client.uploadActivity(updated[index])
            updated[index].externalID = external
            pushedCount += 1
        }

        try self.persistActivities(updated)
        return pushedCount
    }

    private func pushWorkoutsToIntervals(client: IntervalsAPIClient) async throws -> Int {
        let scoped = self.athleteScopedPlannedWorkouts
        try await client.upsertWorkouts(scoped)
        var updated = self.plannedWorkouts
        let scopedIDs = Set(scoped.map(\.id))
        for index in updated.indices where scopedIDs.contains(updated[index].id) {
            if updated[index].externalID == nil {
                updated[index].externalID = "fricu-workout-\(updated[index].id.uuidString)"
            }
        }
        try self.persistWorkouts(updated)
        return scoped.count
    }

    private func applyStravaAuthUpdate(_ auth: StravaAuthUpdate) {
        self.profile.stravaAccessToken = auth.accessToken
        if !auth.refreshToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            self.profile.stravaRefreshToken = auth.refreshToken
        }
        self.profile.stravaAccessTokenExpiresAt = auth.expiresAt
        self.persistProfile()
    }

    private func norwegianDoubleThresholdSessions(for sport: SportType) -> [(name: String, segments: [WorkoutSegment])] {
        switch sport {
        case .cycling:
            return [
                (
                    name: "Norwegian Double Threshold AM (Bike)",
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
                (
                    name: "Norwegian Double Threshold PM (Bike)",
                    segments: [
                        WorkoutSegment(minutes: 15, intensityPercentFTP: 58, note: "Warm-up"),
                        WorkoutSegment(minutes: 10, intensityPercentFTP: 92, note: "LT Block #1"),
                        WorkoutSegment(minutes: 3, intensityPercentFTP: 55, note: "Recover"),
                        WorkoutSegment(minutes: 10, intensityPercentFTP: 92, note: "LT Block #2"),
                        WorkoutSegment(minutes: 3, intensityPercentFTP: 55, note: "Recover"),
                        WorkoutSegment(minutes: 10, intensityPercentFTP: 92, note: "LT Block #3"),
                        WorkoutSegment(minutes: 10, intensityPercentFTP: 50, note: "Cool-down")
                    ]
                )
            ]
        case .running:
            return [
                (
                    name: "Norwegian Double Threshold AM (Run)",
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
                (
                    name: "Norwegian Double Threshold PM (Run)",
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
        case .swimming, .strength:
            return []
        }
    }

    private func applyDefaultCredentialsIfNeeded() {
        var updated = profile
        let defaults = AthleteProfile.default
        var changed = false

        if updated.openAIAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            updated.openAIAPIKey = defaults.openAIAPIKey
            changed = true
        }

        if changed {
            profile = updated
            persistProfile()
        }
    }

    private func buildGPTCoachInput() -> GPTCoachInput {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]

        let summary = self.summary
        let latestWellnessHRV = athleteScopedWellnessSamples.sortedByDateDescending().latestValue(\.hrv) ?? profile.hrvToday
        let recentLoadPoints = loadSeries.suffix(28).map { point in
            GPTCoachInput.LoadPoint(
                date: IntervalsDateFormatter.day.string(from: point.date),
                tss: point.tss,
                ctl: point.ctl,
                atl: point.atl,
                tsb: point.tsb
            )
        }

        let recentActivityPoints = filteredActivities.prefix(14).map { activity in
            GPTCoachInput.ActivityPoint(
                date: iso.string(from: activity.date),
                sport: activity.sport.label,
                durationMinutes: max(1, activity.durationSec / 60),
                distanceKm: activity.distanceKm,
                tss: activity.tss,
                normalizedPower: activity.normalizedPower,
                avgHeartRate: activity.avgHeartRate,
                notes: activity.notes
            )
        }

        let upcoming = athleteScopedPlannedWorkouts
            .filter { $0.scheduledDate != nil }
            .sorted { ($0.scheduledDate ?? $0.createdAt) < ($1.scheduledDate ?? $1.createdAt) }
            .prefix(10)
            .map { workout in
                GPTCoachInput.PlannedWorkoutPoint(
                    date: iso.string(from: workout.scheduledDate ?? workout.createdAt),
                    sport: workout.sport.label,
                    name: workout.name,
                    totalMinutes: workout.totalMinutes,
                    segmentCount: workout.segments.count
                )
            }

        return GPTCoachInput(
            now: iso.string(from: Date()),
            summary: GPTCoachInput.Summary(
                weeklyTSS: summary.weeklyTSS,
                monthlyDistanceKm: summary.monthlyDistanceKm,
                ctl: summary.currentCTL,
                atl: summary.currentATL,
                tsb: summary.currentTSB
            ),
            profile: GPTCoachInput.ProfileContext(
                athleteAgeYears: profile.athleteAgeYears,
                athleteWeightKg: profile.athleteWeightKg,
                cyclingFTPWatts: profile.cyclingFTPWatts,
                runningFTPWatts: profile.runningFTPWatts,
                swimmingFTPWatts: profile.swimmingFTPWatts,
                strengthFTPWatts: profile.strengthFTPWatts,
                cyclingThresholdHeartRate: profile.cyclingThresholdHeartRate,
                runningThresholdHeartRate: profile.runningThresholdHeartRate,
                swimmingThresholdHeartRate: profile.swimmingThresholdHeartRate,
                strengthThresholdHeartRate: profile.strengthThresholdHeartRate,
                hrvBaseline: profile.hrvBaseline,
                hrvToday: latestWellnessHRV,
                goalRaceDate: profile.goalRaceDate.map { IntervalsDateFormatter.day.string(from: $0) }
            ),
            recentLoad: recentLoadPoints,
            recentActivities: Array(recentActivityPoints),
            upcomingWorkouts: Array(upcoming)
        )
    }

    private func activityInsightLoadPoint(for activity: Activity) -> DailyLoadPoint? {
        let calendar = Calendar.current
        let targetDay = calendar.startOfDay(for: activity.date)
        let sportRows = activities.filter { $0.sport == activity.sport }
        guard !sportRows.isEmpty else { return nil }
        let seriesDays = Self.dynamicLoadSeriesDaysForCompute(for: sportRows)
        let series = LoadCalculator.buildSeries(activities: sportRows, profile: profile, days: seriesDays)
        return series.first { calendar.isDate($0.date, inSameDayAs: targetDay) }
    }

    private func buildActivityMetricInsightInput(_ activity: Activity) -> ActivityMetricInsightInput {
        let dayLoad = activityInsightLoadPoint(for: activity)
        let ftp = max(1, profile.ftpWatts(for: activity.sport))
        let thresholdHR = max(1, profile.thresholdHeartRate(for: activity.sport, on: activity.date))
        let intensityFactor = activity.normalizedPower.map { Double($0) / Double(ftp) }
        let tssPerHour = Double(activity.tss) / max(Double(activity.durationSec) / 3600.0, 1.0 / 60.0)
        let split = LoadCalculator.estimateTISSSplit(activity: activity, profile: profile)

        return ActivityMetricInsightInput(
            date: IntervalsDateFormatter.day.string(from: activity.date),
            sport: activity.sport.label,
            durationMinutes: max(1, activity.durationSec / 60),
            distanceKm: activity.distanceKm,
            tss: activity.tss,
            normalizedPower: activity.normalizedPower,
            avgHeartRate: activity.avgHeartRate,
            ftp: ftp,
            thresholdHeartRate: thresholdHR,
            intensityFactor: intensityFactor,
            tssPerHour: tssPerHour,
            ctl: dayLoad?.ctl,
            atl: dayLoad?.atl,
            tsb: dayLoad?.tsb,
            aerobicTISS: split.aerobic,
            anaerobicTISS: split.anaerobic,
            notes: activity.notes
        )
    }

    private func activityInsightFingerprint(_ activity: Activity) -> String {
        let input = buildActivityMetricInsightInput(activity)
        let intervalSignature = activity.intervals
            .map { "\($0.name)|\($0.durationSec)|\($0.targetPower ?? -1)|\($0.actualPower ?? -1)" }
            .joined(separator: ";")

        let ctlText = input.ctl.map { String(format: "%.3f", $0) } ?? "-"
        let atlText = input.atl.map { String(format: "%.3f", $0) } ?? "-"
        let tsbText = input.tsb.map { String(format: "%.3f", $0) } ?? "-"
        let aerobicText = input.aerobicTISS.map { String(format: "%.3f", $0) } ?? "-"
        let anaerobicText = input.anaerobicTISS.map { String(format: "%.3f", $0) } ?? "-"
        let intensityText = input.intensityFactor.map { String(format: "%.5f", $0) } ?? "-"

        return [
            "v1",
            input.date,
            activity.sport.rawValue,
            "\(activity.durationSec)",
            String(format: "%.3f", activity.distanceKm),
            "\(activity.tss)",
            "\(activity.normalizedPower ?? -1)",
            "\(activity.avgHeartRate ?? -1)",
            "\(input.ftp)",
            "\(input.thresholdHeartRate)",
            String(format: "%.4f", input.tssPerHour),
            intensityText,
            ctlText,
            atlText,
            tsbText,
            aerobicText,
            anaerobicText,
            intervalSignature,
            activity.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        ].joined(separator: "|")
    }

    private func persistActivityMetricInsights() throws {
        if let repository = self.repository {
            let rows = activityMetricInsightsCache.values.sorted { lhs, rhs in
                if lhs.activityDate != rhs.activityDate {
                    return lhs.activityDate > rhs.activityDate
                }
                return lhs.generatedAt > rhs.generatedAt
            }
            try repository.saveActivityMetricInsights(rows)
        }
    }

    private func pruneActivityMetricInsights() {
        let validIDs = Set(activities.map(\.id))
        let pruned = activityMetricInsightsCache.filter { validIDs.contains($0.key) }
        guard pruned.count != activityMetricInsightsCache.count else { return }
        activityMetricInsightsCache = pruned
        do {
            try persistActivityMetricInsights()
        } catch {
            lastError = "Failed to prune cached activity GPT insights: \(error.localizedDescription)"
        }
    }

    private func makeIntervalsClient() throws -> IntervalsAPIClient {
        let key = profile.intervalsAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            throw IntervalsAPIError.missingAPIKey
        }
        return IntervalsAPIClient(apiKey: key)
    }

    private func activityKey(_ activity: Activity) -> String {
        let day = Calendar.current.startOfDay(for: activity.date).timeIntervalSince1970
        let athlete = dedupAthleteToken(for: activity)
        return "\(Int(day))-\(activity.sport.rawValue)-\(athlete)-\(activity.durationSec)-\(activity.tss)-\(Int(activity.distanceKm * 100))"
    }

    private func calendarEventKey(_ event: CalendarEvent) -> String {
        let day = Calendar.current.startOfDay(for: event.startDate).timeIntervalSince1970
        let athlete = athletePanelID(forName: event.athleteName)
        return "\(Int(day))-\(event.category)-\(event.type)-\(event.name)-\(athlete)"
    }

    private func activitiesFingerprint(_ activities: [Activity]) -> Int {
        var hasher = Hasher()
        hasher.combine(activities.count)
        for activity in activities {
            hasher.combine(activity.id)
            hasher.combine(activity.date.timeIntervalSinceReferenceDate)
            hasher.combine(activity.sport.rawValue)
            hasher.combine(activity.durationSec)
            hasher.combine(activity.distanceKm)
            hasher.combine(activity.tss)
            hasher.combine(activity.normalizedPower ?? -1)
            hasher.combine(activity.avgHeartRate ?? -1)
            hasher.combine(normalizedNonEmptyString(activity.athleteName)?.lowercased() ?? "")
        }
        return hasher.finalize()
    }

    private func wellnessFingerprint(_ samples: [WellnessSample]) -> Int {
        var hasher = Hasher()
        hasher.combine(samples.count)
        for sample in samples {
            hasher.combine(sample.date.timeIntervalSinceReferenceDate)
            hasher.combine(athletePanelID(forName: sample.athleteName))
            hasher.combine(sample.hrv ?? -1)
            hasher.combine(sample.restingHR ?? -1)
            hasher.combine(sample.sleepHours ?? -1)
            hasher.combine(sample.sleepScore ?? -1)
            hasher.combine(sample.weightKg ?? -1)
        }
        return hasher.finalize()
    }

    private func workoutsFingerprint(_ workouts: [PlannedWorkout]) -> Int {
        var hasher = Hasher()
        hasher.combine(workouts.count)
        for workout in workouts {
            hasher.combine(workout.id)
            hasher.combine(workout.createdAt.timeIntervalSinceReferenceDate)
            hasher.combine(workout.sport.rawValue)
            hasher.combine(workout.name)
            hasher.combine(workout.totalMinutes)
            hasher.combine(workout.scheduledDate?.timeIntervalSinceReferenceDate ?? -1)
            hasher.combine(athletePanelID(forName: workout.athleteName))
        }
        return hasher.finalize()
    }

    private func mealPlansFingerprint(_ plans: [DailyMealPlan]) -> Int {
        var hasher = Hasher()
        hasher.combine(plans.count)
        for plan in plans {
            hasher.combine(plan.id)
            hasher.combine(plan.date.timeIntervalSinceReferenceDate)
            hasher.combine(athletePanelID(forName: plan.athleteName))
            hasher.combine(plan.hydrationTargetLiters)
            hasher.combine(plan.hydrationActualLiters)
            hasher.combine(plan.goalProfile.rawValue)
            hasher.combine(plan.notes)
            hasher.combine(plan.mealTargets.count)
            for target in plan.mainMealTargets {
                hasher.combine(target.id)
                hasher.combine(target.slot.rawValue)
                hasher.combine(target.calories)
                hasher.combine(target.protein)
                hasher.combine(target.carbs)
                hasher.combine(target.fat)
            }
            hasher.combine(plan.fridgeItems.count)
            for fridge in plan.fridgeItems {
                hasher.combine(fridge.id)
                hasher.combine(fridge.foodCode)
                hasher.combine(fridge.foodName)
                hasher.combine(fridge.servings)
                hasher.combine(fridge.servingLabel ?? "")
                hasher.combine(fridge.caloriesPerServing ?? -1)
                hasher.combine(fridge.proteinPerServing ?? -1)
                hasher.combine(fridge.carbsPerServing ?? -1)
                hasher.combine(fridge.fatPerServing ?? -1)
                hasher.combine(fridge.source ?? "")
            }
            hasher.combine(plan.items.count)
            for item in plan.items {
                hasher.combine(item.id)
                hasher.combine(item.slot.rawValue)
                hasher.combine(item.plannedFood)
                hasher.combine(item.actualFood)
                hasher.combine(item.plannedCalories)
                hasher.combine(item.actualCalories)
                hasher.combine(item.plannedProtein)
                hasher.combine(item.actualProtein)
                hasher.combine(item.plannedCarbs)
                hasher.combine(item.actualCarbs)
                hasher.combine(item.plannedFat)
                hasher.combine(item.actualFat)
            }
        }
        return hasher.finalize()
    }

    private func calendarEventsFingerprint(_ events: [CalendarEvent]) -> Int {
        var hasher = Hasher()
        hasher.combine(events.count)
        for event in events {
            hasher.combine(event.id)
            hasher.combine(event.startDate.timeIntervalSinceReferenceDate)
            hasher.combine(event.endDate?.timeIntervalSinceReferenceDate ?? -1)
            hasher.combine(event.type)
            hasher.combine(event.category)
            hasher.combine(event.name)
            hasher.combine(athletePanelID(forName: event.athleteName))
        }
        return hasher.finalize()
    }

    private func derivedProfileFingerprint(_ profile: AthleteProfile) -> Int {
        var hasher = Hasher()
        hasher.combine(profile.ftpWatts)
        hasher.combine(profile.thresholdHeartRate)
        hasher.combine(profile.cyclingFTPWatts)
        hasher.combine(profile.runningFTPWatts)
        hasher.combine(profile.swimmingFTPWatts)
        hasher.combine(profile.strengthFTPWatts)
        hasher.combine(profile.cyclingThresholdHeartRate)
        hasher.combine(profile.runningThresholdHeartRate)
        hasher.combine(profile.swimmingThresholdHeartRate)
        hasher.combine(profile.strengthThresholdHeartRate)
        hasher.combine(profile.cyclingMaxHeartRate)
        hasher.combine(profile.runningMaxHeartRate)
        hasher.combine(profile.swimmingMaxHeartRate)
        hasher.combine(profile.strengthMaxHeartRate)
        hasher.combine(profile.athleteAgeYears)
        hasher.combine(profile.athleteWeightKg)
        hasher.combine(profile.hrvBaseline)
        hasher.combine(profile.hrvToday)
        hasher.combine(profile.goalRaceDate?.timeIntervalSinceReferenceDate ?? -1)
        hasher.combine(profile.hrThresholdRanges.count)
        for range in profile.hrThresholdRanges.sorted(by: { $0.startDate < $1.startDate }) {
            hasher.combine(range.sport.rawValue)
            hasher.combine(range.startDate.timeIntervalSinceReferenceDate)
            hasher.combine(range.endDate?.timeIntervalSinceReferenceDate ?? -1)
            hasher.combine(range.lthr)
            hasher.combine(range.aeTHR ?? -1)
            hasher.combine(range.restingHR ?? -1)
            hasher.combine(range.maxHR ?? -1)
        }
        return hasher.finalize()
    }

    private func setupDerivedRefreshPipeline() {
        let refreshSignals: [AnyPublisher<Void, Never>] = [
            $activities
                .map { [weak self] in self?.activitiesFingerprint($0) ?? 0 }
                .removeDuplicates()
                .map { _ in () }
                .eraseToAnyPublisher(),
            NotificationCenter.default
                .publisher(for: UserDefaults.didChangeNotification)
                .map { _ in
                    UserDefaults.standard.string(forKey: AppLanguageOption.storageKey) ?? AppLanguageOption.system.rawValue
                }
                .removeDuplicates()
                .map { _ in () }
                .eraseToAnyPublisher(),
            $selectedSportFilter
                .removeDuplicates()
                .map { _ in () }
                .eraseToAnyPublisher(),
            $selectedAthletePanelID
                .removeDuplicates()
                .map { _ in () }
                .eraseToAnyPublisher(),
            $profile
                .map { [weak self] in self?.derivedProfileFingerprint($0) ?? 0 }
                .removeDuplicates()
                .map { _ in () }
                .eraseToAnyPublisher(),
            $selectedScenario
                .removeDuplicates()
                .map { _ in () }
                .eraseToAnyPublisher(),
            $selectedEnduranceFocus
                .removeDuplicates()
                .map { _ in () }
                .eraseToAnyPublisher(),
            $wellnessSamples
                .map { [weak self] in self?.wellnessFingerprint($0) ?? 0 }
                .removeDuplicates()
                .map { _ in () }
                .eraseToAnyPublisher(),
            $plannedWorkouts
                .map { [weak self] in self?.workoutsFingerprint($0) ?? 0 }
                .removeDuplicates()
                .map { _ in () }
                .eraseToAnyPublisher(),
            $dailyMealPlans
                .map { [weak self] in self?.mealPlansFingerprint($0) ?? 0 }
                .removeDuplicates()
                .map { _ in () }
                .eraseToAnyPublisher(),
            $intervalsCalendarEvents
                .map { [weak self] in self?.calendarEventsFingerprint($0) ?? 0 }
                .removeDuplicates()
                .map { _ in () }
                .eraseToAnyPublisher(),
            $trainerRiderSessions
                .map { rows in rows.map { "\($0.id.uuidString)|\($0.name)" }.joined(separator: ";") }
                .removeDuplicates()
                .map { _ in () }
                .eraseToAnyPublisher()
        ]

        Publishers.MergeMany(refreshSignals)
            .sink { [weak self] in
                self?.markDerivedStateDirty()
            }
            .store(in: &cancellables)
    }

    private func setupAppSettingsSyncPipeline() {
        NotificationCenter.default
            .publisher(for: UserDefaults.didChangeNotification)
            .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.persistAppSettingsToRepository(reason: "UserDefaults.didChangeNotification")
            }
            .store(in: &cancellables)
    }

    private func markDerivedStateDirty() {
        derivedRefreshToken &+= 1
        scheduleDerivedRefresh()
    }

    private func scheduleDerivedRefresh() {
        let token = derivedRefreshToken
        derivedRefreshWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard token == self.derivedRefreshToken else { return }
            self.recomputeDerivedCaches()
        }
        derivedRefreshWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: workItem)
    }

    private struct DerivedComputationSnapshot {
        let activities: [Activity]
        let dailyMealPlans: [DailyMealPlan]
        let plannedWorkouts: [PlannedWorkout]
        let wellnessSamples: [WellnessSample]
        let intervalsCalendarEvents: [CalendarEvent]
        let selectedAthletePanelID: String
        let selectedSportFilter: SportType?
        let selectedScenario: TrainingScenario
        let selectedEnduranceFocus: EnduranceFocus
        let profile: AthleteProfile
        let recommendation: AIRecommendation?
    }

    private struct DerivedComputationResult {
        let athleteScopedActivities: [Activity]
        let athleteScopedDailyMealPlans: [DailyMealPlan]
        let athleteScopedPlannedWorkouts: [PlannedWorkout]
        let athleteScopedWellnessSamples: [WellnessSample]
        let athleteScopedCalendarEvents: [CalendarEvent]
        let filteredActivities: [Activity]
        let loadSeries: [DailyLoadPoint]
        let summary: DashboardSummary
        let metricStories: [MetricStory]
        let scenarioMetricPack: ScenarioMetricPack
    }

    nonisolated private static func dynamicLoadSeriesDaysForCompute(for activities: [Activity]) -> Int {
        guard let oldest = activities.map(\.date).min() else { return 120 }
        let span = Calendar.current.dateComponents([.day], from: oldest, to: Date()).day ?? 120
        return min(1460, max(120, span + 14))
    }

    nonisolated private static func buildDerivedComputationResult(
        from snapshot: DerivedComputationSnapshot
    ) -> DerivedComputationResult {
        let filterByAthlete = snapshot.selectedAthletePanelID != AthletePanel.allID
        let athleteScopedActivities = snapshot.activities
            .filter { !filterByAthlete || AthleteIdentityNormalizer.panelID(from: $0.athleteName) == snapshot.selectedAthletePanelID }
            .sorted { $0.date > $1.date }

        let athleteScopedDailyMealPlans = snapshot.dailyMealPlans
            .filter { !filterByAthlete || AthleteIdentityNormalizer.panelID(from: $0.athleteName) == snapshot.selectedAthletePanelID }
            .sorted { $0.date > $1.date }

        let athleteScopedPlannedWorkouts = snapshot.plannedWorkouts
            .filter { !filterByAthlete || AthleteIdentityNormalizer.panelID(from: $0.athleteName) == snapshot.selectedAthletePanelID }
            .sorted { $0.createdAt > $1.createdAt }

        let athleteScopedWellnessSamples = snapshot.wellnessSamples
            .filter { !filterByAthlete || AthleteIdentityNormalizer.panelID(from: $0.athleteName) == snapshot.selectedAthletePanelID }
            .sorted { $0.date > $1.date }

        let athleteScopedCalendarEvents = snapshot.intervalsCalendarEvents
            .filter { !filterByAthlete || AthleteIdentityNormalizer.panelID(from: $0.athleteName) == snapshot.selectedAthletePanelID }
            .sorted { $0.startDate > $1.startDate }

        let filteredActivities: [Activity]
        if let sport = snapshot.selectedSportFilter {
            filteredActivities = athleteScopedActivities.filter { $0.sport == sport }
        } else {
            filteredActivities = athleteScopedActivities
        }

        let seriesDays = dynamicLoadSeriesDaysForCompute(for: filteredActivities)
        let loadSeries = LoadCalculator.buildSeries(
            activities: filteredActivities,
            profile: snapshot.profile,
            days: seriesDays
        )
        let summary = LoadCalculator.summary(activities: filteredActivities, series: loadSeries)

        var metricStories: [MetricStory] = []
        var scenarioMetricPack = ScenarioMetricPack(
            scenario: snapshot.selectedScenario,
            headline: "",
            items: [],
            actions: []
        )

        let group = DispatchGroup()
        let lock = NSLock()

        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            let stories = MetricStoryEngine.buildStories(
                summary: summary,
                loadSeries: loadSeries,
                activities: filteredActivities,
                recommendation: snapshot.recommendation,
                profile: snapshot.profile,
                wellness: athleteScopedWellnessSamples
            )
            lock.lock()
            metricStories = stories
            lock.unlock()
            group.leave()
        }

        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            let pack = ScenarioMetricEngine.build(
                scenario: snapshot.selectedScenario,
                summary: summary,
                loadSeries: loadSeries,
                activities: filteredActivities,
                wellness: athleteScopedWellnessSamples,
                profile: snapshot.profile,
                enduranceFocus: snapshot.selectedEnduranceFocus
            )
            lock.lock()
            scenarioMetricPack = pack
            lock.unlock()
            group.leave()
        }

        group.wait()

        return DerivedComputationResult(
            athleteScopedActivities: athleteScopedActivities,
            athleteScopedDailyMealPlans: athleteScopedDailyMealPlans,
            athleteScopedPlannedWorkouts: athleteScopedPlannedWorkouts,
            athleteScopedWellnessSamples: athleteScopedWellnessSamples,
            athleteScopedCalendarEvents: athleteScopedCalendarEvents,
            filteredActivities: filteredActivities,
            loadSeries: loadSeries,
            summary: summary,
            metricStories: metricStories,
            scenarioMetricPack: scenarioMetricPack
        )
    }

    private func recomputeDerivedCaches() {
        refreshAthletePanelsAndSelection(preferSpecificSelection: false)

        let snapshot = DerivedComputationSnapshot(
            activities: activities,
            dailyMealPlans: dailyMealPlans,
            plannedWorkouts: plannedWorkouts,
            wellnessSamples: wellnessSamples,
            intervalsCalendarEvents: intervalsCalendarEvents,
            selectedAthletePanelID: selectedAthletePanelID,
            selectedSportFilter: selectedSportFilter,
            selectedScenario: selectedScenario,
            selectedEnduranceFocus: selectedEnduranceFocus,
            profile: profile,
            recommendation: gptRecommendation
        )

        derivedComputationGeneration &+= 1
        let generation = derivedComputationGeneration
        let queue = derivedComputationQueue

        queue.async { [snapshot] in
            let result = Self.buildDerivedComputationResult(from: snapshot)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                guard generation == self.derivedComputationGeneration else { return }
                self.athleteScopedActivitiesCache = result.athleteScopedActivities
                self.athleteScopedDailyMealPlansCache = result.athleteScopedDailyMealPlans
                self.athleteScopedPlannedWorkoutsCache = result.athleteScopedPlannedWorkouts
                self.athleteScopedWellnessSamplesCache = result.athleteScopedWellnessSamples
                self.athleteScopedCalendarEventsCache = result.athleteScopedCalendarEvents
                self.filteredActivitiesCache = result.filteredActivities
                self.loadSeriesCache = result.loadSeries
                self.summaryCache = result.summary
                self.metricStoriesCache = result.metricStories
                self.scenarioMetricPackCache = result.scenarioMetricPack
            }
        }
    }
}

#if canImport(SwiftUI) && canImport(AppKit)
struct TrainerBikeComputerSnapshotPayload {
    let riderName: String
    let startDate: Date
    let endDate: Date
    let elapsedSec: Int
    let movingSec: Int
    let latestPower: Int?
    let maxPower: Int?
    let latestHeartRate: Int?
    let maxHeartRate: Int?
    let latestCadence: Int?
    let averagePower: Int?
    let normalizedPower: Int?
    let power5s: Double?
    let power30s: Double?
    let power1m: Double?
    let power20m: Double?
    let power60m: Double?
    let averageHeartRate: Int?
    let maxHeartRateForZones: Int
    let averageCadence: Int?
    let latestSpeedKPH: Double?
    let averageSpeedKPH: Double?
    let maxSpeedKPH: Double?
    let distanceKm: Double
    let estimatedCaloriesKCal: Double?
    let balanceLeftPercent: Double?
    let balanceRightPercent: Double?
    let powerZoneSec: [Int]
    let heartRateZoneSec: [Int]
    let powerTrace: [Double]
    let heartRateTrace: [Double]
    let cadenceTrace: [Double]
}

private struct TrainerBikeComputerSnapshotView: View {
    let payload: TrainerBikeComputerSnapshotPayload

    var body: some View {
        BikeComputerLightDashboardView(
            model: payload.lightDashboardModel(
                title: "Fricu 实时码表截图",
                subtitle: "\(payload.riderName) · \(IntervalsDateFormatter.dateTimeLocal.string(from: payload.startDate))",
                alerts: []
            )
        )
        .frame(width: 1280, height: 720, alignment: .topLeading)
    }
}

extension AppStore {
    static func renderTrainerBikeComputerSnapshot(payload: TrainerBikeComputerSnapshotPayload) -> Data? {
        let renderer = ImageRenderer(content: TrainerBikeComputerSnapshotView(payload: payload))
        renderer.proposedSize = ProposedViewSize(width: 1280, height: 720)
        renderer.scale = 2

        if let cgImage = renderer.cgImage {
            let bitmap = NSBitmapImageRep(cgImage: cgImage)
            return bitmap.representation(using: .png, properties: [:])
        }

        if let nsImage = renderer.nsImage,
           let tiff = nsImage.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiff),
           let png = bitmap.representation(using: .png, properties: [:]) {
            return png
        }
        return nil
    }
}
#endif
