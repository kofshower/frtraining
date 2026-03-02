import Foundation

enum SportType: String, Codable, CaseIterable, Identifiable {
    case cycling
    case running
    case swimming
    case strength

    var id: String { rawValue }

    private var labelKey: String {
        switch self {
        case .cycling: return "sport.cycling"
        case .running: return "sport.running"
        case .swimming: return "sport.swimming"
        case .strength: return "sport.strength"
        }
    }

    private var englishLabel: String {
        switch self {
        case .cycling: return "Cycling"
        case .running: return "Running"
        case .swimming: return "Swimming"
        case .strength: return "Strength"
        }
    }

    private var simplifiedChineseLabel: String {
        switch self {
        case .cycling: return "骑行"
        case .running: return "跑步"
        case .swimming: return "游泳"
        case .strength: return "力量"
        }
    }

    private var hardFallbackLabel: String {
        let raw = UserDefaults.standard.string(forKey: AppLanguageOption.storageKey) ?? AppLanguageOption.system.rawValue
        let option = AppLanguageOption(rawValue: raw) ?? .system
        switch option {
        case .english:
            return englishLabel
        case .simplifiedChinese:
            return simplifiedChineseLabel
        case .system:
            let prefersChinese = Locale.preferredLanguages.first?.lowercased().hasPrefix("zh") == true
            return prefersChinese ? simplifiedChineseLabel : englishLabel
        }
    }

    var label: String {
        let localized = L10n.string(labelKey)
        return localized == labelKey ? hardFallbackLabel : localized
    }
}

enum TrainerAvatarSkinTone: String, Codable, CaseIterable, Identifiable {
    case veryLight
    case light
    case medium
    case tan
    case deep

    var id: String { rawValue }

    var title: String {
        switch self {
        case .veryLight: return L10n.choose(simplifiedChinese: "很浅", english: "Very Light")
        case .light: return L10n.choose(simplifiedChinese: "浅色", english: "Light")
        case .medium: return L10n.choose(simplifiedChinese: "中等", english: "Medium")
        case .tan: return L10n.choose(simplifiedChinese: "小麦色", english: "Tan")
        case .deep: return L10n.choose(simplifiedChinese: "深色", english: "Deep")
        }
    }

    var rgb: (Double, Double, Double) {
        switch self {
        case .veryLight: return (0.98, 0.84, 0.74)
        case .light: return (0.93, 0.75, 0.62)
        case .medium: return (0.80, 0.62, 0.48)
        case .tan: return (0.64, 0.46, 0.33)
        case .deep: return (0.42, 0.29, 0.20)
        }
    }
}

enum TrainerBikeModel: String, Codable, CaseIterable, Identifiable {
    case road
    case aero
    case climbing
    case timeTrial

    var id: String { rawValue }

    var title: String {
        switch self {
        case .road: return L10n.choose(simplifiedChinese: "公路车", english: "Road")
        case .aero: return L10n.choose(simplifiedChinese: "空气动力", english: "Aero")
        case .climbing: return L10n.choose(simplifiedChinese: "爬坡车", english: "Climbing")
        case .timeTrial: return L10n.choose(simplifiedChinese: "计时车", english: "Time Trial")
        }
    }
}

enum TrainerBikePaint: String, Codable, CaseIterable, Identifiable {
    case stealthBlack
    case raceRed
    case oceanBlue
    case neonGreen
    case pearlWhite

    var id: String { rawValue }

    var title: String {
        switch self {
        case .stealthBlack: return L10n.choose(simplifiedChinese: "隐形黑", english: "Stealth Black")
        case .raceRed: return L10n.choose(simplifiedChinese: "竞速红", english: "Race Red")
        case .oceanBlue: return L10n.choose(simplifiedChinese: "海洋蓝", english: "Ocean Blue")
        case .neonGreen: return L10n.choose(simplifiedChinese: "荧光绿", english: "Neon Green")
        case .pearlWhite: return L10n.choose(simplifiedChinese: "珍珠白", english: "Pearl White")
        }
    }

    var rgb: (Double, Double, Double) {
        switch self {
        case .stealthBlack: return (0.12, 0.13, 0.15)
        case .raceRed: return (0.88, 0.18, 0.22)
        case .oceanBlue: return (0.16, 0.46, 0.93)
        case .neonGreen: return (0.20, 0.84, 0.38)
        case .pearlWhite: return (0.93, 0.94, 0.96)
        }
    }
}

enum TrainerWheelsetStyle: String, Codable, CaseIterable, Identifiable {
    case shallow
    case deep
    case discRear

    var id: String { rawValue }

    var title: String {
        switch self {
        case .shallow: return L10n.choose(simplifiedChinese: "浅框", english: "Shallow")
        case .deep: return L10n.choose(simplifiedChinese: "高框", english: "Deep")
        case .discRear: return L10n.choose(simplifiedChinese: "后轮碟", english: "Rear Disc")
        }
    }
}

enum TrainerJerseyColor: String, Codable, CaseIterable, Identifiable {
    case white
    case black
    case red
    case blue
    case green
    case yellow

    var id: String { rawValue }

    var title: String {
        switch self {
        case .white: return L10n.choose(simplifiedChinese: "白", english: "White")
        case .black: return L10n.choose(simplifiedChinese: "黑", english: "Black")
        case .red: return L10n.choose(simplifiedChinese: "红", english: "Red")
        case .blue: return L10n.choose(simplifiedChinese: "蓝", english: "Blue")
        case .green: return L10n.choose(simplifiedChinese: "绿", english: "Green")
        case .yellow: return L10n.choose(simplifiedChinese: "黄", english: "Yellow")
        }
    }

    var rgb: (Double, Double, Double) {
        switch self {
        case .white: return (0.95, 0.95, 0.96)
        case .black: return (0.15, 0.16, 0.18)
        case .red: return (0.89, 0.23, 0.27)
        case .blue: return (0.19, 0.48, 0.92)
        case .green: return (0.20, 0.76, 0.44)
        case .yellow: return (0.96, 0.83, 0.22)
        }
    }
}

enum TrainerBibColor: String, Codable, CaseIterable, Identifiable {
    case black
    case navy
    case gray
    case white

    var id: String { rawValue }

    var title: String {
        switch self {
        case .black: return L10n.choose(simplifiedChinese: "黑", english: "Black")
        case .navy: return L10n.choose(simplifiedChinese: "藏蓝", english: "Navy")
        case .gray: return L10n.choose(simplifiedChinese: "灰", english: "Gray")
        case .white: return L10n.choose(simplifiedChinese: "白", english: "White")
        }
    }

    var rgb: (Double, Double, Double) {
        switch self {
        case .black: return (0.10, 0.11, 0.13)
        case .navy: return (0.10, 0.19, 0.34)
        case .gray: return (0.45, 0.48, 0.52)
        case .white: return (0.90, 0.91, 0.93)
        }
    }
}

enum TrainerHelmetStyle: String, Codable, CaseIterable, Identifiable {
    case road
    case aero
    case timeTrial

    var id: String { rawValue }

    var title: String {
        switch self {
        case .road: return L10n.choose(simplifiedChinese: "公路", english: "Road")
        case .aero: return L10n.choose(simplifiedChinese: "气动", english: "Aero")
        case .timeTrial: return L10n.choose(simplifiedChinese: "计时", english: "TT")
        }
    }
}

enum TrainerHelmetColor: String, Codable, CaseIterable, Identifiable {
    case white
    case black
    case red
    case blue
    case neon

    var id: String { rawValue }

    var title: String {
        switch self {
        case .white: return L10n.choose(simplifiedChinese: "白", english: "White")
        case .black: return L10n.choose(simplifiedChinese: "黑", english: "Black")
        case .red: return L10n.choose(simplifiedChinese: "红", english: "Red")
        case .blue: return L10n.choose(simplifiedChinese: "蓝", english: "Blue")
        case .neon: return L10n.choose(simplifiedChinese: "荧光", english: "Neon")
        }
    }

    var rgb: (Double, Double, Double) {
        switch self {
        case .white: return (0.95, 0.96, 0.98)
        case .black: return (0.11, 0.12, 0.13)
        case .red: return (0.89, 0.22, 0.24)
        case .blue: return (0.21, 0.48, 0.93)
        case .neon: return (0.36, 0.92, 0.33)
        }
    }
}

enum TrainerGlassesStyle: String, Codable, CaseIterable, Identifiable {
    case none
    case classic
    case wrap

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return L10n.choose(simplifiedChinese: "无", english: "None")
        case .classic: return L10n.choose(simplifiedChinese: "经典", english: "Classic")
        case .wrap: return L10n.choose(simplifiedChinese: "包覆", english: "Wrap")
        }
    }
}

enum TrainerGlassesTint: String, Codable, CaseIterable, Identifiable {
    case clear
    case smoke
    case mirror
    case amber

    var id: String { rawValue }

    var title: String {
        switch self {
        case .clear: return L10n.choose(simplifiedChinese: "透明", english: "Clear")
        case .smoke: return L10n.choose(simplifiedChinese: "烟灰", english: "Smoke")
        case .mirror: return L10n.choose(simplifiedChinese: "镜面", english: "Mirror")
        case .amber: return L10n.choose(simplifiedChinese: "琥珀", english: "Amber")
        }
    }

    var rgb: (Double, Double, Double) {
        switch self {
        case .clear: return (0.86, 0.90, 0.98)
        case .smoke: return (0.24, 0.26, 0.30)
        case .mirror: return (0.58, 0.72, 0.92)
        case .amber: return (0.86, 0.61, 0.30)
        }
    }
}

enum TrainerShibaFurColor: String, Codable, CaseIterable, Identifiable {
    case redWhite
    case sesame
    case blackTan
    case cream
    case darkRed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .redWhite: return L10n.choose(simplifiedChinese: "赤柴", english: "Red & White")
        case .sesame: return L10n.choose(simplifiedChinese: "胡麻", english: "Sesame")
        case .blackTan: return L10n.choose(simplifiedChinese: "黑柴", english: "Black & Tan")
        case .cream: return L10n.choose(simplifiedChinese: "白柴", english: "Cream")
        case .darkRed: return L10n.choose(simplifiedChinese: "深赤", english: "Dark Red")
        }
    }
}

enum TrainerShibaHarnessColor: String, Codable, CaseIterable, Identifiable {
    case cyan
    case raceRed
    case lime
    case violet
    case charcoal
    case orange

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cyan: return L10n.choose(simplifiedChinese: "青蓝", english: "Cyan")
        case .raceRed: return L10n.choose(simplifiedChinese: "竞速红", english: "Race Red")
        case .lime: return L10n.choose(simplifiedChinese: "荧光绿", english: "Lime")
        case .violet: return L10n.choose(simplifiedChinese: "紫", english: "Violet")
        case .charcoal: return L10n.choose(simplifiedChinese: "炭灰", english: "Charcoal")
        case .orange: return L10n.choose(simplifiedChinese: "橙", english: "Orange")
        }
    }

    var rgb: (Double, Double, Double) {
        switch self {
        case .cyan: return (0.19, 0.82, 0.88)
        case .raceRed: return (0.89, 0.23, 0.27)
        case .lime: return (0.41, 0.92, 0.34)
        case .violet: return (0.59, 0.42, 0.95)
        case .charcoal: return (0.26, 0.28, 0.31)
        case .orange: return (0.96, 0.58, 0.18)
        }
    }
}

