import XCTest
@testable import FricuApp

final class VideoPoseBackendStrategyTests: XCTestCase {
    func testAutoPrefersMotionBERTWhenExternalPythonBackendsAreAllowed() {
        XCTAssertEqual(
            VideoJointAngleAnalyzer.poseModelAttemptOrder(
                preferredModel: .auto,
                allowsExternalPythonBackends: true
            ),
            [.mmposeMotionBERT, .mediaPipeBlazePoseGHUM, .appleVision]
        )
    }

    func testMotionBERTSelectionFallsBackToAppleVisionOnPlatformsWithoutExternalPython() {
        XCTAssertEqual(
            VideoJointAngleAnalyzer.poseModelAttemptOrder(
                preferredModel: .mmposeMotionBERT,
                allowsExternalPythonBackends: false
            ),
            [.appleVision]
        )
    }

    func testExternal3DAnglesReplaceMatchingFramesByDetectedSide() {
        let samples = [
            VideoJointAngleSample(
                id: 1,
                timeSeconds: 0.5,
                side: .left,
                confidence: 0.61,
                kneeAngleDeg: 100,
                hipAngleDeg: 90,
                crankPhaseDeg: 180,
                leftShoulder: nil,
                leftHip: PoseJointPoint(x: 0.4, y: 0.4, confidence: 0.8),
                leftKnee: PoseJointPoint(x: 0.45, y: 0.6, confidence: 0.8),
                leftAnkle: PoseJointPoint(x: 0.48, y: 0.8, confidence: 0.8),
                rightShoulder: nil,
                rightHip: nil,
                rightKnee: nil,
                rightAnkle: nil,
                leftToe: nil,
                rightToe: nil
            ),
            VideoJointAngleSample(
                id: 2,
                timeSeconds: 1.0,
                side: .right,
                confidence: 0.57,
                kneeAngleDeg: 110,
                hipAngleDeg: 95,
                crankPhaseDeg: 0,
                leftShoulder: nil,
                leftHip: nil,
                leftKnee: nil,
                leftAnkle: nil,
                rightShoulder: nil,
                rightHip: PoseJointPoint(x: 0.55, y: 0.4, confidence: 0.7),
                rightKnee: PoseJointPoint(x: 0.58, y: 0.6, confidence: 0.7),
                rightAnkle: PoseJointPoint(x: 0.6, y: 0.8, confidence: 0.7),
                leftToe: nil,
                rightToe: nil
            )
        ]
        let external = [
            External3DAngleSample(
                timeSeconds: 0.52,
                leftKneeAngleDeg: 132,
                leftHipAngleDeg: 118,
                leftAnkleAngleDeg: 84,
                rightKneeAngleDeg: 141,
                rightHipAngleDeg: 126,
                rightAnkleAngleDeg: 92,
                confidence: 0.92
            ),
            External3DAngleSample(
                timeSeconds: 1.03,
                leftKneeAngleDeg: 101,
                leftHipAngleDeg: 87,
                leftAnkleAngleDeg: 79,
                rightKneeAngleDeg: 144,
                rightHipAngleDeg: 129,
                rightAnkleAngleDeg: 96,
                confidence: 0.88
            )
        ]

        let merged = VideoJointAngleAnalyzer.mergeExternal3DAngles(
            into: samples,
            from: external,
            toleranceSeconds: 0.08
        )

        XCTAssertEqual(merged.matchedFrameCount, 2)
        XCTAssertEqual(merged.samples[0].kneeAngleDeg, 132)
        XCTAssertEqual(merged.samples[0].hipAngleDeg, 118)
        XCTAssertEqual(merged.samples[0].ankleAngleDeg, 84)
        XCTAssertEqual(merged.samples[1].kneeAngleDeg, 144)
        XCTAssertEqual(merged.samples[1].hipAngleDeg, 129)
        XCTAssertEqual(merged.samples[1].ankleAngleDeg, 96)
        XCTAssertGreaterThan(merged.samples[0].confidence, samples[0].confidence)
        XCTAssertGreaterThan(merged.samples[1].confidence, samples[1].confidence)
    }

    func testNormalizeSideViewPlanarAnglesUsesPreferredSideGeometryForAllAngles() {
        let samples = [
            VideoJointAngleSample(
                id: 1,
                timeSeconds: 0.5,
                side: .left,
                confidence: 0.88,
                kneeAngleDeg: 144,
                hipAngleDeg: 152,
                ankleAngleDeg: 92,
                shoulderAngleDeg: 150,
                elbowAngleDeg: 160,
                crankPhaseDeg: 180,
                leftShoulder: PoseJointPoint(x: 0.20, y: 0.20, confidence: 0.9),
                leftElbow: PoseJointPoint(x: 0.10, y: 0.18, confidence: 0.9),
                leftWrist: PoseJointPoint(x: 0.04, y: 0.16, confidence: 0.9),
                leftHip: PoseJointPoint(x: 0.20, y: 0.40, confidence: 0.9),
                leftKnee: PoseJointPoint(x: 0.28, y: 0.52, confidence: 0.9),
                leftAnkle: PoseJointPoint(x: 0.36, y: 0.64, confidence: 0.9),
                rightShoulder: PoseJointPoint(x: 0.60, y: 0.20, confidence: 0.9),
                rightElbow: PoseJointPoint(x: 0.70, y: 0.20, confidence: 0.9),
                rightWrist: PoseJointPoint(x: 0.80, y: 0.20, confidence: 0.9),
                rightHip: PoseJointPoint(x: 0.60, y: 0.40, confidence: 0.9),
                rightKnee: PoseJointPoint(x: 0.70, y: 0.40, confidence: 0.9),
                rightAnkle: PoseJointPoint(x: 0.70, y: 0.60, confidence: 0.9),
                leftToe: PoseJointPoint(x: 0.42, y: 0.68, confidence: 0.9),
                rightToe: nil
            )
        ]

        let normalized = VideoJointAngleAnalyzer.normalizeSideViewPlanarAngles(
            in: samples,
            preferredSide: .right
        )

        XCTAssertEqual(normalized[0].side, .right)
        XCTAssertEqual(normalized[0].kneeAngleDeg ?? .nan, 90, accuracy: 0.0001)
        XCTAssertEqual(normalized[0].hipAngleDeg ?? .nan, 90, accuracy: 0.0001)
        XCTAssertEqual(normalized[0].ankleAngleDeg ?? .nan, 180, accuracy: 0.0001)
        XCTAssertEqual(normalized[0].shoulderAngleDeg ?? .nan, 90, accuracy: 0.0001)
        XCTAssertEqual(normalized[0].elbowAngleDeg ?? .nan, 180, accuracy: 0.0001)
    }

