import XCTest
@testable import FricuApp

final class VideoFittingChaosTests: XCTestCase {
    func testChaosWorkflowResolverMaintainsCoreInvariants() {
        var generator = SeededGenerator(seed: 0xF17C0)

        for _ in 0..<500 {
            let assignedViewCount = generator.int(in: 0...4)
            let requiredViewCount = generator.int(in: 1...3)
            let snapshot = VideoFittingWorkflowSnapshot(
                assignedViewCount: assignedViewCount,
                requiredViewCount: requiredViewCount,
                isComplianceRunning: generator.bool(),
                complianceChecked: generator.bool(),
                compliancePassed: generator.bool(),
                isAnalyzing: generator.bool(),
                hasRecognitionResults: generator.bool()
            )

            let states = VideoFittingWorkflowResolver.resolve(from: snapshot)
            let expectedCanRun = assignedViewCount > 0 && snapshot.complianceChecked && snapshot.compliancePassed

            XCTAssertEqual(states.canRunPostCompliance, expectedCanRun)
            XCTAssertEqual(states.viewAssignment, assignedViewCount == 0 ? .pending : (assignedViewCount >= requiredViewCount ? .done : .ready))

            if snapshot.isAnalyzing {
                XCTAssertEqual(states.skeletonRecognition, .running)
                XCTAssertEqual(states.report, .running)
            }

            if assignedViewCount == 0, !snapshot.isAnalyzing {
                XCTAssertEqual(states.skeletonRecognition, .pending)
                XCTAssertEqual(states.report, .pending)
            }
        }
    }

    func testChaosQualityGatePolicyKeepsScoresFiniteAndConsistent() {
        var generator = SeededGenerator(seed: 0x51DE)
        let policy = VideoCaptureQualityGatePolicy.default

        for _ in 0..<400 {
            let metrics = VideoCaptureQualityMetrics(
                fps: generator.specialOrFinite(range: -20...400),
                luma: generator.optionalSpecialOrFinite(range: -0.5...1.5),
                sharpness: generator.optionalSpecialOrFinite(range: -0.2...0.3),
                occlusionRatio: generator.optionalSpecialOrFinite(range: -0.5...1.5),
                distortionRisk: generator.optionalSpecialOrFinite(range: -0.5...1.5),
                skeletonAlignability: generator.optionalSpecialOrFinite(range: -0.5...1.5)
            )

            let result = policy.evaluate(metrics)

            XCTAssertTrue(result.score.isFinite)
            XCTAssertGreaterThanOrEqual(result.score, 0)
            XCTAssertLessThanOrEqual(result.score, 1)
            XCTAssertEqual(Set(result.failures).count, result.failures.count)

            if result.passed {
                XCTAssertTrue(result.failures.isEmpty)
                XCTAssertNotEqual(result.grade, .rejected)
            } else {
                XCTAssertEqual(result.grade, .rejected)
            }
        }
    }

    func testChaosSideRecognitionSummaryNeverEmitsPartialOverlayGeometry() {
        var generator = SeededGenerator(seed: 0xC0FFEE)

        for iteration in 0..<200 {
            let result = makeRandomSideResult(generator: &generator, idBase: iteration * 100)
            let guidance = makePassingGuidance(generator: &generator)
            let summary = VideoFittingJointRecognitionQualitySummaryResolver.resolve(
                selectedView: .side,
                sourceURL: URL(fileURLWithPath: "/tmp/chaos-side-\(iteration).mp4"),
                guidance: guidance,
                result: result
            )

            XCTAssertNotEqual(summary.tone, .blocked)
            XCTAssertEqual(Set(summary.checkpointVisuals.map(\.checkpoint)).isSubset(of: Set(CrankClockCheckpoint.allCases)), true)

            for visual in summary.angleVisuals {
                assertConsistentGeometry(
                    frameTime: visual.frameTimeSeconds,
                    points: [visual.firstPoint, visual.jointPoint, visual.thirdPoint]
                )
                XCTAssertTrue(visual.angleDegrees.isFinite)
            }

            for checkpoint in summary.checkpointVisuals {
                assertConsistentGeometry(
                    frameTime: checkpoint.frameTimeSeconds,
                    points: [checkpoint.firstPoint, checkpoint.jointPoint, checkpoint.thirdPoint]
                )
            }

            for sample in summary.playbackOverlay?.samples ?? [] {
                assertConsistentGeometry(
                    frameTime: sample.timeSeconds,
                    points: [sample.firstPoint, sample.jointPoint, sample.thirdPoint]
                )
                if let bodyBounds = sample.bodyBounds {
                    XCTAssertTrue(bodyBounds.minX.isFinite)
                    XCTAssertTrue(bodyBounds.minY.isFinite)
                    XCTAssertTrue(bodyBounds.maxX.isFinite)
                    XCTAssertTrue(bodyBounds.maxY.isFinite)
                    XCTAssertLessThanOrEqual(bodyBounds.minX, bodyBounds.maxX)
                    XCTAssertLessThanOrEqual(bodyBounds.minY, bodyBounds.maxY)
                    XCTAssertGreaterThanOrEqual(bodyBounds.minX, 0)
                    XCTAssertLessThanOrEqual(bodyBounds.maxX, 1)
                    XCTAssertGreaterThanOrEqual(bodyBounds.minY, 0)
                    XCTAssertLessThanOrEqual(bodyBounds.maxY, 1)
                }
                if let kneeAngle = sample.kneeAngleDegrees {
                    XCTAssertTrue(kneeAngle.isFinite)
                }
                if let hipAngle = sample.hipAngleDegrees {
                    XCTAssertTrue(hipAngle.isFinite)
                }
            }
        }
    }