enum TrainerShibaGoggleStyle: String, Codable, CaseIterable, Identifiable {
    case none
    case sport
    case wrap
    case retro

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return L10n.choose(simplifiedChinese: "无", english: "None")
        case .sport: return L10n.choose(simplifiedChinese: "运动", english: "Sport")
        case .wrap: return L10n.choose(simplifiedChinese: "包覆", english: "Wrap")
        case .retro: return L10n.choose(simplifiedChinese: "复古", english: "Retro")
        }
    }
}

enum TrainerShibaBodyType: String, Codable, CaseIterable, Identifiable {
    case compact
    case standard
    case athletic
    case chunky

    var id: String { rawValue }

    var title: String {
        switch self {
        case .compact: return L10n.choose(simplifiedChinese: "紧凑", english: "Compact")
        case .standard: return L10n.choose(simplifiedChinese: "标准", english: "Standard")
        case .athletic: return L10n.choose(simplifiedChinese: "运动型", english: "Athletic")
        case .chunky: return L10n.choose(simplifiedChinese: "圆润型", english: "Chunky")
        }
    }
}

struct TrainerRiderAppearance: Codable, Equatable {
    var skinTone: TrainerAvatarSkinTone
    var bikeModel: TrainerBikeModel
    var bikePaint: TrainerBikePaint
    var wheelset: TrainerWheelsetStyle
    var jerseyColor: TrainerJerseyColor
    var bibColor: TrainerBibColor
    var helmetStyle: TrainerHelmetStyle
    var helmetColor: TrainerHelmetColor
    var glassesStyle: TrainerGlassesStyle
    var glassesTint: TrainerGlassesTint
    var shibaFurColor: TrainerShibaFurColor
    var shibaHarnessColor: TrainerShibaHarnessColor
    var shibaGoggleStyle: TrainerShibaGoggleStyle
    var shibaBodyType: TrainerShibaBodyType
    var whooshRunnerModelID: String

    static let `default` = TrainerRiderAppearance(
        skinTone: .medium,
        bikeModel: .road,
        bikePaint: .oceanBlue,
        wheelset: .deep,
        jerseyColor: .blue,
        bibColor: .black,
        helmetStyle: .aero,
        helmetColor: .white,
        glassesStyle: .wrap,
        glassesTint: .smoke,
        shibaFurColor: .redWhite,
        shibaHarnessColor: .cyan,
        shibaGoggleStyle: .wrap,
        shibaBodyType: .standard,
        whooshRunnerModelID: "shiba_pup_run_colored"
    )

    var signature: String {
        "\(skinTone.rawValue)|\(bikeModel.rawValue)|\(bikePaint.rawValue)|\(wheelset.rawValue)|\(jerseyColor.rawValue)|\(bibColor.rawValue)|\(helmetStyle.rawValue)|\(helmetColor.rawValue)|\(glassesStyle.rawValue)|\(glassesTint.rawValue)|\(shibaFurColor.rawValue)|\(shibaHarnessColor.rawValue)|\(shibaGoggleStyle.rawValue)|\(shibaBodyType.rawValue)|\(whooshRunnerModelID)"
    }

    private enum CodingKeys: String, CodingKey {
        case skinTone
        case bikeModel
        case bikePaint
        case wheelset
        case jerseyColor
        case bibColor
        case helmetStyle
        case helmetColor
        case glassesStyle
        case glassesTint
        case shibaFurColor
        case shibaHarnessColor
        case shibaGoggleStyle
        case shibaBodyType
        case whooshRunnerModelID
    }

    init(
        skinTone: TrainerAvatarSkinTone,
        bikeModel: TrainerBikeModel,
        bikePaint: TrainerBikePaint,
        wheelset: TrainerWheelsetStyle,
        jerseyColor: TrainerJerseyColor,
        bibColor: TrainerBibColor,
        helmetStyle: TrainerHelmetStyle,
        helmetColor: TrainerHelmetColor,
        glassesStyle: TrainerGlassesStyle,
        glassesTint: TrainerGlassesTint,
        shibaFurColor: TrainerShibaFurColor,
        shibaHarnessColor: TrainerShibaHarnessColor,
        shibaGoggleStyle: TrainerShibaGoggleStyle,
        shibaBodyType: TrainerShibaBodyType,
        whooshRunnerModelID: String
    ) {
        self.skinTone = skinTone
        self.bikeModel = bikeModel
        self.bikePaint = bikePaint
        self.wheelset = wheelset
        self.jerseyColor = jerseyColor
        self.bibColor = bibColor
        self.helmetStyle = helmetStyle
        self.helmetColor = helmetColor
        self.glassesStyle = glassesStyle
        self.glassesTint = glassesTint
        self.shibaFurColor = shibaFurColor
        self.shibaHarnessColor = shibaHarnessColor
        self.shibaGoggleStyle = shibaGoggleStyle
        self.shibaBodyType = shibaBodyType
        self.whooshRunnerModelID = whooshRunnerModelID
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = TrainerRiderAppearance.default
        self.skinTone = try c.decodeIfPresent(TrainerAvatarSkinTone.self, forKey: .skinTone) ?? defaults.skinTone
        self.bikeModel = try c.decodeIfPresent(TrainerBikeModel.self, forKey: .bikeModel) ?? defaults.bikeModel
        self.bikePaint = try c.decodeIfPresent(TrainerBikePaint.self, forKey: .bikePaint) ?? defaults.bikePaint
        self.wheelset = try c.decodeIfPresent(TrainerWheelsetStyle.self, forKey: .wheelset) ?? defaults.wheelset
        self.jerseyColor = try c.decodeIfPresent(TrainerJerseyColor.self, forKey: .jerseyColor) ?? defaults.jerseyColor
        self.bibColor = try c.decodeIfPresent(TrainerBibColor.self, forKey: .bibColor) ?? defaults.bibColor
        self.helmetStyle = try c.decodeIfPresent(TrainerHelmetStyle.self, forKey: .helmetStyle) ?? defaults.helmetStyle
        self.helmetColor = try c.decodeIfPresent(TrainerHelmetColor.self, forKey: .helmetColor) ?? defaults.helmetColor
        self.glassesStyle = try c.decodeIfPresent(TrainerGlassesStyle.self, forKey: .glassesStyle) ?? defaults.glassesStyle
        self.glassesTint = try c.decodeIfPresent(TrainerGlassesTint.self, forKey: .glassesTint) ?? defaults.glassesTint
        self.shibaFurColor = try c.decodeIfPresent(TrainerShibaFurColor.self, forKey: .shibaFurColor) ?? defaults.shibaFurColor
        self.shibaHarnessColor = try c.decodeIfPresent(TrainerShibaHarnessColor.self, forKey: .shibaHarnessColor) ?? defaults.shibaHarnessColor
        self.shibaGoggleStyle = try c.decodeIfPresent(TrainerShibaGoggleStyle.self, forKey: .shibaGoggleStyle) ?? defaults.shibaGoggleStyle
        self.shibaBodyType = try c.decodeIfPresent(TrainerShibaBodyType.self, forKey: .shibaBodyType) ?? defaults.shibaBodyType
        self.whooshRunnerModelID = try c.decodeIfPresent(String.self, forKey: .whooshRunnerModelID) ?? defaults.whooshRunnerModelID
    }
}

struct IntervalEffort: Codable, Identifiable {
    var id: UUID
    var name: String
    var durationSec: Int
    var targetPower: Int?
    var actualPower: Int?

    init(id: UUID = UUID(), name: String, durationSec: Int, targetPower: Int? = nil, actualPower: Int? = nil) {
        self.id = id
        self.name = name
        self.durationSec = durationSec
        self.targetPower = targetPower
        self.actualPower = actualPower
    }
}

struct Activity: Codable, Identifiable {
    var id: UUID
    var date: Date
    var sport: SportType
    var athleteName: String?
    var durationSec: Int
    var distanceKm: Double
    var tss: Int
    var normalizedPower: Int?
    var avgHeartRate: Int?
    var intervals: [IntervalEffort]
    var notes: String
    var externalID: String?
    var sourceFileName: String?
    var sourceFileType: String?
    var sourceFileBase64: String?
    var bikeComputerScreenshotBase64: String?
    var bikeComputerScreenshotFileName: String?
    var bikeComputerScreenshotMimeType: String?
    var platformPayloadJSON: String?

    init(
        id: UUID = UUID(),
        date: Date,
        sport: SportType,
        athleteName: String? = nil,
        durationSec: Int,
        distanceKm: Double,
        tss: Int,
        normalizedPower: Int? = nil,
        avgHeartRate: Int? = nil,
        intervals: [IntervalEffort] = [],
        notes: String = "",
        externalID: String? = nil,
        sourceFileName: String? = nil,
        sourceFileType: String? = nil,
        sourceFileBase64: String? = nil,
        bikeComputerScreenshotBase64: String? = nil,
        bikeComputerScreenshotFileName: String? = nil,
        bikeComputerScreenshotMimeType: String? = nil,
        platformPayloadJSON: String? = nil
    ) {
        self.id = id
        self.date = date
        self.sport = sport
        self.athleteName = athleteName
        self.durationSec = durationSec
        self.distanceKm = distanceKm
        self.tss = tss
        self.normalizedPower = normalizedPower
        self.avgHeartRate = avgHeartRate
        self.intervals = intervals
        self.notes = notes
        self.externalID = externalID
        self.sourceFileName = sourceFileName
        self.sourceFileType = sourceFileType
        self.sourceFileBase64 = sourceFileBase64
        self.bikeComputerScreenshotBase64 = bikeComputerScreenshotBase64
        self.bikeComputerScreenshotFileName = bikeComputerScreenshotFileName
        self.bikeComputerScreenshotMimeType = bikeComputerScreenshotMimeType
        self.platformPayloadJSON = platformPayloadJSON
    }
}

struct WorkoutSegment: Codable, Identifiable {
    var id: UUID
    var minutes: Int
    var intensityPercentFTP: Int
    var cadence: Int?
    var note: String

    init(id: UUID = UUID(), minutes: Int, intensityPercentFTP: Int, cadence: Int? = nil, note: String = "") {
        self.id = id
        self.minutes = minutes
        self.intensityPercentFTP = intensityPercentFTP
        self.cadence = cadence
        self.note = note
    }
}

struct PlannedWorkout: Codable, Identifiable {
    var id: UUID
    var createdAt: Date
    var name: String
    var sport: SportType
    var athleteName: String?
    var segments: [WorkoutSegment]
    var scheduledDate: Date?
    var externalID: String?

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        name: String,
        sport: SportType,
        athleteName: String? = nil,
        segments: [WorkoutSegment],
        scheduledDate: Date? = nil,
        externalID: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.name = name
        self.sport = sport
        self.athleteName = athleteName
        self.segments = segments
        self.scheduledDate = scheduledDate
        self.externalID = externalID
    }

    var totalMinutes: Int {
        segments.reduce(0) { $0 + $1.minutes }
    }
}

struct CalendarEvent: Codable, Identifiable {
    var id: UUID
    var startDate: Date
    var endDate: Date?
    var type: String
    var category: String
    var name: String
    var athleteName: String?
    var notes: String
    var externalID: String?

    init(
        id: UUID = UUID(),
        startDate: Date,
        endDate: Date? = nil,
        type: String,
        category: String,
        name: String,
        athleteName: String? = nil,
        notes: String = "",
        externalID: String? = nil
    ) {
        self.id = id
        self.startDate = startDate
        self.endDate = endDate
        self.type = type
        self.category = category
        self.name = name
        self.athleteName = athleteName
        self.notes = notes
        self.externalID = externalID
    }
}

