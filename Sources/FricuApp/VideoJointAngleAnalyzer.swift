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
    case mmposeMotionBERT
    case mediaPipeBlazePoseGHUM
    case appleVision

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .auto:
            return L10n.choose(simplifiedChinese: "自动（优先 MotionAGFormer-L 3D）", english: "Auto (prefer MotionAGFormer-L 3D)")
        case .mmposeMotionBERT:
            return L10n.choose(simplifiedChinese: "MotionAGFormer-L 3D", english: "MotionAGFormer-L 3D")
        case .mediaPipeBlazePoseGHUM:
            return L10n.choose(simplifiedChinese: "BlazePose GHUM（GitHub/MediaPipe）", english: "BlazePose GHUM (GitHub/MediaPipe)")
        case .appleVision:
            return L10n.choose(simplifiedChinese: "Apple Vision 3D/2D", english: "Apple Vision 3D/2D")
        }
    }
}

/// Locates a bundled Python runtime packaged inside the desktop app for external 3D pose inference.
struct MotionBERTRuntimeLocator {
    static let runtimeDirectoryName = "MotionBERTRuntime"

    /// Resolves the packaged runtime root when the build includes a bundled external 3D environment.
    func resolveBundledRuntimeRootURL(
        bundle: Bundle = .main,
        fallbackSearchRoots: [URL] = []
    ) -> URL? {
        let fm = FileManager.default
        let bundledCandidates: [URL] = [
            bundle.resourceURL?.appendingPathComponent(Self.runtimeDirectoryName, isDirectory: true),
            bundle.bundleURL.appendingPathComponent("Contents/Resources/\(Self.runtimeDirectoryName)", isDirectory: true)
        ].compactMap { $0 }

        for root in fallbackSearchRoots {
            let rootCandidates = [
                root.appendingPathComponent(Self.runtimeDirectoryName, isDirectory: true),
                root
            ]
            for candidate in rootCandidates where fm.fileExists(atPath: candidate.path) {
                return candidate
            }
        }

        for candidate in bundledCandidates where fm.fileExists(atPath: candidate.path) {
            return candidate
        }

        return nil
    }

    /// Resolves the bundled python executable path inside the packaged external 3D runtime.
    func resolveBundledPythonPath(
        bundle: Bundle = .main,
        fallbackSearchRoots: [URL] = []
    ) -> String? {
        let fm = FileManager.default
        guard let runtimeRoot = resolveBundledRuntimeRootURL(bundle: bundle, fallbackSearchRoots: fallbackSearchRoots) else {
            return nil
        }

        let candidates = [
            runtimeRoot.appendingPathComponent("bin/python3").path,
            runtimeRoot.appendingPathComponent("bin/python").path
        ]

        for candidate in candidates where fm.isExecutableFile(atPath: candidate) {
            return candidate
        }

        return nil
    }

    /// Resolves an optional packaged cache root copied alongside the bundled runtime.
    func resolveBundledCacheRootURL(
        bundle: Bundle = .main,
        fallbackSearchRoots: [URL] = []
    ) -> URL? {
        let fm = FileManager.default
        guard let runtimeRoot = resolveBundledRuntimeRootURL(bundle: bundle, fallbackSearchRoots: fallbackSearchRoots) else {
            return nil
        }

        let cacheRoot = runtimeRoot.appendingPathComponent("cache", isDirectory: true)
        let packagedCacheDirectories = [
            cacheRoot.appendingPathComponent("mim", isDirectory: true).path,
            cacheRoot.appendingPathComponent("openmmlab", isDirectory: true).path,
            cacheRoot.appendingPathComponent("torch", isDirectory: true).path
        ]
        guard packagedCacheDirectories.contains(where: { fm.fileExists(atPath: $0) }) else {
            return nil
        }
        return cacheRoot
    }
}

struct BikeKeypointModelLocator {
    static let modelDirectoryName = "BikeKeypointModel"
    static let preferredCheckpointDefaultsKey = "fricu.bike.keypoint.checkpoint.override.v1"

    func resolveBundledModelRootURL(
        bundle: Bundle = .main,
        fallbackSearchRoots: [URL] = []
    ) -> URL? {
        let fm = FileManager.default
        let bundledCandidates: [URL] = [
            bundle.resourceURL?.appendingPathComponent(Self.modelDirectoryName, isDirectory: true),
            bundle.bundleURL.appendingPathComponent("Contents/Resources/\(Self.modelDirectoryName)", isDirectory: true)
        ].compactMap { $0 }

        for root in fallbackSearchRoots {
            let rootCandidates = [
                root.appendingPathComponent(Self.modelDirectoryName, isDirectory: true),
                root
            ]
            for candidate in rootCandidates where fm.fileExists(atPath: candidate.path) {
                return candidate
            }
        }

        for candidate in bundledCandidates where fm.fileExists(atPath: candidate.path) {
            return candidate
        }

        return nil
    }

    func resolveBundledCheckpointURL(
        bundle: Bundle = .main,
        fallbackSearchRoots: [URL] = []
    ) -> URL? {
        let fm = FileManager.default
        guard let modelRoot = resolveBundledModelRootURL(bundle: bundle, fallbackSearchRoots: fallbackSearchRoots) else {
            return nil
        }

        let candidates = [
            modelRoot.appendingPathComponent("best.pt", isDirectory: false),
            modelRoot.appendingPathComponent("checkpoint.pt", isDirectory: false)
        ]

        for candidate in candidates where fm.fileExists(atPath: candidate.path) {
            return candidate
        }
        return nil
    }

