@preconcurrency import AVFoundation
import CoreImage
import CoreGraphics
import CoreText
import Foundation

enum VideoFittingReportExportError: LocalizedError {
    case noResult
    case cannotCreatePDF
    case cannotCreateExportSession
    case exportFailed(String)

    var errorDescription: String? {
        switch self {
        case .noResult:
            return L10n.choose(
                simplifiedChinese: "没有可导出的分析结果。",
                english: "No analysis result available for export."
            )
        case .cannotCreatePDF:
            return L10n.choose(
                simplifiedChinese: "无法创建 PDF 导出。",
                english: "Unable to create PDF output."
            )
        case .cannotCreateExportSession:
            return L10n.choose(
                simplifiedChinese: "无法创建视频导出会话。",
                english: "Unable to create video export session."
            )
        case .exportFailed(let reason):
            return L10n.choose(
                simplifiedChinese: "导出失败：\(reason)",
                english: "Export failed: \(reason)"
            )
        }
    }
}

struct VideoFittingReportExporter {
    private final class ExportSessionBox: @unchecked Sendable {
        let session: AVAssetExportSession
        init(_ session: AVAssetExportSession) {
            self.session = session
        }
    }

    func exportPDF(
        resultsByView: [CyclingCameraView: VideoJointAngleAnalysisResult],
        preferredModel: VideoPoseEstimationModel,
        outputURL: URL
    ) throws {
        guard !resultsByView.isEmpty else {
            throw VideoFittingReportExportError.noResult
        }

        let fm = FileManager.default
        if fm.fileExists(atPath: outputURL.path) {
            try fm.removeItem(at: outputURL)
        }

        var mediaBox = CGRect(x: 0, y: 0, width: 595, height: 842)
        guard let context = CGContext(outputURL as CFURL, mediaBox: &mediaBox, nil) else {
            throw VideoFittingReportExportError.cannotCreatePDF
        }

        context.beginPDFPage(nil)
        var currentY: CGFloat = mediaBox.height - 42
        let marginX: CGFloat = 38
        let contentBottom: CGFloat = 40

        func writeLine(_ text: String, size: CGFloat = 11, bold: Bool = false, color: CGColor = CGColor(gray: 0.12, alpha: 1.0), extraSpacing: CGFloat = 2) {
            let lineHeight = size + extraSpacing
            if currentY - lineHeight < contentBottom {
                context.endPDFPage()
                context.beginPDFPage(nil)
                currentY = mediaBox.height - 42
            }

            let fontName = bold ? "Helvetica-Bold" : "Helvetica"
            let font = CTFontCreateWithName(fontName as CFString, size, nil)
            let attrs: [NSAttributedString.Key: Any] = [
                NSAttributedString.Key(rawValue: kCTFontAttributeName as String): font,
                NSAttributedString.Key(rawValue: kCTForegroundColorAttributeName as String): color
            ]
            let attr = NSAttributedString(string: text, attributes: attrs)
            let line = CTLineCreateWithAttributedString(attr)
            context.textPosition = CGPoint(x: marginX, y: currentY)
            CTLineDraw(line, context)
            currentY -= lineHeight
        }

        writeLine("Fricu Video Fitting Report", size: 20, bold: true, extraSpacing: 10)
        writeLine("Generated: \(ISO8601DateFormatter().string(from: Date()))", size: 10, color: CGColor(gray: 0.35, alpha: 1.0))
        writeLine("Pose model preference: \(preferredModel.displayName)", size: 10, color: CGColor(gray: 0.35, alpha: 1.0), extraSpacing: 12)

        let orderedViews: [CyclingCameraView] = [.front, .side, .rear]
        for view in orderedViews {
            guard let result = resultsByView[view] else { continue }
            writeLine(view.displayName, size: 14, bold: true, extraSpacing: 6)
            writeLine("Resolved view: \(result.resolvedView.displayName)")
            writeLine("Frames: \(result.analyzedFrameCount)/\(result.targetFrameCount)  Duration: \(String(format: "%.2f", result.durationSeconds))s")

            if let knee = result.kneeStats {
                writeLine("Knee angle min/avg/max: \(String(format: "%.1f", knee.min)) / \(String(format: "%.1f", knee.mean)) / \(String(format: "%.1f", knee.max)) deg")
            }
            if let hip = result.hipStats {
                writeLine("Hip angle min/avg/max: \(String(format: "%.1f", hip.min)) / \(String(format: "%.1f", hip.mean)) / \(String(format: "%.1f", hip.max)) deg")
            }
            if let cadence = result.cadenceSummary {
                writeLine("Cadence avg/min/max: \(String(format: "%.1f", cadence.meanCadenceRPM)) / \(String(format: "%.1f", cadence.minCadenceRPM)) / \(String(format: "%.1f", cadence.maxCadenceRPM)) rpm")
            }
            if let long = result.longDurationStability {
                writeLine(
                    "Long stability window: \(String(format: "%.0f", long.analyzedDurationSeconds))s, cycles=\(long.cycleCount)"
                )
                if let bdc = long.meanBDCKneeAngleDeg, let bdcDrift = long.bdcKneeDriftDegPerMin {
                    writeLine("BDC knee mean/drift: \(String(format: "%.1f", bdc)) deg / \(String(format: "%+.2f", bdcDrift)) deg/min")
                }
                if let phaseError = long.meanBDCPhaseErrorDeg, let phaseDrift = long.phaseDriftDegPerMin {
                    writeLine("BDC phase error/drift: \(String(format: "%.1f", phaseError)) deg / \(String(format: "%+.2f", phaseDrift)) deg/min")
                }
                if
                    let earlyKnee = long.earlyKneeAngleDeg,
                    let lateKnee = long.lateKneeAngleDeg,
                    let earlyHip = long.earlyHipAngleDeg,
                    let lateHip = long.lateHipAngleDeg
                {
                    writeLine(
                        "Fatigue posture delta (knee/hip): \(String(format: "%+.1f", lateKnee - earlyKnee)) / \(String(format: "%+.1f", lateHip - earlyHip)) deg"
                    )
                }
            }
            if let trajectory = result.frontTrajectory {
                writeLine("Front track width (knee/ankle/toe): \(String(format: "%.3f", trajectory.kneeTrajectorySpanNorm)) / \(String(format: "%.3f", trajectory.ankleTrajectorySpanNorm)) / \(trajectory.toeTrajectorySpanNorm.map { String(format: "%.3f", $0) } ?? "--")")
                writeLine("Knee-over-ankle in range: \(String(format: "%.0f%%", trajectory.kneeOverAnkleInRangeRatio * 100.0))")
            }
            if let frontAssessment = result.frontAutoAssessment {
                writeLine("Front auto assessment: \(riskLevelText(frontAssessment.riskLevel)) (\(String(format: "%.0f", frontAssessment.riskScore)))")
                if !frontAssessment.flags.isEmpty {
                    writeLine("Front flags: \(frontAssessment.flags.joined(separator: ", "))", size: 10, color: CGColor(gray: 0.30, alpha: 1.0))
                }
            }
            if let pelvic = result.rearPelvic {
                writeLine("Pelvic tilt mean/max: \(String(format: "%.1f", pelvic.meanPelvicTiltDeg)) / \(String(format: "%.1f", pelvic.maxPelvicTiltDeg)) deg")
            }
            if let stability = result.rearStability {
                writeLine("CoM shift mean/max/bias: \(String(format: "%.3f", stability.meanCenterShiftNorm)) / \(String(format: "%.3f", stability.maxCenterShiftNorm)) / \(String(format: "%.3f", stability.lateralBias))")
            }
            if let coordination = result.rearCoordination {
                writeLine("Shun-guai suspected: \(coordination.isShunGuaiSuspected ? "YES" : "NO"), corr=\(String(format: "%.2f", coordination.kneeLateralCorrelation))")
            }
            if let rearAssessment = result.rearAutoAssessment {
                writeLine("Rear auto assessment: \(riskLevelText(rearAssessment.riskLevel)) (\(String(format: "%.0f", rearAssessment.riskScore)))")
                if !rearAssessment.flags.isEmpty {
                    writeLine("Rear flags: \(rearAssessment.flags.joined(separator: ", "))", size: 10, color: CGColor(gray: 0.30, alpha: 1.0))
                }
            }

            if !result.adjustmentPlan.isEmpty {
                writeLine("AI adjustment sequence:", bold: true)
                for step in result.adjustmentPlan.prefix(4) {
                    writeLine(
                        "#\(step.priority) [\(String(format: "%.0f", step.impactScore))] \(step.title)",
                        size: 10,
                        color: CGColor(gray: 0.12, alpha: 1.0)
                    )
                    writeLine("- Limit: \(step.maxAdjustmentPerStep)", size: 9, color: CGColor(gray: 0.30, alpha: 1.0))
                    writeLine("- Retest: \(step.retestCondition)", size: 9, color: CGColor(gray: 0.30, alpha: 1.0))
                }
            }

            if !result.fittingHints.isEmpty {
                writeLine("Hints:", bold: true)
                for hint in result.fittingHints.prefix(6) {
                    writeLine("- \(hint)", size: 10, color: CGColor(gray: 0.28, alpha: 1.0))
                }
            }
            currentY -= 8
        }

        context.endPDFPage()
        context.closePDF()
    }