struct DailyLoadPoint: Identifiable {
    var id: Date { date }
    var date: Date
    var tss: Double
    var aerobicTISS: Double
    var anaerobicTISS: Double
    var ctl: Double
    var atl: Double
    var tsb: Double
    var aerobicLongTermStress: Double
    var anaerobicLongTermStress: Double
    var aerobicShortTermStress: Double
    var anaerobicShortTermStress: Double
}

struct DashboardSummary {
    var weeklyTSS: Int
    var monthlyDistanceKm: Double
    var currentCTL: Double
    var currentATL: Double
    var currentTSB: Double
}

struct WellnessSample: Codable, Identifiable {
    var id: Date { date }
    var date: Date
    var athleteName: String?
    var hrv: Double?
    var restingHR: Double?
    var weightKg: Double?
    var sleepHours: Double?
    var sleepScore: Double?

    init(
        date: Date,
        athleteName: String? = nil,
        hrv: Double? = nil,
        restingHR: Double? = nil,
        weightKg: Double? = nil,
        sleepHours: Double? = nil,
        sleepScore: Double? = nil
    ) {
        self.date = date
        self.athleteName = athleteName
        self.hrv = hrv
        self.restingHR = restingHR
        self.weightKg = weightKg
        self.sleepHours = sleepHours
        self.sleepScore = sleepScore
    }
}

enum MealSlot: String, Codable, CaseIterable, Identifiable {
    case breakfast
    case lunch
    case dinner
    case snackAM
    case snackPM
    case postWorkout

    var id: String { rawValue }

    var label: String {
        switch self {
        case .breakfast:
            return L10n.choose(simplifiedChinese: "早餐", english: "Breakfast")
        case .lunch:
            return L10n.choose(simplifiedChinese: "午餐", english: "Lunch")
        case .dinner:
            return L10n.choose(simplifiedChinese: "晚餐", english: "Dinner")
        case .snackAM:
            return L10n.choose(simplifiedChinese: "加餐（上午）", english: "Snack (AM)")
        case .snackPM:
            return L10n.choose(simplifiedChinese: "加餐（下午）", english: "Snack (PM)")
        case .postWorkout:
            return L10n.choose(simplifiedChinese: "训练后补给", english: "Post-workout")
        }
    }
}

struct MealPlanItem: Codable, Identifiable {
    var id: UUID
    var slot: MealSlot
    var plannedFood: String
    var actualFood: String
    var plannedCalories: Int
    var actualCalories: Int
    var plannedProtein: Double
    var actualProtein: Double
    var plannedCarbs: Double
    var actualCarbs: Double
    var plannedFat: Double
    var actualFat: Double

    init(
        id: UUID = UUID(),
        slot: MealSlot,
        plannedFood: String = "",
        actualFood: String = "",
        plannedCalories: Int = 0,
        actualCalories: Int = 0,
        plannedProtein: Double = 0,
        actualProtein: Double = 0,
        plannedCarbs: Double = 0,
        actualCarbs: Double = 0,
        plannedFat: Double = 0,
        actualFat: Double = 0
    ) {
        self.id = id
        self.slot = slot
        self.plannedFood = plannedFood
        self.actualFood = actualFood
        self.plannedCalories = plannedCalories
        self.actualCalories = actualCalories
        self.plannedProtein = plannedProtein
        self.actualProtein = actualProtein
        self.plannedCarbs = plannedCarbs
        self.actualCarbs = actualCarbs
        self.plannedFat = plannedFat
        self.actualFat = actualFat
    }

    mutating func applyPlannedToActual() {
        actualFood = plannedFood
        actualCalories = plannedCalories
        actualProtein = plannedProtein
        actualCarbs = plannedCarbs
        actualFat = plannedFat
    }
}

struct MealNutritionTotals {
    var calories: Int = 0
    var protein: Double = 0
    var carbs: Double = 0
    var fat: Double = 0
}

enum NutritionGoalProfile: String, Codable, CaseIterable, Identifiable {
    case balanced
    case keto
    case highCarbFatLoss
    case pregnancyGlycemicControl

    var id: String { rawValue }

    var label: String {
        switch self {
        case .balanced:
            return L10n.choose(simplifiedChinese: "均衡", english: "Balanced")
        case .keto:
            return L10n.choose(simplifiedChinese: "生酮（Keto）", english: "Keto")
        case .highCarbFatLoss:
            return L10n.choose(simplifiedChinese: "高碳减脂", english: "High-carb fat loss")
        case .pregnancyGlycemicControl:
            return L10n.choose(simplifiedChinese: "怀孕控糖", english: "Pregnancy glycemic control")
        }
    }

    var guidanceHint: String {
        switch self {
        case .balanced:
            return L10n.choose(
                simplifiedChinese: "优先完整食物、蛋白质充足、蔬果与纤维稳定。",
                english: "Prioritize whole foods, sufficient protein, and steady vegetables + fiber."
            )
        case .keto:
            return L10n.choose(
                simplifiedChinese: "控制净碳水，保证电解质、蛋白质与脂肪来源质量。",
                english: "Keep net carbs low and ensure electrolytes, protein, and quality fat sources."
            )
        case .highCarbFatLoss:
            return L10n.choose(
                simplifiedChinese: "围绕训练提高碳水质量与时机，同时控制总热量与脂肪过量。",
                english: "Use quality carbs around training while keeping calories controlled and fats moderate."
            )
        case .pregnancyGlycemicControl:
            return L10n.choose(
                simplifiedChinese: "减少高升糖负荷，分餐进食，强调蛋白质/纤维/低 GI 碳水。",
                english: "Reduce glycemic load with smaller meals, emphasizing protein, fiber, and lower-GI carbs."
            )
        }
    }
}

struct MealMacroTarget: Codable, Identifiable, Hashable {
    var id: UUID
    var slot: MealSlot
    var calories: Int
    var protein: Double
    var carbs: Double
    var fat: Double

    init(
        id: UUID = UUID(),
        slot: MealSlot,
        calories: Int = 0,
        protein: Double = 0,
        carbs: Double = 0,
        fat: Double = 0
    ) {
        self.id = id
        self.slot = slot
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
    }

    static func defaultThreeMeals() -> [MealMacroTarget] {
        [
            MealMacroTarget(slot: .breakfast, calories: 550, protein: 30, carbs: 60, fat: 18),
            MealMacroTarget(slot: .lunch, calories: 800, protein: 45, carbs: 95, fat: 24),
            MealMacroTarget(slot: .dinner, calories: 750, protein: 40, carbs: 70, fat: 28)
        ]
    }

    static func normalizedThreeMeals(from input: [MealMacroTarget]) -> [MealMacroTarget] {
        let mealSlots: [MealSlot] = [.breakfast, .lunch, .dinner]
        return mealSlots.map { slot in
            if let existing = input.first(where: { $0.slot == slot }) {
                return MealMacroTarget(
                    id: existing.id,
                    slot: slot,
                    calories: max(0, existing.calories),
                    protein: max(0, existing.protein),
                    carbs: max(0, existing.carbs),
                    fat: max(0, existing.fat)
                )
            }
            return defaultThreeMeals().first(where: { $0.slot == slot }) ?? MealMacroTarget(slot: slot)
        }
    }
}

struct FridgeFoodEntry: Codable, Identifiable, Hashable {
    var id: UUID
    var foodCode: String
    var foodName: String
    var servings: Double
    var servingLabel: String?
    var caloriesPerServing: Int?
    var proteinPerServing: Double?
    var carbsPerServing: Double?
    var fatPerServing: Double?
    var source: String?

    init(
        id: UUID = UUID(),
        foodCode: String,
        foodName: String,
        servings: Double = 1.0,
        servingLabel: String? = nil,
        caloriesPerServing: Int? = nil,
        proteinPerServing: Double? = nil,
        carbsPerServing: Double? = nil,
        fatPerServing: Double? = nil,
        source: String? = nil
    ) {
        self.id = id
        self.foodCode = foodCode
        self.foodName = foodName
        self.servings = servings
        self.servingLabel = servingLabel
        self.caloriesPerServing = caloriesPerServing
        self.proteinPerServing = proteinPerServing
        self.carbsPerServing = carbsPerServing
        self.fatPerServing = fatPerServing
        self.source = source
    }
}

enum FoodLibraryCategory: String, CaseIterable, Codable, Identifiable {
    case protein
    case carb
    case fat
    case vegetable
    case fruit
    case dairy
    case beverage
    case condiment
    case snack

    var id: String { rawValue }

    var label: String {
        switch self {
        case .protein:
            return L10n.choose(simplifiedChinese: "蛋白质", english: "Protein")
        case .carb:
            return L10n.choose(simplifiedChinese: "主食/碳水", english: "Carbs")
        case .fat:
            return L10n.choose(simplifiedChinese: "脂肪来源", english: "Fats")
        case .vegetable:
            return L10n.choose(simplifiedChinese: "蔬菜", english: "Vegetables")
        case .fruit:
            return L10n.choose(simplifiedChinese: "水果", english: "Fruit")
        case .dairy:
            return L10n.choose(simplifiedChinese: "乳制品", english: "Dairy")
        case .beverage:
            return L10n.choose(simplifiedChinese: "饮品", english: "Beverages")
        case .condiment:
            return L10n.choose(simplifiedChinese: "调味/补剂", english: "Condiments/Supplements")
        case .snack:
            return L10n.choose(simplifiedChinese: "零食", english: "Snacks")
        }
    }
}

struct FoodLibraryItem: Identifiable, Hashable {
    let code: String
    let category: FoodLibraryCategory
    let nameZH: String
    let nameEN: String
    let servingLabelZH: String
    let servingLabelEN: String
    let calories: Int
    let protein: Double
    let carbs: Double
    let fat: Double
    let keywords: [String]

    var id: String { code }

    var displayName: String {
        L10n.choose(simplifiedChinese: nameZH, english: nameEN)
    }

    var servingLabel: String {
        L10n.choose(simplifiedChinese: servingLabelZH, english: servingLabelEN)
    }

    var searchableText: String {
        ([code, nameZH, nameEN] + keywords).joined(separator: " ").lowercased()
    }

    static func fromCustom(_ item: CustomFoodLibraryItem) -> FoodLibraryItem {
        FoodLibraryItem(
            code: item.id.uuidString,
            category: item.category,
            nameZH: item.nameZH,
            nameEN: item.nameEN,
            servingLabelZH: item.servingLabelZH,
            servingLabelEN: item.servingLabelEN,
            calories: item.calories,
            protein: item.protein,
            carbs: item.carbs,
            fat: item.fat,
            keywords: item.keywords + ["custom", "自定义"]
        )
    }

