import Foundation

enum AthleteIdentityNormalizer {
    private static let legacySeparators: [String] = [
        "---来自Fricu",
        "---来自 Fricu",
        "---fromFricu",
        "---from Fricu",
        " · Trainer ride",
        " · 训练骑行",
        "• Trainer ride",
        "• 训练骑行"
    ]

    static func normalizedNonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func canonicalName(_ raw: String?) -> String? {
        guard let normalized = normalizedNonEmpty(raw) else { return nil }
        return stripLegacySuffix(from: normalized)
    }

    static func extractName(fromLegacyText text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return stripLegacySuffix(from: trimmed)
    }

    static func panelID(from raw: String?) -> String {
        canonicalName(raw)?.lowercased() ?? AthletePanel.unknownAthleteToken
    }

    static func displayName(rawName: String?, notes: String, fallback: String) -> String {
        canonicalName(rawName) ?? extractName(fromLegacyText: notes) ?? fallback
    }

    private static func stripLegacySuffix(from text: String) -> String? {
        for separator in legacySeparators {
            if let range = text.range(of: separator, options: [.caseInsensitive]) {
                let prefix = String(text[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !prefix.isEmpty {
                    return prefix
                }
            }
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