    func testNormalizeSideViewPlanarAnglesKeepsSameSideFallbackWhenPreferredGeometryIsMissing() {
        let samples = [
            VideoJointAngleSample(
                id: 1,
                timeSeconds: 0.5,
                side: .left,
                confidence: 0.72,
                kneeAngleDeg: 133,
                hipAngleDeg: 118,
                ankleAngleDeg: 86,
                crankPhaseDeg: 0,
                leftShoulder: nil,
                leftHip: PoseJointPoint(x: 0.40, y: 0.60, confidence: 0.9),
                leftKnee: PoseJointPoint(x: 0.55, y: 0.40, confidence: 0.9),
                leftAnkle: PoseJointPoint(x: 0.62, y: 0.20, confidence: 0.9),
                rightShoulder: nil,
                rightHip: nil,
                rightKnee: nil,
                rightAnkle: nil,
                leftToe: nil,
                rightToe: nil
            )
        ]

        let normalized = VideoJointAngleAnalyzer.normalizeSideViewPlanarAngles(
            in: samples,
            preferredSide: .right
        )

        XCTAssertEqual(normalized[0].hipAngleDeg ?? .nan, 118, accuracy: 0.0001)
        XCTAssertEqual(normalized[0].side, .left)
    }

    func testPhaseAngleDegreesTreatsTopAsZeroInImageCoordinates() {
        let center = PoseJointPoint(x: 0.5, y: 0.5, confidence: 1)

        XCTAssertEqual(
            VideoJointAngleAnalyzer.phaseAngleDegrees(
                center: center,
                pedal: PoseJointPoint(x: 0.5, y: 0.3, confidence: 1)
            ) ?? .nan,
            0,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            VideoJointAngleAnalyzer.phaseAngleDegrees(
                center: center,
                pedal: PoseJointPoint(x: 0.7, y: 0.5, confidence: 1)
            ) ?? .nan,
            90,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            VideoJointAngleAnalyzer.phaseAngleDegrees(
                center: center,
                pedal: PoseJointPoint(x: 0.5, y: 0.7, confidence: 1)
            ) ?? .nan,
            180,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            VideoJointAngleAnalyzer.phaseAngleDegrees(
                center: center,
                pedal: PoseJointPoint(x: 0.3, y: 0.5, confidence: 1)
            ) ?? .nan,
            270,
            accuracy: 0.0001
        )
    }

    func testMergeBikeKeypointsInjectsRoadBikeGeometryIntoSamples() {
        let samples = [
            VideoJointAngleSample(
                id: 1,
                timeSeconds: 0.5,
                side: .left,
                confidence: 0.61,
                kneeAngleDeg: 100,
                hipAngleDeg: 90,
                crankPhaseDeg: 180,
                leftShoulder: nil,
                leftHip: PoseJointPoint(x: 0.4, y: 0.4, confidence: 0.8),
                leftKnee: PoseJointPoint(x: 0.45, y: 0.6, confidence: 0.8),
                leftAnkle: PoseJointPoint(x: 0.48, y: 0.8, confidence: 0.8),
                rightShoulder: nil,
                rightHip: nil,
                rightKnee: nil,
                rightAnkle: nil,
                leftToe: PoseJointPoint(x: 0.46, y: 0.86, confidence: 0.8),
                rightToe: nil
            )
        ]
        let bikeSamples = [
            BikeKeypointSample(
                id: 1,
                timeSeconds: 0.52,
                confidence: 0.93,
                bbCenter: PoseJointPoint(x: 0.50, y: 0.76, confidence: 0.91),
                crankEnd: PoseJointPoint(x: 0.50, y: 0.66, confidence: 0.92),
                pedalCenter: PoseJointPoint(x: 0.53, y: 0.64, confidence: 0.94)
            )
        ]

        let merged = VideoJointAngleAnalyzer.mergeBikeKeypoints(
            into: samples,
            from: bikeSamples,
            toleranceSeconds: 0.05
        )

        XCTAssertEqual(merged.matchedFrameCount, 1)
        XCTAssertEqual(try XCTUnwrap(merged.samples[0].bikeBottomBracket).x, 0.50, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(merged.samples[0].bikeCrankEnd).y, 0.66, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(merged.samples[0].bikePedalCenter).x, 0.53, accuracy: 0.0001)
        XCTAssertGreaterThan(merged.samples[0].confidence, samples[0].confidence)
    }
}
