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
}
