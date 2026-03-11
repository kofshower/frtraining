import Foundation

enum AthleteIdentityNormalizer {
    static func normalizedNonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func canonicalName(_ raw: String?) -> String? {
        normalizedNonEmpty(raw)
    }

    static func panelID(from raw: String?) -> String {
        canonicalName(raw)?.lowercased() ?? AthletePanel.unknownAthleteToken
    }

    static func displayName(rawName: String?, fallback: String) -> String {
        canonicalName(rawName) ?? fallback
    }
}
