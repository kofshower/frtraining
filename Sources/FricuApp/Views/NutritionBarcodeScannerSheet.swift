import SwiftUI

#if os(iOS)
import AVFoundation
import UIKit
#endif

struct NutritionBarcodeScannerSheet: View {
    let onDetected: (String) -> Void
    let onCancel: () -> Void

    var body: some View {
        #if os(iOS)
        NavigationStack {
            NutritionAVFoundationBarcodeScannerView { code in
                onDetected(code)
            }
            .navigationTitle(L10n.choose(simplifiedChinese: "扫码", english: "Scan Barcode"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.choose(simplifiedChinese: "关闭", english: "Close")) {
                        onCancel()
                    }
                }
            }
        }
        #else
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.choose(simplifiedChinese: "摄像头扫码仅支持 iPhone / iPad", english: "Camera barcode scanning is supported on iPhone / iPad only."))
                .font(.headline)
            Text(L10n.choose(simplifiedChinese: "请在 iOS / iPadOS 设备上使用摄像头扫码，或手工输入条码。", english: "Use camera scanning on iOS/iPadOS, or enter the barcode manually."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button(L10n.choose(simplifiedChinese: "关闭", english: "Close")) { onCancel() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .frame(minWidth: 420, minHeight: 180)
        #endif
    }
}

#if os(iOS)
private struct NutritionAVFoundationBarcodeScannerView: UIViewControllerRepresentable {
    let onDetected: (String) -> Void

    func makeUIViewController(context: Context) -> NutritionBarcodeCaptureViewController {
        let controller = NutritionBarcodeCaptureViewController()
        controller.onDetected = { code in
            onDetected(code)
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: NutritionBarcodeCaptureViewController, context: Context) {}
}

private final class NutritionBarcodeCaptureViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onDetected: ((String) -> Void)?

    private let session = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private let statusLabel = UILabel()
    private var isConfigured = false
    private var emittedCode: String?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configureStatusLabel()
        requestCameraAndConfigureIfNeeded()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
        statusLabel.frame = CGRect(x: 16, y: 16, width: view.bounds.width - 32, height: 44)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        startSessionIfNeeded()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopSessionIfRunning()
    }

    private func configureStatusLabel() {
        statusLabel.textColor = .white
        statusLabel.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        statusLabel.layer.cornerRadius = 10
        statusLabel.clipsToBounds = true
        statusLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        statusLabel.textAlignment = .center
        statusLabel.text = L10n.choose(simplifiedChinese: "将条码置于画面中间", english: "Center the barcode in view")
        view.addSubview(statusLabel)
    }

    private func requestCameraAndConfigureIfNeeded() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureSessionIfNeeded()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if granted {
                        self.configureSessionIfNeeded()
                        self.startSessionIfNeeded()
                    } else {
                        self.statusLabel.text = L10n.choose(simplifiedChinese: "未获得相机权限", english: "Camera permission denied")
                    }
                }
            }
        default:
            statusLabel.text = L10n.choose(simplifiedChinese: "未获得相机权限", english: "Camera permission denied")
        }
    }

    private func configureSessionIfNeeded() {
        guard !isConfigured else { return }
        isConfigured = true

        session.beginConfiguration()
        session.sessionPreset = .high

        guard let videoDevice = AVCaptureDevice.default(for: .video),
              let videoInput = try? AVCaptureDeviceInput(device: videoDevice),
              session.canAddInput(videoInput) else {
            session.commitConfiguration()
            statusLabel.text = L10n.choose(simplifiedChinese: "无法初始化相机", english: "Failed to initialize camera")
            return
        }
        session.addInput(videoInput)

        let metadataOutput = AVCaptureMetadataOutput()
        guard session.canAddOutput(metadataOutput) else {
            session.commitConfiguration()
            statusLabel.text = L10n.choose(simplifiedChinese: "无法读取条码", english: "Failed to read barcodes")
            return
        }
        session.addOutput(metadataOutput)
        metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
        metadataOutput.metadataObjectTypes = supportedMetadataTypes(from: metadataOutput.availableMetadataObjectTypes)

        session.commitConfiguration()

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        preview.frame = view.bounds
        view.layer.insertSublayer(preview, at: 0)
        previewLayer = preview
    }

    private func supportedMetadataTypes(from available: [AVMetadataObject.ObjectType]) -> [AVMetadataObject.ObjectType] {
        let preferred: [AVMetadataObject.ObjectType] = [
            .ean8, .ean13, .upce, .code39, .code93, .code128, .itf14, .qr, .dataMatrix, .pdf417, .aztec
        ]
        let availableSet = Set(available)
        let selected = preferred.filter { availableSet.contains($0) }
        return selected.isEmpty ? available : selected
    }

    private func startSessionIfNeeded() {
        guard isConfigured else { return }
        guard !session.isRunning else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.session.startRunning()
        }
    }

    private func stopSessionIfRunning() {
        guard session.isRunning else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.session.stopRunning()
        }
    }

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard emittedCode == nil else { return }
        for object in metadataObjects {
            guard let machineReadable = object as? AVMetadataMachineReadableCodeObject,
                  let value = machineReadable.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty else {
                continue
            }
            emittedCode = value
            statusLabel.text = L10n.choose(simplifiedChinese: "已识别条码：\(value)", english: "Detected barcode: \(value)")
            stopSessionIfRunning()
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                self?.onDetected?(value)
            }
            break
        }
    }
}
#endif

