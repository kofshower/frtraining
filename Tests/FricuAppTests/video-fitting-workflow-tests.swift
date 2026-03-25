import XCTest
@testable import FricuApp

final class VideoFittingWorkflowTests: XCTestCase {
    func testWorkflowStatesPendingWhenNoAssignedViews() {
        let snapshot = VideoFittingWorkflowSnapshot(
            assignedViewCount: 0,
            requiredViewCount: 3,
            isComplianceRunning: false,
            complianceChecked: false,
            compliancePassed: false,
            isAnalyzing: false,
            hasRecognitionResults: false
        )

        let states = VideoFittingWorkflowResolver.resolve(from: snapshot)

        XCTAssertEqual(states.viewAssignment, .pending)
        XCTAssertEqual(states.compliance, .pending)
        XCTAssertEqual(states.skeletonRecognition, .pending)
        XCTAssertEqual(states.report, .pending)
        XCTAssertFalse(states.canRunPostCompliance)
    }

    func testWorkflowStatesReadyBeforeComplianceCheck() {
        let snapshot = VideoFittingWorkflowSnapshot(
            assignedViewCount: 1,
            requiredViewCount: 3,
            isComplianceRunning: false,
            complianceChecked: false,
            compliancePassed: false,
            isAnalyzing: false,
            hasRecognitionResults: false
        )

        let states = VideoFittingWorkflowResolver.resolve(from: snapshot)

        XCTAssertEqual(states.viewAssignment, .ready)
        XCTAssertEqual(states.compliance, .ready)
        XCTAssertEqual(states.skeletonRecognition, .blocked)
        XCTAssertEqual(states.report, .blocked)
        XCTAssertFalse(states.canRunPostCompliance)
    }

    func testWorkflowComplianceRunningOverridesComplianceState() {
        let snapshot = VideoFittingWorkflowSnapshot(
            assignedViewCount: 2,
            requiredViewCount: 3,
            isComplianceRunning: true,
            complianceChecked: false,
            compliancePassed: false,
            isAnalyzing: false,
            hasRecognitionResults: false
        )

        let states = VideoFittingWorkflowResolver.resolve(from: snapshot)

        XCTAssertEqual(states.compliance, .running)
        XCTAssertEqual(states.skeletonRecognition, .blocked)
        XCTAssertEqual(states.report, .blocked)
    }

    func testWorkflowComplianceFailureBlocksDownstream() {
        let snapshot = VideoFittingWorkflowSnapshot(
            assignedViewCount: 3,
            requiredViewCount: 3,
            isComplianceRunning: false,
            complianceChecked: true,
            compliancePassed: false,
            isAnalyzing: false,
            hasRecognitionResults: true
        )

        let states = VideoFittingWorkflowResolver.resolve(from: snapshot)

        XCTAssertEqual(states.viewAssignment, .done)
        XCTAssertEqual(states.compliance, .blocked)
        XCTAssertEqual(states.skeletonRecognition, .blocked)
        XCTAssertEqual(states.report, .blocked)
        XCTAssertFalse(states.canRunPostCompliance)
    }

    func testWorkflowPartialViewsCanProceedAfterCompliancePass() {
        let snapshot = VideoFittingWorkflowSnapshot(
            assignedViewCount: 2,
            requiredViewCount: 3,
            isComplianceRunning: false,
            complianceChecked: true,
            compliancePassed: true,
            isAnalyzing: false,
            hasRecognitionResults: false
        )

        let states = VideoFittingWorkflowResolver.resolve(from: snapshot)

        XCTAssertEqual(states.viewAssignment, .ready)
        XCTAssertEqual(states.compliance, .ready)
        XCTAssertEqual(states.skeletonRecognition, .ready)
        XCTAssertEqual(states.report, .pending)
        XCTAssertTrue(states.canRunPostCompliance)
    }

    func testWorkflowDoneAndReadyWithAllViewsAndResults() {
        let snapshot = VideoFittingWorkflowSnapshot(
            assignedViewCount: 3,
            requiredViewCount: 3,
            isComplianceRunning: false,
            complianceChecked: true,
            compliancePassed: true,
            isAnalyzing: false,
            hasRecognitionResults: true
        )

        let states = VideoFittingWorkflowResolver.resolve(from: snapshot)

        XCTAssertEqual(states.viewAssignment, .done)
        XCTAssertEqual(states.compliance, .done)
        XCTAssertEqual(states.skeletonRecognition, .done)
        XCTAssertEqual(states.report, .ready)
        XCTAssertTrue(states.canRunPostCompliance)
    }

    func testWorkflowAnalyzingOverridesSkeletonAndReportState() {
        let snapshot = VideoFittingWorkflowSnapshot(
            assignedViewCount: 3,
            requiredViewCount: 3,
            isComplianceRunning: false,
            complianceChecked: true,
            compliancePassed: true,
            isAnalyzing: true,
            hasRecognitionResults: true
        )

        let states = VideoFittingWorkflowResolver.resolve(from: snapshot)

        XCTAssertEqual(states.skeletonRecognition, .running)
        XCTAssertEqual(states.report, .running)
    }

    func testCapabilityMatrixAllViewsAvailable() {
        let matrix = VideoFittingCapabilityMatrix.build(assignedViews: [.front, .side, .rear])

        XCTAssertEqual(matrix.availableCount, 3)
        XCTAssertEqual(matrix.unavailableCount, 0)
        XCTAssertTrue(matrix.statuses.allSatisfy(\.isAvailable))
    }

    func testCapabilityMatrixMissingViewsExposeReasons() {
        let matrix = VideoFittingCapabilityMatrix.build(assignedViews: [.side])

        XCTAssertEqual(matrix.availableCount, 1)
        XCTAssertEqual(matrix.unavailableCount, 2)

        let byCapability = Dictionary(uniqueKeysWithValues: matrix.statuses.map { ($0.capability, $0) })
        XCTAssertEqual(byCapability[.sideKinematics]?.isAvailable, true)
        XCTAssertEqual(byCapability[.frontAlignment]?.isAvailable, false)
        XCTAssertEqual(byCapability[.rearStability]?.isAvailable, false)
        XCTAssertTrue((byCapability[.frontAlignment]?.message ?? "").contains("前视") || (byCapability[.frontAlignment]?.message ?? "").contains("front"))
    }

    func testCapabilityMetadataAndStatusIDAreReadable() {
        let capabilities = VideoFittingCapability.allCases
        XCTAssertEqual(capabilities.count, 3)

        for capability in capabilities {
            XCTAssertFalse(capability.id.isEmpty)
            XCTAssertFalse(capability.title.isEmpty)
            XCTAssertFalse(capability.missingReason.isEmpty)
        }

        let status = VideoFittingCapabilityStatus(
            capability: .frontAlignment,
            isAvailable: true,
            message: "ok"
        )
        XCTAssertEqual(status.id, VideoFittingCapability.frontAlignment.id)
    }

