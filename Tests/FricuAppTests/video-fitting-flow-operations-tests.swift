import XCTest
@testable import FricuApp

final class VideoFittingFlowOperationsTests: XCTestCase {
    private let planner = VideoFittingFlowPlanningService()
    private let preflightService = VideoFittingPreflightQualityGateService()

    func testAnalyzeSelectedGuardRequiresCompliance() {
        let blocked = VideoFittingFlowGuardPolicy.analyzeSelectedView(
            canRunPostCompliance: false,
            hasRequestedViewVideo: true
        )
        XCTAssertEqual(blocked, .complianceRequired(.analyzeSelectedView))
    }

    func testAnalyzeSelectedGuardRequiresVideo() {
        let blocked = VideoFittingFlowGuardPolicy.analyzeSelectedView(
            canRunPostCompliance: true,
            hasRequestedViewVideo: false
        )
        XCTAssertEqual(blocked, .selectedViewVideoMissing)
    }

    func testAnalyzeSelectedGuardAllowsExecution() {
        let blocked = VideoFittingFlowGuardPolicy.analyzeSelectedView(
            canRunPostCompliance: true,
            hasRequestedViewVideo: true
        )
        XCTAssertNil(blocked)
    }

    func testExportPDFGuardRequiresAnalysisResults() {
        let blocked = VideoFittingFlowGuardPolicy.exportPDF(
            canRunPostCompliance: true,
            hasAnyAnalysisResult: false
        )
        XCTAssertEqual(blocked, .analysisResultsMissing)
    }

    func testQualityGateFailureMessageIncludesViewAndRetakeTips() {
        let guidance = VideoCaptureGuidance(
            fps: 24,
            luma: 0.21,
            sharpness: 0.03,
            occlusionRatio: 0.62,
            distortionRisk: 0.33,
            skeletonAlignability: 0.31,
            gateResult: VideoCaptureQualityGateResult(
                passed: false,
                score: 0.41,
                grade: .rejected,
                failures: [.lowFrameRate, .lowLuma]
            )
        )

        let message = VideoFittingQualityGateMessagePolicy.failureMessage(view: .front, guidance: guidance)
        XCTAssertTrue(message.contains("前视") || message.lowercased().contains("front"))
        XCTAssertTrue(message.contains("质量") || message.lowercased().contains("quality"))
        XCTAssertTrue(message.contains("重拍") || message.lowercased().contains("retake"))
    }

    func testPreflightServiceBuildsPassedFailuresAndGuidanceMap() async {
        let front = URL(fileURLWithPath: "/tmp/front.mov")
        let rear = URL(fileURLWithPath: "/tmp/rear.mov")
        let plans: [(CyclingCameraView, URL)] = [(.front, front), (.rear, rear)]

        let gate = await preflightService.run(plans: plans) { url in
            if url == front {
                return VideoCaptureGuidance(
                    fps: 60,
                    luma: 0.5,
                    sharpness: 0.2,
                    occlusionRatio: 0.05,
                    distortionRisk: 0.05,
                    skeletonAlignability: 0.95,
                    gateResult: VideoCaptureQualityGateResult(
                        passed: true,
                        score: 0.9,
                        grade: .excellent,
                        failures: []
                    )
                )
            }
            return VideoCaptureGuidance(
                fps: 20,
                luma: 0.2,
                sharpness: 0.03,
                occlusionRatio: 0.6,
                distortionRisk: 0.5,
                skeletonAlignability: 0.2,
                gateResult: VideoCaptureQualityGateResult(
                    passed: false,
                    score: 0.22,
                    grade: .rejected,
                    failures: [.lowFrameRate, .lowLuma]
                )
            )
        }

        XCTAssertEqual(gate.passed.count, 1)
        XCTAssertEqual(gate.passed.first?.0, .front)
        XCTAssertEqual(gate.passed.first?.1, front)
        XCTAssertEqual(gate.failures.count, 1)
        XCTAssertTrue(gate.failures[0].contains("后视") || gate.failures[0].lowercased().contains("rear"))
        XCTAssertEqual(gate.guidanceByView.count, 2)
        XCTAssertNotNil(gate.guidanceByView[.front])
        XCTAssertNotNil(gate.guidanceByView[.rear])
    }

    func testAssignedPlansKeepSupportedOrderAndDropMissing() {
        let front = URL(fileURLWithPath: "/tmp/front.mov")
        let rear = URL(fileURLWithPath: "/tmp/rear.mov")
        let plans = planner.assignedPlans(supportedViews: [.front, .side, .rear]) { view in
            switch view {
            case .front: return front
            case .side: return nil
            case .rear: return rear
            case .auto: return nil
            }
        }

        XCTAssertEqual(plans.count, 2)
        XCTAssertEqual(plans[0].0, .front)
        XCTAssertEqual(plans[0].1, front)
        XCTAssertEqual(plans[1].0, .rear)
        XCTAssertEqual(plans[1].1, rear)
    }

    func testUniqueFailuresPreservesFirstOccurrenceOrder() {
        let input = ["A", "B", "A", "C", "B"]
        let output = planner.uniqueFailures(input)
        XCTAssertEqual(output, ["A", "B", "C"])
    }

