import Foundation
import AVKit
import SwiftUI
#if canImport(VLCKit)
import VLCKit
#endif

/// Represents the supported social platforms for video download links.
enum VideoDownloadPlatform: String, CaseIterable, Identifiable {
    case youtube
    case instagram

    var id: String { rawValue }

    /// Human-readable platform name.
    var displayName: String {
        switch self {
        case .youtube:
            return "YouTube"
        case .instagram:
            return "Instagram"
        }
    }

    /// List of accepted host suffixes for each platform.
    var acceptedHostSuffixes: [String] {
        switch self {
        case .youtube:
            return ["youtube.com", "youtu.be", "m.youtube.com"]
        case .instagram:
            return ["instagram.com", "www.instagram.com"]
        }
    }
}

/// Validation status for a video download request.
enum VideoDownloadValidationResult: Equatable {
    case valid(platform: VideoDownloadPlatform, normalizedURL: URL)
    case emptyInput
    case invalidURL
    case unsupportedPlatform
}

/// Quality presets mapped to yt-dlp format selectors.
enum VideoDownloadQuality: String, CaseIterable, Identifiable {
    case auto
    case p1080
    case p720
    case p480
    case p360

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .auto:
            return L10n.choose(simplifiedChinese: "自动(最佳)", english: "Auto (Best)")
        case .p1080:
            return "1080p"
        case .p720:
            return "720p"
        case .p480:
            return "480p"
        case .p360:
            return "360p"
        }
    }

    /// ytdlp `-f` value.
    var formatSelector: String {
        switch self {
        case .auto:
            // Prefer AVPlayer-friendly progressive MP4 (H.264 + audio) first.
            return "best[ext=mp4][vcodec*=avc1][acodec!=none]/best[ext=mp4][acodec!=none]/best"
        case .p1080:
            return "best[height<=1080][ext=mp4][vcodec*=avc1][acodec!=none]/best[height<=1080][ext=mp4][acodec!=none]/best[height<=1080]"
        case .p720:
            return "best[height<=720][ext=mp4][vcodec*=avc1][acodec!=none]/best[height<=720][ext=mp4][acodec!=none]/best[height<=720]"
        case .p480:
            return "best[height<=480][ext=mp4][vcodec*=avc1][acodec!=none]/best[height<=480][ext=mp4][acodec!=none]/best[height<=480]"
        case .p360:
            return "best[height<=360][ext=mp4][vcodec*=avc1][acodec!=none]/best[height<=360][ext=mp4][acodec!=none]/best[height<=360]"
        }
    }
}

/// Download speed strategy mapped to yt-dlp arguments.
enum VideoDownloadSpeedMode: String, CaseIterable, Identifiable {
    case normal
    case fast

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .normal:
            return L10n.choose(simplifiedChinese: "普通", english: "Normal")
        case .fast:
            return L10n.choose(simplifiedChinese: "高速", english: "Fast")
        }
    }

    /// Additional ytdlp args for speed tuning.
    var ytDlpArguments: [String] {
        switch self {
        case .normal:
            return []
        case .fast:
            // Fragment concurrency accelerates adaptive-stream downloads.
            return ["--concurrent-fragments", "8"]
        }
    }
}

/// Validates and normalizes social media video links for download workflows.
struct VideoDownloadRequestValidator {
    /// Validates a raw link string and returns a platform-aware result.
    /// - Parameter rawText: User input URL text.
    /// - Returns: Validation status with normalized URL when successful.
    func validate(rawText: String) -> VideoDownloadValidationResult {
        let trimmedText = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            return .emptyInput
        }

        guard let parsedURL = URL(string: trimmedText) else {
            return .invalidURL
        }

        guard let host = parsedURL.host?.lowercased() else {
            return .invalidURL
        }

        guard let matchedPlatform = VideoDownloadPlatform.allCases.first(where: { platform in
            platform.acceptedHostSuffixes.contains(where: { suffix in
                host == suffix || host.hasSuffix("." + suffix)
            })
        }) else {
            return .unsupportedPlatform
        }

        return .valid(platform: matchedPlatform, normalizedURL: parsedURL)
    }
}

/// Runtime errors for the downloader execution layer.
enum VideoDownloadExecutionError: Error {
    case downloaderNotInstalled
    case packageManagerNotInstalled
    case installerFailed(reason: String)
    case outputDirectoryUnavailable
    case commandFailed(reason: String)
}

/// Result payload for a completed download job.
struct VideoDownloadResult {
    let outputURL: URL
    let extractedMediaURL: String
}

/// Codec/container details used to explain local playback failures.
struct MediaProbeDetails {
    let container: String
    let videoCodec: String
    let audioCodec: String
    let pixelFormat: String
    let resolution: String
}

/// Formats playback progress and timestamp labels for embedded player controls.
struct VideoPlaybackProgressFormatter {
    /// Converts current and duration seconds into a slider-safe progress value.
    /// - Parameters:
    ///   - currentSeconds: Current playback time in seconds.
    ///   - durationSeconds: Total media duration in seconds.
    /// - Returns: Clamped progress ratio in range `[0, 1]`.
    static func clampedProgress(currentSeconds: Double, durationSeconds: Double) -> Double {
        guard durationSeconds.isFinite, durationSeconds > 0 else {
            return 0
        }
        return min(max(currentSeconds / durationSeconds, 0), 1)
    }

    /// Formats seconds into `MM:SS` or `H:MM:SS` for player timeline labels.
    /// - Parameter seconds: Raw second value.
    /// - Returns: Human-readable timestamp string.
    static func formatTimestamp(seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else {
            return "00:00"
        }

        let wholeSeconds = Int(seconds.rounded(.down))
        let hours = wholeSeconds / 3600
        let minutes = (wholeSeconds % 3600) / 60
        let remainSeconds = wholeSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainSeconds)
        }
        return String(format: "%02d:%02d", minutes, remainSeconds)
    }

    /// Maps a slider progress value back to an absolute seek time.
    /// - Parameters:
    ///   - progress: Slider progress in `[0, 1]`.
    ///   - durationSeconds: Total media duration in seconds.
    /// - Returns: Clamped seek target in seconds.
    static func seekTime(progress: Double, durationSeconds: Double) -> Double {
        guard durationSeconds.isFinite, durationSeconds > 0 else {
            return 0
        }
        return min(max(progress, 0), 1) * durationSeconds
    }
}


/// Playback engine used by the embedded player area.
enum EmbeddedPlaybackEngine: Equatable {
    case libVLC
    case avPlayer
}

