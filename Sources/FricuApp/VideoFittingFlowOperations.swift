import Foundation

struct VideoCaptureGuidance: Equatable {
    let fps: Double
    let luma: Double?
    let sharpness: Double?
    let occlusionRatio: Double?
    let distortionRisk: Double?
    let skeletonAlignability: Double?
    let gateResult: VideoCaptureQualityGateResult

    var qualityGatePass: Bool {
        gateResult.passed
    }

    var qualityScore: Double {
        gateResult.score
    }

    var qualityGrade: VideoCaptureQualityGrade {
        gateResult.grade
    }

    var gateFailureTips: [String] {
        gateResult.failureTips
    }
}

enum VideoFittingFlowAction: Equatable {
    case analyzeSelectedView
    case analyzeAllViews
    case autoCaptureAndAnalyze
    case exportPDF
    case exportReportVideos
}

enum VideoFittingFlowBlockReason: Equatable {
    case complianceRequired(VideoFittingFlowAction)
    case selectedViewVideoMissing
    case assignedViewsMissing
    case analysisResultsMissing
}

enum VideoFittingFlowGuardPolicy {
    static func analyzeSelectedView(
        canRunPostCompliance: Bool,
        hasRequestedViewVideo: Bool
    ) -> VideoFittingFlowBlockReason? {
        if !canRunPostCompliance {
            return .complianceRequired(.analyzeSelectedView)
        }
        if !hasRequestedViewVideo {
            return .selectedViewVideoMissing
        }
        return nil
    }

    static func analyzeAllViews(
        canRunPostCompliance: Bool,
        hasAnyAssignedViewVideo: Bool
    ) -> VideoFittingFlowBlockReason? {
        if !canRunPostCompliance {
            return .complianceRequired(.analyzeAllViews)
        }
        if !hasAnyAssignedViewVideo {
            return .assignedViewsMissing
        }
        return nil
    }

    static func autoCaptureAndAnalyze(
        canRunPostCompliance: Bool,
        hasAnyAssignedViewVideo: Bool
    ) -> VideoFittingFlowBlockReason? {
        if !canRunPostCompliance {
            return .complianceRequired(.autoCaptureAndAnalyze)
        }
        if !hasAnyAssignedViewVideo {
            return .assignedViewsMissing
        }
        return nil
    }

    static func exportPDF(
        canRunPostCompliance: Bool,
        hasAnyAnalysisResult: Bool
    ) -> VideoFittingFlowBlockReason? {
        if !canRunPostCompliance {
            return .complianceRequired(.exportPDF)
        }
        if !hasAnyAnalysisResult {
            return .analysisResultsMissing
        }
        return nil
    }

    static func exportReportVideos(
        canRunPostCompliance: Bool,
        hasAnyAssignedViewVideo: Bool
    ) -> VideoFittingFlowBlockReason? {
        if !canRunPostCompliance {
            return .complianceRequired(.exportReportVideos)
        }
        if !hasAnyAssignedViewVideo {
            return .assignedViewsMissing
        }
        return nil
    }
}

enum VideoFittingQualityGateMessagePolicy {
    static func failureMessage(view: CyclingCameraView, guidance: VideoCaptureGuidance) -> String {
        let fpsText = String(format: "%.1f", guidance.fps)
        let lumaText = guidance.luma.map { String(format: "%.2f", $0) } ?? "--"
        let sharpnessText = guidance.sharpness.map { String(format: "%.3f", $0) } ?? "--"
        let occlusionText = guidance.occlusionRatio.map { String(format: "%.0f%%", $0 * 100) } ?? "--"
        let distortionText = guidance.distortionRisk.map { String(format: "%.0f%%", $0 * 100) } ?? "--"
        let alignText = guidance.skeletonAlignability.map { String(format: "%.0f%%", $0 * 100) } ?? "--"
        let qualityScoreText = String(format: "%.0f", guidance.qualityScore * 100)
        let tips = guidance.gateFailureTips
        let detailLines = tips.map { "• \($0)" }.joined(separator: "\n")
        return L10n.choose(
            simplifiedChinese: "\(view.displayName) 机位未通过质量门控（质量得分 \(qualityScoreText) / FPS \(fpsText) / 亮度 \(lumaText) / 清晰 \(sharpnessText) / 遮挡 \(occlusionText) / 畸变风险 \(distortionText) / 对位可识别 \(alignText)）。\n重拍指令：\n\(detailLines)\n请重拍后再分析。",
            english: "\(view.displayName) failed quality gate (quality score \(qualityScoreText) / FPS \(fpsText) / Luma \(lumaText) / Sharpness \(sharpnessText) / Occlusion \(occlusionText) / Distortion risk \(distortionText) / Skeleton alignability \(alignText)).\nRetake instructions:\n\(detailLines)\nPlease retake before analysis."
        )
    }
}