    static let commonLibrary: [FoodLibraryItem] = [
        // Proteins
        .init(code: "chicken_breast_100g", category: .protein, nameZH: "鸡胸肉", nameEN: "Chicken breast", servingLabelZH: "100g", servingLabelEN: "100g", calories: 165, protein: 31, carbs: 0, fat: 3.6, keywords: ["鸡肉", "protein"]),
        .init(code: "salmon_100g", category: .protein, nameZH: "三文鱼", nameEN: "Salmon", servingLabelZH: "100g", servingLabelEN: "100g", calories: 208, protein: 20, carbs: 0, fat: 13, keywords: ["鱼", "omega3"]),
        .init(code: "lean_beef_100g", category: .protein, nameZH: "瘦牛肉", nameEN: "Lean beef", servingLabelZH: "100g", servingLabelEN: "100g", calories: 176, protein: 26, carbs: 0, fat: 7, keywords: ["牛肉"]),
        .init(code: "egg_1pc", category: .protein, nameZH: "鸡蛋", nameEN: "Egg", servingLabelZH: "1个", servingLabelEN: "1 egg", calories: 78, protein: 6.3, carbs: 0.6, fat: 5.3, keywords: ["蛋"]),
        .init(code: "egg_white_100g", category: .protein, nameZH: "蛋清", nameEN: "Egg white", servingLabelZH: "100g", servingLabelEN: "100g", calories: 52, protein: 11, carbs: 0.7, fat: 0.2, keywords: ["蛋白"]),
        .init(code: "tofu_firm_100g", category: .protein, nameZH: "北豆腐", nameEN: "Firm tofu", servingLabelZH: "100g", servingLabelEN: "100g", calories: 82, protein: 10, carbs: 2, fat: 4.8, keywords: ["豆腐"]),
        .init(code: "shrimp_100g", category: .protein, nameZH: "虾仁", nameEN: "Shrimp", servingLabelZH: "100g", servingLabelEN: "100g", calories: 99, protein: 24, carbs: 0.2, fat: 0.3, keywords: ["虾"]),
        .init(code: "tuna_canned_100g", category: .protein, nameZH: "金枪鱼罐头（水浸）", nameEN: "Tuna canned (in water)", servingLabelZH: "100g", servingLabelEN: "100g", calories: 116, protein: 25, carbs: 0, fat: 1, keywords: ["金枪鱼"]),
        .init(code: "whey_30g", category: .condiment, nameZH: "乳清蛋白粉", nameEN: "Whey protein", servingLabelZH: "30g", servingLabelEN: "30g scoop", calories: 120, protein: 24, carbs: 3, fat: 2, keywords: ["乳清", "蛋白粉"]),
        .init(code: "greek_yogurt_170g", category: .dairy, nameZH: "希腊酸奶（无糖）", nameEN: "Greek yogurt (plain)", servingLabelZH: "170g", servingLabelEN: "170g cup", calories: 100, protein: 17, carbs: 6, fat: 0, keywords: ["酸奶"]),
        .init(code: "cottage_cheese_150g", category: .dairy, nameZH: "茅屋奶酪", nameEN: "Cottage cheese", servingLabelZH: "150g", servingLabelEN: "150g", calories: 147, protein: 20, carbs: 5, fat: 5, keywords: ["奶酪"]),

        // Carbs
        .init(code: "rice_cooked_100g", category: .carb, nameZH: "米饭（熟）", nameEN: "Rice (cooked)", servingLabelZH: "100g", servingLabelEN: "100g", calories: 116, protein: 2.6, carbs: 25.9, fat: 0.3, keywords: ["米饭"]),
        .init(code: "oats_dry_50g", category: .carb, nameZH: "燕麦", nameEN: "Oats", servingLabelZH: "50g", servingLabelEN: "50g", calories: 190, protein: 6.5, carbs: 33, fat: 3.5, keywords: ["燕麦"]),
        .init(code: "potato_200g", category: .carb, nameZH: "土豆", nameEN: "Potato", servingLabelZH: "200g", servingLabelEN: "200g", calories: 154, protein: 4, carbs: 34, fat: 0.2, keywords: ["马铃薯"]),
        .init(code: "sweet_potato_200g", category: .carb, nameZH: "红薯", nameEN: "Sweet potato", servingLabelZH: "200g", servingLabelEN: "200g", calories: 172, protein: 3.2, carbs: 40, fat: 0.2, keywords: ["地瓜"]),
        .init(code: "pasta_cooked_140g", category: .carb, nameZH: "意面（熟）", nameEN: "Pasta (cooked)", servingLabelZH: "140g", servingLabelEN: "140g", calories: 221, protein: 8, carbs: 43, fat: 1.3, keywords: ["意大利面"]),
        .init(code: "bread_whole_2slice", category: .carb, nameZH: "全麦面包", nameEN: "Whole-wheat bread", servingLabelZH: "2片", servingLabelEN: "2 slices", calories: 160, protein: 8, carbs: 28, fat: 2.5, keywords: ["面包"]),
        .init(code: "tortilla_1pc", category: .carb, nameZH: "玉米饼/卷饼皮", nameEN: "Tortilla wrap", servingLabelZH: "1张", servingLabelEN: "1 wrap", calories: 140, protein: 4, carbs: 24, fat: 3, keywords: ["卷饼"]),
        .init(code: "banana_1pc", category: .fruit, nameZH: "香蕉", nameEN: "Banana", servingLabelZH: "1根", servingLabelEN: "1 medium", calories: 105, protein: 1.3, carbs: 27, fat: 0.4, keywords: ["香蕉"]),
        .init(code: "apple_1pc", category: .fruit, nameZH: "苹果", nameEN: "Apple", servingLabelZH: "1个", servingLabelEN: "1 medium", calories: 95, protein: 0.5, carbs: 25, fat: 0.3, keywords: ["苹果"]),
        .init(code: "berries_100g", category: .fruit, nameZH: "莓果", nameEN: "Berries", servingLabelZH: "100g", servingLabelEN: "100g", calories: 57, protein: 0.7, carbs: 14, fat: 0.3, keywords: ["蓝莓", "草莓"]),
        .init(code: "orange_1pc", category: .fruit, nameZH: "橙子", nameEN: "Orange", servingLabelZH: "1个", servingLabelEN: "1 medium", calories: 62, protein: 1.2, carbs: 15.4, fat: 0.2, keywords: ["橙"]),
        .init(code: "dates_30g", category: .fruit, nameZH: "椰枣", nameEN: "Dates", servingLabelZH: "30g", servingLabelEN: "30g", calories: 85, protein: 0.7, carbs: 23, fat: 0.1, keywords: ["枣"]),

        // Fats / nuts
        .init(code: "avocado_half", category: .fat, nameZH: "牛油果", nameEN: "Avocado", servingLabelZH: "1/2个", servingLabelEN: "1/2 avocado", calories: 120, protein: 1.5, carbs: 6, fat: 11, keywords: ["鳄梨"]),
        .init(code: "olive_oil_10g", category: .fat, nameZH: "橄榄油", nameEN: "Olive oil", servingLabelZH: "10g", servingLabelEN: "10g", calories: 90, protein: 0, carbs: 0, fat: 10, keywords: ["油"]),
        .init(code: "peanut_butter_16g", category: .fat, nameZH: "花生酱", nameEN: "Peanut butter", servingLabelZH: "16g", servingLabelEN: "1 tbsp", calories: 94, protein: 3.6, carbs: 3.2, fat: 8, keywords: ["坚果酱"]),
        .init(code: "almonds_28g", category: .fat, nameZH: "杏仁", nameEN: "Almonds", servingLabelZH: "28g", servingLabelEN: "28g", calories: 164, protein: 6, carbs: 6, fat: 14, keywords: ["坚果"]),
        .init(code: "walnuts_28g", category: .fat, nameZH: "核桃", nameEN: "Walnuts", servingLabelZH: "28g", servingLabelEN: "28g", calories: 185, protein: 4.3, carbs: 3.9, fat: 18.5, keywords: ["坚果"]),
        .init(code: "chia_15g", category: .fat, nameZH: "奇亚籽", nameEN: "Chia seeds", servingLabelZH: "15g", servingLabelEN: "15g", calories: 73, protein: 2.5, carbs: 6.3, fat: 4.6, keywords: ["种子"]),

        // Vegetables
        .init(code: "broccoli_100g", category: .vegetable, nameZH: "西兰花", nameEN: "Broccoli", servingLabelZH: "100g", servingLabelEN: "100g", calories: 34, protein: 2.8, carbs: 7, fat: 0.4, keywords: ["花椰菜"]),
        .init(code: "spinach_100g", category: .vegetable, nameZH: "菠菜", nameEN: "Spinach", servingLabelZH: "100g", servingLabelEN: "100g", calories: 23, protein: 2.9, carbs: 3.6, fat: 0.4, keywords: ["菠菜"]),
        .init(code: "lettuce_100g", category: .vegetable, nameZH: "生菜", nameEN: "Lettuce", servingLabelZH: "100g", servingLabelEN: "100g", calories: 15, protein: 1.4, carbs: 2.9, fat: 0.2, keywords: ["叶菜"]),
        .init(code: "tomato_100g", category: .vegetable, nameZH: "番茄", nameEN: "Tomato", servingLabelZH: "100g", servingLabelEN: "100g", calories: 18, protein: 0.9, carbs: 3.9, fat: 0.2, keywords: ["西红柿"]),
        .init(code: "cucumber_100g", category: .vegetable, nameZH: "黄瓜", nameEN: "Cucumber", servingLabelZH: "100g", servingLabelEN: "100g", calories: 15, protein: 0.7, carbs: 3.6, fat: 0.1, keywords: ["黄瓜"]),
        .init(code: "bell_pepper_100g", category: .vegetable, nameZH: "彩椒", nameEN: "Bell pepper", servingLabelZH: "100g", servingLabelEN: "100g", calories: 31, protein: 1, carbs: 6, fat: 0.3, keywords: ["甜椒"]),
        .init(code: "carrot_100g", category: .vegetable, nameZH: "胡萝卜", nameEN: "Carrot", servingLabelZH: "100g", servingLabelEN: "100g", calories: 41, protein: 0.9, carbs: 10, fat: 0.2, keywords: ["萝卜"]),
        .init(code: "mushroom_100g", category: .vegetable, nameZH: "蘑菇", nameEN: "Mushrooms", servingLabelZH: "100g", servingLabelEN: "100g", calories: 22, protein: 3.1, carbs: 3.3, fat: 0.3, keywords: ["菌菇"]),

        // Dairy / beverages
        .init(code: "milk_lowfat_250ml", category: .dairy, nameZH: "低脂牛奶", nameEN: "Low-fat milk", servingLabelZH: "250ml", servingLabelEN: "250ml", calories: 120, protein: 8.5, carbs: 12, fat: 4, keywords: ["牛奶"]),
        .init(code: "soy_milk_250ml", category: .dairy, nameZH: "无糖豆奶", nameEN: "Unsweetened soy milk", servingLabelZH: "250ml", servingLabelEN: "250ml", calories: 80, protein: 7, carbs: 4, fat: 4, keywords: ["豆浆"]),
        .init(code: "kefir_250ml", category: .dairy, nameZH: "开菲尔", nameEN: "Kefir", servingLabelZH: "250ml", servingLabelEN: "250ml", calories: 130, protein: 9, carbs: 10, fat: 5, keywords: ["发酵乳"]),
        .init(code: "sports_drink_500ml", category: .beverage, nameZH: "运动饮料", nameEN: "Sports drink", servingLabelZH: "500ml", servingLabelEN: "500ml bottle", calories: 120, protein: 0, carbs: 30, fat: 0, keywords: ["补糖", "训练中"]),
        .init(code: "electrolyte_1serve", category: .beverage, nameZH: "电解质饮料（无糖）", nameEN: "Electrolyte drink (sugar-free)", servingLabelZH: "1份", servingLabelEN: "1 serving", calories: 5, protein: 0, carbs: 1, fat: 0, keywords: ["电解质"]),

        // Condiments / supplements
        .init(code: "honey_15g", category: .condiment, nameZH: "蜂蜜", nameEN: "Honey", servingLabelZH: "15g", servingLabelEN: "15g", calories: 46, protein: 0, carbs: 12.4, fat: 0, keywords: ["蜂蜜"]),
        .init(code: "jam_20g", category: .condiment, nameZH: "果酱", nameEN: "Jam", servingLabelZH: "20g", servingLabelEN: "20g", calories: 50, protein: 0, carbs: 13, fat: 0, keywords: ["果酱"]),
        .init(code: "protein_bar_1pc", category: .snack, nameZH: "蛋白棒", nameEN: "Protein bar", servingLabelZH: "1根", servingLabelEN: "1 bar", calories: 210, protein: 20, carbs: 22, fat: 7, keywords: ["零食"]),
        .init(code: "rice_cake_2pc", category: .snack, nameZH: "米饼", nameEN: "Rice cakes", servingLabelZH: "2片", servingLabelEN: "2 cakes", calories: 70, protein: 1.4, carbs: 14.5, fat: 0.4, keywords: ["补碳"]),
        .init(code: "dark_chocolate_20g", category: .snack, nameZH: "黑巧克力", nameEN: "Dark chocolate", servingLabelZH: "20g", servingLabelEN: "20g", calories: 120, protein: 1.6, carbs: 9, fat: 9, keywords: ["巧克力"]),

        // Extra mixed common foods
        .init(code: "quinoa_cooked_150g", category: .carb, nameZH: "藜麦（熟）", nameEN: "Quinoa (cooked)", servingLabelZH: "150g", servingLabelEN: "150g", calories: 180, protein: 6.5, carbs: 31, fat: 2.8, keywords: ["藜麦"]),
        .init(code: "noodles_cooked_150g", category: .carb, nameZH: "面条（熟）", nameEN: "Noodles (cooked)", servingLabelZH: "150g", servingLabelEN: "150g", calories: 210, protein: 7, carbs: 40, fat: 2, keywords: ["面"]),
        .init(code: "edamame_100g", category: .protein, nameZH: "毛豆", nameEN: "Edamame", servingLabelZH: "100g", servingLabelEN: "100g", calories: 122, protein: 11, carbs: 10, fat: 5, keywords: ["豆类"]),
        .init(code: "lentils_cooked_150g", category: .carb, nameZH: "扁豆（熟）", nameEN: "Lentils (cooked)", servingLabelZH: "150g", servingLabelEN: "150g", calories: 174, protein: 13, carbs: 30, fat: 0.6, keywords: ["豆类", "纤维"]),
        .init(code: "cheese_slice_1pc", category: .dairy, nameZH: "奶酪片", nameEN: "Cheese slice", servingLabelZH: "1片", servingLabelEN: "1 slice", calories: 70, protein: 4, carbs: 1, fat: 6, keywords: ["奶酪"]),
        .init(code: "ham_lean_50g", category: .protein, nameZH: "火腿（低脂）", nameEN: "Lean ham", servingLabelZH: "50g", servingLabelEN: "50g", calories: 60, protein: 10, carbs: 1, fat: 2, keywords: ["火腿"]),
        .init(code: "kimchi_50g", category: .vegetable, nameZH: "泡菜", nameEN: "Kimchi", servingLabelZH: "50g", servingLabelEN: "50g", calories: 15, protein: 1, carbs: 2, fat: 0, keywords: ["发酵"]),
        .init(code: "seaweed_5g", category: .vegetable, nameZH: "海苔", nameEN: "Seaweed", servingLabelZH: "5g", servingLabelEN: "5g", calories: 15, protein: 2, carbs: 1, fat: 0.2, keywords: ["海藻"]),
        .init(code: "tofu_noodle_150g", category: .carb, nameZH: "魔芋面/豆腐面", nameEN: "Konjac/tofu noodles", servingLabelZH: "150g", servingLabelEN: "150g", calories: 30, protein: 2, carbs: 4, fat: 0.5, keywords: ["低碳"]),
        .init(code: "cauliflower_rice_150g", category: .carb, nameZH: "花椰菜米", nameEN: "Cauliflower rice", servingLabelZH: "150g", servingLabelEN: "150g", calories: 38, protein: 3, carbs: 7, fat: 0.5, keywords: ["低碳"]),
        .init(code: "nuts_mixed_30g", category: .fat, nameZH: "混合坚果", nameEN: "Mixed nuts", servingLabelZH: "30g", servingLabelEN: "30g", calories: 180, protein: 5, carbs: 6, fat: 16, keywords: ["坚果"]),
        .init(code: "yogurt_drink_250ml", category: .beverage, nameZH: "酸奶饮品", nameEN: "Yogurt drink", servingLabelZH: "250ml", servingLabelEN: "250ml", calories: 160, protein: 8, carbs: 24, fat: 4, keywords: ["饮品"]),
        .init(code: "rice_ball_1pc", category: .snack, nameZH: "饭团", nameEN: "Rice ball", servingLabelZH: "1个", servingLabelEN: "1 ball", calories: 180, protein: 4, carbs: 36, fat: 2, keywords: ["便利店", "碳水"]),
        .init(code: "sandwich_turkey_1pc", category: .snack, nameZH: "火鸡三明治", nameEN: "Turkey sandwich", servingLabelZH: "1份", servingLabelEN: "1 sandwich", calories: 320, protein: 24, carbs: 34, fat: 10, keywords: ["三明治"]),
        .init(code: "sardines_100g", category: .protein, nameZH: "沙丁鱼", nameEN: "Sardines", servingLabelZH: "100g", servingLabelEN: "100g", calories: 208, protein: 25, carbs: 0, fat: 11, keywords: ["鱼罐头"]),
        .init(code: "brown_rice_150g", category: .carb, nameZH: "糙米（熟）", nameEN: "Brown rice (cooked)", servingLabelZH: "150g", servingLabelEN: "150g", calories: 166, protein: 3.5, carbs: 35, fat: 1.4, keywords: ["糙米"]),
        .init(code: "granola_40g", category: .snack, nameZH: "格兰诺拉", nameEN: "Granola", servingLabelZH: "40g", servingLabelEN: "40g", calories: 180, protein: 4, carbs: 24, fat: 8, keywords: ["早餐谷物"]),
        .init(code: "basmati_rice_150g", category: .carb, nameZH: "印度香米（熟）", nameEN: "Basmati rice (cooked)", servingLabelZH: "150g", servingLabelEN: "150g", calories: 195, protein: 4, carbs: 43, fat: 0.5, keywords: ["低GI"]),
        .init(code: "wholegrain_crackers_30g", category: .snack, nameZH: "全麦饼干", nameEN: "Wholegrain crackers", servingLabelZH: "30g", servingLabelEN: "30g", calories: 130, protein: 3, carbs: 20, fat: 4, keywords: ["饼干"]),
        .init(code: "unsalted_butter_10g", category: .fat, nameZH: "黄油", nameEN: "Butter", servingLabelZH: "10g", servingLabelEN: "10g", calories: 72, protein: 0.1, carbs: 0, fat: 8.1, keywords: ["黄油"]),
        .init(code: "coconut_milk_100ml", category: .fat, nameZH: "椰奶", nameEN: "Coconut milk", servingLabelZH: "100ml", servingLabelEN: "100ml", calories: 180, protein: 1.6, carbs: 3, fat: 18, keywords: ["生酮"]),
        .init(code: "berries_yogurt_bowl", category: .snack, nameZH: "莓果酸奶碗", nameEN: "Berries yogurt bowl", servingLabelZH: "1碗", servingLabelEN: "1 bowl", calories: 220, protein: 15, carbs: 28, fat: 6, keywords: ["早餐", "加餐"])
    ]

