import AVFoundation
import AVKit
import CoreGraphics
import SwiftUI

struct VideoFittingCaptureGuidePanel: View {
    let highlightMissingSetup: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(L10n.choose(simplifiedChinese: "录制指导", english: "Recording Guide"))
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if highlightMissingSetup {
                    Text(L10n.choose(simplifiedChinese: "建议先看完再上传", english: "Review before upload"))
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.orange.opacity(0.12), in: Capsule())
                        .foregroundStyle(.orange)
                }
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 10, alignment: .top)], alignment: .leading, spacing: 10) {
                guideItem(
                    title: L10n.choose(simplifiedChinese: "相机摆位", english: "Camera Placement"),
                    detail: L10n.choose(
                        simplifiedChinese: "前视对准车身中线；侧视与曲柄平面尽量垂直；后视确保左右髋都可见。",
                        english: "Center the bike in front view; keep side view orthogonal to the crank plane; keep both hips visible in rear view."
                    ),
                    tint: .cyan
                )
                guideItem(
                    title: L10n.choose(simplifiedChinese: "光线建议", english: "Lighting"),
                    detail: L10n.choose(
                        simplifiedChinese: "优先使用前侧补光，避免逆光和高反差阴影，保证关节边界清楚。",
                        english: "Use front/side lighting, avoid backlight and harsh shadows, and keep joint boundaries clear."
                    ),
                    tint: .yellow
                )
                guideItem(
                    title: L10n.choose(simplifiedChinese: "完整入镜", english: "Full Framing"),
                    detail: L10n.choose(
                        simplifiedChinese: "确保人体、车把、车轮与曲柄完整入镜，避免衣物或器材挡住髋-膝-踝。",
                        english: "Keep the rider, handlebars, wheels, and cranks fully in frame; avoid clothing or equipment blocking hip-knee-ankle."
                    ),
                    tint: .teal
                )
                guideItem(
                    title: L10n.choose(simplifiedChinese: "录制时长", english: "Suggested Duration"),
                    detail: L10n.choose(
                        simplifiedChinese: "建议 20-60 秒，保持稳定踩踏；首次录制优先 30 秒，方便快速检查与重拍。",
                        english: "Record for 20-60 seconds with steady pedaling; start with 30 seconds for a quick first pass and retake."
                    ),
                    tint: .indigo
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.14), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func guideItem(title: String, detail: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct VideoFittingComplianceResultCardsView: View {
    let summaries: [VideoFittingComplianceViewSummary]

    private let columns = [
        GridItem(.adaptive(minimum: 220), spacing: 12, alignment: .top)
    ]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
            ForEach(summaries) { summary in
                VideoFittingComplianceResultCard(summary: summary)
            }
        }
    }
}

