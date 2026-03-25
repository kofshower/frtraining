import CoreGraphics
import Foundation
import ImageIO
import SwiftUI
import Charts
import UniformTypeIdentifiers

private struct BikeKeypointWorkbenchProgressEntry: Identifiable, Equatable {
    let id = UUID()
    let timestamp: String
    let message: String
}

struct BikeKeypointDatasetPoint: Codable, Equatable {
    var x: Double
    var y: Double
    var confidence: Double
}

struct BikeKeypointDatasetRecord: Identifiable, Codable, Equatable {
    var id: String
    var imagePath: String
    var videoPath: String
    var timeSeconds: Double
    var width: Int
    var height: Int
    var side: String
    var quality: Double
    var source: String
    var keypoints: [String: BikeKeypointDatasetPoint]

    enum CodingKeys: String, CodingKey {
        case id
        case imagePath = "image_path"
        case videoPath = "video_path"
        case timeSeconds = "time_seconds"
        case width
        case height
        case side
        case quality
        case source
        case keypoints
    }

    var imageURL: URL {
        URL(fileURLWithPath: imagePath)
    }
}

struct BikeKeypointDatasetDocument: Codable, Equatable {
    var schema: String
    var keypointNames: [String]
    var pedalCenterRatio: Double?
    var sourceVideos: [String]
    var recordCount: Int
    var records: [BikeKeypointDatasetRecord]

    enum CodingKeys: String, CodingKey {
        case schema
        case keypointNames = "keypoint_names"
        case pedalCenterRatio = "pedal_center_ratio"
        case sourceVideos = "source_videos"
        case recordCount = "record_count"
        case records
    }

    mutating func normalizeRecordCount() {
        recordCount = records.count
    }
}

struct BikeKeypointTrainingRunSummary: Equatable {
    let checkpointURL: URL
    let metadataURL: URL
    let trainRecordCount: Int
    let valRecordCount: Int
    let bestValidationPixelError: Double
    let device: String
}

struct BikeKeypointDatasetFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var document: BikeKeypointDatasetDocument

    init(document: BikeKeypointDatasetDocument) {
        self.document = document
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let decoder = JSONDecoder()
        self.document = try decoder.decode(BikeKeypointDatasetDocument.self, from: data)
    }

    func fileWrapper(configuration _: WriteConfiguration) throws -> FileWrapper {
        var normalized = document
        normalized.normalizeRecordCount()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(normalized)
        return FileWrapper(regularFileWithContents: data)
    }
}

struct BikeKeypointTrainingEpochMetric: Codable, Equatable, Identifiable {
    let epoch: Double
    let trainLoss: Double
    let valMeanPixelError: Double
    let valMeanScore: Double
    let valNME: Double

    var id: Int { Int(epoch.rounded()) }

    enum CodingKeys: String, CodingKey {
        case epoch
        case trainLoss = "train_loss"
        case valMeanPixelError = "val_mean_pixel_error"
        case valMeanScore = "val_mean_score"
        case valNME = "val_nme"
    }
}

struct BikeKeypointTrainingMetadataDocument: Codable, Equatable {
    var schema: String?
    var keypointNames: [String]?
    var inputSize: Int?
    var heatmapStride: Int?
    var consistencyWeight: Double?
    var bestValidationPixelError: Double
    var epochs: Int
    var device: String
    var history: [BikeKeypointTrainingEpochMetric]

    enum CodingKeys: String, CodingKey {
        case schema
        case keypointNames = "keypoint_names"
        case inputSize = "input_size"
        case heatmapStride = "heatmap_stride"
        case consistencyWeight = "consistency_weight"
        case bestValidationPixelError = "best_val_mean_pixel_error"
        case epochs
        case device
        case history
    }
}

struct BikeKeypointTrainingHistorySummary: Identifiable, Equatable {
    let metadataURL: URL
    let checkpointURL: URL
    let runName: String
    let bestValidationPixelError: Double
    let device: String
    let epochs: Int
    let history: [BikeKeypointTrainingEpochMetric]
    let modifiedAt: Date
    let isActive: Bool

    var id: String { metadataURL.path }
}

struct BikeKeypointTrainingHistoryLoader {
    static func loadHistories(
        searchRoots: [URL],
        activeCheckpointPath: String? = nil
    ) -> [BikeKeypointTrainingHistorySummary] {
        let fm = FileManager.default
        let decoder = JSONDecoder()
        let activeCheckpointURL = activeCheckpointPath.map { URL(fileURLWithPath: $0).resolvingSymlinksInPath() }
        var results: [BikeKeypointTrainingHistorySummary] = []

        for root in searchRoots where fm.fileExists(atPath: root.path) {
            let enumerator = fm.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )
            while let metadataURL = enumerator?.nextObject() as? URL {
                guard metadataURL.lastPathComponent == "best.json" else { continue }
                guard
                    let values = try? metadataURL.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey]),
                    values.isRegularFile == true,
                    let data = try? Data(contentsOf: metadataURL),
                    let metadata = try? decoder.decode(BikeKeypointTrainingMetadataDocument.self, from: data)
                else {
                    continue
                }

                let checkpointURL = metadataURL.deletingPathExtension().appendingPathExtension("pt")
                let normalizedCheckpointURL = checkpointURL.resolvingSymlinksInPath()
                let modifiedAt = values.contentModificationDate ?? .distantPast
                let runName = metadataURL.deletingLastPathComponent().lastPathComponent
                let isActive = activeCheckpointURL?.path == normalizedCheckpointURL.path
                results.append(
                    BikeKeypointTrainingHistorySummary(
                        metadataURL: metadataURL,
                        checkpointURL: checkpointURL,
                        runName: runName,
                        bestValidationPixelError: metadata.bestValidationPixelError,
                        device: metadata.device,
                        epochs: metadata.epochs,
                        history: metadata.history,
                        modifiedAt: modifiedAt,
                        isActive: isActive
                    )
                )
            }
        }

        return results.sorted { lhs, rhs in
            if lhs.isActive != rhs.isActive {
                return lhs.isActive
            }
            return lhs.modifiedAt > rhs.modifiedAt
        }
    }
}

private struct BikeKeypointTrainingScriptLocator {
    func resolveScriptURL(
        bundle: Bundle = .main,
        currentDirectoryPath: String = FileManager.default.currentDirectoryPath
    ) -> URL? {
        let fm = FileManager.default
        let cwd = URL(fileURLWithPath: currentDirectoryPath, isDirectory: true)
        let candidates: [URL] = [
            bundle.resourceURL?.appendingPathComponent("BikeKeypointTraining/bike_keypoint_selftrain.py", isDirectory: false),
            bundle.bundleURL.appendingPathComponent("Contents/Resources/BikeKeypointTraining/bike_keypoint_selftrain.py", isDirectory: false),
            cwd.appendingPathComponent("scripts/bike_keypoint_selftrain.py", isDirectory: false),
        ].compactMap { $0 }

        for candidate in candidates where fm.fileExists(atPath: candidate.path) {
            return candidate
        }
        return nil
    }
}