/// Selects preferred playback engine based on runtime capability.
struct EmbeddedPlaybackEngineSelector {
    /// Returns preferred engine for the current platform.
    /// - Parameters:
    ///   - isMacOSPlatform: `true` when running on macOS.
    ///   - isLibVLCAvailable: `true` when the app linked VLCKit/libVLC symbols.
    /// - Returns: Selected engine used by playback setup and control UI.
    func preferredEngine(isMacOSPlatform: Bool, isLibVLCAvailable: Bool) -> EmbeddedPlaybackEngine {
        if isMacOSPlatform && isLibVLCAvailable {
            return .libVLC
        }
        return .avPlayer
    }
}

/// Locates bundled open-source decoder binaries packaged inside the app.
struct OpenSourceDecoderRuntimeLocator {
    /// Resolves executable path for a bundled decoder tool.
    /// - Parameters:
    ///   - toolName: Binary name such as `ffmpeg` or `ffprobe`.
    ///   - bundle: Runtime bundle used to locate packaged resources.
    ///   - fallbackSearchRoots: Optional search roots for test and CLI fallback.
    /// - Returns: Executable absolute path when found.
    func resolveBundledToolPath(
        toolName: String,
        bundle: Bundle = .main,
        fallbackSearchRoots: [URL] = []
    ) -> String? {
        let fileManager = FileManager.default
        let bundledCandidates = [
            bundle.resourceURL?.appendingPathComponent("OpenSourceDecoder/bin/\(toolName)").path,
            bundle.resourceURL?.appendingPathComponent("bin/\(toolName)").path,
            bundle.bundleURL.appendingPathComponent("Contents/Resources/OpenSourceDecoder/bin/\(toolName)").path,
            bundle.bundleURL.appendingPathComponent("Contents/Resources/bin/\(toolName)").path
        ]

        for searchRoot in fallbackSearchRoots {
            let rootPath = searchRoot.path
            if !bundledCandidates.contains(rootPath + "/\(toolName)") {
                let candidate = rootPath + "/\(toolName)"
                if fileManager.isExecutableFile(atPath: candidate) {
                    return candidate
                }
            }
            let nestedCandidate = rootPath + "/OpenSourceDecoder/bin/\(toolName)"
            if fileManager.isExecutableFile(atPath: nestedCandidate) {
                return nestedCandidate
            }
        }

        for candidate in bundledCandidates.compactMap({ $0 }) {
            if fileManager.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }

        return nil
    }
}

/// Generates localized explanations when a downloaded media file fails local playback.
struct VideoPlaybackCompatibilityAdvisor {
    /// Builds a user-facing explanation for unsupported local playback.
    /// - Parameter details: Optional codec/container details from ffprobe.
    /// - Returns: Localized reason describing platform decoder limits and fallback guidance.
    func localUnplayableReason(details: MediaProbeDetails?) -> String {
        let genericPrefix = L10n.choose(
            simplifiedChinese: "本地文件不可播：当前播放器无法解码该视频格式。",
            english: "Local file is not playable: current player cannot decode this media format."
        )

        let platformLimit = L10n.choose(
            simplifiedChinese: "应用已内置开源解码链路并在播放器内直连播放，但极少数编码参数组合仍可能超出当前版本支持范围。",
            english: "The app ships with a bundled open-source decoder pipeline for in-app playback, but rare codec/profile combinations can still exceed current support."
        )

        if let details {
            let detailSummary = L10n.choose(
                simplifiedChinese: "检测到容器 \(details.container)，视频 \(details.videoCodec)（\(details.resolution), \(details.pixelFormat)），音频 \(details.audioCodec)。",
                english: "Detected container \(details.container), video \(details.videoCodec) (\(details.resolution), \(details.pixelFormat)), audio \(details.audioCodec)."
            )
            return "\(genericPrefix) \(platformLimit) \(detailSummary)"
        }

        return "\(genericPrefix) \(platformLimit)"
    }
}

/// Executes actual video download jobs using a local downloader command.
struct VideoDownloadExecutor {
    /// Starts a download and returns result details on success.
    /// - Parameter sourceURL: Source video URL.
    /// - Returns: Download result including output file and extracted media URL.
    func download(
        sourceURL: URL,
        quality: VideoDownloadQuality,
        speedMode: VideoDownloadSpeedMode
    ) async throws -> VideoDownloadResult {
        #if os(macOS)
        try await Task.detached(priority: .userInitiated) {
            try downloadOnMacOS(sourceURL: sourceURL, quality: quality, speedMode: speedMode)
        }.value
        #else
        throw VideoDownloadExecutionError.commandFailed(
            reason: L10n.choose(
                simplifiedChinese: "当前平台暂不支持本地下载执行。",
                english: "This platform does not support local download execution yet."
            )
        )
        #endif
    }

    #if os(macOS)
    /// macOS-only download implementation backed by `yt-dlp`/`youtube-dl`.
    private func downloadOnMacOS(
        sourceURL: URL,
        quality: VideoDownloadQuality,
        speedMode: VideoDownloadSpeedMode
    ) throws -> VideoDownloadResult {
        let downloaderCommand: String
        do {
            downloaderCommand = try resolveDownloaderCommand()
        } catch VideoDownloadExecutionError.downloaderNotInstalled {
            try installDownloadTools()
            downloaderCommand = try resolveDownloaderCommand()
        }

        let extractedMediaURL = extractMediaURL(downloaderCommand: downloaderCommand, sourceURL: sourceURL)
        let outputDirectory = try ensureOutputDirectory()
        let outputTemplate = outputDirectory.appendingPathComponent("%(title).120B [%(id)s].%(ext)s").path
        let runtimeArgs = jsRuntimeArguments()
        let primaryArgs = [
            downloaderCommand
        ] + runtimeArgs + speedMode.ytDlpArguments + [
            "--no-playlist",
            "--restrict-filenames",
            "--newline",
            "-f", quality.formatSelector,
            "--print", "after_move:filepath",
            "-o", outputTemplate,
            sourceURL.absoluteString
        ]
        let result: (stdout: String, stderr: String)
        do {
            result = try runCommand(arguments: primaryArgs)
        } catch VideoDownloadExecutionError.commandFailed(let reason)
            where isYouTubeURL(sourceURL) && isBotCheckFailure(reason) {
            let cookieRetryArgs = [
                downloaderCommand
            ] + runtimeArgs + speedMode.ytDlpArguments + [
                "--no-playlist",
                "--cookies-from-browser", "chrome",
                "--restrict-filenames",
                "--newline",
                "-f", quality.formatSelector,
                "--print", "after_move:filepath",
                "-o", outputTemplate,
                sourceURL.absoluteString
            ]
            result = try runCommand(arguments: cookieRetryArgs)
        }

        let outputLines = result.stdout
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if let pathLine = outputLines.last(where: { $0.hasPrefix("/") }) {
            return VideoDownloadResult(
                outputURL: URL(fileURLWithPath: pathLine),
                extractedMediaURL: extractedMediaURL
            )
        }
        return VideoDownloadResult(outputURL: outputDirectory, extractedMediaURL: extractedMediaURL)
    }

