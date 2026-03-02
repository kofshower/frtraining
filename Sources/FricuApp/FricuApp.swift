import SwiftUI

@main
struct FricuApp: App {
    @StateObject private var store = AppStore()
    @AppStorage(AppLanguageOption.storageKey) private var appLanguageRawValue = AppLanguageOption.system.rawValue

    init() {
        L10n.installBundleBridgeIfNeeded()
        PowerAssertionController.shared.beginPreventingSleep()
    }

    private var appLocale: Locale {
        let option = AppLanguageOption(rawValue: appLanguageRawValue) ?? .system
        return option.locale
    }

    var body: some Scene {
        #if os(macOS)
            WindowGroup("Fricu") {
                RootView()
                    .environmentObject(store)
                    .environment(\.locale, appLocale)
                    .task {
                        store.bootstrap()
                    }
            }
            .windowResizability(.contentSize)

            Settings {
                SettingsView()
                    .environmentObject(store)
                    .environment(\.locale, appLocale)
            }
        #else
            WindowGroup("Fricu") {
                RootView()
                    .environmentObject(store)
                    .environment(\.locale, appLocale)
                    .task {
                        store.bootstrap()
                    }
            }
        #endif
    }
}

enum AppSection: String, CaseIterable, Identifiable {
    case dashboard
    case trainer
    case lactateLab
    case proSuite
    case nutrition
    case workoutBuilder
    case library
    case insights
    case settings

    var id: String { rawValue }

    var titleKey: LocalizedStringKey {
        switch self {
        case .dashboard: return "app.section.dashboard"
        case .trainer: return "app.section.trainer"
        case .lactateLab: return "app.section.lactateLab"
        case .proSuite: return "app.section.prosuite"
        case .nutrition: return "app.section.nutrition"
        case .workoutBuilder: return "app.section.workoutBuilder"
        case .library: return "app.section.library"
        case .insights: return "app.section.insights"
        case .settings: return "app.section.settings"
        }
    }

