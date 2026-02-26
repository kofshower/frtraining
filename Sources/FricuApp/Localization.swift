import Foundation
import SwiftUI
#if canImport(ObjectiveC)
import ObjectiveC.runtime
#endif

enum AppLanguageOption: String, CaseIterable, Identifiable {
    case system
    case simplifiedChinese = "zh-Hans"
    case english = "en"

    static let storageKey = "app.language.option"

    var id: String { rawValue }

    var locale: Locale {
        switch self {
        case .system:
            return .autoupdatingCurrent
        case .simplifiedChinese:
            return Locale(identifier: "zh-Hans")
        case .english:
            return Locale(identifier: "en")
        }
    }

    var titleKey: LocalizedStringKey {
        switch self {
        case .system:
            return "settings.language.option.system"
        case .simplifiedChinese:
            return "settings.language.option.zhHans"
        case .english:
            return "settings.language.option.english"
        }
    }

    var localizedTitle: String {
        switch self {
        case .system:
            return L10n.string("settings.language.option.system")
        case .simplifiedChinese:
            return L10n.string("settings.language.option.zhHans")
        case .english:
            return L10n.string("settings.language.option.english")
        }
    }
}

enum L10n {
    private static let resourceBundle = Bundle.module

    private static var selectedOption: AppLanguageOption {
        let raw = UserDefaults.standard.string(forKey: AppLanguageOption.storageKey) ?? AppLanguageOption.system.rawValue
        return AppLanguageOption(rawValue: raw) ?? .system
    }

    private static var systemPrefersSimplifiedChinese: Bool {
        Locale.preferredLanguages.first?.lowercased().hasPrefix("zh") == true
    }

    static var prefersSimplifiedChinese: Bool {
        let option = selectedOption
        switch option {
        case .simplifiedChinese:
            return true
        case .english:
            return false
        case .system:
            return systemPrefersSimplifiedChinese
        }
    }

    private static func fallbackByOption(
        option: AppLanguageOption,
        english: String,
        simplifiedChinese: String
    ) -> String {
        switch option {
        case .english:
            return english
        case .simplifiedChinese:
            return simplifiedChinese
        case .system:
            return systemPrefersSimplifiedChinese ? simplifiedChinese : english
        }
    }

    private static func staticFallback(for key: String, option: AppLanguageOption) -> String? {
        switch key {
        case "app.section.dashboard":
            return fallbackByOption(option: option, english: "Dashboard", simplifiedChinese: "仪表盘")
        case "app.section.trainer":
            return fallbackByOption(option: option, english: "Trainer", simplifiedChinese: "骑行台")
        case "app.section.prosuite":
            return fallbackByOption(option: option, english: "Pro Suite", simplifiedChinese: "专业套件")
        case "app.section.workoutBuilder":
            return fallbackByOption(option: option, english: "Workout Builder", simplifiedChinese: "训练构建")
        case "app.section.library":
            return fallbackByOption(option: option, english: "Library", simplifiedChinese: "活动库")
        case "app.section.insights":
            return fallbackByOption(option: option, english: "Insights", simplifiedChinese: "洞察")
        case "app.section.settings":
            return fallbackByOption(option: option, english: "Settings", simplifiedChinese: "设置")
        case "toolbar.sport":
            return fallbackByOption(option: option, english: "Sport", simplifiedChinese: "运动")
        case "toolbar.sport.all":
            return fallbackByOption(option: option, english: "All Sports", simplifiedChinese: "全部运动")
        case "settings.language.title":
            return fallbackByOption(option: option, english: "Language", simplifiedChinese: "语言")
        case "settings.language.picker":
            return fallbackByOption(option: option, english: "App Language", simplifiedChinese: "应用语言")
        case "settings.language.option.system":
            return fallbackByOption(option: option, english: "System", simplifiedChinese: "跟随系统")
        case "settings.language.option.zhHans":
            return fallbackByOption(option: option, english: "Simplified Chinese", simplifiedChinese: "简体中文")
        case "settings.language.option.english":
            return fallbackByOption(option: option, english: "English", simplifiedChinese: "English")
        case "prosuite.module.picker":
            return fallbackByOption(option: option, english: "Module", simplifiedChinese: "模块")
        case "prosuite.module.planner":
            return fallbackByOption(option: option, english: "Training Calendar", simplifiedChinese: "训练日历")
        case "prosuite.module.intervals":
            return fallbackByOption(option: option, english: "Interval Lab", simplifiedChinese: "间歇实验室")
        case "prosuite.module.metrics":
            return fallbackByOption(option: option, english: "Chart Engine", simplifiedChinese: "图表引擎")
        case "prosuite.module.powerModels":
            return fallbackByOption(option: option, english: "Power Modeling", simplifiedChinese: "功率建模")
        case "prosuite.module.activityGrid":
            return fallbackByOption(option: option, english: "Activity Grid", simplifiedChinese: "活动网格")
        case "prosuite.module.collaboration":
            return fallbackByOption(option: option, english: "Collaboration", simplifiedChinese: "协作")
        case "prosuite.module.integrations":
            return fallbackByOption(option: option, english: "Integrations", simplifiedChinese: "集成中心")
        case "prosuite.module.forensic":
            return fallbackByOption(option: option, english: "Forensic", simplifiedChinese: "取证")
        case "app.chrome.pagePicker":
            return fallbackByOption(option: option, english: "Page", simplifiedChinese: "页面")
        case "app.chrome.close":
            return fallbackByOption(option: option, english: "Close", simplifiedChinese: "关闭")
        case "app.chrome.close.help":
            return fallbackByOption(option: option, english: "Close current window", simplifiedChinese: "关闭当前窗口")
        case "Scenario":
            return fallbackByOption(option: option, english: "Scenario", simplifiedChinese: "场景")
        case "Scenario Lens":
            return fallbackByOption(option: option, english: "Scenario Lens", simplifiedChinese: "场景视角")
        case "sport.cycling":
            return fallbackByOption(option: option, english: "Cycling", simplifiedChinese: "骑行")
        case "sport.running":
            return fallbackByOption(option: option, english: "Running", simplifiedChinese: "跑步")
        case "sport.swimming":
            return fallbackByOption(option: option, english: "Swimming", simplifiedChinese: "游泳")
        case "sport.strength":
            return fallbackByOption(option: option, english: "Strength", simplifiedChinese: "力量")
        default:
            return nil
        }
    }