private struct BikeKeypointWorkbenchService {
    private static let progressPrefix = "FRICU_PROGRESS|"

    func resolveWorkspaceRootURL() throws -> URL {
        try VideoWorkspaceDirectoryResolver().resolve(kind: .bikeKeypointWorkspace)
    }

    func latestDatasetURL() -> URL? {
        guard let root = try? resolveWorkspaceRootURL() else { return nil }
        let datasetsRoot = root.appendingPathComponent("datasets", isDirectory: true)
        let fm = FileManager.default
        guard fm.fileExists(atPath: datasetsRoot.path) else { return nil }

        var latest: (url: URL, modificationDate: Date)?
        let enumerator = fm.enumerator(
            at: datasetsRoot,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
        while let candidate = enumerator?.nextObject() as? URL {
            guard candidate.lastPathComponent == "dataset.json" else { continue }
            guard
                let values = try? candidate.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey]),
                values.isRegularFile == true
            else {
                continue
            }
            let modificationDate = values.contentModificationDate ?? .distantPast
            if latest == nil || modificationDate > latest?.modificationDate ?? .distantPast {
                latest = (candidate, modificationDate)
            }
        }
        return latest?.url
    }

    func loadDataset(at datasetURL: URL) throws -> BikeKeypointDatasetDocument {
        let data = try Data(contentsOf: datasetURL)
        let decoder = JSONDecoder()
        return try decoder.decode(BikeKeypointDatasetDocument.self, from: data)
    }

    func recentTrainingHistories(activeCheckpointPath: String? = nil) -> [BikeKeypointTrainingHistorySummary] {
        let workspaceRoot = try? resolveWorkspaceRootURL()
        let currentDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let searchRoots = [
            workspaceRoot?.appendingPathComponent("runs", isDirectory: true),
            currentDirectory.appendingPathComponent(".runtime/BikeKeypointSelfTrain", isDirectory: true)
        ].compactMap { $0 }
        return BikeKeypointTrainingHistoryLoader.loadHistories(
            searchRoots: searchRoots,
            activeCheckpointPath: activeCheckpointPath
        )
    }

    func saveDataset(_ dataset: BikeKeypointDatasetDocument, to datasetURL: URL) throws {
        var normalized = dataset
        normalized.normalizeRecordCount()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(normalized)
        try data.write(to: datasetURL, options: .atomic)
    }

    func generatePseudoLabels(
        videoURL: URL,
        maxSamples: Int,
        minQuality: Double,
        progressHandler: @escaping @Sendable (String) -> Void
    ) async throws -> (datasetURL: URL, document: BikeKeypointDatasetDocument) {
#if os(iOS)
        let _ = videoURL
        let _ = maxSamples
        let _ = minQuality
        let _ = progressHandler
        throw NSError(
            domain: "Fricu.BikeKeypointWorkbench",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: L10n.choose(
                simplifiedChinese: "iPhone/iPad 当前只支持查看已识别结果；样本生成与训练请在 macOS 桌面版执行。",
                english: "iPhone/iPad can only review existing detections for now; sample generation and training run on the macOS desktop app."
            )]
        )
#else
        let workspaceRoot = try resolveWorkspaceRootURL()
        let datasetsRoot = workspaceRoot.appendingPathComponent("datasets", isDirectory: true)
        try FileManager.default.createDirectory(at: datasetsRoot, withIntermediateDirectories: true)
        let runName = "\(videoURL.deletingPathExtension().lastPathComponent)-\(DateFormatter.fricuCompactTimestamp.string(from: Date()))"
        let outputDir = datasetsRoot.appendingPathComponent(runName, isDirectory: true)
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

        let runtimeLocator = MotionBERTRuntimeLocator()
        let invocation = VideoJointAngleAnalyzer.PythonPoseProcessRunner.resolveInvocation(
            preferredEnvironmentVariables: [
                "FRICU_BIKE_KEYPOINT_PYTHON",
                "FRICU_MMPPOSE_PYTHON",
                "FRICU_VIDEO_POSE_PYTHON"
            ],
            preferredCondaEnvironment: "mmpose-mac",
            bundledRuntimeLocator: runtimeLocator
        )
        guard let scriptURL = BikeKeypointTrainingScriptLocator().resolveScriptURL() else {
            throw NSError(
                domain: "Fricu.BikeKeypointWorkbench",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "bike_keypoint_selftrain.py not found"]
            )
        }

        let payload = try await runJSONCommand(
            executableURL: invocation.executableURL,
            arguments: invocation.prefixArguments + [
                scriptURL.path,
                "pseudo-label",
                videoURL.path,
                "--output-dir", outputDir.path,
                "--python", invocation.executableURL.path,
                "--max-samples", String(maxSamples),
                "--min-quality", String(format: "%.2f", minQuality)
            ],
            runtimeLocator: runtimeLocator,
            progressHandler: progressHandler
        )

        let datasetPath = (payload["dataset_path"] as? String) ?? outputDir.appendingPathComponent("dataset.json").path
        let datasetURL = URL(fileURLWithPath: datasetPath)
        return (datasetURL, try loadDataset(at: datasetURL))
