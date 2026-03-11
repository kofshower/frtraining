import XCTest
@testable import FricuApp

/// Tests that guard Fat-loss Assistant routing and copy regressions.
final class FatLossAssistantPageTests: XCTestCase {
    private let languageStorageKey = AppLanguageOption.storageKey

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: languageStorageKey)
        super.tearDown()
    }

    /// Ensures the new app section is available in the global section list.
    func testAppSectionIncludesFatLossAssistant() {
        XCTAssertTrue(AppSection.allCases.contains(.fatLossAssistant))
    }

    /// Ensures static localized title resolves to Chinese when Chinese is selected.
    func testFatLossAssistantLocalizedTitleInChinese() {
        UserDefaults.standard.set(AppLanguageOption.simplifiedChinese.rawValue, forKey: languageStorageKey)

        XCTAssertEqual(AppSection.fatLossAssistant.localizedTitle, "减脂助手")
    }

    /// Ensures bilingual copy token resolves to English when English is selected.
    func testBilingualCopyLocalizedResolvesEnglish() {
        UserDefaults.standard.set(AppLanguageOption.english.rawValue, forKey: languageStorageKey)
        let copy = FatLossAssistantBilingualCopy(simplifiedChinese: "中文", english: "English")

        XCTAssertEqual(copy.localized(), "English")
    }

    /// Guards core copy cards from becoming empty during future edits.
    func testCoreCopyTokensAreNotEmpty() {
        let copyTokens: [FatLossAssistantBilingualCopy] = [
            FatLossAssistantCopy.pageTitle,
            FatLossAssistantCopy.subtitle,
            FatLossAssistantCopy.dailyChecklistTitle,
            FatLossAssistantCopy.strategyTitle,
            FatLossAssistantCopy.reviewTitle,
        ]

        for token in copyTokens {
            XCTAssertFalse(token.simplifiedChinese.isEmpty)
            XCTAssertFalse(token.english.isEmpty)
        }
    }

    /// Ensures decision-tree nodes are one-to-one with detail cards and keep stable order.
    func testDecisionTreeNodesMapOneToOneWithCards() {
        let nodes = FatLossDecisionNode.allCases

        XCTAssertEqual(nodes.map(\.stepNumber), [1, 2, 3, 4])
        XCTAssertEqual(Set(nodes.map(\.id)).count, nodes.count)
        XCTAssertEqual(Set(nodes.map(\.detailCardTitle)).count, nodes.count)

        for node in nodes {
            XCTAssertFalse(node.title.isEmpty)
            XCTAssertFalse(node.icon.isEmpty)
            XCTAssertFalse(node.detailCardTitle.isEmpty)
        }
    }
}