    func testSessionSummaryEmptyStateExplainsNextStep() {
        let snapshot = VideoFittingWorkflowSnapshot(
            assignedViewCount: 0,
            requiredViewCount: 3,
            isComplianceRunning: false,
            complianceChecked: false,
            compliancePassed: false,
            isAnalyzing: false,
            hasRecognitionResults: false
        )

        let states = VideoFittingWorkflowResolver.resolve(from: snapshot)
        let summary = VideoFittingSessionSummaryResolver.resolve(
            snapshot: snapshot,
            states: states,
            capabilityMatrix: VideoFittingCapabilityMatrix.build(assignedViews: [])
        )

        XCTAssertEqual(summary.tone, VideoFittingSessionSummaryTone.empty)
        XCTAssertTrue(summary.statusTitle.contains("空") || summary.statusTitle.contains("Empty"))
        XCTAssertTrue(summary.nextActionTitle.contains("机位") || summary.nextActionTitle.contains("assign"))
        XCTAssertEqual(summary.availableCapabilityTitles.count, 0)
    }

    func testSessionSummaryPartialStatePromptsCompliance() {
        let snapshot = VideoFittingWorkflowSnapshot(
            assignedViewCount: 2,
            requiredViewCount: 3,
            isComplianceRunning: false,
            complianceChecked: false,
            compliancePassed: false,
            isAnalyzing: false,
            hasRecognitionResults: false
        )

        let states = VideoFittingWorkflowResolver.resolve(from: snapshot)
        let summary = VideoFittingSessionSummaryResolver.resolve(
            snapshot: snapshot,
            states: states,
            capabilityMatrix: VideoFittingCapabilityMatrix.build(assignedViews: [.front, .side])
        )

        XCTAssertEqual(summary.tone, VideoFittingSessionSummaryTone.partial)
        XCTAssertTrue(summary.statusTitle.contains("部分") || summary.statusTitle.contains("Partially"))
        XCTAssertTrue(summary.nextActionTitle.contains("合规") || summary.nextActionTitle.contains("compliance"))
        XCTAssertEqual(summary.availableCapabilityTitles.count, 2)
    }

    func testSessionSummaryReadyStateShowsAnalyzableCapabilities() {
        let snapshot = VideoFittingWorkflowSnapshot(
            assignedViewCount: 3,
            requiredViewCount: 3,
            isComplianceRunning: false,
            complianceChecked: true,
            compliancePassed: true,
            isAnalyzing: false,
            hasRecognitionResults: true
        )

        let states = VideoFittingWorkflowResolver.resolve(from: snapshot)
        let summary = VideoFittingSessionSummaryResolver.resolve(
            snapshot: snapshot,
            states: states,
            capabilityMatrix: VideoFittingCapabilityMatrix.build(assignedViews: [.front, .side, .rear])
        )

        XCTAssertEqual(summary.tone, .ready)
        XCTAssertTrue(summary.statusTitle.contains("结论") || summary.statusTitle.contains("Results"))
        XCTAssertTrue(summary.nextActionTitle.contains("导出") || summary.nextActionTitle.contains("review"))
        XCTAssertEqual(summary.availableCapabilityTitles.count, 3)
        XCTAssertEqual(summary.completionRatio, 1.0, accuracy: 0.0001)
    }


    func testCameraViewCardSummaryEmptyStateExplainsMissingImpact() {
        let summary = VideoFittingCameraViewCardSummaryResolver.resolve(
            view: .front,
            sourceURL: nil,
            guidance: nil,
            hasAnalysisResult: false
        )

        XCTAssertEqual(summary.tone, .empty)
        XCTAssertFalse(summary.hasAssignedVideo)
        XCTAssertTrue(summary.statusTitle.contains("上传") || summary.statusTitle.contains("upload"))
        XCTAssertTrue(summary.missingImpact.contains("前视") || summary.missingImpact.contains("front"))
        XCTAssertEqual(summary.supportedConclusions.count, 3)
    }

    func testCameraViewCardSummaryAssignedStateWaitsForQualityCheck() {
        let summary = VideoFittingCameraViewCardSummaryResolver.resolve(
            view: .side,
            sourceURL: URL(fileURLWithPath: "/tmp/side.mp4"),
            guidance: nil,
            hasAnalysisResult: false
        )

        XCTAssertEqual(summary.tone, .partial)
        XCTAssertTrue(summary.hasAssignedVideo)
        XCTAssertEqual(summary.fileName, "side.mp4")
        XCTAssertTrue(summary.statusTitle.contains("检测") || summary.statusTitle.contains("Awaiting"))
        XCTAssertTrue(summary.blockingReasons.isEmpty)
        XCTAssertTrue(summary.qualityMetrics.isEmpty)
    }

    func testCameraViewCardSummaryReadyStateReflectsQualityAndAnalysis() {
        let guidance = VideoCaptureGuidance(
            fps: 59.9,
            luma: 0.48,
            sharpness: 0.09,
            occlusionRatio: 0.08,
            distortionRisk: 0.06,
            skeletonAlignability: 0.91,
            gateResult: VideoCaptureQualityGateResult(
                passed: true,
                score: 0.87,
                grade: .good,
                failures: []
            )
        )

        let readySummary = VideoFittingCameraViewCardSummaryResolver.resolve(
            view: .rear,
            sourceURL: URL(fileURLWithPath: "/tmp/rear.mp4"),
            guidance: guidance,
            hasAnalysisResult: false
        )
        XCTAssertEqual(readySummary.tone, VideoFittingCameraViewCardSummary.Tone.ready)
        XCTAssertTrue(readySummary.statusTitle.contains("分析") || readySummary.statusTitle.contains("Analyzable"))
        XCTAssertTrue(readySummary.qualityTitle.contains(VideoCaptureQualityGrade.good.label))
        XCTAssertTrue(readySummary.blockingReasons.isEmpty)
        XCTAssertEqual(readySummary.qualityMetrics.count, 7)
        XCTAssertEqual(readySummary.qualityMetrics.first(where: { $0.key == "luma" })?.value, "0.48")
        XCTAssertEqual(readySummary.qualityMetrics.first(where: { $0.key == "sharpness" })?.value, "0.090")
        XCTAssertEqual(readySummary.qualityMetrics.first(where: { $0.key == "distortion" })?.value, "6%")

        let analyzedSummary = VideoFittingCameraViewCardSummaryResolver.resolve(
            view: .rear,
            sourceURL: URL(fileURLWithPath: "/tmp/rear.mp4"),
            guidance: guidance,
            hasAnalysisResult: true
        )
        XCTAssertEqual(analyzedSummary.tone, VideoFittingCameraViewCardSummary.Tone.ready)
        XCTAssertTrue(analyzedSummary.statusTitle.contains("分析") || analyzedSummary.statusTitle.contains("Analyzed"))
    }