#endif
    }

    func trainModel(
        datasetURL: URL,
        epochs: Int,
        batchSize: Int,
        progressHandler: @escaping @Sendable (String) -> Void
    ) async throws -> BikeKeypointTrainingRunSummary {
#if os(iOS)
        let _ = datasetURL
        let _ = epochs
        let _ = batchSize
        let _ = progressHandler
        throw NSError(
            domain: "Fricu.BikeKeypointWorkbench",
            code: 3,
            userInfo: [NSLocalizedDescriptionKey: L10n.choose(
                simplifiedChinese: "iPhone/iPad 当前不支持本地训练，请在 macOS 桌面版执行。",
                english: "Local training is unavailable on iPhone/iPad for now. Use the macOS desktop app."
            )]
        )
#else
        let workspaceRoot = try resolveWorkspaceRootURL()
        let runsRoot = workspaceRoot.appendingPathComponent("runs", isDirectory: true)
        try FileManager.default.createDirectory(at: runsRoot, withIntermediateDirectories: true)
        let datasetName = datasetURL.deletingLastPathComponent().lastPathComponent
        let outputDir = runsRoot.appendingPathComponent("\(datasetName)-\(DateFormatter.fricuCompactTimestamp.string(from: Date()))", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

        let runtimeLocator = MotionBERTRuntimeLocator()
        let invocation = VideoJointAngleAnalyzer.PythonPoseProcessRunner.resolveInvocation(
            preferredEnvironmentVariables: [
                "FRICU_BIKE_KEYPOINT_PYTHON",
                "FRICU_MMPPOSE_PYTHON",
                "FRICU_VIDEO_POSE_PYTHON"
            ],
            preferredCondaEnvironment: "mmpose-mac",
            bundledRuntimeLocator: runtimeLocator
        )
        guard let scriptURL = BikeKeypointTrainingScriptLocator().resolveScriptURL() else {
            throw NSError(
                domain: "Fricu.BikeKeypointWorkbench",
                code: 4,
                userInfo: [NSLocalizedDescriptionKey: "bike_keypoint_selftrain.py not found"]
            )
        }

        let payload = try await runJSONCommand(
            executableURL: invocation.executableURL,
            arguments: invocation.prefixArguments + [
                scriptURL.path,
                "train",
                "--dataset", datasetURL.path,
                "--output-dir", outputDir.path,
                "--epochs", String(epochs),
                "--batch-size", String(batchSize)
            ],
            runtimeLocator: runtimeLocator,
            progressHandler: progressHandler
        )

        let checkpointURL = URL(fileURLWithPath: payload["checkpoint_path"] as? String ?? outputDir.appendingPathComponent("best.pt").path)
        let metadataURL = URL(fileURLWithPath: payload["metadata_path"] as? String ?? outputDir.appendingPathComponent("best.json").path)
        return BikeKeypointTrainingRunSummary(
            checkpointURL: checkpointURL,
            metadataURL: metadataURL,
            trainRecordCount: payload["train_record_count"] as? Int ?? 0,
            valRecordCount: payload["val_record_count"] as? Int ?? 0,
            bestValidationPixelError: payload["best_val_mean_pixel_error"] as? Double ?? .nan,
            device: payload["device"] as? String ?? "cpu"
        )
#endif
    }

    func activateCheckpoint(_ checkpointURL: URL) {
        UserDefaults.standard.set(checkpointURL.path, forKey: BikeKeypointModelLocator.preferredCheckpointDefaultsKey)
    }

    func clearActiveCheckpointOverride() {
        UserDefaults.standard.removeObject(forKey: BikeKeypointModelLocator.preferredCheckpointDefaultsKey)
    }

#if !os(iOS)
    private func runJSONCommand(
        executableURL: URL,
        arguments: [String],
        runtimeLocator: MotionBERTRuntimeLocator,
        progressHandler: @escaping @Sendable (String) -> Void
    ) async throws -> [String: Any] {
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = executableURL
            process.arguments = arguments

            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr

            var environment = ProcessInfo.processInfo.environment
            environment["PYTHONUNBUFFERED"] = "1"
            if let bundledCacheRoot = runtimeLocator.resolveBundledCacheRootURL() {
                environment["XDG_CACHE_HOME"] = bundledCacheRoot.path
                let bundledTorchCache = bundledCacheRoot.appendingPathComponent("torch", isDirectory: true)
                if FileManager.default.fileExists(atPath: bundledTorchCache.path) {
                    environment["TORCH_HOME"] = bundledTorchCache.path
                }
            }
            process.environment = environment

            let stderrBuffer = StderrProgressBuffer(progressHandler: progressHandler)
            stderr.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                stderrBuffer.ingest(data: data)
            }

            try process.run()
            process.waitUntilExit()
            stderr.fileHandleForReading.readabilityHandler = nil

            let stdoutData = stdout.fileHandleForReading.readDataToEndOfFile()
            let stderrData = stderr.fileHandleForReading.readDataToEndOfFile()
            let errorText = stderrBuffer.finalize(with: stderrData)

            guard process.terminationStatus == 0 else {
                throw NSError(
                    domain: "Fricu.BikeKeypointWorkbench",
                    code: Int(process.terminationStatus),
                    userInfo: [NSLocalizedDescriptionKey: errorText.isEmpty ? "unknown error" : errorText]
                )
            }

            let object = try JSONSerialization.jsonObject(with: stdoutData, options: [])
            return object as? [String: Any] ?? [:]
        }.value
    }

    private final class StderrProgressBuffer {
        private let lock = NSLock()
        private var buffer = ""
        private var nonProgressLines: [String] = []
        private let progressHandler: @Sendable (String) -> Void

        init(progressHandler: @escaping @Sendable (String) -> Void) {
            self.progressHandler = progressHandler
        }

        func ingest(data: Data) {
            guard !data.isEmpty else { return }
            let text = String(data: data, encoding: .utf8) ?? ""
            lock.lock()
            defer { lock.unlock() }
            buffer.append(text)
            drainBufferedLines()
        }

        func finalize(with data: Data) -> String {
            lock.lock()
            defer { lock.unlock() }
            buffer.append(String(data: data, encoding: .utf8) ?? "")
            drainBufferedLines()
            let remainder = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
            if !remainder.isEmpty {
                handleLine(remainder)
            }
            buffer.removeAll(keepingCapacity: false)
            return nonProgressLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        }

        private func drainBufferedLines() {
            while let newlineRange = buffer.range(of: "\n") {
                let line = String(buffer[..<newlineRange.lowerBound])
                buffer.removeSubrange(buffer.startIndex...newlineRange.lowerBound)
                handleLine(line)
            }
        }

        private func handleLine(_ rawLine: String) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { return }
            if let message = BikeKeypointWorkbenchService.progressMessage(from: line) {
                progressHandler(message)
            } else {
                nonProgressLines.append(line)
            }
        }
    }

    private static func progressMessage(from line: String) -> String? {
        guard line.hasPrefix(progressPrefix) else { return nil }
        let components = line.split(separator: "|").map(String.init)
        guard components.count >= 2 else { return nil }
        let stage = components[1]
        var fields: [String: String] = [:]
        for component in components.dropFirst(2) {
            let pair = component.split(separator: "=", maxSplits: 1).map(String.init)
            guard pair.count == 2 else { continue }
            fields[pair[0]] = pair[1]
        }

        switch stage {
        case "pseudo_prepare":
            return L10n.choose(
                simplifiedChinese: "开始从侧视视频生成 BB / Crank / Pedal 样本...",
                english: "Starting BB / crank / pedal sample generation from the side-view clip..."
            )
        case "pseudo_video":
            let index = fields["index"] ?? "?"
            let total = fields["total"] ?? "?"
            let name = fields["name"] ?? "video"
            return L10n.choose(
                simplifiedChinese: "样本生成 \(index)/\(total)：\(name)",
                english: "Generating samples \(index)/\(total): \(name)"
            )
        case "pseudo_video_done":
            let records = fields["records"] ?? "0"
            let name = fields["name"] ?? "video"
            return L10n.choose(
                simplifiedChinese: "\(name) 已导出 \(records) 帧可标注样本。",
                english: "\(name) exported \(records) annotatable samples."
            )
        case "pseudo_done":
            let records = fields["record_count"] ?? "0"
            return L10n.choose(
                simplifiedChinese: "样本生成完成，共 \(records) 帧。",
                english: "Sample generation completed with \(records) frames."
            )
        case "train_prepare":
            let train = fields["train_records"] ?? "0"
            let val = fields["val_records"] ?? "0"
            let epochs = fields["epochs"] ?? "?"
            let device = fields["device"] ?? "cpu"
            return L10n.choose(
                simplifiedChinese: "开始训练：训练集 \(train) / 验证集 \(val)，共 \(epochs) 轮，设备 \(device)。",
                english: "Training started with \(train) train / \(val) validation samples for \(epochs) epochs on \(device)."
            )
        case "train_epoch":
            let epoch = fields["epoch"] ?? "?"
            let total = fields["total"] ?? "?"
            let valPX = fields["val_px"] ?? "--"
            let bestPX = fields["best_px"] ?? "--"
            return L10n.choose(
                simplifiedChinese: "训练轮次 \(epoch)/\(total)：验证误差 \(valPX) px，当前最佳 \(bestPX) px。",
                english: "Epoch \(epoch)/\(total): validation error \(valPX) px, best so far \(bestPX) px."
            )
        case "train_done":
            let bestPX = fields["best_px"] ?? "--"
            return L10n.choose(
                simplifiedChinese: "训练完成，最佳验证误差 \(bestPX) px。",
                english: "Training finished with a best validation error of \(bestPX) px."
            )
        default:
            return nil
        }
    }
