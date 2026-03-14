import Foundation

enum VideoFittingStepState: Equatable {
    case pending
    case running
    case blocked
    case ready
    case done
}

struct VideoFittingWorkflowSnapshot {
    var assignedViewCount: Int
    var requiredViewCount: Int
    var isComplianceRunning: Bool
    var complianceChecked: Bool
    var compliancePassed: Bool
    var isAnalyzing: Bool
    var hasRecognitionResults: Bool

    var hasAnyAssignedView: Bool {
        assignedViewCount > 0
    }

    var hasAllRequiredViews: Bool {
        requiredViewCount > 0 && assignedViewCount >= requiredViewCount
    }
}

struct VideoFittingWorkflowStates: Equatable {
    let viewAssignment: VideoFittingStepState
    let compliance: VideoFittingStepState
    let skeletonRecognition: VideoFittingStepState
    let report: VideoFittingStepState
    let canRunPostCompliance: Bool
}

enum VideoFittingWorkflowResolver {
    static func resolve(from snapshot: VideoFittingWorkflowSnapshot) -> VideoFittingWorkflowStates {
        let viewAssignment: VideoFittingStepState = {
            guard snapshot.assignedViewCount > 0 else { return .pending }
            return snapshot.hasAllRequiredViews ? .done : .ready
        }()

        let compliance: VideoFittingStepState = {
            if snapshot.isComplianceRunning { return .running }
            guard snapshot.hasAnyAssignedView else { return .pending }
            guard snapshot.complianceChecked else { return .ready }
            guard snapshot.compliancePassed else { return .blocked }
            return snapshot.hasAllRequiredViews ? .done : .ready
        }()

        let canRunPostCompliance = snapshot.hasAnyAssignedView && snapshot.complianceChecked && snapshot.compliancePassed

        let skeletonRecognition: VideoFittingStepState = {
            if snapshot.isAnalyzing { return .running }
            guard snapshot.hasAnyAssignedView else { return .pending }
            guard canRunPostCompliance else { return .blocked }
            return snapshot.hasRecognitionResults ? .done : .ready
        }()

        let report: VideoFittingStepState = {
            if snapshot.isAnalyzing { return .running }
            guard snapshot.hasAnyAssignedView else { return .pending }
            guard canRunPostCompliance else { return .blocked }
            return snapshot.hasRecognitionResults ? .ready : .pending
        }()

        return VideoFittingWorkflowStates(
            viewAssignment: viewAssignment,
            compliance: compliance,
            skeletonRecognition: skeletonRecognition,
            report: report,
            canRunPostCompliance: canRunPostCompliance
        )
    }
}

enum VideoFittingCapability: String, CaseIterable, Identifiable {
    case frontAlignment
    case sideKinematics
    case rearStability

    var id: String { rawValue }

    var title: String {
        switch self {
        case .frontAlignment:
            return L10n.choose(simplifiedChinese: "前视对位与轨迹", english: "Front alignment + trajectory")
        case .sideKinematics:
            return L10n.choose(simplifiedChinese: "侧视角度与 BDC", english: "Side angles + BDC")
        case .rearStability:
            return L10n.choose(simplifiedChinese: "后视稳定与顺拐", english: "Rear stability + crossover")
        }
    }

    var requiredView: CyclingCameraView {
        switch self {
        case .frontAlignment:
            return .front
        case .sideKinematics:
            return .side
        case .rearStability:
            return .rear
        }
    }

    var missingReason: String {
        switch self {
        case .frontAlignment:
            return L10n.choose(
                simplifiedChinese: "缺少前视视频：膝/踝/足尖轨迹与关节对位不可用。",
                english: "Missing front video: knee/ankle/toe trajectories and alignment are unavailable."
            )
        case .sideKinematics:
            return L10n.choose(
                simplifiedChinese: "缺少侧视视频：髋/膝角、BDC 与座高建议不可用。",
                english: "Missing side video: hip/knee angles, BDC, and saddle-height suggestions are unavailable."
            )
        case .rearStability:
            return L10n.choose(
                simplifiedChinese: "缺少后视视频：盆骨倾斜、重心漂移与顺拐风险不可用。",
                english: "Missing rear video: pelvic tilt, COM drift, and crossover-risk analysis are unavailable."
            )
        }
    }
}

struct VideoFittingCapabilityStatus: Identifiable, Equatable {
    let capability: VideoFittingCapability
    let isAvailable: Bool
    let message: String

    var id: String { capability.id }
}

struct VideoFittingCapabilityMatrix: Equatable {
    let statuses: [VideoFittingCapabilityStatus]

    var availableCount: Int {
        statuses.filter(\.isAvailable).count
    }

    var unavailableCount: Int {
        statuses.count - availableCount
    }

    static func build(assignedViews: Set<CyclingCameraView>) -> VideoFittingCapabilityMatrix {
        let statuses = VideoFittingCapability.allCases.map { capability in
            if assignedViews.contains(capability.requiredView) {
                return VideoFittingCapabilityStatus(
                    capability: capability,
                    isAvailable: true,
                    message: L10n.choose(simplifiedChinese: "可用", english: "Available")
                )
            }
            return VideoFittingCapabilityStatus(
                capability: capability,
                isAvailable: false,
                message: capability.missingReason
            )
        }
        return VideoFittingCapabilityMatrix(statuses: statuses)
    }
}

enum VideoFittingSessionSummaryTone: Equatable {
    case empty
    case partial
    case ready
}

struct VideoFittingSessionSummary: Equatable {
    let tone: VideoFittingSessionSummaryTone
    let statusTitle: String
    let statusDetail: String
    let progressText: String
    let completionRatio: Double
    let capabilitySummary: String
    let availableCapabilityTitles: [String]
    let nextActionTitle: String
    let nextActionDetail: String
}

struct VideoFittingCameraViewCardSummary: Identifiable, Equatable {
    enum Tone: Equatable {
        case empty
        case partial
        case ready
    }

    let view: CyclingCameraView
    let title: String
    let subtitle: String
    let fileName: String?
    let statusTitle: String
    let statusDetail: String
    let blockingReasons: [String]
    let qualityTitle: String
    let qualityDetail: String
    let qualityMetrics: [VideoFittingCameraViewQualityMetric]
    let supportedConclusions: [String]
    let missingImpact: String
    let tone: Tone

    var id: String { view.id }
    var hasAssignedVideo: Bool { fileName != nil }
}

struct VideoFittingCameraViewQualityMetric: Identifiable, Equatable {
    let key: String
    let title: String
    let value: String

    var id: String { key }
}

enum VideoFittingCameraViewCardSummaryResolver {
    static func resolve(
        view: CyclingCameraView,
        sourceURL: URL?,
        guidance: VideoCaptureGuidance?,
        hasAnalysisResult: Bool
    ) -> VideoFittingCameraViewCardSummary {
        let fileName = sourceURL?.lastPathComponent
        let supportedConclusions = videoFittingSupportedConclusions(for: view)
        let missingImpact = videoFittingMissingImpactText(for: view)

        if sourceURL == nil {
            return VideoFittingCameraViewCardSummary(
                view: view,
                title: view.displayName,
                subtitle: L10n.choose(simplifiedChinese: "未分配视频", english: "No video assigned"),
                fileName: nil,
                statusTitle: L10n.choose(simplifiedChinese: "待上传", english: "Awaiting upload"),
                statusDetail: L10n.choose(
                    simplifiedChinese: "该机位尚未配置，当前无法产出对应结论。",
                    english: "This view is not configured yet, so its conclusion is unavailable."
                ),
                blockingReasons: [],
                qualityTitle: L10n.choose(simplifiedChinese: "质量状态", english: "Quality"),
                qualityDetail: L10n.choose(simplifiedChinese: "待检测：上传后显示质量结果。", english: "Pending: quality appears after upload."),
                qualityMetrics: [],
                supportedConclusions: supportedConclusions,
                missingImpact: missingImpact,
                tone: .empty
            )
        }

        if hasAnalysisResult {
            return VideoFittingCameraViewCardSummary(
                view: view,
                title: view.displayName,
                subtitle: L10n.choose(simplifiedChinese: "机位已分析", english: "View analyzed"),
                fileName: fileName,
                statusTitle: L10n.choose(simplifiedChinese: "已分析", english: "Analyzed"),
                statusDetail: L10n.choose(
                    simplifiedChinese: "该机位已产出分析结果，可继续补齐其他机位或导出结论。",
                    english: "This view already produced analysis output. You can fill missing views or export conclusions."
                ),
                blockingReasons: guidance.map { blockingReasons(for: $0) } ?? [],
                qualityTitle: qualityTitle(for: guidance),
                qualityDetail: qualityDetail(for: guidance),
                qualityMetrics: qualityMetrics(for: guidance),
                supportedConclusions: supportedConclusions,
                missingImpact: missingImpact,
                tone: .ready
            )
        }

        if let guidance {
            return VideoFittingCameraViewCardSummary(
                view: view,
                title: view.displayName,
                subtitle: guidance.qualityGatePass
                    ? L10n.choose(simplifiedChinese: "机位已就绪", english: "View ready")
                    : L10n.choose(simplifiedChinese: "机位待优化", english: "Needs improvement"),
                fileName: fileName,
                statusTitle: guidance.qualityGatePass
                    ? L10n.choose(simplifiedChinese: "可分析", english: "Analyzable")
                    : L10n.choose(simplifiedChinese: "待优化", english: "Needs work"),
                statusDetail: guidance.qualityGatePass
                    ? L10n.choose(simplifiedChinese: "质量门控已通过，这个机位可以进入后续分析。", english: "Quality gate passed. This view can proceed to analysis.")
                    : L10n.choose(simplifiedChinese: "质量门控未通过，建议先修正光照、遮挡或机位后重试。", english: "Quality gate failed. Fix lighting, occlusion, or camera setup and retry."),
                blockingReasons: blockingReasons(for: guidance),
                qualityTitle: qualityTitle(for: guidance),
                qualityDetail: qualityDetail(for: guidance),
                qualityMetrics: qualityMetrics(for: guidance),
                supportedConclusions: supportedConclusions,
                missingImpact: missingImpact,
                tone: guidance.qualityGatePass ? .ready : .partial
            )
        }

        return VideoFittingCameraViewCardSummary(
            view: view,
            title: view.displayName,
            subtitle: L10n.choose(simplifiedChinese: "机位已上传", english: "Video assigned"),
            fileName: fileName,
            statusTitle: L10n.choose(simplifiedChinese: "待检测", english: "Awaiting quality check"),
            statusDetail: L10n.choose(
                simplifiedChinese: "视频已上传，下一步运行合规检查后可确认是否能进入分析。",
                english: "The video is assigned. Run compliance check next to confirm analyzability."
            ),
            blockingReasons: [],
            qualityTitle: L10n.choose(simplifiedChinese: "质量状态", english: "Quality"),
            qualityDetail: L10n.choose(simplifiedChinese: "待检测：尚未执行质量门控。", english: "Pending: quality gate has not run yet."),
            qualityMetrics: [],
            supportedConclusions: supportedConclusions,
            missingImpact: missingImpact,
            tone: .partial
        )
    }

