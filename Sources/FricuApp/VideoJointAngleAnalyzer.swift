import AVFoundation
import CoreGraphics
import Foundation
import simd
import Vision

enum VideoJointAngleAnalysisError: LocalizedError {
    case noVideoTrack
    case emptyVideo
    case noPoseDetected

    var errorDescription: String? {
        switch self {
        case .noVideoTrack:
            return L10n.choose(simplifiedChinese: "未检测到视频轨道。", english: "No video track found.")
        case .emptyVideo:
            return L10n.choose(simplifiedChinese: "视频时长无效。", english: "Video duration is invalid.")
        case .noPoseDetected:
            return L10n.choose(
                simplifiedChinese: "未检测到可用人体姿态，请确保画面有人体全身或下肢。",
                english: "No usable body pose detected. Ensure the rider is visible in frame."
            )
        }
    }
}

enum VideoPoseEstimationModel: String, CaseIterable, Identifiable {
    case auto
    case mediaPipeBlazePoseGHUM
    case appleVision

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .auto:
            return L10n.choose(simplifiedChinese: "自动（优先 BlazePose GHUM）", english: "Auto (prefer BlazePose GHUM)")
        case .mediaPipeBlazePoseGHUM:
            return L10n.choose(simplifiedChinese: "BlazePose GHUM（GitHub/MediaPipe）", english: "BlazePose GHUM (GitHub/MediaPipe)")
        case .appleVision:
            return L10n.choose(simplifiedChinese: "Apple Vision 3D/2D", english: "Apple Vision 3D/2D")
        }
    }
}

enum VideoPoseBodySide: String {
    case left
    case right
    case unknown

    var displayName: String {
        switch self {
        case .left:
            return L10n.choose(simplifiedChinese: "左侧", english: "Left")
        case .right:
            return L10n.choose(simplifiedChinese: "右侧", english: "Right")
        case .unknown:
            return L10n.choose(simplifiedChinese: "未知", english: "Unknown")
        }
    }
}

enum CyclingCameraView: String, CaseIterable, Identifiable {
    case auto
    case front
    case side
    case rear

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .auto:
            return L10n.choose(simplifiedChinese: "自动识别", english: "Auto")
        case .front:
            return L10n.choose(simplifiedChinese: "前视角", english: "Front")
        case .side:
            return L10n.choose(simplifiedChinese: "侧视角", english: "Side")
        case .rear:
            return L10n.choose(simplifiedChinese: "后视角", english: "Rear")
        }
    }
}

enum CrankClockCheckpoint: String, CaseIterable, Identifiable {
    case point0
    case point3
    case point9
    case point12

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .point0: return "0"
        case .point3: return "3"
        case .point9: return "9"
        case .point12: return "12"
        }
    }

    // 12 点=0°，3 点=90°，0 点(近似 6 点) 180°，9 点=270°。
    var targetPhaseDeg: Double {
        switch self {
        case .point12: return 0
        case .point3: return 90
        case .point0: return 180
        case .point9: return 270
        }
    }
}

struct PoseJointPoint {
    let x: Double
    let y: Double
    let confidence: Double

    var cgPoint: CGPoint {
        CGPoint(x: x, y: y)
    }
}

struct JointAngleStats {
    let min: Double
    let max: Double
    let mean: Double
    let sampleCount: Int
}

struct SideCheckpointSnapshot: Identifiable {
    let checkpoint: CrankClockCheckpoint
    let timeSeconds: Double
    let phaseDeg: Double
    let phaseErrorDeg: Double
    let kneeAngleDeg: Double?
    let hipAngleDeg: Double?

    var id: String { checkpoint.rawValue }
}

enum SaddleHeightAdjustmentDirection {
    case raise
    case lower
    case keep
}

struct SaddleHeightRecommendation {
    let targetKneeAngleMinDeg: Double
    let targetKneeAngleMaxDeg: Double
    let meanBDCKneeAngleDeg: Double
    let direction: SaddleHeightAdjustmentDirection
    let suggestedAdjustmentMinMM: Double
    let suggestedAdjustmentMaxMM: Double
}

struct CadenceCycleSegment: Identifiable {
    let id: Int
    let startTimeSeconds: Double
    let endTimeSeconds: Double
    let durationSeconds: Double
    let cadenceRPM: Double
    let bdcTimeSeconds: Double?
    let bdcPhaseDeg: Double?
    let bdcKneeAngleDeg: Double?
}

struct CadenceCycleSummary {
    let cycleCount: Int
    let meanCadenceRPM: Double
    let minCadenceRPM: Double
    let maxCadenceRPM: Double
    let bdcKneeStats: JointAngleStats?
    let saddleHeightRecommendation: SaddleHeightRecommendation?
}

struct LongDurationStabilityStats {
    let windowStartSeconds: Double
    let windowEndSeconds: Double
    let analyzedDurationSeconds: Double
    let cycleCount: Int
    let meanCadenceRPM: Double?
    let cadenceDriftRPMPerMin: Double?
    let meanBDCPhaseErrorDeg: Double?
    let phaseDriftDegPerMin: Double?
    let meanBDCKneeAngleDeg: Double?
    let earlyBDCKneeAngleDeg: Double?
    let lateBDCKneeAngleDeg: Double?
    let bdcKneeDriftDegPerMin: Double?
    let earlyKneeAngleDeg: Double?
    let lateKneeAngleDeg: Double?
    let earlyHipAngleDeg: Double?
    let lateHipAngleDeg: Double?
}

struct FrontAlignmentStats {
    let meanKneeFootOffset: Double
    let maxKneeFootOffset: Double
    let kneeTrackAsymmetry: Double
    let hipKneeWidthRatio: Double
    let sampleCount: Int
}

struct FrontTrajectoryStats {
    let kneeTrajectorySpanNorm: Double
    let ankleTrajectorySpanNorm: Double
    let toeTrajectorySpanNorm: Double?
    let kneeOverAnkleInRangeRatio: Double
    let sampleCount: Int
}

struct RearPelvicStats {
    let meanPelvicTiltDeg: Double
    let maxPelvicTiltDeg: Double
    let leftHipDropRatio: Double
    let sampleCount: Int
}

struct RearStabilityStats {
    let meanCenterShiftNorm: Double
    let maxCenterShiftNorm: Double
    let lateralBias: Double
    let sampleCount: Int
}

struct PedalingCoordinationStats {
    let kneeLateralCorrelation: Double
    let isShunGuaiSuspected: Bool
    let sampleCount: Int
}

enum FittingRiskLevel {
    case low
    case moderate
    case high
}

struct FrontTrajectoryAssessment {
    let riskLevel: FittingRiskLevel
    let riskScore: Double
    let kneeSpanNorm: Double
    let ankleSpanNorm: Double
    let toeSpanNorm: Double?
    let inRangeRatio: Double
    let kneeTrackAsymmetry: Double?
    let kneeRangeMinNorm: Double
    let kneeRangeMaxNorm: Double
    let ankleRangeMinNorm: Double
    let ankleRangeMaxNorm: Double
    let toeRangeMinNorm: Double
    let toeRangeMaxNorm: Double
    let inRangeRatioMin: Double
    let asymmetryMax: Double
    let kneeSpanInRange: Bool
    let ankleSpanInRange: Bool
    let toeSpanInRange: Bool?
    let inRangeRatioPass: Bool
    let asymmetryPass: Bool?
    let flags: [String]
}

struct RearStabilityAssessment {
    let riskLevel: FittingRiskLevel
    let riskScore: Double
    let meanPelvicTiltDeg: Double?
    let maxPelvicTiltDeg: Double?
    let meanCenterShiftNorm: Double
    let maxCenterShiftNorm: Double
    let lateralBias: Double
    let kneeLateralCorrelation: Double?
    let isShunGuaiSuspected: Bool
    let meanPelvicTiltThresholdDeg: Double
    let maxPelvicTiltThresholdDeg: Double
    let meanCenterShiftThreshold: Double
    let maxCenterShiftThreshold: Double
    let lateralBiasThreshold: Double
    let shunGuaiCorrelationThreshold: Double
    let meanPelvicPass: Bool?
    let maxPelvicPass: Bool?
    let meanCenterShiftPass: Bool
    let maxCenterShiftPass: Bool
    let lateralBiasPass: Bool
    let shunGuaiPass: Bool
    let flags: [String]
}

enum BikeFitAdjustmentDomain: String {
    case capture
    case saddleHeight
    case saddleForeAft
    case cleatAndStance
    case pelvicAndCore
    case baseline
}

struct BikeFitAdjustmentStep: Identifiable {
    let priority: Int
    let domain: BikeFitAdjustmentDomain
    let title: String
    let impactScore: Double
    let rationale: String
    let maxAdjustmentPerStep: String
    let retestCondition: String
    let successCriteria: String

    var id: String {
        "\(priority)-\(domain.rawValue)-\(title)"
    }
}

struct VideoJointAngleSample: Identifiable {
    let id: Int
    let timeSeconds: Double
    let side: VideoPoseBodySide
    let confidence: Double
    let kneeAngleDeg: Double?
    let hipAngleDeg: Double?
    let crankPhaseDeg: Double?

    let leftHip: PoseJointPoint?
    let leftKnee: PoseJointPoint?
    let leftAnkle: PoseJointPoint?
    let rightHip: PoseJointPoint?
    let rightKnee: PoseJointPoint?
    let rightAnkle: PoseJointPoint?
    let leftToe: PoseJointPoint?
    let rightToe: PoseJointPoint?
}

struct VideoJointAngleAnalysisResult {
    let durationSeconds: Double
    let targetFrameCount: Int
    let analyzedFrameCount: Int
    let requestedView: CyclingCameraView
    let resolvedView: CyclingCameraView
    let modelUsed: VideoPoseEstimationModel
    let modelFallbackNote: String?
    let dominantSide: VideoPoseBodySide
    let samples: [VideoJointAngleSample]
    let used3DAngleFrameCount: Int
    let kneeStats: JointAngleStats?
    let hipStats: JointAngleStats?
    let cadenceCycles: [CadenceCycleSegment]
    let cadenceSummary: CadenceCycleSummary?
    let longDurationStability: LongDurationStabilityStats?
    let sideCheckpoints: [SideCheckpointSnapshot]
    let frontAlignment: FrontAlignmentStats?
    let frontTrajectory: FrontTrajectoryStats?
    let rearPelvic: RearPelvicStats?
    let rearStability: RearStabilityStats?
    let rearCoordination: PedalingCoordinationStats?
    let frontAutoAssessment: FrontTrajectoryAssessment?
    let rearAutoAssessment: RearStabilityAssessment?
    let adjustmentPlan: [BikeFitAdjustmentStep]
    let fittingHints: [String]
}

struct VideoJointAngleAnalyzer {
    private static let minJointConfidence: Float = 0.2