#endif
}

private enum BikeKeypointEditablePointKind: String, CaseIterable, Identifiable {
    case bbCenter = "bb_center"
    case crankEnd = "crank_end"
    case pedalCenter = "pedal_center"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bbCenter:
            return "BB"
        case .crankEnd:
            return L10n.choose(simplifiedChinese: "曲柄端", english: "Crank")
        case .pedalCenter:
            return L10n.choose(simplifiedChinese: "脚踏", english: "Pedal")
        }
    }

    var color: Color {
        switch self {
        case .bbCenter:
            return .green
        case .crankEnd:
            return .orange
        case .pedalCenter:
            return .blue
        }
    }
}

struct BikeKeypointWorkbenchPanel: View {
    let sideVideoURL: URL?
    let recommendedMaxSamples: Int

    @AppStorage("fricu.bike.keypoint.dataset.last.url.v1") private var lastDatasetURLPath = ""
    @AppStorage(BikeKeypointModelLocator.preferredCheckpointDefaultsKey) private var preferredCheckpointPath = ""

    @State private var datasetDocument: BikeKeypointDatasetDocument?
    @State private var datasetURL: URL?
    @State private var datasetStatusText = "-"
    @State private var trainingStatusText = "-"
    @State private var selectedRecordID: String?
    @State private var isGeneratingSamples = false
    @State private var isTrainingModel = false
    @State private var isDatasetDirty = false
    @State private var hasLoadedInitialDataset = false
    @State private var pseudoLabelMaxSamples = 96
    @State private var pseudoLabelMinQuality = 0.45
    @State private var trainingEpochs = 8
    @State private var trainingBatchSize = 8
    @State private var progressEntries: [BikeKeypointWorkbenchProgressEntry] = []
    @State private var progressScrollTarget: BikeKeypointWorkbenchProgressEntry.ID?
    @State private var isDatasetImporterPresented = false
    @State private var isDatasetExporterPresented = false
    @State private var exportDocument: BikeKeypointDatasetFileDocument?
    @State private var trainingHistories: [BikeKeypointTrainingHistorySummary] = []