    private static func qualityTitle(for guidance: VideoCaptureGuidance?) -> String {
        guard let guidance else {
            return L10n.choose(simplifiedChinese: "质量状态", english: "Quality")
        }
        return L10n.choose(
            simplifiedChinese: "质量状态 · \(guidance.qualityGrade.label)",
            english: "Quality · \(guidance.qualityGrade.label)"
        )
    }

    private static func qualityDetail(for guidance: VideoCaptureGuidance?) -> String {
        guard let guidance else {
            return L10n.choose(simplifiedChinese: "待检测", english: "Pending")
        }
        if let firstFailure = blockingReasons(for: guidance).first {
            return firstFailure
        }
        let scoreText = String(format: "%.0f", guidance.qualityScore * 100)
        let fpsText = String(format: "%.1f", guidance.fps)
        return L10n.choose(
            simplifiedChinese: "质量 \(scoreText) / FPS \(fpsText) / 对位 \(videoFittingPercentageText(guidance.skeletonAlignability)) / 遮挡 \(videoFittingPercentageText(guidance.occlusionRatio))",
            english: "Score \(scoreText) / FPS \(fpsText) / Align \(videoFittingPercentageText(guidance.skeletonAlignability)) / Occlusion \(videoFittingPercentageText(guidance.occlusionRatio))"
        )
    }

    private static func blockingReasons(for guidance: VideoCaptureGuidance) -> [String] {
        guidance.gateResult.failures.map(\.reason)
    }

    private static func qualityMetrics(for guidance: VideoCaptureGuidance?) -> [VideoFittingCameraViewQualityMetric] {
        guard let guidance else { return [] }
        let scoreText = String(format: "%.0f", guidance.qualityScore * 100)
        let fpsText = String(format: "%.1f", guidance.fps)
        let lumaText = guidance.luma.map { String(format: "%.2f", $0) } ?? "--"
        let sharpnessText = guidance.sharpness.map { String(format: "%.3f", $0) } ?? "--"
        let distortionText = videoFittingPercentageText(guidance.distortionRisk)
        return [
            VideoFittingCameraViewQualityMetric(
                key: "score",
                title: L10n.choose(simplifiedChinese: "质量分", english: "Score"),
                value: scoreText
            ),
            VideoFittingCameraViewQualityMetric(
                key: "fps",
                title: "FPS",
                value: fpsText
            ),
            VideoFittingCameraViewQualityMetric(
                key: "luma",
                title: L10n.choose(simplifiedChinese: "亮度", english: "Luma"),
                value: lumaText
            ),
            VideoFittingCameraViewQualityMetric(
                key: "sharpness",
                title: L10n.choose(simplifiedChinese: "清晰度", english: "Sharpness"),
                value: sharpnessText
            ),
            VideoFittingCameraViewQualityMetric(
                key: "distortion",
                title: L10n.choose(simplifiedChinese: "畸变风险", english: "Distortion"),
                value: distortionText
            ),
            VideoFittingCameraViewQualityMetric(
                key: "alignment",
                title: L10n.choose(simplifiedChinese: "对位", english: "Align"),
                value: videoFittingPercentageText(guidance.skeletonAlignability)
            ),
            VideoFittingCameraViewQualityMetric(
                key: "occlusion",
                title: L10n.choose(simplifiedChinese: "遮挡", english: "Occlusion"),
                value: videoFittingPercentageText(guidance.occlusionRatio)
            )
        ]
    }

}

private func videoFittingSupportedConclusions(for view: CyclingCameraView) -> [String] {
    switch view {
    case .front:
        return [
            L10n.choose(simplifiedChinese: "膝盖轨迹", english: "Knee tracking"),
            L10n.choose(simplifiedChinese: "踝/足尖路径", english: "Ankle / toe path"),
            L10n.choose(simplifiedChinese: "关节对位", english: "Joint alignment")
        ]
    case .side:
        return [
            L10n.choose(simplifiedChinese: "髋/膝角", english: "Hip / knee angles"),
            L10n.choose(simplifiedChinese: "BDC 下止点膝角", english: "BDC knee angle"),
            L10n.choose(simplifiedChinese: "座高建议", english: "Saddle-height guidance")
        ]
    case .rear:
        return [
            L10n.choose(simplifiedChinese: "盆骨倾斜", english: "Pelvic tilt"),
            L10n.choose(simplifiedChinese: "重心漂移", english: "Center-of-mass drift"),
            L10n.choose(simplifiedChinese: "顺拐风险", english: "Crossover risk")
        ]
    case .auto:
        return []
    }
}

private func videoFittingPercentageText(_ value: Double?) -> String {
    guard let value else { return "--" }
    return String(format: "%.0f%%", value * 100)
}

private func videoFittingMissingImpactText(for view: CyclingCameraView) -> String {
    switch view {
    case .front:
        return L10n.choose(
            simplifiedChinese: "缺少前视：无法输出膝/踝/足尖轨迹与关节对位。",
            english: "Missing front view: knee/ankle/toe trajectories and alignment stay unavailable."
        )
    case .side:
        return L10n.choose(
            simplifiedChinese: "缺少侧视：无法输出髋/膝角、BDC 与座高建议。",
            english: "Missing side view: hip/knee angles, BDC, and saddle-height guidance stay unavailable."
        )
    case .rear:
        return L10n.choose(
            simplifiedChinese: "缺少后视：无法输出盆骨倾斜、重心漂移与顺拐风险。",
            english: "Missing rear view: pelvic tilt, COM drift, and crossover-risk analysis stay unavailable."
        )
    case .auto:
        return L10n.choose(
            simplifiedChinese: "缺少机位：对应分析能力不可用。",
            english: "Missing view: corresponding analysis capability is unavailable."
        )
    }
}

struct VideoFittingComplianceViewSummary: Identifiable, Equatable {
    enum Tone: Equatable {
        case empty
        case pending
        case passed
        case failed
    }

    let view: CyclingCameraView
    let title: String
    let statusTitle: String
    let statusDetail: String
    let qualityTitle: String
    let qualityDetail: String
    let reasonLines: [String]
    let recommendationLines: [String]
    let tone: Tone

    var id: String { view.id }
}

enum VideoFittingFailureCategory: String, CaseIterable, Identifiable {
    case cameraPlacement
    case lighting
    case stability
    case visibility
    case landmarks

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cameraPlacement:
            return L10n.choose(simplifiedChinese: "机位与镜头", english: "Camera Placement")
        case .lighting:
            return L10n.choose(simplifiedChinese: "光线", english: "Lighting")
        case .stability:
            return L10n.choose(simplifiedChinese: "稳定与清晰度", english: "Stability and Sharpness")
        case .visibility:
            return L10n.choose(simplifiedChinese: "入镜与遮挡", english: "Framing and Occlusion")
        case .landmarks:
            return L10n.choose(simplifiedChinese: "骨骼对位", english: "Skeleton Alignment")
        }
    }

    var detail: String {
        switch self {
        case .cameraPlacement:
            return L10n.choose(
                simplifiedChinese: "重点检查镜头是否正对车身平面、是否使用超广角、车身中轴是否居中。",
                english: "Check whether the camera is orthogonal to the bike plane, avoids ultra-wide distortion, and centers the bike axis."
            )
        case .lighting:
            return L10n.choose(
                simplifiedChinese: "优先补前侧光，避免逆光，让身体轮廓与关节边界清楚可见。",
                english: "Prioritize front/side lighting, avoid backlight, and keep body contours clearly visible."
            )
        case .stability:
            return L10n.choose(
                simplifiedChinese: "固定机位、锁焦并提高快门，避免拖影和低帧率。",
                english: "Stabilize the camera, lock focus, and increase shutter speed to avoid blur and low frame rate."
            )
        case .visibility:
            return L10n.choose(
                simplifiedChinese: "确保人体与自行车完整入镜，避免衣物、车把或骑行台遮挡髋-膝-踝。",
                english: "Keep the rider and bike fully in frame and avoid clothing, handlebars, or trainer blocking hip-knee-ankle visibility."
            )
        case .landmarks:
            return L10n.choose(
                simplifiedChinese: "若衣物影响关键点识别，建议贴身衣物并在髋/膝/踝处增加标记点。",
                english: "If clothing hurts landmark recognition, wear tighter clothing and add markers on hip, knee, and ankle."
            )
        }
    }
}

struct VideoFittingFailureCategorySummary: Identifiable, Equatable {
    let category: VideoFittingFailureCategory
    let affectedViews: [CyclingCameraView]
    let reasons: [String]

    var id: String { category.id }
}

struct VideoFittingFailureRecoverySummary: Equatable {
    let title: String
    let detail: String
    let categories: [VideoFittingFailureCategorySummary]
    let fixSuggestions: [String]
    let recommendedRetakeViews: [CyclingCameraView]
    let retryTitle: String
    let retryDetail: String
}