    static func lookup(code: String) -> FoodLibraryItem? {
        commonLibrary.first(where: { $0.code == code })
    }
}

struct CustomFoodLibraryItem: Codable, Identifiable, Hashable {
    var id: UUID
    var category: FoodLibraryCategory
    var nameZH: String
    var nameEN: String
    var servingLabelZH: String
    var servingLabelEN: String
    var calories: Int
    var protein: Double
    var carbs: Double
    var fat: Double
    var barcode: String?
    var keywords: [String]
    var createdAt: Date

    init(
        id: UUID = UUID(),
        category: FoodLibraryCategory = .snack,
        nameZH: String,
        nameEN: String? = nil,
        servingLabelZH: String,
        servingLabelEN: String? = nil,
        calories: Int,
        protein: Double,
        carbs: Double,
        fat: Double,
        barcode: String? = nil,
        keywords: [String] = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.category = category
        self.nameZH = nameZH
        self.nameEN = (nameEN?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 } ?? nameZH
        self.servingLabelZH = servingLabelZH
        self.servingLabelEN = (servingLabelEN?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 } ?? servingLabelZH
        self.calories = max(0, calories)
        self.protein = max(0, protein)
        self.carbs = max(0, carbs)
        self.fat = max(0, fat)
        self.barcode = (barcode?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
        self.keywords = keywords
        self.createdAt = createdAt
    }

    var displayName: String {
        L10n.choose(simplifiedChinese: nameZH, english: nameEN)
    }

    func asFoodLibraryItem() -> FoodLibraryItem {
        .fromCustom(self)
    }
}

struct DailyMealPlan: Codable, Identifiable {
    var id: UUID
    var date: Date
    var athleteName: String?
    var hydrationTargetLiters: Double
    var hydrationActualLiters: Double
    var goalProfile: NutritionGoalProfile
    var mealTargets: [MealMacroTarget]
    var fridgeItems: [FridgeFoodEntry]
    var items: [MealPlanItem]
    var notes: String

    init(
        id: UUID = UUID(),
        date: Date,
        athleteName: String? = nil,
        hydrationTargetLiters: Double = 2.5,
        hydrationActualLiters: Double = 0,
        goalProfile: NutritionGoalProfile = .balanced,
        mealTargets: [MealMacroTarget] = MealMacroTarget.defaultThreeMeals(),
        fridgeItems: [FridgeFoodEntry] = [],
        items: [MealPlanItem] = DailyMealPlan.defaultTemplateItems(),
        notes: String = ""
    ) {
        self.id = id
        self.date = date
        self.athleteName = athleteName
        self.hydrationTargetLiters = hydrationTargetLiters
        self.hydrationActualLiters = hydrationActualLiters
        self.goalProfile = goalProfile
        self.mealTargets = MealMacroTarget.normalizedThreeMeals(from: mealTargets)
        self.fridgeItems = fridgeItems
        self.items = items
        self.notes = notes
    }

    var plannedTotals: MealNutritionTotals {
        items.reduce(into: MealNutritionTotals()) { partial, item in
            partial.calories += max(0, item.plannedCalories)
            partial.protein += max(0, item.plannedProtein)
            partial.carbs += max(0, item.plannedCarbs)
            partial.fat += max(0, item.plannedFat)
        }
    }

    var actualTotals: MealNutritionTotals {
        items.reduce(into: MealNutritionTotals()) { partial, item in
            partial.calories += max(0, item.actualCalories)
            partial.protein += max(0, item.actualProtein)
            partial.carbs += max(0, item.actualCarbs)
            partial.fat += max(0, item.actualFat)
        }
    }

    var completionRatio: Double {
        let planned = max(1, plannedTotals.calories)
        return min(max(Double(actualTotals.calories) / Double(planned), 0.0), 1.5)
    }

    var mainMealTargets: [MealMacroTarget] {
        MealMacroTarget.normalizedThreeMeals(from: mealTargets)
    }

    func target(for slot: MealSlot) -> MealMacroTarget? {
        mainMealTargets.first(where: { $0.slot == slot })
    }