    private let service = BikeKeypointWorkbenchService()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.choose(simplifiedChinese: "公路车关键点样本 / 标注 / 训练", english: "Road-bike Samples / Annotation / Training"))
                        .font(.subheadline.weight(.semibold))
                    Text(L10n.choose(
                        simplifiedChinese: "直接在 app 里从当前侧视视频生成 BB / Crank / Pedal 样本，拖点修正，再训练并切换为当前侧视模型。",
                        english: "Generate BB / crank / pedal samples from the current side-view clip, correct them inline, then train and activate the new side-view model."
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                if !preferredCheckpointPath.isEmpty {
                    Button(L10n.choose(simplifiedChinese: "恢复内置模型", english: "Use Bundled Model")) {
                        preferredCheckpointPath = ""
                        service.clearActiveCheckpointOverride()
                        refreshTrainingHistories()
                        trainingStatusText = L10n.choose(
                            simplifiedChinese: "已恢复为内置公路车关键点模型。",
                            english: "Restored the bundled road-bike keypoint model."
                        )
                    }
                    .buttonStyle(.bordered)
                    .disabled(isGeneratingSamples || isTrainingModel)
                }
                Button(L10n.choose(simplifiedChinese: "导入数据集", english: "Import Dataset")) {
                    isDatasetImporterPresented = true
                }
                .buttonStyle(.bordered)
                .disabled(isGeneratingSamples || isTrainingModel)

                Button(L10n.choose(simplifiedChinese: "导出数据集", english: "Export Dataset")) {
                    guard let datasetDocument else { return }
                    exportDocument = BikeKeypointDatasetFileDocument(document: datasetDocument)
                    isDatasetExporterPresented = true
                }
                .buttonStyle(.bordered)
                .disabled(datasetDocument == nil || isGeneratingSamples || isTrainingModel)
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    Stepper(
                        L10n.choose(
                            simplifiedChinese: "样本帧数上限 \(pseudoLabelMaxSamples)",
                            english: "Max sample frames \(pseudoLabelMaxSamples)"
                        ),
                        value: $pseudoLabelMaxSamples,
                        in: 36...240,
                        step: 12
                    )
                    .frame(maxWidth: 260, alignment: .leading)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.choose(simplifiedChinese: "最小样本质量 \(String(format: "%.2f", pseudoLabelMinQuality))", english: "Min sample quality \(String(format: "%.2f", pseudoLabelMinQuality))"))
                            .font(.caption.weight(.semibold))
                        Slider(value: $pseudoLabelMinQuality, in: 0.20...0.90, step: 0.05)
                            .frame(maxWidth: 220)
                    }

                    Spacer()

                    Button(
                        isGeneratingSamples
                            ? L10n.choose(simplifiedChinese: "生成中...", english: "Generating...")
                            : L10n.choose(simplifiedChinese: "从当前侧视视频生成样本", english: "Generate Samples from Side View")
                    ) {
                        handleGenerateSamplesTapped()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isGeneratingSamples || isTrainingModel || sideVideoURL == nil)
                }

                if sideVideoURL == nil {
                    Text(L10n.choose(
                        simplifiedChinese: "提示：请先导入或配置侧视视频，样本生成和 BB/Crank/Pedal 标注只针对侧视机位。",
                        english: "Tip: import or assign a side-view clip first. BB / crank / pedal sampling and annotation are side-view only."
                    ))
                    .font(.caption)
                    .foregroundStyle(.orange)
                }

                statusGrid
            }
            .padding(12)
            .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.secondary.opacity(0.12), lineWidth: 1)
            )

            if !progressEntries.isEmpty || isGeneratingSamples || isTrainingModel {
                progressPanel
            }

            if let datasetDocument, let datasetURL {
                datasetEditor(document: datasetDocument, datasetURL: datasetURL)
            } else {
                Text(L10n.choose(
                    simplifiedChinese: "当前还没有已加载的数据集。你可以先从当前侧视视频生成第一批样本，之后在这里逐帧修正标注并训练模型。",
                    english: "No dataset is loaded yet. Generate your first sample batch from the current side-view clip, then correct annotations here and train the model."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.vertical, 4)
            }
        }
        .onAppear {
            guard !hasLoadedInitialDataset else { return }
            hasLoadedInitialDataset = true
            pseudoLabelMaxSamples = min(max(recommendedMaxSamples, 36), 240)
            loadInitialDatasetIfAvailable()
            refreshTrainingHistories()
        }
        .fileImporter(
            isPresented: $isDatasetImporterPresented,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            handleDatasetImportResult(result)
        }
        .fileExporter(
            isPresented: $isDatasetExporterPresented,
            document: exportDocument,
            contentType: .json,
            defaultFilename: exportDefaultFilename
        ) { result in
            handleDatasetExportResult(result)
        }
    }

    private var statusGrid: some View {
        HStack(alignment: .top, spacing: 12) {
            infoCard(
                title: L10n.choose(simplifiedChinese: "数据集", english: "Dataset"),
                value: datasetDocument.map { "\($0.records.count) 帧" } ?? L10n.choose(simplifiedChinese: "未加载", english: "Not loaded"),
                detail: datasetStatusText
            )
            infoCard(
                title: L10n.choose(simplifiedChinese: "当前模型", english: "Active Model"),
                value: preferredCheckpointPath.isEmpty
                    ? L10n.choose(simplifiedChinese: "内置模型", english: "Bundled model")
                    : URL(fileURLWithPath: preferredCheckpointPath).lastPathComponent,
                detail: preferredCheckpointPath.isEmpty
                    ? L10n.choose(simplifiedChinese: "侧视识别默认使用 app 内置的 BB/Crank/Pedal 模型。", english: "Side-view fitting currently uses the bundled BB / crank / pedal model.")
                    : URL(fileURLWithPath: preferredCheckpointPath).deletingLastPathComponent().path
            )
            infoCard(
                title: L10n.choose(simplifiedChinese: "训练", english: "Training"),
                value: isTrainingModel
                    ? L10n.choose(simplifiedChinese: "进行中", english: "Running")
                    : L10n.choose(simplifiedChinese: "待命", english: "Idle"),
                detail: trainingStatusText
            )
        }
    }

    private var progressPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                if isGeneratingSamples || isTrainingModel {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.top, 2)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                        .padding(.top, 2)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(progressEntries.last?.message ?? L10n.choose(simplifiedChinese: "正在准备任务...", english: "Preparing the task..."))
                        .font(.caption.weight(.semibold))
                    Text(L10n.choose(simplifiedChinese: "最近 \(progressEntries.count) 条样本/训练进度会持续滚动显示。", english: "The latest \(progressEntries.count) sample/training updates keep scrolling here."))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(progressEntries) { entry in
                            HStack(alignment: .top, spacing: 8) {
                                Text(entry.timestamp)
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                Text(entry.message)
                                    .font(.caption)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .id(entry.id)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 150)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .onAppear {
                    if let target = progressScrollTarget {
                        proxy.scrollTo(target, anchor: .bottom)
                    }
                }
                .onChange(of: progressScrollTarget) { _, target in
                    guard let target else { return }
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(target, anchor: .bottom)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func datasetEditor(document: BikeKeypointDatasetDocument, datasetURL: URL) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                Text(L10n.choose(simplifiedChinese: "当前数据集：\(datasetURL.lastPathComponent)", english: "Current dataset: \(datasetURL.lastPathComponent)"))
                    .font(.caption.weight(.semibold))
                Spacer()
                Stepper(
                    L10n.choose(simplifiedChinese: "训练轮次 \(trainingEpochs)", english: "Epochs \(trainingEpochs)"),
                    value: $trainingEpochs,
                    in: 4...24,
                    step: 2
                )
                .frame(maxWidth: 180, alignment: .trailing)
                Stepper(
                    L10n.choose(simplifiedChinese: "批大小 \(trainingBatchSize)", english: "Batch \(trainingBatchSize)"),
                    value: $trainingBatchSize,
                    in: 4...16,
                    step: 4
                )
                .frame(maxWidth: 150, alignment: .trailing)
                Button(L10n.choose(simplifiedChinese: "保存标注", english: "Save Labels")) {
                    handleSaveDatasetTapped()
                }
                .buttonStyle(.bordered)
                .disabled(!isDatasetDirty || isGeneratingSamples || isTrainingModel)

                Button(
                    isTrainingModel
                        ? L10n.choose(simplifiedChinese: "训练中...", english: "Training...")
                        : L10n.choose(simplifiedChinese: "训练当前模型", english: "Train Current Model")
                ) {
                    handleTrainModelTapped()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isGeneratingSamples || isTrainingModel || document.records.isEmpty)
            }

            BikeKeypointThumbnailTimeline(
                records: document.records,
                selectedRecordID: $selectedRecordID
            )

            HStack(alignment: .top, spacing: 12) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(document.records) { record in
                            Button {
                                selectedRecordID = record.id
                            } label: {
                                HStack(alignment: .center, spacing: 10) {
                                    Circle()
                                        .fill(selectedRecordID == record.id ? Color.accentColor : Color.secondary.opacity(0.25))
                                        .frame(width: 8, height: 8)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(record.id)
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.primary)
                                        Text(L10n.choose(
                                            simplifiedChinese: "时间 \(String(format: "%.2fs", record.timeSeconds)) · 质量 \(String(format: "%.2f", record.quality)) · \(record.source)",
                                            english: "Time \(String(format: "%.2fs", record.timeSeconds)) · Quality \(String(format: "%.2f", record.quality)) · \(record.source)"
                                        ))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                }
                                .padding(10)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(selectedRecordID == record.id ? Color.accentColor.opacity(0.10) : Color.secondary.opacity(0.05))
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.trailing, 4)
                }
                .frame(width: 280, height: 440)

                if let binding = selectedRecordBinding {
                    BikeKeypointAnnotationEditor(record: binding, isDirty: $isDatasetDirty)
                        .frame(maxWidth: .infinity, minHeight: 440, maxHeight: 440)
                } else {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.secondary.opacity(0.05))
                        .overlay(
                            Text(L10n.choose(simplifiedChinese: "请选择一帧开始修正 BB / Crank / Pedal。", english: "Select a frame to correct the BB / crank / pedal points."))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        )
                        .frame(maxWidth: .infinity, minHeight: 440, maxHeight: 440)
                }
            }

            BikeKeypointTrainingHistoryPanel(
                histories: trainingHistories,
                activeCheckpointPath: preferredCheckpointPath
            )
        }
        .padding(12)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.12), lineWidth: 1)
        )
    }

    private var selectedRecordBinding: Binding<BikeKeypointDatasetRecord>? {
        guard let selectedRecordID, let document = datasetDocument else { return nil }
        guard let index = document.records.firstIndex(where: { $0.id == selectedRecordID }) else { return nil }
        return Binding(
            get: { datasetDocument?.records[index] ?? document.records[index] },
            set: { newValue in
                guard var updated = datasetDocument else { return }
                updated.records[index] = newValue
                datasetDocument = updated
            }
        )
    }

    @ViewBuilder
    private func infoCard(title: String, value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.white.opacity(0.70), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var exportDefaultFilename: String {
        if let datasetURL {
            return datasetURL.deletingPathExtension().lastPathComponent
        }
        return "fr-training-bike-keypoints"
    }

    private func refreshTrainingHistories() {
        trainingHistories = service.recentTrainingHistories(
            activeCheckpointPath: preferredCheckpointPath.isEmpty ? nil : preferredCheckpointPath
        )
    }

    private func loadInitialDatasetIfAvailable() {
        if !lastDatasetURLPath.isEmpty {
            let candidate = URL(fileURLWithPath: lastDatasetURLPath)
            if FileManager.default.fileExists(atPath: candidate.path) {
                loadDataset(candidate)
                return
            }
        }
        if let latest = service.latestDatasetURL() {
            loadDataset(latest)
        }
    }

    private func loadDataset(_ url: URL) {
        do {
            let document = try service.loadDataset(at: url)
            datasetDocument = document
            datasetURL = url
            selectedRecordID = document.records.first?.id
            lastDatasetURLPath = url.path
            isDatasetDirty = false
            refreshTrainingHistories()
            datasetStatusText = L10n.choose(
                simplifiedChinese: "已加载 \(document.records.count) 帧，路径：\(url.deletingLastPathComponent().lastPathComponent)",
                english: "Loaded \(document.records.count) frames from \(url.deletingLastPathComponent().lastPathComponent)."
            )
        } catch {
            datasetStatusText = error.localizedDescription
        }
    }

    private func handleDatasetImportResult(_ result: Result<[URL], Error>) {
        isDatasetImporterPresented = false
        switch result {
        case let .success(urls):
            guard let importedURL = urls.first else { return }
            loadDataset(importedURL)
            appendProgressEntry(
                L10n.choose(
                    simplifiedChinese: "已导入外部数据集 \(importedURL.lastPathComponent)。",
                    english: "Imported the external dataset \(importedURL.lastPathComponent)."
                )
            )
        case let .failure(error):
            datasetStatusText = error.localizedDescription
            appendProgressEntry(
                L10n.choose(
                    simplifiedChinese: "导入失败：\(error.localizedDescription)",
                    english: "Import failed: \(error.localizedDescription)"
                )
            )
        }
    }

    private func handleDatasetExportResult(_ result: Result<URL, Error>) {
        isDatasetExporterPresented = false
        switch result {
        case let .success(url):
            datasetStatusText = L10n.choose(
                simplifiedChinese: "数据集 JSON 已导出到 \(url.lastPathComponent)。样本帧路径会保留为当前机器上的绝对路径。",
                english: "The dataset JSON was exported to \(url.lastPathComponent). Sample frame paths remain absolute paths on this machine."
            )
            appendProgressEntry(
                L10n.choose(
                    simplifiedChinese: "数据集导出完成。",
                    english: "Dataset export completed."
                )
            )
        case let .failure(error):
            datasetStatusText = error.localizedDescription
            appendProgressEntry(
                L10n.choose(
                    simplifiedChinese: "导出失败：\(error.localizedDescription)",
                    english: "Export failed: \(error.localizedDescription)"
                )
            )
        }
        exportDocument = nil
    }

    private func handleGenerateSamplesTapped() {
        guard let sideVideoURL else { return }
        isGeneratingSamples = true
        datasetStatusText = L10n.choose(simplifiedChinese: "正在生成侧视样本...", english: "Generating side-view samples...")
        appendProgressEntry(
            L10n.choose(
                simplifiedChinese: "开始为当前侧视视频生成 BB / Crank / Pedal 样本。",
                english: "Starting BB / crank / pedal sample generation for the current side-view video."
            )
        )

        Task {
            do {
                let result = try await service.generatePseudoLabels(
                    videoURL: sideVideoURL,
                    maxSamples: pseudoLabelMaxSamples,
                    minQuality: pseudoLabelMinQuality,
                    progressHandler: { message in
                        Task { @MainActor in
                            appendProgressEntry(message)
                        }
                    }
                )
                await MainActor.run {
                    isGeneratingSamples = false
                    datasetDocument = result.document
                    datasetURL = result.datasetURL
                    selectedRecordID = result.document.records.first?.id
                    lastDatasetURLPath = result.datasetURL.path
                    isDatasetDirty = false
                    refreshTrainingHistories()
                    datasetStatusText = L10n.choose(
                        simplifiedChinese: "样本生成完成，共 \(result.document.records.count) 帧，可直接开始修正标注。",
                        english: "Sample generation finished with \(result.document.records.count) frames and is ready for annotation."
                    )
                    appendProgressEntry(
                        L10n.choose(
                            simplifiedChinese: "已加载新数据集，拖动右侧圆点即可开始修正。",
                            english: "The new dataset is loaded. Drag the markers on the right to start correcting labels."
                        )
                    )
                }
            } catch {
                await MainActor.run {
                    isGeneratingSamples = false
                    datasetStatusText = error.localizedDescription
                    appendProgressEntry(
                        L10n.choose(
                            simplifiedChinese: "样本生成失败：\(error.localizedDescription)",
                            english: "Sample generation failed: \(error.localizedDescription)"
                        )
                    )
                }
            }
        }
    }

    private func handleSaveDatasetTapped() {
        guard let datasetDocument, let datasetURL else { return }
        do {
            try service.saveDataset(datasetDocument, to: datasetURL)
            isDatasetDirty = false
            exportDocument = BikeKeypointDatasetFileDocument(document: datasetDocument)
            datasetStatusText = L10n.choose(
                simplifiedChinese: "标注已保存到 \(datasetURL.lastPathComponent)。",
                english: "Annotations saved to \(datasetURL.lastPathComponent)."
            )
            appendProgressEntry(
                L10n.choose(
                    simplifiedChinese: "数据集保存完成，训练将使用最新标注。",
                    english: "The dataset was saved. Training will use the latest labels."
                )
            )
        } catch {
            datasetStatusText = error.localizedDescription
            appendProgressEntry(
                L10n.choose(
                    simplifiedChinese: "保存失败：\(error.localizedDescription)",
                    english: "Save failed: \(error.localizedDescription)"
                )
            )
        }
    }

    private func handleTrainModelTapped() {
        guard let datasetURL else { return }
        if isDatasetDirty {
            handleSaveDatasetTapped()
        }

        isTrainingModel = true
        trainingStatusText = L10n.choose(
            simplifiedChinese: "正在训练新的 BB / Crank / Pedal 模型...",
            english: "Training a new BB / crank / pedal model..."
        )
        appendProgressEntry(
            L10n.choose(
                simplifiedChinese: "开始训练当前数据集；训练完成后会自动切换到新 checkpoint。",
                english: "Training started for the current dataset. The new checkpoint will become active automatically."
            )
        )

        Task {
            do {
                let summary = try await service.trainModel(
                    datasetURL: datasetURL,
                    epochs: trainingEpochs,
                    batchSize: trainingBatchSize,
                    progressHandler: { message in
                        Task { @MainActor in
                            appendProgressEntry(message)
                        }
                    }
                )
                await MainActor.run {
                    isTrainingModel = false
                    service.activateCheckpoint(summary.checkpointURL)
                    preferredCheckpointPath = summary.checkpointURL.path
                    refreshTrainingHistories()
                    trainingStatusText = L10n.choose(
                        simplifiedChinese: "训练完成：最佳验证误差 \(String(format: "%.2f", summary.bestValidationPixelError)) px，已切换到新模型。",
                        english: "Training finished: best validation error \(String(format: "%.2f", summary.bestValidationPixelError)) px, and the new model is now active."
                    )
                    appendProgressEntry(
                        L10n.choose(
                            simplifiedChinese: "新模型已激活，下一次侧视识别会直接使用它。",
                            english: "The new model is active now. The next side-view fitting run will use it directly."
                        )
                    )
                }
            } catch {
                await MainActor.run {
                    isTrainingModel = false
                    trainingStatusText = error.localizedDescription
                    appendProgressEntry(
                        L10n.choose(
                            simplifiedChinese: "训练失败：\(error.localizedDescription)",
                            english: "Training failed: \(error.localizedDescription)"
                        )
                    )
                }
            }
        }
    }

    @MainActor
    private func appendProgressEntry(_ message: String) {
        let entry = BikeKeypointWorkbenchProgressEntry(
            timestamp: Self.progressTimestampFormatter.string(from: Date()),
            message: message
        )
        progressEntries.append(entry)
        if progressEntries.count > 120 {
            progressEntries.removeFirst(progressEntries.count - 120)
        }
        progressScrollTarget = entry.id
    }

    private static let progressTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}