enum VideoFittingFailureRecoverySummaryResolver {
    static func resolve(
        supportedViews: [CyclingCameraView],
        sourceURL: (CyclingCameraView) -> URL?,
        guidanceByView: [CyclingCameraView: VideoCaptureGuidance],
        complianceChecked: Bool,
        compliancePassed: Bool
    ) -> VideoFittingFailureRecoverySummary? {
        guard complianceChecked, !compliancePassed else { return nil }

        var categoryMap: [VideoFittingFailureCategory: Set<CyclingCameraView>] = [:]
        var reasonMap: [VideoFittingFailureCategory: [String]] = [:]
        var fixSuggestions: [String] = []
        var retakeViews: [CyclingCameraView] = []

        for view in supportedViews {
            guard sourceURL(view) != nil else { continue }
            guard let guidance = guidanceByView[view], !guidance.qualityGatePass else { continue }
            retakeViews.append(view)
            for failure in guidance.gateResult.failures {
                categoryMap[failure.recoveryCategory, default: []].insert(view)
                reasonMap[failure.recoveryCategory, default: []].append(failure.reason)
            }
            fixSuggestions.append(contentsOf: guidance.gateFailureTips)
        }

        let categories = VideoFittingFailureCategory.allCases.compactMap { category -> VideoFittingFailureCategorySummary? in
            guard let views = categoryMap[category], !views.isEmpty else { return nil }
            return VideoFittingFailureCategorySummary(
                category: category,
                affectedViews: supportedViews.filter { views.contains($0) },
                reasons: deduplicated(reasonMap[category] ?? [])
            )
        }

        let uniqueRetakeViews = supportedViews.filter { retakeViews.contains($0) }
        let uniqueFixSuggestions = deduplicated(fixSuggestions)

        guard !categories.isEmpty || !uniqueRetakeViews.isEmpty else { return nil }

        return VideoFittingFailureRecoverySummary(
            title: L10n.choose(simplifiedChinese: "失败恢复路径", english: "Recovery Path"),
            detail: L10n.choose(
                simplifiedChinese: "当前至少有一个机位未通过合规检查。先按分类修复，再一键重试；必要时优先重录推荐机位。",
                english: "At least one view failed compliance. Fix the categorized issues first, then retry in one tap; retake the recommended views first when needed."
            ),
            categories: categories,
            fixSuggestions: uniqueFixSuggestions,
            recommendedRetakeViews: uniqueRetakeViews,
            retryTitle: L10n.choose(simplifiedChinese: "一键重试合规检查", english: "Retry Compliance in One Tap"),
            retryDetail: L10n.choose(
                simplifiedChinese: "修正机位、光线或遮挡后，直接重新执行当前视频的合规检查。",
                english: "After fixing camera placement, lighting, or occlusion, rerun compliance on the current videos directly."
            )
        )
    }

    private static func deduplicated(_ items: [String]) -> [String] {
        var seen: Set<String> = []
        return items.filter { seen.insert($0).inserted }
    }
}

enum VideoFittingComplianceViewSummaryResolver {
    static func resolve(
        view: CyclingCameraView,
        sourceURL: URL?,
        guidance: VideoCaptureGuidance?
    ) -> VideoFittingComplianceViewSummary {
        if sourceURL == nil {
            return VideoFittingComplianceViewSummary(
                view: view,
                title: view.displayName,
                statusTitle: L10n.choose(simplifiedChinese: "未配置机位", english: "View missing"),
                statusDetail: L10n.choose(
                    simplifiedChinese: "当前没有可检查的视频，先补齐这个机位后才能判断是否合规。",
                    english: "There is no video to inspect yet. Assign this view before compliance can be evaluated."
                ),
                qualityTitle: L10n.choose(simplifiedChinese: "合规状态", english: "Compliance"),
                qualityDetail: L10n.choose(simplifiedChinese: "待上传", english: "Awaiting upload"),
                reasonLines: [videoFittingMissingImpactText(for: view)],
                recommendationLines: [
                    L10n.choose(
                        simplifiedChinese: "上传对应机位视频后，再执行合规检查。",
                        english: "Upload the corresponding view video, then run compliance check."
                    )
                ],
                tone: .empty
            )
        }

        guard let guidance else {
            return VideoFittingComplianceViewSummary(
                view: view,
                title: view.displayName,
                statusTitle: L10n.choose(simplifiedChinese: "待检查", english: "Pending check"),
                statusDetail: L10n.choose(
                    simplifiedChinese: "视频已配置，但还没有合规结果。",
                    english: "The video is assigned, but there is no compliance result yet."
                ),
                qualityTitle: L10n.choose(simplifiedChinese: "合规状态", english: "Compliance"),
                qualityDetail: L10n.choose(simplifiedChinese: "等待执行", english: "Waiting to run"),
                reasonLines: [
                    L10n.choose(
                        simplifiedChinese: "当前无法判断畸变、遮挡、光照与骨骼对位是否达标。",
                        english: "Distortion, occlusion, lighting, and skeleton alignment have not been evaluated yet."
                    )
                ],
                recommendationLines: [
                    L10n.choose(
                        simplifiedChinese: "点击“检查视频合规”生成结果卡。",
                        english: "Tap “Run Compliance Check” to generate the result card."
                    )
                ],
                tone: .pending
            )
        }

        let qualityTitle = L10n.choose(
            simplifiedChinese: "合规状态 · \(guidance.qualityGrade.label)",
            english: "Compliance · \(guidance.qualityGrade.label)"
        )
        let qualityDetail = qualityDetail(for: guidance)

        if guidance.qualityGatePass {
            return VideoFittingComplianceViewSummary(
                view: view,
                title: view.displayName,
                statusTitle: L10n.choose(simplifiedChinese: "合格", english: "Qualified"),
                statusDetail: L10n.choose(
                    simplifiedChinese: "这个机位已经通过合规检查，可以继续进入骨点识别。",
                    english: "This view passed compliance and can proceed to skeleton recognition."
                ),
                qualityTitle: qualityTitle,
                qualityDetail: qualityDetail,
                reasonLines: [
                    L10n.choose(
                        simplifiedChinese: "未发现会阻塞分析的质量问题。",
                        english: "No blocking quality issue was found."
                    )
                ],
                recommendationLines: [
                    L10n.choose(
                        simplifiedChinese: "保持当前机位设置，继续进行骨点识别。",
                        english: "Keep the current setup and continue with skeleton recognition."
                    )
                ],
                tone: .passed
            )
        }

        let reasons = guidance.gateResult.failures.map(\.reason)
        let recommendations = guidance.gateFailureTips.isEmpty
            ? [
                L10n.choose(
                    simplifiedChinese: "根据现场情况调整机位、光照或标记点后重试。",
                    english: "Adjust camera setup, lighting, or marker placement and retry."
                )
            ]
            : guidance.gateFailureTips

        return VideoFittingComplianceViewSummary(
            view: view,
            title: view.displayName,
            statusTitle: L10n.choose(simplifiedChinese: "不合格", english: "Not qualified"),
            statusDetail: L10n.choose(
                simplifiedChinese: "当前质量门控未通过，建议先修正问题再进入骨点识别。",
                english: "The quality gate failed. Fix the issues before skeleton recognition."
            ),
            qualityTitle: qualityTitle,
            qualityDetail: qualityDetail,
            reasonLines: reasons,
            recommendationLines: recommendations,
            tone: .failed
        )
    }

    private static func qualityDetail(for guidance: VideoCaptureGuidance) -> String {
        let scoreText = String(format: "%.0f", guidance.qualityScore * 100)
        let fpsText = String(format: "%.1f", guidance.fps)
        let alignText = videoFittingPercentageText(guidance.skeletonAlignability)
        let occlusionText = videoFittingPercentageText(guidance.occlusionRatio)
        return L10n.choose(
            simplifiedChinese: "质量 \(scoreText) / FPS \(fpsText) / 对位 \(alignText) / 遮挡 \(occlusionText)",
            english: "Score \(scoreText) / FPS \(fpsText) / Align \(alignText) / Occlusion \(occlusionText)"
        )
    }
}

struct VideoFittingJointRecognitionQualitySummary: Equatable {
    enum Tone: Equatable {
        case empty
        case blocked
        case pending
        case ready
    }

    let statusTitle: String
    let statusDetail: String
    let confidenceText: String
    let dropRateText: String
    let occlusionHint: String
    let problemFrameCountText: String
    let computableIndicators: [String]
    let angleVisuals: [VideoFittingJointAngleVisualSummary]
    let checkpointVisuals: [VideoFittingCheckpointVisualSummary]
    let playbackOverlay: VideoFittingPlaybackOverlaySummary?
    let previewVideoURL: URL?
    let tone: Tone
}

enum VideoFittingJointAngleVisualKind: String, Equatable {
    case knee
    case hip
    case bdcKnee
}

private enum VideoFittingJointTripletKind {
    case knee
    case hip
}

struct VideoFittingJointAngleVisualSummary: Identifiable, Equatable {
    let kind: VideoFittingJointAngleVisualKind
    let title: String
    let subtitle: String
    let angleDegrees: Double
    let detail: String
    let frameTimeSeconds: Double?
    let crankPhaseDegrees: Double?
    let crankCenter: VideoFittingNormalizedPoint?
    let crankRadius: Double?
    let firstPoint: VideoFittingNormalizedPoint?
    let jointPoint: VideoFittingNormalizedPoint?
    let thirdPoint: VideoFittingNormalizedPoint?

    var id: String { kind.rawValue }
}

struct VideoFittingNormalizedPoint: Equatable {
    let x: Double
    let y: Double
}

struct VideoFittingNormalizedRect: Equatable {
    let minX: Double
    let minY: Double
    let maxX: Double
    let maxY: Double

    func expanded(horizontal: Double, vertical: Double) -> VideoFittingNormalizedRect {
        VideoFittingNormalizedRect(
            minX: max(0, minX - horizontal),
            minY: max(0, minY - vertical),
            maxX: min(1, maxX + horizontal),
            maxY: min(1, maxY + vertical)
        )
    }

    func contains(_ point: VideoFittingNormalizedPoint) -> Bool {
        point.x >= minX && point.x <= maxX && point.y >= minY && point.y <= maxY
    }
}

struct VideoFittingCheckpointVisualSummary: Identifiable, Equatable {
    let checkpoint: CrankClockCheckpoint
    let frameTimeSeconds: Double
    let phaseDegrees: Double
    let kneeAngleText: String
    let hipAngleText: String
    let crankCenter: VideoFittingNormalizedPoint?
    let crankRadius: Double?
    let firstPoint: VideoFittingNormalizedPoint?
    let jointPoint: VideoFittingNormalizedPoint?
    let thirdPoint: VideoFittingNormalizedPoint?

    var id: String { checkpoint.id }
}

struct VideoFittingPlaybackOverlaySummary: Equatable {
    let samples: [VideoFittingPlaybackOverlaySample]
    let checkpoints: [VideoFittingPlaybackCheckpointMarker]
    let crankCenter: VideoFittingNormalizedPoint?
    let crankRadius: Double?
}

struct VideoFittingPlaybackOverlaySample: Identifiable, Equatable {
    let id: Int
    let timeSeconds: Double
    let kneeAngleDegrees: Double?
    let hipAngleDegrees: Double?
    let crankPhaseDegrees: Double?
    let firstPoint: VideoFittingNormalizedPoint?
    let jointPoint: VideoFittingNormalizedPoint?
    let thirdPoint: VideoFittingNormalizedPoint?
    let bodyBounds: VideoFittingNormalizedRect?

    func allowsOverlayRendering(horizontalMargin: Double = 0.08, verticalMargin: Double = 0.10) -> Bool {
        guard
            let firstPoint,
            let jointPoint,
            let thirdPoint
        else {
            return false
        }

        let points = [firstPoint, jointPoint, thirdPoint]
        let fallbackBounds = VideoFittingNormalizedRect(minX: 0, minY: 0, maxX: 1, maxY: 1)
        let bounds = (bodyBounds ?? fallbackBounds).expanded(horizontal: horizontalMargin, vertical: verticalMargin)
        return points.allSatisfy(bounds.contains)
    }
}