    mutating func setTarget(_ target: MealMacroTarget) {
        var normalized = MealMacroTarget.normalizedThreeMeals(from: mealTargets)
        if let idx = normalized.firstIndex(where: { $0.slot == target.slot }) {
            normalized[idx] = MealMacroTarget(
                id: normalized[idx].id,
                slot: target.slot,
                calories: max(0, target.calories),
                protein: max(0, target.protein),
                carbs: max(0, target.carbs),
                fat: max(0, target.fat)
            )
        } else {
            normalized.append(target)
        }
        mealTargets = MealMacroTarget.normalizedThreeMeals(from: normalized)
    }

    mutating func applyPlannedToActualForAllItems() {
        for index in items.indices {
            items[index].applyPlannedToActual()
        }
    }

    static func defaultTemplate(date: Date, athleteName: String?) -> DailyMealPlan {
        DailyMealPlan(
            date: Calendar.current.startOfDay(for: date),
            athleteName: athleteName,
            hydrationTargetLiters: 2.5,
            hydrationActualLiters: 0,
            goalProfile: .balanced,
            mealTargets: MealMacroTarget.defaultThreeMeals(),
            fridgeItems: [],
            items: defaultTemplateItems(),
            notes: ""
        )
    }

    enum CodingKeys: String, CodingKey {
        case id
        case date
        case athleteName
        case hydrationTargetLiters
        case hydrationActualLiters
        case goalProfile
        case mealTargets
        case fridgeItems
        case items
        case notes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        date = try container.decode(Date.self, forKey: .date)
        athleteName = try container.decodeIfPresent(String.self, forKey: .athleteName)
        hydrationTargetLiters = try container.decodeIfPresent(Double.self, forKey: .hydrationTargetLiters) ?? 2.5
        hydrationActualLiters = try container.decodeIfPresent(Double.self, forKey: .hydrationActualLiters) ?? 0
        goalProfile = try container.decodeIfPresent(NutritionGoalProfile.self, forKey: .goalProfile) ?? .balanced
        let decodedTargets = try container.decodeIfPresent([MealMacroTarget].self, forKey: .mealTargets) ?? MealMacroTarget.defaultThreeMeals()
        mealTargets = MealMacroTarget.normalizedThreeMeals(from: decodedTargets)
        fridgeItems = try container.decodeIfPresent([FridgeFoodEntry].self, forKey: .fridgeItems) ?? []
        items = try container.decodeIfPresent([MealPlanItem].self, forKey: .items) ?? DailyMealPlan.defaultTemplateItems()
        notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(date, forKey: .date)
        try container.encodeIfPresent(athleteName, forKey: .athleteName)
        try container.encode(hydrationTargetLiters, forKey: .hydrationTargetLiters)
        try container.encode(hydrationActualLiters, forKey: .hydrationActualLiters)
        try container.encode(goalProfile, forKey: .goalProfile)
        try container.encode(mainMealTargets, forKey: .mealTargets)
        try container.encode(fridgeItems, forKey: .fridgeItems)
        try container.encode(items, forKey: .items)
        try container.encode(notes, forKey: .notes)
    }

    static func defaultTemplateItems() -> [MealPlanItem] {
        [
            MealPlanItem(
                slot: .breakfast,
                plannedFood: L10n.choose(simplifiedChinese: "燕麦 + 鸡蛋 + 水果", english: "Oats + eggs + fruit"),
                plannedCalories: 500,
                plannedProtein: 28,
                plannedCarbs: 58,
                plannedFat: 16
            ),
            MealPlanItem(
                slot: .snackAM,
                plannedFood: L10n.choose(simplifiedChinese: "酸奶 + 坚果", english: "Yogurt + nuts"),
                plannedCalories: 240,
                plannedProtein: 12,
                plannedCarbs: 18,
                plannedFat: 14
            ),
            MealPlanItem(
                slot: .lunch,
                plannedFood: L10n.choose(simplifiedChinese: "米饭 + 鸡胸 + 蔬菜", english: "Rice + chicken breast + vegetables"),
                plannedCalories: 700,
                plannedProtein: 42,
                plannedCarbs: 86,
                plannedFat: 18
            ),
            MealPlanItem(
                slot: .snackPM,
                plannedFood: L10n.choose(simplifiedChinese: "香蕉 + 乳清", english: "Banana + whey"),
                plannedCalories: 230,
                plannedProtein: 20,
                plannedCarbs: 30,
                plannedFat: 3
            ),
            MealPlanItem(
                slot: .dinner,
                plannedFood: L10n.choose(simplifiedChinese: "土豆 + 三文鱼 + 沙拉", english: "Potato + salmon + salad"),
                plannedCalories: 720,
                plannedProtein: 40,
                plannedCarbs: 64,
                plannedFat: 30
            ),
            MealPlanItem(
                slot: .postWorkout,
                plannedFood: L10n.choose(simplifiedChinese: "恢复奶昔", english: "Recovery shake"),
                plannedCalories: 210,
                plannedProtein: 24,
                plannedCarbs: 20,
                plannedFat: 4
            )
        ]
    }
}

struct HeartRateThresholdRange: Codable, Identifiable, Hashable {
    var id: UUID
    var sport: SportType
    var startDate: Date
    var endDate: Date?
    var lthr: Int
    var aeTHR: Int?
    var restingHR: Int?
    var maxHR: Int?

    init(
        id: UUID = UUID(),
        sport: SportType,
        startDate: Date,
        endDate: Date? = nil,
        lthr: Int,
        aeTHR: Int? = nil,
        restingHR: Int? = nil,
        maxHR: Int? = nil
    ) {
        self.id = id
        self.sport = sport
        self.startDate = startDate
        self.endDate = endDate
        self.lthr = lthr
        self.aeTHR = aeTHR
        self.restingHR = restingHR
        self.maxHR = maxHR
    }

    func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        let day = calendar.startOfDay(for: date)
        let start = calendar.startOfDay(for: startDate)
        if day < start {
            return false
        }
        if let endDate {
            let end = calendar.startOfDay(for: endDate)
            return day < end
        }
        return true
    }
}

struct AthleteProfile: Codable {
    // Legacy global values kept for backward compatibility; cycling values are authoritative.
    var ftpWatts: Int
    var thresholdHeartRate: Int
    var athleteAgeYears: Int
    var athleteWeightKg: Double
    var basalMetabolicRateKcal: Int
    var nutritionActivityFactor: Double
    var cyclingFTPWatts: Int
    var runningFTPWatts: Int
    var swimmingFTPWatts: Int
    var strengthFTPWatts: Int
    var cyclingThresholdHeartRate: Int
    var runningThresholdHeartRate: Int
    var swimmingThresholdHeartRate: Int
    var strengthThresholdHeartRate: Int
    var cyclingMaxHeartRate: Int
    var runningMaxHeartRate: Int
    var swimmingMaxHeartRate: Int
    var strengthMaxHeartRate: Int
    var hrvBaseline: Double
    var hrvToday: Double
    var goalRaceDate: Date?
    var intervalsAPIKey: String
    var stravaClientID: String
    var stravaClientSecret: String
    var stravaRefreshToken: String
    var stravaAccessToken: String
    var stravaAccessTokenExpiresAt: Int?
    var garminConnectAccessToken: String
    var garminConnectCSRFToken: String
    var ouraPersonalAccessToken: String
    var whoopAccessToken: String
    var appleHealthAccessToken: String
    var googleFitAccessToken: String
    var trainingPeaksAccessToken: String
    var openAIAPIKey: String
    var hrThresholdRanges: [HeartRateThresholdRange]

    static let `default` = AthleteProfile(
        ftpWatts: 260,
        thresholdHeartRate: 172,
        athleteAgeYears: 34,
        athleteWeightKg: 69.0,
        basalMetabolicRateKcal: 1650,
        nutritionActivityFactor: 1.35,
        cyclingFTPWatts: 260,
        runningFTPWatts: 260,
        swimmingFTPWatts: 230,
        strengthFTPWatts: 260,
        cyclingThresholdHeartRate: 172,
        runningThresholdHeartRate: 176,
        swimmingThresholdHeartRate: 164,
        strengthThresholdHeartRate: 172,
        cyclingMaxHeartRate: 0,
        runningMaxHeartRate: 0,
        swimmingMaxHeartRate: 0,
        strengthMaxHeartRate: 0,
        hrvBaseline: 62,
        hrvToday: 62,
        goalRaceDate: nil,
        intervalsAPIKey: "",
        stravaClientID: "",
        stravaClientSecret: "",
        stravaRefreshToken: "",
        stravaAccessToken: "",
        stravaAccessTokenExpiresAt: nil,
        garminConnectAccessToken: "",
        garminConnectCSRFToken: "",
        ouraPersonalAccessToken: "",
        whoopAccessToken: "",
        appleHealthAccessToken: "",
        googleFitAccessToken: "",
        trainingPeaksAccessToken: "",
        openAIAPIKey: "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",
        hrThresholdRanges: []
    )

    private enum CodingKeys: String, CodingKey {
        case ftpWatts
        case thresholdHeartRate
        case athleteAgeYears
        case athleteWeightKg
        case basalMetabolicRateKcal
        case nutritionActivityFactor
        case cyclingFTPWatts
        case runningFTPWatts
        case swimmingFTPWatts
        case strengthFTPWatts
        case cyclingThresholdHeartRate
        case runningThresholdHeartRate
        case swimmingThresholdHeartRate
        case strengthThresholdHeartRate
        case cyclingMaxHeartRate
        case runningMaxHeartRate
        case swimmingMaxHeartRate
        case strengthMaxHeartRate
        case hrvBaseline
        case hrvToday
        case goalRaceDate
        case intervalsAPIKey
        case stravaClientID
        case stravaClientSecret
        case stravaRefreshToken
        case stravaAccessToken
        case stravaAccessTokenExpiresAt
        case garminConnectAccessToken
        case garminConnectCSRFToken
        case ouraPersonalAccessToken
        case whoopAccessToken
        case appleHealthAccessToken
        case googleFitAccessToken
        case trainingPeaksAccessToken
        case openAIAPIKey
        case hrThresholdRanges
    }

