import CoreMedia
import Vision
import XCTest
@testable import FricuApp

final class VideoCaptureQualityProbeServiceTests: XCTestCase {
    private let service = VideoCaptureQualityProbeService()

    func testSampleTimesFallsBackToSingleProbeWhenDurationMissing() {
        let times = service.sampleTimes(durationSeconds: nil, count: 5)

        XCTAssertEqual(times.count, 1)
        XCTAssertEqual(CMTimeGetSeconds(times[0]), 0.5, accuracy: 0.0001)
    }

    func testSampleTimesSpansHeadToTailForFiniteDuration() {
        let times = service.sampleTimes(durationSeconds: 10, count: 4).map(CMTimeGetSeconds)

        XCTAssertEqual(times.count, 4)
        XCTAssertEqual(times.first ?? 0, 0.6, accuracy: 0.0001)
        XCTAssertEqual(times.last ?? 0, 9.2, accuracy: 0.0001)
        XCTAssertGreaterThan(times[1], times[0])
        XCTAssertGreaterThan(times[2], times[1])
    }

    func testPoseFrameAlignableRequiresLegAndTrunkVisibility() {
        let alignable = service.poseFrameAlignable(points: [
            .leftShoulder: point(0.42, 0.82),
            .leftHip: point(0.45, 0.6),
            .leftKnee: point(0.46, 0.38),
            .leftAnkle: point(0.47, 0.16)
        ])
        let blocked = service.poseFrameAlignable(points: [
            .leftHip: point(0.45, 0.6),
            .leftKnee: point(0.46, 0.38),
            .leftAnkle: point(0.47, 0.16)
        ])

        XCTAssertTrue(alignable)
        XCTAssertFalse(blocked)
    }

    func testEstimateDistortionRiskReturnsOneWhenNoTrackablePointsExist() {
        XCTAssertEqual(service.estimateDistortionRisk(points: [:]), 1, accuracy: 0.0001)
    }

    func testEstimateDistortionRiskPenalizesEdgeCropping() {
        let centered = service.estimateDistortionRisk(points: symmetricPosePoints(xOffset: 0))
        let edgeBiased = service.estimateDistortionRisk(points: symmetricPosePoints(xOffset: 0.36))

        XCTAssertLessThan(centered, edgeBiased)
        XCTAssertGreaterThan(edgeBiased - centered, 0.15)
    }

    func testEstimateDistortionRiskPenalizesLegAsymmetry() {
        var asymmetric = symmetricPosePoints(xOffset: 0)
        asymmetric[.rightKnee] = point(0.70, 0.50)
        asymmetric[.rightAnkle] = point(0.72, 0.40)

        let centered = service.estimateDistortionRisk(points: symmetricPosePoints(xOffset: 0))
        let distorted = service.estimateDistortionRisk(points: asymmetric)

        XCTAssertGreaterThan(distorted, centered)
    }

    func testClampedLimitsOutputToBounds() {
        XCTAssertEqual(service.clamped(-1, min: 0, max: 1), 0, accuracy: 0.0001)
        XCTAssertEqual(service.clamped(2, min: 0, max: 1), 1, accuracy: 0.0001)
        XCTAssertEqual(service.clamped(0.42, min: 0, max: 1), 0.42, accuracy: 0.0001)
    }

    private func symmetricPosePoints(xOffset: Double) -> [VNHumanBodyPoseObservation.JointName: VideoCapturePosePoint] {
        [
            .leftShoulder: point(0.36 + xOffset, 0.82),
            .rightShoulder: point(0.64 + xOffset, 0.82),
            .leftHip: point(0.40 + xOffset, 0.62),
            .rightHip: point(0.60 + xOffset, 0.62),
            .leftKnee: point(0.42 + xOffset, 0.38),
            .rightKnee: point(0.58 + xOffset, 0.38),
            .leftAnkle: point(0.44 + xOffset, 0.14),
            .rightAnkle: point(0.56 + xOffset, 0.14)
        ]
    }

    private func point(_ x: Double, _ y: Double, confidence: Float = 0.9) -> VideoCapturePosePoint {
        VideoCapturePosePoint(x: x, y: y, confidence: confidence)
    }
}