struct VideoFittingPlaybackCheckpointMarker: Identifiable, Equatable {
    let checkpoint: CrankClockCheckpoint
    let timeSeconds: Double
    let phaseDegrees: Double
    let kneeAngleText: String
    let hipAngleText: String

    var id: String { checkpoint.id }
}

enum VideoFittingJointRecognitionQualitySummaryResolver {
    static func resolve(
        selectedView: CyclingCameraView,
        sourceURL: URL?,
        guidance: VideoCaptureGuidance?,
        result: VideoJointAngleAnalysisResult?
    ) -> VideoFittingJointRecognitionQualitySummary {
        let fallbackIndicators = videoFittingSupportedConclusions(for: selectedView)

        guard selectedView != .auto else {
            return VideoFittingJointRecognitionQualitySummary(
                statusTitle: L10n.choose(simplifiedChinese: "请选择机位", english: "Select a view"),
                statusDetail: L10n.choose(
                    simplifiedChinese: "先选择前视、侧视或后视机位，再查看骨点识别质量。",
                    english: "Choose front, side, or rear first to inspect recognition quality."
                ),
                confidenceText: "--",
                dropRateText: "--",
                occlusionHint: L10n.choose(simplifiedChinese: "等待选择机位。", english: "Awaiting view selection."),
                problemFrameCountText: "--",
                computableIndicators: [],
                angleVisuals: [],
                checkpointVisuals: [],
                playbackOverlay: nil,
                previewVideoURL: nil,
                tone: .empty
            )
        }

        guard sourceURL != nil else {
            return VideoFittingJointRecognitionQualitySummary(
                statusTitle: L10n.choose(simplifiedChinese: "缺少视频", english: "Missing video"),
                statusDetail: L10n.choose(
                    simplifiedChinese: "当前机位没有视频，骨点识别质量面板暂不可用。",
                    english: "This view has no video yet, so the skeleton quality panel is unavailable."
                ),
                confidenceText: "--",
                dropRateText: "--",
                occlusionHint: videoFittingMissingImpactText(for: selectedView),
                problemFrameCountText: "--",
                computableIndicators: fallbackIndicators,
                angleVisuals: [],
                checkpointVisuals: [],
                playbackOverlay: nil,
                previewVideoURL: nil,
                tone: .empty
            )
        }

        if let guidance, !guidance.qualityGatePass {
            let hint = guidance.gateFailureTips.first ?? L10n.choose(
                simplifiedChinese: "先修正当前质量问题后再识别。",
                english: "Fix the current quality issues before recognition."
            )
            return VideoFittingJointRecognitionQualitySummary(
                statusTitle: L10n.choose(simplifiedChinese: "识别被阻止", english: "Recognition blocked"),
                statusDetail: L10n.choose(
                    simplifiedChinese: "当前机位尚未通过合规检查，因此还不能稳定识别骨点。",
                    english: "This view has not passed compliance, so stable keypoint recognition is blocked."
                ),
                confidenceText: "--",
                dropRateText: "--",
                occlusionHint: hint,
                problemFrameCountText: "--",
                computableIndicators: fallbackIndicators,
                angleVisuals: [],
                checkpointVisuals: [],
                playbackOverlay: nil,
                previewVideoURL: sourceURL,
                tone: .blocked
            )
        }

        guard let result else {
            return VideoFittingJointRecognitionQualitySummary(
                statusTitle: L10n.choose(simplifiedChinese: "待识别", english: "Waiting to recognize"),
                statusDetail: L10n.choose(
                    simplifiedChinese: "这个机位已经可以进入骨点识别，运行后会在这里持续显示质量结果。",
                    english: "This view is ready for skeleton recognition. Run it to persist quality feedback here."
                ),
                confidenceText: "--",
                dropRateText: "--",
                occlusionHint: L10n.choose(
                    simplifiedChinese: "建议先保证髋/膝/踝连续可见；如果衣物遮挡明显，可在关键关节加标记。",
                    english: "Keep hip/knee/ankle continuously visible; add markers if clothing causes occlusion."
                ),
                problemFrameCountText: "--",
                computableIndicators: fallbackIndicators,
                angleVisuals: [],
                checkpointVisuals: [],
                playbackOverlay: nil,
                previewVideoURL: sourceURL,
                tone: .pending
            )
        }

        let averageConfidence = result.samples.isEmpty
            ? 0
            : result.samples.map(\.confidence).reduce(0, +) / Double(result.samples.count)
        let strongRatio = result.samples.isEmpty
            ? 0
            : Double(result.samples.filter { $0.confidence >= 0.55 }.count) / Double(result.samples.count)
        let problemFrameCount = result.samples.filter { isProblemFrame($0, view: result.resolvedView) }.count
        let problemRatio = result.samples.isEmpty ? 0 : Double(problemFrameCount) / Double(result.samples.count)
        let dropRate = result.targetFrameCount > 0
            ? max(0, Double(result.targetFrameCount - result.analyzedFrameCount) / Double(result.targetFrameCount))
            : 0

        return VideoFittingJointRecognitionQualitySummary(
            statusTitle: L10n.choose(simplifiedChinese: "识别质量已生成", english: "Recognition quality ready"),
            statusDetail: L10n.choose(
                simplifiedChinese: "当前面板会持续保留本次识别的稳定性结果，便于判断是否值得继续看结论。",
                english: "This panel keeps the latest recognition stability result so you can judge whether downstream conclusions are reliable."
            ),
            confidenceText: L10n.choose(
                simplifiedChinese: "均值 \(String(format: "%.2f", averageConfidence)) · 高置信 \(String(format: "%.0f%%", strongRatio * 100))",
                english: "Avg \(String(format: "%.2f", averageConfidence)) · High-confidence \(String(format: "%.0f%%", strongRatio * 100))"
            ),
            dropRateText: String(format: "%.0f%%", dropRate * 100),
            occlusionHint: occlusionHint(result: result, problemRatio: problemRatio),
            problemFrameCountText: "\(problemFrameCount)",
            computableIndicators: computableIndicators(for: result),
            angleVisuals: angleVisuals(for: result),
            checkpointVisuals: checkpointVisuals(for: result),
            playbackOverlay: playbackOverlay(for: result),
            previewVideoURL: sourceURL,
            tone: .ready
        )
    }

    private static func isProblemFrame(_ sample: VideoJointAngleSample, view: CyclingCameraView) -> Bool {
        if sample.confidence < 0.55 {
            return true
        }

        switch view {
        case .side:
            if sample.kneeAngleDeg == nil || sample.hipAngleDeg == nil {
                return true
            }
            switch sample.side {
            case .left:
                return sample.leftHip == nil || sample.leftKnee == nil || sample.leftAnkle == nil
            case .right:
                return sample.rightHip == nil || sample.rightKnee == nil || sample.rightAnkle == nil
            case .unknown:
                return (sample.leftHip == nil || sample.leftKnee == nil || sample.leftAnkle == nil) &&
                    (sample.rightHip == nil || sample.rightKnee == nil || sample.rightAnkle == nil)
            }
        case .front:
            let coreMissing =
                sample.leftHip == nil || sample.leftKnee == nil || sample.leftAnkle == nil ||
                sample.rightHip == nil || sample.rightKnee == nil || sample.rightAnkle == nil
            let toesMissing = sample.leftToe == nil && sample.rightToe == nil
            return coreMissing || toesMissing
        case .rear:
            return sample.leftHip == nil || sample.leftKnee == nil || sample.leftAnkle == nil ||
                sample.rightHip == nil || sample.rightKnee == nil || sample.rightAnkle == nil
        case .auto:
            return false
        }
    }

    private static func occlusionHint(result: VideoJointAngleAnalysisResult, problemRatio: Double) -> String {
        if let hint = result.fittingHints.first(where: { hint in
            hint.localizedCaseInsensitiveContains("遮挡") ||
                hint.localizedCaseInsensitiveContains("marker") ||
                hint.localizedCaseInsensitiveContains("标记") ||
                hint.localizedCaseInsensitiveContains("toe")
        }) {
            return hint
        }

        if problemRatio >= 0.35 {
            return L10n.choose(
                simplifiedChinese: "问题帧占比较高，建议减少衣物/车架遮挡，并在髋、膝、踝或足尖加高对比标记。",
                english: "Problem frames are frequent. Reduce clothing/bike occlusion and add high-contrast markers on hip, knee, ankle, or toe."
            )
        }

        return L10n.choose(
            simplifiedChinese: "当前遮挡风险可控；如果仍出现局部漂移，可在关键关节补标记点提升稳定性。",
            english: "Occlusion looks manageable. If local drift remains, add markers on key joints to improve stability."
        )
    }

    private static func computableIndicators(for result: VideoJointAngleAnalysisResult) -> [String] {
        var indicators: [String] = []

        switch result.resolvedView {
        case .side:
            if result.kneeStats != nil { indicators.append(L10n.choose(simplifiedChinese: "膝关节角", english: "Knee angle")) }
            if result.hipStats != nil { indicators.append(L10n.choose(simplifiedChinese: "髋关节角", english: "Hip angle")) }
            if !result.sideCheckpoints.isEmpty { indicators.append(L10n.choose(simplifiedChinese: "0/3/6/9 点位", english: "0/3/6/9 checkpoints")) }
            if result.cadenceSummary != nil { indicators.append(L10n.choose(simplifiedChinese: "BDC / 座高建议", english: "BDC / saddle guidance")) }
        case .front:
            if result.frontAlignment != nil { indicators.append(L10n.choose(simplifiedChinese: "关节对位", english: "Joint alignment")) }
            if result.frontTrajectory != nil { indicators.append(L10n.choose(simplifiedChinese: "膝/踝/足尖轨迹", english: "Knee/ankle/toe trajectory")) }
            if result.frontAutoAssessment != nil { indicators.append(L10n.choose(simplifiedChinese: "前视自动判定", english: "Front auto assessment")) }
        case .rear:
            if result.rearPelvic != nil { indicators.append(L10n.choose(simplifiedChinese: "盆骨倾斜", english: "Pelvic tilt")) }
            if result.rearStability != nil { indicators.append(L10n.choose(simplifiedChinese: "重心漂移", english: "Center-of-mass drift")) }
            if result.rearCoordination != nil { indicators.append(L10n.choose(simplifiedChinese: "顺拐风险", english: "Crossover risk")) }
            if result.rearAutoAssessment != nil { indicators.append(L10n.choose(simplifiedChinese: "后视自动判定", english: "Rear auto assessment")) }
        case .auto:
            break
        }

        if indicators.isEmpty {
            return videoFittingSupportedConclusions(for: result.resolvedView)
        }
        return indicators
    }