private struct VideoFittingComplianceResultCard: View {
    let summary: VideoFittingComplianceViewSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(summary.title)
                        .font(.subheadline.weight(.semibold))
                    Text(summary.statusTitle)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(toneColor)
                }
                Spacer()
                Label(summary.qualityTitle, systemImage: toneIcon)
                    .font(.caption)
                    .foregroundStyle(toneColor)
            }

            Text(summary.statusDetail)
                .font(.caption)
                .foregroundStyle(.secondary)

            resultSection(
                title: L10n.choose(simplifiedChinese: "问题原因", english: "Reasons"),
                lines: summary.reasonLines,
                emptyFallback: L10n.choose(simplifiedChinese: "暂无问题。", english: "No issue detected.")
            )

            resultSection(
                title: L10n.choose(simplifiedChinese: "修复建议", english: "Fix Suggestions"),
                lines: summary.recommendationLines,
                emptyFallback: L10n.choose(simplifiedChinese: "无需调整。", english: "No action needed.")
            )

            Text(summary.qualityDetail)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(toneColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(toneColor.opacity(0.18), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func resultSection(title: String, lines: [String], emptyFallback: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)

            if lines.isEmpty {
                Text(emptyFallback)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    Text("• \(line)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var toneColor: Color {
        switch summary.tone {
        case .empty:
            return .secondary
        case .pending:
            return .cyan
        case .passed:
            return .green
        case .failed:
            return .orange
        }
    }

    private var toneIcon: String {
        switch summary.tone {
        case .empty:
            return "tray"
        case .pending:
            return "clock"
        case .passed:
            return "checkmark.seal.fill"
        case .failed:
            return "exclamationmark.triangle.fill"
        }
    }
}

struct VideoFittingJointRecognitionQualityPanel: View {
    let summary: VideoFittingJointRecognitionQualitySummary
    @State private var expandedVisual: VideoFittingExpandedVisual?
    private let indicatorColumns = [
        GridItem(.adaptive(minimum: 120), spacing: 8, alignment: .leading)
    ]
    private let angleColumns = [
        GridItem(.adaptive(minimum: 180), spacing: 10, alignment: .top)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.choose(simplifiedChinese: "骨点识别质量", english: "Recognition Quality"))
                        .font(.subheadline.weight(.semibold))
                    Text(summary.statusTitle)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(toneColor)
                }
                Spacer()
                Text(summary.statusDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }

            HStack(spacing: 10) {
                qualityMetricCard(
                    title: L10n.choose(simplifiedChinese: "置信度", english: "Confidence"),
                    value: summary.confidenceText,
                    tint: toneColor
                )
                qualityMetricCard(
                    title: L10n.choose(simplifiedChinese: "丢点率", english: "Drop Rate"),
                    value: summary.dropRateText,
                    tint: .orange
                )
                qualityMetricCard(
                    title: L10n.choose(simplifiedChinese: "问题帧数量", english: "Problem Frames"),
                    value: summary.problemFrameCountText,
                    tint: .pink
                )
            }

            if let playbackOverlay = summary.playbackOverlay, let videoURL = summary.previewVideoURL {
                VideoFittingOverlayPlaybackPanel(
                    overlay: playbackOverlay,
                    videoURL: videoURL,
                    tint: toneColor
                )
            }

            if !summary.angleVisuals.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.choose(simplifiedChinese: "关节角度示意", english: "Joint Angle Preview"))
                        .font(.caption.weight(.semibold))
                    LazyVGrid(columns: angleColumns, alignment: .leading, spacing: 10) {
                        ForEach(summary.angleVisuals) { visual in
                            VideoFittingJointAngleVisualCard(
                                summary: visual,
                                tint: toneColor,
                                videoURL: summary.previewVideoURL,
                                displayMode: .compact,
                                onExpand: {
                                    expandedVisual = .joint(
                                        summary: visual,
                                        videoURL: summary.previewVideoURL,
                                        tint: toneColor
                                    )
                                }
                            )
                        }
                    }
                }
            }

            if !summary.checkpointVisuals.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(L10n.choose(simplifiedChinese: "关键点位帧", english: "Checkpoint Frames"))
                            .font(.caption.weight(.semibold))
                        Spacer()
                        Text(L10n.choose(simplifiedChinese: "0 / 3 / 6 / 9 点", english: "0 / 3 / 6 / 9 checkpoints"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    LazyVGrid(columns: angleColumns, alignment: .leading, spacing: 10) {
                        ForEach(summary.checkpointVisuals) { visual in
                            VideoFittingCheckpointVisualCard(
                                summary: visual,
                                tint: toneColor,
                                videoURL: summary.previewVideoURL,
                                displayMode: .compact,
                                onExpand: {
                                    expandedVisual = .checkpoint(
                                        summary: visual,
                                        videoURL: summary.previewVideoURL,
                                        tint: toneColor
                                    )
                                }
                            )
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.choose(simplifiedChinese: "遮挡提示", english: "Occlusion Hint"))
                    .font(.caption.weight(.semibold))
                Text(summary.occlusionHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.choose(simplifiedChinese: "当前可计算指标", english: "Computable Indicators"))
                    .font(.caption.weight(.semibold))
                if summary.computableIndicators.isEmpty {
                    Text(L10n.choose(simplifiedChinese: "暂无可计算指标。", english: "No computable indicators yet."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    LazyVGrid(columns: indicatorColumns, alignment: .leading, spacing: 8) {
                        ForEach(summary.computableIndicators, id: \.self) { indicator in
                            Text(indicator)
                                .font(.caption)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(toneColor.opacity(0.10), in: Capsule())
                                .foregroundStyle(toneColor)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(toneColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(toneColor.opacity(0.18), lineWidth: 1)
        )
        .sheet(item: $expandedVisual) { visual in
            VideoFittingExpandedVisualSheet(visual: visual)
        }
    }

    @ViewBuilder
    private func qualityMetricCard(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
            Text(value)
                .font(.caption.monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var toneColor: Color {
        switch summary.tone {
        case .empty:
            return .secondary
        case .blocked:
            return .orange
        case .pending:
            return .cyan
        case .ready:
            return .green
        }
    }
}

private struct VideoFittingOverlayPlaybackPanel: View {
    let overlay: VideoFittingPlaybackOverlaySummary
    let videoURL: URL
    let tint: Color

    @StateObject private var playback: VideoFittingOverlayPlaybackController

    init(overlay: VideoFittingPlaybackOverlaySummary, videoURL: URL, tint: Color) {
        self.overlay = overlay
        self.videoURL = videoURL
        self.tint = tint
        _playback = StateObject(wrappedValue: VideoFittingOverlayPlaybackController(videoURL: videoURL))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.choose(simplifiedChinese: "叠加回放", english: "Overlay Playback"))
                        .font(.caption.weight(.semibold))
                    Text(L10n.choose(
                        simplifiedChinese: "直接播放原视频，并在画面上叠加当前帧的关节夹角与关键点位。",
                        english: "Play the source clip directly with live joint-angle and checkpoint overlays."
                    ))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                if let current = currentSample {
                    HStack(spacing: 8) {
                        metricBadge(
                            title: L10n.choose(simplifiedChinese: "膝角", english: "Knee"),
                            value: angleText(current.kneeAngleDegrees)
                        )
                        metricBadge(
                            title: L10n.choose(simplifiedChinese: "髋角", english: "Hip"),
                            value: angleText(current.hipAngleDegrees)
                        )
                    }
                }
            }

            ZStack(alignment: .topLeading) {
                VideoFittingEmbeddedAVPlayerView(player: playback.player)
                    .frame(height: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(tint.opacity(0.16), lineWidth: 1)
                    )

                VideoFittingPlaybackFrameOverlay(
                    sample: currentSample,
                    checkpoints: overlay.checkpoints,
                    crankCenter: overlay.crankCenter,
                    crankRadius: overlay.crankRadius,
                    videoSize: playback.videoDisplaySize,
                    currentTimeSeconds: playback.currentTimeSeconds,
                    tint: tint
                )
                .allowsHitTesting(false)
                .frame(height: 300)
            }

            if !overlay.checkpoints.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(overlay.checkpoints) { checkpoint in
                            Button {
                                playback.seek(to: checkpoint.timeSeconds)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(checkpoint.checkpoint.displayName) 点")
                                        .font(.caption.weight(.semibold))
                                    Text(
                                        L10n.choose(
                                            simplifiedChinese: "膝 \(checkpoint.kneeAngleText) · 髋 \(checkpoint.hipAngleText)",
                                            english: "Knee \(checkpoint.kneeAngleText) · Hip \(checkpoint.hipAngleText)"
                                        )
                                    )
                                    .font(.caption2)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(checkpointBackground(checkpoint), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .foregroundStyle(checkpointForeground(checkpoint))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            VideoFittingAngleTrendChart(
                overlay: overlay,
                currentTimeSeconds: playback.currentTimeSeconds,
                tint: tint
            )
            .frame(height: 160)
        }
    }

    private var currentSample: VideoFittingPlaybackOverlaySample? {
        overlay.samples.min {
            abs($0.timeSeconds - playback.currentTimeSeconds) < abs($1.timeSeconds - playback.currentTimeSeconds)
        }
    }

    @ViewBuilder
    private func metricBadge(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(tint.opacity(0.08), in: Capsule())
    }

    private func angleText(_ angle: Double?) -> String {
        guard let angle else { return "--" }
        return String(format: "%.0f°", angle)
    }

    private func checkpointBackground(_ checkpoint: VideoFittingPlaybackCheckpointMarker) -> Color {
        let isActive = abs(checkpoint.timeSeconds - playback.currentTimeSeconds) <= 0.18
        return isActive ? tint.opacity(0.18) : Color.white.opacity(0.55)
    }

    private func checkpointForeground(_ checkpoint: VideoFittingPlaybackCheckpointMarker) -> Color {
        abs(checkpoint.timeSeconds - playback.currentTimeSeconds) <= 0.18 ? tint : .primary
    }
}

private struct VideoFittingPlaybackFrameOverlay: View {
    let sample: VideoFittingPlaybackOverlaySample?
    let checkpoints: [VideoFittingPlaybackCheckpointMarker]
    let crankCenter: VideoFittingNormalizedPoint?
    let crankRadius: Double?
    let videoSize: CGSize?
    let currentTimeSeconds: Double
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            let frame = CGRect(origin: .zero, size: proxy.size)
            let imageRect = overlayImageRect(in: frame)
            ZStack(alignment: .topLeading) {
                if let sample, let frameOverlay = frameOverlay(for: sample) {
                    let firstPoint = point(for: frameOverlay.firstPoint, in: imageRect)
                    let jointPoint = point(for: frameOverlay.jointPoint, in: imageRect)
                    let thirdPoint = point(for: frameOverlay.thirdPoint, in: imageRect)
                    let startAngle = angleDegrees(from: jointPoint, to: firstPoint)
                    let endAngle = angleDegrees(from: jointPoint, to: thirdPoint)
                    let sweep = normalizedSweep(start: startAngle, end: endAngle)
                    let arcRadius = min(imageRect.width, imageRect.height) * 0.12

                    Path { path in
                        path.move(to: firstPoint)
                        path.addLine(to: jointPoint)
                        path.addLine(to: thirdPoint)
                    }
                    .stroke(tint, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))

                    if let crankPhase = sample.crankPhaseDegrees {
                        crankPhaseOverlay(
                            phaseDegrees: crankPhase,
                            crankCenter: crankCenter,
                            crankRadius: crankRadius,
                            pedalPoint: sample.thirdPoint,
                            in: imageRect
                        )
                    }

                    Path { path in
                        path.addArc(
                            center: jointPoint,
                            radius: arcRadius,
                            startAngle: .degrees(startAngle),
                            endAngle: .degrees(startAngle + sweep),
                            clockwise: false
                        )
                    }
                    .stroke(tint.opacity(0.88), style: StrokeStyle(lineWidth: 3, lineCap: .round))

                    let points = [frameOverlay.firstPoint, frameOverlay.jointPoint, frameOverlay.thirdPoint]
                    ForEach(points.indices, id: \.self) { index in
                        Circle()
                            .fill(index == 1 ? tint : Color.white)
                            .frame(width: index == 1 ? 14 : 12, height: index == 1 ? 14 : 12)
                            .overlay(Circle().stroke(tint, lineWidth: 2))
                            .position(point(for: points[index], in: imageRect))
                    }

                    if let kneeAngle = sample.kneeAngleDegrees {
                        Text(String(format: "%.0f°", kneeAngle))
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.white.opacity(0.94), in: Capsule())
                            .overlay(Capsule().strokeBorder(tint.opacity(0.18), lineWidth: 1))
                            .position(
                                arcLabelPoint(
                                    center: jointPoint,
                                    startAngle: startAngle,
                                    sweep: sweep,
                                    radius: arcRadius
                                )
                            )
                    }
                }

                HStack(spacing: 6) {
                    ForEach(checkpoints) { checkpoint in
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(checkpoint.checkpoint.displayName) 点")
                                .font(.caption2.weight(.semibold))
                            Text(checkpoint.kneeAngleText)
                                .font(.caption2.monospacedDigit())
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(checkpointChipBackground(checkpoint), in: Capsule())
                        .foregroundStyle(checkpointChipForeground(checkpoint))
                    }
                }
                .padding(10)
            }
        }
    }

    private func frameOverlay(for sample: VideoFittingPlaybackOverlaySample) -> VideoFittingJointAngleFrameOverlaySummary? {
        guard
            sample.allowsOverlayRendering(),
            let firstPoint = sample.firstPoint,
            let jointPoint = sample.jointPoint,
            let thirdPoint = sample.thirdPoint
        else {
            return nil
        }
        return VideoFittingJointAngleFrameOverlaySummary(
            frameTimeSeconds: sample.timeSeconds,
            firstPoint: firstPoint,
            jointPoint: jointPoint,
            thirdPoint: thirdPoint
        )
    }

    private func checkpointChipBackground(_ checkpoint: VideoFittingPlaybackCheckpointMarker) -> Color {
        abs(checkpoint.timeSeconds - currentTimeSeconds) <= 0.18 ? tint.opacity(0.18) : Color.black.opacity(0.50)
    }

    private func checkpointChipForeground(_ checkpoint: VideoFittingPlaybackCheckpointMarker) -> Color {
        abs(checkpoint.timeSeconds - currentTimeSeconds) <= 0.18 ? tint : .white
    }

    private func overlayImageRect(in frame: CGRect) -> CGRect {
        guard let videoSize, videoSize.width > 1, videoSize.height > 1 else {
            return frame
        }
        return aspectFitRect(imageSize: videoSize, in: frame)
    }

    private func point(for normalized: VideoFittingNormalizedPoint, in frame: CGRect) -> CGPoint {
        CGPoint(
            x: frame.minX + frame.width * normalized.x,
            y: frame.minY + frame.height * (1 - normalized.y)
        )
    }

    private func angleDegrees(from origin: CGPoint, to target: CGPoint) -> Double {
        atan2(target.y - origin.y, target.x - origin.x) * 180 / .pi
    }

    private func normalizedSweep(start: Double, end: Double) -> Double {
        var sweep = end - start
        while sweep < 0 { sweep += 360 }
        while sweep > 180 { sweep -= 360 }
        return sweep
    }

    private func arcLabelPoint(center: CGPoint, startAngle: Double, sweep: Double, radius: Double) -> CGPoint {
        let labelAngle = (startAngle + sweep / 2) * .pi / 180
        let offsetRadius = radius + 20
        return CGPoint(
            x: center.x + cos(labelAngle) * offsetRadius,
            y: center.y + sin(labelAngle) * offsetRadius
        )
    }

    @ViewBuilder
    private func crankPhaseOverlay(
        phaseDegrees: Double,
        crankCenter: VideoFittingNormalizedPoint?,
        crankRadius: Double?,
        pedalPoint: VideoFittingNormalizedPoint?,
        in frame: CGRect
    ) -> some View {
        if let geometry = crankGeometry(
            phaseDegrees: phaseDegrees,
            crankCenter: crankCenter,
            crankRadius: crankRadius,
            pedalPoint: pedalPoint,
            in: frame
        ) {
            Path { path in
                path.move(to: geometry.center)
                path.addLine(to: geometry.pedal)
            }
            .stroke(Color.red.opacity(0.88), style: StrokeStyle(lineWidth: 4, lineCap: .round))

            Circle()
                .fill(Color.red.opacity(0.92))
                .frame(width: 8, height: 8)
                .position(geometry.center)
        }
    }

    private func crankGeometry(
        phaseDegrees: Double,
        crankCenter: VideoFittingNormalizedPoint?,
        crankRadius: Double?,
        pedalPoint: VideoFittingNormalizedPoint?,
        in frame: CGRect
    ) -> (center: CGPoint, pedal: CGPoint)? {
        guard let crankCenter else { return nil }

        let center = point(for: crankCenter, in: frame)
        let pedal: CGPoint

        if let crankRadius, crankRadius.isFinite, crankRadius > 0.001 {
            let radians = phaseDegrees * .pi / 180
            let normalizedPedal = VideoFittingNormalizedPoint(
                x: crankCenter.x + sin(radians) * crankRadius,
                y: crankCenter.y - cos(radians) * crankRadius
            )
            pedal = point(for: normalizedPedal, in: frame)
        } else if let pedalPoint {
            pedal = point(for: pedalPoint, in: frame)
        } else {
            return nil
        }

        return (center, pedal)
    }
}

private struct VideoFittingAngleTrendChart: View {
    let overlay: VideoFittingPlaybackOverlaySummary
    let currentTimeSeconds: Double
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L10n.choose(simplifiedChinese: "全视频夹角变化", english: "Full-Clip Angle Trend"))
                    .font(.caption.weight(.semibold))
                Spacer()
                HStack(spacing: 10) {
                    legend(tint: tint, text: L10n.choose(simplifiedChinese: "膝角", english: "Knee"))
                    legend(tint: .cyan, text: L10n.choose(simplifiedChinese: "髋角", english: "Hip"))
                }
            }

            GeometryReader { proxy in
                let frame = CGRect(origin: .zero, size: proxy.size)
                let domain = yDomain
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(tint.opacity(0.04))

                    grid(in: frame)
                        .stroke(Color.secondary.opacity(0.10), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))

                    linePath(
                        values: overlay.samples.compactMap { sample in
                            sample.kneeAngleDegrees.map { (sample.timeSeconds, $0) }
                        },
                        in: frame,
                        domain: domain
                    )
                    .stroke(tint, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))

                    linePath(
                        values: overlay.samples.compactMap { sample in
                            sample.hipAngleDegrees.map { (sample.timeSeconds, $0) }
                        },
                        in: frame,
                        domain: domain
                    )
                    .stroke(Color.cyan, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))

                    Path { path in
                        let x = xPosition(for: currentTimeSeconds, in: frame)
                        path.move(to: CGPoint(x: x, y: frame.minY))
                        path.addLine(to: CGPoint(x: x, y: frame.maxY))
                    }
                    .stroke(Color.primary.opacity(0.18), style: StrokeStyle(lineWidth: 2, dash: [4, 4]))

                    ForEach(overlay.checkpoints) { checkpoint in
                        let x = xPosition(for: checkpoint.timeSeconds, in: frame)
                        VStack(spacing: 4) {
                            Capsule()
                                .fill(abs(checkpoint.timeSeconds - currentTimeSeconds) <= 0.18 ? tint : Color.secondary.opacity(0.35))
                                .frame(width: 2, height: frame.height - 22)
                            Text(checkpoint.checkpoint.displayName)
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        .position(x: x, y: frame.midY + 4)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func legend(tint: Color, text: String) -> some View {
        HStack(spacing: 6) {
            Capsule()
                .fill(tint)
                .frame(width: 16, height: 4)
            Text(text)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var yDomain: ClosedRange<Double> {
        let values = overlay.samples.flatMap { sample in
            [sample.kneeAngleDegrees, sample.hipAngleDegrees].compactMap { $0 }
        }
        let minimum = values.min() ?? 0
        let maximum = values.max() ?? 180
        let padding = max(8, (maximum - minimum) * 0.1)
        return (minimum - padding)...(maximum + padding)
    }

    private func grid(in frame: CGRect) -> Path {
        var path = Path()
        for index in 1..<4 {
            let y = frame.minY + frame.height * CGFloat(index) / 4
            path.move(to: CGPoint(x: frame.minX, y: y))
            path.addLine(to: CGPoint(x: frame.maxX, y: y))
        }
        return path
    }

    private func linePath(values: [(Double, Double)], in frame: CGRect, domain: ClosedRange<Double>) -> Path {
        var path = Path()
        guard let first = values.first else { return path }
        path.move(to: CGPoint(x: xPosition(for: first.0, in: frame), y: yPosition(for: first.1, in: frame, domain: domain)))
        for value in values.dropFirst() {
            path.addLine(to: CGPoint(x: xPosition(for: value.0, in: frame), y: yPosition(for: value.1, in: frame, domain: domain)))
        }
        return path
    }

    private func xPosition(for seconds: Double, in frame: CGRect) -> CGFloat {
        let duration = max(overlay.samples.last?.timeSeconds ?? 0, overlay.checkpoints.map(\.timeSeconds).max() ?? 0, 0.1)
        let progress = max(0, min(1, seconds / duration))
        return frame.minX + frame.width * progress
    }

    private func yPosition(for value: Double, in frame: CGRect, domain: ClosedRange<Double>) -> CGFloat {
        let span = max(domain.upperBound - domain.lowerBound, 0.1)
        let progress = (value - domain.lowerBound) / span
        return frame.maxY - frame.height * progress
    }
}

private final class VideoFittingOverlayPlaybackController: ObservableObject {
    let player: AVPlayer
    @Published var currentTimeSeconds: Double = 0
    @Published var videoDisplaySize: CGSize?

    private var timeObserver: Any?

    init(videoURL: URL) {
        player = AVPlayer(url: videoURL)
        player.actionAtItemEnd = .pause
        videoDisplaySize = Self.loadVideoDisplaySize(from: videoURL)
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.05, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            self?.currentTimeSeconds = max(CMTimeGetSeconds(time), 0)
        }
    }

    deinit {
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
        }
    }

    func seek(to seconds: Double) {
        let time = CMTime(seconds: max(seconds, 0), preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        player.play()
    }

    private static func loadVideoDisplaySize(from url: URL) -> CGSize? {
        let asset = AVURLAsset(url: url)
        guard let track = asset.tracks(withMediaType: .video).first else { return nil }
        let transformed = track.naturalSize.applying(track.preferredTransform)
        return CGSize(width: abs(transformed.width), height: abs(transformed.height))
    }
}

#if os(macOS)
private struct VideoFittingEmbeddedAVPlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .floating
        view.showsFullScreenToggleButton = true
        view.videoGravity = .resizeAspect
        view.player = player
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        nsView.player = player
        nsView.videoGravity = .resizeAspect
    }
}
#else
private struct VideoFittingEmbeddedAVPlayerView: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.videoGravity = .resizeAspect
        return controller
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        uiViewController.player = player
        uiViewController.videoGravity = .resizeAspect
    }
}
#endif

