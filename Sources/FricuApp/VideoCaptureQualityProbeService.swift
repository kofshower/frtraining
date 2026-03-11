import AVFoundation
import CoreGraphics
import CoreImage
import CoreMedia
import Foundation
import Vision

struct VideoCapturePosePoint: Equatable {
    let x: Double
    let y: Double
    let confidence: Float

    var cgPoint: CGPoint {
        CGPoint(x: x, y: y)
    }
}

struct VideoCaptureQualityProbeService {
    func evaluateCaptureGuidance(for url: URL, maxSamples: Int = 7) async -> VideoCaptureGuidance {
        await Task.detached(priority: .utility) {
            let asset = AVURLAsset(url: url)
            let tracks = (try? await asset.loadTracks(withMediaType: .video)) ?? []
            let nominalFPS: Double
            if let firstTrack = tracks.first, let loadedFPS = try? await firstTrack.load(.nominalFrameRate) {
                nominalFPS = Double(loadedFPS)
            } else {
                nominalFPS = 0
            }
            let fps = max(1.0, nominalFPS)
            let durationSeconds = (try? await asset.load(.duration)).map(CMTimeGetSeconds)
            let frameStats = sampleFrameQualityStats(
                url: url,
                durationSeconds: durationSeconds,
                maxSamples: maxSamples
            )
            let poseQuality = estimatePoseTrackingQuality(
                url: url,
                durationSeconds: durationSeconds,
                maxSamples: maxSamples
            )
            let metrics = VideoCaptureQualityMetrics(
                fps: fps,
                luma: frameStats.luma,
                sharpness: frameStats.sharpness,
                occlusionRatio: poseQuality.occlusionRatio,
                distortionRisk: poseQuality.distortionRisk,
                skeletonAlignability: poseQuality.skeletonAlignability
            )
            let gateResult = VideoCaptureQualityGatePolicy.default.evaluate(metrics)
            return VideoCaptureGuidance(
                fps: metrics.fps,
                luma: metrics.luma,
                sharpness: metrics.sharpness,
                occlusionRatio: metrics.occlusionRatio,
                distortionRisk: metrics.distortionRisk,
                skeletonAlignability: metrics.skeletonAlignability,
                gateResult: gateResult
            )
        }.value
    }

    func sampleFrameQualityStats(
        url: URL,
        durationSeconds: Double?,
        maxSamples: Int
    ) -> (luma: Double?, sharpness: Double?) {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceAfter = .zero
        generator.requestedTimeToleranceBefore = .zero

        let context = CIContext(options: [
            .workingColorSpace: NSNull(),
            .outputColorSpace: NSNull()
        ])

        let times = sampleTimes(durationSeconds: durationSeconds, count: max(3, maxSamples))
        var lumaValues: [Double] = []
        var sharpnessValues: [Double] = []
        lumaValues.reserveCapacity(times.count)
        sharpnessValues.reserveCapacity(times.count)

        for time in times {
            guard let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) else {
                continue
            }
            let metrics = frameLumaAndSharpness(from: cgImage, context: context)
            if let luma = metrics.luma {
                lumaValues.append(luma)
            }
            if let sharpness = metrics.sharpness {
                sharpnessValues.append(sharpness)
            }
        }