    func testCameraViewCardSummaryFailurePrioritizesBlockingReasonsAndShowsDetailedMetrics() {
        let guidance = VideoCaptureGuidance(
            fps: 239.9,
            luma: 0.21,
            sharpness: 0.028,
            occlusionRatio: 0.04,
            distortionRisk: 0.33,
            skeletonAlignability: 1.0,
            gateResult: VideoCaptureQualityGateResult(
                passed: false,
                score: 0.77,
                grade: .rejected,
                failures: [.lowLuma, .lowSharpness]
            )
        )

        let summary = VideoFittingCameraViewCardSummaryResolver.resolve(
            view: .side,
            sourceURL: URL(fileURLWithPath: "/tmp/side.mov"),
            guidance: guidance,
            hasAnalysisResult: false
        )

        XCTAssertEqual(summary.tone, .partial)
        XCTAssertEqual(summary.blockingReasons.count, 2)
        XCTAssertTrue(summary.blockingReasons[0].contains("光照不足") || summary.blockingReasons[0].contains("Lighting too low"))
        XCTAssertTrue(summary.blockingReasons[1].contains("画面模糊") || summary.blockingReasons[1].contains("Image too blurry"))
        XCTAssertTrue(summary.qualityDetail.contains("光照不足") || summary.qualityDetail.contains("Lighting too low"))
        XCTAssertEqual(summary.qualityMetrics.first(where: { $0.key == "luma" })?.value, "0.21")
        XCTAssertEqual(summary.qualityMetrics.first(where: { $0.key == "sharpness" })?.value, "0.028")
        XCTAssertEqual(summary.qualityMetrics.first(where: { $0.key == "distortion" })?.value, "33%")
    }

    func testComplianceViewSummaryExplainsFailureReasonsAndFixes() {
        let guidance = VideoCaptureGuidance(
            fps: 24,
            luma: 0.18,
            sharpness: 0.03,
            occlusionRatio: 0.46,
            distortionRisk: 0.42,
            skeletonAlignability: 0.31,
            gateResult: VideoCaptureQualityGateResult(
                passed: false,
                score: 0.21,
                grade: .rejected,
                failures: [.lowFrameRate, .lowLuma, .highOcclusion, .lowSkeletonAlignability]
            )
        )

        let summary = VideoFittingComplianceViewSummaryResolver.resolve(
            view: .front,
            sourceURL: URL(fileURLWithPath: "/tmp/front.mp4"),
            guidance: guidance
        )

        XCTAssertEqual(summary.tone, .failed)
        XCTAssertTrue(summary.statusTitle.contains("不合格") || summary.statusTitle.contains("qualified"))
        XCTAssertFalse(summary.reasonLines.isEmpty)
        XCTAssertFalse(summary.recommendationLines.isEmpty)
        XCTAssertTrue(summary.reasonLines.joined(separator: " ").contains("帧率") || summary.reasonLines.joined(separator: " ").contains("Frame"))
    }

    func testFailureRecoverySummaryGroupsCategoriesAndRetakeViews() {
        let frontGuidance = VideoCaptureGuidance(
            fps: 24,
            luma: 0.2,
            sharpness: 0.03,
            occlusionRatio: 0.18,
            distortionRisk: 0.12,
            skeletonAlignability: 0.48,
            gateResult: VideoCaptureQualityGateResult(
                passed: false,
                score: 0.28,
                grade: .rejected,
                failures: [.lowFrameRate, .lowSharpness, .lowSkeletonAlignability]
            )
        )
        let rearGuidance = VideoCaptureGuidance(
            fps: 59.9,
            luma: 0.41,
            sharpness: 0.09,
            occlusionRatio: 0.56,
            distortionRisk: 0.44,
            skeletonAlignability: 0.84,
            gateResult: VideoCaptureQualityGateResult(
                passed: false,
                score: 0.35,
                grade: .rejected,
                failures: [.highOcclusion, .highDistortion]
            )
        )

        let summary = VideoFittingFailureRecoverySummaryResolver.resolve(
            supportedViews: [.front, .side, .rear],
            sourceURL: { view in
                switch view {
                case .front, .rear:
                    return URL(fileURLWithPath: "/tmp/\(view.rawValue).mp4")
                case .side, .auto:
                    return nil
                }
            },
            guidanceByView: [
                .front: frontGuidance,
                .rear: rearGuidance
            ],
            complianceChecked: true,
            compliancePassed: false
        )

        XCTAssertNotNil(summary)
        XCTAssertEqual(summary?.recommendedRetakeViews, [.front, .rear])
        XCTAssertTrue(summary?.categories.contains(where: { $0.category == .stability }) == true)
        XCTAssertTrue(summary?.categories.contains(where: { $0.category == .visibility }) == true)
        XCTAssertFalse(summary?.fixSuggestions.isEmpty ?? true)
    }

    func testJointRecognitionQualitySummaryBlockedBeforeCompliancePass() {
        let guidance = VideoCaptureGuidance(
            fps: 29.9,
            luma: 0.24,
            sharpness: 0.03,
            occlusionRatio: 0.5,
            distortionRisk: 0.12,
            skeletonAlignability: 0.28,
            gateResult: VideoCaptureQualityGateResult(
                passed: false,
                score: 0.2,
                grade: .rejected,
                failures: [.lowFrameRate, .highOcclusion]
            )
        )

        let summary = VideoFittingJointRecognitionQualitySummaryResolver.resolve(
            selectedView: .side,
            selectedModel: .auto,
            sourceURL: URL(fileURLWithPath: "/tmp/side.mp4"),
            guidance: guidance,
            result: nil
        )

        XCTAssertEqual(summary.tone, .blocked)
        XCTAssertTrue(summary.statusTitle.contains("阻止") || summary.statusTitle.contains("blocked"))
        XCTAssertEqual(summary.confidenceText, "--")
        XCTAssertFalse(summary.computableIndicators.isEmpty)
    }

    func testJointRecognitionQualitySummaryReportsDerivedMetrics() {
        let summary = VideoFittingJointRecognitionQualitySummaryResolver.resolve(
            selectedView: .front,
            selectedModel: .auto,
            sourceURL: URL(fileURLWithPath: "/tmp/front.mp4"),
            guidance: nil,
            result: makeRecognitionResult()
        )

        XCTAssertEqual(summary.tone, .ready)
        XCTAssertTrue(summary.confidenceText.contains("高置信") || summary.confidenceText.contains("High-confidence"))
        XCTAssertEqual(summary.dropRateText, "25%")
        XCTAssertEqual(summary.problemFrameCountText, "2")
        XCTAssertTrue(summary.computableIndicators.contains { $0.contains("轨迹") || $0.contains("trajectory") })
        XCTAssertFalse(summary.angleVisuals.isEmpty)
    }

