import Foundation
import Combine

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
    var sampleCount: Int = 0
    var elevationGainMeters: Double = 0
    var lastFitPath: String?
    var lastSyncSummary: String?
}

private struct TrainerRiderConnectionMemory: Codable {
    var id: UUID
    var name: String
    var preferredTrainerDeviceID: UUID?
    var preferredHeartRateDeviceID: UUID?
    var preferredPowerMeterDeviceID: UUID?
    var appearance: TrainerRiderAppearance?
}

private struct TrainerRiderConnectionStore: Codable {
    var primarySessionID: UUID?
    var riders: [TrainerRiderConnectionMemory]
}

struct AthletePanel: Identifiable, Hashable {
    static let allID = "__athlete_all__"
    static let unknownAthleteToken = "__default_athlete__"

    let id: String
    let title: String
    let count: Int
    let isAll: Bool
}

@MainActor
final class AppStore: ObservableObject {
    @Published private(set) var activities: [Activity] = []
    @Published private(set) var dailyMealPlans: [DailyMealPlan] = []
    @Published private(set) var customFoodLibrary: [CustomFoodLibraryItem] = []
    @Published private(set) var plannedWorkouts: [PlannedWorkout] = []
    @Published private(set) var wellnessSamples: [WellnessSample] = []
    @Published private(set) var intervalsCalendarEvents: [CalendarEvent] = []
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