    private static func angleVisuals(for result: VideoJointAngleAnalysisResult) -> [VideoFittingJointAngleVisualSummary] {
        var visuals: [VideoFittingJointAngleVisualSummary] = []

        if let kneeSample = representativeKneeSample(for: result),
           let kneeAngle = sanitizedAngle(kneeSample.kneeAngleDeg),
           let kneeTriplet = jointTriplet(for: kneeSample, side: result.dominantSide, kind: .knee) {
            visuals.append(
                VideoFittingJointAngleVisualSummary(
                    kind: .knee,
                    title: L10n.choose(simplifiedChinese: "膝关节角", english: "Knee Angle"),
                    subtitle: L10n.choose(simplifiedChinese: "代表帧", english: "Representative Frame"),
                    angleDegrees: kneeAngle,
                    detail: L10n.choose(
                        simplifiedChinese: "真实关键帧叠加髋-膝-踝连线，用于直观看膝关节开合。",
                        english: "Real keyframe with hip-knee-ankle overlay for direct knee-angle inspection."
                    ),
                    frameTimeSeconds: kneeSample.timeSeconds,
                    crankPhaseDegrees: kneeSample.crankPhaseDeg,
                    crankCenter: result.crankCenter.map(normalizedPoint),
                    crankRadius: result.crankRadius,
                    firstPoint: normalizedPoint(kneeTriplet.0),
                    jointPoint: normalizedPoint(kneeTriplet.1),
                    thirdPoint: normalizedPoint(kneeTriplet.2)
                )
            )
        }

        if let hipSample = representativeHipSample(for: result),
           let hipAngle = sanitizedAngle(hipSample.hipAngleDeg) {
            let hipTriplet = jointTriplet(for: hipSample, side: result.dominantSide, kind: .hip)
            visuals.append(
                VideoFittingJointAngleVisualSummary(
                    kind: .hip,
                    title: L10n.choose(simplifiedChinese: "髋关节角", english: "Hip Angle"),
                    subtitle: L10n.choose(simplifiedChinese: "代表帧", english: "Representative Frame"),
                    angleDegrees: hipAngle,
                    detail: L10n.choose(
                        simplifiedChinese: hipTriplet == nil
                            ? "已保留真实关键帧；若肩点不足，将先显示原始帧并等待更稳定的肩-髋-膝叠加。"
                            : "真实关键帧叠加肩-髋-膝连线，用于判断髋部折叠程度与上身打开状态。",
                        english: hipTriplet == nil
                            ? "Real keyframe kept; when shoulder points are unstable, the raw frame is shown until a shoulder-hip-knee overlay becomes available."
                            : "Real keyframe with shoulder-hip-knee overlay for hip closure and torso opening."
                    ),
                    frameTimeSeconds: hipSample.timeSeconds,
                    crankPhaseDegrees: hipSample.crankPhaseDeg,
                    crankCenter: result.crankCenter.map(normalizedPoint),
                    crankRadius: result.crankRadius,
                    firstPoint: hipTriplet.map { normalizedPoint($0.0) },
                    jointPoint: hipTriplet.map { normalizedPoint($0.1) },
                    thirdPoint: hipTriplet.map { normalizedPoint($0.2) }
                )
            )
        }

        if let bdcSample = representativeBDCSample(for: result),
           let bdcAngle = sanitizedAngle(bdcSample.kneeAngleDeg),
           let bdcTriplet = jointTriplet(for: bdcSample, side: result.dominantSide, kind: .knee) {
            visuals.append(
                VideoFittingJointAngleVisualSummary(
                    kind: .bdcKnee,
                    title: L10n.choose(simplifiedChinese: "BDC 膝角", english: "BDC Knee Angle"),
                    subtitle: L10n.choose(simplifiedChinese: "下止点关键帧", english: "BDC Keyframe"),
                    angleDegrees: bdcAngle,
                    detail: L10n.choose(
                        simplifiedChinese: "真实关键帧叠加下止点腿部连线，用于座高建议与伸展检查。",
                        english: "Real keyframe with bottom-dead-center leg overlay for saddle guidance and extension checks."
                    ),
                    frameTimeSeconds: bdcSample.timeSeconds,
                    crankPhaseDegrees: bdcSample.crankPhaseDeg,
                    crankCenter: result.crankCenter.map(normalizedPoint),
                    crankRadius: result.crankRadius,
                    firstPoint: normalizedPoint(bdcTriplet.0),
                    jointPoint: normalizedPoint(bdcTriplet.1),
                    thirdPoint: normalizedPoint(bdcTriplet.2)
                )
            )
        }

        return visuals
    }

    private static func checkpointVisuals(for result: VideoJointAngleAnalysisResult) -> [VideoFittingCheckpointVisualSummary] {
        guard result.resolvedView == .side else { return [] }

        return result.sideCheckpoints.compactMap { checkpoint in
            let sample = nearestSample(to: checkpoint.timeSeconds, in: result.samples)
            let triplet = sample.flatMap { jointTriplet(for: $0, side: result.dominantSide, kind: .knee) }
            return VideoFittingCheckpointVisualSummary(
                checkpoint: checkpoint.checkpoint,
                frameTimeSeconds: checkpoint.timeSeconds,
                phaseDegrees: checkpoint.phaseDeg,
                kneeAngleText: sanitizedAngle(checkpoint.kneeAngleDeg).map { String(format: "%.0f°", $0) } ?? "--",
                hipAngleText: sanitizedAngle(checkpoint.hipAngleDeg).map { String(format: "%.0f°", $0) } ?? "--",
                crankCenter: result.crankCenter.map(normalizedPoint),
                crankRadius: result.crankRadius,
                firstPoint: triplet.map { normalizedPoint($0.0) },
                jointPoint: triplet.map { normalizedPoint($0.1) },
                thirdPoint: triplet.map { normalizedPoint($0.2) }
            )
        }
    }

    private static func playbackOverlay(for result: VideoJointAngleAnalysisResult) -> VideoFittingPlaybackOverlaySummary? {
        guard result.resolvedView == .side else { return nil }

        let samples = result.samples.compactMap { sample -> VideoFittingPlaybackOverlaySample? in
            let triplet = jointTriplet(for: sample, side: result.dominantSide, kind: .knee)
            let kneeAngle = sanitizedAngle(sample.kneeAngleDeg)
            let hipAngle = sanitizedAngle(sample.hipAngleDeg)
            guard kneeAngle != nil || hipAngle != nil || triplet != nil else {
                return nil
            }

            return VideoFittingPlaybackOverlaySample(
                id: sample.id,
                timeSeconds: sample.timeSeconds,
                kneeAngleDegrees: kneeAngle,
                hipAngleDegrees: hipAngle,
                crankPhaseDegrees: sample.crankPhaseDeg,
                firstPoint: triplet.map { normalizedPoint($0.0) },
                jointPoint: triplet.map { normalizedPoint($0.1) },
                thirdPoint: triplet.map { normalizedPoint($0.2) },
                bodyBounds: bodyBounds(for: sample)
            )
        }

        guard !samples.isEmpty else { return nil }

        let checkpoints = result.sideCheckpoints.map { checkpoint in
            VideoFittingPlaybackCheckpointMarker(
                checkpoint: checkpoint.checkpoint,
                timeSeconds: checkpoint.timeSeconds,
                phaseDegrees: checkpoint.phaseDeg,
                kneeAngleText: sanitizedAngle(checkpoint.kneeAngleDeg).map { String(format: "%.0f°", $0) } ?? "--",
                hipAngleText: sanitizedAngle(checkpoint.hipAngleDeg).map { String(format: "%.0f°", $0) } ?? "--"
            )
        }

        return VideoFittingPlaybackOverlaySummary(
            samples: samples,
            checkpoints: checkpoints,
            crankCenter: result.crankCenter.map(normalizedPoint),
            crankRadius: result.crankRadius
        )
    }

    private static func representativeKneeSample(for result: VideoJointAngleAnalysisResult) -> VideoJointAngleSample? {
        let candidates = result.samples.filter {
            sanitizedAngle($0.kneeAngleDeg) != nil &&
                jointTriplet(for: $0, side: result.dominantSide, kind: .knee) != nil &&
                $0.confidence >= 0.55
        }
        guard !candidates.isEmpty else { return nil }
        guard let target = result.kneeStats?.mean else { return candidates.first }
        return candidates.min { lhs, rhs in
            let lhsDistance = abs((lhs.kneeAngleDeg ?? target) - target)
            let rhsDistance = abs((rhs.kneeAngleDeg ?? target) - target)
            return lhsDistance < rhsDistance
        }
    }

    private static func representativeBDCSample(for result: VideoJointAngleAnalysisResult) -> VideoJointAngleSample? {
        let candidates = result.samples.filter {
            sanitizedAngle($0.kneeAngleDeg) != nil &&
                $0.crankPhaseDeg != nil &&
                jointTriplet(for: $0, side: result.dominantSide, kind: .knee) != nil &&
                $0.confidence >= 0.55
        }
        guard !candidates.isEmpty else { return nil }
        return candidates.min { phaseDistance($0.crankPhaseDeg ?? 180, 180) < phaseDistance($1.crankPhaseDeg ?? 180, 180) }
    }

    private static func representativeHipSample(for result: VideoJointAngleAnalysisResult) -> VideoJointAngleSample? {
        let candidates = result.samples.filter {
            sanitizedAngle($0.hipAngleDeg) != nil &&
                $0.confidence >= 0.55
        }
        guard !candidates.isEmpty else { return nil }
        guard let target = result.hipStats?.mean else { return candidates.first }
        return candidates.min { lhs, rhs in
            let lhsDistance = abs((lhs.hipAngleDeg ?? target) - target)
            let rhsDistance = abs((rhs.hipAngleDeg ?? target) - target)
            return lhsDistance < rhsDistance
        }
    }

    private static func nearestSample(to timeSeconds: Double, in samples: [VideoJointAngleSample]) -> VideoJointAngleSample? {
        samples.min { abs($0.timeSeconds - timeSeconds) < abs($1.timeSeconds - timeSeconds) }
    }

    private static func phaseDistance(_ lhs: Double, _ rhs: Double) -> Double {
        let wrapped = abs(lhs - rhs).truncatingRemainder(dividingBy: 360)
        return min(wrapped, 360 - wrapped)
    }

    private static func sanitizedAngle(_ value: Double?) -> Double? {
        guard let value, value.isFinite else { return nil }
        return value
    }