    func testExportedResultsByViewOnlyIncludesSupportedViews() {
        let frontResult = makeResult(duration: 20)
        let sideResult = makeResult(duration: 30)
        let results = planner.exportedResultsByView(
            resultsByView: [
                .front: frontResult,
                .side: sideResult,
                .auto: makeResult(duration: 10)
            ],
            supportedViews: [.front, .rear]
        )

        XCTAssertEqual(results.count, 1)
        XCTAssertNotNil(results[.front])
        XCTAssertNil(results[.side])
        XCTAssertNil(results[.rear])
        XCTAssertNil(results[.auto])
    }

    func testSuggestedCaptureWindowPrefersCadenceCycleStart() {
        let cycle = CadenceCycleSegment(
            id: 0,
            startTimeSeconds: 7.0,
            endTimeSeconds: 8.0,
            durationSeconds: 1.0,
            cadenceRPM: 90,
            bdcTimeSeconds: nil,
            bdcPhaseDeg: nil,
            bdcKneeAngleDeg: nil
        )
        let result = makeResult(duration: 40, cadenceCycles: [cycle], samples: [])
        let window = VideoFittingCaptureWindowPolicy.suggestedCaptureWindow(from: result, preferredDuration: 20)

        XCTAssertEqual(window.start, 7.0, accuracy: 0.0001)
        XCTAssertEqual(window.duration, 20.0, accuracy: 0.0001)
    }

    func testSuggestedCaptureWindowUsesPhaseSampleFallback() {
        let result = makeResult(
            duration: 18,
            samples: [
                makeSample(id: 0, time: 3.4, phase: 140),
                makeSample(id: 1, time: 10.0, phase: nil)
            ]
        )
        let window = VideoFittingCaptureWindowPolicy.suggestedCaptureWindow(from: result, preferredDuration: 10)

        XCTAssertEqual(window.start, 2.6, accuracy: 0.0001)
        XCTAssertEqual(window.duration, 10.0, accuracy: 0.0001)
    }

    func testSuggestedCaptureWindowFallsBackToCenteredWindow() {
        let result = makeResult(duration: 20, samples: [])
        let window = VideoFittingCaptureWindowPolicy.suggestedCaptureWindow(from: result, preferredDuration: 6)

        XCTAssertEqual(window.start, 4.9, accuracy: 0.0001)
        XCTAssertEqual(window.duration, 6.0, accuracy: 0.0001)
    }

    func testSuggestedCaptureWindowClampsDurationToResultDuration() {
        let result = makeResult(duration: 5, samples: [])
        let window = VideoFittingCaptureWindowPolicy.suggestedCaptureWindow(from: result, preferredDuration: 30)

        XCTAssertEqual(window.duration, 5.0, accuracy: 0.0001)
        XCTAssertGreaterThanOrEqual(window.start, 0.0)
    }

    func testAnalysisResultCoversWindowWhenRangeIsEnough() {
        let result = makeResult(
            duration: 30,
            samples: [
                makeSample(id: 0, time: 0.1, phase: nil),
                makeSample(id: 1, time: 29.9, phase: nil)
            ]
        )
        XCTAssertTrue(
            VideoFittingCaptureWindowPolicy.analysisResultCoversWindow(
                result,
                start: 5,
                duration: 20
            )
        )
    }

    func testAnalysisResultCoversWindowRejectsWhenSamplesEmpty() {
        let result = makeResult(duration: 30, samples: [])
        XCTAssertFalse(
            VideoFittingCaptureWindowPolicy.analysisResultCoversWindow(
                result,
                start: 5,
                duration: 20
            )
        )
    }

    func testAnalysisResultCoversWindowRejectsWhenDurationIsTooShort() {
        let result = makeResult(
            duration: 10,
            samples: [
                makeSample(id: 0, time: 0, phase: nil),
                makeSample(id: 1, time: 9.8, phase: nil)
            ]
        )
        XCTAssertFalse(
            VideoFittingCaptureWindowPolicy.analysisResultCoversWindow(
                result,
                start: 5,
                duration: 12
            )
        )
    }

    private func makeResult(
        duration: Double,
        cadenceCycles: [CadenceCycleSegment] = [],
        samples: [VideoJointAngleSample] = []
    ) -> VideoJointAngleAnalysisResult {
        VideoJointAngleAnalysisResult(
            durationSeconds: duration,
            targetFrameCount: max(1, samples.count),
            analyzedFrameCount: samples.count,
            requestedView: .side,
            resolvedView: .side,
            modelUsed: .appleVision,
            modelFallbackNote: nil,
            dominantSide: .left,
            samples: samples,
            used3DAngleFrameCount: 0,
            kneeStats: nil,
            hipStats: nil,
            cadenceCycles: cadenceCycles,
            cadenceSummary: nil,
            longDurationStability: nil,
            sideCheckpoints: [],
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

    private func makeSample(id: Int, time: Double, phase: Double?) -> VideoJointAngleSample {
        VideoJointAngleSample(
            id: id,
            timeSeconds: time,
            side: .left,
            confidence: 0.8,
            kneeAngleDeg: nil,
            hipAngleDeg: nil,
            crankPhaseDeg: phase,
            leftHip: nil,
            leftKnee: nil,
            leftAnkle: nil,
            rightHip: nil,
            rightKnee: nil,
            rightAnkle: nil,
            leftToe: nil,
            rightToe: nil
        )
    }
}