    func testChaosHipVisualFallsBackCleanlyWhenShouldersDisappear() throws {
        var generator = SeededGenerator(seed: 0xA11CE)
        let result = makeRandomSideResult(generator: &generator, idBase: 9000, includeShoulders: false)
        let summary = VideoFittingJointRecognitionQualitySummaryResolver.resolve(
            selectedView: .side,
            sourceURL: URL(fileURLWithPath: "/tmp/chaos-side-fallback.mp4"),
            guidance: makePassingGuidance(generator: &generator),
            result: result
        )

        let hipVisual = summary.angleVisuals.first(where: { $0.kind == .hip })
        if let hipVisual {
            XCTAssertNotNil(hipVisual.frameTimeSeconds)
            XCTAssertNil(hipVisual.firstPoint)
            XCTAssertNil(hipVisual.jointPoint)
            XCTAssertNil(hipVisual.thirdPoint)
            XCTAssertTrue(hipVisual.angleDegrees.isFinite)
        }
    }

    private func assertConsistentGeometry(
        frameTime: Double?,
        points: [VideoFittingNormalizedPoint?],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let concrete = points.compactMap { $0 }
        XCTAssertTrue(concrete.count == 0 || concrete.count == 3, file: file, line: line)
        if concrete.count == 3 {
            XCTAssertNotNil(frameTime, file: file, line: line)
            for point in concrete {
                XCTAssertTrue(point.x.isFinite, file: file, line: line)
                XCTAssertTrue(point.y.isFinite, file: file, line: line)
                XCTAssertGreaterThanOrEqual(point.x, 0, file: file, line: line)
                XCTAssertLessThanOrEqual(point.x, 1, file: file, line: line)
                XCTAssertGreaterThanOrEqual(point.y, 0, file: file, line: line)
                XCTAssertLessThanOrEqual(point.y, 1, file: file, line: line)
            }
        }
    }