private struct BikeKeypointAnnotationEditor: View {
    @Binding var record: BikeKeypointDatasetRecord
    @Binding var isDirty: Bool
    @State private var cgImage: CGImage?

    var body: some View {
        GeometryReader { proxy in
            let frame = CGRect(origin: .zero, size: proxy.size)
            let imageRect = contentRect(in: frame)

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.black.opacity(0.92))

                if let cgImage {
                    Image(decorative: cgImage, scale: 1.0)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                } else {
                    VStack(spacing: 8) {
                        ProgressView()
                        Text(L10n.choose(simplifiedChinese: "正在加载样本帧...", english: "Loading the sample frame..."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                annotationLines(in: imageRect)

                ForEach(BikeKeypointEditablePointKind.allCases) { kind in
                    annotationMarker(for: kind, in: imageRect)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.choose(
                        simplifiedChinese: "拖动圆点修正 BB、曲柄端和脚踏中心。保存后可直接训练当前数据集。",
                        english: "Drag the markers to correct the BB, crank end, and pedal center. Save the dataset before training."
                    ))
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.88))
                    Text(L10n.choose(
                        simplifiedChinese: "时间 \(String(format: "%.2fs", record.timeSeconds)) · 来源 \(record.source) · 质量 \(String(format: "%.2f", record.quality))",
                        english: "Time \(String(format: "%.2fs", record.timeSeconds)) · Source \(record.source) · Quality \(String(format: "%.2f", record.quality))"
                    ))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.72))
                }
                .padding(12)
            }
        }
        .background(Color.secondary.opacity(0.03), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.12), lineWidth: 1)
        )
        .task(id: record.imagePath) {
            cgImage = BikeKeypointAnnotationImageLoader.loadImage(at: record.imageURL)
        }
    }

    @ViewBuilder
    private func annotationLines(in imageRect: CGRect) -> some View {
        if
            let bb = point(for: .bbCenter),
            let crank = point(for: .crankEnd),
            let pedal = point(for: .pedalCenter)
        {
            Path { path in
                path.move(to: location(for: bb, in: imageRect))
                path.addLine(to: location(for: crank, in: imageRect))
                path.addLine(to: location(for: pedal, in: imageRect))
            }
            .stroke(Color.white.opacity(0.8), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
        }
    }

    @ViewBuilder
    private func annotationMarker(for kind: BikeKeypointEditablePointKind, in imageRect: CGRect) -> some View {
        let point = point(for: kind) ?? BikeKeypointDatasetPoint(x: 0.5, y: 0.5, confidence: 0.99)
        let location = location(for: point, in: imageRect)

        VStack(spacing: 4) {
            Circle()
                .fill(kind.color)
                .frame(width: 16, height: 16)
                .overlay(Circle().stroke(Color.white, lineWidth: 2))
                .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
            Text(kind.title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(kind.color.opacity(0.92), in: Capsule())
        }
        .position(location)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    updatePoint(kind, location: value.location, in: imageRect)
                }
        )
    }

    private func point(for kind: BikeKeypointEditablePointKind) -> BikeKeypointDatasetPoint? {
        record.keypoints[kind.rawValue]
    }

    private func updatePoint(_ kind: BikeKeypointEditablePointKind, location: CGPoint, in imageRect: CGRect) {
        guard imageRect.width > 1, imageRect.height > 1 else { return }
        let normalizedX = min(max((location.x - imageRect.minX) / imageRect.width, 0), 1)
        let normalizedY = min(max((location.y - imageRect.minY) / imageRect.height, 0), 1)
        record.keypoints[kind.rawValue] = BikeKeypointDatasetPoint(
            x: normalizedX,
            y: normalizedY,
            confidence: 0.99
        )
        record.source = "manual"
        record.quality = max(record.quality, 0.95)
        isDirty = true
    }

    private func location(for point: BikeKeypointDatasetPoint, in imageRect: CGRect) -> CGPoint {
        CGPoint(
            x: imageRect.minX + point.x * imageRect.width,
            y: imageRect.minY + point.y * imageRect.height
        )
    }

    private func contentRect(in frame: CGRect) -> CGRect {
        let width = max(Double(record.width), 1)
        let height = max(Double(record.height), 1)
        let imageAspect = width / height
        let frameAspect = frame.width / max(frame.height, 1)

        if imageAspect > frameAspect {
            let fittedHeight = frame.width / imageAspect
            let originY = frame.minY + (frame.height - fittedHeight) / 2
            return CGRect(x: frame.minX, y: originY, width: frame.width, height: fittedHeight)
        } else {
            let fittedWidth = frame.height * imageAspect
            let originX = frame.minX + (frame.width - fittedWidth) / 2
            return CGRect(x: originX, y: frame.minY, width: fittedWidth, height: frame.height)
        }
    }
}

