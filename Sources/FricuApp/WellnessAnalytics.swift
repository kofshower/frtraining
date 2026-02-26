import Foundation

extension Array where Element == WellnessSample {
    func sortedByDateDescending() -> [WellnessSample] {
        sorted { $0.date > $1.date }
    }

    func sortedByDateAscending() -> [WellnessSample] {
        sorted { $0.date < $1.date }
    }

    // Expects samples already sorted from newest to oldest.
    func averageMostRecent(_ count: Int, keyPath: KeyPath<WellnessSample, Double?>) -> Double? {
        guard count > 0 else { return nil }
        let values = prefix(count).compactMap { $0[keyPath: keyPath] }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    // Expects samples already sorted from newest to oldest.
    func latestValue(_ keyPath: KeyPath<WellnessSample, Double?>) -> Double? {
        compactMap { $0[keyPath: keyPath] }.first
    }
}