    private static func bundle(for option: AppLanguageOption) -> Bundle {
        switch option {
        case .system:
            return resourceBundle
        case .simplifiedChinese, .english:
            let raw = option.rawValue
            let candidates: [String] = [
                raw,
                raw.lowercased(),
                raw.replacingOccurrences(of: "-", with: "_"),
                raw.lowercased().replacingOccurrences(of: "-", with: "_"),
                String(raw.prefix(2)),
            ]
            for candidate in candidates {
                guard let path = resourceBundle.path(forResource: candidate, ofType: "lproj") else { continue }
                if let bundle = Bundle(path: path) {
                    return bundle
                }
            }
            return resourceBundle
        }
    }

    static func string(_ key: String) -> String {
        let option = selectedOption
        let bundles = [bundle(for: option), resourceBundle]

        var visited = Set<String>()
        for bundle in bundles {
            let identity = bundle.bundleURL.path
            if visited.contains(identity) { continue }
            visited.insert(identity)

            let value = bundle.localizedString(forKey: key, value: key, table: nil)
            if value != key {
                return value
            }
        }

        return staticFallback(for: key, option: option) ?? key
    }

    static func choose(simplifiedChinese: String, english: String) -> String {
        prefersSimplifiedChinese ? simplifiedChinese : english
    }

    static func t(_ simplifiedChinese: String, _ english: String) -> String {
        choose(simplifiedChinese: simplifiedChinese, english: english)
    }

    static func installBundleBridgeIfNeeded() {
        Bundle.installFricuLocalizationBridgeIfNeeded()
    }
}

#if canImport(ObjectiveC)
private enum BundleBridgeState {
    static var installed = false
}

private extension Bundle {
    @objc func fricu_localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
        if self == .main {
            let localized = L10n.string(key)
            if localized != key {
                return localized
            }
        }
        return fricu_localizedString(forKey: key, value: value, table: tableName)
    }

    static func installFricuLocalizationBridgeIfNeeded() {
        guard !BundleBridgeState.installed else { return }

        guard
            let original = class_getInstanceMethod(
                Bundle.self,
                #selector(Bundle.localizedString(forKey:value:table:))
            ),
            let replacement = class_getInstanceMethod(
                Bundle.self,
                #selector(Bundle.fricu_localizedString(forKey:value:table:))
            )
        else {
            return
        }

        method_exchangeImplementations(original, replacement)
        BundleBridgeState.installed = true
    }
}
#else
private extension Bundle {
    static func installFricuLocalizationBridgeIfNeeded() {}
}
#endif