    init(
        ftpWatts: Int,
        thresholdHeartRate: Int,
        athleteAgeYears: Int,
        athleteWeightKg: Double,
        basalMetabolicRateKcal: Int,
        nutritionActivityFactor: Double,
        cyclingFTPWatts: Int,
        runningFTPWatts: Int,
        swimmingFTPWatts: Int,
        strengthFTPWatts: Int,
        cyclingThresholdHeartRate: Int,
        runningThresholdHeartRate: Int,
        swimmingThresholdHeartRate: Int,
        strengthThresholdHeartRate: Int,
        cyclingMaxHeartRate: Int,
        runningMaxHeartRate: Int,
        swimmingMaxHeartRate: Int,
        strengthMaxHeartRate: Int,
        hrvBaseline: Double,
        hrvToday: Double,
        goalRaceDate: Date?,
        intervalsAPIKey: String,
        stravaClientID: String,
        stravaClientSecret: String,
        stravaRefreshToken: String,
        stravaAccessToken: String,
        stravaAccessTokenExpiresAt: Int?,
        garminConnectAccessToken: String,
        garminConnectCSRFToken: String,
        ouraPersonalAccessToken: String,
        whoopAccessToken: String,
        appleHealthAccessToken: String,
        googleFitAccessToken: String,
        trainingPeaksAccessToken: String,
        openAIAPIKey: String,
        hrThresholdRanges: [HeartRateThresholdRange]
    ) {
        self.ftpWatts = ftpWatts
        self.thresholdHeartRate = thresholdHeartRate
        self.athleteAgeYears = athleteAgeYears
        self.athleteWeightKg = athleteWeightKg
        self.basalMetabolicRateKcal = max(500, basalMetabolicRateKcal)
        self.nutritionActivityFactor = min(max(nutritionActivityFactor, 1.0), 2.5)
        self.cyclingFTPWatts = cyclingFTPWatts
        self.runningFTPWatts = runningFTPWatts
        self.swimmingFTPWatts = swimmingFTPWatts
        self.strengthFTPWatts = strengthFTPWatts
        self.cyclingThresholdHeartRate = cyclingThresholdHeartRate
        self.runningThresholdHeartRate = runningThresholdHeartRate
        self.swimmingThresholdHeartRate = swimmingThresholdHeartRate
        self.strengthThresholdHeartRate = strengthThresholdHeartRate
        self.cyclingMaxHeartRate = cyclingMaxHeartRate
        self.runningMaxHeartRate = runningMaxHeartRate
        self.swimmingMaxHeartRate = swimmingMaxHeartRate
        self.strengthMaxHeartRate = strengthMaxHeartRate
        self.hrvBaseline = hrvBaseline
        self.hrvToday = hrvToday
        self.goalRaceDate = goalRaceDate
        self.intervalsAPIKey = intervalsAPIKey
        self.stravaClientID = stravaClientID
        self.stravaClientSecret = stravaClientSecret
        self.stravaRefreshToken = stravaRefreshToken
        self.stravaAccessToken = stravaAccessToken
        self.stravaAccessTokenExpiresAt = stravaAccessTokenExpiresAt
        self.garminConnectAccessToken = garminConnectAccessToken
        self.garminConnectCSRFToken = garminConnectCSRFToken
        self.ouraPersonalAccessToken = ouraPersonalAccessToken
        self.whoopAccessToken = whoopAccessToken
        self.appleHealthAccessToken = appleHealthAccessToken
        self.googleFitAccessToken = googleFitAccessToken
        self.trainingPeaksAccessToken = trainingPeaksAccessToken
        self.openAIAPIKey = openAIAPIKey
        self.hrThresholdRanges = hrThresholdRanges
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let legacyFTP = try container.decodeIfPresent(Int.self, forKey: .ftpWatts) ?? 260
        let legacyThresholdHR = try container.decodeIfPresent(Int.self, forKey: .thresholdHeartRate) ?? 172
        self.athleteAgeYears = try container.decodeIfPresent(Int.self, forKey: .athleteAgeYears) ?? 34
        self.athleteWeightKg = try container.decodeIfPresent(Double.self, forKey: .athleteWeightKg) ?? 69.0
        self.basalMetabolicRateKcal = max(500, try container.decodeIfPresent(Int.self, forKey: .basalMetabolicRateKcal) ?? 1650)
        self.nutritionActivityFactor = min(max(try container.decodeIfPresent(Double.self, forKey: .nutritionActivityFactor) ?? 1.35, 1.0), 2.5)
        self.cyclingFTPWatts = try container.decodeIfPresent(Int.self, forKey: .cyclingFTPWatts) ?? legacyFTP
        self.runningFTPWatts = try container.decodeIfPresent(Int.self, forKey: .runningFTPWatts) ?? legacyFTP
        self.swimmingFTPWatts = try container.decodeIfPresent(Int.self, forKey: .swimmingFTPWatts) ?? legacyFTP
        self.strengthFTPWatts = try container.decodeIfPresent(Int.self, forKey: .strengthFTPWatts) ?? legacyFTP
        self.cyclingThresholdHeartRate = try container.decodeIfPresent(Int.self, forKey: .cyclingThresholdHeartRate) ?? legacyThresholdHR
        self.runningThresholdHeartRate = try container.decodeIfPresent(Int.self, forKey: .runningThresholdHeartRate) ?? legacyThresholdHR
        self.swimmingThresholdHeartRate = try container.decodeIfPresent(Int.self, forKey: .swimmingThresholdHeartRate) ?? legacyThresholdHR
        self.strengthThresholdHeartRate = try container.decodeIfPresent(Int.self, forKey: .strengthThresholdHeartRate) ?? legacyThresholdHR
        self.cyclingMaxHeartRate = max(0, try container.decodeIfPresent(Int.self, forKey: .cyclingMaxHeartRate) ?? 0)
        self.runningMaxHeartRate = max(0, try container.decodeIfPresent(Int.self, forKey: .runningMaxHeartRate) ?? 0)
        self.swimmingMaxHeartRate = max(0, try container.decodeIfPresent(Int.self, forKey: .swimmingMaxHeartRate) ?? 0)
        self.strengthMaxHeartRate = max(0, try container.decodeIfPresent(Int.self, forKey: .strengthMaxHeartRate) ?? 0)
        self.ftpWatts = self.cyclingFTPWatts
        self.thresholdHeartRate = self.cyclingThresholdHeartRate
        self.hrvBaseline = try container.decodeIfPresent(Double.self, forKey: .hrvBaseline) ?? 62
        self.hrvToday = try container.decodeIfPresent(Double.self, forKey: .hrvToday) ?? 62
        self.goalRaceDate = try container.decodeIfPresent(Date.self, forKey: .goalRaceDate)
        self.intervalsAPIKey = try container.decodeIfPresent(String.self, forKey: .intervalsAPIKey) ?? ""
        self.stravaClientID = try container.decodeIfPresent(String.self, forKey: .stravaClientID) ?? ""
        self.stravaClientSecret = try container.decodeIfPresent(String.self, forKey: .stravaClientSecret) ?? ""
        self.stravaRefreshToken = try container.decodeIfPresent(String.self, forKey: .stravaRefreshToken) ?? ""
        self.stravaAccessToken = try container.decodeIfPresent(String.self, forKey: .stravaAccessToken) ?? ""
        self.stravaAccessTokenExpiresAt = try container.decodeIfPresent(Int.self, forKey: .stravaAccessTokenExpiresAt)
        self.garminConnectAccessToken = try container.decodeIfPresent(String.self, forKey: .garminConnectAccessToken) ?? ""
        self.garminConnectCSRFToken = try container.decodeIfPresent(String.self, forKey: .garminConnectCSRFToken) ?? ""
        self.ouraPersonalAccessToken = try container.decodeIfPresent(String.self, forKey: .ouraPersonalAccessToken) ?? ""
        self.whoopAccessToken = try container.decodeIfPresent(String.self, forKey: .whoopAccessToken) ?? ""
        self.appleHealthAccessToken = try container.decodeIfPresent(String.self, forKey: .appleHealthAccessToken) ?? ""
        self.googleFitAccessToken = try container.decodeIfPresent(String.self, forKey: .googleFitAccessToken) ?? ""
        self.trainingPeaksAccessToken = try container.decodeIfPresent(String.self, forKey: .trainingPeaksAccessToken) ?? ""
        self.openAIAPIKey = try container.decodeIfPresent(String.self, forKey: .openAIAPIKey) ?? ""
        self.hrThresholdRanges = try container.decodeIfPresent([HeartRateThresholdRange].self, forKey: .hrThresholdRanges) ?? []
    }

    var estimatedDailyMaintenanceCalories: Int {
        Int((Double(max(500, basalMetabolicRateKcal)) * min(max(nutritionActivityFactor, 1.0), 2.5)).rounded())
    }

    func recommendedDailyNutritionTargetKcal(
        goalProfile: NutritionGoalProfile,
        extraTrainingCalories: Int = 0
    ) -> Int {
        let baseMaintenance = max(1200, estimatedDailyMaintenanceCalories + max(0, extraTrainingCalories))
        let adjusted: Int
        switch goalProfile {
        case .balanced:
            adjusted = baseMaintenance
        case .keto:
            adjusted = baseMaintenance
        case .highCarbFatLoss:
            adjusted = max(1100, baseMaintenance - 250)
        case .pregnancyGlycemicControl:
            adjusted = max(1400, baseMaintenance)
        }
        return adjusted
    }

    func recommendedMainMealTargets(
        goalProfile: NutritionGoalProfile,
        extraTrainingCalories: Int = 0
    ) -> [MealMacroTarget] {
        let kcal = recommendedDailyNutritionTargetKcal(goalProfile: goalProfile, extraTrainingCalories: extraTrainingCalories)
        let weight = max(35.0, athleteWeightKg)

        let macroSplit: (protein: Double, carbs: Double, fat: Double)
        switch goalProfile {
        case .balanced:
            macroSplit = (0.22, 0.48, 0.30)
        case .keto:
            macroSplit = (0.22, 0.08, 0.70)
        case .highCarbFatLoss:
            macroSplit = (0.24, 0.51, 0.25)
        case .pregnancyGlycemicControl:
            macroSplit = (0.24, 0.38, 0.38)
        }

        var proteinGrams = max(Int((weight * 1.8).rounded()), Int((Double(kcal) * macroSplit.protein / 4.0).rounded()))
        let carbsGrams = max(0, Int((Double(kcal) * macroSplit.carbs / 4.0).rounded()))
        var fatGrams = max(0, Int((Double(kcal) * macroSplit.fat / 9.0).rounded()))

        // Keep total roughly consistent after enforcing minimum protein.
        let recomputedKcal = proteinGrams * 4 + carbsGrams * 4 + fatGrams * 9
        if recomputedKcal > kcal + 80 {
            let excess = recomputedKcal - kcal
            fatGrams = max(0, fatGrams - Int((Double(excess) / 9.0).rounded()))
        } else if recomputedKcal < kcal - 80 {
            let deficit = kcal - recomputedKcal
            fatGrams += Int((Double(deficit) / 9.0).rounded())
        }
        proteinGrams = max(0, proteinGrams)

        func alloc(_ total: Int, ratios: [Double]) -> [Int] {
            guard !ratios.isEmpty else { return [] }
            let normalized = {
                let s = ratios.reduce(0, +)
                return s > 0 ? ratios.map { $0 / s } : Array(repeating: 1.0 / Double(ratios.count), count: ratios.count)
            }()
            var out = normalized.map { Int((Double(total) * $0).rounded()) }
            let diff = total - out.reduce(0, +)
            if diff != 0, let idx = out.indices.max(by: { out[$0] < out[$1] }) {
                out[idx] += diff
            }
            return out
        }

        let kcalSplit = alloc(kcal, ratios: [0.28, 0.38, 0.34])
        let proteinSplit = alloc(proteinGrams, ratios: [0.30, 0.35, 0.35])
        let carbsSplit = alloc(carbsGrams, ratios: [0.25, 0.40, 0.35])
        let fatSplit = alloc(fatGrams, ratios: [0.30, 0.30, 0.40])

        return [
            MealMacroTarget(slot: .breakfast, calories: kcalSplit[0], protein: Double(proteinSplit[0]), carbs: Double(carbsSplit[0]), fat: Double(fatSplit[0])),
            MealMacroTarget(slot: .lunch, calories: kcalSplit[1], protein: Double(proteinSplit[1]), carbs: Double(carbsSplit[1]), fat: Double(fatSplit[1])),
            MealMacroTarget(slot: .dinner, calories: kcalSplit[2], protein: Double(proteinSplit[2]), carbs: Double(carbsSplit[2]), fat: Double(fatSplit[2]))
        ]
    }

    func ftpWatts(for sport: SportType) -> Int {
        switch sport {
        case .cycling: return cyclingFTPWatts
        case .running: return runningFTPWatts
        case .swimming: return swimmingFTPWatts
        case .strength: return strengthFTPWatts
        }
    }

    func thresholdHeartRate(for sport: SportType) -> Int {
        thresholdHeartRate(for: sport, on: Date())
    }