private struct BikeKeypointThumbnailTimeline: View {
    let records: [BikeKeypointDatasetRecord]
    @Binding var selectedRecordID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(L10n.choose(simplifiedChinese: "帧缩略图时间轴", english: "Frame Thumbnail Timeline"))
                    .font(.caption.weight(.semibold))
                Spacer()
                Text(L10n.choose(
                    simplifiedChinese: "按时间浏览样本，点哪一帧就编辑哪一帧。",
                    english: "Browse samples by time and edit whichever frame you tap."
                ))
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 10) {
                    ForEach(records) { record in
                        BikeKeypointThumbnailCell(
                            record: record,
                            isSelected: selectedRecordID == record.id
                        )
                        .onTapGesture {
                            selectedRecordID = record.id
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(10)
        .background(Color.white.opacity(0.70), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct BikeKeypointThumbnailCell: View {
    let record: BikeKeypointDatasetRecord
    let isSelected: Bool
    @State private var cgImage: CGImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.black.opacity(0.88))
                if let cgImage {
                    Image(decorative: cgImage, scale: 1.0)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 112, height: 76)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                } else {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .frame(width: 112, height: 76)

            Text(String(format: "%.2fs", record.timeSeconds))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.primary)
            Text(L10n.choose(
                simplifiedChinese: "质 \(String(format: "%.2f", record.quality))",
                english: "Q \(String(format: "%.2f", record.quality))"
            ))
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
        }
        .padding(8)
        .frame(width: 128, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor : Color.secondary.opacity(0.12), lineWidth: isSelected ? 2 : 1)
        )
        .task(id: record.imagePath) {
            cgImage = BikeKeypointAnnotationImageLoader.loadThumbnail(at: record.imageURL, maxPixelSize: 320)
        }
    }
}