private struct VideoFittingJointAngleVisualCard: View {
    enum DisplayMode {
        case compact
        case expanded
    }

    let summary: VideoFittingJointAngleVisualSummary
    let tint: Color
    let videoURL: URL?
    let displayMode: DisplayMode
    let onExpand: (() -> Void)?
    @State private var frameImage: CGImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(summary.title)
                        .font(.caption.weight(.semibold))
                    Text(summary.subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: 8) {
                    Text("\(Int(summary.angleDegrees.rounded()))°")
                        .font(.title3.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                    if onExpand != nil {
                        Button(action: { onExpand?() }) {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.caption.weight(.semibold))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    }
                }
            }

            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(tint.opacity(0.08))
                if canPreviewFrame {
                    jointAngleFramePreview
                } else {
                    jointAngleIllustration
                        .padding(12)
                }
            }
            .frame(height: previewHeight)
            .task(id: frameOverlayTaskID) {
                await loadFrameIfNeeded()
            }

            Text(summary.detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.white.opacity(0.45), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(tint.opacity(0.14), lineWidth: 1)
        )
    }

    private var previewHeight: CGFloat {
        switch displayMode {
        case .compact:
            return 120
        case .expanded:
            return 420
        }
    }

    private var jointAngleIllustration: some View {
        GeometryReader { proxy in
            let layout = angleLayout(in: proxy.size)
            ZStack {
                Path { path in
                    path.move(to: layout.firstPoint)
                    path.addLine(to: layout.jointPoint)
                    path.addLine(to: layout.thirdPoint)
                }
                .stroke(tint, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))

                Path { path in
                    path.addArc(
                        center: layout.jointPoint,
                        radius: layout.arcRadius,
                        startAngle: .degrees(layout.startAngle),
                        endAngle: .degrees(layout.endAngle),
                        clockwise: false
                    )
                }
                .stroke(tint.opacity(0.55), style: StrokeStyle(lineWidth: 3, lineCap: .round))

                ForEach(layout.anchorPoints.indices, id: \.self) { index in
                    Circle()
                        .fill(index == 1 ? tint : Color.white)
                        .frame(width: index == 1 ? 14 : 12, height: index == 1 ? 14 : 12)
                        .overlay(
                            Circle()
                                .stroke(tint, lineWidth: 2)
                        )
                        .position(layout.anchorPoints[index])
                }

                Text("\(Int(summary.angleDegrees.rounded()))°")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.92), in: Capsule())
                    .overlay(
                        Capsule()
                            .strokeBorder(tint.opacity(0.18), lineWidth: 1)
                    )
                    .position(layout.labelPoint)
            }
        }
    }

    private func jointAngleFrameOverlay(_ overlay: VideoFittingJointAngleFrameOverlaySummary) -> some View {
        GeometryReader { proxy in
            let frame = CGRect(origin: .zero, size: proxy.size)
            let imageRect = fittedImageRect(in: frame)
            let firstPoint = point(for: overlay.firstPoint, in: imageRect)
            let jointPoint = point(for: overlay.jointPoint, in: imageRect)
            let thirdPoint = point(for: overlay.thirdPoint, in: imageRect)
            let startAngle = angleDegrees(from: jointPoint, to: firstPoint)
            let endAngle = angleDegrees(from: jointPoint, to: thirdPoint)
            let sweep = normalizedSweep(start: startAngle, end: endAngle)
            let arcRadius = min(imageRect.width, imageRect.height) * 0.12
            let labelPoint = arcLabelPoint(
                center: jointPoint,
                startAngle: startAngle,
                sweep: sweep,
                radius: arcRadius
            )
            ZStack {
                if let frameImage {
                    Image(decorative: frameImage, scale: 1, orientation: .up)
                        .resizable()
                        .scaledToFit()
                        .frame(width: imageRect.width, height: imageRect.height)
                        .position(x: imageRect.midX, y: imageRect.midY)
                } else {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.55))
                    ProgressView()
                        .controlSize(.small)
                }

                Path { path in
                    path.move(to: firstPoint)
                    path.addLine(to: jointPoint)
                    path.addLine(to: thirdPoint)
                }
                .stroke(tint, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))

                Path { path in
                    path.addArc(
                        center: jointPoint,
                        radius: arcRadius,
                        startAngle: .degrees(startAngle),
                        endAngle: .degrees(startAngle + sweep),
                        clockwise: false
                    )
                }
                .stroke(tint.opacity(0.85), style: StrokeStyle(lineWidth: 3, lineCap: .round))

                let points = [overlay.firstPoint, overlay.jointPoint, overlay.thirdPoint]
                ForEach(points.indices, id: \.self) { index in
                    Circle()
                        .fill(index == 1 ? tint : Color.white)
                        .frame(width: index == 1 ? 14 : 12, height: index == 1 ? 14 : 12)
                        .overlay(Circle().stroke(tint, lineWidth: 2))
                        .position(point(for: points[index], in: imageRect))
                }

                Text("\(Int(summary.angleDegrees.rounded()))°")
                    .font(displayMode == .expanded ? .body.weight(.semibold) : .caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.94), in: Capsule())
                    .overlay(
                        Capsule()
                            .strokeBorder(tint.opacity(0.18), lineWidth: 1)
                    )
                    .position(labelPoint)

                VStack {
                    HStack {
                        Spacer()
                        Text(timecodeText(overlay.frameTimeSeconds))
                            .font(.caption2.monospacedDigit())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.black.opacity(0.55), in: Capsule())
                            .foregroundStyle(.white)
                    }
                    Spacer()
                }
                .padding(10)
            }
        }
    }

    private var jointAngleFramePreview: some View {
        GeometryReader { proxy in
            let frame = CGRect(origin: .zero, size: proxy.size)
            let imageRect = fittedImageRect(in: frame)

            ZStack {
                if let frameImage {
                    Image(decorative: frameImage, scale: 1, orientation: .up)
                        .resizable()
                        .scaledToFit()
                        .frame(width: imageRect.width, height: imageRect.height)
                        .position(x: imageRect.midX, y: imageRect.midY)
                } else {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.55))
                    ProgressView()
                        .controlSize(.small)
                }

                if let overlay = frameOverlay {
                    frameOverlayLayer(overlay, in: imageRect)
                } else {
                    VStack {
                        HStack {
                            Spacer()
                            Text(L10n.choose(simplifiedChinese: "真实关键帧", english: "Real Keyframe"))
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.black.opacity(0.52), in: Capsule())
                                .foregroundStyle(.white)
                        }
                        Spacer()
                        HStack {
                            Text(L10n.choose(simplifiedChinese: "肩点不足，暂未叠加", english: "Shoulder points unavailable"))
                                .font(.caption2.weight(.medium))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.white.opacity(0.92), in: Capsule())
                                .overlay(
                                    Capsule()
                                        .strokeBorder(tint.opacity(0.18), lineWidth: 1)
                                )
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                    }
                    .padding(10)
                }

                if let timeSeconds = summary.frameTimeSeconds {
                    VStack {
                        HStack {
                            Spacer()
                            Text(timecodeText(timeSeconds))
                                .font(.caption2.monospacedDigit())
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.black.opacity(0.55), in: Capsule())
                                .foregroundStyle(.white)
                        }
                        Spacer()
                    }
                    .padding(10)
                }
            }
        }
    }

    @ViewBuilder
    private func frameOverlayLayer(_ overlay: VideoFittingJointAngleFrameOverlaySummary, in imageRect: CGRect) -> some View {
        let firstPoint = point(for: overlay.firstPoint, in: imageRect)
        let jointPoint = point(for: overlay.jointPoint, in: imageRect)
        let thirdPoint = point(for: overlay.thirdPoint, in: imageRect)
        let startAngle = angleDegrees(from: jointPoint, to: firstPoint)
        let endAngle = angleDegrees(from: jointPoint, to: thirdPoint)
        let sweep = normalizedSweep(start: startAngle, end: endAngle)
        let arcRadius = min(imageRect.width, imageRect.height) * 0.12
        let labelPoint = arcLabelPoint(
            center: jointPoint,
            startAngle: startAngle,
            sweep: sweep,
            radius: arcRadius
        )

        Path { path in
            path.move(to: firstPoint)
            path.addLine(to: jointPoint)
            path.addLine(to: thirdPoint)
        }
        .stroke(tint, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))

        if let crankPhase = summary.crankPhaseDegrees {
            crankPhaseOverlay(
                phaseDegrees: crankPhase,
                crankCenter: summary.crankCenter,
                crankRadius: summary.crankRadius,
                pedalPoint: summary.thirdPoint,
                in: imageRect
            )
        }

        Path { path in
            path.addArc(
                center: jointPoint,
                radius: arcRadius,
                startAngle: .degrees(startAngle),
                endAngle: .degrees(startAngle + sweep),
                clockwise: false
            )
        }
        .stroke(tint.opacity(0.85), style: StrokeStyle(lineWidth: 3, lineCap: .round))

        let points = [overlay.firstPoint, overlay.jointPoint, overlay.thirdPoint]
        ForEach(points.indices, id: \.self) { index in
            Circle()
                .fill(index == 1 ? tint : Color.white)
                .frame(width: index == 1 ? 14 : 12, height: index == 1 ? 14 : 12)
                .overlay(Circle().stroke(tint, lineWidth: 2))
                .position(point(for: points[index], in: imageRect))
        }

        Text("\(Int(summary.angleDegrees.rounded()))°")
            .font(displayMode == .expanded ? .body.weight(.semibold) : .caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.white.opacity(0.94), in: Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(tint.opacity(0.18), lineWidth: 1)
            )
            .position(labelPoint)
    }

    private func angleLayout(in size: CGSize) -> JointAngleIllustrationLayout {
        let angle = min(max(summary.angleDegrees, 30), 165)

        switch summary.kind {
        case .knee, .bdcKnee:
            let joint = CGPoint(x: size.width * 0.45, y: size.height * 0.64)
            let first = point(from: joint, length: size.width * 0.24, degrees: 230)
            let third = point(from: joint, length: size.width * 0.24, degrees: 230 + angle)
            return JointAngleIllustrationLayout(
                firstPoint: first,
                jointPoint: joint,
                thirdPoint: third,
                startAngle: 230,
                endAngle: 230 + angle,
                arcRadius: size.width * 0.12,
                labelPoint: CGPoint(x: joint.x + size.width * 0.10, y: joint.y - size.height * 0.18)
            )
        case .hip:
            let joint = CGPoint(x: size.width * 0.42, y: size.height * 0.58)
            let first = point(from: joint, length: size.width * 0.22, degrees: 232)
            let third = point(from: joint, length: size.width * 0.24, degrees: 232 + angle)
            return JointAngleIllustrationLayout(
                firstPoint: first,
                jointPoint: joint,
                thirdPoint: third,
                startAngle: 232,
                endAngle: 232 + angle,
                arcRadius: size.width * 0.11,
                labelPoint: CGPoint(x: joint.x + size.width * 0.12, y: joint.y - size.height * 0.20)
            )
        }
    }

    private func point(from origin: CGPoint, length: Double, degrees: Double) -> CGPoint {
        let radians = degrees * .pi / 180
        return CGPoint(
            x: origin.x + length * cos(radians),
            y: origin.y + length * sin(radians)
        )
    }

    private var frameOverlay: VideoFittingJointAngleFrameOverlaySummary? {
        guard
            let timeSeconds = summary.frameTimeSeconds,
            let firstPoint = summary.firstPoint,
            let jointPoint = summary.jointPoint,
            let thirdPoint = summary.thirdPoint
        else {
            return nil
        }

        return VideoFittingJointAngleFrameOverlaySummary(
            frameTimeSeconds: timeSeconds,
            firstPoint: firstPoint,
            jointPoint: jointPoint,
            thirdPoint: thirdPoint
        )
    }

    private var canPreviewFrame: Bool {
        videoURL != nil && summary.frameTimeSeconds != nil
    }

    private var frameOverlayTaskID: String {
        let frameKey = summary.frameTimeSeconds.map { String(format: "%.3f", $0) } ?? "none"
        return "\(summary.kind.rawValue)-\(frameKey)-\(videoURL?.absoluteString ?? "no-video")"
    }

    @MainActor
    private func loadFrameIfNeeded() async {
        guard let videoURL, let timeSeconds = summary.frameTimeSeconds else {
            frameImage = nil
            return
        }

        do {
            let asset = AVURLAsset(url: videoURL)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 720, height: 720)
            generator.requestedTimeToleranceBefore = CMTime(seconds: 0.04, preferredTimescale: 600)
            generator.requestedTimeToleranceAfter = CMTime(seconds: 0.04, preferredTimescale: 600)
            let time = CMTime(seconds: max(timeSeconds, 0), preferredTimescale: 600)
            frameImage = try generator.copyCGImage(at: time, actualTime: nil)
        } catch {
            frameImage = nil
        }
    }

    private func fittedImageRect(in frame: CGRect) -> CGRect {
        guard let frameImage else { return frame }
        return aspectFitRect(
            imageSize: CGSize(width: frameImage.width, height: frameImage.height),
            in: frame
        )
    }

    private func point(for normalized: VideoFittingNormalizedPoint, in frame: CGRect) -> CGPoint {
        CGPoint(
            x: frame.minX + frame.width * normalized.x,
            y: frame.minY + frame.height * (1 - normalized.y)
        )
    }

    private func angleDegrees(from origin: CGPoint, to target: CGPoint) -> Double {
        atan2(target.y - origin.y, target.x - origin.x) * 180 / .pi
    }

    private func normalizedSweep(start: Double, end: Double) -> Double {
        var sweep = end - start
        while sweep < 0 { sweep += 360 }
        while sweep > 180 { sweep -= 360 }
        return sweep
    }

    private func arcLabelPoint(center: CGPoint, startAngle: Double, sweep: Double, radius: Double) -> CGPoint {
        let labelAngle = (startAngle + sweep / 2) * .pi / 180
        let offsetRadius = radius + 20
        return CGPoint(
            x: center.x + cos(labelAngle) * offsetRadius,
            y: center.y + sin(labelAngle) * offsetRadius
        )
    }

    @ViewBuilder
    private func crankPhaseOverlay(
        phaseDegrees: Double,
        crankCenter: VideoFittingNormalizedPoint?,
        crankRadius: Double?,
        pedalPoint: VideoFittingNormalizedPoint?,
        in frame: CGRect
    ) -> some View {
        if let geometry = crankGeometry(
            phaseDegrees: phaseDegrees,
            crankCenter: crankCenter,
            crankRadius: crankRadius,
            pedalPoint: pedalPoint,
            in: frame
        ) {
            Path { path in
                path.move(to: geometry.center)
                path.addLine(to: geometry.pedal)
            }
            .stroke(Color.red.opacity(0.88), style: StrokeStyle(lineWidth: displayMode == .expanded ? 5 : 4, lineCap: .round))

            Circle()
                .fill(Color.red.opacity(0.92))
                .frame(width: displayMode == .expanded ? 9 : 8, height: displayMode == .expanded ? 9 : 8)
                .position(geometry.center)
        }
    }

    private func crankGeometry(
        phaseDegrees: Double,
        crankCenter: VideoFittingNormalizedPoint?,
        crankRadius: Double?,
        pedalPoint: VideoFittingNormalizedPoint?,
        in frame: CGRect
    ) -> (center: CGPoint, pedal: CGPoint)? {
        guard let crankCenter else { return nil }

        let center = point(for: crankCenter, in: frame)
        let pedal: CGPoint

        if let crankRadius, crankRadius.isFinite, crankRadius > 0.001 {
            let radians = phaseDegrees * .pi / 180
            let normalizedPedal = VideoFittingNormalizedPoint(
                x: crankCenter.x + sin(radians) * crankRadius,
                y: crankCenter.y - cos(radians) * crankRadius
            )
            pedal = point(for: normalizedPedal, in: frame)
        } else if let pedalPoint {
            pedal = point(for: pedalPoint, in: frame)
        } else {
            return nil
        }

        return (center, pedal)
    }

    private func timecodeText(_ seconds: Double) -> String {
        String(format: "T %.1fs", seconds)
    }
}