    func testJointRecognitionQualitySummaryBuildsAngleVisualsForSideView() throws {
        let summary = VideoFittingJointRecognitionQualitySummaryResolver.resolve(
            selectedView: .side,
            selectedModel: .auto,
            sourceURL: URL(fileURLWithPath: "/tmp/side.mp4"),
            guidance: nil,
            result: makeSideRecognitionResult()
        )

        XCTAssertEqual(summary.tone, .ready)
        XCTAssertEqual(summary.angleVisuals.map(\.kind), [.knee, .hip, .ankle, .bdcKnee])
        XCTAssertTrue(summary.angleVisuals.allSatisfy { $0.angleDegrees > 0 })
        XCTAssertEqual(summary.checkpointVisuals.map(\.checkpoint), [.point0, .point3, .point6, .point9])
        let overlayCheckpoints = summary.playbackOverlay?.checkpoints.map { $0.checkpoint }
        XCTAssertEqual(overlayCheckpoints, [.point0, .point3, .point6, .point9])
        XCTAssertEqual(summary.checkpointVisuals.map { Int($0.phaseDegrees.rounded()) }, [2, 90, 180, 270])
        let overlayPhaseDegrees = summary.playbackOverlay?.checkpoints.map { Int($0.phaseDegrees.rounded()) }
        XCTAssertEqual(overlayPhaseDegrees, [2, 90, 180, 270])
        XCTAssertEqual(summary.playbackOverlay?.samples.count, 4)
        XCTAssertNotNil(summary.previewVideoURL)
        XCTAssertNotNil(summary.playbackOverlay?.crankCenter)
        XCTAssertNotNil(summary.playbackOverlay?.crankRadius)
        XCTAssertNotNil(summary.angleVisuals.first?.frameTimeSeconds)
        XCTAssertNotNil(summary.angleVisuals.first?.crankCenter)
        XCTAssertNotNil(summary.angleVisuals.first?.crankRadius)
        XCTAssertNotNil(summary.angleVisuals.first?.firstPoint)
        XCTAssertNotNil(summary.angleVisuals.first?.jointPoint)
        XCTAssertNotNil(summary.angleVisuals.first?.thirdPoint)
        let hipVisual = try XCTUnwrap(summary.angleVisuals.first(where: { $0.kind == VideoFittingJointAngleVisualKind.hip }))
        XCTAssertNotNil(hipVisual.frameTimeSeconds)
        XCTAssertNotNil(hipVisual.crankCenter)
        XCTAssertNotNil(hipVisual.crankRadius)
        XCTAssertNotNil(hipVisual.firstPoint)
        XCTAssertNotNil(hipVisual.jointPoint)
        XCTAssertNotNil(hipVisual.thirdPoint)
        XCTAssertTrue(summary.checkpointVisuals.allSatisfy { $0.crankCenter != nil && $0.crankRadius != nil })
        XCTAssertTrue(summary.checkpointVisuals.allSatisfy { $0.firstPoint != nil && $0.jointPoint != nil && $0.thirdPoint != nil })
        let overlaySamples = summary.playbackOverlay?.samples ?? []
        XCTAssertTrue(overlaySamples.allSatisfy { !$0.renderableJointOverlays().isEmpty })
        XCTAssertTrue(overlaySamples.allSatisfy { sample in
            let kinds = Set(sample.renderableJointOverlays().map(\.kind))
            return kinds.contains(.knee) && kinds.contains(.hip) && kinds.contains(.shoulder) && kinds.contains(.elbow)
        })
        XCTAssertTrue(overlaySamples.allSatisfy { $0.bodyBounds != nil })
        XCTAssertTrue(overlaySamples.allSatisfy { $0.allowsOverlayRendering() })
    }

    func testCrankClockCheckpointTitlesExposeDeadCenterAndClockfaceLabels() {
        let topTitle = CrankClockCheckpoint.point0.positionTitle
        let bottomTitle = CrankClockCheckpoint.point6.positionTitle
        let topClockface = CrankClockCheckpoint.point0.clockfaceTitle
        let rightClockface = CrankClockCheckpoint.point3.clockfaceTitle

        XCTAssertTrue(topTitle.contains("上死点") || topTitle.localizedCaseInsensitiveContains("top dead center"))
        XCTAssertTrue(bottomTitle.contains("下死点") || bottomTitle.localizedCaseInsensitiveContains("bottom dead center"))
        XCTAssertTrue(topClockface.contains("12") || topClockface.localizedCaseInsensitiveContains("12"))
        XCTAssertTrue(rightClockface.contains("3") || rightClockface.localizedCaseInsensitiveContains("3"))
    }

    func testJointRecognitionQualitySummaryKeepsHipKeyframeWhenShoulderOverlayUnavailable() throws {
        let baseResult = makeSideRecognitionResult()
        let shoulderlessSamples = baseResult.samples.map { sample in
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
                crankPhaseDeg: sample.crankPhaseDeg,
                leftShoulder: nil,
                leftElbow: sample.leftElbow,
                leftWrist: sample.leftWrist,
                leftHip: sample.leftHip,
                leftKnee: sample.leftKnee,
                leftAnkle: sample.leftAnkle,
                rightShoulder: nil,
                rightElbow: sample.rightElbow,
                rightWrist: sample.rightWrist,
                rightHip: sample.rightHip,
                rightKnee: sample.rightKnee,
                rightAnkle: sample.rightAnkle,
                leftToe: sample.leftToe,
                rightToe: sample.rightToe
            )
        }
        let result = VideoJointAngleAnalysisResult(
            durationSeconds: baseResult.durationSeconds,
            targetFrameCount: baseResult.targetFrameCount,
            analyzedFrameCount: baseResult.analyzedFrameCount,
            requestedView: baseResult.requestedView,
            resolvedView: baseResult.resolvedView,
            modelUsed: baseResult.modelUsed,
            modelFallbackNote: baseResult.modelFallbackNote,
            dominantSide: baseResult.dominantSide,
            samples: shoulderlessSamples,
            crankCenter: baseResult.crankCenter,
            crankRadius: baseResult.crankRadius,
            used3DAngleFrameCount: baseResult.used3DAngleFrameCount,
            kneeStats: baseResult.kneeStats,
            hipStats: baseResult.hipStats,
            cadenceCycles: baseResult.cadenceCycles,
            cadenceSummary: baseResult.cadenceSummary,
            longDurationStability: baseResult.longDurationStability,
            sideCheckpoints: baseResult.sideCheckpoints,
            frontAlignment: baseResult.frontAlignment,
            frontTrajectory: baseResult.frontTrajectory,
            rearPelvic: baseResult.rearPelvic,
            rearStability: baseResult.rearStability,
            rearCoordination: baseResult.rearCoordination,
            frontAutoAssessment: baseResult.frontAutoAssessment,
            rearAutoAssessment: baseResult.rearAutoAssessment,
            adjustmentPlan: baseResult.adjustmentPlan,
            fittingHints: baseResult.fittingHints
        )