private struct BikeKeypointTrainingHistoryPanel: View {
    let histories: [BikeKeypointTrainingHistorySummary]
    let activeCheckpointPath: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(L10n.choose(simplifiedChinese: "训练历史对比", english: "Training History Comparison"))
                    .font(.caption.weight(.semibold))
                Spacer()
                Text(L10n.choose(
                    simplifiedChinese: histories.isEmpty ? "当前还没有训练历史。" : "最近训练会按当前激活模型和时间排序。",
                    english: histories.isEmpty ? "No training history yet." : "Recent runs are sorted by the active model first, then by time."
                ))
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            if histories.isEmpty {
                Text(L10n.choose(
                    simplifiedChinese: "第一次训练完成后，这里会对比不同 run 的验证误差曲线和最佳像素误差。",
                    english: "Once your first training run finishes, compare validation curves and best pixel errors here."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            } else {
                Chart {
                    ForEach(histories.prefix(4)) { summary in
                        ForEach(summary.history) { epoch in
                            LineMark(
                                x: .value("Epoch", epoch.epoch),
                                y: .value("ValPx", epoch.valMeanPixelError)
                            )
                            .foregroundStyle(by: .value("Run", summary.runName))

                            PointMark(
                                x: .value("Epoch", epoch.epoch),
                                y: .value("ValPx", epoch.valMeanPixelError)
                            )
                            .foregroundStyle(by: .value("Run", summary.runName))
                        }
                    }
                }
                .frame(height: 180)
                .chartYAxisLabel(L10n.choose(simplifiedChinese: "验证误差 px", english: "Validation px"))
                .chartXAxisLabel(L10n.choose(simplifiedChinese: "训练轮次", english: "Epoch"))

                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(histories.prefix(6)) { summary in
                        HStack(alignment: .top, spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 8) {
                                    Text(summary.runName)
                                        .font(.caption.weight(.semibold))
                                    if summary.isActive || (!activeCheckpointPath.isEmpty && URL(fileURLWithPath: activeCheckpointPath).lastPathComponent == summary.checkpointURL.lastPathComponent) {
                                        Text(L10n.choose(simplifiedChinese: "当前激活", english: "Active"))
                                            .font(.caption2.weight(.semibold))
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(Color.green.opacity(0.14), in: Capsule())
                                            .foregroundStyle(.green)
                                    }
                                }
                                Text(summary.metadataURL.deletingLastPathComponent().path)
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(String(format: "%.2f px", summary.bestValidationPixelError))
                                    .font(.caption.weight(.semibold))
                                    .monospacedDigit()
                                Text(L10n.choose(
                                    simplifiedChinese: "\(summary.epochs) 轮 · \(summary.device) · \(DateFormatter.bikeKeypointHistory.string(from: summary.modifiedAt))",
                                    english: "\(summary.epochs) epochs · \(summary.device) · \(DateFormatter.bikeKeypointHistory.string(from: summary.modifiedAt))"
                                ))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            }
                        }
                        .padding(10)
                        .background(Color.white.opacity(0.70), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private enum BikeKeypointAnnotationImageLoader {
    static func loadImage(at url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    static func loadThumbnail(at url: URL, maxPixelSize: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}

private extension DateFormatter {
    static let bikeKeypointHistory: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()
}