    func thresholdHeartRate(for sport: SportType, on date: Date) -> Int {
        let fallback: Int
        switch sport {
        case .cycling: fallback = cyclingThresholdHeartRate
        case .running: fallback = runningThresholdHeartRate
        case .swimming: fallback = swimmingThresholdHeartRate
        case .strength: fallback = strengthThresholdHeartRate
        }

        let matches = hrThresholdRanges.filter { range in
            range.sport == sport && range.lthr > 0 && range.contains(date)
        }
        if let best = matches.max(by: { $0.startDate < $1.startDate }) {
            return best.lthr
        }

        if fallback > 0 {
            return fallback
        }

        if let rangeMax = maxHeartRateFromRange(for: sport, on: date) {
            return estimatedLTHR(fromMaxHeartRate: rangeMax, sport: sport)
        }

        if let configuredMax = configuredMaxHeartRate(for: sport), configuredMax > 0 {
            return estimatedLTHR(fromMaxHeartRate: configuredMax, sport: sport)
        }

        return estimatedLTHR(
            fromMaxHeartRate: estimatedMaxHeartRateFromAge(),
            sport: sport
        )
    }

    mutating func recordLTHRRange(for sport: SportType, lthr: Int, startDate: Date = Date()) {
        guard lthr > 0 else { return }
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: startDate)

        if let idx = hrThresholdRanges.firstIndex(where: {
            $0.sport == sport && calendar.isDate($0.startDate, inSameDayAs: day)
        }) {
            hrThresholdRanges[idx].lthr = lthr
            hrThresholdRanges[idx].startDate = day
            hrThresholdRanges[idx].endDate = nil
        } else {
            for idx in hrThresholdRanges.indices where hrThresholdRanges[idx].sport == sport {
                if hrThresholdRanges[idx].contains(day, calendar: calendar),
                   calendar.startOfDay(for: hrThresholdRanges[idx].startDate) < day {
                    hrThresholdRanges[idx].endDate = day
                }
            }
            hrThresholdRanges.append(
                HeartRateThresholdRange(
                    sport: sport,
                    startDate: day,
                    endDate: nil,
                    lthr: lthr
                )
            )
        }

        hrThresholdRanges = normalizedThresholdRanges(hrThresholdRanges, calendar: calendar)
    }

    private func normalizedThresholdRanges(
        _ ranges: [HeartRateThresholdRange],
        calendar: Calendar
    ) -> [HeartRateThresholdRange] {
        var bySport: [SportType: [HeartRateThresholdRange]] = [:]
        for row in ranges where row.lthr > 0 {
            bySport[row.sport, default: []].append(row)
        }

        var output: [HeartRateThresholdRange] = []
        for sport in SportType.allCases {
            var list = (bySport[sport] ?? []).sorted {
                calendar.startOfDay(for: $0.startDate) < calendar.startOfDay(for: $1.startDate)
            }
            guard !list.isEmpty else { continue }
            for idx in list.indices {
                list[idx].startDate = calendar.startOfDay(for: list[idx].startDate)
            }
            for idx in list.indices.dropLast() {
                let nextStart = calendar.startOfDay(for: list[idx + 1].startDate)
                list[idx].endDate = nextStart
            }
            if let last = list.indices.last {
                list[last].endDate = nil
            }
            output.append(contentsOf: list)
        }
        return output
    }

    func heartRateThresholdRange(for sport: SportType, on date: Date) -> HeartRateThresholdRange? {
        hrThresholdRanges
            .filter { $0.sport == sport && $0.lthr > 0 && $0.contains(date) }
            .max(by: { $0.startDate < $1.startDate })
    }

    func aerobicThresholdHeartRate(for sport: SportType, on date: Date) -> Int {
        if let range = heartRateThresholdRange(for: sport, on: date), let ae = range.aeTHR, ae > 0 {
            return ae
        }
        let lthr = thresholdHeartRate(for: sport, on: date)
        return Int((Double(lthr) * 0.9).rounded())
    }

    func restingHeartRate(for sport: SportType, on date: Date) -> Int? {
        heartRateThresholdRange(for: sport, on: date)?.restingHR
    }

    func maxHeartRate(for sport: SportType, on date: Date) -> Int? {
        if let rangeMax = maxHeartRateFromRange(for: sport, on: date), rangeMax > 0 {
            return rangeMax
        }
        if let configured = configuredMaxHeartRate(for: sport), configured > 0 {
            return configured
        }
        return nil
    }

    private func configuredMaxHeartRate(for sport: SportType) -> Int? {
        switch sport {
        case .cycling: return cyclingMaxHeartRate > 0 ? cyclingMaxHeartRate : nil
        case .running: return runningMaxHeartRate > 0 ? runningMaxHeartRate : nil
        case .swimming: return swimmingMaxHeartRate > 0 ? swimmingMaxHeartRate : nil
        case .strength: return strengthMaxHeartRate > 0 ? strengthMaxHeartRate : nil
        }
    }

    private func maxHeartRateFromRange(for sport: SportType, on date: Date) -> Int? {
        hrThresholdRanges
            .filter { $0.sport == sport && $0.contains(date) }
            .compactMap(\.maxHR)
            .filter { $0 > 0 }
            .max()
    }

    private func estimatedMaxHeartRateFromAge() -> Int {
        let age = max(1, athleteAgeYears)
        let estimate = 208.0 - 0.7 * Double(age)
        return max(140, Int(estimate.rounded()))
    }

    private func estimatedLTHR(fromMaxHeartRate maxHR: Int, sport: SportType) -> Int {
        let ratio: Double
        switch sport {
        case .cycling: ratio = 0.90
        case .running: ratio = 0.92
        case .swimming: ratio = 0.88
        case .strength: ratio = 0.90
        }
        return max(90, Int((Double(maxHR) * ratio).rounded()))
    }

}

struct AIRecommendation {
    var readinessScore: Int
    var phase: String
    var todayFocus: String
    var weeklyFocus: [String]
    var cautions: [String]
}

enum TrainingScenario: String, CaseIterable, Identifiable {
    case dailyDecision
    case keyWorkout
    case enduranceBuild
    case lactateTest
    case raceTaper
    case recovery
    case returnFromBreak

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dailyDecision:
            return L10n.choose(simplifiedChinese: "日常决策", english: "Daily Decision")
        case .keyWorkout:
            return L10n.choose(simplifiedChinese: "关键课执行", english: "Key Workout")
        case .enduranceBuild:
            return L10n.choose(simplifiedChinese: "耐力构建", english: "Endurance Build")
        case .lactateTest:
            return L10n.choose(simplifiedChinese: "乳酸阈值测试", english: "Lactate Threshold Test")
        case .raceTaper:
            return L10n.choose(simplifiedChinese: "赛前减量", english: "Race Taper")
        case .recovery:
            return L10n.choose(simplifiedChinese: "恢复管理", english: "Recovery")
        case .returnFromBreak:
            return L10n.choose(simplifiedChinese: "停训回归", english: "Return From Break")
        }
    }

    var subtitle: String {
        switch self {
        case .dailyDecision:
            return L10n.choose(
                simplifiedChinese: "每天训练前快速判断今天该练什么。",
                english: "Quickly decide what to do today before training."
            )
        case .keyWorkout:
            return L10n.choose(
                simplifiedChinese: "保证高质量训练日达到目标而不过载。",
                english: "Hit quality-session goals without overreaching."
            )
        case .enduranceBuild:
            return L10n.choose(
                simplifiedChinese: "关注周期负荷与可持续增长。",
                english: "Focus on sustainable load growth across the cycle."
            )
        case .lactateTest:
            return L10n.choose(
                simplifiedChinese: "用分级乳酸测试校准 LT1/LT2 与训练区间。",
                english: "Use graded lactate testing to calibrate LT1/LT2 and training zones."
            )
        case .raceTaper:
            return L10n.choose(
                simplifiedChinese: "在保强度的前提下卸掉疲劳。",
                english: "Shed fatigue while keeping race-specific intensity."
            )
        case .recovery:
            return L10n.choose(
                simplifiedChinese: "优先恢复指标与负荷回落。",
                english: "Prioritize recovery signals and load reduction."
            )
        case .returnFromBreak:
            return L10n.choose(
                simplifiedChinese: "控制回归速度，避免二次受伤或过载。",
                english: "Control the return ramp to avoid relapse or overload."
            )
        }
    }
}

enum EnduranceFocus: String, CaseIterable, Identifiable {
    case cardiacFilling
    case aerobicEfficiency
    case fatigueResistance

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cardiacFilling:
            return L10n.choose(simplifiedChinese: "心脏舒张充盈", english: "Cardiac Filling")
        case .aerobicEfficiency:
            return L10n.choose(simplifiedChinese: "有氧效率", english: "Aerobic Efficiency")
        case .fatigueResistance:
            return L10n.choose(simplifiedChinese: "抗疲劳耐力", english: "Fatigue Resistance")
        }
    }

    var subtitle: String {
        switch self {
        case .cardiacFilling:
            return L10n.choose(
                simplifiedChinese: "通过低强度长时段训练，提升每搏输出与舒张充盈效率。",
                english: "Use long low-intensity work to improve stroke volume and filling efficiency."
            )
        case .aerobicEfficiency:
            return L10n.choose(
                simplifiedChinese: "在同等心率下跑/骑得更快。",
                english: "Go faster at the same heart rate."
            )
        case .fatigueResistance:
            return L10n.choose(
                simplifiedChinese: "在累积疲劳下保持输出稳定。",
                english: "Maintain stable output under accumulated fatigue."
            )
        }
    }
}

struct ScenarioMetricItem: Identifiable {
    enum Tone {
        case good
        case watch
        case risk
    }

    let id = UUID()
    var name: String
    var value: String
    var reason: String
    var tone: Tone
}

struct ScenarioMetricPack {
    var scenario: TrainingScenario
    var headline: String
    var items: [ScenarioMetricItem]
    var actions: [String]
}

struct MetricStory: Identifiable {
    enum Tone {
        case positive
        case neutral
        case warning
    }

    let id = UUID()
    var title: String
    var body: String
    var tone: Tone
}

struct ActivityMetricInsight: Codable, Identifiable {
    var id: UUID { activityID }
    var activityID: UUID
    var activityDate: Date
    var generatedAt: Date
    var model: String
    var fingerprint: String
    var summary: String
    var keyFindings: [String]
    var actions: [String]
}

enum LactateTestType: String, CaseIterable, Identifiable, Codable {
    case ramp
    case mlss
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ramp:
            return L10n.t("全递增乳酸测试", "Ramp Test")
        case .mlss:
            return L10n.t("最大乳酸稳态测试", "MLSS Test")
        case .custom:
            return L10n.t("自定义测试", "Custom Test")
        }
    }
}

struct LactateSamplePoint: Codable, Identifiable {
    let id: UUID
    let power: Double
    let lactate: Double

    init(id: UUID = UUID(), power: Double, lactate: Double) {
        self.id = id
        self.power = power
        self.lactate = lactate
    }
}

struct LactateHistoryRecord: Codable, Identifiable {
    let id: UUID
    let tester: String
    let type: LactateTestType
    let createdAt: Date
    let points: [LactateSamplePoint]

    init(
        id: UUID = UUID(),
        tester: String,
        type: LactateTestType,
        createdAt: Date,
        points: [LactateSamplePoint]
    ) {
        self.id = id
        self.tester = tester
        self.type = type
        self.createdAt = createdAt
        self.points = points
    }
}

extension Int {
    var asDuration: String {
        let h = self / 3600
        let m = (self % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }
}