private struct VideoFittingCheckpointVisualCard: View {
    enum DisplayMode {
        case compact
        case expanded
    }

    let summary: VideoFittingCheckpointVisualSummary
    let tint: Color
    let videoURL: URL?
    let displayMode: DisplayMode
    let onExpand: (() -> Void)?
    @State private var frameImage: CGImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(summary.checkpoint.displayName) 点")
                        .font(.caption.weight(.semibold))
                    Text(String(format: "T %.1fs · P %.0f°", summary.frameTimeSeconds, summary.phaseDegrees))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if onExpand != nil {
                    Button(action: { onExpand?() }) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }

            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(tint.opacity(0.08))
                checkpointFrameOverlay
            }
            .frame(height: previewHeight)
            .task(id: frameTaskID) {
                await loadFrame()
            }

            HStack(spacing: 10) {
                labelChip(title: L10n.choose(simplifiedChinese: "膝角", english: "Knee"), value: summary.kneeAngleText)
                labelChip(title: L10n.choose(simplifiedChinese: "髋角", english: "Hip"), value: summary.hipAngleText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.white.opacity(0.45), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(tint.opacity(0.14), lineWidth: 1)
        )
    }

    private var previewHeight: CGFloat {
        switch displayMode {
        case .compact:
            return 120
        case .expanded:
            return 420
        }
    }

    private var checkpointFrameOverlay: some View {
        GeometryReader { proxy in
            let frame = CGRect(origin: .zero, size: proxy.size)
            let imageRect = fittedImageRect(in: frame)
            ZStack {
                if let frameImage {
                    Image(decorative: frameImage, scale: 1, orientation: .up)
                        .resizable()
                        .scaledToFit()
                        .frame(width: imageRect.width, height: imageRect.height)
                        .position(x: imageRect.midX, y: imageRect.midY)
                } else {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.55))
                    ProgressView()
                        .controlSize(.small)
                }

                if let overlay = overlaySummary {
                    let firstPoint = point(for: overlay.firstPoint, in: imageRect)
                    let jointPoint = point(for: overlay.jointPoint, in: imageRect)
                    let thirdPoint = point(for: overlay.thirdPoint, in: imageRect)
                    let startAngle = angleDegrees(from: jointPoint, to: firstPoint)
                    let endAngle = angleDegrees(from: jointPoint, to: thirdPoint)
                    let sweep = normalizedSweep(start: startAngle, end: endAngle)
                    let arcRadius = min(imageRect.width, imageRect.height) * 0.12
                    let angleText = summary.kneeAngleText == "--" ? nil : summary.kneeAngleText
                    Path { path in
                        path.move(to: firstPoint)
                        path.addLine(to: jointPoint)
                        path.addLine(to: thirdPoint)
                    }
                    .stroke(tint, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))

                    crankPhaseOverlay(
                        phaseDegrees: summary.phaseDegrees,
                        crankCenter: summary.crankCenter,
                        crankRadius: summary.crankRadius,
                        pedalPoint: summary.thirdPoint,
                        in: imageRect
                    )

                    Path { path in
                        path.addArc(
                            center: jointPoint,
                            radius: arcRadius,
                            startAngle: .degrees(startAngle),
                            endAngle: .degrees(startAngle + sweep),
                            clockwise: false
                        )
                    }
                    .stroke(tint.opacity(0.85), style: StrokeStyle(lineWidth: 3, lineCap: .round))

                    let points = [overlay.firstPoint, overlay.jointPoint, overlay.thirdPoint]
                    ForEach(points.indices, id: \.self) { index in
                        Circle()
                            .fill(index == 1 ? tint : Color.white)
                            .frame(width: index == 1 ? 14 : 12, height: index == 1 ? 14 : 12)
                            .overlay(Circle().stroke(tint, lineWidth: 2))
                            .position(point(for: points[index], in: imageRect))
                    }

                    if let angleText {
                        Text(angleText)
                            .font(displayMode == .expanded ? .body.weight(.semibold) : .caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.white.opacity(0.94), in: Capsule())
                            .overlay(
                                Capsule()
                                    .strokeBorder(tint.opacity(0.18), lineWidth: 1)
                            )
                            .position(
                                arcLabelPoint(
                                    center: jointPoint,
                                    startAngle: startAngle,
                                    sweep: sweep,
                                    radius: arcRadius
                                )
                            )
                    }
                }
            }
        }
    }

    private func labelChip(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(tint.opacity(0.08), in: Capsule())
    }

    private var overlaySummary: VideoFittingJointAngleFrameOverlaySummary? {
        guard
            let firstPoint = summary.firstPoint,
            let jointPoint = summary.jointPoint,
            let thirdPoint = summary.thirdPoint
        else {
            return nil
        }
        return VideoFittingJointAngleFrameOverlaySummary(
            frameTimeSeconds: summary.frameTimeSeconds,
            firstPoint: firstPoint,
            jointPoint: jointPoint,
            thirdPoint: thirdPoint
        )
    }

    private var frameTaskID: String {
        "\(summary.id)-\(videoURL?.absoluteString ?? "no-video")"
    }

    @MainActor
    private func loadFrame() async {
        guard let videoURL else {
            frameImage = nil
            return
        }

        do {
            let asset = AVURLAsset(url: videoURL)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 720, height: 720)
            generator.requestedTimeToleranceBefore = CMTime(seconds: 0.04, preferredTimescale: 600)
            generator.requestedTimeToleranceAfter = CMTime(seconds: 0.04, preferredTimescale: 600)
            let time = CMTime(seconds: max(summary.frameTimeSeconds, 0), preferredTimescale: 600)
            frameImage = try generator.copyCGImage(at: time, actualTime: nil)
        } catch {
            frameImage = nil
        }
    }

    private func fittedImageRect(in frame: CGRect) -> CGRect {
        guard let frameImage else { return frame }
        return aspectFitRect(
            imageSize: CGSize(width: frameImage.width, height: frameImage.height),
            in: frame
        )
    }

    private func point(for normalized: VideoFittingNormalizedPoint, in frame: CGRect) -> CGPoint {
        CGPoint(
            x: frame.minX + frame.width * normalized.x,
            y: frame.minY + frame.height * (1 - normalized.y)
        )
    }

    private func angleDegrees(from origin: CGPoint, to target: CGPoint) -> Double {
        atan2(target.y - origin.y, target.x - origin.x) * 180 / .pi
    }

    private func normalizedSweep(start: Double, end: Double) -> Double {
        var sweep = end - start
        while sweep < 0 { sweep += 360 }
        while sweep > 180 { sweep -= 360 }
        return sweep
    }

    private func arcLabelPoint(center: CGPoint, startAngle: Double, sweep: Double, radius: Double) -> CGPoint {
        let labelAngle = (startAngle + sweep / 2) * .pi / 180
        let offsetRadius = radius + 20
        return CGPoint(
            x: center.x + cos(labelAngle) * offsetRadius,
            y: center.y + sin(labelAngle) * offsetRadius
        )
    }

    @ViewBuilder
    private func crankPhaseOverlay(
        phaseDegrees: Double,
        crankCenter: VideoFittingNormalizedPoint?,
        crankRadius: Double?,
        pedalPoint: VideoFittingNormalizedPoint?,
        in frame: CGRect
    ) -> some View {
        if let geometry = crankGeometry(
            phaseDegrees: phaseDegrees,
            crankCenter: crankCenter,
            crankRadius: crankRadius,
            pedalPoint: pedalPoint,
            in: frame
        ) {
            Path { path in
                path.move(to: geometry.center)
                path.addLine(to: geometry.pedal)
            }
            .stroke(Color.red.opacity(0.88), style: StrokeStyle(lineWidth: displayMode == .expanded ? 5 : 4, lineCap: .round))

            Circle()
                .fill(Color.red.opacity(0.92))
                .frame(width: displayMode == .expanded ? 9 : 8, height: displayMode == .expanded ? 9 : 8)
                .position(geometry.center)
        }
    }

    private func crankGeometry(
        phaseDegrees: Double,
        crankCenter: VideoFittingNormalizedPoint?,
        crankRadius: Double?,
        pedalPoint: VideoFittingNormalizedPoint?,
        in frame: CGRect
    ) -> (center: CGPoint, pedal: CGPoint)? {
        guard let crankCenter else { return nil }

        let center = point(for: crankCenter, in: frame)
        let pedal: CGPoint

        if let crankRadius, crankRadius.isFinite, crankRadius > 0.001 {
            let radians = phaseDegrees * .pi / 180
            let normalizedPedal = VideoFittingNormalizedPoint(
                x: crankCenter.x + sin(radians) * crankRadius,
                y: crankCenter.y - cos(radians) * crankRadius
            )
            pedal = point(for: normalizedPedal, in: frame)
        } else if let pedalPoint {
            pedal = point(for: pedalPoint, in: frame)
        } else {
            return nil
        }

        return (center, pedal)
    }
}