    /// Resolves available downloader command on the host system.
    private func resolveDownloaderCommand() throws -> String {
        let candidates = [
            "/opt/homebrew/bin/yt-dlp",
            "/usr/local/bin/yt-dlp",
            "yt-dlp",
            "/opt/homebrew/bin/youtube-dl",
            "/usr/local/bin/youtube-dl",
            "youtube-dl"
        ]
        for candidate in candidates {
            if (try? runCommand(arguments: [candidate, "--version"], mapNonZeroToMissingTool: true)) != nil {
                return candidate
            }
        }
        throw VideoDownloadExecutionError.downloaderNotInstalled
    }

    /// Extracts the resolved direct media URL for status display.
    private func extractMediaURL(downloaderCommand: String, sourceURL: URL) -> String {
        let runtimeArgs = jsRuntimeArguments()
        let primaryArgs = [downloaderCommand] + runtimeArgs + [
            "--no-playlist",
            "--get-url",
            sourceURL.absoluteString
        ]
        if let extraction = try? runCommand(arguments: primaryArgs) {
            let firstMediaURL = extraction.stdout
                .split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first(where: { $0.hasPrefix("http://") || $0.hasPrefix("https://") })
            if let firstMediaURL {
                return firstMediaURL
            }
        }

        if isYouTubeURL(sourceURL),
           let extraction = try? runCommand(arguments: [downloaderCommand] + runtimeArgs + [
            "--no-playlist",
            "--cookies-from-browser", "chrome",
            "--get-url",
            sourceURL.absoluteString
           ]) {
            let firstMediaURL = extraction.stdout
                .split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first(where: { $0.hasPrefix("http://") || $0.hasPrefix("https://") })
            if let firstMediaURL {
                return firstMediaURL
            }
        }

        return "-"
    }

    /// Installs downloader tools via Homebrew when available.
    private func installDownloadTools() throws {
        guard let brewPath = resolveHomebrewPath() else {
            throw VideoDownloadExecutionError.packageManagerNotInstalled
        }

        do {
            _ = try runCommand(arguments: [brewPath, "install", "yt-dlp"])
        } catch VideoDownloadExecutionError.commandFailed(let reason) {
            throw VideoDownloadExecutionError.installerFailed(reason: reason)
        } catch {
            throw VideoDownloadExecutionError.installerFailed(reason: error.localizedDescription)
        }

        // `youtube-dl` is optional fallback and may be unavailable in some taps.
        _ = try? runCommand(arguments: [brewPath, "install", "youtube-dl"])
    }

    /// Resolves Homebrew executable from common installation paths.
    private func resolveHomebrewPath() -> String? {
        let candidates = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew", "brew"]
        for candidate in candidates {
            if candidate == "brew" {
                if (try? runCommand(arguments: ["brew", "--version"])) != nil {
                    return candidate
                }
                continue
            }
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    /// Returns js runtime arguments with absolute paths to avoid GUI PATH mismatch.
    private func jsRuntimeArguments() -> [String] {
        var args: [String] = []
        if FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/deno") {
            args.append("--js-runtimes")
            args.append("deno:/opt/homebrew/bin/deno")
        } else if FileManager.default.isExecutableFile(atPath: "/usr/local/bin/deno") {
            args.append("--js-runtimes")
            args.append("deno:/usr/local/bin/deno")
        }

        if FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/node") {
            args.append("--js-runtimes")
            args.append("node:/opt/homebrew/bin/node")
        } else if FileManager.default.isExecutableFile(atPath: "/usr/local/bin/node") {
            args.append("--js-runtimes")
            args.append("node:/usr/local/bin/node")
        }
        return args
    }

    /// Returns whether the source URL is a YouTube link.
    private func isYouTubeURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host.contains("youtube.com") || host.contains("youtu.be")
    }

    /// Detects YouTube anti-bot errors from yt-dlp output.
    private func isBotCheckFailure(_ reason: String) -> Bool {
        let lowered = reason.lowercased()
        return lowered.contains("sign in to confirm") || lowered.contains("not a bot")
    }

    /// Ensures download output directory exists.
    private func ensureOutputDirectory() throws -> URL {
        guard let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else {
            throw VideoDownloadExecutionError.outputDirectoryUnavailable
        }
        let outputDirectory = downloads.appendingPathComponent("FricuDownloads", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
            return outputDirectory
        } catch {
            throw VideoDownloadExecutionError.commandFailed(
                reason: L10n.choose(
                    simplifiedChinese: "无法创建下载目录：\(error.localizedDescription)",
                    english: "Unable to create output directory: \(error.localizedDescription)"
                )
            )
        }
    }

    /// Runs a command and returns captured stdout/stderr.
    private func runCommand(arguments: [String], mapNonZeroToMissingTool: Bool = false) throws -> (stdout: String, stderr: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = arguments

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
        } catch {
            if mapNonZeroToMissingTool {
                throw VideoDownloadExecutionError.downloaderNotInstalled
            }
            throw VideoDownloadExecutionError.commandFailed(reason: error.localizedDescription)
        }

        process.waitUntilExit()

        let stdoutData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        let stdout = String(decoding: stdoutData, as: UTF8.self)
        let stderr = String(decoding: stderrData, as: UTF8.self)

        guard process.terminationStatus == 0 else {
            if mapNonZeroToMissingTool {
                throw VideoDownloadExecutionError.downloaderNotInstalled
            }
            let reason = [stderr.trimmingCharacters(in: .whitespacesAndNewlines), stdout.trimmingCharacters(in: .whitespacesAndNewlines)]
                .first(where: { !$0.isEmpty }) ?? L10n.choose(
                simplifiedChinese: "下载命令执行失败。",
                english: "Download command failed."
            )
            throw VideoDownloadExecutionError.commandFailed(reason: reason)
        }

        return (stdout, stderr)
    }
    #endif
}

