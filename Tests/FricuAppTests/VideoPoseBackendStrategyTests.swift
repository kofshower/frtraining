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
                rightKneeAngleDeg: 141,
                rightHipAngleDeg: 126,
                confidence: 0.92
            ),
            External3DAngleSample(
                timeSeconds: 1.03,
                leftKneeAngleDeg: 101,
                leftHipAngleDeg: 87,
                rightKneeAngleDeg: 144,
                rightHipAngleDeg: 129,
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
        XCTAssertEqual(merged.samples[1].kneeAngleDeg, 144)
        XCTAssertEqual(merged.samples[1].hipAngleDeg, 129)
        XCTAssertGreaterThan(merged.samples[0].confidence, samples[0].confidence)
        XCTAssertGreaterThan(merged.samples[1].confidence, samples[1].confidence)
    }
}