    private static func jointTriplet(
        for sample: VideoJointAngleSample,
        side: VideoPoseBodySide,
        kind: VideoFittingJointTripletKind
    ) -> (PoseJointPoint, PoseJointPoint, PoseJointPoint)? {
        func triplet(shoulder: PoseJointPoint?, hip: PoseJointPoint?, knee: PoseJointPoint?, ankle: PoseJointPoint?) -> (PoseJointPoint, PoseJointPoint, PoseJointPoint)? {
            switch kind {
            case .knee:
                guard let hip, let knee, let ankle else { return nil }
                return (hip, knee, ankle)
            case .hip:
                guard let shoulder, let hip, let knee else { return nil }
                return (shoulder, hip, knee)
            }
        }

        switch side {
        case .left:
            return triplet(shoulder: sample.leftShoulder, hip: sample.leftHip, knee: sample.leftKnee, ankle: sample.leftAnkle)
        case .right:
            return triplet(shoulder: sample.rightShoulder, hip: sample.rightHip, knee: sample.rightKnee, ankle: sample.rightAnkle)
        case .unknown:
            if let left = triplet(shoulder: sample.leftShoulder, hip: sample.leftHip, knee: sample.leftKnee, ankle: sample.leftAnkle) {
                return left
            }
            return triplet(shoulder: sample.rightShoulder, hip: sample.rightHip, knee: sample.rightKnee, ankle: sample.rightAnkle)
        }
    }

    private static func normalizedPoint(_ point: PoseJointPoint) -> VideoFittingNormalizedPoint {
        VideoFittingNormalizedPoint(x: point.x, y: point.y)
    }

    private static func bodyBounds(for sample: VideoJointAngleSample) -> VideoFittingNormalizedRect? {
        let points = [
            sample.leftShoulder,
            sample.leftHip,
            sample.leftKnee,
            sample.leftAnkle,
            sample.rightShoulder,
            sample.rightHip,
            sample.rightKnee,
            sample.rightAnkle,
            sample.leftToe,
            sample.rightToe
        ].compactMap { $0 }.map(normalizedPoint)

        guard
            let minX = points.map(\.x).min(),
            let minY = points.map(\.y).min(),
            let maxX = points.map(\.x).max(),
            let maxY = points.map(\.y).max()
        else {
            return nil
        }

        return VideoFittingNormalizedRect(minX: minX, minY: minY, maxX: maxX, maxY: maxY)
    }
}

enum VideoFittingResultTab: String, CaseIterable, Identifiable {
    case overview
    case metrics
    case suggestions
    case evidence

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview:
            return L10n.choose(simplifiedChinese: "总览", english: "Overview")
        case .metrics:
            return L10n.choose(simplifiedChinese: "指标", english: "Metrics")
        case .suggestions:
            return L10n.choose(simplifiedChinese: "建议", english: "Suggestions")
        case .evidence:
            return L10n.choose(simplifiedChinese: "证据", english: "Evidence")
        }
    }
}

enum VideoFittingResultRiskTone: Equatable {
    case low
    case moderate
    case high
    case pending
}

struct VideoFittingResultOverviewSummary: Equatable {
    let headline: String
    let detail: String
    let riskTitle: String
    let riskDetail: String
    let availableConclusions: [String]
    let nextActions: [String]
    let tone: VideoFittingResultRiskTone
}

enum VideoFittingResultOverviewSummaryResolver {
    static func resolve(
        result: VideoJointAngleAnalysisResult?,
        qualitySummary: VideoFittingJointRecognitionQualitySummary,
        selectedView: CyclingCameraView
    ) -> VideoFittingResultOverviewSummary {
        guard let result else {
            return VideoFittingResultOverviewSummary(
                headline: L10n.choose(simplifiedChinese: "等待分析结果", english: "Awaiting analysis result"),
                detail: L10n.choose(
                    simplifiedChinese: "先完成合规检查与骨点识别，结果区会在这里汇总核心结论。",
                    english: "Complete compliance and skeleton recognition first. The result area will summarize core conclusions here."
                ),
                riskTitle: L10n.choose(simplifiedChinese: "当前风险", english: "Current Risk"),
                riskDetail: qualitySummary.statusDetail,
                availableConclusions: qualitySummary.computableIndicators,
                nextActions: [
                    nextActionForPendingResult(selectedView: selectedView, qualitySummary: qualitySummary)
                ],
                tone: .pending
            )
        }

        let conclusions = qualitySummary.computableIndicators.isEmpty
            ? videoFittingSupportedConclusions(for: result.resolvedView)
            : qualitySummary.computableIndicators

        switch result.resolvedView {
        case .front:
            let assessment = result.frontAutoAssessment
            let tone = riskTone(level: assessment?.riskLevel, fallbackProblemHint: qualitySummary.problemFrameCountText)
            let detail = result.frontTrajectory.map(frontTrajectoryResultSummary)
                ?? L10n.choose(
                    simplifiedChinese: "已完成前视角识别，可查看关节对位与轨迹结果。",
                    english: "Front-view recognition is ready. You can review alignment and trajectory findings."
                )
            let nextActions = assessment?.flags.isEmpty == false
                ? assessment?.flags ?? []
                : [qualitySummary.occlusionHint]
            return VideoFittingResultOverviewSummary(
                headline: L10n.choose(simplifiedChinese: "前视结论已生成", english: "Front-view conclusion ready"),
                detail: detail,
                riskTitle: riskTitle(for: tone),
                riskDetail: detail,
                availableConclusions: conclusions,
                nextActions: nextActions,
                tone: tone
            )
        case .side:
            let recommendation = result.cadenceSummary?.saddleHeightRecommendation
            let directionText = recommendation.map { saddleAdjustmentDirectionText($0.direction) }
            let detail: String
            if let recommendation, let directionText {
                detail = L10n.choose(
                    simplifiedChinese: "当前侧视结果显示 BDC 膝角均值 \(String(format: "%.1f°", recommendation.meanBDCKneeAngleDeg))，建议\(directionText)。",
                    english: "Current side-view result shows mean BDC knee angle \(String(format: "%.1f°", recommendation.meanBDCKneeAngleDeg)); recommended to \(directionText)."
                )
            } else {
                detail = L10n.choose(
                    simplifiedChinese: "已完成侧视角识别，可查看髋/膝角、BDC 与稳定性结果。",
                    english: "Side-view recognition is ready. You can review hip/knee angles, BDC, and stability outputs."
                )
            }
            let tone: VideoFittingResultRiskTone = {
                if !result.adjustmentPlan.isEmpty { return .moderate }
                if let long = result.longDurationStability,
                   abs(long.phaseDriftDegPerMin ?? 0) > 2.5 || abs(long.bdcKneeDriftDegPerMin ?? 0) > 1.6 {
                    return .high
                }
                return .low
            }()
            let nextActions = result.adjustmentPlan.prefix(3).map {
                L10n.choose(
                    simplifiedChinese: "\($0.title)：\($0.maxAdjustmentPerStep)；\($0.retestCondition)",
                    english: "\($0.title): \($0.maxAdjustmentPerStep); \($0.retestCondition)"
                )
            }
            return VideoFittingResultOverviewSummary(
                headline: L10n.choose(simplifiedChinese: "侧视结论已生成", english: "Side-view conclusion ready"),
                detail: detail,
                riskTitle: riskTitle(for: tone),
                riskDetail: qualitySummary.occlusionHint,
                availableConclusions: conclusions,
                nextActions: nextActions.isEmpty ? [qualitySummary.occlusionHint] : nextActions,
                tone: tone
            )
        case .rear:
            let assessment = result.rearAutoAssessment
            let tone = riskTone(level: assessment?.riskLevel, fallbackProblemHint: qualitySummary.problemFrameCountText)
            let detail = result.rearStability.map { rearStabilityResultSummary(stability: $0, pelvic: result.rearPelvic, coordination: result.rearCoordination) }
                ?? L10n.choose(
                    simplifiedChinese: "已完成后视角识别，可查看盆骨与重心稳定性结果。",
                    english: "Rear-view recognition is ready. You can review pelvic and stability outputs."
                )
            let nextActions = assessment?.flags.isEmpty == false
                ? assessment?.flags ?? []
                : [qualitySummary.occlusionHint]
            return VideoFittingResultOverviewSummary(
                headline: L10n.choose(simplifiedChinese: "后视结论已生成", english: "Rear-view conclusion ready"),
                detail: detail,
                riskTitle: riskTitle(for: tone),
                riskDetail: detail,
                availableConclusions: conclusions,
                nextActions: nextActions,
                tone: tone
            )
        case .auto:
            return VideoFittingResultOverviewSummary(
                headline: L10n.choose(simplifiedChinese: "等待机位结果", english: "Awaiting view result"),
                detail: qualitySummary.statusDetail,
                riskTitle: L10n.choose(simplifiedChinese: "当前风险", english: "Current Risk"),
                riskDetail: qualitySummary.occlusionHint,
                availableConclusions: conclusions,
                nextActions: [qualitySummary.occlusionHint],
                tone: .pending
            )
        }
    }

    private static func riskTone(level: FittingRiskLevel?, fallbackProblemHint: String) -> VideoFittingResultRiskTone {
        if let level {
            switch level {
            case .low:
                return .low
            case .moderate:
                return .moderate
            case .high:
                return .high
            }
        }
        return fallbackProblemHint == "0" ? .low : .moderate
    }

    private static func riskTitle(for tone: VideoFittingResultRiskTone) -> String {
        switch tone {
        case .low:
            return L10n.choose(simplifiedChinese: "风险较低", english: "Low risk")
        case .moderate:
            return L10n.choose(simplifiedChinese: "建议复核", english: "Review advised")
        case .high:
            return L10n.choose(simplifiedChinese: "高风险", english: "High risk")
        case .pending:
            return L10n.choose(simplifiedChinese: "待判断", english: "Pending")
        }
    }

    private static func nextActionForPendingResult(
        selectedView: CyclingCameraView,
        qualitySummary: VideoFittingJointRecognitionQualitySummary
    ) -> String {
        switch qualitySummary.tone {
        case .empty:
            return videoFittingMissingImpactText(for: selectedView)
        case .blocked:
            return qualitySummary.occlusionHint
        case .pending:
            return L10n.choose(
                simplifiedChinese: "先运行骨点识别，结果页会自动切到可读结论。",
                english: "Run skeleton recognition first, then this result page will switch to readable conclusions."
            )
        case .ready:
            return L10n.choose(
                simplifiedChinese: "结果已就绪，可切换到指标、建议与证据继续查看。",
                english: "Results are ready. Switch to Metrics, Suggestions, and Evidence for more detail."
            )
        }
    }
}