    var localizedTitle: String {
        switch self {
        case .dashboard:
            return L10n.choose(simplifiedChinese: "仪表盘", english: "Dashboard")
        case .trainer:
            return L10n.choose(simplifiedChinese: "骑行台", english: "Trainer")
        case .lactateLab:
            return L10n.choose(simplifiedChinese: "乳酸实验室", english: "Lactate Lab")
        case .proSuite:
            return L10n.choose(simplifiedChinese: "专业套件", english: "Pro Suite")
        case .nutrition:
            return L10n.choose(simplifiedChinese: "饮食", english: "Nutrition")
        case .workoutBuilder:
            return L10n.choose(simplifiedChinese: "训练构建", english: "Workout Builder")
        case .library:
            return L10n.choose(simplifiedChinese: "活动库", english: "Library")
        case .insights:
            return L10n.choose(simplifiedChinese: "洞察", english: "Insights")
        case .settings:
            return L10n.choose(simplifiedChinese: "设置", english: "Settings")
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard: return "speedometer"
        case .trainer: return "bicycle"
        case .lactateLab: return "testtube.2"
        case .proSuite: return "square.grid.3x3"
        case .nutrition: return "fork.knife"
        case .workoutBuilder: return "pencil.and.ruler"
        case .library: return "calendar"
        case .insights: return "chart.xyaxis.line"
        case .settings: return "gearshape"
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var store: AppStore
    @State private var selection: AppSection = .dashboard

    private func detailView(for section: AppSection) -> some View {
        Group {
            switch section {
            case .dashboard:
                DashboardView()
            case .trainer:
                TrainerPageView()
            case .lactateLab:
                LactateLabView()
            case .proSuite:
                ProSuiteView()
            case .nutrition:
                NutritionPageView()
            case .workoutBuilder:
                WorkoutBuilderView()
            case .library:
                ActivityLibraryView()
            case .insights:
                InsightsView()
            case .settings:
                SettingsView()
            }
        }
    }

    var body: some View {
        AppPageChrome(
            section: selection,
            selection: $selection
        ) {
            detailView(for: selection)
        }
        .groupBoxStyle(HealthCardGroupBoxStyle())
        .tint(HealthThemePalette.accent)
        .toolbar {
            if selection != .settings {
                ToolbarItem(placement: .automatic) {
                    Picker(L10n.choose(simplifiedChinese: "运动", english: "Sport"), selection: $store.selectedSportFilter) {
                        Text(L10n.choose(simplifiedChinese: "全部运动", english: "All Sports")).tag(Optional<SportType>.none)
                        ForEach(SportType.allCases) { sport in
                            Text(verbatim: sport.label).tag(Optional(sport))
                        }
                    }
                    .appDropdownTheme()
                }
            }
        }
        #if os(macOS)
            .frame(minWidth: 1180, minHeight: 760)
        #endif
    }
}

private struct AppPageChrome<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var store: AppStore
    @AppStorage(AppChartDisplayMode.storageKey) private var chartDisplayModeRawValue = AppChartDisplayMode.line.rawValue
    let section: AppSection
    @Binding var selection: AppSection
    @ViewBuilder var content: () -> Content

    private var contentMaxWidth: CGFloat {
        #if os(iOS)
            1320
        #else
            1480
        #endif
    }

    private func panelHorizontalPadding(for width: CGFloat) -> CGFloat {
        width >= 1280 ? 20 : 16
    }

    private func headerPickerWidth(for width: CGFloat) -> CGFloat {
        width >= 1280 ? 260 : 230
    }

    private var chartDisplayMode: AppChartDisplayMode {
        get { AppChartDisplayMode(rawValue: chartDisplayModeRawValue) ?? .line }
        set { chartDisplayModeRawValue = newValue.rawValue }
    }

    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    var body: some View {
        ZStack {
            HealthCanvasBackground()
                .ignoresSafeArea()

            GeometryReader { proxy in
                let availableWidth = proxy.size.width
                let useSidebarLayout = isWidePadLayout(for: availableWidth)

                Group {
                    if useSidebarLayout {
                        HStack(alignment: .top, spacing: 14) {
                            sideNavigationRail(width: availableWidth)
                                .frame(width: 270, alignment: .top)

                            VStack(spacing: 12) {
                                topControlBar(width: availableWidth - 284, showPagePicker: false)
                                contentPanel
                            }
                        }
                    } else {
                        VStack(spacing: 12) {
                            topControlBar(width: availableWidth, showPagePicker: true)
                            contentPanel
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(12)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    HealthThemePalette.surfaceStroke(for: colorScheme).opacity(0.7),
                    lineWidth: 1
                )
                .padding(10)
        )
        .padding(.all, 6)
        #if os(iOS)
            .environment(\.defaultMinListRowHeight, 54)
        #endif
    }

    private var contentPanel: some View {
        content()
            .environment(\.appChartDisplayMode, chartDisplayMode)
            .frame(maxWidth: contentMaxWidth, maxHeight: .infinity, alignment: .topLeading)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private func topControlBar(width: CGFloat, showPagePicker: Bool) -> some View {
        let useHorizontalHeaderLayout = width >= 980
        let useHorizontalPickerLayout = width >= 820

        Group {
            if useHorizontalHeaderLayout {
                HStack(spacing: 12) {
                    headerTitle
                    Spacer(minLength: 8)
                    headerPickersRow(width: width, horizontal: true, showPagePicker: showPagePicker)
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    headerTitle
                    headerPickersRow(width: width, horizontal: useHorizontalPickerLayout, showPagePicker: showPagePicker)
                }
            }
        }
        .padding(.horizontal, panelHorizontalPadding(for: width))
        .padding(.vertical, 12)
        .frame(maxWidth: contentMaxWidth, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .center)
        .healthSurface(cornerRadius: 20)
    }

    private func sideNavigationRail(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.choose(simplifiedChinese: "工作台", english: "Workspace"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            athletePicker(width: width - 26)

            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(AppSection.allCases) { candidate in
                        Button {
                            withAnimation(.easeOut(duration: 0.18)) {
                                selection = candidate
                            }
                        } label: {
                            Label {
                                Text(verbatim: candidate.localizedTitle)
                                    .font(.callout.weight(.semibold))
                            } icon: {
                                Image(systemName: candidate.systemImage)
                                    .frame(width: 20)
                            }
                            .foregroundStyle(selection == candidate ? HealthThemePalette.accent : Color.primary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(selection == candidate ? HealthThemePalette.accent.opacity(0.13) : Color.clear)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
        .frame(maxHeight: .infinity, alignment: .top)
        .healthSurface(cornerRadius: 20)
    }

    private var headerTitle: some View {
        Label {
            Text(verbatim: section.localizedTitle)
        } icon: {
            Image(systemName: section.systemImage)
        }
        .font(.headline.weight(.semibold))
    }

    @ViewBuilder
    private func headerPickersRow(width: CGFloat, horizontal: Bool, showPagePicker: Bool) -> some View {
        Group {
            if horizontal {
                HStack(spacing: 10) {
                    athletePicker(width: width)
                    if showPagePicker {
                        sectionPicker(width: width)
                    }
                }
            } else {
                VStack(spacing: 8) {
                    athletePicker(width: width)
                    if showPagePicker {
                        sectionPicker(width: width)
                    }
                }
            }
        }
    }

    private func athletePicker(width: CGFloat) -> some View {
        Picker(
            L10n.choose(simplifiedChinese: "运动员", english: "Athlete"),
            selection: $store.selectedAthletePanelID
        ) {
            ForEach(store.athletePanels) { athlete in
                Text(athlete.title).tag(athlete.id)
            }
        }
        .appDropdownTheme(width: headerPickerWidth(for: width))
    }

    private func sectionPicker(width: CGFloat) -> some View {
        Picker(L10n.choose(simplifiedChinese: "页面", english: "Page"), selection: $selection) {
            ForEach(AppSection.allCases) { candidate in
                Label {
                    Text(verbatim: candidate.localizedTitle)
                } icon: {
                    Image(systemName: candidate.systemImage)
                }
                .tag(candidate)
            }
        }
        .appDropdownTheme(width: headerPickerWidth(for: width) + 30)
    }

    private func isWidePadLayout(for width: CGFloat) -> Bool {
        #if os(iOS)
            horizontalSizeClass == .regular && width >= 1180
        #else
            false
        #endif
    }
}

private struct ThresholdRangeEditorRow: Identifiable {
    var id: UUID
    var sport: SportType
    var startDate: Date
    var hasEndDate: Bool
    var endDate: Date
    var lthr: String
    var aeTHR: String
    var restingHR: String
    var maxHR: String

    init(range: HeartRateThresholdRange) {
        id = range.id
        sport = range.sport
        startDate = range.startDate
        hasEndDate = range.endDate != nil
        endDate = range.endDate ?? Calendar.current.date(byAdding: .day, value: 1, to: range.startDate) ?? range.startDate
        lthr = String(range.lthr)
        aeTHR = range.aeTHR.map(String.init) ?? ""
        restingHR = range.restingHR.map(String.init) ?? ""
        maxHR = range.maxHR.map(String.init) ?? ""
    }

    init(sport: SportType, startDate: Date, lthr: Int) {
        id = UUID()
        self.sport = sport
        self.startDate = startDate
        hasEndDate = false
        endDate = Calendar.current.date(byAdding: .day, value: 1, to: startDate) ?? startDate
        self.lthr = String(max(1, lthr))
        aeTHR = ""
        restingHR = ""
        maxHR = ""
    }
}

struct SettingsView: View {
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var store: AppStore
    @AppStorage(AppLanguageOption.storageKey) private var appLanguageRawValue = AppLanguageOption.system.rawValue
    @State private var cyclingFTP = ""
    @State private var runningFTP = ""
    @State private var swimmingFTP = ""
    @State private var strengthFTP = ""
    @State private var cyclingThresholdHR = ""
    @State private var runningThresholdHR = ""
    @State private var swimmingThresholdHR = ""
    @State private var strengthThresholdHR = ""
    @State private var cyclingMaxHR = ""
    @State private var runningMaxHR = ""
    @State private var swimmingMaxHR = ""
    @State private var strengthMaxHR = ""
    @State private var athleteAgeYears = ""
    @State private var athleteWeightKg = ""
    @State private var basalMetabolicRateKcal = ""
    @State private var nutritionActivityFactor = ""
    @State private var hrvBaseline = ""
    @State private var hrvToday = ""
    @State private var intervalsKey = ""
    @State private var serverBaseURL = ""
    @State private var stravaClientID = ""
    @State private var stravaClientSecret = ""
    private let stravaOAuthRedirectURI = "http://127.0.0.1:53682/callback"
    @State private var stravaPullRecentDays = 30
    @State private var garminAccessToken = ""
    @State private var garminCSRFToken = ""
    @State private var ouraAccessToken = ""
    @State private var whoopAccessToken = ""
    @State private var appleHealthAccessToken = ""
    @State private var googleFitAccessToken = ""
    @State private var trainingPeaksAccessToken = ""
    @State private var openAIAPIKey = ""
    @State private var serverHost = ""
    @State private var serverPort = ""
    @State private var hasGoalDate = false
    @State private var goalDate = Date()
    @State private var profileEstimate: ProfilePhysioEstimate?
    @State private var estimateStatus: String?
    @State private var thresholdRangeEditorRows: [ThresholdRangeEditorRow] = []
    @State private var thresholdRangeValidationMessage: String?
    @State private var newAthletePanelName = ""
    @State private var showDeleteAthletePanelConfirm = false
    @State private var pendingDeleteAthletePanel: AthletePanel?

    private var appLanguageBinding: Binding<AppLanguageOption> {
        Binding<AppLanguageOption>(
            get: { AppLanguageOption(rawValue: appLanguageRawValue) ?? .system },
            set: { appLanguageRawValue = $0.rawValue }
        )
    }

    private var manageableAthletePanels: [AthletePanel] {
        store.athletePanels.filter { !$0.isAll }
    }

    private func addAthletePanelFromSettings() {
        let trimmed = newAthletePanelName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if let existing = manageableAthletePanels.first(where: {
            $0.title.localizedCaseInsensitiveCompare(trimmed) == .orderedSame
        }) {
            store.selectedAthletePanelID = existing.id
            newAthletePanelName = ""
            return
        }

        store.addTrainerRiderSession(named: trimmed)
        if let created = store.athletePanels.first(where: {
            !$0.isAll && $0.title.localizedCaseInsensitiveCompare(trimmed) == .orderedSame
        }) {
            store.selectedAthletePanelID = created.id
        }
        newAthletePanelName = ""
    }

    private func parseOptionalIntField(_ value: String, fallback: Int) -> Int {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return 0
        }
        return Int(trimmed) ?? fallback
    }

    private func parseOptionalPositiveInt(_ value: String) -> Int? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let parsed = Int(trimmed), parsed > 0 else {
            return nil
        }
        return parsed
    }

    private func thresholdFallback(for sport: SportType) -> Int {
        switch sport {
        case .cycling: return Int(cyclingThresholdHR) ?? store.profile.cyclingThresholdHeartRate
        case .running: return Int(runningThresholdHR) ?? store.profile.runningThresholdHeartRate
        case .swimming: return Int(swimmingThresholdHR) ?? store.profile.swimmingThresholdHeartRate
        case .strength: return Int(strengthThresholdHR) ?? store.profile.strengthThresholdHeartRate
        }
    }

    private func thresholdRowIndices(for sport: SportType) -> [Int] {
        thresholdRangeEditorRows.indices
            .filter { thresholdRangeEditorRows[$0].sport == sport }
            .sorted { thresholdRangeEditorRows[$0].startDate > thresholdRangeEditorRows[$1].startDate }
    }

    private func sortThresholdRows() {
        thresholdRangeEditorRows.sort { lhs, rhs in
            if lhs.sport != rhs.sport {
                return lhs.sport.rawValue < rhs.sport.rawValue
            }
            if lhs.startDate != rhs.startDate {
                return lhs.startDate > rhs.startDate
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    private func addThresholdRow(for sport: SportType) {
        let startDate = Calendar.current.startOfDay(for: Date())
        thresholdRangeEditorRows.append(
            ThresholdRangeEditorRow(
                sport: sport,
                startDate: startDate,
                lthr: thresholdFallback(for: sport)
            )
        )
        sortThresholdRows()
    }

    private func buildThresholdRangesFromEditor() -> [HeartRateThresholdRange]? {
        var output: [HeartRateThresholdRange] = []
        let calendar = Calendar.current
        var errors: [String] = []

        for row in thresholdRangeEditorRows {
            guard let lthr = parseOptionalPositiveInt(row.lthr) else {
                errors.append("\(row.sport.label) 的一条区间缺少有效 LTHR（需 > 0）")
                continue
            }
            let startDay = calendar.startOfDay(for: row.startDate)
            var endDay: Date?
            if row.hasEndDate {
                let candidate = calendar.startOfDay(for: row.endDate)
                if candidate <= startDay {
                    errors.append("\(row.sport.label) 区间结束日必须晚于开始日")
                } else {
                    endDay = candidate
                }
            }
            output.append(
                HeartRateThresholdRange(
                    id: row.id,
                    sport: row.sport,
                    startDate: startDay,
                    endDate: endDay,
                    lthr: lthr,
                    aeTHR: parseOptionalPositiveInt(row.aeTHR),
                    restingHR: parseOptionalPositiveInt(row.restingHR),
                    maxHR: parseOptionalPositiveInt(row.maxHR)
                )
            )
        }

        if !errors.isEmpty {
            thresholdRangeValidationMessage = errors.joined(separator: "；")
            return nil
        }

        thresholdRangeValidationMessage = nil
        return output.sorted { lhs, rhs in
            if lhs.sport != rhs.sport {
                return lhs.sport.rawValue < rhs.sport.rawValue
            }
            if lhs.startDate != rhs.startDate {
                return lhs.startDate > rhs.startDate
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    private func persistProfileFromFields() {
        var profile = store.profile
        profile.cyclingFTPWatts = Int(cyclingFTP) ?? profile.cyclingFTPWatts
        profile.runningFTPWatts = Int(runningFTP) ?? profile.runningFTPWatts
        profile.swimmingFTPWatts = Int(swimmingFTP) ?? profile.swimmingFTPWatts
        profile.strengthFTPWatts = Int(strengthFTP) ?? profile.strengthFTPWatts
        profile.cyclingThresholdHeartRate = Int(cyclingThresholdHR) ?? profile.cyclingThresholdHeartRate
        profile.runningThresholdHeartRate = Int(runningThresholdHR) ?? profile.runningThresholdHeartRate
        profile.swimmingThresholdHeartRate = Int(swimmingThresholdHR) ?? profile.swimmingThresholdHeartRate
        profile.strengthThresholdHeartRate = Int(strengthThresholdHR) ?? profile.strengthThresholdHeartRate
        profile.cyclingMaxHeartRate = parseOptionalIntField(cyclingMaxHR, fallback: profile.cyclingMaxHeartRate)
        profile.runningMaxHeartRate = parseOptionalIntField(runningMaxHR, fallback: profile.runningMaxHeartRate)
        profile.swimmingMaxHeartRate = parseOptionalIntField(swimmingMaxHR, fallback: profile.swimmingMaxHeartRate)
        profile.strengthMaxHeartRate = parseOptionalIntField(strengthMaxHR, fallback: profile.strengthMaxHeartRate)
        // Keep legacy global fields aligned to cycling values.
        profile.ftpWatts = profile.cyclingFTPWatts
        profile.thresholdHeartRate = profile.cyclingThresholdHeartRate
        profile.athleteAgeYears = Int(athleteAgeYears) ?? profile.athleteAgeYears
        profile.athleteWeightKg = Double(athleteWeightKg) ?? profile.athleteWeightKg
        profile.basalMetabolicRateKcal = max(500, Int(basalMetabolicRateKcal) ?? profile.basalMetabolicRateKcal)
        profile.nutritionActivityFactor = min(max(Double(nutritionActivityFactor) ?? profile.nutritionActivityFactor, 1.0), 2.5)
        profile.hrvBaseline = Double(hrvBaseline) ?? profile.hrvBaseline
        profile.hrvToday = Double(hrvToday) ?? profile.hrvToday
        profile.goalRaceDate = hasGoalDate ? goalDate : nil
        profile.intervalsAPIKey = intervalsKey.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.stravaClientID = stravaClientID.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.stravaClientSecret = stravaClientSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.garminConnectAccessToken = garminAccessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.garminConnectCSRFToken = garminCSRFToken.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.ouraPersonalAccessToken = ouraAccessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.whoopAccessToken = whoopAccessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.appleHealthAccessToken = appleHealthAccessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.googleFitAccessToken = googleFitAccessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.trainingPeaksAccessToken = trainingPeaksAccessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.openAIAPIKey = openAIAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let ranges = buildThresholdRangesFromEditor() else {
            return
        }
        profile.hrThresholdRanges = ranges
        store.profile = profile
        store.persistProfile()
    }

    private func persistServerURLFromFields() {
        let trimmed = serverBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            UserDefaults.standard.removeObject(forKey: RemoteHTTPRepository.serverURLDefaultsKey)
            return
        }

        guard let parsed = URL(string: trimmed), parsed.scheme != nil, parsed.host != nil else {
            return
        }

        UserDefaults.standard.set(trimmed, forKey: RemoteHTTPRepository.serverURLDefaultsKey)
    }

    private func loadServerURLField() {
        serverBaseURL = UserDefaults.standard.string(forKey: RemoteHTTPRepository.serverURLDefaultsKey)
            ?? RemoteHTTPRepository.fallbackServerURLString
    }

    private func persistStravaOAuthConfigFromFields() {
        var profile = store.profile
        profile.stravaClientID = stravaClientID.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.stravaClientSecret = stravaClientSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        store.profile = profile
        store.persistProfile()
    }

    private func evaluateProfileEstimate() {
        let scopedActivities = store.athleteScopedActivities
        let estimate = AthleteProfileAutoEstimator.evaluate(
            activities: scopedActivities,
            profile: store.profile
        )
        profileEstimate = estimate
        estimateStatus = L10n.choose(
            simplifiedChinese: "评估完成（\(store.selectedAthleteTitle)）：\(estimate.items.count) 个运动项目，时间 \(estimate.generatedAt.formatted(date: .abbreviated, time: .shortened))",
            english: "Evaluation complete (\(store.selectedAthleteTitle)): \(estimate.items.count) sports at \(estimate.generatedAt.formatted(date: .abbreviated, time: .shortened))."
        )
    }

    private func applyProfileEstimate(_ estimate: ProfilePhysioEstimate) {
        for item in estimate.items {
            switch item.sport {
            case .cycling:
                cyclingFTP = String(item.ftpWatts)
                cyclingThresholdHR = String(item.thresholdHeartRate)
            case .running:
                runningFTP = String(item.ftpWatts)
                runningThresholdHR = String(item.thresholdHeartRate)
            case .swimming:
                swimmingFTP = String(item.ftpWatts)
                swimmingThresholdHR = String(item.thresholdHeartRate)
            case .strength:
                strengthFTP = String(item.ftpWatts)
                strengthThresholdHR = String(item.thresholdHeartRate)
            }
        }
        persistProfileFromFields()
        estimateStatus = L10n.choose(
            simplifiedChinese: "已应用并保存 FTP/LTHR 评估结果。",
            english: "Applied and saved FTP/LTHR evaluation."
        )
    }

    private func loadFieldsFromProfile() {
        cyclingFTP = String(store.profile.cyclingFTPWatts)
        runningFTP = String(store.profile.runningFTPWatts)
        swimmingFTP = String(store.profile.swimmingFTPWatts)
        strengthFTP = String(store.profile.strengthFTPWatts)
        cyclingThresholdHR = String(store.profile.cyclingThresholdHeartRate)
        runningThresholdHR = String(store.profile.runningThresholdHeartRate)
        swimmingThresholdHR = String(store.profile.swimmingThresholdHeartRate)
        strengthThresholdHR = String(store.profile.strengthThresholdHeartRate)
        cyclingMaxHR = store.profile.cyclingMaxHeartRate > 0 ? String(store.profile.cyclingMaxHeartRate) : ""
        runningMaxHR = store.profile.runningMaxHeartRate > 0 ? String(store.profile.runningMaxHeartRate) : ""
        swimmingMaxHR = store.profile.swimmingMaxHeartRate > 0 ? String(store.profile.swimmingMaxHeartRate) : ""
        strengthMaxHR = store.profile.strengthMaxHeartRate > 0 ? String(store.profile.strengthMaxHeartRate) : ""
        athleteAgeYears = String(store.profile.athleteAgeYears)
        athleteWeightKg = String(format: "%.1f", store.profile.athleteWeightKg)
        basalMetabolicRateKcal = String(store.profile.basalMetabolicRateKcal)
        nutritionActivityFactor = String(format: "%.2f", store.profile.nutritionActivityFactor)
        hrvBaseline = String(format: "%.1f", store.profile.hrvBaseline)
        hrvToday = String(format: "%.1f", store.profile.hrvToday)
        intervalsKey = store.profile.intervalsAPIKey
        stravaClientID = store.profile.stravaClientID
        stravaClientSecret = store.profile.stravaClientSecret
        garminAccessToken = store.profile.garminConnectAccessToken
        garminCSRFToken = store.profile.garminConnectCSRFToken
        ouraAccessToken = store.profile.ouraPersonalAccessToken
        whoopAccessToken = store.profile.whoopAccessToken
        appleHealthAccessToken = store.profile.appleHealthAccessToken
        googleFitAccessToken = store.profile.googleFitAccessToken
        trainingPeaksAccessToken = store.profile.trainingPeaksAccessToken
        openAIAPIKey = store.profile.openAIAPIKey
        serverHost = store.serverHost
        serverPort = store.serverPort
        if let goal = store.profile.goalRaceDate {
            hasGoalDate = true
            goalDate = goal
        } else {
            hasGoalDate = false
        }
        thresholdRangeEditorRows = store.profile.hrThresholdRanges
            .map(ThresholdRangeEditorRow.init)
        sortThresholdRows()
        thresholdRangeValidationMessage = nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Athlete Profile")
                        .font(.title3.bold())
                    Text("Inputs for load modeling, TSS estimation, and AI recommendations.")
                        .foregroundStyle(.secondary)
                    Text("\(L10n.choose(simplifiedChinese: "当前面板", english: "Current Panel")): \(store.selectedAthleteTitle)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                GroupBox(L10n.string("settings.language.title")) {
                    Picker(L10n.string("settings.language.picker"), selection: appLanguageBinding) {
                        ForEach(AppLanguageOption.allCases) { option in
                            Text(verbatim: option.localizedTitle).tag(option)
                        }
                    }
                    .appDropdownTheme()
                }

                GroupBox(L10n.choose(simplifiedChinese: "运动员面板管理", english: "Athlete Panel Management")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(
                            L10n.choose(
                                simplifiedChinese: "新增/删除入口统一在此处。页面顶部下拉框用于切换当前运动员。",
                                english: "Add/delete athlete panels only here. Use the top dropdown to switch current athlete."
                            )
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)

                        HStack(spacing: 8) {
                            TextField(
                                L10n.choose(simplifiedChinese: "新运动员名称", english: "New athlete name"),
                                text: $newAthletePanelName
                            )
                            .textFieldStyle(.roundedBorder)
                            .onSubmit {
                                addAthletePanelFromSettings()
                            }

                            Button(
                                L10n.choose(
                                    simplifiedChinese: "新增运动员面板",
                                    english: "Add Athlete Panel"
                                )
                            ) {
                                addAthletePanelFromSettings()
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(newAthletePanelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }

                        if manageableAthletePanels.isEmpty {
                            Text(L10n.choose(simplifiedChinese: "暂无运动员面板", english: "No athlete panels"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(manageableAthletePanels) { panel in
                                HStack(spacing: 10) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(panel.title)
                                            .font(.subheadline.weight(.semibold))
                                        Text(
                                            L10n.choose(
                                                simplifiedChinese: "活动数 \(panel.count)",
                                                english: "Activities \(panel.count)"
                                            )
                                        )
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    }

                                    Spacer()

                                    if panel.id == store.selectedAthletePanelID {
                                        Text(L10n.choose(simplifiedChinese: "当前", english: "Current"))
                                            .font(.caption2)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 3)
                                            .background(.blue.opacity(0.14), in: Capsule())
                                    }

                                    if store.canDeleteAthletePanel(panelID: panel.id) {
                                        Button(
                                            L10n.choose(simplifiedChinese: "删除", english: "Delete"),
                                            role: .destructive
                                        ) {
                                            pendingDeleteAthletePanel = panel
                                            showDeleteAthletePanelConfirm = true
                                        }
                                        .buttonStyle(.bordered)
                                    } else {
                                        Text(L10n.choose(simplifiedChinese: "主骑手", english: "Primary Rider"))
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }
                    .padding(.top, 4)
                }

                GroupBox("Cycling") {
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                        GridRow {
                            Text("FTP (W)")
                            TextField("260", text: $cyclingFTP)
                                .textFieldStyle(.roundedBorder)
                        }
                        GridRow {
                            Text("Threshold HR")
                            TextField("172", text: $cyclingThresholdHR)
                                .textFieldStyle(.roundedBorder)
                        }
                        GridRow {
                            Text("Max HR (optional)")
                            TextField("190", text: $cyclingMaxHR)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                    .padding(.top, 4)
                }

                GroupBox("Running") {
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                        GridRow {
                            Text("FTP (W)")
                            TextField("260", text: $runningFTP)
                                .textFieldStyle(.roundedBorder)
                        }
                        GridRow {
                            Text("Threshold HR")
                            TextField("176", text: $runningThresholdHR)
                                .textFieldStyle(.roundedBorder)
                        }
                        GridRow {
                            Text("Max HR (optional)")
                            TextField("195", text: $runningMaxHR)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                    .padding(.top, 4)
                }

                GroupBox("Swimming") {
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                        GridRow {
                            Text("FTP (W)")
                            TextField("230", text: $swimmingFTP)
                                .textFieldStyle(.roundedBorder)
                        }
                        GridRow {
                            Text("Threshold HR")
                            TextField("164", text: $swimmingThresholdHR)
                                .textFieldStyle(.roundedBorder)
                        }
                        GridRow {
                            Text("Max HR (optional)")
                            TextField("185", text: $swimmingMaxHR)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                    .padding(.top, 4)
                }

                GroupBox("Strength") {
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                        GridRow {
                            Text("FTP (W)")
                            TextField("260", text: $strengthFTP)
                                .textFieldStyle(.roundedBorder)
                        }
                        GridRow {
                            Text("Threshold HR")
                            TextField("172", text: $strengthThresholdHR)
                                .textFieldStyle(.roundedBorder)
                        }
                        GridRow {
                            Text("Max HR (optional)")
                            TextField("190", text: $strengthMaxHR)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                    .padding(.top, 4)
                }

                GroupBox("Recovery & Race") {
                    VStack(alignment: .leading, spacing: 8) {
                        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                            GridRow {
                                Text("Athlete Age")
                                TextField("34", text: $athleteAgeYears)
                                    .textFieldStyle(.roundedBorder)
                            }
                            GridRow {
                                Text("Body Weight (kg)")
                                TextField("69.0", text: $athleteWeightKg)
                                    .textFieldStyle(.roundedBorder)
                            }
                            GridRow {
                                Text("HRV Baseline (All Sports)")
                                TextField("62", text: $hrvBaseline)
                                    .textFieldStyle(.roundedBorder)
                            }
                            GridRow {
                                Text("HRV Today (All Sports)")
                                TextField("58", text: $hrvToday)
                                    .textFieldStyle(.roundedBorder)
                            }
                        }

                        Toggle("Set goal race date", isOn: $hasGoalDate)
                        if hasGoalDate {
                            DatePicker("Goal Race Date", selection: $goalDate, displayedComponents: .date)
                        }
                    }
                    .padding(.top, 4)
                }

                GroupBox(L10n.choose(simplifiedChinese: "Nutrition Profile", english: "Nutrition Profile")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(
                            L10n.choose(
                                simplifiedChinese: "按运动员区分营养基础参数。饮食页面会基于 BMR 和活动系数生成默认热量/三餐目标。",
                                english: "Nutrition baseline settings are athlete-specific. Nutrition page will use BMR and activity factor to generate default calories and meal targets."
                            )
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)

                        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                            GridRow {
                                Text(L10n.choose(simplifiedChinese: "基础代谢 BMR (kcal)", english: "BMR (kcal)"))
                                TextField("1650", text: $basalMetabolicRateKcal)
                                    .textFieldStyle(.roundedBorder)
                            }
                            GridRow {
                                Text(L10n.choose(simplifiedChinese: "日常活动系数", english: "Daily activity factor"))
                                TextField("1.35", text: $nutritionActivityFactor)
                                    .textFieldStyle(.roundedBorder)
                            }
                            GridRow {
                                Text(L10n.choose(simplifiedChinese: "维持热量估算", english: "Estimated maintenance"))
                                Text("\(Int((Double(max(500, Int(basalMetabolicRateKcal) ?? store.profile.basalMetabolicRateKcal)) * min(max(Double(nutritionActivityFactor) ?? store.profile.nutritionActivityFactor, 1.0), 2.5)).rounded())) kcal/day")
                                    .font(.body.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.top, 4)
                }

                GroupBox("FTP / Threshold HR Evaluation") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(
                            L10n.choose(
                                simplifiedChinese: "基于最近 120 天活动，自动评估每个运动的 FTP 和阈值心率（LTHR）。",
                                english: "Automatically estimate sport-specific FTP and LTHR from the last 120 days of activities."
                            )
                        )
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack {
                            Button(L10n.choose(simplifiedChinese: "评估 FTP + LTHR", english: "Estimate FTP + LTHR")) {
                                evaluateProfileEstimate()
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(store.athleteScopedActivities.isEmpty)

                            if let estimate = profileEstimate {
                                Button(L10n.choose(simplifiedChinese: "应用评估并保存", english: "Apply Estimate & Save")) {
                                    applyProfileEstimate(estimate)
                                }
                                .buttonStyle(.bordered)
                            }
                        }

                        if let estimateStatus {
                            Text(estimateStatus)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if let estimate = profileEstimate {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(estimate.items) { item in
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(
                                            L10n.choose(
                                                simplifiedChinese: "\(item.sport.label): FTP \(item.ftpWatts)W (\(item.ftpConfidence)，样本 \(item.ftpSamples)) · LTHR \(item.thresholdHeartRate)bpm (\(item.thresholdConfidence)，样本 \(item.thresholdSamples))",
                                                english: "\(item.sport.label): FTP \(item.ftpWatts)W (\(item.ftpConfidence), samples \(item.ftpSamples)) · LTHR \(item.thresholdHeartRate)bpm (\(item.thresholdConfidence), samples \(item.thresholdSamples))"
                                            )
                                        )
                                            .font(.subheadline.monospacedDigit())
                                        Text(item.methodSummary)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.top, 4)
                }

                GroupBox(L10n.choose(simplifiedChinese: "LTHR 区间表（GC 风格）", english: "LTHR Range Table (GC Style)")) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(
                            L10n.choose(
                                simplifiedChinese: "可按运动编辑起止日期和阈值参数。结束日期为空表示持续生效。",
                                english: "Edit start/end dates and threshold parameters per sport. Empty end date means still active."
                            )
                        )
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        ForEach(SportType.allCases) { sport in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(sport.label)
                                        .font(.headline)
                                    Spacer()
                                    Button(
                                        L10n.choose(
                                            simplifiedChinese: "新增 \(sport.label) 区间",
                                            english: "Add \(sport.label) Range"
                                        )
                                    ) {
                                        addThresholdRow(for: sport)
                                    }
                                    .buttonStyle(.bordered)
                                }

                                let indices = thresholdRowIndices(for: sport)
                                if indices.isEmpty {
                                    Text(L10n.choose(simplifiedChinese: "暂无区间", english: "No ranges"))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                } else {
                                    ForEach(indices, id: \.self) { index in
                                        VStack(alignment: .leading, spacing: 8) {
                                            HStack {
                                                DatePicker(
                                                    L10n.choose(simplifiedChinese: "开始", english: "Start"),
                                                    selection: $thresholdRangeEditorRows[index].startDate,
                                                    displayedComponents: .date
                                                )
                                                Toggle(
                                                    L10n.choose(simplifiedChinese: "结束日期", english: "End Date"),
                                                    isOn: $thresholdRangeEditorRows[index].hasEndDate
                                                )
                                                    #if os(macOS)
                                                        .toggleStyle(.checkbox)
                                                    #endif
                                                    .frame(width: 110)
                                                if thresholdRangeEditorRows[index].hasEndDate {
                                                    DatePicker(
                                                        L10n.choose(simplifiedChinese: "结束", english: "End"),
                                                        selection: $thresholdRangeEditorRows[index].endDate,
                                                        displayedComponents: .date
                                                    )
                                                }
                                                Spacer()
                                                Button(role: .destructive) {
                                                    thresholdRangeEditorRows.remove(at: index)
                                                } label: {
                                                    Label(
                                                        L10n.choose(simplifiedChinese: "删除", english: "Delete"),
                                                        systemImage: "trash"
                                                    )
                                                }
                                                .buttonStyle(.borderless)
                                            }

                                            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
                                                GridRow {
                                                    Text("LTHR")
                                                    TextField("172", text: $thresholdRangeEditorRows[index].lthr)
                                                        .textFieldStyle(.roundedBorder)
                                                }
                                                GridRow {
                                                    Text("AeTHR")
                                                    TextField("155 (optional)", text: $thresholdRangeEditorRows[index].aeTHR)
                                                        .textFieldStyle(.roundedBorder)
                                                }
                                                GridRow {
                                                    Text("RHR")
                                                    TextField("52 (optional)", text: $thresholdRangeEditorRows[index].restingHR)
                                                        .textFieldStyle(.roundedBorder)
                                                }
                                                GridRow {
                                                    Text("Max HR")
                                                    TextField("190 (optional)", text: $thresholdRangeEditorRows[index].maxHR)
                                                        .textFieldStyle(.roundedBorder)
                                                }
                                            }
                                        }
                                        .padding(8)
                                        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
                                    }
                                }
                            }
                        }

                        if let thresholdRangeValidationMessage {
                            Text(
                                L10n.choose(
                                    simplifiedChinese: "区间表校验失败：\(thresholdRangeValidationMessage)",
                                    english: "Range validation failed: \(thresholdRangeValidationMessage)"
                                )
                            )
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                    .padding(.top, 4)
                }

                GroupBox(L10n.choose(simplifiedChinese: "服务与集成配置", english: "Service & Integration Configuration")) {
                    VStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Intervals.icu API Key")
                                .font(.headline)
                            SecureField("API key", text: $intervalsKey)
                                .textFieldStyle(.roundedBorder)
                        }

                        Divider()

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Strava")
                                .font(.headline)
                            Text(
                                L10n.choose(
                                    simplifiedChinese: "先填写 Strava App 的 Client ID / Client Secret，然后执行 OAuth 授权。",
                                    english: "Fill Strava App Client ID / Client Secret first, then run OAuth authorization."
                                )
                            )
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            TextField("Strava Client ID", text: $stravaClientID)
                                .textFieldStyle(.roundedBorder)
                            SecureField("Strava Client Secret", text: $stravaClientSecret)
                                .textFieldStyle(.roundedBorder)
                            HStack {
                                Button(L10n.choose(simplifiedChinese: "OAuth 登录并回调", english: "OAuth Login + Callback")) {
                                    persistStravaOAuthConfigFromFields()
                                    Task {
                                        await store.syncAuthorizeStravaOAuth(redirectURI: stravaOAuthRedirectURI) { authURL in
                                            openURL(authURL)
                                        }
                                        loadFieldsFromProfile()
                                    }
                                }
                                .buttonStyle(.borderedProminent)

                                Button(L10n.choose(simplifiedChinese: "打开 Strava 应用设置", english: "Open Strava App Settings")) {
                                    if let url = URL(string: "https://www.strava.com/settings/api") {
                                        openURL(url)
                                    }
                                }
                            }
                            Text(
                                L10n.choose(
                                    simplifiedChinese: "回调地址：\(stravaOAuthRedirectURI)",
                                    english: "Redirect URI: \(stravaOAuthRedirectURI)"
                                )
                            )
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(
                                L10n.choose(
                                    simplifiedChinese: "授权 scope: read, read_all, activity:read_all, profile:read_all, activity:write",
                                    english: "OAuth scopes: read, read_all, activity:read_all, profile:read_all, activity:write"
                                )
                            )
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        Divider()

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Wellness / Platform Connectors")
                                .font(.headline)
                            SecureField("Garmin Connect Access Token", text: $garminAccessToken)
                                .textFieldStyle(.roundedBorder)
                            TextField(
                                L10n.choose(
                                    simplifiedChinese: "Garmin Connect Csrf Token（connectus/gc-api 常需）",
                                    english: "Garmin Connect Csrf Token (often required for connectus/gc-api)"
                                ),
                                text: $garminCSRFToken
                            )
                                .textFieldStyle(.roundedBorder)
                            SecureField("Oura Personal Access Token", text: $ouraAccessToken)
                                .textFieldStyle(.roundedBorder)
                            SecureField("WHOOP Access Token", text: $whoopAccessToken)
                                .textFieldStyle(.roundedBorder)
                            SecureField("Apple Health Access Token", text: $appleHealthAccessToken)
                                .textFieldStyle(.roundedBorder)
                            SecureField("Google Fit Access Token", text: $googleFitAccessToken)
                                .textFieldStyle(.roundedBorder)
                            SecureField("TrainingPeaks Access Token", text: $trainingPeaksAccessToken)
                                .textFieldStyle(.roundedBorder)
                        }

<<<<<<< ours
                VStack(alignment: .leading, spacing: 8) {
                    Text("Backend Server")
                        .font(.headline)
                    TextField("http://127.0.0.1:8080", text: $serverBaseURL)
                        .textFieldStyle(.roundedBorder)
                    Text(
                        L10n.choose(
                            simplifiedChinese: "用于活动/计划/档案数据的服务端地址。留空会回退到默认 http://127.0.0.1:8080。",
                            english: "Server base URL for activity/workout/profile persistence. Leave blank to use default http://127.0.0.1:8080."
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Wellness / Platform Connectors")
                        .font(.headline)
                    SecureField("Garmin Connect Access Token", text: $garminAccessToken)
                        .textFieldStyle(.roundedBorder)
                    TextField(
                        L10n.choose(
                            simplifiedChinese: "Garmin Connect Csrf Token（connectus/gc-api 常需）",
                            english: "Garmin Connect Csrf Token (often required for connectus/gc-api)"
                        ),
                        text: $garminCSRFToken
                    )
                        .textFieldStyle(.roundedBorder)
                    SecureField("Oura Personal Access Token", text: $ouraAccessToken)
                        .textFieldStyle(.roundedBorder)
                    SecureField("WHOOP Access Token", text: $whoopAccessToken)
                        .textFieldStyle(.roundedBorder)
                    SecureField("Apple Health Access Token", text: $appleHealthAccessToken)
                        .textFieldStyle(.roundedBorder)
                    SecureField("Google Fit Access Token", text: $googleFitAccessToken)
                        .textFieldStyle(.roundedBorder)
                    SecureField("TrainingPeaks Access Token", text: $trainingPeaksAccessToken)
                        .textFieldStyle(.roundedBorder)
                }
=======
                        Divider()
>>>>>>> theirs

                        VStack(alignment: .leading, spacing: 8) {
                            Text("GPT / OpenAI")
                                .font(.headline)
                            SecureField("API key", text: $openAIAPIKey)
                                .textFieldStyle(.roundedBorder)
                        }

                        Divider()

                        VStack(alignment: .leading, spacing: 8) {
                            Text(L10n.choose(simplifiedChinese: "服务端连接", english: "Server Connection"))
                                .font(.headline)
                            TextField("Server IP / Host", text: $serverHost)
                                .textFieldStyle(.roundedBorder)
                            TextField("Server Port", text: $serverPort)
                                .textFieldStyle(.roundedBorder)
                            Button(L10n.choose(simplifiedChinese: "应用服务端地址", english: "Apply Server Endpoint")) {
                                store.updateServerEndpoint(host: serverHost, port: serverPort)
                            }
                            .buttonStyle(.bordered)
                            Text(L10n.choose(
                                simplifiedChinese: "示例：http://127.0.0.1:8080；修改后会立即重建客户端连接。",
                                english: "Example: http://127.0.0.1:8080. Applying will rebuild the server client immediately."
                            ))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                }

                Button("Save Profile") {
                    persistProfileFromFields()
                    persistServerURLFromFields()
                }
                .buttonStyle(.borderedProminent)

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Intervals.icu Sync")
                        .font(.headline)
                    HStack {
                        Button("Pull Activities") {
                            Task { await store.syncPullActivitiesFromIntervals() }
                        }
                        Button("Push Activities") {
                            Task { await store.syncPushActivitiesToIntervals() }
                        }
                    }
                    HStack {
                        Button("Pull Workouts") {
                            Task { await store.syncPullWorkoutsFromIntervals() }
                        }
                        Button("Push Workouts") {
                            Task { await store.syncPushWorkoutsToIntervals() }
                        }
                    }
                    Button("Pull HRV / Wellness") {
                        Task { await store.syncPullWellnessFromIntervals() }
                    }
                    Button("Pull Calendar Events") {
                        Task { await store.syncPullEventsFromIntervals() }
                    }
                    Divider()
                    HStack {
                        Button("Full Pull (A/W/Wellness/Events)") {
                            Task { await store.syncPullEverythingFromIntervals() }
                        }
                        .buttonStyle(.borderedProminent)

                        Button("Bi-Sync (Push + Pull All)") {
                            Task { await store.syncBidirectionalIntervals() }
                        }
                    }
                }
                .disabled(store.isSyncing)

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Strava Sync")
                        .font(.headline)
                    HStack(alignment: .center, spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(L10n.choose(simplifiedChinese: "最近天数", english: "Recent Days"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Picker("", selection: $stravaPullRecentDays) {
                                ForEach([3, 7, 14, 30, 60, 90, 180], id: \.self) { days in
                                    Text(L10n.choose(
                                        simplifiedChinese: "最近 \(days) 天",
                                        english: "Last \(days) days"
                                    )).tag(days)
                                }
                            }
                            .labelsHidden()
                            .appDropdownTheme()
                            .frame(maxWidth: 180)
                        }

                        Button("Pull Activities from Strava") {
                            Task { await store.syncPullActivitiesFromStrava(days: stravaPullRecentDays) }
                        }
                    }
                    Text(
                        L10n.choose(
                            simplifiedChinese: "按选择的最近天数从 Strava 拉取活动明细。",
                            english: "Pull activities from Strava for the selected recent-day range."
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .disabled(store.isSyncing)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Garmin Connect Sync")
                        .font(.headline)
                    Button("Pull Activities from Garmin Connect") {
                        Task { await store.syncPullActivitiesFromGarminConnect() }
                    }
                    Text(
                        L10n.choose(
                            simplifiedChinese: "Token 可填 Bearer token 或 Cookie 串（如 SESSION=...; ...）。",
                            english: "Token can be a Bearer token or a Cookie string (for example: SESSION=...; ...)."
                        )
                    )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(
                        L10n.choose(
                            simplifiedChinese: "中国区 connectus.garmin.cn 建议额外填写 Connect-Csrf-Token。",
                            english: "For China region connectus.garmin.cn, providing Connect-Csrf-Token is recommended."
                        )
                    )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .disabled(store.isSyncing)

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Wellness Sync")
                        .font(.headline)
                    HStack {
                        Button("Pull Wellness from Garmin") {
                            Task { await store.syncPullWellnessFromGarmin() }
                        }
                        Button("Pull Wellness from Oura") {
                            Task { await store.syncPullWellnessFromOura() }
                        }
                        Button("Pull Wellness from WHOOP") {
                            Task { await store.syncPullWellnessFromWhoop() }
                        }
                    }
                }
                .disabled(store.isSyncing)

                if let status = store.syncStatus {
                    Text(status)
                        .foregroundStyle(.secondary)
                }

                if let message = store.lastError {
                    Text(message)
                        .foregroundStyle(.red)
                }

                Text(
                    L10n.choose(
                        simplifiedChinese: "计划训练库总分钟数：\(store.totalWorkoutMinutes)",
                        english: "Planned workout minutes in library: \(store.totalWorkoutMinutes)"
                    )
                )
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
        .frame(width: 700, height: 700)
        .onAppear {
            loadFieldsFromProfile()
            loadServerURLField()
        }
        .onChange(of: store.selectedAthletePanelID) { _, _ in
            profileEstimate = nil
            estimateStatus = nil
            loadFieldsFromProfile()
        }
        .confirmationDialog(
            L10n.choose(simplifiedChinese: "删除运动员面板？", english: "Delete athlete panel?"),
            isPresented: $showDeleteAthletePanelConfirm,
            titleVisibility: .visible
        ) {
            if let panel = pendingDeleteAthletePanel {
                Button(
                    L10n.choose(simplifiedChinese: "删除面板与相关数据", english: "Delete Panel + Data"),
                    role: .destructive
                ) {
                    store.deleteAthletePanelAndAssociatedData(panelID: panel.id)
                    pendingDeleteAthletePanel = nil
                }
            }
            Button(L10n.choose(simplifiedChinese: "取消", english: "Cancel"), role: .cancel) {
                pendingDeleteAthletePanel = nil
            }
        } message: {
            if let panel = pendingDeleteAthletePanel {
                Text(
                    L10n.choose(
                        simplifiedChinese: "将删除 \(panel.title) 的活动、训练计划、饮食计划、wellness 数据和日历事件。此操作不可撤销。",
                        english: "This will delete activities, workouts, meal plans, wellness data, and calendar events for \(panel.title). This cannot be undone."
                    )
                )
            }
        }
    }
}