/// A dedicated page for preparing YouTube and Instagram video download jobs.
struct VideoDownloaderPageView: View {
    @State private var sourceURLText = ""
    @State private var selectedQuality: VideoDownloadQuality = .auto
    @State private var selectedSpeedMode: VideoDownloadSpeedMode = .normal
    @State private var isDownloading = false
    @State private var hasDownloadAttempt = false
    @State private var jobStateText = ""
    @State private var extractedMediaURLText = "-"
    @State private var outputLocationText = "-"
    @State private var downloadedVideoURL: URL?
    @State private var playbackPlayer: AVPlayer?
    @State private var playbackCurrentSeconds: Double = 0
    @State private var playbackDurationSeconds: Double = 0
    @State private var isSeekingPlaybackPosition = false
    @State private var playbackTimeObserver: Any?
    @State private var isPlayerExpanded = false
    @State private var usesLibVLCPlayback = false
    #if os(macOS) && canImport(VLCKit)
    @StateObject private var libVLCPlaybackController = LibVLCPlaybackController()
    #endif
    @State private var playbackErrorText = "-"
    @State private var errorAlertMessage = ""
    @State private var showErrorAlert = false
    private let validator = VideoDownloadRequestValidator()
    private let executor = VideoDownloadExecutor()

    private var validationResult: VideoDownloadValidationResult {
        validator.validate(rawText: sourceURLText)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(L10n.choose(simplifiedChinese: "视频下载", english: "Video Downloader"))
                    .font(.largeTitle.bold())

                GroupBox(L10n.choose(simplifiedChinese: "新建下载任务", english: "Create Download Task")) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(L10n.choose(
                            simplifiedChinese: "支持粘贴 YouTube 或 Instagram 视频链接，系统会自动识别平台。",
                            english: "Paste a YouTube or Instagram video link and the platform will be detected automatically."
                        ))
                        .font(.callout)
                        .foregroundStyle(.secondary)

                        TextField(
                            L10n.choose(
                                simplifiedChinese: "输入视频链接（https://...）",
                                english: "Paste video URL (https://...)"
                            ),
                            text: $sourceURLText
                        )
                        .textFieldStyle(.roundedBorder)

                        HStack(spacing: 8) {
                            Text(L10n.choose(simplifiedChinese: "清晰度", english: "Quality"))
                                .font(.subheadline.weight(.semibold))
                            Picker(
                                L10n.choose(simplifiedChinese: "清晰度", english: "Quality"),
                                selection: $selectedQuality
                            ) {
                                ForEach(VideoDownloadQuality.allCases) { quality in
                                    Text(quality.displayName).tag(quality)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .disabled(isDownloading)
                        }

                        HStack(spacing: 8) {
                            Text(L10n.choose(simplifiedChinese: "下载速度", english: "Speed"))
                                .font(.subheadline.weight(.semibold))
                            Picker(
                                L10n.choose(simplifiedChinese: "下载速度", english: "Speed"),
                                selection: $selectedSpeedMode
                            ) {
                                ForEach(VideoDownloadSpeedMode.allCases) { mode in
                                    Text(mode.displayName).tag(mode)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .disabled(isDownloading)
                        }

                        validationMessage

                        HStack(spacing: 12) {
                            Button(
                                isDownloading
                                    ? L10n.choose(simplifiedChinese: "下载中...", english: "Downloading...")
                                    : L10n.choose(simplifiedChinese: "开始下载", english: "Start Download")
                            ) {
                                handleStartDownloadTapped()
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(!isDownloadReady || isDownloading)

                            Button(L10n.choose(simplifiedChinese: "清空", english: "Clear")) {
                                sourceURLText = ""
                                resetJobFeedback()
                            }
                            .buttonStyle(.bordered)
                            .disabled(isDownloading)

                            if isDownloading {
                                ProgressView()
                                    .controlSize(.small)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox(L10n.choose(simplifiedChinese: "状态说明", english: "Status")) {
                    VStack(alignment: .leading, spacing: 8) {
                        statusRow(title: "URL", value: normalizedURLText)
                        statusRow(
                            title: L10n.choose(simplifiedChinese: "平台", english: "Platform"),
                            value: selectedPlatformText
                        )
                        statusRow(
                            title: L10n.choose(simplifiedChinese: "任务状态", english: "Job State"),
                            value: currentJobStateText
                        )
                        statusRow(
                            title: L10n.choose(simplifiedChinese: "已选清晰度", english: "Selected Quality"),
                            value: selectedQuality.displayName
                        )
                        statusRow(
                            title: L10n.choose(simplifiedChinese: "下载速度", english: "Speed Mode"),
                            value: selectedSpeedMode.displayName
                        )
                        statusRow(
                            title: L10n.choose(simplifiedChinese: "视频下载地址", english: "Media URL"),
                            value: extractedMediaURLText
                        )
                        statusRow(
                            title: L10n.choose(simplifiedChinese: "输出路径", english: "Output"),
                            value: outputLocationText
                        )
                        statusRow(
                            title: L10n.choose(simplifiedChinese: "播放内核", english: "Playback Engine"),
                            value: playbackEngineText
                        )
                        statusRow(
                            title: L10n.choose(simplifiedChinese: "播放测试", english: "Playback"),
                            value: playbackStatusText
                        )
                    }
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox(L10n.choose(simplifiedChinese: "播放测试", english: "Playback Test")) {
                    VStack(alignment: .leading, spacing: 10) {
                        if usesLibVLCPlayback, downloadedVideoURL != nil {
                            #if os(macOS) && canImport(VLCKit)
                            EmbeddedLibVLCPlayerView(controller: libVLCPlaybackController)
                                .frame(minHeight: playerMinHeight, maxHeight: playerMaxHeight)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                            HStack(spacing: 8) {
                                Button(L10n.choose(simplifiedChinese: "播放", english: "Play")) {
                                    libVLCPlaybackController.play()
                                }
                                .buttonStyle(.borderedProminent)

                                Button(L10n.choose(simplifiedChinese: "暂停", english: "Pause")) {
                                    libVLCPlaybackController.pause()
                                }
                                .buttonStyle(.bordered)

                                Button(L10n.choose(simplifiedChinese: "重播", english: "Replay")) {
                                    libVLCPlaybackController.replay()
                                }
                                .buttonStyle(.bordered)

                                playerSizeToggleButton
                            }
                            #endif
                        } else if let player = playbackPlayer, downloadedVideoURL != nil {
                            EmbeddedAVPlayerView(player: player)
                                .frame(minHeight: playerMinHeight, maxHeight: playerMaxHeight)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                            VStack(spacing: 6) {
                                Slider(
                                    value: Binding(
                                        get: {
                                            VideoPlaybackProgressFormatter.clampedProgress(
                                                currentSeconds: playbackCurrentSeconds,
                                                durationSeconds: playbackDurationSeconds
                                            )
                                        },
                                        set: { updatedProgress in
                                            playbackCurrentSeconds = VideoPlaybackProgressFormatter.seekTime(
                                                progress: updatedProgress,
                                                durationSeconds: playbackDurationSeconds
                                            )
                                        }
                                    ),
                                    in: 0...1,
                                    onEditingChanged: { isEditing in
                                        isSeekingPlaybackPosition = isEditing
                                        if !isEditing {
                                            seekPlayback(to: playbackCurrentSeconds)
                                        }
                                    }
                                )

                                HStack {
                                    Text(VideoPlaybackProgressFormatter.formatTimestamp(seconds: playbackCurrentSeconds))
                                    Spacer()
                                    Text(VideoPlaybackProgressFormatter.formatTimestamp(seconds: playbackDurationSeconds))
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }

                            HStack(spacing: 8) {
                                Button(L10n.choose(simplifiedChinese: "后退10秒", english: "-10s")) {
                                    seekPlayback(by: -10)
                                }
                                .buttonStyle(.bordered)

                                Button(L10n.choose(simplifiedChinese: "播放", english: "Play")) {
                                    player.play()
                                }
                                .buttonStyle(.borderedProminent)

                                Button(L10n.choose(simplifiedChinese: "暂停", english: "Pause")) {
                                    player.pause()
                                }
                                .buttonStyle(.bordered)

                                Button(L10n.choose(simplifiedChinese: "重播", english: "Replay")) {
                                    seekPlayback(to: 0)
                                    player.play()
                                }
                                .buttonStyle(.bordered)

                                Button(L10n.choose(simplifiedChinese: "前进10秒", english: "+10s")) {
                                    seekPlayback(by: 10)
                                }
                                .buttonStyle(.bordered)

                                playerSizeToggleButton
                            }
                        } else {
                            Text(
                                L10n.choose(
                                    simplifiedChinese: "下载成功后会在这里自动加载播放器。",
                                    english: "The player will appear here automatically after a successful download."
                                )
                            )
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        }

                        if playbackErrorText != "-" {
                            Text(playbackErrorText)
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(20)
        }
        .alert(
            L10n.choose(simplifiedChinese: "下载失败", english: "Download Failed"),
            isPresented: $showErrorAlert
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorAlertMessage)
        }
        .onChange(of: sourceURLText) { _, _ in
            resetJobFeedback()
        }
        .onDisappear {
            removePlaybackTimeObserverIfNeeded()
        }
    }

    private var playerMinHeight: CGFloat {
        isPlayerExpanded ? 320 : 220
    }

    private var playerMaxHeight: CGFloat {
        isPlayerExpanded ? 560 : 360
    }

    @ViewBuilder
    private var playerSizeToggleButton: some View {
        Button(
            isPlayerExpanded
                ? L10n.choose(simplifiedChinese: "最小化", english: "Minimize")
                : L10n.choose(simplifiedChinese: "最大化", english: "Maximize")
        ) {
            isPlayerExpanded.toggle()
        }
        .buttonStyle(.bordered)
    }

    /// Indicates whether the current input is ready for a download action.
    private var isDownloadReady: Bool {
        if case .valid = validationResult {
            return true
        }
        return false
    }

    /// Returns the user-facing job state, including explicit failure feedback after tapping download.
    private var currentJobStateText: String {
        if hasDownloadAttempt, !jobStateText.isEmpty {
            return jobStateText
        }
        return isDownloadReady
            ? L10n.choose(simplifiedChinese: "可执行", english: "Ready")
            : L10n.choose(simplifiedChinese: "等待有效链接", english: "Waiting for valid link")
    }


    /// Returns active playback engine text shown in status panel.
    private var playbackEngineText: String {
        if usesLibVLCPlayback {
            return "libVLC"
        }
        if playbackPlayer != nil {
            return "AVPlayer"
        }
        #if os(macOS) && canImport(VLCKit)
        return "libVLC (ready)"
        #else
        return "AVPlayer"
        #endif
    }

    /// Returns playback status for the status panel.
    private var playbackStatusText: String {
        if usesLibVLCPlayback || playbackPlayer != nil {
            return L10n.choose(simplifiedChinese: "可播放", english: "Ready to play")
        }
        if playbackErrorText != "-" {
            return L10n.choose(simplifiedChinese: "不可播放", english: "Not playable")
        }
        return "-"
    }

    /// Handles start action and executes the actual download workflow.
    private func handleStartDownloadTapped() {
        hasDownloadAttempt = true

        switch validationResult {
        case .valid(let platform, let normalizedURL):
            isDownloading = true
            jobStateText = L10n.choose(
                simplifiedChinese: "下载中...（缺少依赖时会自动安装）",
                english: "Downloading... (auto-installs dependencies if missing)"
            )
            extractedMediaURLText = "-"
            outputLocationText = "-"
            playbackErrorText = "-"
            downloadedVideoURL = nil
            removePlaybackTimeObserverIfNeeded()
            playbackPlayer = nil
            usesLibVLCPlayback = false
            #if os(macOS) && canImport(VLCKit)
            libVLCPlaybackController.stop()
            #endif

            Task {
                do {
                    let result = try await executor.download(
                        sourceURL: normalizedURL,
                        quality: selectedQuality,
                        speedMode: selectedSpeedMode
                    )
                    await MainActor.run {
                        isDownloading = false
                        jobStateText = L10n.choose(
                            simplifiedChinese: "下载完成",
                            english: "Completed"
                        )
                        extractedMediaURLText = result.extractedMediaURL
                        outputLocationText = result.outputURL.path
                        configurePlaybackPlayer(
                            with: result.outputURL,
                            fallbackMediaURLText: result.extractedMediaURL
                        )
                    }
                } catch {
                    await MainActor.run {
                        isDownloading = false
                        jobStateText = L10n.choose(
                            simplifiedChinese: "执行失败：\(humanReadableErrorTitle(error))",
                            english: "Failed: \(humanReadableErrorTitle(error))"
                        )
                        errorAlertMessage = humanReadableErrorMessage(error, platform: platform, url: normalizedURL)
                        showErrorAlert = true
                    }
                }
            }
        case .emptyInput:
            jobStateText = L10n.choose(
                simplifiedChinese: "执行失败：缺少链接",
                english: "Failed: missing URL"
            )
            errorAlertMessage = L10n.choose(
                simplifiedChinese: "请先输入可识别的 YouTube 或 Instagram 链接。",
                english: "Please provide a valid YouTube or Instagram URL first."
            )
            showErrorAlert = true
        case .invalidURL:
            jobStateText = L10n.choose(
                simplifiedChinese: "执行失败：链接格式无效",
                english: "Failed: invalid URL format"
            )
            errorAlertMessage = L10n.choose(
                simplifiedChinese: "链接格式无效，请使用完整链接（例如 https://...）。",
                english: "The URL format is invalid. Please use a full URL such as https://..."
            )
            showErrorAlert = true
        case .unsupportedPlatform:
            jobStateText = L10n.choose(
                simplifiedChinese: "执行失败：平台不支持",
                english: "Failed: unsupported platform"
            )
            errorAlertMessage = L10n.choose(
                simplifiedChinese: "当前仅支持 YouTube / Instagram 链接。",
                english: "Only YouTube / Instagram links are supported."
            )
            showErrorAlert = true
        }
    }

    /// Clears transient job feedback so status reflects the latest input.
    private func resetJobFeedback() {
        hasDownloadAttempt = false
        isDownloading = false
        jobStateText = ""
        extractedMediaURLText = "-"
        outputLocationText = "-"
        downloadedVideoURL = nil
        removePlaybackTimeObserverIfNeeded()
        playbackPlayer = nil
        playbackCurrentSeconds = 0
        playbackDurationSeconds = 0
        usesLibVLCPlayback = false
        #if os(macOS) && canImport(VLCKit)
        libVLCPlaybackController.stop()
        #endif
        playbackErrorText = "-"
        errorAlertMessage = ""
    }

    /// Configures embedded playback for the downloaded local file.
    private func configurePlaybackPlayer(with outputURL: URL, fallbackMediaURLText: String) {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: outputURL.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            removePlaybackTimeObserverIfNeeded()
            playbackPlayer = nil
            usesLibVLCPlayback = false
            #if os(macOS) && canImport(VLCKit)
            libVLCPlaybackController.stop()
            #endif
            downloadedVideoURL = nil
            playbackErrorText = L10n.choose(
                simplifiedChinese: "下载已完成，但未找到可播放文件。",
                english: "Download completed, but no playable file was found."
            )
            return
        }

        downloadedVideoURL = outputURL
        removePlaybackTimeObserverIfNeeded()
        playbackPlayer = nil
        playbackCurrentSeconds = 0
        playbackDurationSeconds = 0
        usesLibVLCPlayback = false
        playbackErrorText = "-"

        #if os(macOS) && canImport(VLCKit)
        let selector = EmbeddedPlaybackEngineSelector()
        let selectedEngine = selector.preferredEngine(isMacOSPlatform: true, isLibVLCAvailable: true)
        if selectedEngine == .libVLC {
            usesLibVLCPlayback = true
            libVLCPlaybackController.load(mediaURL: outputURL)
            libVLCPlaybackController.play()
            return
        }
        #endif

        Task {
            let asset = AVURLAsset(url: outputURL)
            do {
                let isPlayable = try await asset.load(.isPlayable)
                await MainActor.run {
                    guard isPlayable else {
                        Task {
                            let unplayableReason = await buildLocalUnplayableReason(inputURL: outputURL)
                            await MainActor.run {
                                playbackErrorText = "\(unplayableReason)\n" + L10n.choose(
                                    simplifiedChinese: "正在尝试自动转码...",
                                    english: "Trying auto-transcode..."
                                )
                            }

                            if let transcodedURL = await transcodeToPlayableCopy(inputURL: outputURL) {
                                do {
                                    let transcodedAsset = AVURLAsset(url: transcodedURL)
                                    let transcodedPlayable = try await transcodedAsset.load(.isPlayable)
                                    await MainActor.run {
                                        if transcodedPlayable {
                                            downloadedVideoURL = transcodedURL
                                            let player = AVPlayer(url: transcodedURL)
                                            playbackPlayer = player
                                            attachPlaybackTimeObserver(to: player)
                                            playbackErrorText = "\(unplayableReason)\n" + L10n.choose(
                                                simplifiedChinese: "已自动转码为兼容格式进行播放测试（原文件保留）。",
                                                english: "Auto-transcoded to a compatible format for playback test (original file kept)."
                                            )
                                            player.play()
                                            return
                                        }
                                    }
                                } catch {
                                    // Continue to stream fallback below.
                                }
                            }

                            await MainActor.run {
                                if let fallbackURL = URL(string: fallbackMediaURLText),
                                   let scheme = fallbackURL.scheme?.lowercased(),
                                   scheme == "http" || scheme == "https" {
                                    downloadedVideoURL = nil
                                    usesLibVLCPlayback = false
                                    let player = AVPlayer(url: fallbackURL)
                                    playbackPlayer = player
                                    attachPlaybackTimeObserver(to: player)
                                    playbackErrorText = "\(unplayableReason)\n" + L10n.choose(
                                        simplifiedChinese: "已回退为在线流地址播放测试。",
                                        english: "Falling back to stream URL for playback test."
                                    )
                                    player.play()
                                } else {
                                    removePlaybackTimeObserverIfNeeded()
                                    playbackPlayer = nil
                                    usesLibVLCPlayback = false
                                    downloadedVideoURL = nil
                                    playbackErrorText = "\(unplayableReason)\n" + L10n.choose(
                                        simplifiedChinese: "自动转码与流地址回退均失败。",
                                        english: "Both auto-transcode and stream fallback failed."
                                    )
                                }
                            }
                        }
                        return
                    }

                    let player = AVPlayer(url: outputURL)
                    usesLibVLCPlayback = false
                    playbackPlayer = player
                    attachPlaybackTimeObserver(to: player)
                    playbackErrorText = "-"
                    player.play()
                }
            } catch {
                await MainActor.run {
                    removePlaybackTimeObserverIfNeeded()
                    playbackPlayer = nil
                    usesLibVLCPlayback = false
                    downloadedVideoURL = nil
                    playbackErrorText = L10n.choose(
                        simplifiedChinese: "播放器初始化失败：\(error.localizedDescription)",
                        english: "Player initialization failed: \(error.localizedDescription)"
                    )
                }
            }
        }
    }

    /// Attaches periodic playback observation for custom timeline controls.
    /// - Parameter player: Active AVPlayer instance.
    private func attachPlaybackTimeObserver(to player: AVPlayer) {
        removePlaybackTimeObserverIfNeeded()
        let updateInterval = CMTime(seconds: 0.25, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        playbackTimeObserver = player.addPeriodicTimeObserver(forInterval: updateInterval, queue: .main) { currentTime in
            guard !isSeekingPlaybackPosition else {
                return
            }

            let currentSeconds = CMTimeGetSeconds(currentTime)
            if currentSeconds.isFinite {
                playbackCurrentSeconds = max(0, currentSeconds)
            }

            let durationSeconds = CMTimeGetSeconds(player.currentItem?.duration ?? .invalid)
            if durationSeconds.isFinite, durationSeconds > 0 {
                playbackDurationSeconds = durationSeconds
            }
        }
    }

    /// Removes playback observation to prevent duplicated observer callbacks.
    private func removePlaybackTimeObserverIfNeeded() {
        guard let existingObserver = playbackTimeObserver, let player = playbackPlayer else {
            playbackTimeObserver = nil
            return
        }
        player.removeTimeObserver(existingObserver)
        playbackTimeObserver = nil
    }

    /// Seeks playback by a relative offset.
    /// - Parameter offsetSeconds: Relative offset in seconds.
    private func seekPlayback(by offsetSeconds: Double) {
        seekPlayback(to: playbackCurrentSeconds + offsetSeconds)
    }

    /// Seeks playback to an absolute target position.
    /// - Parameter absoluteSeconds: Target playback position in seconds.
    private func seekPlayback(to absoluteSeconds: Double) {
        guard let player = playbackPlayer else {
            return
        }

        let boundedSeconds = min(max(absoluteSeconds, 0), max(playbackDurationSeconds, 0))
        let seekTarget = CMTime(seconds: boundedSeconds, preferredTimescale: 600)
        player.seek(to: seekTarget, toleranceBefore: .zero, toleranceAfter: .zero)
        playbackCurrentSeconds = boundedSeconds
    }

    /// Attempts to transcode the downloaded file into an AVPlayer-friendly MP4 copy via ffmpeg.
    /// Performance assumptions: this is CPU and disk I/O intensive, so execution runs on `.utility` priority.
    /// Potential bottlenecks: high-resolution sources and slow storage can increase end-to-end latency.
    /// Optimization suggestion: expose codec preset and hardware acceleration flags as user-tunable settings.
    private func transcodeToPlayableCopy(inputURL: URL) async -> URL? {
        guard let ffmpegCommand = resolveFFmpegCommand() else { return nil }
        return await Task.detached(priority: .utility) {
            let outputDirectory = inputURL.deletingLastPathComponent()
            let baseName = inputURL.deletingPathExtension().lastPathComponent
            let outputURL = outputDirectory.appendingPathComponent("\(baseName)_playable.mp4")

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [
                ffmpegCommand,
                "-y",
                "-i", inputURL.path,
                "-movflags", "+faststart",
                "-c:v", "libx264",
                "-pix_fmt", "yuv420p",
                "-preset", "veryfast",
                "-crf", "23",
                "-c:a", "aac",
                "-b:a", "192k",
                outputURL.path
            ]
            let outputPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = outputPipe

            do {
                try process.run()
                process.waitUntilExit()
                guard process.terminationStatus == 0 else { return nil }
                return FileManager.default.fileExists(atPath: outputURL.path) ? outputURL : nil
            } catch {
                return nil
            }
        }.value
    }

    /// Builds a human-readable reason for local playback failure using ffprobe diagnostics.
    private func buildLocalUnplayableReason(inputURL: URL) async -> String {
        let advisor = VideoPlaybackCompatibilityAdvisor()
        guard let ffprobeCommand = resolveFFprobeCommand() else {
            return advisor.localUnplayableReason(details: nil) + " " + L10n.choose(
                simplifiedChinese: "（未检测到 ffprobe，无法提供编码详情）",
                english: "(ffprobe not found, codec details unavailable)"
            )
        }

        guard let details = await probeMediaDetails(ffprobeCommand: ffprobeCommand, inputURL: inputURL) else {
            return advisor.localUnplayableReason(details: nil)
        }

        return advisor.localUnplayableReason(details: details)
    }

    /// Probes container and codec information via ffprobe.
    /// Performance assumptions: probe cost is mostly process spawn and metadata parsing overhead.
    /// Potential bottlenecks: network-mounted files can delay probe completion because ffprobe must read headers.
    /// Optimization suggestion: cache probe results keyed by file path and modification date.
    private func probeMediaDetails(ffprobeCommand: String, inputURL: URL) async -> MediaProbeDetails? {
        await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [
                ffprobeCommand,
                "-v", "error",
                "-print_format", "json",
                "-show_streams",
                "-show_format",
                inputURL.path
            ]
            let outputPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = outputPipe

            do {
                try process.run()
                process.waitUntilExit()
                guard process.terminationStatus == 0 else { return nil }
            } catch {
                return nil
            }

            let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
            let format = json["format"] as? [String: Any]
            let container = (format?["format_name"] as? String)?.split(separator: ",").first.map(String.init) ?? "unknown"

            let streams = json["streams"] as? [[String: Any]] ?? []
            let video = streams.first(where: { ($0["codec_type"] as? String) == "video" })
            let audio = streams.first(where: { ($0["codec_type"] as? String) == "audio" })

            let videoCodec = video?["codec_name"] as? String ?? "unknown"
            let audioCodec = audio?["codec_name"] as? String ?? "unknown"
            let pixelFormat = video?["pix_fmt"] as? String ?? "unknown"
            let width = video?["width"] as? Int
            let height = video?["height"] as? Int
            let resolution: String
            if let width, let height {
                resolution = "\(width)x\(height)"
            } else {
                resolution = "unknown"
            }

            return MediaProbeDetails(
                container: container,
                videoCodec: videoCodec,
                audioCodec: audioCodec,
                pixelFormat: pixelFormat,
                resolution: resolution
            )
        }.value
    }

    /// Resolves ffmpeg executable path for optional local transcode fallback.
    private func resolveFFmpegCommand() -> String? {
        let runtimeLocator = OpenSourceDecoderRuntimeLocator()
        if let bundledFFmpeg = runtimeLocator.resolveBundledToolPath(toolName: "ffmpeg") {
            return bundledFFmpeg
        }

        let candidates = ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg"]
        for candidate in candidates {
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    /// Resolves ffprobe executable path for playback diagnostics.
    private func resolveFFprobeCommand() -> String? {
        let runtimeLocator = OpenSourceDecoderRuntimeLocator()
        if let bundledFFprobe = runtimeLocator.resolveBundledToolPath(toolName: "ffprobe") {
            return bundledFFprobe
        }

        let candidates = ["/opt/homebrew/bin/ffprobe", "/usr/local/bin/ffprobe"]
        for candidate in candidates {
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    /// Returns a concise error title for status row.
    private func humanReadableErrorTitle(_ error: Error) -> String {
        guard let executionError = error as? VideoDownloadExecutionError else {
            return L10n.choose(simplifiedChinese: "未知错误", english: "Unknown error")
        }
        switch executionError {
        case .downloaderNotInstalled:
            return L10n.choose(simplifiedChinese: "未检测到下载工具", english: "Downloader tool not found")
        case .packageManagerNotInstalled:
            return L10n.choose(simplifiedChinese: "未检测到 Homebrew", english: "Homebrew not found")
        case .installerFailed:
            return L10n.choose(simplifiedChinese: "自动安装失败", english: "Auto-install failed")
        case .outputDirectoryUnavailable:
            return L10n.choose(simplifiedChinese: "输出目录不可用", english: "Output directory unavailable")
        case .commandFailed:
            return L10n.choose(simplifiedChinese: "下载命令失败", english: "Downloader command failed")
        }
    }

    /// Returns detailed user-facing error message for alert display.
    private func humanReadableErrorMessage(_ error: Error, platform: VideoDownloadPlatform, url: URL) -> String {
        guard let executionError = error as? VideoDownloadExecutionError else {
            return L10n.choose(
                simplifiedChinese: "下载失败：\(error.localizedDescription)",
                english: "Download failed: \(error.localizedDescription)"
            )
        }

        switch executionError {
        case .downloaderNotInstalled:
            return L10n.choose(
                simplifiedChinese: "未检测到 yt-dlp/youtube-dl，请先安装后再试。\n示例：brew install yt-dlp",
                english: "Neither yt-dlp nor youtube-dl is installed. Install one and retry.\nExample: brew install yt-dlp"
            )
        case .packageManagerNotInstalled:
            return L10n.choose(
                simplifiedChinese: "系统未检测到 Homebrew，无法自动安装下载工具。请先安装 Homebrew 后重试。",
                english: "Homebrew was not found, so downloader tools cannot be installed automatically. Install Homebrew and retry."
            )
        case .installerFailed(let reason):
            return L10n.choose(
                simplifiedChinese: "自动安装 yt-dlp 失败。\n原因：\(reason)",
                english: "Automatic installation of yt-dlp failed.\nReason: \(reason)"
            )
        case .outputDirectoryUnavailable:
            return L10n.choose(
                simplifiedChinese: "无法获取系统下载目录，请检查系统权限后重试。",
                english: "Unable to resolve the system Downloads directory. Check app permissions and retry."
            )
        case .commandFailed(let reason):
            if reason.lowercased().contains("sign in to confirm") || reason.lowercased().contains("not a bot") {
                return L10n.choose(
                    simplifiedChinese: "YouTube 要求账号验证（疑似反爬验证）。已自动尝试读取 Chrome 登录态，仍未通过。\n请先在 Chrome 登录 YouTube 后重试，或导入 cookies 再下载。",
                    english: "YouTube requires account verification (anti-bot check). The app already retried with Chrome cookies but it still failed.\nPlease sign in to YouTube in Chrome and retry, or provide cookies for download."
                )
            }
            return L10n.choose(
                simplifiedChinese: "下载 \(platform.displayName) 视频失败。\n链接：\(url.absoluteString)\n原因：\(reason)",
                english: "Failed to download \(platform.displayName) video.\nURL: \(url.absoluteString)\nReason: \(reason)"
            )
        }
    }

    /// Provides a user-facing validation message with contextual styling.
    @ViewBuilder
    private var validationMessage: some View {
        switch validationResult {
        case .valid(let platform, _):
            Label(
                L10n.choose(
                    simplifiedChinese: "链接有效：已识别为 \(platform.displayName)",
                    english: "Valid link: detected as \(platform.displayName)"
                ),
                systemImage: "checkmark.circle.fill"
            )
            .foregroundStyle(.green)
        case .emptyInput:
            Label(
                L10n.choose(simplifiedChinese: "请输入链接", english: "Please enter a link"),
                systemImage: "info.circle"
            )
            .foregroundStyle(.secondary)
        case .invalidURL:
            Label(
                L10n.choose(simplifiedChinese: "链接格式无效", english: "Invalid URL format"),
                systemImage: "xmark.circle.fill"
            )
            .foregroundStyle(.red)
        case .unsupportedPlatform:
            Label(
                L10n.choose(
                    simplifiedChinese: "仅支持 YouTube / Instagram 链接",
                    english: "Only YouTube / Instagram links are supported"
                ),
                systemImage: "exclamationmark.triangle.fill"
            )
            .foregroundStyle(.orange)
        }
    }

    /// Returns the normalized URL text for status display.
    private var normalizedURLText: String {
        switch validationResult {
        case .valid(_, let normalizedURL):
            return normalizedURL.absoluteString
        default:
            return "-"
        }
    }

    /// Returns the selected platform text for status display.
    private var selectedPlatformText: String {
        switch validationResult {
        case .valid(let platform, _):
            return platform.displayName
        default:
            return "-"
        }
    }

    /// Renders a standard status row with label and value.
    /// - Parameters:
    ///   - title: Label shown on the left side.
    ///   - value: Current value shown on the right side.
    /// - Returns: A row view for the status panel.
    @ViewBuilder
    private func statusRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .fontWeight(.semibold)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }
}

#if os(macOS) && canImport(VLCKit)
/// Coordinates libVLC media playback state and imperative controls for SwiftUI.
final class LibVLCPlaybackController: ObservableObject {
    private let mediaPlayer = VLCMediaPlayer()

    /// `true` after a media URL is loaded into libVLC.
    @Published private(set) var hasLoadedMedia = false

    /// Loads media URL and immediately binds it to the current media player instance.
    /// - Parameter mediaURL: Local file URL or remote URL accepted by libVLC.
    func load(mediaURL: URL) {
        mediaPlayer.media = VLCMedia(url: mediaURL)
        hasLoadedMedia = true
    }

    /// Attaches a drawable view used by libVLC video rendering pipeline.
    /// - Parameter drawableView: Cocoa view that hosts libVLC pixel output.
    func attachDrawable(_ drawableView: NSView) {
        if let existingDrawable = mediaPlayer.drawable as? NSView, existingDrawable == drawableView {
            return
        }
        mediaPlayer.drawable = drawableView
    }

    /// Starts or resumes playback.
    func play() {
        mediaPlayer.play()
    }

    /// Pauses playback while keeping current media position.
    func pause() {
        mediaPlayer.pause()
    }

    /// Seeks to the beginning by stopping and starting current media.
    func replay() {
        mediaPlayer.stop()
        mediaPlayer.play()
    }

    /// Stops playback and clears loaded-state flag for UI status updates.
    func stop() {
        mediaPlayer.stop()
        hasLoadedMedia = false
    }
}

/// NSView host that connects SwiftUI layout with libVLC drawable rendering.
private struct EmbeddedLibVLCPlayerView: NSViewRepresentable {
    @ObservedObject var controller: LibVLCPlaybackController

    func makeNSView(context: Context) -> NSView {
        let containerView = NSView()
        controller.attachDrawable(containerView)
        return containerView
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        controller.attachDrawable(nsView)
    }
}
#endif

#if os(macOS)
/// A lightweight AVKit player wrapper that avoids SwiftUI `VideoPlayer` runtime issues.
private struct EmbeddedAVPlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .floating
        view.showsFullScreenToggleButton = true
        view.player = player
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        nsView.player = player
    }
}
#else
/// iOS fallback wrapper for embedded AVPlayer playback.
private struct EmbeddedAVPlayerView: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        return controller
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        uiViewController.player = player
    }
}
#endif