    func analyze(
        videoURL: URL,
        maxSamples: Int = 180,
        requestedView: CyclingCameraView = .side,
        preferredModel: VideoPoseEstimationModel = .auto
    ) async throws -> VideoJointAngleAnalysisResult {
        try await Task.detached(priority: .utility) {
            let asset = AVURLAsset(url: videoURL)
            let durationTime = try await asset.load(.duration)
            let durationSeconds = CMTimeGetSeconds(durationTime)
            guard durationSeconds.isFinite, durationSeconds > 0 else {
                throw VideoJointAngleAnalysisError.emptyVideo
            }

            let tracks = try await asset.loadTracks(withMediaType: .video)
            guard let videoTrack = tracks.first else {
                throw VideoJointAngleAnalysisError.noVideoTrack
            }

            let nominalFPS = max(1.0, Double(try await videoTrack.load(.nominalFrameRate)))
            let preferredSampleCount = max(24, min(maxSamples, 720))
            let estimatedFrameCount = max(1, Int((durationSeconds * nominalFPS).rounded()))
            let targetFrameCount = max(1, min(preferredSampleCount, estimatedFrameCount))
            let interval = durationSeconds / Double(targetFrameCount)

            var samples: [VideoJointAngleSample] = []
            samples.reserveCapacity(targetFrameCount)
            var modelUsed: VideoPoseEstimationModel = .appleVision
            var modelFallbackNote: String?
            var modelRuntimeHints: [String] = []
            var used3DAngleFrameCount = 0

            if preferredModel != .appleVision {
                if let mediaPipeResult = try? MediaPipePoseEstimator.sampleVideo(
                    videoURL: videoURL,
                    maxSamples: targetFrameCount
                ), !mediaPipeResult.samples.isEmpty {
                    samples = mediaPipeResult.samples
                    modelRuntimeHints = mediaPipeResult.warnings
                    modelUsed = .mediaPipeBlazePoseGHUM
                } else if preferredModel == .mediaPipeBlazePoseGHUM {
                    modelFallbackNote = L10n.choose(
                        simplifiedChinese: "BlazePose GHUM 不可用，已回退到 Apple Vision。",
                        english: "BlazePose GHUM is unavailable. Fell back to Apple Vision."
                    )
                }
            }

            if samples.isEmpty {
                let generator = AVAssetImageGenerator(asset: asset)
                generator.appliesPreferredTrackTransform = true
                generator.requestedTimeToleranceAfter = .zero
                generator.requestedTimeToleranceBefore = .zero

                let pose2DRequest = VNDetectHumanBodyPoseRequest()
                var pose3DRequest: VNDetectHumanBodyPose3DRequest?
                if #available(macOS 14.0, iOS 17.0, tvOS 17.0, *) {
                    pose3DRequest = VNDetectHumanBodyPose3DRequest()
                }

                for index in 0..<targetFrameCount {
                    let rawSecond = min(durationSeconds, Double(index) * interval)
                    let time = CMTime(seconds: rawSecond, preferredTimescale: 600)
                    let image: CGImage
                    do {
                        image = try generator.copyCGImage(at: time, actualTime: nil)
                    } catch {
                        continue
                    }

                    let handler = VNImageRequestHandler(cgImage: image, options: [:])
                    var observation2D: VNHumanBodyPoseObservation?
                    do {
                        try handler.perform([pose2DRequest])
                        observation2D = pose2DRequest.results?.first
                    } catch {
                        observation2D = nil
                    }

                    var observation3D: VNHumanBodyPose3DObservation?
                    if let pose3DRequest {
                        do {
                            try handler.perform([pose3DRequest])
                            observation3D = pose3DRequest.results?.first
                        } catch {
                            observation3D = nil
                        }
                    }

                    guard let extracted = Self.sampleFromObservations(
                        observation2D: observation2D,
                        observation3D: observation3D,
                        sampleIndex: index,
                        timeSeconds: rawSecond
                    ) else {
                        continue
                    }
                    samples.append(extracted.sample)
                    if extracted.used3D {
                        used3DAngleFrameCount += 1
                    }
                }
                modelUsed = .appleVision
            }

            guard !samples.isEmpty else {
                throw VideoJointAngleAnalysisError.noPoseDetected
            }

            let dominantSide = Self.dominantSide(from: samples)
            let resolvedView = Self.resolveView(requested: requestedView, from: samples)

            let kneeStats = Self.stats(for: samples.compactMap(\.kneeAngleDeg))
            let hipStats = Self.stats(for: samples.compactMap(\.hipAngleDeg))
            let cadenceCycles = Self.extractCadenceCycles(samples: samples)
            let cadenceSummary = Self.summarizeCadenceCycles(cadenceCycles)
            let longDurationStability = Self.extractLongDurationStability(
                samples: samples,
                cycles: cadenceCycles,
                durationSeconds: durationSeconds
            )
            let sideCheckpoints = resolvedView == .side
                ? Self.extractSideCheckpoints(samples: samples)
                : []
            let frontAlignment = resolvedView == .front
                ? Self.extractFrontAlignment(samples: samples)
                : nil
            let frontTrajectory = resolvedView == .front
                ? Self.extractFrontTrajectory(samples: samples)
                : nil
            let rearPelvic = resolvedView == .rear
                ? Self.extractRearPelvic(samples: samples)
                : nil
            let rearStability = resolvedView == .rear
                ? Self.extractRearStability(samples: samples)
                : nil
            let rearCoordination = resolvedView == .rear
                ? Self.extractRearCoordination(samples: samples)
                : nil
            let frontAutoAssessment = resolvedView == .front
                ? Self.buildFrontTrajectoryAssessment(
                    frontAlignment: frontAlignment,
                    frontTrajectory: frontTrajectory
                )
                : nil
            let rearAutoAssessment = resolvedView == .rear
                ? Self.buildRearStabilityAssessment(
                    rearPelvic: rearPelvic,
                    rearStability: rearStability,
                    rearCoordination: rearCoordination
                )
                : nil
            let adjustmentPlan = Self.buildAdjustmentPlan(
                resolvedView: resolvedView,
                durationSeconds: durationSeconds,
                cadenceSummary: cadenceSummary,
                longDurationStability: longDurationStability,
                frontAlignment: frontAlignment,
                frontTrajectory: frontTrajectory,
                rearPelvic: rearPelvic,
                rearStability: rearStability,
                rearCoordination: rearCoordination
            )
            let fittingHints = Self.buildFittingHints(
                samples: samples,
                resolvedView: resolvedView,
                modelUsed: modelUsed,
                modelFallbackNote: modelFallbackNote,
                seedHints: modelRuntimeHints,
                longDurationStability: longDurationStability,
                durationSeconds: durationSeconds
            )

            return VideoJointAngleAnalysisResult(
                durationSeconds: durationSeconds,
                targetFrameCount: targetFrameCount,
                analyzedFrameCount: samples.count,
                requestedView: requestedView,
                resolvedView: resolvedView,
                modelUsed: modelUsed,
                modelFallbackNote: modelFallbackNote,
                dominantSide: dominantSide,
                samples: samples,
                used3DAngleFrameCount: used3DAngleFrameCount,
                kneeStats: kneeStats,
                hipStats: hipStats,
                cadenceCycles: cadenceCycles,
                cadenceSummary: cadenceSummary,
                longDurationStability: longDurationStability,
                sideCheckpoints: sideCheckpoints,
                frontAlignment: frontAlignment,
                frontTrajectory: frontTrajectory,
                rearPelvic: rearPelvic,
                rearStability: rearStability,
                rearCoordination: rearCoordination,
                frontAutoAssessment: frontAutoAssessment,
                rearAutoAssessment: rearAutoAssessment,
                adjustmentPlan: adjustmentPlan,
                fittingHints: fittingHints
            )
        }.value
    }

    private static func sampleFromObservations(
        observation2D: VNHumanBodyPoseObservation?,
        observation3D: VNHumanBodyPose3DObservation?,
        sampleIndex: Int,
        timeSeconds: Double
    ) -> (sample: VideoJointAngleSample, used3D: Bool)? {
        guard let observation2D else { return nil }
        guard let baseSample = sampleFromObservation(
            observation2D,
            sampleIndex: sampleIndex,
            timeSeconds: timeSeconds
        ) else {
            return nil
        }

        guard
            let observation3D,
            #available(macOS 14.0, iOS 17.0, tvOS 17.0, *),
            let override = overrideAnglesFrom3D(
                observation3D,
                preferredSide: baseSample.side
            )
        else {
            return (baseSample, false)
        }

        let phaseDeg = phaseAngleDegrees(
            hip: override.side == .right ? baseSample.rightHip : baseSample.leftHip,
            ankle: override.side == .right ? baseSample.rightAnkle : baseSample.leftAnkle
        )

        let sample = VideoJointAngleSample(
            id: baseSample.id,
            timeSeconds: baseSample.timeSeconds,
            side: override.side,
            confidence: baseSample.confidence,
            kneeAngleDeg: override.knee,
            hipAngleDeg: override.hip,
            crankPhaseDeg: phaseDeg,
            leftHip: baseSample.leftHip,
            leftKnee: baseSample.leftKnee,
            leftAnkle: baseSample.leftAnkle,
            rightHip: baseSample.rightHip,
            rightKnee: baseSample.rightKnee,
            rightAnkle: baseSample.rightAnkle,
            leftToe: baseSample.leftToe,
            rightToe: baseSample.rightToe
        )
        return (sample, true)
    }

    private static func sampleFromObservation(
        _ observation: VNHumanBodyPoseObservation,
        sampleIndex: Int,
        timeSeconds: Double
    ) -> VideoJointAngleSample? {
        guard let points = try? observation.recognizedPoints(.all) else {
            return nil
        }

        let left = buildAngles(for: .left, points: points)
        let right = buildAngles(for: .right, points: points)

        let picked: (side: VideoPoseBodySide, confidence: Double, knee: Double?, hip: Double?)?
        if let left, let right {
            picked = left.confidence >= right.confidence ? left : right
        } else if let left {
            picked = left
        } else if let right {
            picked = right
        } else {
            picked = nil
        }
        guard let picked else { return nil }

        let leftHip = jointPoint(.leftHip, in: points)
        let leftKnee = jointPoint(.leftKnee, in: points)
        let leftAnkle = jointPoint(.leftAnkle, in: points)
        let rightHip = jointPoint(.rightHip, in: points)
        let rightKnee = jointPoint(.rightKnee, in: points)
        let rightAnkle = jointPoint(.rightAnkle, in: points)
        let leftToe = leftAnkle.map { approximateToePoint(knee: leftKnee, ankle: $0) }
        let rightToe = rightAnkle.map { approximateToePoint(knee: rightKnee, ankle: $0) }

        let crankPhaseDeg = phaseAngleDegrees(
            hip: picked.side == .right ? rightHip : leftHip,
            ankle: picked.side == .right ? rightAnkle : leftAnkle
        )

        return VideoJointAngleSample(
            id: sampleIndex,
            timeSeconds: timeSeconds,
            side: picked.side,
            confidence: picked.confidence,
            kneeAngleDeg: picked.knee,
            hipAngleDeg: picked.hip,
            crankPhaseDeg: crankPhaseDeg,
            leftHip: leftHip,
            leftKnee: leftKnee,
            leftAnkle: leftAnkle,
            rightHip: rightHip,
            rightKnee: rightKnee,
            rightAnkle: rightAnkle,
            leftToe: leftToe,
            rightToe: rightToe
        )
    }

    @available(macOS 14.0, iOS 17.0, tvOS 17.0, *)
    private static func overrideAnglesFrom3D(
        _ observation: VNHumanBodyPose3DObservation,
        preferredSide: VideoPoseBodySide
    ) -> (side: VideoPoseBodySide, knee: Double?, hip: Double?)? {
        let left = buildAngles3D(for: .left, observation: observation)
        let right = buildAngles3D(for: .right, observation: observation)

        if preferredSide == .left, let left { return left }
        if preferredSide == .right, let right { return right }

        if let left, let right {
            return preferredSide == .unknown ? right : left
        }
        if let left { return left }
        if let right { return right }
        return nil
    }

    @available(macOS 14.0, iOS 17.0, tvOS 17.0, *)
    private static func buildAngles3D(
        for side: VideoPoseBodySide,
        observation: VNHumanBodyPose3DObservation
    ) -> (side: VideoPoseBodySide, knee: Double?, hip: Double?)? {
        guard side == .left || side == .right else { return nil }

        let shoulderName: VNHumanBodyPose3DObservation.JointName = side == .left ? .leftShoulder : .rightShoulder
        let hipName: VNHumanBodyPose3DObservation.JointName = side == .left ? .leftHip : .rightHip
        let kneeName: VNHumanBodyPose3DObservation.JointName = side == .left ? .leftKnee : .rightKnee
        let ankleName: VNHumanBodyPose3DObservation.JointName = side == .left ? .leftAnkle : .rightAnkle

        guard
            let shoulderPoint = jointPoint3D(shoulderName, in: observation),
            let hipPoint = jointPoint3D(hipName, in: observation),
            let kneePoint = jointPoint3D(kneeName, in: observation),
            let anklePoint = jointPoint3D(ankleName, in: observation)
        else {
            return nil
        }

        let kneeAngle = angleDegrees3D(a: hipPoint, b: kneePoint, c: anklePoint)
        let hipAngle = angleDegrees3D(a: shoulderPoint, b: hipPoint, c: kneePoint)
        return (side, kneeAngle, hipAngle)
    }

    private static func buildAngles(
        for side: VideoPoseBodySide,
        points: [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint]
    ) -> (side: VideoPoseBodySide, confidence: Double, knee: Double?, hip: Double?)? {
        guard side == .left || side == .right else { return nil }

        let shoulderName: VNHumanBodyPoseObservation.JointName = side == .left ? .leftShoulder : .rightShoulder
        let hipName: VNHumanBodyPoseObservation.JointName = side == .left ? .leftHip : .rightHip
        let kneeName: VNHumanBodyPoseObservation.JointName = side == .left ? .leftKnee : .rightKnee
        let ankleName: VNHumanBodyPoseObservation.JointName = side == .left ? .leftAnkle : .rightAnkle

        guard
            let shoulder = points[shoulderName], shoulder.confidence >= minJointConfidence,
            let hip = points[hipName], hip.confidence >= minJointConfidence,
            let knee = points[kneeName], knee.confidence >= minJointConfidence,
            let ankle = points[ankleName], ankle.confidence >= minJointConfidence
        else {
            return nil
        }

        let shoulderPoint = CGPoint(x: shoulder.location.x, y: shoulder.location.y)
        let hipPoint = CGPoint(x: hip.location.x, y: hip.location.y)
        let kneePoint = CGPoint(x: knee.location.x, y: knee.location.y)
        let anklePoint = CGPoint(x: ankle.location.x, y: ankle.location.y)

        let kneeAngle = angleDegrees(a: hipPoint, b: kneePoint, c: anklePoint)
        let hipAngle = angleDegrees(a: shoulderPoint, b: hipPoint, c: kneePoint)
        let confidence = Double((shoulder.confidence + hip.confidence + knee.confidence + ankle.confidence) / 4)

        return (side: side, confidence: confidence, knee: kneeAngle, hip: hipAngle)
    }

    private static func resolveView(
        requested: CyclingCameraView,
        from samples: [VideoJointAngleSample]
    ) -> CyclingCameraView {
        guard requested == .auto else { return requested }
        let bilateralCount = samples.filter {
            $0.leftHip != nil && $0.leftKnee != nil && $0.leftAnkle != nil &&
            $0.rightHip != nil && $0.rightKnee != nil && $0.rightAnkle != nil
        }.count
        let ratio = samples.isEmpty ? 0 : Double(bilateralCount) / Double(samples.count)
        return ratio >= 0.42 ? .front : .side
    }

    private static func extractSideCheckpoints(samples: [VideoJointAngleSample]) -> [SideCheckpointSnapshot] {
        let valid = samples.compactMap { sample -> (VideoJointAngleSample, Double)? in
            guard let phase = sample.crankPhaseDeg else { return nil }
            return (sample, phase)
        }
        guard !valid.isEmpty else { return [] }

        return CrankClockCheckpoint.allCases.compactMap { checkpoint in
            guard let best = valid.min(by: {
                circularPhaseDifference($0.1, checkpoint.targetPhaseDeg) < circularPhaseDifference($1.1, checkpoint.targetPhaseDeg)
            }) else { return nil }
            let error = circularPhaseDifference(best.1, checkpoint.targetPhaseDeg)
            return SideCheckpointSnapshot(
                checkpoint: checkpoint,
                timeSeconds: best.0.timeSeconds,
                phaseDeg: best.1,
                phaseErrorDeg: error,
                kneeAngleDeg: best.0.kneeAngleDeg,
                hipAngleDeg: best.0.hipAngleDeg
            )
        }
    }

    private static func extractCadenceCycles(samples: [VideoJointAngleSample]) -> [CadenceCycleSegment] {
        let valid = samples.compactMap { sample -> (time: Double, phase: Double, knee: Double?)? in
            guard let phase = sample.crankPhaseDeg else { return nil }
            return (sample.timeSeconds, normalizeDegrees(phase), sample.kneeAngleDeg)
        }
        guard valid.count >= 6 else { return [] }

        var unwrapped: [Double] = Array(repeating: 0, count: valid.count)
        unwrapped[0] = valid[0].phase

        for index in 1..<valid.count {
            var delta = valid[index].phase - valid[index - 1].phase
            while delta <= -180 { delta += 360 }
            while delta > 180 { delta -= 360 }
            unwrapped[index] = unwrapped[index - 1] + delta
        }

        let totalDelta = (unwrapped.last ?? 0) - unwrapped[0]
        guard abs(totalDelta) >= 300 else { return [] }
        let direction = totalDelta >= 0 ? 1.0 : -1.0
        let progress = unwrapped.map { direction * ($0 - unwrapped[0]) }
        guard let maxProgress = progress.last, maxProgress >= 300 else { return [] }

        let maxCycleIndex = Int(floor(maxProgress / 360))
        guard maxCycleIndex >= 0 else { return [] }

        var segments: [CadenceCycleSegment] = []
        segments.reserveCapacity(maxCycleIndex + 1)

        for cycleIndex in 0...maxCycleIndex {
            let lower = Double(cycleIndex) * 360
            let upper = lower + 360

            let indices = progress.enumerated().compactMap { index, value in
                (value >= lower && value < upper) ? index : nil
            }
            guard let firstIndex = indices.first else { continue }
            let span = (indices.map { progress[$0] }.max() ?? lower) - (indices.map { progress[$0] }.min() ?? lower)
            guard span >= 240 else { continue }

            let crossingIndex = progress.firstIndex(where: { $0 >= upper }) ?? indices.last!
            let startTime = valid[firstIndex].time

            let endTime: Double
            if crossingIndex > firstIndex, crossingIndex < progress.count {
                let prevIndex = crossingIndex - 1
                let p0 = progress[prevIndex]
                let p1 = progress[crossingIndex]
                let t0 = valid[prevIndex].time
                let t1 = valid[crossingIndex].time
                if p1 > p0 {
                    let ratio = min(max((upper - p0) / (p1 - p0), 0), 1)
                    endTime = t0 + (t1 - t0) * ratio
                } else {
                    endTime = valid[crossingIndex].time
                }
            } else {
                endTime = valid[indices.last!].time
            }

            let duration = max(0.0001, endTime - startTime)
            let cadence = 60.0 / duration
            guard cadence.isFinite, cadence >= 20, cadence <= 220 else { continue }

            let cycleCandidateIndices = indices.filter { progress[$0] >= lower && progress[$0] < upper }
            let bestBDCIndex = cycleCandidateIndices.min(by: {
                circularPhaseDifference(valid[$0].phase, 180) < circularPhaseDifference(valid[$1].phase, 180)
            })

            segments.append(
                CadenceCycleSegment(
                    id: cycleIndex,
                    startTimeSeconds: startTime,
                    endTimeSeconds: endTime,
                    durationSeconds: duration,
                    cadenceRPM: cadence,
                    bdcTimeSeconds: bestBDCIndex.map { valid[$0].time },
                    bdcPhaseDeg: bestBDCIndex.map { valid[$0].phase },
                    bdcKneeAngleDeg: bestBDCIndex.flatMap { valid[$0].knee }
                )
            )
        }

        return segments
    }

    private static func summarizeCadenceCycles(_ cycles: [CadenceCycleSegment]) -> CadenceCycleSummary? {
        guard !cycles.isEmpty else { return nil }
        let cadenceValues = cycles.map(\.cadenceRPM)
        let cadenceMean = cadenceValues.reduce(0, +) / Double(cadenceValues.count)
        let bdcKneeValues = cycles.compactMap(\.bdcKneeAngleDeg)
        let bdcKneeStats = stats(for: bdcKneeValues)
        let recommendation = bdcKneeStats.map(buildSaddleHeightRecommendation)

        return CadenceCycleSummary(
            cycleCount: cycles.count,
            meanCadenceRPM: cadenceMean,
            minCadenceRPM: cadenceValues.min() ?? cadenceMean,
            maxCadenceRPM: cadenceValues.max() ?? cadenceMean,
            bdcKneeStats: bdcKneeStats,
            saddleHeightRecommendation: recommendation
        )
    }

    private static func extractLongDurationStability(
        samples: [VideoJointAngleSample],
        cycles: [CadenceCycleSegment],
        durationSeconds: Double
    ) -> LongDurationStabilityStats? {
        guard durationSeconds >= 20 else { return nil }

        let analyzedDuration = min(60.0, durationSeconds)
        let windowEnd = durationSeconds
        let windowStart = max(0, windowEnd - analyzedDuration)
        let windowCenter = (windowStart + windowEnd) / 2.0
        let earlyEnd = windowStart + analyzedDuration * 0.35
        let lateStart = windowEnd - analyzedDuration * 0.35

        let windowCycles = cycles.filter {
            $0.startTimeSeconds >= windowStart && $0.endTimeSeconds <= windowEnd
        }
        let cadencePairs = windowCycles.map { cycle -> (Double, Double) in
            let mid = (cycle.startTimeSeconds + cycle.endTimeSeconds) / 2.0
            return (mid, cycle.cadenceRPM)
        }
        let meanCadence = mean(cadencePairs.map(\.1))
        let cadenceDrift = linearSlopePerMinute(pairs: cadencePairs)

        let bdcPhasePairs = windowCycles.compactMap { cycle -> (Double, Double)? in
            guard let phase = cycle.bdcPhaseDeg else { return nil }
            let t = cycle.bdcTimeSeconds ?? ((cycle.startTimeSeconds + cycle.endTimeSeconds) / 2.0)
            let error = circularPhaseDifference(phase, 180.0)
            return (t, error)
        }
        let meanBDCPhaseError = mean(bdcPhasePairs.map(\.1))
        let phaseDrift = linearSlopePerMinute(pairs: bdcPhasePairs)

        let bdcKneePairs = windowCycles.compactMap { cycle -> (Double, Double)? in
            guard let knee = cycle.bdcKneeAngleDeg else { return nil }
            let t = cycle.bdcTimeSeconds ?? ((cycle.startTimeSeconds + cycle.endTimeSeconds) / 2.0)
            return (t, knee)
        }
        let meanBDCKnee = mean(bdcKneePairs.map(\.1))
        let bdcKneeDrift = linearSlopePerMinute(pairs: bdcKneePairs)
        let earlyBDCKnee = mean(
            bdcKneePairs.filter { $0.0 <= windowCenter }.map(\.1)
        )
        let lateBDCKnee = mean(
            bdcKneePairs.filter { $0.0 > windowCenter }.map(\.1)
        )

        let windowSamples = samples.filter { $0.timeSeconds >= windowStart && $0.timeSeconds <= windowEnd }
        let earlySamples = windowSamples.filter { $0.timeSeconds <= earlyEnd }
        let lateSamples = windowSamples.filter { $0.timeSeconds >= lateStart }
        let earlyKnee = mean(earlySamples.compactMap(\.kneeAngleDeg))
        let lateKnee = mean(lateSamples.compactMap(\.kneeAngleDeg))
        let earlyHip = mean(earlySamples.compactMap(\.hipAngleDeg))
        let lateHip = mean(lateSamples.compactMap(\.hipAngleDeg))

        let hasMetrics = meanCadence != nil ||
            meanBDCPhaseError != nil ||
            meanBDCKnee != nil ||
            earlyKnee != nil ||
            lateKnee != nil ||
            earlyHip != nil ||
            lateHip != nil
        guard hasMetrics else { return nil }

        return LongDurationStabilityStats(
            windowStartSeconds: windowStart,
            windowEndSeconds: windowEnd,
            analyzedDurationSeconds: analyzedDuration,
            cycleCount: windowCycles.count,
            meanCadenceRPM: meanCadence,
            cadenceDriftRPMPerMin: cadenceDrift,
            meanBDCPhaseErrorDeg: meanBDCPhaseError,
            phaseDriftDegPerMin: phaseDrift,
            meanBDCKneeAngleDeg: meanBDCKnee,
            earlyBDCKneeAngleDeg: earlyBDCKnee,
            lateBDCKneeAngleDeg: lateBDCKnee,
            bdcKneeDriftDegPerMin: bdcKneeDrift,
            earlyKneeAngleDeg: earlyKnee,
            lateKneeAngleDeg: lateKnee,
            earlyHipAngleDeg: earlyHip,
            lateHipAngleDeg: lateHip
        )
    }

    private static func buildSaddleHeightRecommendation(from bdcKneeStats: JointAngleStats) -> SaddleHeightRecommendation {
        let targetMin = 145.0
        let targetMax = 155.0
        let currentMean = bdcKneeStats.mean
        let mmPerDegree = 2.5

        if currentMean < targetMin {
            let minAdjust = (targetMin - currentMean) * mmPerDegree
            let maxAdjust = (targetMax - currentMean) * mmPerDegree
            return SaddleHeightRecommendation(
                targetKneeAngleMinDeg: targetMin,
                targetKneeAngleMaxDeg: targetMax,
                meanBDCKneeAngleDeg: currentMean,
                direction: .raise,
                suggestedAdjustmentMinMM: max(0, minAdjust),
                suggestedAdjustmentMaxMM: max(0, maxAdjust)
            )
        }

        if currentMean > targetMax {
            let minAdjust = (currentMean - targetMax) * mmPerDegree
            let maxAdjust = (currentMean - targetMin) * mmPerDegree
            return SaddleHeightRecommendation(
                targetKneeAngleMinDeg: targetMin,
                targetKneeAngleMaxDeg: targetMax,
                meanBDCKneeAngleDeg: currentMean,
                direction: .lower,
                suggestedAdjustmentMinMM: max(0, minAdjust),
                suggestedAdjustmentMaxMM: max(0, maxAdjust)
            )
        }

        return SaddleHeightRecommendation(
            targetKneeAngleMinDeg: targetMin,
            targetKneeAngleMaxDeg: targetMax,
            meanBDCKneeAngleDeg: currentMean,
            direction: .keep,
            suggestedAdjustmentMinMM: 0,
            suggestedAdjustmentMaxMM: 3
        )
    }

    private static func extractFrontAlignment(samples: [VideoJointAngleSample]) -> FrontAlignmentStats? {
        var normalizedOffsets: [Double] = []
        var asymmetries: [Double] = []
        var widthRatios: [Double] = []

        for sample in samples {
            guard
                let leftHip = sample.leftHip,
                let rightHip = sample.rightHip,
                let leftKnee = sample.leftKnee,
                let rightKnee = sample.rightKnee,
                let leftAnkle = sample.leftAnkle,
                let rightAnkle = sample.rightAnkle
            else {
                continue
            }

            let hipWidth = abs(rightHip.x - leftHip.x)
            guard hipWidth > 0.000001 else { continue }

            let leftOffset = (leftKnee.x - leftAnkle.x) / hipWidth
            let rightOffset = (rightKnee.x - rightAnkle.x) / hipWidth
            let meanOffset = (abs(leftOffset) + abs(rightOffset)) / 2.0
            normalizedOffsets.append(meanOffset)
            asymmetries.append(abs(abs(leftOffset) - abs(rightOffset)))

            let kneeWidth = abs(rightKnee.x - leftKnee.x)
            widthRatios.append(kneeWidth / hipWidth)
        }

        guard !normalizedOffsets.isEmpty else { return nil }
        return FrontAlignmentStats(
            meanKneeFootOffset: normalizedOffsets.reduce(0, +) / Double(normalizedOffsets.count),
            maxKneeFootOffset: normalizedOffsets.max() ?? 0,
            kneeTrackAsymmetry: asymmetries.reduce(0, +) / Double(asymmetries.count),
            hipKneeWidthRatio: widthRatios.reduce(0, +) / Double(widthRatios.count),
            sampleCount: normalizedOffsets.count
        )
    }

    private static func extractFrontTrajectory(samples: [VideoJointAngleSample]) -> FrontTrajectoryStats? {
        var leftKneeX: [Double] = []
        var rightKneeX: [Double] = []
        var leftAnkleX: [Double] = []
        var rightAnkleX: [Double] = []
        var leftToeX: [Double] = []
        var rightToeX: [Double] = []
        var hipWidths: [Double] = []
        var kneeOverAnkleCount = 0
        var validCount = 0

        for sample in samples {
            guard
                let leftHip = sample.leftHip,
                let rightHip = sample.rightHip,
                let leftKnee = sample.leftKnee,
                let rightKnee = sample.rightKnee,
                let leftAnkle = sample.leftAnkle,
                let rightAnkle = sample.rightAnkle
            else {
                continue
            }
            let hipWidth = abs(rightHip.x - leftHip.x)
            guard hipWidth > 0.000001 else { continue }
            hipWidths.append(hipWidth)
            leftKneeX.append(leftKnee.x)
            rightKneeX.append(rightKnee.x)
            leftAnkleX.append(leftAnkle.x)
            rightAnkleX.append(rightAnkle.x)
            if let leftToe = sample.leftToe, let rightToe = sample.rightToe {
                leftToeX.append(leftToe.x)
                rightToeX.append(rightToe.x)
            }
            let threshold = hipWidth * 0.22
            if abs(leftKnee.x - leftAnkle.x) <= threshold && abs(rightKnee.x - rightAnkle.x) <= threshold {
                kneeOverAnkleCount += 1
            }
            validCount += 1
        }

        guard validCount >= 10 else { return nil }
        let hipWidthNorm = median(hipWidths) ?? (hipWidths.reduce(0, +) / Double(hipWidths.count))
        guard hipWidthNorm > 0.000001 else { return nil }

        func span(_ values: [Double]) -> Double {
            guard let minV = values.min(), let maxV = values.max() else { return 0 }
            return max(0, maxV - minV)
        }

        let kneeSpan = (span(leftKneeX) + span(rightKneeX)) / 2.0 / hipWidthNorm
        let ankleSpan = (span(leftAnkleX) + span(rightAnkleX)) / 2.0 / hipWidthNorm
        let toeSpan: Double? = (leftToeX.count >= 6 && rightToeX.count >= 6)
            ? ((span(leftToeX) + span(rightToeX)) / 2.0 / hipWidthNorm)
            : nil

        return FrontTrajectoryStats(
            kneeTrajectorySpanNorm: kneeSpan,
            ankleTrajectorySpanNorm: ankleSpan,
            toeTrajectorySpanNorm: toeSpan,
            kneeOverAnkleInRangeRatio: Double(kneeOverAnkleCount) / Double(validCount),
            sampleCount: validCount
        )
    }

    private static func extractRearPelvic(samples: [VideoJointAngleSample]) -> RearPelvicStats? {
        var tilts: [Double] = []
        var leftDropCount = 0

        for sample in samples {
            guard let leftHip = sample.leftHip, let rightHip = sample.rightHip else { continue }
            let dx = rightHip.x - leftHip.x
            let dy = rightHip.y - leftHip.y
            guard abs(dx) > 0.000001 else { continue }
            let tilt = atan2(dy, dx) * 180.0 / Double.pi
            tilts.append(tilt)
            if leftHip.y < rightHip.y - 0.004 {
                leftDropCount += 1
            }
        }

        guard !tilts.isEmpty else { return nil }
        let meanTilt = tilts.reduce(0, +) / Double(tilts.count)
        let maxAbs = tilts.map { abs($0) }.max() ?? 0
        return RearPelvicStats(
            meanPelvicTiltDeg: meanTilt,
            maxPelvicTiltDeg: maxAbs,
            leftHipDropRatio: Double(leftDropCount) / Double(tilts.count),
            sampleCount: tilts.count
        )
    }

    private static func extractRearStability(samples: [VideoJointAngleSample]) -> RearStabilityStats? {
        var shifts: [Double] = []
        var signedShifts: [Double] = []

        var centers: [Double] = []
        var hipWidths: [Double] = []
        centers.reserveCapacity(samples.count)
        hipWidths.reserveCapacity(samples.count)

        for sample in samples {
            guard let leftHip = sample.leftHip, let rightHip = sample.rightHip else { continue }
            let hipWidth = abs(rightHip.x - leftHip.x)
            guard hipWidth > 0.000001 else { continue }
            hipWidths.append(hipWidth)
            let hipCenter = (leftHip.x + rightHip.x) / 2.0
            if let leftKnee = sample.leftKnee, let rightKnee = sample.rightKnee {
                let kneeCenter = (leftKnee.x + rightKnee.x) / 2.0
                // Approximate COM lateral drift with a lower-body center proxy.
                centers.append(hipCenter * 0.7 + kneeCenter * 0.3)
            } else {
                centers.append(hipCenter)
            }
        }
        guard centers.count >= 10 else { return nil }
        let baseline = median(centers) ?? (centers.reduce(0, +) / Double(centers.count))

        for idx in centers.indices {
            let hw = hipWidths[idx]
            let signed = (centers[idx] - baseline) / hw
            signedShifts.append(signed)
            shifts.append(abs(signed))
        }

        guard !shifts.isEmpty else { return nil }
        return RearStabilityStats(
            meanCenterShiftNorm: shifts.reduce(0, +) / Double(shifts.count),
            maxCenterShiftNorm: shifts.max() ?? 0,
            lateralBias: signedShifts.reduce(0, +) / Double(signedShifts.count),
            sampleCount: shifts.count
        )
    }

    private static func buildFittingHints(
        samples: [VideoJointAngleSample],
        resolvedView: CyclingCameraView,
        modelUsed: VideoPoseEstimationModel,
        modelFallbackNote: String?,
        seedHints: [String],
        longDurationStability: LongDurationStabilityStats?,
        durationSeconds: Double
    ) -> [String] {
        var hints: [String] = seedHints
        if let modelFallbackNote {
            hints.append(modelFallbackNote)
        }
        guard !samples.isEmpty else { return hints }

        let strongFrames = samples.filter { $0.confidence >= 0.55 }.count
        let strongRatio = Double(strongFrames) / Double(samples.count)
        if strongRatio < 0.60 {
            hints.append(
                L10n.choose(
                    simplifiedChinese: "关键点置信度偏低。建议穿紧身骑行服、提高侧前方光照，并减少背景遮挡。",
                    english: "Keypoint confidence is low. Use tight clothing, stronger front/side lighting, and reduce background occlusion."
                )
            )
            hints.append(
                L10n.choose(
                    simplifiedChinese: "可贴标记点提高精度：大转子、膝外侧髁、外踝、ASIS（髂前上棘）。",
                    english: "Add visual markers for better precision: greater trochanter, lateral femoral epicondyle, lateral malleolus, and ASIS."
                )
            )
        }

        if resolvedView == .front {
            let toeAvailableFrames = samples.filter { $0.leftToe != nil && $0.rightToe != nil }.count
            let toeRatio = Double(toeAvailableFrames) / Double(samples.count)
            if toeRatio < 0.55 {
                hints.append(
                    L10n.choose(
                        simplifiedChinese: "前视图足尖识别不足，足尖轨迹精度受限。建议在鞋尖贴高对比标记并避免裤脚遮挡。",
                        english: "Toe detection is insufficient in front view, limiting toe-path accuracy. Add high-contrast shoe-tip markers and avoid coverage by clothing."
                    )
                )
            }
        }

        if modelUsed == .appleVision {
            hints.append(
                L10n.choose(
                    simplifiedChinese: "若需更高精度，建议安装 Python + MediaPipe 以启用 BlazePose GHUM。",
                    english: "For higher precision, install Python + MediaPipe to enable BlazePose GHUM."
                )
            )
        }
        if durationSeconds < 20 {
            hints.append(
                L10n.choose(
                    simplifiedChinese: "当前视频时长不足 20 秒，无法完成 20-60 秒稳定性统计。建议录制至少 20 秒连续踩踏。",
                    english: "Video is shorter than 20s, so 20-60s stability statistics cannot run. Record at least 20s of continuous pedaling."
                )
            )
        } else if longDurationStability == nil {
            hints.append(
                L10n.choose(
                    simplifiedChinese: "未提取到足够稳定的踏频周期，长时段稳定性统计可能不完整。建议提升帧率、减少遮挡并保持画面稳定。",
                    english: "Not enough stable cadence cycles were extracted, so long-duration stability metrics may be incomplete. Increase FPS, reduce occlusion, and keep camera stable."
                )
            )
        } else if let longDurationStability, longDurationStability.cycleCount < 12 {
            hints.append(
                L10n.choose(
                    simplifiedChinese: "长时段稳定性周期数偏少，建议提高踏频清晰度（更高帧率/更少遮挡）或延长采集时长。",
                    english: "Long-duration stability has too few valid cycles. Improve cadence visibility (higher FPS/less occlusion) or capture a longer clip."
                )
            )
        }
        return hints
    }

    private static func buildAdjustmentPlan(
        resolvedView: CyclingCameraView,
        durationSeconds: Double,
        cadenceSummary: CadenceCycleSummary?,
        longDurationStability: LongDurationStabilityStats?,
        frontAlignment: FrontAlignmentStats?,
        frontTrajectory: FrontTrajectoryStats?,
        rearPelvic: RearPelvicStats?,
        rearStability: RearStabilityStats?,
        rearCoordination: PedalingCoordinationStats?
    ) -> [BikeFitAdjustmentStep] {
        struct Candidate {
            let domain: BikeFitAdjustmentDomain
            let title: String
            var score: Double
            let rationale: String
            let maxAdjustment: String
            let retest: String
            let success: String
        }

        var candidates: [Candidate] = []

        if durationSeconds < 20 || longDurationStability == nil || (longDurationStability?.cycleCount ?? 0) < 12 {
            let cycleCount = longDurationStability?.cycleCount ?? 0
            let score = durationSeconds < 20 ? 97.0 : (cycleCount > 0 ? 90.0 : 84.0)
            candidates.append(
                Candidate(
                    domain: .capture,
                    title: L10n.choose(simplifiedChinese: "先补采集质量（再调车）", english: "Fix capture quality first"),
                    score: score,
                    rationale: L10n.choose(
                        simplifiedChinese: "当前长时段统计不足（时长 \(String(format: "%.1f", durationSeconds))s，周期 \(cycleCount)）。先保证 20-60 秒、≥12 个周期的数据，再做机械调整，结论更可靠。",
                        english: "Long-duration stats are insufficient (duration \(String(format: "%.1f", durationSeconds))s, cycles \(cycleCount)). Collect 20-60s with >=12 cycles before changing bike setup."
                    ),
                    maxAdjustment: L10n.choose(
                        simplifiedChinese: "本步不改车，只优化采集：60fps（最低 30fps）、稳定机位、提升光照。",
                        english: "No bike changes in this step; improve capture first: 60fps (>=30fps), stable camera, better lighting."
                    ),
                    retest: L10n.choose(
                        simplifiedChinese: "同功率同踏频复测 20-60 秒，目标提取 ≥12 个有效踏频周期。",
                        english: "Retest 20-60s at similar cadence/power; target >=12 valid cadence cycles."
                    ),
                    success: L10n.choose(
                        simplifiedChinese: "出现完整长时段指标：BDC、相位漂移、疲劳前后姿态差异可稳定输出。",
                        english: "Long-duration metrics become consistently available: BDC, phase drift, and fatigue deltas."
                    )
                )
            )
        }

        if let cadenceSummary {
            let recommendation = cadenceSummary.saddleHeightRecommendation
            let bdcMean = cadenceSummary.bdcKneeStats?.mean ?? recommendation?.meanBDCKneeAngleDeg
            let bdcDrift = abs(longDurationStability?.bdcKneeDriftDegPerMin ?? 0)
            let bdcDeviation: Double
            if let recommendation, let bdcMean {
                if bdcMean < recommendation.targetKneeAngleMinDeg {
                    bdcDeviation = recommendation.targetKneeAngleMinDeg - bdcMean
                } else if bdcMean > recommendation.targetKneeAngleMaxDeg {
                    bdcDeviation = bdcMean - recommendation.targetKneeAngleMaxDeg
                } else {
                    bdcDeviation = 0
                }
            } else {
                bdcDeviation = 0
            }

            if bdcDeviation >= 1.5 || bdcDrift >= 1.2 {
                let directionText = saddleAdjustmentLabel(recommendation?.direction ?? .keep)
                let deltaUpper = recommendation?.suggestedAdjustmentMaxMM ?? max(2.0, min(6.0, bdcDeviation * 2.5))
                let stepLimit = bdcDeviation >= 6 ? 4.0 : (bdcDeviation >= 3 ? 3.0 : 2.0)
                let score = min(98.0, 68.0 + bdcDeviation * 4.0 + bdcDrift * 8.0)

                candidates.append(
                    Candidate(
                        domain: .saddleHeight,
                        title: L10n.choose(
                            simplifiedChinese: "先调座高（BDC 膝角主导）",
                            english: "Adjust saddle height first (BDC-led)"
                        ),
                        score: score,
                        rationale: L10n.choose(
                            simplifiedChinese: "BDC 膝角偏差 \(String(format: "%.1f°", bdcDeviation))，漂移 \(String(format: "%.2f°/min", bdcDrift))。建议先\(directionText)（总建议上限约 \(String(format: "%.0f", deltaUpper)) mm）。",
                            english: "BDC deviation \(String(format: "%.1f°", bdcDeviation)), drift \(String(format: "%.2f°/min", bdcDrift)). \(directionText) first (total range up to \(String(format: "%.0f", deltaUpper)) mm)."
                        ),
                        maxAdjustment: L10n.choose(
                            simplifiedChinese: "每步最多 \(String(format: "%.0f", stepLimit)) mm（单次不要超过 4 mm），每次只改一个参数。",
                            english: "Max \(String(format: "%.0f", stepLimit)) mm per step (never >4 mm each change); only change one variable per step."
                        ),
                        retest: L10n.choose(
                            simplifiedChinese: "每次调整后复测 20-60 秒，保持相近功率与踏频，检查 BDC 膝角均值/漂移与相位漂移。",
                            english: "After each change, retest 20-60s at similar power/cadence and check BDC mean/drift and phase drift."
                        ),
                        success: L10n.choose(
                            simplifiedChinese: "BDC 膝角进入 145-155° 且 |BDC 漂移| ≤ 1.6°/min。",
                            english: "BDC knee angle reaches 145-155° and |BDC drift| <= 1.6°/min."
                        )
                    )
                )
            }
        }

        if let longDurationStability {
            let phaseError = longDurationStability.meanBDCPhaseErrorDeg ?? 0
            let phaseDrift = abs(longDurationStability.phaseDriftDegPerMin ?? 0)
            let kneeFatigue = abs((longDurationStability.lateKneeAngleDeg ?? 0) - (longDurationStability.earlyKneeAngleDeg ?? 0))
            let hipFatigue = abs((longDurationStability.lateHipAngleDeg ?? 0) - (longDurationStability.earlyHipAngleDeg ?? 0))
            let fatigue = max(kneeFatigue, hipFatigue)

            if phaseError > 14 || phaseDrift > 1.8 || fatigue > 3.5 {
                let score = min(96.0, 58.0 + phaseError * 0.9 + phaseDrift * 6.5 + fatigue * 4.0)
                candidates.append(
                    Candidate(
                        domain: .saddleForeAft,
                        title: L10n.choose(
                            simplifiedChinese: "第二步调前后（相位与疲劳漂移）",
                            english: "Then tune fore-aft (phase & fatigue drift)"
                        ),
                        score: score,
                        rationale: L10n.choose(
                            simplifiedChinese: "BDC 相位误差 \(String(format: "%.1f°", phaseError))，相位漂移 \(String(format: "%.2f°/min", phaseDrift))，疲劳后姿态变化 \(String(format: "%.1f°", fatigue))。",
                            english: "BDC phase error \(String(format: "%.1f°", phaseError)), phase drift \(String(format: "%.2f°/min", phaseDrift)), post-fatigue change \(String(format: "%.1f°", fatigue))."
                        ),
                        maxAdjustment: L10n.choose(
                            simplifiedChinese: "座垫前后每步 2-3 mm（单次不超过 5 mm）。",
                            english: "Move saddle fore-aft by 2-3 mm per step (max 5 mm each change)."
                        ),
                        retest: L10n.choose(
                            simplifiedChinese: "复测 20-60 秒，至少 12 个周期；重点比较相位误差、相位漂移和疲劳前后差值。",
                            english: "Retest 20-60s with >=12 cycles; compare phase error, phase drift, and fatigue deltas."
                        ),
                        success: L10n.choose(
                            simplifiedChinese: "|相位漂移| ≤ 2.5°/min，疲劳后膝/髋变化收敛到 ±4°以内。",
                            english: "|Phase drift| <= 2.5°/min and post-fatigue knee/hip delta within ±4°."
                        )
                    )
                )
            }
        }

        if let frontTrajectory {
            let toeSpan = frontTrajectory.toeTrajectorySpanNorm ?? 0
            let severity = max(
                max(0, frontTrajectory.kneeTrajectorySpanNorm - 0.36) * 160,
                max(0, frontTrajectory.ankleTrajectorySpanNorm - 0.28) * 180,
                max(0, toeSpan - 0.34) * 140,
                max(0, 0.70 - frontTrajectory.kneeOverAnkleInRangeRatio) * 120
            )
            let asym = frontAlignment?.kneeTrackAsymmetry ?? 0
            let asymPenalty = max(0, asym - 0.08) * 120
            let combinedSeverity = max(severity + asymPenalty, 0)

            if combinedSeverity >= 8 {
                let score = min(94.0, 50.0 + combinedSeverity)
                candidates.append(
                    Candidate(
                        domain: .cleatAndStance,
                        title: L10n.choose(
                            simplifiedChinese: "锁片/站距微调（前视轨迹）",
                            english: "Cleat/stance micro-adjustment (front view)"
                        ),
                        score: score,
                        rationale: L10n.choose(
                            simplifiedChinese: "前视膝-踝-足尖轨迹存在偏宽或不对称，膝踝合理占比 \(String(format: "%.0f%%", frontTrajectory.kneeOverAnkleInRangeRatio * 100))。",
                            english: "Front-view knee/ankle/toe path shows excessive width or asymmetry; in-range ratio \(String(format: "%.0f%%", frontTrajectory.kneeOverAnkleInRangeRatio * 100))."
                        ),
                        maxAdjustment: L10n.choose(
                            simplifiedChinese: "锁片每步 1-2 mm 或 0.5-1°；一次只改单侧，避免并行改多项。",
                            english: "Cleat change: 1-2 mm or 0.5-1° per step; adjust one side at a time."
                        ),
                        retest: L10n.choose(
                            simplifiedChinese: "复测 20-40 秒前视视频，检查膝轨迹宽度、足尖轨迹与左右对称。",
                            english: "Retest 20-40s front-view clip; verify knee/toe path width and left-right symmetry."
                        ),
                        success: L10n.choose(
                            simplifiedChinese: "膝轨迹 ≤ 0.36、踝轨迹 ≤ 0.28，膝踝合理占比 ≥ 70%。",
                            english: "Knee path <= 0.36, ankle path <= 0.28, knee-over-ankle in-range >= 70%."
                        )
                    )
                )
            }
        }

        if let rearStability {
            let pelvicTilt = rearPelvic?.maxPelvicTiltDeg ?? 0
            let shunGuai = rearCoordination?.isShunGuaiSuspected == true
            let severity = max(
                max(0, rearStability.meanCenterShiftNorm - 0.10) * 280,
                max(0, rearStability.maxCenterShiftNorm - 0.22) * 220,
                max(0, abs(rearStability.lateralBias) - 0.05) * 300,
                max(0, pelvicTilt - 6.0) * 4.5
            ) + (shunGuai ? 18 : 0)

            if severity >= 10 {
                let score = min(93.0, 49.0 + severity)
                candidates.append(
                    Candidate(
                        domain: .pelvicAndCore,
                        title: L10n.choose(
                            simplifiedChinese: "盆骨/重心稳定性修正（后视）",
                            english: "Pelvic/CoM stability correction (rear view)"
                        ),
                        score: score,
                        rationale: L10n.choose(
                            simplifiedChinese: "后视显示盆骨或重心漂移偏大\(shunGuai ? "，并伴随疑似顺拐。" : "。")",
                            english: "Rear-view metrics show elevated pelvic or CoM drift\(shunGuai ? ", with possible shun-guai." : ".")"
                        ),
                        maxAdjustment: L10n.choose(
                            simplifiedChinese: "座垫水平/左右垫片每步 ≤0.5° 或 ≤2 mm；一次只改一个变量。",
                            english: "Saddle tilt/shim change <=0.5° or <=2 mm per step; modify one variable at a time."
                        ),
                        retest: L10n.choose(
                            simplifiedChinese: "复测 30-60 秒后视视频，比较盆骨倾斜、重心偏置和顺拐指标。",
                            english: "Retest 30-60s rear-view clip and compare pelvic tilt, CoM bias, and shun-guai indicators."
                        ),
                        success: L10n.choose(
                            simplifiedChinese: "最大盆骨倾斜 ≤ 6°，重心偏置 |bias| ≤ 0.05，且无顺拐提示。",
                            english: "Max pelvic tilt <= 6°, CoM |bias| <= 0.05, and no shun-guai warning."
                        )
                    )
                )
            }
        }

        if let saddleIndex = candidates.firstIndex(where: { $0.domain == .saddleHeight }),
           let foreAftIndex = candidates.firstIndex(where: { $0.domain == .saddleForeAft }),
           candidates[saddleIndex].score <= candidates[foreAftIndex].score {
            candidates[saddleIndex].score = min(99.0, candidates[foreAftIndex].score + 1.0)
        }

        if candidates.isEmpty {
            candidates.append(
                Candidate(
                    domain: .baseline,
                    title: L10n.choose(
                        simplifiedChinese: "当前状态稳定，建立基线",
                        english: "Current setup looks stable; keep baseline"
                    ),
                    score: 35.0,
                    rationale: L10n.choose(
                        simplifiedChinese: "未发现高优先级偏差，优先保持当前设定并持续跟踪长时段稳定性。",
                        english: "No high-priority deviation found. Keep setup and track long-duration stability."
                    ),
                    maxAdjustment: L10n.choose(
                        simplifiedChinese: "本轮不做机械调整；如需微调，每步 ≤1-2 mm。",
                        english: "No mechanical change in this round; if needed, limit to <=1-2 mm per step."
                    ),
                    retest: L10n.choose(
                        simplifiedChinese: "每周复测一次 20-60 秒，保持同拍摄位和光照。",
                        english: "Retest 20-60s weekly with the same camera position and lighting."
                    ),
                    success: L10n.choose(
                        simplifiedChinese: "关键指标连续稳定（BDC、相位漂移、前后视对位/重心）。",
                        english: "Key metrics remain stable over sessions (BDC, phase drift, front/rear alignment)."
                    )
                )
            )
        }

        let sorted = candidates.sorted { lhs, rhs in
            if abs(lhs.score - rhs.score) > 0.0001 {
                return lhs.score > rhs.score
            }

            let lhsPriority = domainPriority(lhs.domain)
            let rhsPriority = domainPriority(rhs.domain)
            return lhsPriority < rhsPriority
        }

        return sorted.enumerated().map { index, candidate in
            BikeFitAdjustmentStep(
                priority: index + 1,
                domain: candidate.domain,
                title: candidate.title,
                impactScore: clamped(candidate.score, min: 0, max: 99),
                rationale: candidate.rationale,
                maxAdjustmentPerStep: candidate.maxAdjustment,
                retestCondition: candidate.retest,
                successCriteria: candidate.success
            )
        }
    }

    private static func domainPriority(_ domain: BikeFitAdjustmentDomain) -> Int {
        switch domain {
        case .capture: return 0
        case .saddleHeight: return 1
        case .saddleForeAft: return 2
        case .cleatAndStance: return 3
        case .pelvicAndCore: return 4
        case .baseline: return 9
        }
    }

    private static func saddleAdjustmentLabel(_ direction: SaddleHeightAdjustmentDirection) -> String {
        switch direction {
        case .raise:
            return L10n.choose(simplifiedChinese: "升高座高", english: "raise saddle")
        case .lower:
            return L10n.choose(simplifiedChinese: "降低座高", english: "lower saddle")
        case .keep:
            return L10n.choose(simplifiedChinese: "微调座高", english: "micro-adjust saddle")
        }
    }

    private static func buildFrontTrajectoryAssessment(
        frontAlignment: FrontAlignmentStats?,
        frontTrajectory: FrontTrajectoryStats?
    ) -> FrontTrajectoryAssessment? {
        guard let frontTrajectory else { return nil }

        let kneeRangeMin = 0.16
        let kneeRangeMax = 0.36
        let ankleRangeMin = 0.12
        let ankleRangeMax = 0.28
        let toeRangeMin = 0.14
        let toeRangeMax = 0.34
        let inRangeRatioMin = 0.70
        let asymmetryMax = 0.10

        let kneeDev = rangeDeviation(frontTrajectory.kneeTrajectorySpanNorm, min: kneeRangeMin, max: kneeRangeMax)
        let ankleDev = rangeDeviation(frontTrajectory.ankleTrajectorySpanNorm, min: ankleRangeMin, max: ankleRangeMax)
        let toeDev = frontTrajectory.toeTrajectorySpanNorm.map {
            rangeDeviation($0, min: toeRangeMin, max: toeRangeMax)
        } ?? 0
        let ratioDev = max(0, inRangeRatioMin - frontTrajectory.kneeOverAnkleInRangeRatio)
        let asym = frontAlignment?.kneeTrackAsymmetry
        let asymDev = max(0, (asym ?? 0) - asymmetryMax)

        let score = clamped(
            kneeDev * 180 +
                ankleDev * 220 +
                toeDev * 180 +
                ratioDev * 140 +
                asymDev * 160,
            min: 0,
            max: 100
        )

        let kneeInRange = kneeDev <= 0.0001
        let ankleInRange = ankleDev <= 0.0001
        let toeInRange = frontTrajectory.toeTrajectorySpanNorm.map { rangeDeviation($0, min: toeRangeMin, max: toeRangeMax) <= 0.0001 }
        let ratioPass = ratioDev <= 0.0001
        let asymPass = asym.map { max(0, $0 - asymmetryMax) <= 0.0001 }

        var flags: [String] = []
        if !kneeInRange {
            flags.append(L10n.choose(simplifiedChinese: "膝轨迹超出合理区间", english: "knee path is out of range"))
        }
        if !ankleInRange {
            flags.append(L10n.choose(simplifiedChinese: "踝轨迹超出合理区间", english: "ankle path is out of range"))
        }
        if toeInRange == false {
            flags.append(L10n.choose(simplifiedChinese: "足尖轨迹超出合理区间", english: "toe path is out of range"))
        }
        if !ratioPass {
            flags.append(L10n.choose(simplifiedChinese: "膝踝对位占比偏低", english: "knee-over-ankle ratio is low"))
        }
        if asymPass == false {
            flags.append(L10n.choose(simplifiedChinese: "左右轨迹不对称", english: "left-right track asymmetry is high"))
        }

        return FrontTrajectoryAssessment(
            riskLevel: riskLevelFromScore(score),
            riskScore: score,
            kneeSpanNorm: frontTrajectory.kneeTrajectorySpanNorm,
            ankleSpanNorm: frontTrajectory.ankleTrajectorySpanNorm,
            toeSpanNorm: frontTrajectory.toeTrajectorySpanNorm,
            inRangeRatio: frontTrajectory.kneeOverAnkleInRangeRatio,
            kneeTrackAsymmetry: asym,
            kneeRangeMinNorm: kneeRangeMin,
            kneeRangeMaxNorm: kneeRangeMax,
            ankleRangeMinNorm: ankleRangeMin,
            ankleRangeMaxNorm: ankleRangeMax,
            toeRangeMinNorm: toeRangeMin,
            toeRangeMaxNorm: toeRangeMax,
            inRangeRatioMin: inRangeRatioMin,
            asymmetryMax: asymmetryMax,
            kneeSpanInRange: kneeInRange,
            ankleSpanInRange: ankleInRange,
            toeSpanInRange: toeInRange,
            inRangeRatioPass: ratioPass,
            asymmetryPass: asymPass,
            flags: flags
        )
    }

    private static func buildRearStabilityAssessment(
        rearPelvic: RearPelvicStats?,
        rearStability: RearStabilityStats?,
        rearCoordination: PedalingCoordinationStats?
    ) -> RearStabilityAssessment? {
        guard let rearStability else { return nil }

        let meanPelvicThreshold = 3.5
        let maxPelvicThreshold = 6.0
        let meanCenterThreshold = 0.10
        let maxCenterThreshold = 0.22
        let lateralBiasThreshold = 0.05
        let shunGuaiCorrThreshold = 0.55

        let meanPelvic = rearPelvic?.meanPelvicTiltDeg
        let maxPelvic = rearPelvic?.maxPelvicTiltDeg
        let meanPelvicDev = meanPelvic.map { max(0, abs($0) - meanPelvicThreshold) } ?? 0
        let maxPelvicDev = maxPelvic.map { max(0, $0 - maxPelvicThreshold) } ?? 0
        let meanCenterDev = max(0, rearStability.meanCenterShiftNorm - meanCenterThreshold)
        let maxCenterDev = max(0, rearStability.maxCenterShiftNorm - maxCenterThreshold)
        let lateralBiasDev = max(0, abs(rearStability.lateralBias) - lateralBiasThreshold)
        let corr = rearCoordination?.kneeLateralCorrelation
        let corrDev = max(0, (corr ?? 0) - shunGuaiCorrThreshold)
        let shunGuaiSuspected = rearCoordination?.isShunGuaiSuspected == true

        let score = clamped(
            meanPelvicDev * 5.0 +
                maxPelvicDev * 6.0 +
                meanCenterDev * 260 +
                maxCenterDev * 220 +
                lateralBiasDev * 320 +
                corrDev * 70 +
                (shunGuaiSuspected ? 20 : 0),
            min: 0,
            max: 100
        )

        let meanPelvicPass = meanPelvic.map { abs($0) <= meanPelvicThreshold }
        let maxPelvicPass = maxPelvic.map { $0 <= maxPelvicThreshold }
        let meanCenterPass = meanCenterDev <= 0.0001
        let maxCenterPass = maxCenterDev <= 0.0001
        let lateralBiasPass = lateralBiasDev <= 0.0001
        let shunGuaiPass = !shunGuaiSuspected

        var flags: [String] = []
        if meanPelvicPass == false {
            flags.append(L10n.choose(simplifiedChinese: "平均盆骨倾斜偏大", english: "mean pelvic tilt is high"))
        }
        if maxPelvicPass == false {
            flags.append(L10n.choose(simplifiedChinese: "最大盆骨倾斜超标", english: "max pelvic tilt is too high"))
        }
        if !meanCenterPass {
            flags.append(L10n.choose(simplifiedChinese: "重心平均漂移偏大", english: "mean CoM drift is high"))
        }
        if !maxCenterPass {
            flags.append(L10n.choose(simplifiedChinese: "重心峰值漂移偏大", english: "peak CoM drift is high"))
        }
        if !lateralBiasPass {
            flags.append(L10n.choose(simplifiedChinese: "重心左右偏置明显", english: "lateral CoM bias is high"))
        }
        if !shunGuaiPass {
            flags.append(L10n.choose(simplifiedChinese: "顺拐风险升高", english: "shun-guai risk is elevated"))
        }

        return RearStabilityAssessment(
            riskLevel: riskLevelFromScore(score),
            riskScore: score,
            meanPelvicTiltDeg: meanPelvic,
            maxPelvicTiltDeg: maxPelvic,
            meanCenterShiftNorm: rearStability.meanCenterShiftNorm,
            maxCenterShiftNorm: rearStability.maxCenterShiftNorm,
            lateralBias: rearStability.lateralBias,
            kneeLateralCorrelation: corr,
            isShunGuaiSuspected: shunGuaiSuspected,
            meanPelvicTiltThresholdDeg: meanPelvicThreshold,
            maxPelvicTiltThresholdDeg: maxPelvicThreshold,
            meanCenterShiftThreshold: meanCenterThreshold,
            maxCenterShiftThreshold: maxCenterThreshold,
            lateralBiasThreshold: lateralBiasThreshold,
            shunGuaiCorrelationThreshold: shunGuaiCorrThreshold,
            meanPelvicPass: meanPelvicPass,
            maxPelvicPass: maxPelvicPass,
            meanCenterShiftPass: meanCenterPass,
            maxCenterShiftPass: maxCenterPass,
            lateralBiasPass: lateralBiasPass,
            shunGuaiPass: shunGuaiPass,
            flags: flags
        )
    }

    private static func riskLevelFromScore(_ score: Double) -> FittingRiskLevel {
        if score >= 58 { return .high }
        if score >= 28 { return .moderate }
        return .low
    }

    private static func rangeDeviation(_ value: Double, min minValue: Double, max maxValue: Double) -> Double {
        if value < minValue { return minValue - value }
        if value > maxValue { return value - maxValue }
        return 0
    }

    private static func extractRearCoordination(samples: [VideoJointAngleSample]) -> PedalingCoordinationStats? {
        var leftSeries: [Double] = []
        var rightSeries: [Double] = []
        for sample in samples {
            guard
                let leftKnee = sample.leftKnee,
                let rightKnee = sample.rightKnee,
                let leftHip = sample.leftHip,
                let rightHip = sample.rightHip
            else {
                continue
            }
            leftSeries.append(leftKnee.x - leftHip.x)
            rightSeries.append(rightKnee.x - rightHip.x)
        }

        let count = min(leftSeries.count, rightSeries.count)
        guard count >= 12 else { return nil }
        let corr = pearsonCorrelation(
            x: Array(leftSeries.prefix(count)),
            y: Array(rightSeries.prefix(count))
        )
        let suspected = corr > 0.55 && count >= 30
        return PedalingCoordinationStats(
            kneeLateralCorrelation: corr,
            isShunGuaiSuspected: suspected,
            sampleCount: count
        )
    }

    private static func phaseAngleDegrees(hip: PoseJointPoint?, ankle: PoseJointPoint?) -> Double? {
        guard let hip, let ankle else { return nil }
        let dx = ankle.x - hip.x
        let dy = ankle.y - hip.y
        guard abs(dx) + abs(dy) > 0.000001 else { return nil }
        let raw = atan2(dx, dy) * 180.0 / Double.pi
        return normalizeDegrees(raw)
    }

    private static func circularPhaseDifference(_ lhs: Double, _ rhs: Double) -> Double {
        let delta = abs(normalizeDegrees(lhs) - normalizeDegrees(rhs))
        return min(delta, 360 - delta)
    }

    private static func normalizeDegrees(_ value: Double) -> Double {
        var v = value.truncatingRemainder(dividingBy: 360)
        if v < 0 { v += 360 }
        return v
    }

    private static func approximateToePoint(knee: PoseJointPoint?, ankle: PoseJointPoint) -> PoseJointPoint {
        guard let knee else {
            return PoseJointPoint(x: ankle.x, y: ankle.y, confidence: ankle.confidence * 0.6)
        }
        let vx = ankle.x - knee.x
        let vy = ankle.y - knee.y
        let scale = 0.35
        return PoseJointPoint(
            x: ankle.x + vx * scale,
            y: ankle.y + vy * scale,
            confidence: min(ankle.confidence, knee.confidence) * 0.7
        )
    }

    private static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let count = sorted.count
        if count % 2 == 1 {
            return sorted[count / 2]
        }
        return (sorted[count / 2 - 1] + sorted[count / 2]) / 2.0
    }

    private static func jointPoint(
        _ name: VNHumanBodyPoseObservation.JointName,
        in points: [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint]
    ) -> PoseJointPoint? {
        guard let point = points[name], point.confidence >= minJointConfidence else { return nil }
        return PoseJointPoint(
            x: Double(point.location.x),
            y: Double(point.location.y),
            confidence: Double(point.confidence)
        )
    }

    @available(macOS 14.0, iOS 17.0, tvOS 17.0, *)
    private static func jointPoint3D(
        _ name: VNHumanBodyPose3DObservation.JointName,
        in observation: VNHumanBodyPose3DObservation
    ) -> SIMD3<Double>? {
        guard let point = try? observation.recognizedPoint(name) else { return nil }
        let matrix = point.position
        let translation = matrix.columns.3
        return SIMD3<Double>(
            Double(translation.x),
            Double(translation.y),
            Double(translation.z)
        )
    }

    private static func angleDegrees3D(a: SIMD3<Double>, b: SIMD3<Double>, c: SIMD3<Double>) -> Double? {
        let ba = a - b
        let bc = c - b
        let dot = simd_dot(ba, bc)
        let magBA = simd_length(ba)
        let magBC = simd_length(bc)
        guard magBA > 0.000001, magBC > 0.000001 else { return nil }
        let cosine = max(-1.0, min(1.0, dot / (magBA * magBC)))
        return acos(cosine) * 180.0 / Double.pi
    }

    private static func angleDegrees(a: CGPoint, b: CGPoint, c: CGPoint) -> Double? {
        let ba = CGVector(dx: a.x - b.x, dy: a.y - b.y)
        let bc = CGVector(dx: c.x - b.x, dy: c.y - b.y)
        let dot = ba.dx * bc.dx + ba.dy * bc.dy
        let magBA = hypot(ba.dx, ba.dy)
        let magBC = hypot(bc.dx, bc.dy)
        guard magBA > 0.000001, magBC > 0.000001 else { return nil }
        let cosine = max(-1.0, min(1.0, dot / (magBA * magBC)))
        return acos(cosine) * 180.0 / Double.pi
    }

    private static func dominantSide(from samples: [VideoJointAngleSample]) -> VideoPoseBodySide {
        let leftCount = samples.filter { $0.side == .left }.count
        let rightCount = samples.filter { $0.side == .right }.count
        if leftCount == rightCount { return .unknown }
        return leftCount > rightCount ? .left : .right
    }

    private static func stats(for values: [Double]) -> JointAngleStats? {
        guard !values.isEmpty else { return nil }
        let minValue = values.min() ?? 0
        let maxValue = values.max() ?? 0
        let mean = values.reduce(0, +) / Double(values.count)
        return JointAngleStats(
            min: minValue,
            max: maxValue,
            mean: mean,
            sampleCount: values.count
        )
    }

    private static func mean(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private static func linearSlopePerMinute(pairs: [(x: Double, y: Double)]) -> Double? {
        guard pairs.count >= 3 else { return nil }
        let xs = pairs.map(\.x)
        let ys = pairs.map(\.y)
        let meanX = xs.reduce(0, +) / Double(xs.count)
        let meanY = ys.reduce(0, +) / Double(ys.count)

        var numerator = 0.0
        var denominator = 0.0
        for idx in pairs.indices {
            let dx = xs[idx] - meanX
            numerator += dx * (ys[idx] - meanY)
            denominator += dx * dx
        }
        guard denominator > 0.0000001 else { return nil }
        return (numerator / denominator) * 60.0
    }

    private static func clamped(_ value: Double, min minValue: Double, max maxValue: Double) -> Double {
        Swift.max(minValue, Swift.min(maxValue, value))
    }

    private enum MediaPipePoseEstimator {
        struct Result {
            let samples: [VideoJointAngleSample]
            let warnings: [String]
        }

        private struct RawJoint: Decodable {
            let x: Double
            let y: Double
            let confidence: Double
        }

        private struct RawFrame: Decodable {
            let id: Int
            let timeSeconds: Double
            let joints: [String: RawJoint]
            let leftKneeAngleDeg: Double?
            let leftHipAngleDeg: Double?
            let rightKneeAngleDeg: Double?
            let rightHipAngleDeg: Double?

            private enum CodingKeys: String, CodingKey {
                case id
                case timeSeconds = "time_seconds"
                case joints
                case leftKneeAngleDeg = "left_knee_angle_deg"
                case leftHipAngleDeg = "left_hip_angle_deg"
                case rightKneeAngleDeg = "right_knee_angle_deg"
                case rightHipAngleDeg = "right_hip_angle_deg"
            }
        }

        private struct RawOutput: Decodable {
            let backend: String?
            let samples: [RawFrame]
            let warnings: [String]?
        }

        static func sampleVideo(videoURL: URL, maxSamples: Int) throws -> Result {
            guard let scriptPath = resolveScriptPath() else {
                throw NSError(
                    domain: "Fricu.VideoPose.MediaPipe",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "MediaPipe script not found"]
                )
            }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [
                "python3",
                scriptPath,
                "--video", videoURL.path,
                "--max-samples", String(maxSamples)
            ]

            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr

            try process.run()
            process.waitUntilExit()

            let outData = stdout.fileHandleForReading.readDataToEndOfFile()
            let errData = stderr.fileHandleForReading.readDataToEndOfFile()

            guard process.terminationStatus == 0 else {
                let errorText = String(data: errData, encoding: .utf8) ?? "unknown error"
                throw NSError(
                    domain: "Fricu.VideoPose.MediaPipe",
                    code: Int(process.terminationStatus),
                    userInfo: [NSLocalizedDescriptionKey: errorText]
                )
            }

            let decoder = JSONDecoder()
            let payload = try decoder.decode(RawOutput.self, from: outData)
            let mapped = payload.samples.compactMap(mapFrameToSample)
            return Result(samples: mapped, warnings: payload.warnings ?? [])
        }

        private static func mapFrameToSample(_ frame: RawFrame) -> VideoJointAngleSample? {
            let leftShoulder = point("left_shoulder", in: frame.joints)
            let leftHip = point("left_hip", in: frame.joints)
            let leftKnee = point("left_knee", in: frame.joints)
            let leftAnkle = point("left_ankle", in: frame.joints)
            let leftToe = point("left_foot_index", in: frame.joints) ?? point("left_toe", in: frame.joints)

            let rightShoulder = point("right_shoulder", in: frame.joints)
            let rightHip = point("right_hip", in: frame.joints)
            let rightKnee = point("right_knee", in: frame.joints)
            let rightAnkle = point("right_ankle", in: frame.joints)
            let rightToe = point("right_foot_index", in: frame.joints) ?? point("right_toe", in: frame.joints)

            let leftKneeAngle = frame.leftKneeAngleDeg ?? angle(leftHip, leftKnee, leftAnkle)
            let leftHipAngle = frame.leftHipAngleDeg ?? angle(leftShoulder, leftHip, leftKnee)
            let rightKneeAngle = frame.rightKneeAngleDeg ?? angle(rightHip, rightKnee, rightAnkle)
            let rightHipAngle = frame.rightHipAngleDeg ?? angle(rightShoulder, rightHip, rightKnee)

            let leftConfidence = averageConfidence([leftShoulder, leftHip, leftKnee, leftAnkle])
            let rightConfidence = averageConfidence([rightShoulder, rightHip, rightKnee, rightAnkle])

            let side: VideoPoseBodySide
            let confidence: Double
            let kneeAngle: Double?
            let hipAngle: Double?
            if leftConfidence >= rightConfidence {
                side = .left
                confidence = leftConfidence
                kneeAngle = leftKneeAngle
                hipAngle = leftHipAngle
            } else {
                side = .right
                confidence = rightConfidence
                kneeAngle = rightKneeAngle
                hipAngle = rightHipAngle
            }

            guard kneeAngle != nil || hipAngle != nil else { return nil }

            let resolvedLeftToe = leftToe ?? leftAnkle.map { VideoJointAngleAnalyzer.approximateToePoint(knee: leftKnee, ankle: $0) }
            let resolvedRightToe = rightToe ?? rightAnkle.map { VideoJointAngleAnalyzer.approximateToePoint(knee: rightKnee, ankle: $0) }
            let phase = VideoJointAngleAnalyzer.phaseAngleDegrees(
                hip: side == .right ? rightHip : leftHip,
                ankle: side == .right ? rightAnkle : leftAnkle
            )

            return VideoJointAngleSample(
                id: frame.id,
                timeSeconds: frame.timeSeconds,
                side: side,
                confidence: confidence,
                kneeAngleDeg: kneeAngle,
                hipAngleDeg: hipAngle,
                crankPhaseDeg: phase,
                leftHip: leftHip,
                leftKnee: leftKnee,
                leftAnkle: leftAnkle,
                rightHip: rightHip,
                rightKnee: rightKnee,
                rightAnkle: rightAnkle,
                leftToe: resolvedLeftToe,
                rightToe: resolvedRightToe
            )
        }

        private static func point(_ key: String, in joints: [String: RawJoint]) -> PoseJointPoint? {
            guard let raw = joints[key], raw.confidence > 0 else { return nil }
            return PoseJointPoint(x: raw.x, y: raw.y, confidence: raw.confidence)
        }

        private static func averageConfidence(_ points: [PoseJointPoint?]) -> Double {
            let values = points.compactMap { $0?.confidence }
            guard !values.isEmpty else { return 0 }
            return values.reduce(0, +) / Double(values.count)
        }

        private static func angle(_ a: PoseJointPoint?, _ b: PoseJointPoint?, _ c: PoseJointPoint?) -> Double? {
            guard let a, let b, let c else { return nil }
            return VideoJointAngleAnalyzer.angleDegrees(a: a.cgPoint, b: b.cgPoint, c: c.cgPoint)
        }

        private static func resolveScriptPath() -> String? {
            let fm = FileManager.default
            let cwd = URL(fileURLWithPath: fm.currentDirectoryPath, isDirectory: true)
            let bundle = Bundle.main
            let candidates: [String] = [
                bundle.resourceURL?.appendingPathComponent("PoseModels/video_pose_mediapipe.py").path,
                bundle.bundleURL.appendingPathComponent("Contents/Resources/PoseModels/video_pose_mediapipe.py").path,
                cwd.appendingPathComponent("Sources/FricuApp/Resources/PoseModels/video_pose_mediapipe.py").path,
                cwd.appendingPathComponent("scripts/video_pose_mediapipe.py").path
            ].compactMap { $0 }

            for path in candidates where fm.fileExists(atPath: path) {
                return path
            }
            return nil
        }
    }

    private static func pearsonCorrelation(x: [Double], y: [Double]) -> Double {
        let count = min(x.count, y.count)
        guard count > 1 else { return 0 }
        let xSlice = x.prefix(count)
        let ySlice = y.prefix(count)
        let xMean = xSlice.reduce(0, +) / Double(count)
        let yMean = ySlice.reduce(0, +) / Double(count)

        var numerator = 0.0
        var xVariance = 0.0
        var yVariance = 0.0
        for idx in 0..<count {
            let dx = x[idx] - xMean
            let dy = y[idx] - yMean
            numerator += dx * dy
            xVariance += dx * dx
            yVariance += dy * dy
        }
        let denominator = sqrt(max(0.0000001, xVariance * yVariance))
        return numerator / denominator
    }
}
