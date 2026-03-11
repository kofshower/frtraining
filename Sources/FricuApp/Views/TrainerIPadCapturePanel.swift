import SwiftUI

#if os(iOS)
import AVFoundation
import CoreMotion
import UIKit
import Vision

private enum TrainerCaptureReadiness {
    case pending
    case ready
    case recording
    case blocked

    var color: Color {
        switch self {
        case .pending:
            return .secondary
        case .ready:
            return .green
        case .recording:
            return .red
        case .blocked:
            return .orange
        }
    }
}

private final class TrainerIPadCaptureController: NSObject, ObservableObject {
    @Published var permissionDenied = false
    @Published var isSessionRunning = false
    @Published var isRecording = false
    @Published var horizonDegrees: Double = 0
    @Published var levelReady = false
    @Published var personReady = false
    @Published var bikePoseReady = false
    @Published var framingReady = false
    @Published var readinessMessage = L10n.choose(
        simplifiedChinese: "等待相机初始化...",
        english: "Waiting for camera initialization..."
    )
    @Published var savedVideoPath = "-"
    @Published var lastError = "-"

    let captureSession = AVCaptureSession()
    let guideRectNormalized = CGRect(x: 0.16, y: 0.14, width: 0.68, height: 0.74)

    var canStartRecording: Bool {
        !permissionDenied && isSessionRunning && levelReady && personReady && bikePoseReady && framingReady && !isRecording
    }

    private let sessionQueue = DispatchQueue(label: "fricu.trainer.capture.session", qos: .userInitiated)
    private let analysisQueue = DispatchQueue(label: "fricu.trainer.capture.analysis", qos: .userInitiated)
    private let motionManager = CMMotionManager()
    private let movieOutput = AVCaptureMovieFileOutput()
    private let videoDataOutput = AVCaptureVideoDataOutput()
    private var configured = false
    private var analyzingFrame = false
    private var lastAnalysisTime: CFTimeInterval = 0

    func activate() {
        requestCameraPermissionIfNeeded()
        startMotionUpdates()
    }

    func deactivate() {
        stopRecordingIfNeeded()
        stopSession()
        stopMotionUpdates()
    }

    func startRecordingIfReady() {
        guard canStartRecording else {
            publishStatusMessage()
            return
        }
        guard !movieOutput.isRecording else { return }

        do {
            let outputURL = try makeRecordingOutputURL()
            lastError = "-"
            savedVideoPath = "-"

            if let connection = movieOutput.connection(with: .video), connection.isVideoOrientationSupported {
                connection.videoOrientation = .landscapeRight
            }
            movieOutput.startRecording(to: outputURL, recordingDelegate: self)
        } catch {
            lastError = L10n.choose(
                simplifiedChinese: "创建录制文件失败：\(error.localizedDescription)",
                english: "Failed to create recording file: \(error.localizedDescription)"
            )
        }
    }

    func stopRecordingIfNeeded() {
        guard movieOutput.isRecording else { return }
        movieOutput.stopRecording()
    }