        let summary = VideoFittingJointRecognitionQualitySummaryResolver.resolve(
            selectedView: .side,
            selectedModel: .auto,
            sourceURL: URL(fileURLWithPath: "/tmp/side.mp4"),
            guidance: nil,
            result: result
        )

        let hipVisual = try XCTUnwrap(summary.angleVisuals.first(where: { $0.kind == VideoFittingJointAngleVisualKind.hip }))
        XCTAssertNotNil(hipVisual.frameTimeSeconds)
        XCTAssertNil(hipVisual.firstPoint)
        XCTAssertNil(hipVisual.jointPoint)
        XCTAssertNil(hipVisual.thirdPoint)
    }

    func testJointRecognitionQualitySummarySurfacesMotionAGFormerAndAnkleOutputs() throws {
        let result = makeSideRecognitionResult()
        let summary = VideoFittingJointRecognitionQualitySummaryResolver.resolve(
            selectedView: .side,
            selectedModel: .mmposeMotionBERT,
            sourceURL: URL(fileURLWithPath: "/tmp/side-motionagformer.mp4"),
            guidance: nil,
            result: VideoJointAngleAnalysisResult(
                durationSeconds: result.durationSeconds,
                targetFrameCount: result.targetFrameCount,
                analyzedFrameCount: result.analyzedFrameCount,
                requestedView: result.requestedView,
                resolvedView: result.resolvedView,
                modelUsed: .mmposeMotionBERT,
                modelFallbackNote: nil,
                dominantSide: result.dominantSide,
                samples: result.samples,
                crankCenter: result.crankCenter,
                crankRadius: result.crankRadius,
                used3DAngleFrameCount: 4,
                kneeStats: result.kneeStats,
                hipStats: result.hipStats,
                ankleStats: result.ankleStats,
                cadenceCycles: result.cadenceCycles,
                cadenceSummary: result.cadenceSummary,
                longDurationStability: result.longDurationStability,
                sideCheckpoints: result.sideCheckpoints,
                frontAlignment: result.frontAlignment,
                frontTrajectory: result.frontTrajectory,
                rearPelvic: result.rearPelvic,
                rearStability: result.rearStability,
                rearCoordination: result.rearCoordination,
                frontAutoAssessment: result.frontAutoAssessment,
                rearAutoAssessment: result.rearAutoAssessment,
                adjustmentPlan: result.adjustmentPlan,
                fittingHints: result.fittingHints,
                bikeKeypointModelText: "Road-bike BB/Crank/Pedal"
            )
        )

        XCTAssertTrue(summary.actualModelText.contains("MotionAGFormer"))
        XCTAssertTrue(summary.actualModelText.contains("BB/Crank/Pedal"))
        XCTAssertTrue(summary.computableIndicators.contains(where: { $0.contains("踝") || $0.localizedCaseInsensitiveContains("ankle") }))
        XCTAssertTrue(summary.angleVisuals.contains(where: { $0.kind == .ankle }))
        XCTAssertTrue((summary.playbackOverlay?.samples ?? []).contains(where: { $0.ankleAngleDegrees != nil }))
    }

    func testJointRecognitionQualitySummaryPlaybackUsesBikePedalPointWhenAvailable() throws {
        let baseResult = makeSideRecognitionResult()
        let bikePedal = PoseJointPoint(x: 0.61, y: 0.77, confidence: 0.95)
        let bikeSamples = baseResult.samples.enumerated().map { index, sample in
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
                bikeBottomBracket: index == 0 ? PoseJointPoint(x: 0.51, y: 0.76, confidence: 0.93) : nil,
                bikeCrankEnd: index == 0 ? PoseJointPoint(x: 0.57, y: 0.73, confidence: 0.94) : nil,
                bikePedalCenter: index == 0 ? bikePedal : nil
            )
        }

        let result = VideoJointAngleAnalysisResult(
            durationSeconds: baseResult.durationSeconds,
            targetFrameCount: baseResult.targetFrameCount,
            analyzedFrameCount: baseResult.analyzedFrameCount,
            requestedView: baseResult.requestedView,
            resolvedView: baseResult.resolvedView,
            modelUsed: baseResult.modelUsed,
            modelFallbackNote: baseResult.modelFallbackNote,
            dominantSide: baseResult.dominantSide,
            samples: bikeSamples,
            crankCenter: baseResult.crankCenter,
            crankRadius: baseResult.crankRadius,
            used3DAngleFrameCount: baseResult.used3DAngleFrameCount,
            kneeStats: baseResult.kneeStats,
            hipStats: baseResult.hipStats,
            ankleStats: baseResult.ankleStats,
            cadenceCycles: baseResult.cadenceCycles,
            cadenceSummary: baseResult.cadenceSummary,
            longDurationStability: baseResult.longDurationStability,
            sideCheckpoints: baseResult.sideCheckpoints,
            frontAlignment: baseResult.frontAlignment,
            frontTrajectory: baseResult.frontTrajectory,
            rearPelvic: baseResult.rearPelvic,
            rearStability: baseResult.rearStability,
            rearCoordination: baseResult.rearCoordination,
            frontAutoAssessment: baseResult.frontAutoAssessment,
            rearAutoAssessment: baseResult.rearAutoAssessment,
            adjustmentPlan: baseResult.adjustmentPlan,
            fittingHints: baseResult.fittingHints,
            bikeKeypointModelText: "Road-bike BB/Crank/Pedal"
        )

        let summary = VideoFittingJointRecognitionQualitySummaryResolver.resolve(
            selectedView: .side,
            selectedModel: .auto,
            sourceURL: URL(fileURLWithPath: "/tmp/side-bike.mp4"),
            guidance: nil,
            result: result
        )

        let pedalPoint = try XCTUnwrap(summary.playbackOverlay?.samples.first?.pedalPoint)
        XCTAssertEqual(pedalPoint.x, bikePedal.x, accuracy: 0.0001)
        XCTAssertEqual(pedalPoint.y, bikePedal.y, accuracy: 0.0001)
    }

    func testPendingMotionAGFormerSummaryExplainsTwoStagePipeline() throws {
        let summary = VideoFittingJointRecognitionQualitySummaryResolver.resolve(
            selectedView: .side,
            selectedModel: .mmposeMotionBERT,
            sourceURL: URL(fileURLWithPath: "/tmp/side-pending-motionagformer.mp4"),
            guidance: nil,
            result: nil
        )

        XCTAssertTrue(summary.requestedModelText.contains("MotionAGFormer"))
        XCTAssertTrue(summary.actualModelText == "等待识别" || summary.actualModelText == "Pending")
        let decisionText = try XCTUnwrap(summary.modelDecisionText)
        XCTAssertTrue(
            decisionText.contains("2D 骨架底稿") ||
            decisionText.localizedCaseInsensitiveContains("2D skeleton draft")
        )
    }

    func testPlaybackOverlaySampleBlocksRenderingWhenJointFallsOutsideBodyBounds() {
        let kneeOverlay = VideoFittingPlaybackJointOverlay(
            kind: .knee,
            angleDegrees: 112,
            firstPoint: VideoFittingNormalizedPoint(x: 0.42, y: 0.72),
            jointPoint: VideoFittingNormalizedPoint(x: 0.48, y: 0.48),
            thirdPoint: VideoFittingNormalizedPoint(x: 0.12, y: 0.05)
        )
        let sample = VideoFittingPlaybackOverlaySample(
            id: 1,
            timeSeconds: 1.2,
            kneeAngleDegrees: 112,
            hipAngleDegrees: 91,
            crankPhaseDegrees: 90,
            pedalPoint: kneeOverlay.thirdPoint,
            jointOverlays: [kneeOverlay],
            bodyBounds: VideoFittingNormalizedRect(minX: 0.36, minY: 0.28, maxX: 0.61, maxY: 0.86)
        )

        XCTAssertFalse(sample.allowsOverlayRendering())
    }

    func testPlaybackOverlaySampleAllowsRenderingWithinExpandedBodyBounds() {
        let kneeOverlay = VideoFittingPlaybackJointOverlay(
            kind: .knee,
            angleDegrees: 118,
            firstPoint: VideoFittingNormalizedPoint(x: 0.40, y: 0.75),
            jointPoint: VideoFittingNormalizedPoint(x: 0.46, y: 0.50),
            thirdPoint: VideoFittingNormalizedPoint(x: 0.52, y: 0.88)
        )
        let sample = VideoFittingPlaybackOverlaySample(
            id: 2,
            timeSeconds: 2.4,
            kneeAngleDegrees: 118,
            hipAngleDegrees: 104,
            crankPhaseDegrees: 182,
            pedalPoint: kneeOverlay.thirdPoint,
            jointOverlays: [kneeOverlay],
            bodyBounds: VideoFittingNormalizedRect(minX: 0.36, minY: 0.28, maxX: 0.50, maxY: 0.80)
        )

        XCTAssertTrue(sample.allowsOverlayRendering())
    }

    func testResultOverviewSummaryPendingStateExplainsNextStep() {
        let qualitySummary = VideoFittingJointRecognitionQualitySummaryResolver.resolve(
            selectedView: .side,
            selectedModel: .auto,
            sourceURL: URL(fileURLWithPath: "/tmp/side.mp4"),
            guidance: nil,
            result: nil
        )

        let summary = VideoFittingResultOverviewSummaryResolver.resolve(
            result: nil,
            qualitySummary: qualitySummary,
            selectedView: .side
        )

        XCTAssertEqual(summary.tone, .pending)
        XCTAssertTrue(summary.headline.contains("等待") || summary.headline.contains("Awaiting"))
        XCTAssertFalse(summary.nextActions.isEmpty)
    }

    func testResultOverviewSummaryReadyStateSurfacesFrontConclusion() {
        let result = makeRecognitionResult()
        let qualitySummary = VideoFittingJointRecognitionQualitySummaryResolver.resolve(
            selectedView: .front,
            selectedModel: .auto,
            sourceURL: URL(fileURLWithPath: "/tmp/front.mp4"),
            guidance: nil,
            result: result
        )

        let summary = VideoFittingResultOverviewSummaryResolver.resolve(
            result: result,
            qualitySummary: qualitySummary,
            selectedView: .front
        )

        XCTAssertEqual(summary.tone, .low)
        XCTAssertTrue(summary.headline.contains("前视") || summary.headline.contains("Front"))
        XCTAssertFalse(summary.availableConclusions.isEmpty)
        XCTAssertFalse(summary.detail.isEmpty)
    }

    func testQualityGatePassesWithExcellentMetrics() {
        let metrics = VideoCaptureQualityMetrics(
            fps: 60,
            luma: 0.42,
            sharpness: 0.11,
            occlusionRatio: 0.08,
            distortionRisk: 0.05,
            skeletonAlignability: 0.92
        )

        let result = VideoCaptureQualityGatePolicy.default.evaluate(metrics)

        XCTAssertTrue(result.passed)
        XCTAssertTrue(result.failures.isEmpty)
        XCTAssertEqual(result.grade, .good)
        XCTAssertGreaterThanOrEqual(result.score, 0.8)
    }

    func testQualityGradeLabelsAreNotEmpty() {
        let labels = [
            VideoCaptureQualityGrade.excellent.label,
            VideoCaptureQualityGrade.good.label,
            VideoCaptureQualityGrade.acceptable.label,
            VideoCaptureQualityGrade.rejected.label
        ]
        XCTAssertTrue(labels.allSatisfy { !$0.isEmpty })
    }

    func testQualityFailureTipsCoverAllFailureCases() {
        let allFailures: [VideoCaptureQualityFailure] = [
            .missingFrameRate,
            .lowFrameRate,
            .missingLuma,
            .lowLuma,
            .missingSharpness,
            .lowSharpness,
            .missingOcclusion,
            .highOcclusion,
            .missingDistortion,
            .highDistortion,
            .missingSkeletonAlignability,
            .lowSkeletonAlignability
        ]

        XCTAssertTrue(allFailures.map(\.tip).allSatisfy { !$0.isEmpty })
    }

    func testQualityGateRejectsWhenSignalsAreMissing() {
        let metrics = VideoCaptureQualityMetrics(
            fps: 60,
            luma: nil,
            sharpness: nil,
            occlusionRatio: nil,
            distortionRisk: nil,
            skeletonAlignability: nil
        )

        let result = VideoCaptureQualityGatePolicy.default.evaluate(metrics)

        XCTAssertFalse(result.passed)
        XCTAssertEqual(result.grade, .rejected)
        XCTAssertTrue(result.failures.contains(.missingLuma))
        XCTAssertTrue(result.failures.contains(.missingSharpness))
        XCTAssertTrue(result.failures.contains(.missingOcclusion))
        XCTAssertTrue(result.failures.contains(.missingDistortion))
        XCTAssertTrue(result.failures.contains(.missingSkeletonAlignability))
        XCTAssertEqual(result.failureTips.count, result.failures.count)
    }

    func testQualityGateRejectsWhenMetricsBreakThresholds() {
        let metrics = VideoCaptureQualityMetrics(
            fps: 20,
            luma: 0.2,
            sharpness: 0.03,
            occlusionRatio: 0.65,
            distortionRisk: 0.55,
            skeletonAlignability: 0.3
        )

        let result = VideoCaptureQualityGatePolicy.default.evaluate(metrics)

        XCTAssertFalse(result.passed)
        XCTAssertEqual(result.grade, .rejected)
        XCTAssertTrue(result.failures.contains(.lowFrameRate))
        XCTAssertTrue(result.failures.contains(.lowLuma))
        XCTAssertTrue(result.failures.contains(.lowSharpness))
        XCTAssertTrue(result.failures.contains(.highOcclusion))
        XCTAssertTrue(result.failures.contains(.highDistortion))
        XCTAssertTrue(result.failures.contains(.lowSkeletonAlignability))
        XCTAssertLessThan(result.score, 0.72)
    }

    func testQualityGateAcceptableGradeAtThresholdPass() {
        let metrics = VideoCaptureQualityMetrics(
            fps: 30,
            luma: 0.28,
            sharpness: 0.055,
            occlusionRatio: 0.38,
            distortionRisk: 0.34,
            skeletonAlignability: 0.62
        )

        let result = VideoCaptureQualityGatePolicy.default.evaluate(metrics)

        XCTAssertTrue(result.passed)
        XCTAssertEqual(result.grade, .acceptable)
        XCTAssertTrue(result.failures.isEmpty)
        XCTAssertGreaterThan(result.score, 0)
    }

    func testQualityGateClampsScoreForExtremeInputs() {
        let metrics = VideoCaptureQualityMetrics(
            fps: 240,
            luma: 2.0,
            sharpness: 3.0,
            occlusionRatio: -1.0,
            distortionRisk: -1.0,
            skeletonAlignability: 3.0
        )

        let result = VideoCaptureQualityGatePolicy.default.evaluate(metrics)

        XCTAssertGreaterThanOrEqual(result.score, 0)
        XCTAssertLessThanOrEqual(result.score, 1)
    }

    func testQualityGateDoesNotRejectHighFPSWellTrackedClipForSharpnessOnly() {
        let metrics = VideoCaptureQualityMetrics(
            fps: 239.9,
            luma: 0.46,
            sharpness: 0.012,
            occlusionRatio: 0.04,
            distortionRisk: 0.11,
            skeletonAlignability: 1.0
        )

        let result = VideoCaptureQualityGatePolicy.default.evaluate(metrics)

        XCTAssertTrue(result.passed)
        XCTAssertFalse(result.failures.contains(.lowSharpness))
        XCTAssertNotEqual(result.grade, .rejected)
    }

    func testQualityGateMissingFrameRatePath() {
        let metrics = VideoCaptureQualityMetrics(
            fps: 0,
            luma: 0.4,
            sharpness: 0.08,
            occlusionRatio: 0.1,
            distortionRisk: 0.1,
            skeletonAlignability: 0.8
        )

        let result = VideoCaptureQualityGatePolicy.default.evaluate(metrics)

        XCTAssertFalse(result.passed)
        XCTAssertTrue(result.failures.contains(.missingFrameRate))
        XCTAssertEqual(result.grade, .rejected)
    }

    private func makeRecognitionResult() -> VideoJointAngleAnalysisResult {
        let validPoint = PoseJointPoint(x: 0.5, y: 0.5, confidence: 0.9)
        let stableSample = VideoJointAngleSample(
            id: 0,
            timeSeconds: 0,
            side: .left,
            confidence: 0.92,
            kneeAngleDeg: 72,
            hipAngleDeg: 44,
            crankPhaseDeg: 0,
            leftShoulder: validPoint,
            leftHip: validPoint,
            leftKnee: validPoint,
            leftAnkle: validPoint,
            rightShoulder: validPoint,
            rightHip: validPoint,
            rightKnee: validPoint,
            rightAnkle: validPoint,
            leftToe: validPoint,
            rightToe: validPoint
        )
        let unstableSample = VideoJointAngleSample(
            id: 1,
            timeSeconds: 0.5,
            side: .left,
            confidence: 0.42,
            kneeAngleDeg: 71,
            hipAngleDeg: 43,
            crankPhaseDeg: 20,
            leftShoulder: validPoint,
            leftHip: validPoint,
            leftKnee: nil,
            leftAnkle: validPoint,
            rightShoulder: validPoint,
            rightHip: validPoint,
            rightKnee: validPoint,
            rightAnkle: validPoint,
            leftToe: nil,
            rightToe: nil
        )
        let partiallyOccludedSample = VideoJointAngleSample(
            id: 2,
            timeSeconds: 1.0,
            side: .left,
            confidence: 0.67,
            kneeAngleDeg: 69,
            hipAngleDeg: 41,
            crankPhaseDeg: 40,
            leftShoulder: validPoint,
            leftHip: validPoint,
            leftKnee: validPoint,
            leftAnkle: validPoint,
            rightShoulder: validPoint,
            rightHip: validPoint,
            rightKnee: validPoint,
            rightAnkle: validPoint,
            leftToe: nil,
            rightToe: nil
        )

        return VideoJointAngleAnalysisResult(
            durationSeconds: 12,
            targetFrameCount: 4,
            analyzedFrameCount: 3,
            requestedView: .front,
            resolvedView: .front,
            modelUsed: .appleVision,
            modelFallbackNote: nil,
            dominantSide: .left,
            samples: [stableSample, unstableSample, partiallyOccludedSample],
            crankCenter: nil,
            crankRadius: nil,
            used3DAngleFrameCount: 0,
            kneeStats: JointAngleStats(min: 68, max: 74, mean: 71, sampleCount: 3),
            hipStats: JointAngleStats(min: 40, max: 45, mean: 43, sampleCount: 3),
            cadenceCycles: [],
            cadenceSummary: nil,
            longDurationStability: nil,
            sideCheckpoints: [],
            frontAlignment: FrontAlignmentStats(
                meanKneeFootOffset: 0.12,
                maxKneeFootOffset: 0.18,
                kneeTrackAsymmetry: 0.04,
                hipKneeWidthRatio: 0.88,
                sampleCount: 3
            ),
            frontTrajectory: FrontTrajectoryStats(
                kneeTrajectorySpanNorm: 0.24,
                ankleTrajectorySpanNorm: 0.18,
                toeTrajectorySpanNorm: 0.23,
                kneeOverAnkleInRangeRatio: 0.81,
                sampleCount: 3
            ),
            rearPelvic: nil,
            rearStability: nil,
            rearCoordination: nil,
            frontAutoAssessment: FrontTrajectoryAssessment(
                riskLevel: .low,
                riskScore: 0.18,
                kneeSpanNorm: 0.24,
                ankleSpanNorm: 0.18,
                toeSpanNorm: 0.23,
                inRangeRatio: 0.81,
                kneeTrackAsymmetry: 0.04,
                kneeRangeMinNorm: 0.15,
                kneeRangeMaxNorm: 0.36,
                ankleRangeMinNorm: 0.10,
                ankleRangeMaxNorm: 0.28,
                toeRangeMinNorm: 0.12,
                toeRangeMaxNorm: 0.34,
                inRangeRatioMin: 0.70,
                asymmetryMax: 0.10,
                kneeSpanInRange: true,
                ankleSpanInRange: true,
                toeSpanInRange: true,
                inRangeRatioPass: true,
                asymmetryPass: true,
                flags: []
            ),
            rearAutoAssessment: nil,
            adjustmentPlan: [],
            fittingHints: [
                "前视角有少量足尖遮挡，必要时可在鞋尖加标记点。"
            ]
        )
    }

    private func makeSideRecognitionResult() -> VideoJointAngleAnalysisResult {
        let leftShoulder = PoseJointPoint(x: 0.42, y: 0.76, confidence: 0.93)
        let leftElbow = PoseJointPoint(x: 0.56, y: 0.70, confidence: 0.92)
        let leftWrist = PoseJointPoint(x: 0.66, y: 0.63, confidence: 0.91)
        let leftHip = PoseJointPoint(x: 0.44, y: 0.56, confidence: 0.94)
        let leftKnee = PoseJointPoint(x: 0.53, y: 0.37, confidence: 0.93)
        let leftAnkle = PoseJointPoint(x: 0.60, y: 0.18, confidence: 0.92)
        let leftToe = PoseJointPoint(x: 0.68, y: 0.13, confidence: 0.88)
        let sample0 = VideoJointAngleSample(
            id: 0,
            timeSeconds: 0.4,
            side: .left,
            confidence: 0.91,
            kneeAngleDeg: 115,
            hipAngleDeg: 46,
            ankleAngleDeg: 95,
            shoulderAngleDeg: 83,
            elbowAngleDeg: 148,
            crankPhaseDeg: 2,
            leftShoulder: leftShoulder,
            leftElbow: leftElbow,
            leftWrist: leftWrist,
            leftHip: leftHip,
            leftKnee: leftKnee,
            leftAnkle: leftAnkle,
            rightShoulder: nil,
            rightHip: nil,
            rightKnee: nil,
            rightAnkle: nil,
            leftToe: leftToe,
            rightToe: nil
        )
        let sample3 = VideoJointAngleSample(
            id: 1,
            timeSeconds: 1.1,
            side: .left,
            confidence: 0.92,
            kneeAngleDeg: 92,
            hipAngleDeg: 58,
            ankleAngleDeg: 103,
            shoulderAngleDeg: 87,
            elbowAngleDeg: 145,
            crankPhaseDeg: 90,
            leftShoulder: leftShoulder,
            leftElbow: leftElbow,
            leftWrist: leftWrist,
            leftHip: leftHip,
            leftKnee: leftKnee,
            leftAnkle: leftAnkle,
            rightShoulder: nil,
            rightHip: nil,
            rightKnee: nil,
            rightAnkle: nil,
            leftToe: leftToe,
            rightToe: nil
        )
        let sample9 = VideoJointAngleSample(
            id: 2,
            timeSeconds: 1.9,
            side: .left,
            confidence: 0.90,
            kneeAngleDeg: 76,
            hipAngleDeg: 43,
            ankleAngleDeg: 88,
            shoulderAngleDeg: 81,
            elbowAngleDeg: 151,
            crankPhaseDeg: 270,
            leftShoulder: leftShoulder,
            leftElbow: leftElbow,
            leftWrist: leftWrist,
            leftHip: leftHip,
            leftKnee: leftKnee,
            leftAnkle: leftAnkle,
            rightShoulder: nil,
            rightHip: nil,
            rightKnee: nil,
            rightAnkle: nil,
            leftToe: leftToe,
            rightToe: nil
        )
        let sample6 = VideoJointAngleSample(
            id: 3,
            timeSeconds: 2.6,
            side: .left,
            confidence: 0.94,
            kneeAngleDeg: 119,
            hipAngleDeg: 45,
            ankleAngleDeg: 108,
            shoulderAngleDeg: 84,
            elbowAngleDeg: 147,
            crankPhaseDeg: 180,
            leftShoulder: leftShoulder,
            leftElbow: leftElbow,
            leftWrist: leftWrist,
            leftHip: leftHip,
            leftKnee: leftKnee,
            leftAnkle: leftAnkle,
            rightShoulder: nil,
            rightHip: nil,
            rightKnee: nil,
            rightAnkle: nil,
            leftToe: leftToe,
            rightToe: nil
        )

        return VideoJointAngleAnalysisResult(
            durationSeconds: 18,
            targetFrameCount: 4,
            analyzedFrameCount: 4,
            requestedView: .side,
            resolvedView: .side,
            modelUsed: .appleVision,
            modelFallbackNote: nil,
            dominantSide: .left,
            samples: [sample0, sample3, sample9, sample6],
            crankCenter: PoseJointPoint(x: 0.517, y: 0.176, confidence: 0.93),
            crankRadius: 0.103,
            used3DAngleFrameCount: 4,
            kneeStats: JointAngleStats(min: 76, max: 119, mean: 101, sampleCount: 4),
            hipStats: JointAngleStats(min: 43, max: 58, mean: 48, sampleCount: 4),
            ankleStats: JointAngleStats(min: 88, max: 108, mean: 99, sampleCount: 4),
            cadenceCycles: [],
            cadenceSummary: CadenceCycleSummary(
                cycleCount: 1,
                meanCadenceRPM: 89,
                minCadenceRPM: 89,
                maxCadenceRPM: 89,
                bdcKneeStats: JointAngleStats(min: 115, max: 115, mean: 115, sampleCount: 1),
                saddleHeightRecommendation: nil
            ),
            longDurationStability: nil,
            sideCheckpoints: [
                SideCheckpointSnapshot(checkpoint: .point0, timeSeconds: 0.4, phaseDeg: 2, phaseErrorDeg: 2, kneeAngleDeg: 115, hipAngleDeg: 46, ankleAngleDeg: 95),
                SideCheckpointSnapshot(checkpoint: .point3, timeSeconds: 1.1, phaseDeg: 90, phaseErrorDeg: 0, kneeAngleDeg: 92, hipAngleDeg: 58, ankleAngleDeg: 103),
                SideCheckpointSnapshot(checkpoint: .point6, timeSeconds: 2.6, phaseDeg: 180, phaseErrorDeg: 0, kneeAngleDeg: 119, hipAngleDeg: 45, ankleAngleDeg: 108),
                SideCheckpointSnapshot(checkpoint: .point9, timeSeconds: 1.9, phaseDeg: 270, phaseErrorDeg: 0, kneeAngleDeg: 76, hipAngleDeg: 43, ankleAngleDeg: 88)
            ],
            frontAlignment: nil,
            frontTrajectory: nil,
            rearPelvic: nil,
            rearStability: nil,
            rearCoordination: nil,
            frontAutoAssessment: nil,
            rearAutoAssessment: nil,
            adjustmentPlan: [],
            fittingHints: []
        )
    }
}