struct VideoFittingPreflightQualityGateResult {
    let passed: [(CyclingCameraView, URL)]
    let failures: [String]
    let guidanceByView: [CyclingCameraView: VideoCaptureGuidance]
}

struct VideoFittingPreflightQualityGateService {
    func run(
        plans: [(CyclingCameraView, URL)],
        evaluateGuidance: (URL) async -> VideoCaptureGuidance
    ) async -> VideoFittingPreflightQualityGateResult {
        var passed: [(CyclingCameraView, URL)] = []
        var failures: [String] = []
        var guidanceByView: [CyclingCameraView: VideoCaptureGuidance] = [:]

        for (view, url) in plans {
            let guidance = await evaluateGuidance(url)
            guidanceByView[view] = guidance
            if guidance.qualityGatePass {
                passed.append((view, url))
            } else {
                failures.append(VideoFittingQualityGateMessagePolicy.failureMessage(view: view, guidance: guidance))
            }
        }

        return VideoFittingPreflightQualityGateResult(
            passed: passed,
            failures: failures,
            guidanceByView: guidanceByView
        )
    }
}

struct VideoFittingFlowPlanningService {
    func assignedPlans(
        supportedViews: [CyclingCameraView],
        sourceVideoURL: (CyclingCameraView) -> URL?
    ) -> [(CyclingCameraView, URL)] {
        supportedViews.compactMap { view in
            guard let url = sourceVideoURL(view) else { return nil }
            return (view, url)
        }
    }

    func exportedResultsByView(
        resultsByView: [CyclingCameraView: VideoJointAngleAnalysisResult],
        supportedViews: [CyclingCameraView]
    ) -> [CyclingCameraView: VideoJointAngleAnalysisResult] {
        var output: [CyclingCameraView: VideoJointAngleAnalysisResult] = [:]
        for view in supportedViews {
            if let result = resultsByView[view] {
                output[view] = result
            }
        }
        return output
    }

    func uniqueFailures(_ failures: [String]) -> [String] {
        failures.reduce(into: [String]()) { partial, item in
            if !partial.contains(item) {
                partial.append(item)
            }
        }
    }
}

enum VideoFittingCaptureWindowPolicy {
    static func analysisResultCoversWindow(
        _ result: VideoJointAngleAnalysisResult,
        start: Double,
        duration: Double
    ) -> Bool {
        let end = start + duration
        guard result.durationSeconds + 0.35 >= end else { return false }
        guard !result.samples.isEmpty else { return false }
        let first = result.samples.first?.timeSeconds ?? 0
        let last = result.samples.last?.timeSeconds ?? 0
        return first <= start + 0.5 && last + 0.35 >= end
    }

    static func suggestedCaptureWindow(
        from result: VideoJointAngleAnalysisResult,
        preferredDuration: Double
    ) -> (start: Double, duration: Double) {
        let duration = min(max(1.0, preferredDuration), max(1.2, result.durationSeconds))
        if let cycle = result.cadenceCycles.first {
            let start = min(max(0, cycle.startTimeSeconds), max(0, result.durationSeconds - duration))
            return (start, duration)
        }

        if let phaseSample = result.samples.first(where: { $0.crankPhaseDeg != nil }) {
            let start = min(max(0, phaseSample.timeSeconds - 0.8), max(0, result.durationSeconds - duration))
            return (start, duration)
        }

        let start = max(0, (result.durationSeconds - duration) * 0.35)
        return (start, duration)
    }
}
