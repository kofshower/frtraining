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
            if sharpness < minSharpness {
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
        let fpsScore: Double = {
            guard metrics.fps.isFinite, metrics.fps > 0 else { return 0 }
            return clamp(metrics.fps / 60.0)
        }()
        let lumaScore = normalized(metrics.luma, goodLow: minLuma, goodHigh: 0.48)
        let sharpnessScore = normalized(metrics.sharpness, goodLow: minSharpness, goodHigh: 0.12)
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
        guard let value else { return 0 }
        guard goodHigh > goodLow else { return 0 }
        return clamp((value - goodLow) / (goodHigh - goodLow))
    }

    private func inverseNormalized(_ value: Double?, goodLow: Double, goodHigh: Double) -> Double {
        guard let value else { return 0 }
        guard goodHigh > goodLow else { return 0 }
        return clamp((goodHigh - value) / (goodHigh - goodLow))
    }

    private func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}
