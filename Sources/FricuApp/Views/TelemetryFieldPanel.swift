import SwiftUI

struct TelemetryField: Identifiable {
    let id = UUID()
    let label: String
    let value: String
}

struct TelemetryFieldSection: Identifiable {
    let id = UUID()
    let title: String
    let rows: [TelemetryField]
    var minimumColumnWidth: CGFloat = 280
}

struct TelemetryFieldPanel: View {
    let title: String
    let sections: [TelemetryFieldSection]

    var body: some View {
        GroupBox(title) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(sections) { section in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(section.title)
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)

                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: section.minimumColumnWidth), spacing: 8, alignment: .leading)],
                            spacing: 8
                        ) {
                            ForEach(section.rows) { row in
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(row.label)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    Text(row.value)
                                        .font(.caption.monospacedDigit())
                                        .textSelection(.enabled)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }
                }
            }
            .padding(.top, 4)
        }
    }
}

enum TelemetryFieldFactory {
    static func noDataRows(label: String) -> [TelemetryField] {
        [.init(label: label, value: L10n.t("暂无数据", "No data yet"))]
    }

    static func rawRows(from cache: [String: String], emptyLabel: String = L10n.t("Raw Characteristic", "Raw Characteristic")) -> [TelemetryField] {
        let sortedKeys = cache.keys.sorted()
        guard !sortedKeys.isEmpty else { return noDataRows(label: emptyLabel) }
        return sortedKeys.map { .init(label: $0, value: cache[$0] ?? "--") }
    }

    static func format(_ value: Double?, unit: String, digits: Int = 1) -> String {
        guard let value else { return "--" }
        return String(format: "%.\(digits)f%@", value, unit)
    }
}