private struct JointAngleIllustrationLayout {
    let firstPoint: CGPoint
    let jointPoint: CGPoint
    let thirdPoint: CGPoint
    let startAngle: Double
    let endAngle: Double
    let arcRadius: Double
    let labelPoint: CGPoint

    var anchorPoints: [CGPoint] {
        [firstPoint, jointPoint, thirdPoint]
    }
}

private struct VideoFittingJointAngleFrameOverlaySummary {
    let frameTimeSeconds: Double
    let firstPoint: VideoFittingNormalizedPoint
    let jointPoint: VideoFittingNormalizedPoint
    let thirdPoint: VideoFittingNormalizedPoint
}

private func aspectFitRect(imageSize: CGSize, in bounds: CGRect) -> CGRect {
    guard imageSize.width > 0, imageSize.height > 0, bounds.width > 0, bounds.height > 0 else {
        return bounds
    }
    let scale = min(bounds.width / imageSize.width, bounds.height / imageSize.height)
    let fittedSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
    return CGRect(
        x: bounds.midX - fittedSize.width / 2,
        y: bounds.midY - fittedSize.height / 2,
        width: fittedSize.width,
        height: fittedSize.height
    )
}

private enum VideoFittingExpandedVisual: Identifiable {
    case joint(summary: VideoFittingJointAngleVisualSummary, videoURL: URL?, tint: Color)
    case checkpoint(summary: VideoFittingCheckpointVisualSummary, videoURL: URL?, tint: Color)