private func saddleAdjustmentDirectionText(_ direction: SaddleHeightAdjustmentDirection) -> String {
    switch direction {
    case .raise:
        return L10n.choose(simplifiedChinese: "升高座高", english: "raise saddle")
    case .lower:
        return L10n.choose(simplifiedChinese: "降低座高", english: "lower saddle")
    case .keep:
        return L10n.choose(
            simplifiedChinese: "保持当前座高（可微调）",
            english: "keep saddle height (fine-tune)"
        )
    }
}

private func frontTrajectoryResultSummary(_ trajectory: FrontTrajectoryStats) -> String {
    var flags: [String] = []
    if trajectory.kneeTrajectorySpanNorm > 0.36 {
        flags.append(L10n.choose(simplifiedChinese: "膝轨迹偏宽", english: "knee path too wide"))
    }
    if trajectory.ankleTrajectorySpanNorm > 0.28 {
        flags.append(L10n.choose(simplifiedChinese: "踝轨迹偏宽", english: "ankle path too wide"))
    }
    if let toeSpan = trajectory.toeTrajectorySpanNorm, toeSpan > 0.34 {
        flags.append(L10n.choose(simplifiedChinese: "足尖轨迹偏宽", english: "toe path too wide"))
    }
    if trajectory.kneeOverAnkleInRangeRatio < 0.70 {
        flags.append(L10n.choose(simplifiedChinese: "膝踝对位不稳定", english: "knee-ankle alignment unstable"))
    }
    if flags.isEmpty {
        return L10n.choose(
            simplifiedChinese: "前视图评估：膝-踝-足尖轨迹整体在合理范围内。",
            english: "Front-view assessment: knee-ankle-toe tracks are within a reasonable range."
        )
    }
    return L10n.choose(
        simplifiedChinese: "前视图评估：\(flags.joined(separator: "，"))。",
        english: "Front-view assessment: \(flags.joined(separator: ", "))."
    )
}

private func rearStabilityResultSummary(
    stability: RearStabilityStats,
    pelvic: RearPelvicStats?,
    coordination: PedalingCoordinationStats?
) -> String {
    var flags: [String] = []
    if let pelvic, pelvic.maxPelvicTiltDeg > 6.0 {
        flags.append(L10n.choose(simplifiedChinese: "盆骨倾斜偏大", english: "pelvic tilt too high"))
    }
    if stability.meanCenterShiftNorm > 0.10 {
        flags.append(L10n.choose(simplifiedChinese: "重心平均漂移偏大", english: "mean CoM drift too high"))
    }
    if stability.maxCenterShiftNorm > 0.22 {
        flags.append(L10n.choose(simplifiedChinese: "重心最大漂移偏大", english: "max CoM drift too high"))
    }
    if abs(stability.lateralBias) > 0.05 {
        flags.append(L10n.choose(simplifiedChinese: "重心左右偏置明显", english: "lateral CoM bias is noticeable"))
    }
    if coordination?.isShunGuaiSuspected == true {
        flags.append(L10n.choose(simplifiedChinese: "疑似顺拐", english: "possible shun-guai pattern"))
    }
    if flags.isEmpty {
        return L10n.choose(
            simplifiedChinese: "后视图评估：盆骨稳定、重心漂移控制良好，未见明显顺拐。",
            english: "Rear-view assessment: pelvic and CoM stability are good, with no obvious shun-guai."
        )
    }
    return L10n.choose(
        simplifiedChinese: "后视图评估：\(flags.joined(separator: "，"))。",
        english: "Rear-view assessment: \(flags.joined(separator: ", "))."
    )
}

enum VideoFittingSessionSummaryResolver {
    static func resolve(
        snapshot: VideoFittingWorkflowSnapshot,
        states: VideoFittingWorkflowStates,
        capabilityMatrix: VideoFittingCapabilityMatrix
    ) -> VideoFittingSessionSummary {
        let completionCount = completedStepCount(for: snapshot)
        let availableTitles = capabilityMatrix.statuses
            .filter(\.isAvailable)
            .map { $0.capability.title }

        let capabilitySummary = L10n.choose(
            simplifiedChinese: "当前可分析能力 \(capabilityMatrix.availableCount)/\(capabilityMatrix.statuses.count)",
            english: "Available analysis capability \(capabilityMatrix.availableCount)/\(capabilityMatrix.statuses.count)"
        )
        let progressText = L10n.choose(
            simplifiedChinese: "完成度 \(completionCount)/4",
            english: "Progress \(completionCount)/4"
        )

        if !snapshot.hasAnyAssignedView {
            return VideoFittingSessionSummary(
                tone: .empty,
                statusTitle: L10n.choose(simplifiedChinese: "空状态", english: "Empty"),
                statusDetail: L10n.choose(
                    simplifiedChinese: "还没有开始 fitting session。先为前 / 侧 / 后机位分配独立视频。",
                    english: "Fitting session has not started yet. Assign dedicated videos for front / side / rear first."
                ),
                progressText: progressText,
                completionRatio: 0,
                capabilitySummary: capabilitySummary,
                availableCapabilityTitles: availableTitles,
                nextActionTitle: L10n.choose(simplifiedChinese: "下一步：分配机位视频", english: "Next: assign view videos"),
                nextActionDetail: L10n.choose(
                    simplifiedChinese: "建议先补齐前视、侧视、后视视频，这样后续能一次得到完整结论。",
                    english: "Start by assigning front, side, and rear videos so the downstream workflow can produce a complete conclusion."
                )
            )
        }

        if !states.canRunPostCompliance {
            let statusDetail: String
            let nextActionTitle: String
            let nextActionDetail: String

            if snapshot.isComplianceRunning {
                statusDetail = L10n.choose(
                    simplifiedChinese: "机位已配置，正在执行视频合规检查。",
                    english: "View videos are assigned and the compliance check is running."
                )
                nextActionTitle = L10n.choose(simplifiedChinese: "下一步：等待合规结果", english: "Next: wait for compliance result")
                nextActionDetail = L10n.choose(
                    simplifiedChinese: "检查会验证畸变、光照、清晰度和骨骼对位；通过后才能进入分析。",
                    english: "The check validates distortion, lighting, sharpness, and skeleton alignment before analysis can continue."
                )
            } else if snapshot.complianceChecked && !snapshot.compliancePassed {
                statusDetail = L10n.choose(
                    simplifiedChinese: "已完成机位配置，但合规检查未通过，session 暂时阻塞。",
                    english: "View assignment is complete, but compliance failed and the session is currently blocked."
                )
                nextActionTitle = L10n.choose(simplifiedChinese: "下一步：按指令重拍", english: "Next: retake with guidance")
                nextActionDetail = L10n.choose(
                    simplifiedChinese: "根据合规失败提示修正机位、光照或遮挡，然后重新执行合规检查。",
                    english: "Fix camera position, lighting, or occlusion according to the failure guidance, then rerun compliance."
                )
            } else {
                statusDetail = L10n.choose(
                    simplifiedChinese: "机位已部分完成配置，当前进入合规检查前准备阶段。",
                    english: "View assignment is partially complete and the session is ready for compliance preparation."
                )
                nextActionTitle = L10n.choose(simplifiedChinese: "下一步：执行合规检查", english: "Next: run compliance check")
                nextActionDetail = L10n.choose(
                    simplifiedChinese: "先检查视频是否满足畸变、骨骼对位和光照要求，再进入骨骼识别。",
                    english: "Run the compliance check for distortion, skeleton alignment, and lighting before joint recognition."
                )
            }

            return VideoFittingSessionSummary(
                tone: .partial,
                statusTitle: L10n.choose(simplifiedChinese: "部分完成", english: "Partially complete"),
                statusDetail: statusDetail,
                progressText: progressText,
                completionRatio: Double(completionCount) / 4.0,
                capabilitySummary: capabilitySummary,
                availableCapabilityTitles: availableTitles,
                nextActionTitle: nextActionTitle,
                nextActionDetail: nextActionDetail
            )
        }

        if snapshot.hasRecognitionResults {
            return VideoFittingSessionSummary(
                tone: .ready,
                statusTitle: L10n.choose(simplifiedChinese: "可输出结论", english: "Results ready"),
                statusDetail: L10n.choose(
                    simplifiedChinese: "session 已通过合规并产出分析结果，可以查看结论、补齐机位或导出报告。",
                    english: "The session passed compliance and already has analysis results. You can review conclusions, fill missing views, or export reports."
                ),
                progressText: progressText,
                completionRatio: Double(completionCount) / 4.0,
                capabilitySummary: capabilitySummary,
                availableCapabilityTitles: availableTitles,
                nextActionTitle: L10n.choose(simplifiedChinese: "下一步：查看结果或导出报告", english: "Next: review or export"),
                nextActionDetail: L10n.choose(
                    simplifiedChinese: "先查看当前可输出结论；如果想得到完整结论，再补齐缺失机位后重新分析。",
                    english: "Review the available conclusions first. If you want complete coverage, add missing views and rerun analysis."
                )
            )
        }

        return VideoFittingSessionSummary(
            tone: .ready,
            statusTitle: L10n.choose(simplifiedChinese: "可开始分析", english: "Ready to analyze"),
            statusDetail: L10n.choose(
                simplifiedChinese: "机位与合规检查都已就绪，当前可以开始识别骨骼关节并生成结论。",
                english: "View assignment and compliance are ready. Joint recognition can start now."
            ),
            progressText: progressText,
            completionRatio: Double(completionCount) / 4.0,
            capabilitySummary: capabilitySummary,
            availableCapabilityTitles: availableTitles,
            nextActionTitle: L10n.choose(simplifiedChinese: "下一步：开始骨骼识别", english: "Next: start joint recognition"),
            nextActionDetail: L10n.choose(
                simplifiedChinese: "建议先跑当前视角识别验证稳定性，再执行全部机位分析。",
                english: "Run recognition on the current view first to confirm tracking stability, then analyze all views."
            )
        )
    }

    private static func completedStepCount(for snapshot: VideoFittingWorkflowSnapshot) -> Int {
        var completed = 0
        if snapshot.hasAnyAssignedView {
            completed += 1
        }
        if snapshot.complianceChecked && snapshot.compliancePassed {
            completed += 1
        }
        if snapshot.hasRecognitionResults {
            completed += 2
        }
        return min(completed, 4)
    }
}

enum VideoCaptureQualityGrade: String {
    case excellent
    case good
    case acceptable
    case rejected

    var label: String {
        switch self {
        case .excellent:
            return L10n.choose(simplifiedChinese: "优秀", english: "Excellent")
        case .good:
            return L10n.choose(simplifiedChinese: "良好", english: "Good")
        case .acceptable:
            return L10n.choose(simplifiedChinese: "可用", english: "Acceptable")
        case .rejected:
            return L10n.choose(simplifiedChinese: "拒绝", english: "Rejected")
        }
    }
}