    private func requestCameraPermissionIfNeeded() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            permissionDenied = false
            configureSessionIfNeeded()
            startSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard let self else { return }
                DispatchQueue.main.async {
                    self.permissionDenied = !granted
                    if granted {
                        self.configureSessionIfNeeded()
                        self.startSession()
                    } else {
                        self.readinessMessage = L10n.choose(
                            simplifiedChinese: "未获得相机权限，无法拍摄。",
                            english: "Camera permission denied. Capture unavailable."
                        )
                    }
                }
            }
        default:
            permissionDenied = true
            readinessMessage = L10n.choose(
                simplifiedChinese: "未获得相机权限，无法拍摄。",
                english: "Camera permission denied. Capture unavailable."
            )
        }
    }

    private func configureSessionIfNeeded() {
        guard !configured else { return }
        configured = true

        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.captureSession.beginConfiguration()
            self.captureSession.sessionPreset = .high

            guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                  let input = try? AVCaptureDeviceInput(device: camera),
                  self.captureSession.canAddInput(input) else {
                self.captureSession.commitConfiguration()
                DispatchQueue.main.async {
                    self.lastError = L10n.choose(
                        simplifiedChinese: "无法初始化 iPad 摄像头。",
                        english: "Failed to initialize iPad camera."
                    )
                }
                return
            }
            self.captureSession.addInput(input)

            if self.captureSession.canAddOutput(self.movieOutput) {
                self.captureSession.addOutput(self.movieOutput)
            }

            self.videoDataOutput.alwaysDiscardsLateVideoFrames = true
            self.videoDataOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)
            ]
            self.videoDataOutput.setSampleBufferDelegate(self, queue: self.analysisQueue)
            if self.captureSession.canAddOutput(self.videoDataOutput) {
                self.captureSession.addOutput(self.videoDataOutput)
            }

            if let connection = self.videoDataOutput.connection(with: .video), connection.isVideoOrientationSupported {
                connection.videoOrientation = .landscapeRight
            }
            if let connection = self.movieOutput.connection(with: .video), connection.isVideoOrientationSupported {
                connection.videoOrientation = .landscapeRight
            }

            self.captureSession.commitConfiguration()
        }
    }

    private func startSession() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard !self.captureSession.isRunning else { return }
            self.captureSession.startRunning()
            DispatchQueue.main.async {
                self.isSessionRunning = true
                self.publishStatusMessage()
            }
        }
    }

    private func stopSession() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard self.captureSession.isRunning else { return }
            self.captureSession.stopRunning()
            DispatchQueue.main.async {
                self.isSessionRunning = false
            }
        }
    }

    private func startMotionUpdates() {
        guard motionManager.isDeviceMotionAvailable else { return }
        motionManager.deviceMotionUpdateInterval = 0.12
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let motion else { return }
            let rollDeg = abs(motion.attitude.roll * 180.0 / .pi)
            let pitchDeg = abs(motion.attitude.pitch * 180.0 / .pi)
            let levelMetric = min(rollDeg, pitchDeg)
            horizonDegrees = levelMetric
            levelReady = levelMetric <= 4.5
            publishStatusMessage()
        }
    }

    private func stopMotionUpdates() {
        motionManager.stopDeviceMotionUpdates()
    }

    private func publishStatusMessage() {
        if permissionDenied {
            readinessMessage = L10n.choose(
                simplifiedChinese: "请在系统设置里开启相机权限。",
                english: "Enable camera permission in Settings."
            )
            return
        }
        if isRecording {
            readinessMessage = L10n.choose(
                simplifiedChinese: "录制中，请保持机位稳定。",
                english: "Recording. Keep camera stable."
            )
            return
        }
        if canStartRecording {
            readinessMessage = L10n.choose(
                simplifiedChinese: "人、车把、轮组构图已通过，点击“开始拍摄”。",
                english: "Framing passed. Rider, handlebar, and wheel area look ready. Tap Start."
            )
            return
        }

        var reasons: [String] = []
        if !levelReady {
            reasons.append(L10n.choose(simplifiedChinese: "请调平 iPad（水平误差 <= 4.5°）", english: "Level iPad (tilt <= 4.5°)"))
        }
        if !personReady {
            reasons.append(L10n.choose(simplifiedChinese: "请让骑手进入取景框", english: "Place rider inside guide frame"))
        }
        if !framingReady {
            reasons.append(L10n.choose(simplifiedChinese: "请让车身完整落入取景框", english: "Fit full bike body inside guide frame"))
        }
        if !bikePoseReady {
            reasons.append(L10n.choose(simplifiedChinese: "请确保能看到手腕和踝部（车把/踏频区域）", english: "Keep wrists and ankles visible (bar/pedal area)"))
        }
        readinessMessage = reasons.joined(separator: " · ")
    }

    private func analyze(sampleBuffer: CMSampleBuffer) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let now = CACurrentMediaTime()
        if now - lastAnalysisTime < 0.45 { return }
        if analyzingFrame { return }
        analyzingFrame = true
        lastAnalysisTime = now

        defer { analyzingFrame = false }

        let humanRequest = VNDetectHumanRectanglesRequest()
        humanRequest.maximumObservations = 1
        let poseRequest = VNDetectHumanBodyPoseRequest()

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .right, options: [:])
        do {
            try handler.perform([humanRequest, poseRequest])
        } catch {
            DispatchQueue.main.async {
                self.lastError = L10n.choose(
                    simplifiedChinese: "姿态识别失败：\(error.localizedDescription)",
                    english: "Pose detection failed: \(error.localizedDescription)"
                )
            }
            return
        }

        let humanRect = humanRequest.results?.first?.boundingBox
        let personReady = humanRect != nil

        var framingReady = false
        if let humanRect {
            let overlap = overlapRatio(source: humanRect, target: guideRectNormalized)
            let center = CGPoint(x: humanRect.midX, y: humanRect.midY)
            let centered = guideRectNormalized.insetBy(dx: 0.05, dy: 0.05).contains(center)
            let sizeOK = humanRect.height >= 0.22 && humanRect.height <= 0.95
            framingReady = overlap >= 0.70 && centered && sizeOK
        }

        var bikePoseReady = false
        if let pose = poseRequest.results?.first {
            let wristCount = recognizedPointCount(
                observation: pose,
                joints: [.leftWrist, .rightWrist],
                minConfidence: 0.2
            )
            let ankleCount = recognizedPointCount(
                observation: pose,
                joints: [.leftAnkle, .rightAnkle],
                minConfidence: 0.2
            )
            bikePoseReady = wristCount >= 1 && ankleCount >= 1
        }

        DispatchQueue.main.async {
            self.personReady = personReady
            self.framingReady = framingReady
            self.bikePoseReady = bikePoseReady
            self.publishStatusMessage()
        }
    }

    private func recognizedPointCount(
        observation: VNHumanBodyPoseObservation,
        joints: [VNHumanBodyPoseObservation.JointName],
        minConfidence: Float
    ) -> Int {
        var count = 0
        for joint in joints {
            if let point = try? observation.recognizedPoint(joint), point.confidence >= minConfidence {
                count += 1
            }
        }
        return count
    }

    private func overlapRatio(source: CGRect, target: CGRect) -> CGFloat {
        let area = source.width * source.height
        guard area > 0 else { return 0 }
        let overlap = source.intersection(target)
        if overlap.isNull || overlap.isEmpty { return 0 }
        return (overlap.width * overlap.height) / area
    }

    private func makeRecordingOutputURL() throws -> URL {
        let fm = FileManager.default
        let root = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fm.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? fm.temporaryDirectory
        let directory = root
            .appendingPathComponent("Fricu", isDirectory: true)
            .appendingPathComponent("TrainerCameraCaptures", isDirectory: true)
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)

        let fileName = "trainer-camera-\(DateFormatter.fricuCompactTimestamp.string(from: Date())).mov"
        let output = directory.appendingPathComponent(fileName, isDirectory: false)
        if fm.fileExists(atPath: output.path) {
            try fm.removeItem(at: output)
        }
        return output
    }
}