    private func riskLevelText(_ level: FittingRiskLevel) -> String {
        switch level {
        case .low:
            return "LOW"
        case .moderate:
            return "MODERATE"
        case .high:
            return "HIGH"
        }
    }

    func exportAnnotatedClip(
        sourceURL: URL,
        analysisResult: VideoJointAngleAnalysisResult,
        startSeconds: Double,
        durationSeconds: Double,
        outputURL: URL
    ) async throws -> URL {
        let fm = FileManager.default
        if fm.fileExists(atPath: outputURL.path) {
            try fm.removeItem(at: outputURL)
        }

        let asset = AVURLAsset(url: sourceURL)
        let rawDuration = CMTimeGetSeconds(try await asset.load(.duration))
        guard rawDuration.isFinite, rawDuration > 0 else {
            throw VideoFittingReportExportError.exportFailed("Invalid source duration.")
        }

        let clippedDuration = min(max(0.8, durationSeconds), rawDuration)
        let clippedStart = min(max(0, startSeconds), max(0, rawDuration - clippedDuration))
        let start = CMTime(seconds: clippedStart, preferredTimescale: 600)
        let duration = CMTime(seconds: clippedDuration, preferredTimescale: 600)

        let sourceVideoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let sourceVideoTrack = sourceVideoTracks.first else {
            throw VideoFittingReportExportError.exportFailed("No video track.")
        }
        let sourceAudioTracks = try await asset.loadTracks(withMediaType: .audio)
        let sourceNominalFPS = max(1.0, Double(try await sourceVideoTrack.load(.nominalFrameRate)))
        let sourceNaturalSize = try await sourceVideoTrack.load(.naturalSize)

        let composition = AVMutableComposition()
        guard let compositionVideoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw VideoFittingReportExportError.exportFailed("Cannot create composition video track.")
        }
        try compositionVideoTrack.insertTimeRange(
            CMTimeRange(start: start, duration: duration),
            of: sourceVideoTrack,
            at: .zero
        )
        compositionVideoTrack.preferredTransform = try await sourceVideoTrack.load(.preferredTransform)

