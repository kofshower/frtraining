import XCTest
@testable import FricuApp

/// Tests for nutrition page copy tokens to avoid accidental empty or regressed wording.
final class NutritionPageCopyTests: XCTestCase {
    private let languageStorageKey = AppLanguageOption.storageKey

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: languageStorageKey)
        super.tearDown()
    }

    /// Verifies the shared bilingual token resolves to Chinese text when language is Chinese.
    func testBilingualCopyLocalizedReturnsChineseText() {
        let copy = NutritionPageBilingualCopy(simplifiedChinese: "中文文案", english: "English copy")
        UserDefaults.standard.set(AppLanguageOption.simplifiedChinese.rawValue, forKey: languageStorageKey)

        XCTAssertEqual(copy.localized(), "中文文案")
    }

    /// Verifies the shared bilingual token resolves to English text when language is English.
    func testBilingualCopyLocalizedReturnsEnglishText() {
        let copy = NutritionPageBilingualCopy(simplifiedChinese: "中文文案", english: "English copy")
        UserDefaults.standard.set(AppLanguageOption.english.rawValue, forKey: languageStorageKey)

        XCTAssertEqual(copy.localized(), "English copy")
    }

    /// Guards key fat-loss section titles from becoming empty.
    func testFatLossSectionTitlesAreNotEmpty() {
        let titles: [NutritionPageBilingualCopy] = [
            NutritionPageCopy.coreLogicTitle,
            NutritionPageCopy.mechanismTitle,
            NutritionPageCopy.engineTitle,
            NutritionPageCopy.executionTitle,
            NutritionPageCopy.screenshotInsightsTitle,
            NutritionPageCopy.appetiteMechanismTitle
        ]

        for title in titles {
            XCTAssertFalse(title.simplifiedChinese.isEmpty)
            XCTAssertFalse(title.english.isEmpty)
        }
    }
    /// Guards screenshot-derived pathway summary copy from becoming empty.
    func testScreenshotInsightSummaryCopyIsNotEmpty() {
        XCTAssertFalse(NutritionPageCopy.screenshotInsightsSummary.simplifiedChinese.isEmpty)
        XCTAssertFalse(NutritionPageCopy.screenshotInsightsSummary.english.isEmpty)
    }

    /// Guards the screenshot-derived appetite regulation summary copy from becoming empty.
    func testAppetiteMechanismSummaryCopyIsNotEmpty() {
        XCTAssertFalse(NutritionPageCopy.appetiteMechanismSummary.simplifiedChinese.isEmpty)
        XCTAssertFalse(NutritionPageCopy.appetiteMechanismSummary.english.isEmpty)
    }

    /// Ensures the new mechanism card keeps core terms for product intent.
    func testAppetiteMechanismSummaryContainsCoreConcepts() {
        XCTAssertTrue(NutritionPageCopy.appetiteMechanismSummary.simplifiedChinese.contains("低 GI"))
        XCTAssertTrue(NutritionPageCopy.appetiteMechanismSummary.simplifiedChinese.contains("瘦素抵抗"))
        XCTAssertTrue(NutritionPageCopy.appetiteMechanismSummary.english.contains("low-GI"))
        XCTAssertTrue(NutritionPageCopy.appetiteMechanismSummary.english.contains("leptin resistance"))
    }
}
