import SwiftUI

struct VideoFittingCameraViewCards: View {
    let cards: [VideoFittingCameraViewCardSummary]
    let isBusy: Bool
    let chooseAction: (CyclingCameraView) -> Void
    let clearAction: (CyclingCameraView) -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 240), spacing: 12, alignment: .top)
    ]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
            ForEach(cards) { card in
                cardView(for: card)
            }
        }
    }

    @ViewBuilder
    private func cardView(for card: VideoFittingCameraViewCardSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(card.title)
                        .font(.headline)
                    Text(card.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                Text(card.statusTitle)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(toneColor(for: card).opacity(0.14), in: Capsule())
                    .foregroundStyle(toneColor(for: card))
            }

            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(toneColor(for: card).opacity(0.08))
                .frame(height: 110)
                .overlay(alignment: .topLeading) {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(
                            card.fileName ?? L10n.choose(simplifiedChinese: "缩略图占位", english: "Thumbnail placeholder"),
                            systemImage: thumbnailSymbol(for: card.view)
                        )
                        .font(.caption.weight(.semibold))
                        .lineLimit(2)

                        Text(
                            card.fileName == nil
                                ? L10n.choose(simplifiedChinese: "上传后将在这里显示机位文件占位。", english: "The assigned video placeholder appears here after upload.")
                                : L10n.choose(simplifiedChinese: "当前已绑定该机位视频，可直接替换或删除。", english: "A video is assigned to this view. You can replace or remove it directly.")
                        )
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                    .padding(12)
                }

            infoBlock(title: L10n.choose(simplifiedChinese: "质量状态", english: "Quality Status"), accent: qualityAccent(for: card)) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(card.qualityTitle)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(qualityAccent(for: card))
                    Text(card.qualityDetail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if !card.blockingReasons.isEmpty {
                infoBlock(title: L10n.choose(simplifiedChinese: "阻塞原因", english: "Blocking Issues"), accent: .orange) {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(card.blockingReasons, id: \.self) { reason in
                            Label(reason, systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                }
            }

            if !card.qualityMetrics.isEmpty {
                infoBlock(title: L10n.choose(simplifiedChinese: "质量指标", english: "Quality Metrics"), accent: qualityAccent(for: card)) {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 8) {
                        ForEach(card.qualityMetrics) { metric in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(metric.title)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Text(metric.value)
                                    .font(.caption)
                                    .foregroundStyle(.primary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                            .background(toneColor(for: card).opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                    }
                }
            }

            infoBlock(title: L10n.choose(simplifiedChinese: "支持的分析结论", english: "Supported Conclusions"), accent: .teal) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(card.supportedConclusions, id: \.self) { item in
                        Label(item, systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.teal)
                    }
                }
            }

            if card.hasAssignedVideo {
                Text(card.statusDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                infoBlock(title: L10n.choose(simplifiedChinese: "缺失影响", english: "Missing Impact"), accent: .orange) {
                    Text(card.missingImpact)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 8) {
                Button(
                    card.hasAssignedVideo
                        ? L10n.choose(simplifiedChinese: "替换", english: "Replace")
                        : L10n.choose(simplifiedChinese: "上传", english: "Upload")
                ) {
                    chooseAction(card.view)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isBusy)

                Button(L10n.choose(simplifiedChinese: "删除", english: "Remove")) {
                    clearAction(card.view)
                }
                .buttonStyle(.bordered)
                .disabled(isBusy || !card.hasAssignedVideo)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(14)
        .background(toneColor(for: card).opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(toneColor(for: card).opacity(0.18), lineWidth: 1)
        }
    }

    @ViewBuilder
    private func infoBlock<Content: View>(title: String, accent: Color, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(accent)
            content()
        }
    }

    private func toneColor(for card: VideoFittingCameraViewCardSummary) -> Color {
        switch card.tone {
        case .empty:
            return .secondary
        case .partial:
            return .orange
        case .ready:
            return .green
        }
    }

    private func qualityAccent(for card: VideoFittingCameraViewCardSummary) -> Color {
        switch card.tone {
        case .empty:
            return .secondary
        case .partial:
            return .orange
        case .ready:
            return .green
        }
    }

    private func thumbnailSymbol(for view: CyclingCameraView) -> String {
        switch view {
        case .front:
            return "figure.stand.line.dotted.figure.stand"
        case .side:
            return "figure.walk.motion"
        case .rear:
            return "figure.turn.right"
        case .auto:
            return "video"
        }
    }
}