enum VideoCaptureQualityFailure: String, Equatable {
    case missingFrameRate
    case lowFrameRate
    case missingLuma
    case lowLuma
    case missingSharpness
    case lowSharpness
    case missingOcclusion
    case highOcclusion
    case missingDistortion
    case highDistortion
    case missingSkeletonAlignability
    case lowSkeletonAlignability

    var reason: String {
        switch self {
        case .missingFrameRate:
            return L10n.choose(simplifiedChinese: "无法读取帧率", english: "Frame rate unavailable")
        case .lowFrameRate:
            return L10n.choose(simplifiedChinese: "帧率过低", english: "Frame rate too low")
        case .missingLuma:
            return L10n.choose(simplifiedChinese: "无法评估光照", english: "Lighting signal unavailable")
        case .lowLuma:
            return L10n.choose(simplifiedChinese: "光照不足", english: "Lighting too low")
        case .missingSharpness:
            return L10n.choose(simplifiedChinese: "无法评估清晰度", english: "Sharpness signal unavailable")
        case .lowSharpness:
            return L10n.choose(simplifiedChinese: "画面模糊", english: "Image too blurry")
        case .missingOcclusion:
            return L10n.choose(simplifiedChinese: "无法评估遮挡", english: "Occlusion signal unavailable")
        case .highOcclusion:
            return L10n.choose(simplifiedChinese: "遮挡过多", english: "Occlusion too high")
        case .missingDistortion:
            return L10n.choose(simplifiedChinese: "无法评估畸变", english: "Distortion signal unavailable")
        case .highDistortion:
            return L10n.choose(simplifiedChinese: "畸变风险高", english: "Distortion risk too high")
        case .missingSkeletonAlignability:
            return L10n.choose(simplifiedChinese: "无法评估骨骼对位", english: "Skeleton alignment signal unavailable")
        case .lowSkeletonAlignability:
            return L10n.choose(simplifiedChinese: "骨骼对位不稳定", english: "Skeleton alignment unstable")
        }
    }

    var recoveryCategory: VideoFittingFailureCategory {
        switch self {
        case .missingFrameRate, .lowFrameRate, .missingSharpness, .lowSharpness:
            return .stability
        case .missingLuma, .lowLuma:
            return .lighting
        case .missingOcclusion, .highOcclusion:
            return .visibility
        case .missingDistortion, .highDistortion:
            return .cameraPlacement
        case .missingSkeletonAlignability, .lowSkeletonAlignability:
            return .landmarks
        }
    }

    var tip: String {
        switch self {
        case .missingFrameRate:
            return L10n.choose(
                simplifiedChinese: "无法读取帧率，请重新导出原始视频后重试。",
                english: "Frame rate is unavailable. Re-export the original video and retry."
            )
        case .lowFrameRate:
            return L10n.choose(
                simplifiedChinese: "帧率过低（建议 60fps，最低 30fps）。",
                english: "Frame rate is too low (target 60fps, minimum 30fps)."
            )
        case .missingLuma:
            return L10n.choose(
                simplifiedChinese: "无法评估光照，请保证画面稳定并提供前侧补光。",
                english: "Luma signal unavailable. Stabilize shot and add front/side lighting."
            )
        case .lowLuma:
            return L10n.choose(
                simplifiedChinese: "光照不足（提升前侧光，避免逆光）。",
                english: "Lighting is insufficient (add front/side light and avoid backlight)."
            )
        case .missingSharpness:
            return L10n.choose(
                simplifiedChinese: "无法评估清晰度，请固定机位并避免数码缩放。",
                english: "Sharpness signal unavailable. Stabilize camera and avoid digital zoom."
            )
        case .lowSharpness:
            return L10n.choose(
                simplifiedChinese: "画面模糊（提高快门、锁焦并固定机位）。",
                english: "Image is blurry (increase shutter speed, lock focus, stabilize camera)."
            )
        case .missingOcclusion:
            return L10n.choose(
                simplifiedChinese: "无法评估遮挡，请确保髋-膝-踝可连续可见。",
                english: "Occlusion signal unavailable. Keep hip-knee-ankle continuously visible."
            )
        case .highOcclusion:
            return L10n.choose(
                simplifiedChinese: "遮挡过多（避免衣物遮挡与器材遮挡）。",
                english: "Occlusion is too high (reduce clothing/equipment occlusion)."
            )
        case .missingDistortion:
            return L10n.choose(
                simplifiedChinese: "无法评估畸变，请避免超广角并保持机位正对。",
                english: "Distortion signal unavailable. Avoid ultra-wide lens and align camera plane."
            )
        case .highDistortion:
            return L10n.choose(
                simplifiedChinese: "画面畸变风险高（请远离超广角并让车身中轴居中）。",
                english: "Distortion risk is high (avoid ultra-wide lens and center bike axis)."
            )
        case .missingSkeletonAlignability:
            return L10n.choose(
                simplifiedChinese: "无法稳定识别骨骼关键点（建议贴身衣物并加髋/膝/踝标记）。",
                english: "Skeleton alignment signal unavailable (wear tighter clothing and add hip/knee/ankle markers)."
            )
        case .lowSkeletonAlignability:
            return L10n.choose(
                simplifiedChinese: "骨骼对位识别不稳定（建议加标记点并重拍）。",
                english: "Skeleton alignment is unstable (add marker points and retake)."
            )
        }
    }
}

struct VideoCaptureQualityMetrics: Equatable {
    let fps: Double
    let luma: Double?
    let sharpness: Double?
    let occlusionRatio: Double?
    let distortionRisk: Double?
    let skeletonAlignability: Double?
}

struct VideoCaptureQualityGateResult: Equatable {
    let passed: Bool
    let score: Double
    let grade: VideoCaptureQualityGrade
    let failures: [VideoCaptureQualityFailure]

    var failureTips: [String] {
        failures.map(\.tip)
    }
}

struct VideoCaptureQualityGatePolicy {
    let minFPS: Double
    let minLuma: Double
    let minSharpness: Double
    let maxOcclusionRatio: Double
    let maxDistortionRisk: Double
    let minSkeletonAlignability: Double

    static let `default` = VideoCaptureQualityGatePolicy(
        minFPS: 30,
        minLuma: 0.28,
        minSharpness: 0.055,
        maxOcclusionRatio: 0.38,
        maxDistortionRisk: 0.34,
        minSkeletonAlignability: 0.62
    )

    func evaluate(_ metrics: VideoCaptureQualityMetrics) -> VideoCaptureQualityGateResult {
        var failures: [VideoCaptureQualityFailure] = []
        let effectiveSharpnessFloor = effectiveMinSharpness(for: metrics)

        if !metrics.fps.isFinite || metrics.fps <= 0 {
            failures.append(.missingFrameRate)
        } else if metrics.fps < minFPS {
            failures.append(.lowFrameRate)
        }

        if let luma = metrics.luma {
            if luma < minLuma {
                failures.append(.lowLuma)
            }
        } else {
            failures.append(.missingLuma)
        }

        if let sharpness = metrics.sharpness {
            if sharpness < effectiveSharpnessFloor {
                failures.append(.lowSharpness)
            }
        } else {
            failures.append(.missingSharpness)
        }

        if let occlusion = metrics.occlusionRatio {
            if occlusion > maxOcclusionRatio {
                failures.append(.highOcclusion)
            }
        } else {
            failures.append(.missingOcclusion)
        }

        if let distortion = metrics.distortionRisk {
            if distortion > maxDistortionRisk {
                failures.append(.highDistortion)
            }
        } else {
            failures.append(.missingDistortion)
        }

        if let alignability = metrics.skeletonAlignability {
            if alignability < minSkeletonAlignability {
                failures.append(.lowSkeletonAlignability)
            }
        } else {
            failures.append(.missingSkeletonAlignability)
        }

        let score = qualityScore(metrics)
        let passed = failures.isEmpty

        let grade: VideoCaptureQualityGrade
        if !passed {
            grade = .rejected
        } else if score >= 0.86 {
            grade = .excellent
        } else if score >= 0.72 {
            grade = .good
        } else {
            grade = .acceptable
        }

        return VideoCaptureQualityGateResult(
            passed: passed,
            score: score,
            grade: grade,
            failures: failures
        )
    }

    private func qualityScore(_ metrics: VideoCaptureQualityMetrics) -> Double {
        let effectiveSharpnessFloor = effectiveMinSharpness(for: metrics)
        let fpsScore: Double = {
            guard metrics.fps.isFinite, metrics.fps > 0 else { return 0 }
            return clamp(metrics.fps / 60.0)
        }()
        let lumaScore = normalized(metrics.luma, goodLow: minLuma, goodHigh: 0.48)
        let sharpnessScore = normalized(metrics.sharpness, goodLow: effectiveSharpnessFloor, goodHigh: max(0.12, effectiveSharpnessFloor + 0.04))
        let occlusionScore = inverseNormalized(metrics.occlusionRatio, goodLow: 0.0, goodHigh: maxOcclusionRatio)
        let distortionScore = inverseNormalized(metrics.distortionRisk, goodLow: 0.0, goodHigh: maxDistortionRisk)
        let alignScore = normalized(metrics.skeletonAlignability, goodLow: minSkeletonAlignability, goodHigh: 0.95)

        let weighted =
            fpsScore * 0.15 +
            lumaScore * 0.15 +
            sharpnessScore * 0.15 +
            occlusionScore * 0.2 +
            distortionScore * 0.15 +
            alignScore * 0.2

        return clamp(weighted)
    }

    private func normalized(_ value: Double?, goodLow: Double, goodHigh: Double) -> Double {
        guard let value, value.isFinite else { return 0 }
        guard goodHigh > goodLow else { return 0 }
        return clamp((value - goodLow) / (goodHigh - goodLow))
    }

    private func effectiveMinSharpness(for metrics: VideoCaptureQualityMetrics) -> Double {
        let hasStrongTracking = (metrics.skeletonAlignability ?? 0) >= 0.9
        let hasLowOcclusion = (metrics.occlusionRatio ?? 1) <= 0.08
        let hasHealthyLuma = (metrics.luma ?? 0) >= 0.4
        let isHighFrameRate = metrics.fps >= 120
        if isHighFrameRate && hasStrongTracking && hasLowOcclusion && hasHealthyLuma {
            return 0.01
        }
        return minSharpness
    }

    private func inverseNormalized(_ value: Double?, goodLow: Double, goodHigh: Double) -> Double {
        guard let value, value.isFinite else { return 0 }
        guard goodHigh > goodLow else { return 0 }
        return clamp((goodHigh - value) / (goodHigh - goodLow))
    }

    private func clamp(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }
}