        let luma = lumaValues.isEmpty ? nil : lumaValues.reduce(0, +) / Double(lumaValues.count)
        let sharpness = sharpnessValues.isEmpty ? nil : sharpnessValues.reduce(0, +) / Double(sharpnessValues.count)
        return (luma, sharpness)
    }

    func estimatePoseTrackingQuality(
        url: URL,
        durationSeconds: Double?,
        maxSamples: Int
    ) -> (occlusionRatio: Double?, distortionRisk: Double?, skeletonAlignability: Double?) {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceAfter = .zero
        generator.requestedTimeToleranceBefore = .zero

        let jointNames: [VNHumanBodyPoseObservation.JointName] = [
            .leftShoulder, .rightShoulder,
            .leftHip, .rightHip,
            .leftKnee, .rightKnee,
            .leftAnkle, .rightAnkle
        ]

        let times = sampleTimes(durationSeconds: durationSeconds, count: max(3, maxSamples))
        var visibilityRatios: [Double] = []
        var alignabilityRatios: [Double] = []
        var distortionRisks: [Double] = []
        visibilityRatios.reserveCapacity(times.count)
        alignabilityRatios.reserveCapacity(times.count)
        distortionRisks.reserveCapacity(times.count)

        for time in times {
            guard let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) else {
                continue
            }
            let request = VNDetectHumanBodyPoseRequest()
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
                guard let observation = request.results?.first,
                      let points = try? observation.recognizedPoints(.all) else {
                    visibilityRatios.append(0)
                    alignabilityRatios.append(0)
                    distortionRisks.append(1)
                    continue
                }
                let visibleCount = jointNames.reduce(into: 0) { partial, name in
                    if let point = points[name], point.confidence >= 0.3 {
                        partial += 1
                    }
                }
                let normalizedPoints = normalizedPosePoints(from: points)
                visibilityRatios.append(Double(visibleCount) / Double(jointNames.count))
                alignabilityRatios.append(poseFrameAlignable(points: normalizedPoints) ? 1 : 0)
                distortionRisks.append(estimateDistortionRisk(points: normalizedPoints))
            } catch {
                visibilityRatios.append(0)
                alignabilityRatios.append(0)
                distortionRisks.append(1)
            }
        }

        guard !visibilityRatios.isEmpty else {
            return (nil, nil, nil)
        }
        let meanVisibility = visibilityRatios.reduce(0, +) / Double(visibilityRatios.count)
        let meanAlignability = alignabilityRatios.isEmpty
            ? nil
            : alignabilityRatios.reduce(0, +) / Double(alignabilityRatios.count)
        let meanDistortionRisk = distortionRisks.isEmpty
            ? nil
            : distortionRisks.reduce(0, +) / Double(distortionRisks.count)
        return (
            occlusionRatio: clamped(1 - meanVisibility, min: 0, max: 1),
            distortionRisk: meanDistortionRisk,
            skeletonAlignability: meanAlignability
        )
    }

    func poseFrameAlignable(
        points: [VNHumanBodyPoseObservation.JointName: VideoCapturePosePoint]
    ) -> Bool {
        func confident(_ joint: VNHumanBodyPoseObservation.JointName, minScore: Float = 0.35) -> Bool {
            guard let point = points[joint] else { return false }
            return point.confidence >= minScore
        }

        let leftLeg = confident(.leftHip) && confident(.leftKnee) && confident(.leftAnkle)
        let rightLeg = confident(.rightHip) && confident(.rightKnee) && confident(.rightAnkle)
        let leftTrunk = confident(.leftShoulder) && confident(.leftHip)
        let rightTrunk = confident(.rightShoulder) && confident(.rightHip)
        return (leftLeg || rightLeg) && (leftTrunk || rightTrunk)
    }

    func estimateDistortionRisk(
        points: [VNHumanBodyPoseObservation.JointName: VideoCapturePosePoint]
    ) -> Double {
        func distance(_ a: CGPoint, _ b: CGPoint) -> Double {
            let dx = Double(a.x - b.x)
            let dy = Double(a.y - b.y)
            return sqrt(dx * dx + dy * dy)
        }

        func point(_ joint: VNHumanBodyPoseObservation.JointName, minScore: Float = 0.3) -> CGPoint? {
            guard let recognized = points[joint], recognized.confidence >= minScore else {
                return nil
            }
            return recognized.cgPoint
        }

        let tracked: [CGPoint] = [
            point(.leftShoulder), point(.rightShoulder),
            point(.leftHip), point(.rightHip),
            point(.leftKnee), point(.rightKnee),
            point(.leftAnkle), point(.rightAnkle)
        ]
        .compactMap { $0 }

        guard !tracked.isEmpty else { return 1 }

        let edgeCount = tracked.reduce(into: 0) { partial, point in
            if point.x < 0.08 || point.x > 0.92 || point.y < 0.05 || point.y > 0.95 {
                partial += 1
            }
        }
        let edgeRisk = Double(edgeCount) / Double(tracked.count)

        let symmetryRisk: Double = {
            guard let leftHip = point(.leftHip),
                  let leftKnee = point(.leftKnee),
                  let leftAnkle = point(.leftAnkle),
                  let rightHip = point(.rightHip),
                  let rightKnee = point(.rightKnee),
                  let rightAnkle = point(.rightAnkle) else {
                return 0.18
            }
            let leftLeg = distance(leftHip, leftKnee) + distance(leftKnee, leftAnkle)
            let rightLeg = distance(rightHip, rightKnee) + distance(rightKnee, rightAnkle)
            let mean = max(0.001, (leftLeg + rightLeg) / 2)
            let asymmetry = abs(leftLeg - rightLeg) / mean
            return clamped(asymmetry / 0.55, min: 0, max: 1)
        }()

        return clamped(edgeRisk * 0.65 + symmetryRisk * 0.35, min: 0, max: 1)
    }

    func sampleTimes(durationSeconds: Double?, count: Int) -> [CMTime] {
        let safeCount = max(1, count)
        let durationSeconds = max(0, durationSeconds ?? 0)
        if !durationSeconds.isFinite || durationSeconds <= 0.1 {
            return [CMTime(seconds: 0.5, preferredTimescale: 600)]
        }
        let head = min(durationSeconds, 0.6)
        let tail = min(durationSeconds, max(1.0, durationSeconds * 0.92))
        if safeCount == 1 {
            return [CMTime(seconds: head, preferredTimescale: 600)]
        }
        let step = max(0.05, (tail - head) / Double(safeCount - 1))
        return (0..<safeCount).map { index in
            let second = min(durationSeconds, head + Double(index) * step)
            return CMTime(seconds: second, preferredTimescale: 600)
        }
    }

    func frameLumaAndSharpness(from cgImage: CGImage, context: CIContext) -> (luma: Double?, sharpness: Double?) {
        let ciImage = CIImage(cgImage: cgImage)
        let luma = areaAverageLuma(for: ciImage, context: context)
        let sharpness: Double? = {
            guard let edgeFilter = CIFilter(name: "CIEdges") else { return nil }
            edgeFilter.setValue(ciImage, forKey: kCIInputImageKey)
            edgeFilter.setValue(2.8, forKey: kCIInputIntensityKey)
            guard let output = edgeFilter.outputImage else { return nil }
            return areaAverageLuma(for: output, context: context)
        }()
        return (luma, sharpness)
    }

    func areaAverageLuma(for image: CIImage, context: CIContext) -> Double? {
        guard let filter = CIFilter(name: "CIAreaAverage") else {
            return nil
        }
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(CIVector(cgRect: image.extent), forKey: kCIInputExtentKey)
        guard let output = filter.outputImage else {
            return nil
        }
        var bitmap = [UInt8](repeating: 0, count: 4)
        context.render(
            output,
            toBitmap: &bitmap,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: nil
        )

        let r = Double(bitmap[0]) / 255.0
        let g = Double(bitmap[1]) / 255.0
        let b = Double(bitmap[2]) / 255.0
        return 0.2126 * r + 0.7152 * g + 0.0722 * b
    }

    func clamped(_ value: Double, min minValue: Double, max maxValue: Double) -> Double {
        Swift.max(minValue, Swift.min(maxValue, value))
    }

    private func normalizedPosePoints(
        from points: [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint]
    ) -> [VNHumanBodyPoseObservation.JointName: VideoCapturePosePoint] {
        points.mapValues { point in
            VideoCapturePosePoint(
                x: Double(point.location.x),
                y: Double(point.location.y),
                confidence: point.confidence
            )
        }
    }
}