    private func makeRandomSideResult(
        generator: inout SeededGenerator,
        idBase: Int,
        includeShoulders: Bool = true
    ) -> VideoJointAngleAnalysisResult {
        let sampleCount = generator.int(in: 4...18)
        var samples: [VideoJointAngleSample] = []
        samples.reserveCapacity(sampleCount)

        for index in 0..<sampleCount {
            let time = generator.double(in: 0.0...12.0)
            let hip = generator.posePoint()
            let knee = generator.posePoint()
            let ankle = generator.posePoint()
            let shoulder = includeShoulders ? generator.posePoint() : nil

            samples.append(
                VideoJointAngleSample(
                    id: idBase + index,
                    timeSeconds: time,
                    side: .left,
                    confidence: generator.double(in: 0.35...0.99),
                    kneeAngleDeg: generator.maybeFiniteAngle(),
                    hipAngleDeg: generator.maybeFiniteAngle(),
                    crankPhaseDeg: generator.optionalFinite(range: 0...360),
                    leftShoulder: shoulder,
                    leftHip: hip,
                    leftKnee: knee,
                    leftAnkle: ankle,
                    rightShoulder: nil,
                    rightHip: nil,
                    rightKnee: nil,
                    rightAnkle: nil,
                    leftToe: generator.oneIn(4) ? nil : generator.posePoint(),
                    rightToe: nil
                )
            )
        }

        let checkpoints = CrankClockCheckpoint.allCases.shuffled(using: &generator).map { checkpoint in
            SideCheckpointSnapshot(
                checkpoint: checkpoint,
                timeSeconds: generator.double(in: 0.0...12.0),
                phaseDeg: checkpoint.targetPhaseDeg + generator.double(in: -8...8),
                phaseErrorDeg: generator.double(in: 0...8),
                kneeAngleDeg: generator.optionalFinite(range: 70...140),
                hipAngleDeg: generator.optionalFinite(range: 35...125)
            )
        }

        let finiteKnees = samples.compactMap(\.kneeAngleDeg).filter(\.isFinite)
        let finiteHips = samples.compactMap(\.hipAngleDeg).filter(\.isFinite)

        return VideoJointAngleAnalysisResult(
            durationSeconds: 12,
            targetFrameCount: max(sampleCount, sampleCount + generator.int(in: 0...6)),
            analyzedFrameCount: sampleCount,
            requestedView: .side,
            resolvedView: .side,
            modelUsed: .appleVision,
            modelFallbackNote: generator.oneIn(5) ? "chaos-fallback" : nil,
            dominantSide: .left,
            samples: samples,
            crankCenter: nil,
            crankRadius: nil,
            used3DAngleFrameCount: generator.int(in: 0...sampleCount),
            kneeStats: stats(from: finiteKnees),
            hipStats: stats(from: finiteHips),
            cadenceCycles: [],
            cadenceSummary: nil,
            longDurationStability: nil,
            sideCheckpoints: checkpoints,
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

    private func makePassingGuidance(generator: inout SeededGenerator) -> VideoCaptureGuidance {
        let metrics = VideoCaptureQualityMetrics(
            fps: generator.double(in: 120...240),
            luma: generator.double(in: 0.45...0.7),
            sharpness: generator.double(in: 0.02...0.16),
            occlusionRatio: generator.double(in: 0.0...0.06),
            distortionRisk: generator.double(in: 0.0...0.12),
            skeletonAlignability: generator.double(in: 0.9...1.0)
        )
        let gateResult = VideoCaptureQualityGatePolicy.default.evaluate(metrics)
        XCTAssertTrue(gateResult.passed)
        return VideoCaptureGuidance(
            fps: metrics.fps,
            luma: metrics.luma,
            sharpness: metrics.sharpness,
            occlusionRatio: metrics.occlusionRatio,
            distortionRisk: metrics.distortionRisk,
            skeletonAlignability: metrics.skeletonAlignability,
            gateResult: gateResult
        )
    }

    private func stats(from values: [Double]) -> JointAngleStats? {
        guard let minValue = values.min(), let maxValue = values.max(), !values.isEmpty else { return nil }
        let meanValue = values.reduce(0, +) / Double(values.count)
        return JointAngleStats(min: minValue, max: maxValue, mean: meanValue, sampleCount: values.count)
    }
}

private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0xDEADBEEF : seed
    }

    mutating func next() -> UInt64 {
        state = 6364136223846793005 &* state &+ 1442695040888963407
        return state
    }

    mutating func bool() -> Bool {
        next() & 1 == 0
    }

    mutating func oneIn(_ divisor: UInt64) -> Bool {
        next() % divisor == 0
    }

    mutating func int(in range: ClosedRange<Int>) -> Int {
        let width = UInt64(range.upperBound - range.lowerBound + 1)
        return range.lowerBound + Int(next() % width)
    }

    mutating func double(in range: ClosedRange<Double>) -> Double {
        let unit = Double(next()) / Double(UInt64.max)
        return range.lowerBound + (range.upperBound - range.lowerBound) * unit
    }

    mutating func optionalFinite(range: ClosedRange<Double>) -> Double? {
        oneIn(4) ? nil : double(in: range)
    }

    mutating func maybeFiniteAngle() -> Double? {
        if oneIn(5) { return nil }
        if oneIn(11) { return .nan }
        if oneIn(13) { return .infinity }
        return double(in: 30...170)
    }

    mutating func specialOrFinite(range: ClosedRange<Double>) -> Double {
        if oneIn(17) { return .nan }
        if oneIn(19) { return .infinity }
        if oneIn(23) { return -.infinity }
        return double(in: range)
    }

    mutating func optionalSpecialOrFinite(range: ClosedRange<Double>) -> Double? {
        oneIn(4) ? nil : specialOrFinite(range: range)
    }

    mutating func posePoint() -> PoseJointPoint? {
        if oneIn(5) { return nil }
        return PoseJointPoint(
            x: double(in: 0.1...0.9),
            y: double(in: 0.1...0.9),
            confidence: Double(double(in: 0.35...0.99))
        )
    }
}