    func resolveCheckpointURL(
        bundle: Bundle = .main,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        currentDirectoryPath: String = FileManager.default.currentDirectoryPath,
        fallbackSearchRoots: [URL] = []
    ) -> URL? {
        let fm = FileManager.default

        if let explicitCheckpoint = environment["FRICU_BIKE_KEYPOINT_CHECKPOINT"] {
            let url = URL(fileURLWithPath: explicitCheckpoint)
            if fm.fileExists(atPath: url.path) {
                return url
            }
        }

        if let preferredCheckpoint = UserDefaults.standard.string(forKey: Self.preferredCheckpointDefaultsKey) {
            let url = URL(fileURLWithPath: preferredCheckpoint)
            if fm.fileExists(atPath: url.path) {
                return url
            }
        }

        if let bundled = resolveBundledCheckpointURL(bundle: bundle, fallbackSearchRoots: fallbackSearchRoots) {
            return bundled
        }

        if let explicitModelDirectory = environment["FRICU_BIKE_KEYPOINT_MODEL_DIR"] {
            let candidate = URL(fileURLWithPath: explicitModelDirectory).appendingPathComponent("best.pt", isDirectory: false)
            if fm.fileExists(atPath: candidate.path) {
                return candidate
            }
        }

        let searchRoots = fallbackSearchRoots + [
            URL(fileURLWithPath: currentDirectoryPath, isDirectory: true)
                .appendingPathComponent(".runtime/BikeKeypointSelfTrain", isDirectory: true),
            URL(fileURLWithPath: currentDirectoryPath, isDirectory: true)
                .appendingPathComponent("runtime/BikeKeypointSelfTrain", isDirectory: true)
        ]

        var newestMatch: (url: URL, modificationDate: Date)?
        for root in searchRoots where fm.fileExists(atPath: root.path) {
            let enumerator = fm.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )
            while let fileURL = enumerator?.nextObject() as? URL {
                guard fileURL.lastPathComponent == "best.pt" else { continue }
                guard
                    let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey]),
                    values.isRegularFile == true
                else {
                    continue
                }
                let modificationDate = values.contentModificationDate ?? .distantPast
                if newestMatch == nil || modificationDate > newestMatch?.modificationDate ?? .distantPast {
                    newestMatch = (fileURL, modificationDate)
                }
            }
        }

        return newestMatch?.url
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
    case point6
    case point9

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .point0: return "0"
        case .point3: return "3"
        case .point6: return "6"
        case .point9: return "9"
        }
    }

    var positionTitle: String {
        switch self {
        case .point0:
            return L10n.choose(simplifiedChinese: "上死点", english: "Top Dead Center")
        case .point3:
            return L10n.choose(simplifiedChinese: "右水平", english: "Right Horizontal")
        case .point6:
            return L10n.choose(simplifiedChinese: "下死点", english: "Bottom Dead Center")
        case .point9:
            return L10n.choose(simplifiedChinese: "左水平", english: "Left Horizontal")
        }
    }

    var clockfaceTitle: String {
        switch self {
        case .point0:
            return L10n.choose(simplifiedChinese: "12 点位", english: "12 o'clock")
        case .point3:
            return L10n.choose(simplifiedChinese: "3 点位", english: "3 o'clock")
        case .point6:
            return L10n.choose(simplifiedChinese: "6 点位", english: "6 o'clock")
        case .point9:
            return L10n.choose(simplifiedChinese: "9 点位", english: "9 o'clock")
        }
    }

    // 0 点=0°（上止点），3 点=90°（前水平），6 点=180°（下止点），9 点=270°（后水平）。
    var targetPhaseDeg: Double {
        switch self {
        case .point0: return 0
        case .point3: return 90
        case .point6: return 180
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
    var ankleAngleDeg: Double? = nil

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
    var ankleAngleDeg: Double? = nil
    var shoulderAngleDeg: Double? = nil
    var elbowAngleDeg: Double? = nil
    let crankPhaseDeg: Double?

    let leftShoulder: PoseJointPoint?
    let leftElbow: PoseJointPoint?
    let leftWrist: PoseJointPoint?
    let leftHip: PoseJointPoint?
    let leftKnee: PoseJointPoint?
    let leftAnkle: PoseJointPoint?
    let rightShoulder: PoseJointPoint?
    let rightElbow: PoseJointPoint?
    let rightWrist: PoseJointPoint?
    let rightHip: PoseJointPoint?
    let rightKnee: PoseJointPoint?
    let rightAnkle: PoseJointPoint?
    let leftToe: PoseJointPoint?
    let rightToe: PoseJointPoint?
    let bikeBottomBracket: PoseJointPoint?
    let bikeCrankEnd: PoseJointPoint?
    let bikePedalCenter: PoseJointPoint?

    init(
        id: Int,
        timeSeconds: Double,
        side: VideoPoseBodySide,
        confidence: Double,
        kneeAngleDeg: Double?,
        hipAngleDeg: Double?,
        ankleAngleDeg: Double? = nil,
        shoulderAngleDeg: Double? = nil,
        elbowAngleDeg: Double? = nil,
        crankPhaseDeg: Double?,
        leftShoulder: PoseJointPoint?,
        leftElbow: PoseJointPoint? = nil,
        leftWrist: PoseJointPoint? = nil,
        leftHip: PoseJointPoint?,
        leftKnee: PoseJointPoint?,
        leftAnkle: PoseJointPoint?,
        rightShoulder: PoseJointPoint?,
        rightElbow: PoseJointPoint? = nil,
        rightWrist: PoseJointPoint? = nil,
        rightHip: PoseJointPoint?,
        rightKnee: PoseJointPoint?,
        rightAnkle: PoseJointPoint?,
        leftToe: PoseJointPoint?,
        rightToe: PoseJointPoint?,
        bikeBottomBracket: PoseJointPoint? = nil,
        bikeCrankEnd: PoseJointPoint? = nil,
        bikePedalCenter: PoseJointPoint? = nil
    ) {
        self.id = id
        self.timeSeconds = timeSeconds
        self.side = side
        self.confidence = confidence
        self.kneeAngleDeg = kneeAngleDeg
        self.hipAngleDeg = hipAngleDeg
        self.ankleAngleDeg = ankleAngleDeg
        self.shoulderAngleDeg = shoulderAngleDeg
        self.elbowAngleDeg = elbowAngleDeg
        self.crankPhaseDeg = crankPhaseDeg
        self.leftShoulder = leftShoulder
        self.leftElbow = leftElbow
        self.leftWrist = leftWrist
        self.leftHip = leftHip
        self.leftKnee = leftKnee
        self.leftAnkle = leftAnkle
        self.rightShoulder = rightShoulder
        self.rightElbow = rightElbow
        self.rightWrist = rightWrist
        self.rightHip = rightHip
        self.rightKnee = rightKnee
        self.rightAnkle = rightAnkle
        self.leftToe = leftToe
        self.rightToe = rightToe
        self.bikeBottomBracket = bikeBottomBracket
        self.bikeCrankEnd = bikeCrankEnd
        self.bikePedalCenter = bikePedalCenter
    }
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
    let crankCenter: PoseJointPoint?
    let crankRadius: Double?
    let used3DAngleFrameCount: Int
    let kneeStats: JointAngleStats?
    let hipStats: JointAngleStats?
    var ankleStats: JointAngleStats? = nil
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
    var bikeKeypointModelText: String? = nil
    var bikeKeypointFallbackNote: String? = nil
}

struct External3DAngleSample {
    let timeSeconds: Double
    let leftKneeAngleDeg: Double?
    let leftHipAngleDeg: Double?
    var leftAnkleAngleDeg: Double? = nil
    let rightKneeAngleDeg: Double?
    let rightHipAngleDeg: Double?
    var rightAnkleAngleDeg: Double? = nil
    let confidence: Double
}

struct BikeKeypointSample {
    let id: Int
    let timeSeconds: Double
    let confidence: Double
    let bbCenter: PoseJointPoint?
    let crankEnd: PoseJointPoint?
    let pedalCenter: PoseJointPoint?
}

struct BikeKeypointSummary {
    let bbCenter: PoseJointPoint?
    let radius: Double?
    let fitRMS: Double?
}

struct VideoJointAngleAnalysisProgressUpdate: Sendable {
    let message: String
}

actor VideoJointAngleAnalysisProgressReporter {
    typealias Handler = @MainActor @Sendable (VideoJointAngleAnalysisProgressUpdate) -> Void

    private let handler: Handler

    init(handler: @escaping Handler) {
        self.handler = handler
    }

    func publish(_ update: VideoJointAngleAnalysisProgressUpdate) async {
        await handler(update)
    }
}

struct VideoJointAngleAnalyzer {
    private static let minJointConfidence: Float = 0.2

    func analyze(
        videoURL: URL,
        maxSamples: Int = 180,
        requestedView: CyclingCameraView = .side,
        preferredModel: VideoPoseEstimationModel = .auto,
        progressReporter: VideoJointAngleAnalysisProgressReporter? = nil
    ) async throws -> VideoJointAngleAnalysisResult {
        try await Task.detached(priority: .utility) {
            await Self.publishProgress(
                progressReporter,
                message: L10n.choose(
                    simplifiedChinese: "正在读取视频元数据并规划识别流程...",
                    english: "Reading video metadata and planning the recognition workflow..."
                )
            )
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
            await Self.publishProgress(
                progressReporter,
                message: L10n.choose(
                    simplifiedChinese: "视频已就绪：源视频约 \(Self.formattedProgressNumber(nominalFPS)) fps，计划抽样 \(targetFrameCount) 帧。",
                    english: "Video ready: source is about \(Self.formattedProgressNumber(nominalFPS)) fps and \(targetFrameCount) frames will be sampled."
                )
            )

            var samples: [VideoJointAngleSample] = []
            samples.reserveCapacity(targetFrameCount)
            var modelUsed: VideoPoseEstimationModel = .appleVision
            var modelFallbackNote: String?
            var modelRuntimeHints: [String] = []
            var used3DAngleFrameCount = 0
            var bikeKeypointModelText: String?
            var bikeKeypointFallbackNote: String?
            let allowsExternalPythonBackends = Self.allowsExternalPythonPoseBackends
            let attemptOrder = Self.poseModelAttemptOrder(
                preferredModel: preferredModel,
                allowsExternalPythonBackends: allowsExternalPythonBackends
            )
            let usesExternal3DLift = attemptOrder.contains(.mmposeMotionBERT)
            let basePoseOrder = attemptOrder.filter { $0 != .mmposeMotionBERT }

            for candidate in basePoseOrder {
                switch candidate {
                case .mediaPipeBlazePoseGHUM:
                    await Self.publishProgress(
                        progressReporter,
                        message: usesExternal3DLift
                            ? L10n.choose(
                                simplifiedChinese: "正在为 MotionAGFormer-L 准备 2D 骨架底稿：运行 BlazePose GHUM...",
                                english: "Preparing the 2D skeleton for MotionAGFormer-L by running BlazePose GHUM..."
                            )
                            : L10n.choose(
                                simplifiedChinese: "正在运行 BlazePose GHUM 2D 骨点识别...",
                                english: "Running BlazePose GHUM 2D pose recognition..."
                            )
                    )
                    if let mediaPipeResult = try? MediaPipePoseEstimator.sampleVideo(
                        videoURL: videoURL,
                        maxSamples: targetFrameCount
                    ), !mediaPipeResult.samples.isEmpty {
                        samples = mediaPipeResult.samples
                        modelRuntimeHints = mediaPipeResult.warnings
                        modelUsed = .mediaPipeBlazePoseGHUM
                        await Self.publishProgress(
                            progressReporter,
                            message: usesExternal3DLift
                                ? L10n.choose(
                                    simplifiedChinese: "MotionAGFormer-L 的 2D 骨架底稿已准备完成，保留 \(samples.count) 帧有效骨点。",
                                    english: "The 2D skeleton draft for MotionAGFormer-L is ready with \(samples.count) valid frames."
                                )
                                : L10n.choose(
                                    simplifiedChinese: "BlazePose GHUM 已完成，保留 \(samples.count) 帧有效骨点。",
                                    english: "BlazePose GHUM finished with \(samples.count) valid frames."
                                )
                        )
                    } else if preferredModel == .mediaPipeBlazePoseGHUM {
                        modelFallbackNote = L10n.choose(
                            simplifiedChinese: "BlazePose GHUM 不可用，已回退到 Apple Vision。",
                            english: "BlazePose GHUM is unavailable. Fell back to Apple Vision."
                        )
                        await Self.publishProgress(
                            progressReporter,
                            message: modelFallbackNote ?? ""
                        )
                    } else if usesExternal3DLift {
                        await Self.publishProgress(
                            progressReporter,
                            message: L10n.choose(
                                simplifiedChinese: "BlazePose GHUM 当前不可用，改用 Apple Vision 生成 2D 骨架底稿，随后仍会继续尝试 MotionAGFormer-L 3D。",
                                english: "BlazePose GHUM is currently unavailable. Apple Vision will generate the 2D skeleton draft first, and MotionAGFormer-L 3D will still be attempted afterwards."
                            )
                        )
                    }
                case .appleVision:
                    await Self.publishProgress(
                        progressReporter,
                        message: usesExternal3DLift
                            ? L10n.choose(
                                simplifiedChinese: "正在为 MotionAGFormer-L 生成本地 2D 骨架底稿：逐帧运行 Apple Vision...",
                                english: "Generating the local 2D skeleton draft for MotionAGFormer-L with Apple Vision frame by frame..."
                            )
                            : L10n.choose(
                                simplifiedChinese: "正在逐帧运行 Apple Vision 骨点识别...",
                                english: "Running Apple Vision pose recognition frame by frame..."
                            )
                    )
                    let visionResult = try await Self.sampleVideoWithAppleVision(
                        asset: asset,
                        durationSeconds: durationSeconds,
                        interval: interval,
                        targetFrameCount: targetFrameCount,
                        progressReporter: progressReporter
                    )
                    samples = visionResult.samples
                    used3DAngleFrameCount = visionResult.used3DAngleFrameCount
                    modelUsed = .appleVision
                    await Self.publishProgress(
                        progressReporter,
                        message: usesExternal3DLift
                            ? L10n.choose(
                                simplifiedChinese: "MotionAGFormer-L 的本地 2D 骨架底稿已完成，保留 \(samples.count) 帧有效骨点。",
                                english: "The local 2D skeleton draft for MotionAGFormer-L is ready with \(samples.count) valid frames."
                            )
                            : L10n.choose(
                                simplifiedChinese: "Apple Vision 已完成，保留 \(samples.count) 帧有效骨点。",
                                english: "Apple Vision finished with \(samples.count) valid frames."
                            )
                    )
                case .auto, .mmposeMotionBERT:
                    break
                }

                if !samples.isEmpty {
                    break
                }
            }

            guard !samples.isEmpty else {
                throw VideoJointAngleAnalysisError.noPoseDetected
            }

            if attemptOrder.contains(.mmposeMotionBERT) {
                do {
                    await Self.publishProgress(
                        progressReporter,
                        message: L10n.choose(
                            simplifiedChinese: "正在启动 MotionAGFormer-L 3D 推理...",
                            english: "Starting MotionAGFormer-L 3D inference..."
                        )
                    )
                    let motionBERTResult = try await MMPoseMotionBERTEstimator.sampleVideo(
                        videoURL: videoURL,
                        maxSamples: targetFrameCount,
                        progressReporter: progressReporter
                    )
                    await Self.publishProgress(
                        progressReporter,
                        message: L10n.choose(
                            simplifiedChinese: "MotionAGFormer-L 已返回结果，正在融合 3D 关节角...",
                            english: "MotionAGFormer-L returned results. Merging 3D joint angles..."
                        )
                    )
                    let merged = Self.mergeExternal3DAngles(
                        into: samples,
                        from: motionBERTResult.samples,
                        toleranceSeconds: max(interval * 0.9, 0.1)
                    )
                    if merged.matchedFrameCount >= max(8, samples.count / 3) {
                        samples = merged.samples
                        used3DAngleFrameCount = merged.matchedFrameCount
                        modelUsed = .mmposeMotionBERT
                        modelRuntimeHints.append(contentsOf: motionBERTResult.warnings)
                        modelRuntimeHints.append(
                            L10n.choose(
                                simplifiedChinese: "MotionAGFormer-L 继续负责外部 3D 提升，但侧视 fitting 页面中的膝/髋/踝角会统一回视频平面的投影定义，确保曲柄点位与同一条腿的几何角度保持一致。",
                                english: "MotionAGFormer-L still provides the external 3D lift, but the side-view fitting knee/hip/ankle angles are normalized back to the video-plane projected definitions so crank checkpoints stay aligned with the same leg's geometry."
                            )
                        )
                        await Self.publishProgress(
                            progressReporter,
                            message: L10n.choose(
                                simplifiedChinese: "MotionAGFormer-L 3D 融合完成，匹配 \(merged.matchedFrameCount) 帧。",
                                english: "MotionAGFormer-L 3D merge completed with \(merged.matchedFrameCount) matched frames."
                            )
                        )
                    } else if preferredModel == .mmposeMotionBERT {
                        modelFallbackNote = L10n.choose(
                            simplifiedChinese: "MotionAGFormer-L 返回的可匹配角度帧太少，已回退到当前 2D/本地角度链路。",
                            english: "MotionAGFormer-L returned too few matched 3D-angle frames. Fell back to the current 2D/local angle pipeline."
                        )
                        await Self.publishProgress(
                            progressReporter,
                            message: modelFallbackNote ?? ""
                        )
                    }
                } catch {
                    if preferredModel == .mmposeMotionBERT {
                        modelFallbackNote = L10n.choose(
                            simplifiedChinese: "MotionAGFormer-L 当前不可用，已回退到本地后端。桌面发版会优先使用 app 内置运行时；开发环境未打包时才回退到本机 Python。",
                            english: "MotionAGFormer-L is currently unavailable. Fell back to the local backend. Desktop releases prefer the app-bundled runtime; development builds fall back to a local Python runtime only when it is not packaged."
                        )
                        await Self.publishProgress(
                            progressReporter,
                            message: modelFallbackNote ?? ""
                        )
                    }
                }
            } else if preferredModel == .mmposeMotionBERT {
                modelFallbackNote = L10n.choose(
                    simplifiedChinese: "当前平台不支持直接执行 MotionAGFormer-L Python 后端，已回退到 Apple Vision。",
                    english: "The current platform cannot run the MotionAGFormer-L Python backend directly. Fell back to Apple Vision."
                )
                await Self.publishProgress(
                    progressReporter,
                    message: modelFallbackNote ?? ""
                )
            }

            await Self.publishProgress(
                progressReporter,
                message: L10n.choose(
                    simplifiedChinese: "正在计算关节指标、踏频周期与 fitting 建议...",
                    english: "Computing joint metrics, cadence cycles, and fitting suggestions..."
                )
            )
            let dominantSide = Self.dominantSide(from: samples)
            let resolvedView = Self.resolveView(requested: requestedView, from: samples)
            if resolvedView == .side {
                samples = Self.normalizeSideViewPlanarAngles(
                    in: samples,
                    preferredSide: dominantSide
                )
            }

            var crankEstimate: (center: PoseJointPoint, radius: Double)?
            if resolvedView == .side, allowsExternalPythonBackends {
                do {
                    await Self.publishProgress(
                        progressReporter,
                        message: L10n.choose(
                            simplifiedChinese: "正在使用公路车 BB/Crank/Pedal 模型细化曲柄几何...",
                            english: "Refining crank geometry with the road-bike BB/Crank/Pedal model..."
                        )
                    )
                    let bikeKeypointResult = try await BikeKeypointEstimator.sampleVideo(
                        videoURL: videoURL,
                        maxSamples: targetFrameCount,
                        progressReporter: progressReporter
                    )
                    let merged = Self.mergeBikeKeypoints(
                        into: samples,
                        from: bikeKeypointResult.samples,
                        toleranceSeconds: max(interval * 0.9, 0.1)
                    )
                    if merged.matchedFrameCount >= max(8, samples.count / 4) {
                        samples = merged.samples
                        if let summaryEstimate = Self.crankEstimate(from: bikeKeypointResult.summary) {
                            crankEstimate = summaryEstimate
                        }
                        bikeKeypointModelText = bikeKeypointResult.modelText
                        modelRuntimeHints.append(contentsOf: bikeKeypointResult.warnings)
                        modelRuntimeHints.append(
                            L10n.choose(
                                simplifiedChinese: "\(bikeKeypointResult.modelText) 已细化 \(merged.matchedFrameCount) 帧 BB / 曲柄 / 脚踏位置。",
                                english: "\(bikeKeypointResult.modelText) refined the BB / crank / pedal geometry for \(merged.matchedFrameCount) frames."
                            )
                        )
                    } else {
                        bikeKeypointFallbackNote = L10n.choose(
                            simplifiedChinese: "公路车 BB/Crank/Pedal 模型返回的可匹配帧过少，当前仍按人体脚尖/踝部几何估计曲柄位置。",
                            english: "The road-bike BB/Crank/Pedal model returned too few matching frames, so crank geometry still falls back to the rider toe/ankle estimate."
                        )
                    }
                } catch {
                    bikeKeypointFallbackNote = L10n.choose(
                        simplifiedChinese: "本次未启用公路车 BB/Crank/Pedal 专用模型，曲柄位置仍按人体脚尖/踝部几何估计。",
                        english: "The dedicated road-bike BB/Crank/Pedal model was not used for this run, so crank geometry still relies on the rider toe/ankle estimate."
                    )
                }
            }

            if crankEstimate == nil, resolvedView == .side {
                crankEstimate = Self.estimateCrankCenter(samples: samples, side: dominantSide)
            }

            if let crankEstimate {
                samples = samples.map { sample in
                    let pedalPoint = Self.dominantCrankReferencePoint(for: sample, side: dominantSide)
                    return Self.updatingCrankPhase(
                        sample: sample,
                        phaseDegrees: Self.phaseAngleDegrees(center: crankEstimate.center, pedal: pedalPoint) ?? sample.crankPhaseDeg
                    )
                }
            }

            let kneeStats = Self.stats(for: samples.compactMap(\.kneeAngleDeg))
            let hipStats = Self.stats(for: samples.compactMap(\.hipAngleDeg))
            let ankleStats = Self.stats(for: samples.compactMap(\.ankleAngleDeg))
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
            await Self.publishProgress(
                progressReporter,
                message: L10n.choose(
                    simplifiedChinese: "识别完成，共生成 \(samples.count) 帧关节结果。",
                    english: "Recognition completed with \(samples.count) analyzed frames."
                )
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
                crankCenter: crankEstimate?.center,
                crankRadius: crankEstimate?.radius,
                used3DAngleFrameCount: used3DAngleFrameCount,
                kneeStats: kneeStats,
                hipStats: hipStats,
                ankleStats: ankleStats,
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
                fittingHints: fittingHints,
                bikeKeypointModelText: bikeKeypointModelText,
                bikeKeypointFallbackNote: bikeKeypointFallbackNote
            )
        }.value
    }

    static func poseModelAttemptOrder(
        preferredModel: VideoPoseEstimationModel,
        allowsExternalPythonBackends: Bool
    ) -> [VideoPoseEstimationModel] {
        switch preferredModel {
        case .appleVision:
            return [.appleVision]
        case .mediaPipeBlazePoseGHUM:
            return allowsExternalPythonBackends
                ? [.mediaPipeBlazePoseGHUM, .appleVision]
                : [.appleVision]
        case .mmposeMotionBERT:
            return allowsExternalPythonBackends
                ? [.mmposeMotionBERT, .mediaPipeBlazePoseGHUM, .appleVision]
                : [.appleVision]
        case .auto:
            return allowsExternalPythonBackends
                ? [.mmposeMotionBERT, .mediaPipeBlazePoseGHUM, .appleVision]
                : [.appleVision]
        }
    }

    static func mergeExternal3DAngles(
        into samples: [VideoJointAngleSample],
        from externalAngles: [External3DAngleSample],
        toleranceSeconds: Double
    ) -> (samples: [VideoJointAngleSample], matchedFrameCount: Int) {
        guard !samples.isEmpty, !externalAngles.isEmpty else {
            return (samples, 0)
        }

        let sortedExternal = externalAngles.sorted { $0.timeSeconds < $1.timeSeconds }
        var matchedFrameCount = 0
        let merged = samples.map { sample -> VideoJointAngleSample in
            guard let nearest = sortedExternal.min(by: {
                abs($0.timeSeconds - sample.timeSeconds) < abs($1.timeSeconds - sample.timeSeconds)
            }) else {
                return sample
            }
            guard abs(nearest.timeSeconds - sample.timeSeconds) <= toleranceSeconds else {
                return sample
            }

            let fusedKnee: Double?
            let fusedHip: Double?
            let fusedAnkle: Double?
            switch sample.side {
            case .left:
                fusedKnee = nearest.leftKneeAngleDeg ?? sample.kneeAngleDeg
                fusedHip = nearest.leftHipAngleDeg ?? sample.hipAngleDeg
                fusedAnkle = nearest.leftAnkleAngleDeg ?? sample.ankleAngleDeg
            case .right:
                fusedKnee = nearest.rightKneeAngleDeg ?? sample.kneeAngleDeg
                fusedHip = nearest.rightHipAngleDeg ?? sample.hipAngleDeg
                fusedAnkle = nearest.rightAnkleAngleDeg ?? sample.ankleAngleDeg
            case .unknown:
                if nearest.leftKneeAngleDeg != nil || nearest.leftHipAngleDeg != nil {
                    fusedKnee = nearest.leftKneeAngleDeg ?? sample.kneeAngleDeg
                    fusedHip = nearest.leftHipAngleDeg ?? sample.hipAngleDeg
                    fusedAnkle = nearest.leftAnkleAngleDeg ?? sample.ankleAngleDeg
                } else {
                    fusedKnee = nearest.rightKneeAngleDeg ?? sample.kneeAngleDeg
                    fusedHip = nearest.rightHipAngleDeg ?? sample.hipAngleDeg
                    fusedAnkle = nearest.rightAnkleAngleDeg ?? sample.ankleAngleDeg
                }
            }

            guard
                fusedKnee != sample.kneeAngleDeg ||
                fusedHip != sample.hipAngleDeg ||
                fusedAnkle != sample.ankleAngleDeg
            else {
                return sample
            }

            matchedFrameCount += 1
            return VideoJointAngleSample(
                id: sample.id,
                timeSeconds: sample.timeSeconds,
                side: sample.side,
                confidence: max(sample.confidence, nearest.confidence),
                kneeAngleDeg: fusedKnee,
                hipAngleDeg: fusedHip,
                ankleAngleDeg: fusedAnkle,
                shoulderAngleDeg: sample.shoulderAngleDeg,
                elbowAngleDeg: sample.elbowAngleDeg,
                crankPhaseDeg: sample.crankPhaseDeg,
                leftShoulder: sample.leftShoulder,
                leftElbow: sample.leftElbow,
                leftWrist: sample.leftWrist,
                leftHip: sample.leftHip,
                leftKnee: sample.leftKnee,
                leftAnkle: sample.leftAnkle,
                rightShoulder: sample.rightShoulder,
                rightElbow: sample.rightElbow,
                rightWrist: sample.rightWrist,
                rightHip: sample.rightHip,
                rightKnee: sample.rightKnee,
                rightAnkle: sample.rightAnkle,
                leftToe: sample.leftToe,
                rightToe: sample.rightToe,
                bikeBottomBracket: sample.bikeBottomBracket,
                bikeCrankEnd: sample.bikeCrankEnd,
                bikePedalCenter: sample.bikePedalCenter
            )
        }

        return (merged, matchedFrameCount)
    }

    static func mergeBikeKeypoints(
        into samples: [VideoJointAngleSample],
        from bikeSamples: [BikeKeypointSample],
        toleranceSeconds: Double
    ) -> (samples: [VideoJointAngleSample], matchedFrameCount: Int) {
        guard !samples.isEmpty, !bikeSamples.isEmpty else {
            return (samples, 0)
        }

        let sortedExternal = bikeSamples.sorted { $0.timeSeconds < $1.timeSeconds }
        var matchedFrameCount = 0
        let merged = samples.map { sample -> VideoJointAngleSample in
            guard let nearest = sortedExternal.min(by: {
                abs($0.timeSeconds - sample.timeSeconds) < abs($1.timeSeconds - sample.timeSeconds)
            }) else {
                return sample
            }
            guard abs(nearest.timeSeconds - sample.timeSeconds) <= toleranceSeconds else {
                return sample
            }

            let mergedBottomBracket = nearest.bbCenter ?? sample.bikeBottomBracket
            let mergedCrankEnd = nearest.crankEnd ?? sample.bikeCrankEnd
            let mergedPedalCenter = nearest.pedalCenter ?? sample.bikePedalCenter
            guard
                mergedBottomBracket != nil ||
                mergedCrankEnd != nil ||
                mergedPedalCenter != nil
            else {
                return sample
            }

            matchedFrameCount += 1
            return VideoJointAngleSample(
                id: sample.id,
                timeSeconds: sample.timeSeconds,
                side: sample.side,
                confidence: max(sample.confidence, nearest.confidence),
                kneeAngleDeg: sample.kneeAngleDeg,
                hipAngleDeg: sample.hipAngleDeg,
                ankleAngleDeg: sample.ankleAngleDeg,
                shoulderAngleDeg: sample.shoulderAngleDeg,
                elbowAngleDeg: sample.elbowAngleDeg,
                crankPhaseDeg: sample.crankPhaseDeg,
                leftShoulder: sample.leftShoulder,
                leftElbow: sample.leftElbow,
                leftWrist: sample.leftWrist,
                leftHip: sample.leftHip,
                leftKnee: sample.leftKnee,
                leftAnkle: sample.leftAnkle,
                rightShoulder: sample.rightShoulder,
                rightElbow: sample.rightElbow,
                rightWrist: sample.rightWrist,
                rightHip: sample.rightHip,
                rightKnee: sample.rightKnee,
                rightAnkle: sample.rightAnkle,
                leftToe: sample.leftToe,
                rightToe: sample.rightToe,
                bikeBottomBracket: mergedBottomBracket,
                bikeCrankEnd: mergedCrankEnd,
                bikePedalCenter: mergedPedalCenter
            )
        }

        return (merged, matchedFrameCount)
    }

    private struct SideViewPlanarAngleCandidate {
        let side: VideoPoseBodySide
        let confidence: Double
        let knee: Double?
        let hip: Double?
        let ankle: Double?
        let shoulder: Double?
        let elbow: Double?
    }

    static func normalizeSideViewPlanarAngles(
        in samples: [VideoJointAngleSample],
        preferredSide: VideoPoseBodySide
    ) -> [VideoJointAngleSample] {
        samples.map { sample in
            guard let normalized = normalizedSideViewPlanarAngles(for: sample, preferredSide: preferredSide) else {
                return sample
            }
            guard
                normalized.side != sample.side ||
                normalized.knee != sample.kneeAngleDeg ||
                normalized.hip != sample.hipAngleDeg ||
                normalized.ankle != sample.ankleAngleDeg ||
                normalized.shoulder != sample.shoulderAngleDeg ||
                normalized.elbow != sample.elbowAngleDeg ||
                normalized.confidence != sample.confidence
            else {
                return sample
            }
            return VideoJointAngleSample(
                id: sample.id,
                timeSeconds: sample.timeSeconds,
                side: normalized.side,
                confidence: normalized.confidence,
                kneeAngleDeg: normalized.knee,
                hipAngleDeg: normalized.hip,
                ankleAngleDeg: normalized.ankle,
                shoulderAngleDeg: normalized.shoulder,
                elbowAngleDeg: normalized.elbow,
                crankPhaseDeg: sample.crankPhaseDeg,
                leftShoulder: sample.leftShoulder,
                leftElbow: sample.leftElbow,
                leftWrist: sample.leftWrist,
                leftHip: sample.leftHip,
                leftKnee: sample.leftKnee,
                leftAnkle: sample.leftAnkle,
                rightShoulder: sample.rightShoulder,
                rightElbow: sample.rightElbow,
                rightWrist: sample.rightWrist,
                rightHip: sample.rightHip,
                rightKnee: sample.rightKnee,
                rightAnkle: sample.rightAnkle,
                leftToe: sample.leftToe,
                rightToe: sample.rightToe,
                bikeBottomBracket: sample.bikeBottomBracket,
                bikeCrankEnd: sample.bikeCrankEnd,
                bikePedalCenter: sample.bikePedalCenter
            )
        }
    }

    private static func normalizedSideViewPlanarAngles(
        for sample: VideoJointAngleSample,
        preferredSide: VideoPoseBodySide
    ) -> SideViewPlanarAngleCandidate? {
        let left = planarAngleCandidate(for: .left, in: sample)
        let right = planarAngleCandidate(for: .right, in: sample)

        switch preferredSide {
        case .left:
            return left ?? right
        case .right:
            return right ?? left
        case .unknown:
            if let left, let right {
                return left.confidence >= right.confidence ? left : right
            }
            return left ?? right
        }
    }

    private static func planarAngleCandidate(
        for side: VideoPoseBodySide,
        in sample: VideoJointAngleSample
    ) -> SideViewPlanarAngleCandidate? {
        guard side == .left || side == .right else { return nil }

        let shoulder = side == .left ? sample.leftShoulder : sample.rightShoulder
        let elbow = side == .left ? sample.leftElbow : sample.rightElbow
        let wrist = side == .left ? sample.leftWrist : sample.rightWrist
        let hip = side == .left ? sample.leftHip : sample.rightHip
        let knee = side == .left ? sample.leftKnee : sample.rightKnee
        let ankle = side == .left ? sample.leftAnkle : sample.rightAnkle
        let toe = (side == .left ? sample.leftToe : sample.rightToe) ?? ankle.map {
            approximateToePoint(knee: knee, ankle: $0)
        }

        let kneeAngle = angle(hip, knee, ankle)
        let hipAngle = angle(shoulder, hip, knee)
        let ankleAngle = angle(knee, ankle, toe)
        let shoulderAngle = angle(hip, shoulder, elbow)
        let elbowAngle = angle(shoulder, elbow, wrist)

        let confidenceValues = [shoulder, hip, knee, ankle, toe]
            .compactMap { $0?.confidence }
        guard !confidenceValues.isEmpty else { return nil }

        return SideViewPlanarAngleCandidate(
            side: side,
            confidence: confidenceValues.reduce(0, +) / Double(confidenceValues.count),
            knee: kneeAngle ?? (sample.side == side ? sample.kneeAngleDeg : nil),
            hip: hipAngle ?? (sample.side == side ? sample.hipAngleDeg : nil),
            ankle: ankleAngle ?? (sample.side == side ? sample.ankleAngleDeg : nil),
            shoulder: shoulderAngle ?? (sample.side == side ? sample.shoulderAngleDeg : nil),
            elbow: elbowAngle ?? (sample.side == side ? sample.elbowAngleDeg : nil)
        )
    }

    private static func angle(_ a: PoseJointPoint?, _ b: PoseJointPoint?, _ c: PoseJointPoint?) -> Double? {
        guard let a, let b, let c else { return nil }
        return angleDegrees(a: a.cgPoint, b: b.cgPoint, c: c.cgPoint)
    }

    private static var allowsExternalPythonPoseBackends: Bool {
#if os(iOS)
        false
#else
        true
#endif
    }

    private static func publishProgress(
        _ reporter: VideoJointAngleAnalysisProgressReporter?,
        message: String
    ) async {
        guard let reporter else { return }
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        await reporter.publish(VideoJointAngleAnalysisProgressUpdate(message: trimmed))
    }

    private static func formattedProgressNumber(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    private static func sampleVideoWithAppleVision(
        asset: AVURLAsset,
        durationSeconds: Double,
        interval: Double,
        targetFrameCount: Int,
        progressReporter: VideoJointAngleAnalysisProgressReporter?
    ) async throws -> (samples: [VideoJointAngleSample], used3DAngleFrameCount: Int) {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceAfter = .zero
        generator.requestedTimeToleranceBefore = .zero

        let pose2DRequest = VNDetectHumanBodyPoseRequest()
        var pose3DRequest: VNDetectHumanBodyPose3DRequest?
        if #available(macOS 14.0, iOS 17.0, tvOS 17.0, *) {
            pose3DRequest = VNDetectHumanBodyPose3DRequest()
        }

        var samples: [VideoJointAngleSample] = []
        samples.reserveCapacity(targetFrameCount)
        var used3DAngleFrameCount = 0
        let progressStep = max(1, targetFrameCount / 10)

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

            let completedCount = index + 1
            if completedCount == 1 || completedCount == targetFrameCount || completedCount % progressStep == 0 {
                await Self.publishProgress(
                    progressReporter,
                    message: L10n.choose(
                        simplifiedChinese: "Apple Vision 已处理 \(completedCount)/\(targetFrameCount) 帧...",
                        english: "Apple Vision processed \(completedCount)/\(targetFrameCount) frames..."
                    )
                )
            }
        }

        return (samples, used3DAngleFrameCount)
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
            pedal: override.side == .right
                ? (baseSample.rightToe ?? baseSample.rightAnkle)
                : (baseSample.leftToe ?? baseSample.leftAnkle)
        )

        let sample = VideoJointAngleSample(
            id: baseSample.id,
            timeSeconds: baseSample.timeSeconds,
            side: override.side,
            confidence: baseSample.confidence,
            kneeAngleDeg: override.knee,
            hipAngleDeg: override.hip,
            ankleAngleDeg: baseSample.ankleAngleDeg,
            shoulderAngleDeg: baseSample.shoulderAngleDeg,
            elbowAngleDeg: baseSample.elbowAngleDeg,
            crankPhaseDeg: phaseDeg,
            leftShoulder: baseSample.leftShoulder,
            leftElbow: baseSample.leftElbow,
            leftWrist: baseSample.leftWrist,
            leftHip: baseSample.leftHip,
            leftKnee: baseSample.leftKnee,
            leftAnkle: baseSample.leftAnkle,
            rightShoulder: baseSample.rightShoulder,
            rightElbow: baseSample.rightElbow,
            rightWrist: baseSample.rightWrist,
            rightHip: baseSample.rightHip,
            rightKnee: baseSample.rightKnee,
            rightAnkle: baseSample.rightAnkle,
            leftToe: baseSample.leftToe,
            rightToe: baseSample.rightToe,
            bikeBottomBracket: baseSample.bikeBottomBracket,
            bikeCrankEnd: baseSample.bikeCrankEnd,
            bikePedalCenter: baseSample.bikePedalCenter
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
        let leftShoulder = jointPoint(.leftShoulder, in: points)
        let leftElbow = jointPoint(.leftElbow, in: points)
        let leftWrist = jointPoint(.leftWrist, in: points)
        let rightHip = jointPoint(.rightHip, in: points)
        let rightKnee = jointPoint(.rightKnee, in: points)
        let rightAnkle = jointPoint(.rightAnkle, in: points)
        let rightShoulder = jointPoint(.rightShoulder, in: points)
        let rightElbow = jointPoint(.rightElbow, in: points)
        let rightWrist = jointPoint(.rightWrist, in: points)
        let leftToe = leftAnkle.map { approximateToePoint(knee: leftKnee, ankle: $0) }
        let rightToe = rightAnkle.map { approximateToePoint(knee: rightKnee, ankle: $0) }
        func angle(_ a: PoseJointPoint?, _ b: PoseJointPoint?, _ c: PoseJointPoint?) -> Double? {
            guard let a, let b, let c else { return nil }
            return angleDegrees(a: a.cgPoint, b: b.cgPoint, c: c.cgPoint)
        }
        let leftShoulderAngle = angle(leftHip, leftShoulder, leftElbow)
        let rightShoulderAngle = angle(rightHip, rightShoulder, rightElbow)
        let leftElbowAngle = angle(leftShoulder, leftElbow, leftWrist)
        let rightElbowAngle = angle(rightShoulder, rightElbow, rightWrist)

        let crankPhaseDeg = phaseAngleDegrees(
            hip: picked.side == .right ? rightHip : leftHip,
            pedal: picked.side == .right
                ? (rightToe ?? rightAnkle)
                : (leftToe ?? leftAnkle)
        )

        let shoulderAngle = picked.side == .right ? rightShoulderAngle : leftShoulderAngle
        let elbowAngle = picked.side == .right ? rightElbowAngle : leftElbowAngle

        return VideoJointAngleSample(
            id: sampleIndex,
            timeSeconds: timeSeconds,
            side: picked.side,
            confidence: picked.confidence,
            kneeAngleDeg: picked.knee,
            hipAngleDeg: picked.hip,
            // Vision lacks a reliable toe/foot landmark here, so avoid fabricating ankle angles.
            ankleAngleDeg: nil,
            shoulderAngleDeg: shoulderAngle,
            elbowAngleDeg: elbowAngle,
            crankPhaseDeg: crankPhaseDeg,
            leftShoulder: leftShoulder,
            leftElbow: leftElbow,
            leftWrist: leftWrist,
            leftHip: leftHip,
            leftKnee: leftKnee,
            leftAnkle: leftAnkle,
            rightShoulder: rightShoulder,
            rightElbow: rightElbow,
            rightWrist: rightWrist,
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
                hipAngleDeg: best.0.hipAngleDeg,
                ankleAngleDeg: best.0.ankleAngleDeg
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

        if modelUsed == .mmposeMotionBERT {
            hints.append(
                L10n.choose(
                    simplifiedChinese: "当前 3D 关节角来自 MotionAGFormer-L；若鞋尖或踝部被遮挡，BDC 与踏频相位仍会受 2D 关键点质量影响。",
                    english: "3D joint angles now come from MotionAGFormer-L; if toe or ankle visibility is poor, BDC and cadence phase still depend on 2D keypoint quality."
                )
            )
        } else if modelUsed == .appleVision {
            hints.append(
                L10n.choose(
                    simplifiedChinese: "若需更高精度的 3D 关节角，桌面版会优先使用随 app 打包的 MotionAGFormer-L 运行时；开发构建未打包时才回退到本机 Python 环境。",
                    english: "For higher-accuracy 3D joint angles, desktop builds prefer the MotionAGFormer-L runtime packaged inside the app; development builds fall back to a local Python runtime only when that bundle is unavailable."
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

    static func phaseAngleDegrees(hip: PoseJointPoint?, pedal: PoseJointPoint?) -> Double? {
        guard let hip, let pedal else { return nil }
        let dx = pedal.x - hip.x
        let dy = hip.y - pedal.y
        guard abs(dx) + abs(dy) > 0.000001 else { return nil }
        let raw = atan2(dx, dy) * 180.0 / Double.pi
        return normalizeDegrees(raw)
    }

    static func phaseAngleDegrees(center: PoseJointPoint?, pedal: PoseJointPoint?) -> Double? {
        guard let center, let pedal else { return nil }
        let dx = pedal.x - center.x
        let dy = center.y - pedal.y
        guard abs(dx) + abs(dy) > 0.000001 else { return nil }
        let raw = atan2(dx, dy) * 180.0 / Double.pi
        return normalizeDegrees(raw)
    }

    private static func dominantPedalPoint(for sample: VideoJointAngleSample, side: VideoPoseBodySide) -> PoseJointPoint? {
        if let bikePedalCenter = sample.bikePedalCenter {
            return bikePedalCenter
        }
        switch side {
        case .left:
            return sample.leftToe ?? sample.leftAnkle
        case .right:
            return sample.rightToe ?? sample.rightAnkle
        case .unknown:
            return sample.leftToe ?? sample.leftAnkle ?? sample.rightToe ?? sample.rightAnkle
        }
    }

    private static func dominantCrankReferencePoint(for sample: VideoJointAngleSample, side: VideoPoseBodySide) -> PoseJointPoint? {
        if let bikeCrankEnd = sample.bikeCrankEnd {
            return bikeCrankEnd
        }
        return dominantPedalPoint(for: sample, side: side)
    }

    private static func updatingCrankPhase(sample: VideoJointAngleSample, phaseDegrees: Double?) -> VideoJointAngleSample {
        VideoJointAngleSample(
            id: sample.id,
            timeSeconds: sample.timeSeconds,
            side: sample.side,
            confidence: sample.confidence,
            kneeAngleDeg: sample.kneeAngleDeg,
            hipAngleDeg: sample.hipAngleDeg,
            ankleAngleDeg: sample.ankleAngleDeg,
            shoulderAngleDeg: sample.shoulderAngleDeg,
            elbowAngleDeg: sample.elbowAngleDeg,
            crankPhaseDeg: phaseDegrees,
            leftShoulder: sample.leftShoulder,
            leftElbow: sample.leftElbow,
            leftWrist: sample.leftWrist,
            leftHip: sample.leftHip,
            leftKnee: sample.leftKnee,
            leftAnkle: sample.leftAnkle,
            rightShoulder: sample.rightShoulder,
            rightElbow: sample.rightElbow,
            rightWrist: sample.rightWrist,
            rightHip: sample.rightHip,
            rightKnee: sample.rightKnee,
            rightAnkle: sample.rightAnkle,
            leftToe: sample.leftToe,
            rightToe: sample.rightToe,
            bikeBottomBracket: sample.bikeBottomBracket,
            bikeCrankEnd: sample.bikeCrankEnd,
            bikePedalCenter: sample.bikePedalCenter
        )
    }

    private static func estimateCrankCenter(
        samples: [VideoJointAngleSample],
        side: VideoPoseBodySide
    ) -> (center: PoseJointPoint, radius: Double)? {
        let pedalPoints = samples.compactMap { dominantCrankReferencePoint(for: $0, side: side) }
            .filter { $0.x.isFinite && $0.y.isFinite }
        guard pedalPoints.count >= 6 else { return nil }

        let xs = pedalPoints.map(\.x)
        let ys = pedalPoints.map(\.y)
        guard
            (xs.max() ?? 0) - (xs.min() ?? 0) >= 0.02,
            (ys.max() ?? 0) - (ys.min() ?? 0) >= 0.02,
            let fit = solveCircle(points: pedalPoints)
        else {
            return nil
        }

        let centerX = Double(fit.center.x)
        let centerY = Double(fit.center.y)
        let radius = fit.radius
        guard
            centerX.isFinite,
            centerY.isFinite,
            radius.isFinite,
            radius >= 0.02,
            radius <= 0.25,
            centerX >= 0.15,
            centerX <= 0.85,
            centerY >= 0.25,
            centerY <= 0.90
        else {
            return nil
        }

        let rmsError = sqrt(
            pedalPoints
                .map { point -> Double in
                    let dx = point.x - centerX
                    let dy = point.y - centerY
                    let error = hypot(dx, dy) - radius
                    return error * error
                }
                .reduce(0, +) / Double(pedalPoints.count)
        )
        guard rmsError <= max(0.04, radius * 0.45) else { return nil }

        let confidence = median(pedalPoints.map(\.confidence)) ?? 0.7
        return (
            center: PoseJointPoint(x: centerX, y: centerY, confidence: confidence),
            radius: radius
        )
    }

    private static func crankEstimate(from summary: BikeKeypointSummary) -> (center: PoseJointPoint, radius: Double)? {
        guard let center = summary.bbCenter else { return nil }
        guard
            let radius = summary.radius,
            radius.isFinite,
            radius >= 0.02,
            radius <= 0.25,
            center.x.isFinite,
            center.y.isFinite,
            center.x >= 0.15,
            center.x <= 0.85,
            center.y >= 0.25,
            center.y <= 0.90
        else {
            return nil
        }
        return (center, radius)
    }

    private static func solveCircle(points: [PoseJointPoint]) -> (center: CGPoint, radius: Double)? {
        let count = Double(points.count)
        guard count >= 3 else { return nil }

        var sumX = 0.0
        var sumY = 0.0
        var sumXX = 0.0
        var sumYY = 0.0
        var sumXY = 0.0
        var sumZ = 0.0
        var sumXZ = 0.0
        var sumYZ = 0.0

        for point in points {
            let x = point.x
            let y = point.y
            let z = x * x + y * y
            sumX += x
            sumY += y
            sumXX += x * x
            sumYY += y * y
            sumXY += x * y
            sumZ += z
            sumXZ += x * z
            sumYZ += y * z
        }

        let matrix = (
            SIMD3<Double>(sumXX, sumXY, sumX),
            SIMD3<Double>(sumXY, sumYY, sumY),
            SIMD3<Double>(sumX, sumY, count)
        )
        let vector = SIMD3<Double>(-sumXZ, -sumYZ, -sumZ)
        guard let solution = solveLinear3x3(matrix: matrix, vector: vector) else { return nil }

        let a = solution.x
        let b = solution.y
        let c = solution.z
        let center = CGPoint(x: -a / 2.0, y: -b / 2.0)
        let radiusSquared = center.x * center.x + center.y * center.y - c
        guard radiusSquared.isFinite, radiusSquared > 0 else { return nil }

        return (center: center, radius: sqrt(radiusSquared))
    }

    private static func solveLinear3x3(
        matrix: (SIMD3<Double>, SIMD3<Double>, SIMD3<Double>),
        vector: SIMD3<Double>
    ) -> SIMD3<Double>? {
        let determinant = det3(matrix)
        guard determinant.isFinite, abs(determinant) > 1e-9 else { return nil }

        let dx = det3((vector, matrix.1, matrix.2))
        let dy = det3((matrix.0, vector, matrix.2))
        let dz = det3((matrix.0, matrix.1, vector))
        return SIMD3<Double>(dx / determinant, dy / determinant, dz / determinant)
    }

    private static func det3(_ matrix: (SIMD3<Double>, SIMD3<Double>, SIMD3<Double>)) -> Double {
        let a = matrix.0
        let b = matrix.1
        let c = matrix.2
        return
            a.x * (b.y * c.z - b.z * c.y) -
            a.y * (b.x * c.z - b.z * c.x) +
            a.z * (b.x * c.y - b.y * c.x)
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

    enum PythonPoseProcessRunner {
        struct Invocation {
            let executableURL: URL
            let prefixArguments: [String]
        }

        static func resolveInvocation(
            preferredEnvironmentVariables: [String],
            preferredCondaEnvironment: String? = nil,
            bundledRuntimeLocator: MotionBERTRuntimeLocator? = nil,
            bundle: Bundle = .main,
            environment: [String: String] = ProcessInfo.processInfo.environment,
            fileManager: FileManager = .default
        ) -> Invocation {
            let env = environment

            if let bundledRuntimeLocator,
               let bundledPython = bundledRuntimeLocator.resolveBundledPythonPath(bundle: bundle) {
                return Invocation(executableURL: URL(fileURLWithPath: bundledPython), prefixArguments: [])
            }

            for key in preferredEnvironmentVariables {
                if let path = env[key], fileManager.isExecutableFile(atPath: path) {
                    return Invocation(executableURL: URL(fileURLWithPath: path), prefixArguments: [])
                }
            }

            if let home = env["HOME"], let preferredCondaEnvironment {
                let candidatePaths = [
                    "\(home)/miniconda3/envs/\(preferredCondaEnvironment)/bin/python",
                    "\(home)/anaconda3/envs/\(preferredCondaEnvironment)/bin/python",
                    "\(home)/micromamba/envs/\(preferredCondaEnvironment)/bin/python"
                ]
                for path in candidatePaths where fileManager.isExecutableFile(atPath: path) {
                    return Invocation(executableURL: URL(fileURLWithPath: path), prefixArguments: [])
                }
            }

            if let condaPrefix = env["CONDA_PREFIX"] {
                let candidate = URL(fileURLWithPath: condaPrefix).appendingPathComponent("bin/python").path
                if fileManager.isExecutableFile(atPath: candidate) {
                    return Invocation(executableURL: URL(fileURLWithPath: candidate), prefixArguments: [])
                }
            }

            return Invocation(
                executableURL: URL(fileURLWithPath: "/usr/bin/env"),
                prefixArguments: ["python3"]
            )
        }
    }

    private enum MMPoseMotionBERTEstimator {
        struct Result {
            let samples: [External3DAngleSample]
            let warnings: [String]
        }

        private static let progressPrefix = "FRICU_PROGRESS|"

        private struct RawFrame: Decodable {
            let timeSeconds: Double
            let leftKneeAngleDeg: Double?
            let leftHipAngleDeg: Double?
            let leftAnkleAngleDeg: Double?
            let rightKneeAngleDeg: Double?
            let rightHipAngleDeg: Double?
            let rightAnkleAngleDeg: Double?
            let confidence: Double?

            private enum CodingKeys: String, CodingKey {
                case timeSeconds = "time_seconds"
                case leftKneeAngleDeg = "left_knee_angle_deg"
                case leftHipAngleDeg = "left_hip_angle_deg"
                case leftAnkleAngleDeg = "left_ankle_angle_deg"
                case rightKneeAngleDeg = "right_knee_angle_deg"
                case rightHipAngleDeg = "right_hip_angle_deg"
                case rightAnkleAngleDeg = "right_ankle_angle_deg"
                case confidence
            }
        }

        private struct RawOutput: Decodable {
            let backend: String?
            let samples: [RawFrame]
            let warnings: [String]?
        }

        private final class StderrProgressBuffer {
            private let lock = NSLock()
            private var buffer = ""
            private var nonProgressLines: [String] = []

            func ingest(data: Data, progressReporter: VideoJointAngleAnalysisProgressReporter?) {
                guard !data.isEmpty else { return }
                let text = String(data: data, encoding: .utf8) ?? ""
                lock.lock()
                defer { lock.unlock() }
                buffer.append(text)
                drainBufferedProgressLines(progressReporter: progressReporter)
            }

            func finalize(with data: Data, progressReporter: VideoJointAngleAnalysisProgressReporter?) -> String {
                lock.lock()
                defer { lock.unlock() }
                buffer.append(String(data: data, encoding: .utf8) ?? "")
                drainBufferedProgressLines(progressReporter: progressReporter)
                let remainder = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
                if !remainder.isEmpty {
                    handleProgressLine(remainder, progressReporter: progressReporter)
                }
                buffer.removeAll(keepingCapacity: false)
                return nonProgressLines
                    .joined(separator: "\n")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }

            private func drainBufferedProgressLines(progressReporter: VideoJointAngleAnalysisProgressReporter?) {
                while let newlineRange = buffer.range(of: "\n") {
                    let line = String(buffer[..<newlineRange.lowerBound])
                    buffer.removeSubrange(buffer.startIndex...newlineRange.lowerBound)
                    handleProgressLine(line, progressReporter: progressReporter)
                }
            }

            private func handleProgressLine(
                _ rawLine: String,
                progressReporter: VideoJointAngleAnalysisProgressReporter?
            ) {
                let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !line.isEmpty else { return }
                if let update = MMPoseMotionBERTEstimator.progressUpdate(from: line) {
                    Task {
                        await progressReporter?.publish(update)
                    }
                } else {
                    nonProgressLines.append(line)
                }
            }
        }

        static func sampleVideo(
            videoURL: URL,
            maxSamples: Int,
            progressReporter: VideoJointAngleAnalysisProgressReporter?
        ) async throws -> Result {
            guard let scriptPath = resolveScriptPath() else {
                throw NSError(
                    domain: "Fricu.VideoPose.MotionAGFormer",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "MotionAGFormer-L script not found"]
                )
            }

#if os(iOS)
            let _ = videoURL
            let _ = maxSamples
            let _ = scriptPath
            throw NSError(
                domain: "Fricu.VideoPose.MotionAGFormer",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "MotionAGFormer-L script execution is unavailable on iOS. Use Apple Vision instead."]
            )
#else
            let runtimeLocator = MotionBERTRuntimeLocator()
            let invocation = PythonPoseProcessRunner.resolveInvocation(
                preferredEnvironmentVariables: [
                    "FRICU_MMPPOSE_PYTHON",
                    "FRICU_VIDEO_POSE_PYTHON"
                ],
                preferredCondaEnvironment: "mmpose-mac",
                bundledRuntimeLocator: runtimeLocator
            )

            let process = Process()
            process.executableURL = invocation.executableURL
            process.arguments = invocation.prefixArguments + [
                scriptPath,
                "--video", videoURL.path,
                "--max-samples", String(maxSamples)
            ]

            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr
            var processEnvironment = ProcessInfo.processInfo.environment
            if let bundledCacheRoot = runtimeLocator.resolveBundledCacheRootURL() {
                processEnvironment["XDG_CACHE_HOME"] = bundledCacheRoot.path
                let bundledTorchCache = bundledCacheRoot.appendingPathComponent("torch", isDirectory: true)
                if FileManager.default.fileExists(atPath: bundledTorchCache.path) {
                    processEnvironment["TORCH_HOME"] = bundledTorchCache.path
                }
            }
            process.environment = processEnvironment

            let stderrProgressBuffer = StderrProgressBuffer()
            stderr.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                stderrProgressBuffer.ingest(
                    data: data,
                    progressReporter: progressReporter
                )
            }

            try process.run()
            process.waitUntilExit()

            stderr.fileHandleForReading.readabilityHandler = nil

            let outData = stdout.fileHandleForReading.readDataToEndOfFile()
            let errData = stderr.fileHandleForReading.readDataToEndOfFile()
            let errorText = stderrProgressBuffer.finalize(
                with: errData,
                progressReporter: progressReporter
            )

            guard process.terminationStatus == 0 else {
                throw NSError(
                    domain: "Fricu.VideoPose.MotionAGFormer",
                    code: Int(process.terminationStatus),
                    userInfo: [NSLocalizedDescriptionKey: errorText.isEmpty ? "unknown error" : errorText]
                )
            }

            let decoder = JSONDecoder()
            let payload = try decoder.decode(RawOutput.self, from: outData)
            let mapped = payload.samples.map {
                External3DAngleSample(
                    timeSeconds: $0.timeSeconds,
                    leftKneeAngleDeg: $0.leftKneeAngleDeg,
                    leftHipAngleDeg: $0.leftHipAngleDeg,
                    leftAnkleAngleDeg: $0.leftAnkleAngleDeg,
                    rightKneeAngleDeg: $0.rightKneeAngleDeg,
                    rightHipAngleDeg: $0.rightHipAngleDeg,
                    rightAnkleAngleDeg: $0.rightAnkleAngleDeg,
                    confidence: $0.confidence ?? 0.6
                )
            }
            return Result(samples: mapped, warnings: payload.warnings ?? [])
#endif
        }

        private static func progressUpdate(from line: String) -> VideoJointAngleAnalysisProgressUpdate? {
            guard line.hasPrefix(progressPrefix) else { return nil }
            let components = line.split(separator: "|").map(String.init)
            guard components.count >= 2 else { return nil }
            let stage = components[1]
            var fields: [String: String] = [:]
            for component in components.dropFirst(2) {
                let pair = component.split(separator: "=", maxSplits: 1).map(String.init)
                guard pair.count == 2 else { continue }
                fields[pair[0]] = pair[1]
            }

            switch stage {
            case "prepare":
                let targetFrames = fields["target_frames"] ?? "?"
                let device = fields["device"] ?? "cpu"
                return VideoJointAngleAnalysisProgressUpdate(
                    message: L10n.choose(
                        simplifiedChinese: "MotionAGFormer-L 已接管，计划在 \(device) 上推理 \(targetFrames) 帧。",
                        english: "MotionAGFormer-L took over and will infer \(targetFrames) frames on \(device)."
                    )
                )
            case "loading_model":
                let device = fields["device"] ?? "cpu"
                return VideoJointAngleAnalysisProgressUpdate(
                    message: L10n.choose(
                        simplifiedChinese: "正在加载 MotionAGFormer-L 3D 模型（\(device)）...",
                        english: "Loading the MotionAGFormer-L 3D model on \(device)..."
                    )
                )
            case "model_ready":
                return VideoJointAngleAnalysisProgressUpdate(
                    message: L10n.choose(
                        simplifiedChinese: "MotionAGFormer-L 模型已就绪，开始逐帧推理...",
                        english: "MotionAGFormer-L model is ready and frame inference is starting..."
                    )
                )
            case "frame":
                let completed = fields["completed"] ?? "?"
                let total = fields["total"] ?? "?"
                return VideoJointAngleAnalysisProgressUpdate(
                    message: L10n.choose(
                        simplifiedChinese: "MotionAGFormer-L 已处理 \(completed)/\(total) 帧...",
                        english: "MotionAGFormer-L processed \(completed)/\(total) frames..."
                    )
                )
            case "complete":
                let usable = fields["usable"] ?? "?"
                let total = fields["total"] ?? "?"
                let dropped = fields["dropped"] ?? "0"
                return VideoJointAngleAnalysisProgressUpdate(
                    message: L10n.choose(
                        simplifiedChinese: "MotionAGFormer-L 推理完成：输出 \(usable)/\(total) 帧，跳过 \(dropped) 帧。",
                        english: "MotionAGFormer-L finished with \(usable)/\(total) usable frames and \(dropped) skipped frames."
                    )
                )
            default:
                return nil
            }
        }

        private static func resolveScriptPath() -> String? {
            let fm = FileManager.default
            let cwd = URL(fileURLWithPath: fm.currentDirectoryPath, isDirectory: true)
            let bundle = Bundle.main
            let candidates: [String] = [
                bundle.resourceURL?.appendingPathComponent("PoseModels/video_pose_mmpose_motionbert.py").path,
                bundle.resourceURL?.appendingPathComponent("FricuApp_FricuApp.bundle/video_pose_mmpose_motionbert.py").path,
                bundle.resourceURL?.appendingPathComponent("Fricu_FricuApp.bundle/video_pose_mmpose_motionbert.py").path,
                bundle.bundleURL.appendingPathComponent("Contents/Resources/PoseModels/video_pose_mmpose_motionbert.py").path,
                bundle.bundleURL.appendingPathComponent("Contents/Resources/FricuApp_FricuApp.bundle/video_pose_mmpose_motionbert.py").path,
                bundle.bundleURL.appendingPathComponent("Contents/Resources/Fricu_FricuApp.bundle/video_pose_mmpose_motionbert.py").path,
                cwd.appendingPathComponent("Sources/FricuApp/Resources/PoseModels/video_pose_mmpose_motionbert.py").path,
                cwd.appendingPathComponent("scripts/video_pose_mmpose_motionbert.py").path
            ].compactMap { $0 }

            for path in candidates where fm.fileExists(atPath: path) {
                return path
            }
            return nil
        }
    }

    private enum BikeKeypointEstimator {
        struct Result {
            let samples: [BikeKeypointSample]
            let summary: BikeKeypointSummary
            let warnings: [String]
            let modelText: String
        }

        private static let progressPrefix = "FRICU_PROGRESS|"

        private struct RawPoint: Decodable {
            let x: Double
            let y: Double
            let confidence: Double?
        }

        private struct RawFrame: Decodable {
            let id: Int
            let timeSeconds: Double
            let keypoints: [String: RawPoint]
            let confidence: Double?

            private enum CodingKeys: String, CodingKey {
                case id
                case timeSeconds = "time_seconds"
                case keypoints
                case confidence
            }
        }

        private struct RawSummary: Decodable {
            let bbCenter: RawPoint?
            let radius: Double?
            let fitRMS: Double?

            private enum CodingKeys: String, CodingKey {
                case bbCenter = "bb_center"
                case radius
                case fitRMS = "fit_rms"
            }
        }

        private struct RawOutput: Decodable {
            let backend: String?
            let samples: [RawFrame]
            let summary: RawSummary?
            let warnings: [String]?
        }

        private final class StderrProgressBuffer {
            private let lock = NSLock()
            private var buffer = ""
            private var nonProgressLines: [String] = []

            func ingest(data: Data, progressReporter: VideoJointAngleAnalysisProgressReporter?) {
                guard !data.isEmpty else { return }
                let text = String(data: data, encoding: .utf8) ?? ""
                lock.lock()
                defer { lock.unlock() }
                buffer.append(text)
                drainBufferedProgressLines(progressReporter: progressReporter)
            }

            func finalize(with data: Data, progressReporter: VideoJointAngleAnalysisProgressReporter?) -> String {
                lock.lock()
                defer { lock.unlock() }
                buffer.append(String(data: data, encoding: .utf8) ?? "")
                drainBufferedProgressLines(progressReporter: progressReporter)
                let remainder = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
                if !remainder.isEmpty {
                    handleProgressLine(remainder, progressReporter: progressReporter)
                }
                buffer.removeAll(keepingCapacity: false)
                return nonProgressLines
                    .joined(separator: "\n")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }

            private func drainBufferedProgressLines(progressReporter: VideoJointAngleAnalysisProgressReporter?) {
                while let newlineRange = buffer.range(of: "\n") {
                    let line = String(buffer[..<newlineRange.lowerBound])
                    buffer.removeSubrange(buffer.startIndex...newlineRange.lowerBound)
                    handleProgressLine(line, progressReporter: progressReporter)
                }
            }

            private func handleProgressLine(
                _ rawLine: String,
                progressReporter: VideoJointAngleAnalysisProgressReporter?
            ) {
                let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !line.isEmpty else { return }
                if let update = BikeKeypointEstimator.progressUpdate(from: line) {
                    Task {
                        await progressReporter?.publish(update)
                    }
                } else {
                    nonProgressLines.append(line)
                }
            }
        }

        static func sampleVideo(
            videoURL: URL,
            maxSamples: Int,
            progressReporter: VideoJointAngleAnalysisProgressReporter?
        ) async throws -> Result {
            guard let scriptPath = resolveScriptPath() else {
                throw NSError(
                    domain: "Fricu.VideoPose.BikeKeypoint",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Bike keypoint script not found"]
                )
            }
            let checkpointLocator = BikeKeypointModelLocator()
            guard let checkpointPath = checkpointLocator.resolveCheckpointURL() else {
                throw NSError(
                    domain: "Fricu.VideoPose.BikeKeypoint",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "Bike keypoint checkpoint not found"]
                )
            }

#if os(iOS)
            let _ = videoURL
            let _ = maxSamples
            let _ = scriptPath
            let _ = checkpointPath
            throw NSError(
                domain: "Fricu.VideoPose.BikeKeypoint",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Bike keypoint script execution is unavailable on iOS."]
            )
#else
            let runtimeLocator = MotionBERTRuntimeLocator()
            let invocation = PythonPoseProcessRunner.resolveInvocation(
                preferredEnvironmentVariables: [
                    "FRICU_BIKE_KEYPOINT_PYTHON",
                    "FRICU_MMPPOSE_PYTHON",
                    "FRICU_VIDEO_POSE_PYTHON"
                ],
                preferredCondaEnvironment: "mmpose-mac",
                bundledRuntimeLocator: runtimeLocator
            )

            let process = Process()
            process.executableURL = invocation.executableURL
            process.arguments = invocation.prefixArguments + [
                scriptPath,
                "--video", videoURL.path,
                "--checkpoint", checkpointPath.path,
                "--max-samples", String(maxSamples)
            ]

            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr

            var processEnvironment = ProcessInfo.processInfo.environment
            processEnvironment["PYTHONUNBUFFERED"] = "1"
            if let bundledCacheRoot = runtimeLocator.resolveBundledCacheRootURL() {
                processEnvironment["XDG_CACHE_HOME"] = bundledCacheRoot.path
                let bundledTorchCache = bundledCacheRoot.appendingPathComponent("torch", isDirectory: true)
                if FileManager.default.fileExists(atPath: bundledTorchCache.path) {
                    processEnvironment["TORCH_HOME"] = bundledTorchCache.path
                }
            }
            process.environment = processEnvironment

            let stderrProgressBuffer = StderrProgressBuffer()
            stderr.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                stderrProgressBuffer.ingest(data: data, progressReporter: progressReporter)
            }

            try process.run()
            process.waitUntilExit()

            stderr.fileHandleForReading.readabilityHandler = nil

            let outData = stdout.fileHandleForReading.readDataToEndOfFile()
            let errData = stderr.fileHandleForReading.readDataToEndOfFile()
            let errorText = stderrProgressBuffer.finalize(with: errData, progressReporter: progressReporter)

            guard process.terminationStatus == 0 else {
                throw NSError(
                    domain: "Fricu.VideoPose.BikeKeypoint",
                    code: Int(process.terminationStatus),
                    userInfo: [NSLocalizedDescriptionKey: errorText.isEmpty ? "unknown error" : errorText]
                )
            }

            let decoder = JSONDecoder()
            let payload = try decoder.decode(RawOutput.self, from: outData)
            let mappedSamples = payload.samples.map { frame in
                BikeKeypointSample(
                    id: frame.id,
                    timeSeconds: frame.timeSeconds,
                    confidence: frame.confidence ?? 0.6,
                    bbCenter: point(named: "bb_center", in: frame.keypoints),
                    crankEnd: point(named: "crank_end", in: frame.keypoints),
                    pedalCenter: point(named: "pedal_center", in: frame.keypoints)
                )
            }
            let mappedSummary = BikeKeypointSummary(
                bbCenter: payload.summary?.bbCenter.map {
                    PoseJointPoint(
                        x: $0.x,
                        y: $0.y,
                        confidence: $0.confidence ?? 0.6
                    )
                },
                radius: payload.summary?.radius,
                fitRMS: payload.summary?.fitRMS
            )
            return Result(
                samples: mappedSamples,
                summary: mappedSummary,
                warnings: payload.warnings ?? [],
                modelText: L10n.choose(
                    simplifiedChinese: "公路车 BB/Crank/Pedal",
                    english: "Road-bike BB/Crank/Pedal"
                )
            )
#endif
        }

        private static func point(named key: String, in joints: [String: RawPoint]) -> PoseJointPoint? {
            guard let raw = joints[key] else { return nil }
            return PoseJointPoint(
                x: raw.x,
                y: raw.y,
                confidence: raw.confidence ?? 0.0
            )
        }

        private static func progressUpdate(from line: String) -> VideoJointAngleAnalysisProgressUpdate? {
            guard line.hasPrefix(progressPrefix) else { return nil }
            let components = line.split(separator: "|").map(String.init)
            guard components.count >= 2 else { return nil }
            let stage = components[1]
            var fields: [String: String] = [:]
            for component in components.dropFirst(2) {
                let pair = component.split(separator: "=", maxSplits: 1).map(String.init)
                guard pair.count == 2 else { continue }
                fields[pair[0]] = pair[1]
            }

            switch stage {
            case "prepare":
                let targetFrames = fields["target_frames"] ?? "?"
                let device = fields["device"] ?? "cpu"
                return VideoJointAngleAnalysisProgressUpdate(
                    message: L10n.choose(
                        simplifiedChinese: "公路车关键点模型已接管，计划在 \(device) 上细化 \(targetFrames) 帧 BB / 曲柄 / 脚踏位置。",
                        english: "The road-bike keypoint model took over and will refine the BB / crank / pedal geometry for \(targetFrames) frames on \(device)."
                    )
                )
            case "loading_model":
                let device = fields["device"] ?? "cpu"
                return VideoJointAngleAnalysisProgressUpdate(
                    message: L10n.choose(
                        simplifiedChinese: "正在加载公路车 BB/Crank/Pedal 模型（\(device)）...",
                        english: "Loading the road-bike BB/Crank/Pedal model on \(device)..."
                    )
                )
            case "model_ready":
                return VideoJointAngleAnalysisProgressUpdate(
                    message: L10n.choose(
                        simplifiedChinese: "公路车关键点模型已就绪，开始逐帧细化...",
                        english: "The road-bike keypoint model is ready and frame refinement is starting..."
                    )
                )
            case "frame":
                let completed = fields["completed"] ?? "?"
                let total = fields["total"] ?? "?"
                return VideoJointAngleAnalysisProgressUpdate(
                    message: L10n.choose(
                        simplifiedChinese: "公路车关键点模型已处理 \(completed)/\(total) 帧...",
                        english: "The road-bike keypoint model processed \(completed)/\(total) frames..."
                    )
                )
            case "complete":
                let usable = fields["usable"] ?? "?"
                let total = fields["total"] ?? "?"
                let dropped = fields["dropped"] ?? "0"
                return VideoJointAngleAnalysisProgressUpdate(
                    message: L10n.choose(
                        simplifiedChinese: "公路车关键点模型完成：输出 \(usable)/\(total) 帧，跳过 \(dropped) 帧。",
                        english: "The road-bike keypoint model finished with \(usable)/\(total) usable frames and \(dropped) skipped frames."
                    )
                )
            default:
                return nil
            }
        }

        private static func resolveScriptPath() -> String? {
            let fm = FileManager.default
            let cwd = URL(fileURLWithPath: fm.currentDirectoryPath, isDirectory: true)
            let bundle = Bundle.main
            let candidates: [String] = [
                bundle.resourceURL?.appendingPathComponent("PoseModels/video_bike_keypoints.py").path,
                bundle.resourceURL?.appendingPathComponent("FricuApp_FricuApp.bundle/video_bike_keypoints.py").path,
                bundle.resourceURL?.appendingPathComponent("Fricu_FricuApp.bundle/video_bike_keypoints.py").path,
                bundle.bundleURL.appendingPathComponent("Contents/Resources/PoseModels/video_bike_keypoints.py").path,
                bundle.bundleURL.appendingPathComponent("Contents/Resources/FricuApp_FricuApp.bundle/video_bike_keypoints.py").path,
                bundle.bundleURL.appendingPathComponent("Contents/Resources/Fricu_FricuApp.bundle/video_bike_keypoints.py").path,
                cwd.appendingPathComponent("Sources/FricuApp/Resources/PoseModels/video_bike_keypoints.py").path
            ].compactMap { $0 }

            for path in candidates where fm.fileExists(atPath: path) {
                return path
            }
            return nil
        }
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
            let leftAnkleAngleDeg: Double?
            let rightKneeAngleDeg: Double?
            let rightHipAngleDeg: Double?
            let rightAnkleAngleDeg: Double?

            private enum CodingKeys: String, CodingKey {
                case id
                case timeSeconds = "time_seconds"
                case joints
                case leftKneeAngleDeg = "left_knee_angle_deg"
                case leftHipAngleDeg = "left_hip_angle_deg"
                case leftAnkleAngleDeg = "left_ankle_angle_deg"
                case rightKneeAngleDeg = "right_knee_angle_deg"
                case rightHipAngleDeg = "right_hip_angle_deg"
                case rightAnkleAngleDeg = "right_ankle_angle_deg"
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

#if os(iOS)
            let _ = videoURL
            let _ = maxSamples
            let _ = scriptPath
            throw NSError(
                domain: "Fricu.VideoPose.MediaPipe",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "MediaPipe script execution is unavailable on iOS. Use Apple Vision instead."]
            )
#else
            let invocation = PythonPoseProcessRunner.resolveInvocation(
                preferredEnvironmentVariables: [
                    "FRICU_MEDIAPIPE_PYTHON",
                    "FRICU_VIDEO_POSE_PYTHON"
                ],
                preferredCondaEnvironment: "mmpose-mac",
                bundledRuntimeLocator: MotionBERTRuntimeLocator()
            )
            let process = Process()
            process.executableURL = invocation.executableURL
            process.arguments = invocation.prefixArguments + [
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
#endif
        }

        private static func mapFrameToSample(_ frame: RawFrame) -> VideoJointAngleSample? {
            let leftShoulder = point("left_shoulder", in: frame.joints)
            let leftElbow = point("left_elbow", in: frame.joints)
            let leftWrist = point("left_wrist", in: frame.joints)
            let leftHip = point("left_hip", in: frame.joints)
            let leftKnee = point("left_knee", in: frame.joints)
            let leftAnkle = point("left_ankle", in: frame.joints)
            let leftToe = point("left_foot_index", in: frame.joints) ?? point("left_toe", in: frame.joints)

            let rightShoulder = point("right_shoulder", in: frame.joints)
            let rightElbow = point("right_elbow", in: frame.joints)
            let rightWrist = point("right_wrist", in: frame.joints)
            let rightHip = point("right_hip", in: frame.joints)
            let rightKnee = point("right_knee", in: frame.joints)
            let rightAnkle = point("right_ankle", in: frame.joints)
            let rightToe = point("right_foot_index", in: frame.joints) ?? point("right_toe", in: frame.joints)

            let resolvedLeftToe = leftToe ?? leftAnkle.map { VideoJointAngleAnalyzer.approximateToePoint(knee: leftKnee, ankle: $0) }
            let resolvedRightToe = rightToe ?? rightAnkle.map { VideoJointAngleAnalyzer.approximateToePoint(knee: rightKnee, ankle: $0) }

            let leftKneeAngle = frame.leftKneeAngleDeg ?? angle(leftHip, leftKnee, leftAnkle)
            let leftHipAngle = frame.leftHipAngleDeg ?? angle(leftShoulder, leftHip, leftKnee)
            let leftAnkleAngle = frame.leftAnkleAngleDeg ?? angle(leftKnee, leftAnkle, resolvedLeftToe)
            let leftShoulderAngle = angle(leftHip, leftShoulder, leftElbow)
            let leftElbowAngle = angle(leftShoulder, leftElbow, leftWrist)
            let rightKneeAngle = frame.rightKneeAngleDeg ?? angle(rightHip, rightKnee, rightAnkle)
            let rightHipAngle = frame.rightHipAngleDeg ?? angle(rightShoulder, rightHip, rightKnee)
            let rightAnkleAngle = frame.rightAnkleAngleDeg ?? angle(rightKnee, rightAnkle, resolvedRightToe)
            let rightShoulderAngle = angle(rightHip, rightShoulder, rightElbow)
            let rightElbowAngle = angle(rightShoulder, rightElbow, rightWrist)

            let leftConfidence = averageConfidence([leftShoulder, leftHip, leftKnee, leftAnkle])
            let rightConfidence = averageConfidence([rightShoulder, rightHip, rightKnee, rightAnkle])

            let side: VideoPoseBodySide
            let confidence: Double
            let kneeAngle: Double?
            let hipAngle: Double?
            let ankleAngle: Double?
            let shoulderAngle: Double?
            let elbowAngle: Double?
            if leftConfidence >= rightConfidence {
                side = .left
                confidence = leftConfidence
                kneeAngle = leftKneeAngle
                hipAngle = leftHipAngle
                ankleAngle = leftAnkleAngle
                shoulderAngle = leftShoulderAngle
                elbowAngle = leftElbowAngle
            } else {
                side = .right
                confidence = rightConfidence
                kneeAngle = rightKneeAngle
                hipAngle = rightHipAngle
                ankleAngle = rightAnkleAngle
                shoulderAngle = rightShoulderAngle
                elbowAngle = rightElbowAngle
            }

            guard kneeAngle != nil || hipAngle != nil || ankleAngle != nil || shoulderAngle != nil || elbowAngle != nil else { return nil }
            let phase = VideoJointAngleAnalyzer.phaseAngleDegrees(
                hip: side == .right ? rightHip : leftHip,
                pedal: side == .right
                    ? (resolvedRightToe ?? rightAnkle)
                    : (resolvedLeftToe ?? leftAnkle)
            )

            return VideoJointAngleSample(
                id: frame.id,
                timeSeconds: frame.timeSeconds,
                side: side,
                confidence: confidence,
                kneeAngleDeg: kneeAngle,
                hipAngleDeg: hipAngle,
                ankleAngleDeg: ankleAngle,
                shoulderAngleDeg: shoulderAngle,
                elbowAngleDeg: elbowAngle,
                crankPhaseDeg: phase,
                leftShoulder: leftShoulder,
                leftElbow: leftElbow,
                leftWrist: leftWrist,
                leftHip: leftHip,
                leftKnee: leftKnee,
                leftAnkle: leftAnkle,
                rightShoulder: rightShoulder,
                rightElbow: rightElbow,
                rightWrist: rightWrist,
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