    @Published var selectedAthletePanelID: String = AthletePanel.allID {
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
    @Published var lastError: String?
    @Published var syncStatus: String?
    @Published var isSyncing = false
    @Published private(set) var athletePanelsCache: [AthletePanel] = []
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
    @Published private(set) var trainerRecordingSampleCount = 0
    @Published private(set) var trainerRecordingElevationGainMeters: Double = 0
    @Published private(set) var trainerRecordingLastFitPath: String?
    @Published private(set) var trainerRecordingLastSyncSummary: String?
    @Published private(set) var trainerRecordingStatusBySession: [UUID: TrainerRecordingStatus] = [:]

    private var gptRecommendation: AIRecommendation?
    private var didAttemptAICoachBootstrap = false
    private let repository: DataRepository?
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
    private var trainerPowerCancellableBySession: [UUID: AnyCancellable] = [:]
    private var trainerRiderConnectionMemoryBySessionID: [UUID: TrainerRiderConnectionMemory] = [:]
    private let trainerRiderConnectionStoreDefaultsKey = "fricu.trainer.rider.connection.store.v1"
    private let athleteProfileStoreDefaultsKey = "fricu.athlete.profile.store.v1"
    private var athleteProfilesByPanelID: [String: AthleteProfile] = [:]
    private var isApplyingAthleteProfile = false

    init() {
        do {
            self.repository = try LocalJSONRepository()
        } catch {
            self.repository = nil
            self.lastError = "Failed to initialize repository: \(error.localizedDescription)"
        }
        configureInitialTrainerSessions()
        setupDerivedRefreshPipeline()
        setupTrainerRecordingPipeline()
        markDerivedStateDirty()
    }

    private func configureInitialTrainerSessions() {
        let restoredStore = loadTrainerRiderConnectionStore()
        let restoredRiders = (restoredStore?.riders ?? []).filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        if restoredRiders.isEmpty {
            let primaryMemory = TrainerRiderConnectionMemory(
                id: UUID(),
                name: "Athlete 1",
                preferredTrainerDeviceID: nil,
                preferredHeartRateDeviceID: nil,
                preferredPowerMeterDeviceID: nil,
                appearance: .default
            )
            trainerRiderConnectionMemoryBySessionID = [primaryMemory.id: primaryMemory]
            let primary = makeTrainerRiderSession(from: primaryMemory, useSharedManagers: true)
            trainerRiderSessions = [primary]
            primaryTrainerSessionID = primary.id
            persistTrainerRiderConnectionStore()
        } else {
            let primaryID = resolvedPrimarySessionID(
                in: restoredRiders,
                preferred: restoredStore?.primarySessionID
            )
            trainerRiderConnectionMemoryBySessionID = Dictionary(
                uniqueKeysWithValues: restoredRiders.map { ($0.id, $0) }
            )
            trainerRiderSessions = restoredRiders.map { memory in
                makeTrainerRiderSession(from: memory, useSharedManagers: memory.id == primaryID)
            }
            primaryTrainerSessionID = primaryID
        }

        trainerRecordingStatusBySession = Dictionary(
            uniqueKeysWithValues: trainerRiderSessions.map { ($0.id, TrainerRecordingStatus()) }
        )
        refreshPrimaryTrainerRecordingSnapshot()
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
        session.heartRateMonitor.setPreferredAutoConnectDeviceID(memory.preferredHeartRateDeviceID)
        session.powerMeter.setPreferredAutoConnectDeviceID(memory.preferredPowerMeterDeviceID)
    }

    private func installConnectionPersistenceCallbacks(for session: TrainerRiderSession) {
        let sessionID = session.id
        session.trainer.onConnectedDeviceChanged = { [weak self] deviceID, _ in
            Task { @MainActor in
                self?.rememberConnectedTrainerDevice(sessionID: sessionID, deviceID: deviceID)
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
        let riders = trainerRiderSessions.map { session in
            var memory = trainerRiderConnectionMemoryBySessionID[session.id]
            ?? TrainerRiderConnectionMemory(
                id: session.id,
                name: session.name,
                preferredTrainerDeviceID: nil,
                preferredHeartRateDeviceID: nil,
                preferredPowerMeterDeviceID: nil,
                appearance: .default
            )
            memory.name = session.name
            if memory.appearance == nil {
                memory.appearance = .default
            }
            return memory
        }
        let payload = TrainerRiderConnectionStore(primarySessionID: primaryTrainerSessionID, riders: riders)
        do {
            let data = try JSONEncoder().encode(payload)
            UserDefaults.standard.set(data, forKey: trainerRiderConnectionStoreDefaultsKey)
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
            preferredHeartRateDeviceID: nil,
            preferredPowerMeterDeviceID: nil,
            appearance: .default
        )
    }

    private func rememberConnectedTrainerDevice(sessionID: UUID, deviceID: UUID) {
        var memory = baseConnectionMemory(for: sessionID)
        memory.name = trainerRiderSession(id: sessionID)?.name ?? memory.name
        memory.preferredTrainerDeviceID = deviceID
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
        for session in trainerRiderSessions {
            session.trainer.startAutoConnectIfPossible()
            session.heartRateMonitor.startAutoConnectIfPossible()
            session.powerMeter.startAutoConnectIfPossible()
        }
    }

    private var nextTrainerSessionName: String {
        "Athlete \(trainerRiderSessions.count + 1)"
    }

    func addTrainerRiderSession(named preferredName: String? = nil) {
        let trimmed = preferredName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let name = trimmed.isEmpty ? nextTrainerSessionName : trimmed
        let memory = TrainerRiderConnectionMemory(
            id: UUID(),
            name: name,
            preferredTrainerDeviceID: nil,
            preferredHeartRateDeviceID: nil,
            preferredPowerMeterDeviceID: nil,
            appearance: .default
        )
        let session = makeTrainerRiderSession(from: memory, useSharedManagers: false)
        trainerRiderConnectionMemoryBySessionID[session.id] = memory
        trainerRiderSessions.append(session)
        updateTrainerRecordingStatus(TrainerRecordingStatus(), for: session.id)
        observeTrainerConnection(for: session)
        observeTrainerPower(for: session)
        persistTrainerRiderConnectionStore()
        refreshAthletePanelsAndSelection(preferSpecificSelection: false)
    }

    func renameTrainerRiderSession(id: UUID, to newName: String) {
        guard let index = trainerRiderSessions.firstIndex(where: { $0.id == id }) else { return }
        let oldName = trainerRiderSessions[index].name
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard trimmed != oldName else { return }
        trainerRiderSessions[index].name = trimmed
        var memory = baseConnectionMemory(for: id)
        memory.name = trimmed
        trainerRiderConnectionMemoryBySessionID[id] = memory
        migrateAthleteIdentity(from: oldName, to: trimmed)
        persistTrainerRiderConnectionStore()
        refreshAthletePanelsAndSelection(preferSpecificSelection: false)
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

    func removeTrainerRiderSession(id: UUID) {
        guard let index = trainerRiderSessions.firstIndex(where: { $0.id == id }) else { return }
        let session = trainerRiderSessions[index]
        if id == primaryTrainerSessionID {
            lastError = "Primary rider cannot be removed."
            return
        }
        if trainerRecordingStatus(for: id).isActive {
            lastError = "Stop rider recording before removing this rider."
            return
        }

        session.trainer.stopScan()
        session.trainer.disconnect()
        session.heartRateMonitor.stopScan()
        session.heartRateMonitor.disconnect()
        session.powerMeter.stopScan()
        session.powerMeter.disconnect()
        trainerRiderSessions.remove(at: index)
        trainerRiderConnectionMemoryBySessionID[id] = nil
        trainerConnectionCancellableBySession[id]?.cancel()
        trainerConnectionCancellableBySession[id] = nil
        trainerPowerCancellableBySession[id]?.cancel()
        trainerPowerCancellableBySession[id] = nil
        trainerRecordingStatusBySession[id] = nil
        trainerRecordingSessionByRider[id] = nil
        trainerRecordingTimerTaskBySession[id]?.cancel()
        trainerRecordingTimerTaskBySession[id] = nil
        trainerRecordingFinalizationTaskBySession[id]?.cancel()
        trainerRecordingFinalizationTaskBySession[id] = nil
        isFinalizingTrainerRecordingBySession.remove(id)
        persistTrainerRiderConnectionStore()
        refreshAthletePanelsAndSelection(preferSpecificSelection: false)
        refreshPrimaryTrainerRecordingSnapshot()
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
            trainerRecordingSampleCount = 0
            trainerRecordingElevationGainMeters = 0
            trainerRecordingLastFitPath = nil
            trainerRecordingLastSyncSummary = nil
            return
        }
        let status = trainerRecordingStatus(for: primaryID)
        trainerRecordingIsActive = status.isActive
        trainerRecordingElapsedSec = status.elapsedSec
        trainerRecordingSampleCount = status.sampleCount
        trainerRecordingElevationGainMeters = status.elevationGainMeters
        trainerRecordingLastFitPath = status.lastFitPath
        trainerRecordingLastSyncSummary = status.lastSyncSummary
    }

    private var fallbackAthleteName: String {
        if let primary = trainerRiderSessions.first?.name.trimmingCharacters(in: .whitespacesAndNewlines),
           !primary.isEmpty {
            return primary
        }
        if let existing = activities
            .compactMap({ normalizedNonEmptyString($0.athleteName) ?? parseAthleteNameFromLegacyNotes($0.notes) })
            .first {
            return existing
        }
        return "Athlete 1"
    }

    private func loadAthleteProfileStoreIfNeeded(fallback: AthleteProfile) {
        var restored: [String: AthleteProfile] = [:]
        if let data = UserDefaults.standard.data(forKey: athleteProfileStoreDefaultsKey) {
            if let decoded = try? JSONDecoder().decode([String: AthleteProfile].self, from: data) {
                restored = decoded
            }
        }
        if restored.isEmpty {
            let fallbackKey = athletePanelID(forName: fallbackAthleteName)
            restored[fallbackKey] = fallback
        }
        athleteProfilesByPanelID = restored
    }

    private func persistAthleteProfileStore() {
        do {
            let data = try JSONEncoder().encode(athleteProfilesByPanelID)
            UserDefaults.standard.set(data, forKey: athleteProfileStoreDefaultsKey)
        } catch {
            lastError = "Failed to save athlete profile store: \(error.localizedDescription)"
        }
    }

    private func cacheProfileForSelectedAthlete() {
        guard !isApplyingAthleteProfile else { return }
        guard selectedAthletePanelID != AthletePanel.allID else { return }
        athleteProfilesByPanelID[selectedAthletePanelID] = profile
        persistAthleteProfileStore()
    }

    private func applySelectedAthleteProfileIfNeeded() {
        guard selectedAthletePanelID != AthletePanel.allID else { return }
        let chosen = athleteProfilesByPanelID[selectedAthletePanelID] ?? profile
        athleteProfilesByPanelID[selectedAthletePanelID] = chosen
        persistAthleteProfileStore()
        guard derivedProfileFingerprint(profile) != derivedProfileFingerprint(chosen) else { return }
        isApplyingAthleteProfile = true
        profile = chosen
        isApplyingAthleteProfile = false
    }

    private func refreshAthletePanelsAndSelection(preferSpecificSelection: Bool) {
        var countsByPanelID: [String: Int] = [:]
        var titleByPanelID: [String: String] = [:]

        for activity in activities {
            let title = athleteDisplayName(for: activity)
            let panelID = athletePanelID(forName: title)
            countsByPanelID[panelID, default: 0] += 1
            if titleByPanelID[panelID] == nil {
                titleByPanelID[panelID] = title
            }
        }

        for session in trainerRiderSessions {
            let title = session.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { continue }
            let panelID = athletePanelID(forName: title)
            if titleByPanelID[panelID] == nil {
                titleByPanelID[panelID] = title
            }
            countsByPanelID[panelID, default: 0] += 0
        }

        for workout in plannedWorkouts {
            guard let name = normalizedNonEmptyString(workout.athleteName) else { continue }
            let panelID = athletePanelID(forName: name)
            if titleByPanelID[panelID] == nil {
                titleByPanelID[panelID] = name
            }
            countsByPanelID[panelID, default: 0] += 0
        }

        for plan in dailyMealPlans {
            guard let name = normalizedNonEmptyString(plan.athleteName) else { continue }
            let panelID = athletePanelID(forName: name)
            if titleByPanelID[panelID] == nil {
                titleByPanelID[panelID] = name
            }
            countsByPanelID[panelID, default: 0] += 0
        }

        for sample in wellnessSamples {
            guard let name = normalizedNonEmptyString(sample.athleteName) else { continue }
            let panelID = athletePanelID(forName: name)
            if titleByPanelID[panelID] == nil {
                titleByPanelID[panelID] = name
            }
            countsByPanelID[panelID, default: 0] += 0
        }

        for event in intervalsCalendarEvents {
            guard let name = normalizedNonEmptyString(event.athleteName) else { continue }
            let panelID = athletePanelID(forName: name)
            if titleByPanelID[panelID] == nil {
                titleByPanelID[panelID] = name
            }
            countsByPanelID[panelID, default: 0] += 0
        }

        if titleByPanelID.isEmpty {
            let fallback = fallbackAthleteName
            let panelID = athletePanelID(forName: fallback)
            titleByPanelID[panelID] = fallback
            countsByPanelID[panelID] = 0
        }

        var rows: [AthletePanel] = titleByPanelID.map { panelID, title in
            AthletePanel(
                id: panelID,
                title: title,
                count: countsByPanelID[panelID] ?? 0,
                isAll: false
            )
        }
        let hiddenPlaceholderPanelIDs = Set(
            rows
                .filter { $0.count == 0 && isDisposablePlaceholderAthleteName($0.title) }
                .map(\.id)
        )
        if !hiddenPlaceholderPanelIDs.isEmpty {
            rows.removeAll { hiddenPlaceholderPanelIDs.contains($0.id) }
            athleteProfilesByPanelID = athleteProfilesByPanelID.filter { key, _ in
                !hiddenPlaceholderPanelIDs.contains(key)
            }
        }
        rows.sort { lhs, rhs in
            if lhs.count != rhs.count { return lhs.count > rhs.count }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }

        let all = AthletePanel(
            id: AthletePanel.allID,
            title: L10n.choose(simplifiedChinese: "全部运动员", english: "All Athletes"),
            count: activities.count,
            isAll: true
        )
        athletePanelsCache = [all] + rows

        let previousSelection = selectedAthletePanelID
        if !athletePanelsCache.contains(where: { $0.id == previousSelection }) {
            selectedAthletePanelID = rows.first?.id ?? AthletePanel.allID
        } else if preferSpecificSelection, previousSelection == AthletePanel.allID {
            selectedAthletePanelID = rows.first?.id ?? AthletePanel.allID
        }

        for panel in rows where athleteProfilesByPanelID[panel.id] == nil {
            athleteProfilesByPanelID[panel.id] = profile
        }
        persistAthleteProfileStore()
    }

    private func isDisposablePlaceholderAthleteName(_ name: String) -> Bool {
        guard let normalized = normalizedNonEmptyString(name) else { return false }
        let lower = normalized.lowercased()
        guard lower.hasPrefix("athlete ") else { return false }
        let suffix = lower.dropFirst("athlete ".count).trimmingCharacters(in: .whitespacesAndNewlines)
        return !suffix.isEmpty && suffix.allSatisfy(\.isNumber)
    }

    private func migrateLegacyAthleteNamesIfNeeded() {
        let defaultName = fallbackAthleteName

        var activitiesUpdated = activities
        var activitiesChanged = false
        for index in activitiesUpdated.indices {
            let current = activitiesUpdated[index]
            if normalizedNonEmptyString(current.athleteName) == nil {
                let resolved = parseAthleteNameFromLegacyNotes(current.notes) ?? defaultName
                activitiesUpdated[index].athleteName = resolved
                activitiesChanged = true
            }
        }

        var workoutsUpdated = plannedWorkouts
        var workoutsChanged = false
        for index in workoutsUpdated.indices where normalizedNonEmptyString(workoutsUpdated[index].athleteName) == nil {
            workoutsUpdated[index].athleteName = defaultName
            workoutsChanged = true
        }

        var mealPlansUpdated = dailyMealPlans
        var mealPlansChanged = false
        for index in mealPlansUpdated.indices where normalizedNonEmptyString(mealPlansUpdated[index].athleteName) == nil {
            mealPlansUpdated[index].athleteName = defaultName
            mealPlansChanged = true
        }

        var wellnessUpdated = wellnessSamples
        var wellnessChanged = false
        for index in wellnessUpdated.indices where normalizedNonEmptyString(wellnessUpdated[index].athleteName) == nil {
            wellnessUpdated[index].athleteName = defaultName
            wellnessChanged = true
        }

        var eventsUpdated = intervalsCalendarEvents
        var eventsChanged = false
        for index in eventsUpdated.indices where normalizedNonEmptyString(eventsUpdated[index].athleteName) == nil {
            eventsUpdated[index].athleteName = defaultName
            eventsChanged = true
        }

        if activitiesChanged { activities = activitiesUpdated }
        if mealPlansChanged { dailyMealPlans = mealPlansUpdated }
        if workoutsChanged { plannedWorkouts = workoutsUpdated }
        if wellnessChanged { wellnessSamples = wellnessUpdated }
        if eventsChanged { intervalsCalendarEvents = eventsUpdated }

        do {
            if let repository {
                if activitiesChanged { try repository.saveActivities(activitiesUpdated) }
                if mealPlansChanged { try repository.saveDailyMealPlans(mealPlansUpdated) }
                if workoutsChanged { try repository.saveWorkouts(workoutsUpdated) }
                if eventsChanged { try repository.saveCalendarEvents(eventsUpdated) }
                if activitiesChanged || mealPlansChanged || workoutsChanged || wellnessChanged || eventsChanged {
                    try repository.saveProfile(profile)
                }
            }
        } catch {
            lastError = "Failed to migrate athlete ownership: \(error.localizedDescription)"
        }
    }

    private func migrateAthleteIdentity(from oldName: String, to newName: String) {
        let oldKey = athletePanelID(forName: oldName)
        let newKey = athletePanelID(forName: newName)
        guard oldKey != newKey else { return }

        var updatedActivities = activities
        var updatedMealPlans = dailyMealPlans
        var updatedWorkouts = plannedWorkouts
        var updatedWellness = wellnessSamples
        var updatedEvents = intervalsCalendarEvents

        var touched = false

        for index in updatedActivities.indices where athletePanelID(forName: updatedActivities[index].athleteName) == oldKey {
            updatedActivities[index].athleteName = newName
            touched = true
        }
        for index in updatedWorkouts.indices where athletePanelID(forName: updatedWorkouts[index].athleteName) == oldKey {
            updatedWorkouts[index].athleteName = newName
            touched = true
        }
        for index in updatedMealPlans.indices where athletePanelID(forName: updatedMealPlans[index].athleteName) == oldKey {
            updatedMealPlans[index].athleteName = newName
            touched = true
        }
        for index in updatedWellness.indices where athletePanelID(forName: updatedWellness[index].athleteName) == oldKey {
            updatedWellness[index].athleteName = newName
            touched = true
        }
        for index in updatedEvents.indices where athletePanelID(forName: updatedEvents[index].athleteName) == oldKey {
            updatedEvents[index].athleteName = newName
            touched = true
        }

        if touched {
            activities = updatedActivities
            dailyMealPlans = updatedMealPlans
            plannedWorkouts = updatedWorkouts
            wellnessSamples = updatedWellness
            intervalsCalendarEvents = updatedEvents
            do {
                if let repository {
                    try repository.saveActivities(updatedActivities)
                    try repository.saveDailyMealPlans(updatedMealPlans)
                    try repository.saveWorkouts(updatedWorkouts)
                    try repository.saveCalendarEvents(updatedEvents)
                }
            } catch {
                lastError = "Failed to persist renamed athlete data: \(error.localizedDescription)"
            }
        }

        if let cached = athleteProfilesByPanelID.removeValue(forKey: oldKey) {
            athleteProfilesByPanelID[newKey] = cached
        }
        persistAthleteProfileStore()
    }

    func bootstrap() {
        do {
            var loadedProfile: AthleteProfile = .default
            if let repository {
                self.activities = try repository.loadActivities()
                self.dailyMealPlans = try repository.loadDailyMealPlans()
                self.customFoodLibrary = try repository.loadCustomFoods()
                self.plannedWorkouts = try repository.loadWorkouts()
                self.intervalsCalendarEvents = try repository.loadCalendarEvents()
                loadedProfile = try repository.loadProfile()
                self.activityMetricInsightsCache = Dictionary(
                    uniqueKeysWithValues: try repository.loadActivityMetricInsights().map { ($0.activityID, $0) }
                )
            } else {
                self.activities = DemoDataFactory.generateActivities(days: 120)
                self.dailyMealPlans = []
                self.customFoodLibrary = []
                self.plannedWorkouts = []
                self.intervalsCalendarEvents = []
                loadedProfile = .default
                self.activityMetricInsightsCache = [:]
            }

            self.profile = loadedProfile
            migrateLegacyAthleteNamesIfNeeded()
            loadAthleteProfileStoreIfNeeded(fallback: loadedProfile)
            refreshAthletePanelsAndSelection(preferSpecificSelection: true)
            applySelectedAthleteProfileIfNeeded()
            pruneActivityMetricInsights()
            applyDefaultCredentialsIfNeeded()
            ensureTrainerRiderAutoReconnect()
        } catch {
            self.lastError = "Failed to load local data: \(error.localizedDescription)"
        }
    }

    var filteredActivities: [Activity] {
        filteredActivitiesCache
    }

    var athletePanels: [AthletePanel] {
        athletePanelsCache
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

    var selectedAthleteTitle: String {
        guard selectedAthletePanelID != AthletePanel.allID else {
            return L10n.choose(simplifiedChinese: "全部运动员", english: "All Athletes")
        }
        return athletePanelsCache.first(where: { $0.id == selectedAthletePanelID })?.title
            ?? L10n.choose(simplifiedChinese: "默认运动员", english: "Default Athlete")
    }

    var isAllAthletesSelected: Bool {
        selectedAthletePanelID == AthletePanel.allID
    }

    var selectedAthleteNameForWrite: String {
        if selectedAthletePanelID != AthletePanel.allID,
           let panel = athletePanelsCache.first(where: { $0.id == selectedAthletePanelID }) {
            return panel.title
        }
        if let primary = trainerRiderSessions.first?.name.trimmingCharacters(in: .whitespacesAndNewlines), !primary.isEmpty {
            return primary
        }
        return L10n.choose(simplifiedChinese: "默认运动员", english: "Default Athlete")
    }

    func profileForAthlete(named athleteName: String?) -> AthleteProfile {
        let panelID = athletePanelID(forName: athleteName)
        return athleteProfilesByPanelID[panelID] ?? profile
    }

    func activitiesForAthlete(named athleteName: String?) -> [Activity] {
        let panelID = athletePanelID(forName: athleteName)
        return activities
            .filter { athletePanelID(for: $0) == panelID }
            .sorted { $0.date > $1.date }
    }

    func workoutsForAthlete(named athleteName: String?) -> [PlannedWorkout] {
        let panelID = athletePanelID(forName: athleteName)
        return plannedWorkouts
            .filter { athletePanelID(forName: $0.athleteName) == panelID }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func mealPlansForAthlete(named athleteName: String?) -> [DailyMealPlan] {
        let panelID = athletePanelID(forName: athleteName)
        return dailyMealPlans
            .filter { athletePanelID(forName: $0.athleteName) == panelID }
            .sorted { $0.date > $1.date }
    }

    func wellnessSamplesForAthlete(named athleteName: String?) -> [WellnessSample] {
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
        var samples: [LiveRideSample]
        var cumulativeDistanceMeters: Double
        var cumulativeElevationGainMeters: Double
    }

    private struct RideDistanceDelta {
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
            observeTrainerPower(for: session)
        }
    }

    private func observeTrainerConnection(for session: TrainerRiderSession) {
        let sessionID = session.id
        trainerConnectionCancellableBySession[sessionID]?.cancel()
        trainerConnectionCancellableBySession[sessionID] = session.trainer.$isConnected
            .removeDuplicates()
            .sink { [weak self] connected in
                guard let self else { return }

                if connected {
                    self.trainerRecordingFinalizationTaskBySession[sessionID]?.cancel()
                    self.trainerRecordingFinalizationTaskBySession[sessionID] = nil
                } else {
                    self.trainerRecordingFinalizationTaskBySession[sessionID]?.cancel()
                    self.trainerRecordingFinalizationTaskBySession[sessionID] = Task { [weak self] in
                        await self?.finalizeTrainerRecording(for: sessionID, reason: "Trainer disconnected")
                    }
                }
            }
    }

    private func observeTrainerPower(for session: TrainerRiderSession) {
        let sessionID = session.id
        trainerPowerCancellableBySession[sessionID]?.cancel()
        trainerPowerCancellableBySession[sessionID] = session.trainer.$livePowerWatts
            .sink { [weak self] watts in
                guard let self else { return }
                guard let watts, watts > 0 else { return }
                self.startTrainerRecording(for: sessionID, reason: "Power detected")
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
            samples: [],
            cumulativeDistanceMeters: 0,
            cumulativeElevationGainMeters: 0
        )

        var status = trainerRecordingStatus(for: sessionID)
        status.isActive = true
        status.elapsedSec = 0
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
            return RideDistanceDelta(distanceMeters: 0, elevationGainMeters: 0)
        }
        guard let speedKPH = rider.trainer.liveSpeedKPH, speedKPH > 0 else {
            return RideDistanceDelta(distanceMeters: 0, elevationGainMeters: 0)
        }

        let distanceMeters = (speedKPH / 3.6) * dt
        let elevationGainMeters: Double
        if let gradePercent = rider.trainer.targetGradePercent, gradePercent > 0 {
            elevationGainMeters = distanceMeters * (gradePercent / 100.0)
        } else {
            elevationGainMeters = 0
        }
        return RideDistanceDelta(distanceMeters: distanceMeters, elevationGainMeters: elevationGainMeters)
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
                distanceMeters: max(0, distanceMeters)
            )
        }
        return LiveRideSample(
            timestamp: timestamp,
            powerWatts: rider.trainer.livePowerWatts ?? rider.powerMeter.livePowerWatts,
            heartRateBPM: rider.heartRateMonitor.liveHeartRateBPM,
            cadenceRPM: rider.trainer.liveCadenceRPM ?? rider.powerMeter.liveCadenceRPM,
            speedKPH: rider.trainer.liveSpeedKPH,
            distanceMeters: max(0, distanceMeters)
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
        session.samples.append(
            makeLiveRideSample(for: sessionID, at: timestamp, distanceMeters: session.cumulativeDistanceMeters)
        )
        session.lastSampleAt = timestamp
    }

    private func captureTrainerRecordingSample(for sessionID: UUID, at timestamp: Date = Date()) {
        guard trainerRecordingStatus(for: sessionID).isActive else { return }
        guard var session = trainerRecordingSessionByRider[sessionID] else { return }

        appendTrainerRecordingSample(for: sessionID, to: &session, at: timestamp)
        trainerRecordingSessionByRider[sessionID] = session

        var status = trainerRecordingStatus(for: sessionID)
        status.elapsedSec = max(0, Int(timestamp.timeIntervalSince(session.startedAt).rounded()))
        status.sampleCount = session.samples.count
        status.elevationGainMeters = max(0, session.cumulativeElevationGainMeters)
        updateTrainerRecordingStatus(status, for: sessionID)
    }

    private func finalizeTrainerRecording(for sessionID: UUID, reason: String) async {
        guard trainerRecordingSessionByRider[sessionID] != nil else {
            var status = trainerRecordingStatus(for: sessionID)
            status.isActive = false
            status.elapsedSec = 0
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
            var status = trainerRecordingStatus(for: sessionID)
            status.isActive = false
            status.elapsedSec = 0
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
        updateTrainerRecordingStatus(inProgressStatus, for: sessionID)

        let samples = session.samples.sorted { $0.timestamp < $1.timestamp }
        let elapsedSec = max(1, Int(end.timeIntervalSince(session.startedAt).rounded()))
        let totalDistanceMeters = max(0, session.cumulativeDistanceMeters)

        let powerValues = samples.compactMap { $0.powerWatts }.filter { $0 > 0 }
        let hrValues = samples.compactMap { $0.heartRateBPM }.filter { $0 > 0 }
        let avgPower = powerValues.isEmpty ? nil : Int((Double(powerValues.reduce(0, +)) / Double(powerValues.count)).rounded())
        let maxPower = powerValues.max()
        let normalizedPower = TSSEstimator.normalizedPower(from: powerValues.map(Double.init)) ?? avgPower
        let avgHeartRate = hrValues.isEmpty ? nil : Int((Double(hrValues.reduce(0, +)) / Double(hrValues.count)).rounded())
        let maxHeartRate = hrValues.max()

        let summary = LiveRideSummary(
            startDate: session.startedAt,
            endDate: end,
            sport: .cycling,
            totalElapsedSec: elapsedSec,
            totalTimerSec: elapsedSec,
            totalDistanceMeters: totalDistanceMeters,
            averageHeartRate: avgHeartRate,
            maxHeartRate: maxHeartRate,
            averagePower: avgPower,
            maxPower: maxPower,
            normalizedPower: normalizedPower
        )

        let riderName = trainerRiderSession(id: sessionID)?.name ?? "Rider"

        do {
            let fitData = LiveRideFITWriter.export(samples: samples, summary: summary)
            let fitURL = try saveTrainerFITToDist(fitData: fitData, startDate: session.startedAt)

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
                notes: "\(riderName) · Trainer ride · \(IntervalsDateFormatter.dateTimeLocal.string(from: session.startedAt))",
                externalID: "fricu:trainer:\(sessionID.uuidString):\(Int(session.startedAt.timeIntervalSince1970))",
                sourceFileName: fitURL.lastPathComponent,
                sourceFileType: "fit",
                sourceFileBase64: fitData.base64EncodedString()
            )

            let merged = mergeActivities(imported: [activity])
            try persistActivities(merged)
            if let saved = activities.first(where: { $0.sourceFileName == fitURL.lastPathComponent }) {
                activity = saved
            }

            let syncSummary = await pushTrainerRideToClouds(
                activity: activity,
                fitData: fitData,
                fitFileName: fitURL.lastPathComponent
            )
            let finalSummary = "\(riderName) · \(reason)。已保存 FIT：\(fitURL.lastPathComponent)。\(syncSummary)"

            var status = trainerRecordingStatus(for: sessionID)
            status.lastFitPath = fitURL.path
            status.lastSyncSummary = finalSummary
            updateTrainerRecordingStatus(status, for: sessionID)
            syncStatus = finalSummary
            lastError = nil
        } catch {
            let message = "Trainer recording finalize failed (\(riderName)): \(error.localizedDescription)"
            let failureSummary = "\(riderName) · \(reason)。保存失败：\(error.localizedDescription)"
            var status = trainerRecordingStatus(for: sessionID)
            status.lastSyncSummary = failureSummary
            updateTrainerRecordingStatus(status, for: sessionID)
            syncStatus = failureSummary
            lastError = message
        }
    }

    private func saveTrainerFITToDist(fitData: Data, startDate: Date) throws -> URL {
        let fm = FileManager.default
        let distDir = try resolveWritableTrainerRecordingDirectory()

        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"

        let base = "trainer-\(formatter.string(from: startDate))"
        var candidate = distDir.appendingPathComponent("\(base).fit")
        var suffix = 1
        while fm.fileExists(atPath: candidate.path) {
            candidate = distDir.appendingPathComponent("\(base)-\(suffix).fit")
            suffix += 1
        }

        try fitData.write(to: candidate, options: .atomic)
        return candidate
    }

    private func resolveWritableTrainerRecordingDirectory() throws -> URL {
        let fm = FileManager.default

        var roots: [URL] = []
        roots.append(URL(fileURLWithPath: fm.currentDirectoryPath, isDirectory: true))
        if let documents = fm.urls(for: .documentDirectory, in: .userDomainMask).first {
            roots.append(documents.appendingPathComponent("Fricu", isDirectory: true))
        }
        if let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            roots.append(appSupport.appendingPathComponent("Fricu", isDirectory: true))
        }

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
        roots.append(URL(fileURLWithPath: fm.currentDirectoryPath, isDirectory: true))
        if let documents = fm.urls(for: .documentDirectory, in: .userDomainMask).first {
            roots.append(documents.appendingPathComponent("Fricu", isDirectory: true))
        }
        if let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            roots.append(appSupport.appendingPathComponent("Fricu", isDirectory: true))
        }

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

        do {
            return try await uploadToStravaWithAuthRetry(
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
            return try await uploadToStravaWithAuthRetry(
                client: client,
                auth: &auth,
                payload: (tcx, "tcx"),
                name: title,
                description: description + " (fallback: tcx)",
                externalID: externalID + "-tcx"
            )
        }
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
        let activityPanels = athletePanelsCache.filter { !$0.isAll && $0.count > 0 }
        if isAllAthletesSelected, activityPanels.count > 1 {
            lastError = L10n.choose(
                simplifiedChinese: "当前处于“全部运动员”视图。请先选择具体运动员面板，再清空该运动员活动。",
                english: "You are in All Athletes view. Select a specific athlete panel first, then clear that athlete's activities."
            )
            return
        }

        let updated: [Activity]
        let removedCount: Int
        if isAllAthletesSelected {
            updated = []
            removedCount = activities.count
        } else {
            updated = activities.filter { activity in
                !matchesSelectedAthlete(panelID: athletePanelID(for: activity))
            }
            removedCount = activities.count - updated.count
        }

        do {
            try persistActivities(updated)
            if isAllAthletesSelected {
                self.syncStatus = "Cleared all activities."
            } else {
                self.syncStatus = "Cleared \(removedCount) activities for \(selectedAthleteTitle)."
            }
            self.lastError = nil
        } catch {
            self.lastError = "Failed to clear activities: \(error.localizedDescription)"
        }
    }

    func isPrimaryTrainerAthletePanel(panelID: String) -> Bool {
        guard panelID != AthletePanel.allID else { return false }
        guard let primaryID = primaryTrainerSessionID,
              let session = trainerRiderSessions.first(where: { $0.id == primaryID })
        else { return false }
        return athletePanelID(forName: session.name) == panelID
    }

    func canDeleteAthletePanel(panelID: String) -> Bool {
        guard panelID != AthletePanel.allID else { return false }
        // Keep the current primary rider panel protected because it owns shared BLE managers.
        return !isPrimaryTrainerAthletePanel(panelID: panelID)
    }

    func deleteAthletePanelAndAssociatedData(panelID: String) {
        guard panelID != AthletePanel.allID else { return }
        guard let panel = athletePanelsCache.first(where: { $0.id == panelID }) else { return }
        guard canDeleteAthletePanel(panelID: panelID) else {
            lastError = L10n.choose(
                simplifiedChinese: "当前主骑手面板无法直接删除。请先切换主骑手或删除其他面板。",
                english: "The current primary rider panel cannot be deleted directly. Switch primary rider or delete another panel first."
            )
            return
        }

        let originalActivitiesCount = activities.count
        let originalWorkoutsCount = plannedWorkouts.count
        let originalMealPlansCount = dailyMealPlans.count
        let originalWellnessCount = wellnessSamples.count
        let originalEventsCount = intervalsCalendarEvents.count

        let removedActivityIDs = Set(
            activities
                .filter { athletePanelID(for: $0) == panelID }
                .map(\.id)
        )
        let updatedActivities = activities.filter { athletePanelID(for: $0) != panelID }
        let updatedWorkouts = plannedWorkouts.filter { athletePanelID(forName: $0.athleteName) != panelID }
        let updatedMealPlans = dailyMealPlans.filter { athletePanelID(forName: $0.athleteName) != panelID }
        let updatedWellness = wellnessSamples.filter { athletePanelID(forName: $0.athleteName) != panelID }
        let updatedEvents = intervalsCalendarEvents.filter { athletePanelID(forName: $0.athleteName) != panelID }

        do {
            try persistActivities(updatedActivities)
            try persistWorkouts(updatedWorkouts)
            try persistDailyMealPlans(updatedMealPlans)
            try persistCalendarEvents(updatedEvents)
            wellnessSamples = updatedWellness
        } catch {
            lastError = "Failed to delete athlete panel data: \(error.localizedDescription)"
            return
        }

        if !removedActivityIDs.isEmpty {
            pruneActivityMetricInsights()
        }

        athleteProfilesByPanelID.removeValue(forKey: panelID)
        persistAthleteProfileStore()

        let removableSessionIDs = trainerRiderSessions
            .filter { $0.id != primaryTrainerSessionID && athletePanelID(forName: $0.name) == panelID }
            .map(\.id)
        for sessionID in removableSessionIDs {
            removeTrainerRiderSession(id: sessionID)
        }

        refreshAthletePanelsAndSelection(preferSpecificSelection: false)
        markDerivedStateDirty()

        let removedCountsSummary = [
            L10n.choose(simplifiedChinese: "活动", english: "activities") + " \(originalActivitiesCount - updatedActivities.count)",
            L10n.choose(simplifiedChinese: "训练计划", english: "workouts") + " \(originalWorkoutsCount - updatedWorkouts.count)",
            L10n.choose(simplifiedChinese: "饮食计划", english: "meal plans") + " \(originalMealPlansCount - updatedMealPlans.count)",
            L10n.choose(simplifiedChinese: "生理指标", english: "wellness") + " \(originalWellnessCount - updatedWellness.count)",
            L10n.choose(simplifiedChinese: "日历事件", english: "calendar events") + " \(originalEventsCount - updatedEvents.count)"
        ]

        syncStatus = L10n.choose(
            simplifiedChinese: "已删除运动员面板数据：\(panel.title)（" + removedCountsSummary.joined(separator: "，") + "）",
            english: "Deleted athlete panel data for \(panel.title) (\(removedCountsSummary.joined(separator: ", ")))."
        )
        lastError = nil
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
            let targetIndexes = updated.indices.filter { index in
                self.isAllAthletesSelected || self.matchesSelectedAthlete(panelID: self.athletePanelID(for: updated[index]))
            }

            for index in targetIndexes {
                if updated[index].externalID?.hasPrefix("intervals:") == true {
                    continue
                }

                let external = try await client.uploadActivity(updated[index])
                updated[index].externalID = external
                pushedCount += 1
            }

            try self.persistActivities(updated)
            if self.isAllAthletesSelected {
                self.syncStatus = "Pushed \(pushedCount) activities to Intervals.icu."
            } else {
                self.syncStatus = "Pushed \(pushedCount) activities to Intervals.icu for \(self.selectedAthleteTitle)."
            }
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
        self.isSyncing = true
        self.syncStatus = status
        self.lastError = nil

        do {
            try await action()
        } catch {
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
                replacement.athleteName = self.firstNonEmpty(replacement.athleteName, existing.athleteName)
                replacement.sourceFileName = existing.sourceFileName
                replacement.sourceFileType = existing.sourceFileType
                replacement.sourceFileBase64 = existing.sourceFileBase64
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
        if let repository = self.repository {
            try repository.saveActivities(deduped)
        }
        self.activities = deduped
        pruneActivityMetricInsights()
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

    private func parseAthleteNameFromLegacyNotes(_ notes: String) -> String? {
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let separators = [
            "---来自 Fricu",
            "---from Fricu",
            " · Trainer ride",
            " · 训练骑行",
            "• Trainer ride",
            "• 训练骑行"
        ]
        for separator in separators {
            if let range = trimmed.range(of: separator, options: [.caseInsensitive]) {
                let candidate = String(trimmed[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !candidate.isEmpty {
                    return candidate
                }
            }
        }
        return nil
    }

    private func athleteDisplayName(for activity: Activity) -> String {
        if let name = normalizedNonEmptyString(activity.athleteName) {
            return name
        }
        if let legacy = parseAthleteNameFromLegacyNotes(activity.notes) {
            return legacy
        }
        return L10n.choose(simplifiedChinese: "默认运动员", english: "Default Athlete")
    }

    private func athletePanelID(forName name: String?) -> String {
        normalizedNonEmptyString(name)?.lowercased() ?? AthletePanel.unknownAthleteToken
    }

    private func athletePanelID(for activity: Activity) -> String {
        athletePanelID(forName: athleteDisplayName(for: activity))
    }

    private func matchesSelectedAthlete(panelID: String) -> Bool {
        selectedAthletePanelID == AthletePanel.allID || panelID == selectedAthletePanelID
    }

    private func matchesSelectedAthlete(name: String?) -> Bool {
        matchesSelectedAthlete(panelID: athletePanelID(forName: name))
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
        merged.athleteName = firstNonEmpty(preferred.athleteName, fallback.athleteName)
        merged.externalID = firstNonEmpty(preferred.externalID, fallback.externalID)
        merged.sourceFileName = firstNonEmpty(preferred.sourceFileName, fallback.sourceFileName)
        merged.sourceFileType = firstNonEmpty(preferred.sourceFileType, fallback.sourceFileType)
        if merged.sourceFileBase64 == nil {
            merged.sourceFileBase64 = fallback.sourceFileBase64
        }
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
                replacement.athleteName = self.firstNonEmpty(replacement.athleteName, existing.athleteName)
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
        self.wellnessSamples = normalized

        let scoped = normalized.filter { matchesSelectedAthlete(name: $0.athleteName) }
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
                replacement.athleteName = self.firstNonEmpty(replacement.athleteName, existing.athleteName)
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
        let selectedSportFilter: SportType?
        let selectedScenario: TrainingScenario
        let selectedEnduranceFocus: EnduranceFocus
        let selectedAthletePanelID: String
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

    nonisolated private static func normalizedNonEmptyStringForCompute(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }

    nonisolated private static func parseAthleteNameFromLegacyNotesForCompute(_ notes: String) -> String? {
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let separators = [
            "---来自 Fricu",
            "---from Fricu",
            " · Trainer ride",
            " · 训练骑行",
            "• Trainer ride",
            "• 训练骑行"
        ]
        for separator in separators {
            if let range = trimmed.range(of: separator, options: [.caseInsensitive]) {
                let candidate = String(trimmed[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !candidate.isEmpty {
                    return candidate
                }
            }
        }
        return nil
    }

    nonisolated private static func athletePanelIDForCompute(name: String?) -> String {
        normalizedNonEmptyStringForCompute(name)?.lowercased() ?? AthletePanel.unknownAthleteToken
    }

    nonisolated private static func athletePanelIDForCompute(activity: Activity) -> String {
        if let tagged = normalizedNonEmptyStringForCompute(activity.athleteName) {
            return athletePanelIDForCompute(name: tagged)
        }
        if let parsed = parseAthleteNameFromLegacyNotesForCompute(activity.notes) {
            return athletePanelIDForCompute(name: parsed)
        }
        return AthletePanel.unknownAthleteToken
    }

    nonisolated private static func matchesSelectedAthleteForCompute(
        panelID: String,
        selectedAthletePanelID: String
    ) -> Bool {
        selectedAthletePanelID == AthletePanel.allID || panelID == selectedAthletePanelID
    }

    nonisolated private static func dynamicLoadSeriesDaysForCompute(for activities: [Activity]) -> Int {
        guard let oldest = activities.map(\.date).min() else { return 120 }
        let span = Calendar.current.dateComponents([.day], from: oldest, to: Date()).day ?? 120
        return min(1460, max(120, span + 14))
    }

    nonisolated private static func buildDerivedComputationResult(
        from snapshot: DerivedComputationSnapshot
    ) -> DerivedComputationResult {
        let athleteScopedActivities = snapshot.activities
            .filter { activity in
                matchesSelectedAthleteForCompute(
                    panelID: athletePanelIDForCompute(activity: activity),
                    selectedAthletePanelID: snapshot.selectedAthletePanelID
                )
            }
            .sorted { $0.date > $1.date }

        let athleteScopedDailyMealPlans = snapshot.dailyMealPlans
            .filter { plan in
                matchesSelectedAthleteForCompute(
                    panelID: athletePanelIDForCompute(name: plan.athleteName),
                    selectedAthletePanelID: snapshot.selectedAthletePanelID
                )
            }
            .sorted { $0.date > $1.date }

        let athleteScopedPlannedWorkouts = snapshot.plannedWorkouts
            .filter { workout in
                matchesSelectedAthleteForCompute(
                    panelID: athletePanelIDForCompute(name: workout.athleteName),
                    selectedAthletePanelID: snapshot.selectedAthletePanelID
                )
            }
            .sorted { $0.createdAt > $1.createdAt }

        let athleteScopedWellnessSamples = snapshot.wellnessSamples
            .filter { sample in
                matchesSelectedAthleteForCompute(
                    panelID: athletePanelIDForCompute(name: sample.athleteName),
                    selectedAthletePanelID: snapshot.selectedAthletePanelID
                )
            }
            .sorted { $0.date > $1.date }

        let athleteScopedCalendarEvents = snapshot.intervalsCalendarEvents
            .filter { event in
                matchesSelectedAthleteForCompute(
                    panelID: athletePanelIDForCompute(name: event.athleteName),
                    selectedAthletePanelID: snapshot.selectedAthletePanelID
                )
            }
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
            selectedSportFilter: selectedSportFilter,
            selectedScenario: selectedScenario,
            selectedEnduranceFocus: selectedEnduranceFocus,
            selectedAthletePanelID: selectedAthletePanelID,
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
