import SwiftUI

struct VideoFittingSessionSummaryCard: View {
    let summary: VideoFittingSessionSummary

    private let columns = [
        GridItem(.adaptive(minimum: 220), spacing: 12, alignment: .top)
    ]

    var body: some View {
        GroupBox(L10n.choose(simplifiedChinese: "Session 总览", english: "Session Summary")) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(summary.statusTitle)
                            .font(.title3.weight(.semibold))
                        Text(summary.statusDetail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 12)

                    VStack(alignment: .trailing, spacing: 8) {
                        Text(summary.progressText)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(toneColor.opacity(0.14), in: Capsule())
                            .foregroundStyle(toneColor)

                        ProgressView(value: summary.completionRatio)
                            .progressViewStyle(.linear)
                            .frame(width: 180)
                            .tint(toneColor)
                    }
                }

                LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                    summaryBlock(
                        title: L10n.choose(simplifiedChinese: "当前状态", english: "Current Status"),
                        accent: toneColor
                    ) {
                        Text(summary.statusDetail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    summaryBlock(
                        title: summary.capabilitySummary,
                        accent: capabilityAccent
                    ) {
                        if summary.availableCapabilityTitles.isEmpty {
                            Text(
                                L10n.choose(
                                    simplifiedChinese: "暂无可分析能力；先分配机位视频。",
                                    english: "No analysis capability yet. Assign view videos first."
                                )
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        } else {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(summary.availableCapabilityTitles, id: \.self) { title in
                                    Label(title, systemImage: "checkmark.circle.fill")
                                        .font(.caption)
                                        .foregroundStyle(capabilityAccent)
                                }
                            }
                        }
                    }

                    summaryBlock(
                        title: summary.nextActionTitle,
                        accent: .orange
                    ) {
                        Text(summary.nextActionDetail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var toneColor: Color {
        switch summary.tone {
        case .empty:
            return .secondary
        case .partial:
            return .orange
        case .ready:
            return .green
        }
    }

    private var capabilityAccent: Color {
        summary.availableCapabilityTitles.isEmpty ? .secondary : .green
    }

    @ViewBuilder
    private func summaryBlock<Content: View>(
        title: String,
        accent: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(accent)
            content()
        }
        .frame(maxWidth: .infinity, minHeight: 88, alignment: .topLeading)
        .padding(12)
        .background(accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