    var id: String {
        switch self {
        case let .joint(summary, _, _):
            return "joint-\(summary.id)"
        case let .checkpoint(summary, _, _):
            return "checkpoint-\(summary.id)"
        }
    }
}

private struct VideoFittingExpandedVisualSheet: View {
    let visual: VideoFittingExpandedVisual
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(title)
                    .font(.title3.weight(.bold))
                Spacer()
                Button(L10n.choose(simplifiedChinese: "关闭", english: "Close")) {
                    dismiss()
                }
                .buttonStyle(.bordered)
            }

            switch visual {
            case let .joint(summary, videoURL, tint):
                VideoFittingJointAngleVisualCard(
                    summary: summary,
                    tint: tint,
                    videoURL: videoURL,
                    displayMode: .expanded,
                    onExpand: nil
                )
                .frame(maxWidth: .infinity, alignment: .top)
            case let .checkpoint(summary, videoURL, tint):
                VideoFittingCheckpointVisualCard(
                    summary: summary,
                    tint: tint,
                    videoURL: videoURL,
                    displayMode: .expanded,
                    onExpand: nil
                )
                .frame(maxWidth: .infinity, alignment: .top)
            }

            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(minWidth: 860, minHeight: 620)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var title: String {
        switch visual {
        case let .joint(summary, _, _):
            return summary.title
        case let .checkpoint(summary, _, _):
            return L10n.choose(
                simplifiedChinese: "\(summary.checkpoint.displayName) 点关键帧",
                english: "\(summary.checkpoint.displayName) checkpoint frame"
            )
        }
    }
}