        if let sourceAudioTrack = sourceAudioTracks.first,
           let compositionAudioTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
           ) {
            try? compositionAudioTrack.insertTimeRange(
                CMTimeRange(start: start, duration: duration),
                of: sourceAudioTrack,
                at: .zero
            )
        }

        guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            throw VideoFittingReportExportError.cannotCreateExportSession
        }

        let videoComposition = AVMutableVideoComposition(asset: composition, applyingCIFiltersWithHandler: { request in
            let sourceImage = request.sourceImage
            let localTime = CMTimeGetSeconds(request.compositionTime)
            let sampleTime = clippedStart + max(0, localTime)
            let sample = nearestSample(at: sampleTime, samples: analysisResult.samples)
            let annotated = annotateFrame(
                sourceImage: sourceImage,
                sample: sample,
                resolvedView: analysisResult.resolvedView,
                sampleTime: sampleTime
            )
            request.finish(with: annotated, context: nil)
        })
        videoComposition.frameDuration = CMTime(seconds: 1.0 / sourceNominalFPS, preferredTimescale: 600)
        videoComposition.renderSize = videoComposition.renderSize == .zero
            ? sourceNaturalSize
            : videoComposition.renderSize

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mov
        exportSession.videoComposition = videoComposition
        exportSession.shouldOptimizeForNetworkUse = true

        let boxed = ExportSessionBox(exportSession)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            boxed.session.exportAsynchronously {
                switch boxed.session.status {
                case .completed:
                    continuation.resume()
                case .failed:
                    continuation.resume(throwing: VideoFittingReportExportError.exportFailed(boxed.session.error?.localizedDescription ?? "Unknown error"))
                case .cancelled:
                    continuation.resume(throwing: VideoFittingReportExportError.exportFailed("Cancelled"))
                default:
                    continuation.resume(throwing: VideoFittingReportExportError.exportFailed("Unexpected status"))
                }
            }
        }
        return outputURL
    }

    func exportClip(
        sourceURL: URL,
        startSeconds: Double,
        durationSeconds: Double,
        outputURL: URL
    ) async throws -> URL {
        let fm = FileManager.default
        if fm.fileExists(atPath: outputURL.path) {
            try fm.removeItem(at: outputURL)
        }

        let asset = AVURLAsset(url: sourceURL)
        let rawDuration = CMTimeGetSeconds(try await asset.load(.duration))
        guard rawDuration.isFinite, rawDuration > 0 else {
            throw VideoFittingReportExportError.exportFailed("Invalid source duration.")
        }

        let clippedDuration = min(max(0.8, durationSeconds), rawDuration)
        let clippedStart = min(max(0, startSeconds), max(0, rawDuration - clippedDuration))
        let start = CMTime(seconds: clippedStart, preferredTimescale: 600)
        let duration = CMTime(seconds: clippedDuration, preferredTimescale: 600)

        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
            throw VideoFittingReportExportError.cannotCreateExportSession
        }
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mov
        exportSession.timeRange = CMTimeRange(start: start, duration: duration)
        exportSession.shouldOptimizeForNetworkUse = true

        let boxed = ExportSessionBox(exportSession)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            boxed.session.exportAsynchronously {
                switch boxed.session.status {
                case .completed:
                    continuation.resume()
                case .failed:
                    continuation.resume(throwing: VideoFittingReportExportError.exportFailed(boxed.session.error?.localizedDescription ?? "Unknown error"))
                case .cancelled:
                    continuation.resume(throwing: VideoFittingReportExportError.exportFailed("Cancelled"))
                default:
                    continuation.resume(throwing: VideoFittingReportExportError.exportFailed("Unexpected status"))
                }
            }
        }
        return outputURL
    }

    private func annotateFrame(
        sourceImage: CIImage,
        sample: VideoJointAngleSample?,
        resolvedView: CyclingCameraView,
        sampleTime: Double
    ) -> CIImage {
        guard let sample else { return sourceImage }
        let extent = sourceImage.extent.integral
        guard extent.width > 2, extent.height > 2 else { return sourceImage }
        guard
            let overlayCG = makeOverlayCGImage(
                width: Int(extent.width),
                height: Int(extent.height),
                sample: sample,
                resolvedView: resolvedView,
                sampleTime: sampleTime
            )
        else {
            return sourceImage
        }

        let overlay = CIImage(cgImage: overlayCG)
            .transformed(by: CGAffineTransform(translationX: extent.origin.x, y: extent.origin.y))
        return overlay.composited(over: sourceImage)
    }

    private func makeOverlayCGImage(
        width: Int,
        height: Int,
        sample: VideoJointAngleSample,
        resolvedView: CyclingCameraView,
        sampleTime: Double
    ) -> CGImage? {
        guard
            let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else {
            return nil
        }

        let leftColor = CGColor(red: 0.15, green: 0.88, blue: 0.55, alpha: 0.92)
        let rightColor = CGColor(red: 0.99, green: 0.62, blue: 0.16, alpha: 0.92)
        let textBg = CGColor(red: 0, green: 0, blue: 0, alpha: 0.45)
        let textFg = CGColor(red: 1, green: 1, blue: 1, alpha: 0.95)

        let mapPoint: (PoseJointPoint?) -> CGPoint? = { point in
            guard let point else { return nil }
            return CGPoint(
                x: point.x * Double(width),
                y: point.y * Double(height)
            )
        }

        let leftChain = [mapPoint(sample.leftHip), mapPoint(sample.leftKnee), mapPoint(sample.leftAnkle), mapPoint(sample.leftToe)].compactMap { $0 }
        let rightChain = [mapPoint(sample.rightHip), mapPoint(sample.rightKnee), mapPoint(sample.rightAnkle), mapPoint(sample.rightToe)].compactMap { $0 }

        drawChain(leftChain, color: leftColor, context: context)
        drawChain(rightChain, color: rightColor, context: context)
        drawPoints(leftChain, color: leftColor, context: context)
        drawPoints(rightChain, color: rightColor, context: context)

        let leftKnee = angleDegrees(
            a: mapPoint(sample.leftHip),
            b: mapPoint(sample.leftKnee),
            c: mapPoint(sample.leftAnkle)
        )
        let rightKnee = angleDegrees(
            a: mapPoint(sample.rightHip),
            b: mapPoint(sample.rightKnee),
            c: mapPoint(sample.rightAnkle)
        )

        var lines: [String] = []
        lines.append("T \(String(format: "%.2f", sampleTime))s · \(resolvedView.displayName)")
        if let knee = sample.kneeAngleDeg {
            lines.append("Knee \(String(format: "%.1f", knee))°")
        }
        if let hip = sample.hipAngleDeg {
            lines.append("Hip \(String(format: "%.1f", hip))°")
        }
        if let phase = sample.crankPhaseDeg {
            lines.append("Phase \(String(format: "%.0f", phase))°")
        }
        if let leftKnee {
            lines.append("L-Knee \(String(format: "%.1f", leftKnee))°")
        }
        if let rightKnee {
            lines.append("R-Knee \(String(format: "%.1f", rightKnee))°")
        }

        let panelHeight = CGFloat(24 + lines.count * 18)
        context.setFillColor(textBg)
        context.fill(CGRect(x: 14, y: CGFloat(height) - panelHeight - 14, width: 260, height: panelHeight))

        var baseline = CGFloat(height) - 34
        for line in lines {
            drawText(
                line,
                at: CGPoint(x: 24, y: baseline),
                color: textFg,
                size: 13,
                context: context
            )
            baseline -= 18
        }

        return context.makeImage()
    }

    private func drawChain(_ points: [CGPoint], color: CGColor, context: CGContext) {
        guard points.count >= 2 else { return }
        context.setStrokeColor(color)
        context.setLineWidth(3)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.beginPath()
        context.move(to: points[0])
        for point in points.dropFirst() {
            context.addLine(to: point)
        }
        context.strokePath()
    }

    private func drawPoints(_ points: [CGPoint], color: CGColor, context: CGContext) {
        context.setFillColor(color)
        for point in points {
            context.fillEllipse(in: CGRect(x: point.x - 3.5, y: point.y - 3.5, width: 7, height: 7))
        }
    }

    private func drawText(_ text: String, at point: CGPoint, color: CGColor, size: CGFloat, context: CGContext) {
        let font = CTFontCreateWithName("Helvetica-Bold" as CFString, size, nil)
        let attrs: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(rawValue: kCTFontAttributeName as String): font,
            NSAttributedString.Key(rawValue: kCTForegroundColorAttributeName as String): color
        ]
        let attr = NSAttributedString(string: text, attributes: attrs)
        let line = CTLineCreateWithAttributedString(attr)
        context.textPosition = point
        CTLineDraw(line, context)
    }

    private func nearestSample(at timeSeconds: Double, samples: [VideoJointAngleSample]) -> VideoJointAngleSample? {
        guard !samples.isEmpty else { return nil }
        var low = 0
        var high = samples.count - 1
        while low < high {
            let mid = (low + high) / 2
            if samples[mid].timeSeconds < timeSeconds {
                low = mid + 1
            } else {
                high = mid
            }
        }
        let right = samples[min(low, samples.count - 1)]
        if low == 0 { return right }
        let left = samples[low - 1]
        return abs(left.timeSeconds - timeSeconds) <= abs(right.timeSeconds - timeSeconds) ? left : right
    }

    private func angleDegrees(a: CGPoint?, b: CGPoint?, c: CGPoint?) -> Double? {
        guard let a, let b, let c else { return nil }
        let ba = CGVector(dx: a.x - b.x, dy: a.y - b.y)
        let bc = CGVector(dx: c.x - b.x, dy: c.y - b.y)
        let dot = ba.dx * bc.dx + ba.dy * bc.dy
        let magBA = hypot(ba.dx, ba.dy)
        let magBC = hypot(bc.dx, bc.dy)
        guard magBA > 0.000001, magBC > 0.000001 else { return nil }
        let cosine = max(-1.0, min(1.0, dot / (magBA * magBC)))
        return acos(cosine) * 180.0 / Double.pi
    }
}