extension TrainerIPadCaptureController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        analyze(sampleBuffer: sampleBuffer)
    }
}

extension TrainerIPadCaptureController: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(
        _ output: AVCaptureFileOutput,
        didStartRecordingTo fileURL: URL,
        from connections: [AVCaptureConnection]
    ) {
        DispatchQueue.main.async {
            self.isRecording = true
            self.publishStatusMessage()
        }
    }

    func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        DispatchQueue.main.async {
            self.isRecording = false
            if let error {
                self.lastError = L10n.choose(
                    simplifiedChinese: "录制失败：\(error.localizedDescription)",
                    english: "Recording failed: \(error.localizedDescription)"
                )
            } else {
                self.savedVideoPath = outputFileURL.path
                self.lastError = "-"
            }
            self.publishStatusMessage()
        }
    }
}

private struct TrainerCameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> CameraPreviewContainerView {
        let view = CameraPreviewContainerView()
        view.previewLayer.videoGravity = .resizeAspectFill
        view.previewLayer.session = session
        if let connection = view.previewLayer.connection, connection.isVideoOrientationSupported {
            connection.videoOrientation = .landscapeRight
        }
        return view
    }

    func updateUIView(_ uiView: CameraPreviewContainerView, context: Context) {
        uiView.previewLayer.session = session
        if let connection = uiView.previewLayer.connection, connection.isVideoOrientationSupported {
            connection.videoOrientation = .landscapeRight
        }
    }
}