struct VideoFittingFailureRecoveryPanel: View {
    let summary: VideoFittingFailureRecoverySummary
    let isRetrying: Bool
    let retryAction: () -> Void

    private let categoryColumns = [
        GridItem(.adaptive(minimum: 220), spacing: 10, alignment: .top)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(summary.title)
                        .font(.subheadline.weight(.semibold))
                    Text(summary.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(
                    isRetrying
                        ? L10n.choose(simplifiedChinese: "重试中...", english: "Retrying...")
                        : summary.retryTitle
                ) {
                    retryAction()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isRetrying)
            }

            if !summary.recommendedRetakeViews.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.choose(simplifiedChinese: "推荐重录机位", english: "Recommended Retake Views"))
                        .font(.caption.weight(.semibold))
                    HStack(spacing: 8) {
                        ForEach(summary.recommendedRetakeViews) { view in
                            Text(view.displayName)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.orange.opacity(0.12), in: Capsule())
                                .foregroundStyle(.orange)
                        }
                    }
                }
            }

            LazyVGrid(columns: categoryColumns, alignment: .leading, spacing: 10) {
                ForEach(summary.categories) { category in
                    let affectedViewsText = category.affectedViews.map { $0.displayName }.joined(separator: " / ")
                    VStack(alignment: .leading, spacing: 6) {
                        Text(category.category.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.orange)
                        Text(category.category.detail)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(
                            L10n.choose(
                                simplifiedChinese: "涉及机位：\(affectedViewsText)",
                                english: "Affected views: \(affectedViewsText)"
                            )
                        )
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        ForEach(category.reasons, id: \.self) { reason in
                            Text("• \(reason)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.choose(simplifiedChinese: "修复建议", english: "Fix Suggestions"))
                    .font(.caption.weight(.semibold))
                ForEach(summary.fixSuggestions, id: \.self) { tip in
                    Text("• \(tip)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Text(summary.retryDetail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.2), lineWidth: 1)
        )
    }
}