private final class CameraPreviewContainerView: UIView {
    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }
}

struct TrainerIPadCapturePanel: View {
    @StateObject private var captureController = TrainerIPadCaptureController()

    private var readinessState: TrainerCaptureReadiness {
        if captureController.permissionDenied {
            return .blocked
        }
        if captureController.isRecording {
            return .recording
        }
        if captureController.canStartRecording {
            return .ready
        }
        return .pending
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.choose(simplifiedChinese: "iPad 拍摄引导", english: "iPad Capture Guide"))
                .font(.headline)

            ZStack(alignment: .topLeading) {
                TrainerCameraPreviewView(session: captureController.captureSession)
                    .frame(minHeight: 280, maxHeight: 380)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        GeometryReader { proxy in
                            let guide = captureController.guideRectNormalized
                            let width = proxy.size.width
                            let height = proxy.size.height
                            let frameWidth = width * guide.width
                            let frameHeight = height * guide.height
                            let frameX = width * guide.minX
                            let frameY = height * (1.0 - guide.maxY)

                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(readinessState.color, lineWidth: 3)
                                .frame(width: frameWidth, height: frameHeight)
                                .position(x: frameX + frameWidth / 2, y: frameY + frameHeight / 2)

                            Rectangle()
                                .fill(captureController.levelReady ? Color.green : Color.orange)
                                .frame(width: frameWidth * 0.78, height: 2)
                                .position(x: frameX + frameWidth / 2, y: frameY + frameHeight * 0.48)
                        }
                    }

                VStack(alignment: .leading, spacing: 6) {
                    statusChip(
                        title: L10n.choose(simplifiedChinese: "水平", english: "Level"),
                        value: String(format: "%.1f°", captureController.horizonDegrees),
                        pass: captureController.levelReady
                    )
                    statusChip(
                        title: L10n.choose(simplifiedChinese: "人体", english: "Rider"),
                        value: captureController.personReady ? L10n.choose(simplifiedChinese: "已识别", english: "Detected") : L10n.choose(simplifiedChinese: "未识别", english: "Missing"),
                        pass: captureController.personReady
                    )
                    statusChip(
                        title: L10n.choose(simplifiedChinese: "人车同框", english: "Bike Framing"),
                        value: captureController.framingReady && captureController.bikePoseReady
                            ? L10n.choose(simplifiedChinese: "通过", english: "Pass")
                            : L10n.choose(simplifiedChinese: "待调整", english: "Adjust"),
                        pass: captureController.framingReady && captureController.bikePoseReady
                    )
                }
                .padding(10)
            }

            Text(captureController.readinessMessage)
                .font(.subheadline)
                .foregroundStyle(readinessState.color)

            HStack(spacing: 10) {
                Button(L10n.choose(simplifiedChinese: "开始拍摄", english: "Start Capture")) {
                    captureController.startRecordingIfReady()
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(!captureController.canStartRecording)

                Button(L10n.choose(simplifiedChinese: "停止拍摄", english: "Stop Capture")) {
                    captureController.stopRecordingIfNeeded()
                }
                .buttonStyle(.bordered)
                .disabled(!captureController.isRecording)
            }

            LabeledContent(L10n.choose(simplifiedChinese: "保存路径", english: "Saved Path"), value: captureController.savedVideoPath)
                .font(.footnote)
                .lineLimit(2)
                .textSelection(.enabled)

            if captureController.lastError != "-" {
                Text(captureController.lastError)
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }
        .onAppear { captureController.activate() }
        .onDisappear { captureController.deactivate() }
    }

    @ViewBuilder
    private func statusChip(title: String, value: String, pass: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: pass ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(pass ? Color.green : Color.orange)
            Text("\(title): \(value)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
    }
}

#else

struct TrainerIPadCapturePanel: View {
    var body: some View {
        EmptyView()
    }
}

#endif
