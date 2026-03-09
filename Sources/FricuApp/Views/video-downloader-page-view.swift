import Foundation
import AVKit
import SwiftUI
import Charts
import CoreImage
import UniformTypeIdentifiers
import Vision
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

/// Display layout mode for embedded playback.
enum VideoFittingMode: String, CaseIterable, Identifiable {
    case fit
    case fill
    case stretch

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fit:
            return L10n.choose(simplifiedChinese: "适配", english: "Fit")
        case .fill:
            return L10n.choose(simplifiedChinese: "填充", english: "Fill")
        case .stretch:
            return L10n.choose(simplifiedChinese: "拉伸", english: "Stretch")
        }
    }

    var symbol: String {
        switch self {
        case .fit:
            return "rectangle.center.inset.filled"
        case .fill:
            return "rectangle.inset.filled.and.person.filled"
        case .stretch:
            return "arrow.up.left.and.arrow.down.right"
        }
    }

    var requiresAVPlayer: Bool {
        self != .fit
    }

    var avVideoGravity: AVLayerVideoGravity {
        switch self {
        case .fit:
            return .resizeAspect
        case .fill:
            return .resizeAspectFill
        case .stretch:
            return .resize
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
        let bundledCandidates: [String] = [
            bundle.resourceURL?.appendingPathComponent("OpenSourceDecoder/bin/\(toolName)").path,
            bundle.resourceURL?.appendingPathComponent("bin/\(toolName)").path,
            bundle.bundleURL.appendingPathComponent("Contents/Resources/OpenSourceDecoder/bin/\(toolName)").path,
            bundle.bundleURL.appendingPathComponent("Contents/Resources/bin/\(toolName)").path
        ].compactMap { $0 }

        for searchRoot in fallbackSearchRoots {
            let rootPath = searchRoot.path
            let candidate = rootPath + "/\(toolName)"
            if !bundledCandidates.contains(candidate) && fileManager.isExecutableFile(atPath: candidate) {
                return candidate
            }
            let nestedCandidate = rootPath + "/OpenSourceDecoder/bin/\(toolName)"
            if fileManager.isExecutableFile(atPath: nestedCandidate) {
                return nestedCandidate
            }
        }

        for candidate in bundledCandidates {
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
enum VideoToolPageMode {
    case downloader
    case fitting
}

private enum VideoImportTarget {
    case primary
    case camera(CyclingCameraView)
}

private enum VideoFittingFlowState {
    case pending
    case running
    case blocked
    case ready
    case done

    var symbol: String {
        switch self {
        case .pending:
            return "circle"
        case .running:
            return "clock.arrow.circlepath"
        case .blocked:
            return "xmark.octagon.fill"
        case .ready:
            return "bolt.circle.fill"
        case .done:
            return "checkmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .pending:
            return .secondary
        case .running:
            return .blue
        case .blocked:
            return .orange
        case .ready:
            return .teal
        case .done:
            return .green
        }
    }
}

private struct VideoCaptureGuidance {
    let fps: Double
    let luma: Double?
    let sharpness: Double?
    let occlusionRatio: Double?
    let distortionRisk: Double?
    let skeletonAlignability: Double?

    var fpsPass: Bool { fps >= 30 }
    var lumaPass: Bool { (luma ?? 0.33) >= 0.28 }
    var sharpnessPass: Bool { (sharpness ?? 0.08) >= 0.055 }
    var occlusionPass: Bool { (occlusionRatio ?? 0.0) <= 0.38 }
    var distortionPass: Bool { (distortionRisk ?? 0.0) <= 0.34 }
    var skeletonAlignPass: Bool { (skeletonAlignability ?? 0.0) >= 0.62 }
    var qualityGatePass: Bool {
        fpsPass &&
        lumaPass &&
        sharpnessPass &&
        occlusionPass &&
        distortionPass &&
        skeletonAlignPass
    }

    var gateFailureTips: [String] {
        var tips: [String] = []
        if !fpsPass {
            tips.append(
                L10n.choose(
                    simplifiedChinese: "帧率过低（建议 60fps，最低 30fps）",
                    english: "Frame rate too low (target 60fps, minimum 30fps)"
                )
            )
        }
        if !lumaPass {
            tips.append(
                L10n.choose(
                    simplifiedChinese: "光照不足（提升前侧光，避免逆光）",
                    english: "Insufficient lighting (add front/side light, avoid backlight)"
                )
            )
        }
        if !sharpnessPass {
            tips.append(
                L10n.choose(
                    simplifiedChinese: "画面模糊（固定机位，提高快门/对焦）",
                    english: "Image is blurry (stabilize camera, increase shutter/focus)"
                )
            )
        }
        if !occlusionPass {
            tips.append(
                L10n.choose(
                    simplifiedChinese: "遮挡过多（保证髋-膝-踝连续可见，避免衣物遮挡）",
                    english: "Too much occlusion (keep hip-knee-ankle visible; avoid clothing occlusion)"
                )
            )
        }
        if !distortionPass {
            tips.append(
                L10n.choose(
                    simplifiedChinese: "画面畸变或机位偏斜较大（避免超广角，保持车身中轴居中且平直）",
                    english: "Distortion/perspective is too strong (avoid ultra-wide lens and keep bike axis centered)"
                )
            )
        }
        if !skeletonAlignPass {
            tips.append(
                L10n.choose(
                    simplifiedChinese: "骨骼对位识别不稳定（穿贴身衣物，建议在髋/膝/踝加标记点）",
                    english: "Skeleton alignment is unstable (wear tighter clothing and add hip/knee/ankle markers)"
                )
            )
        }
        return tips
    }
}

/// Shared video workspace that can run in downloader mode or fitting mode.
struct VideoDownloaderPageView: View {
    private let pageMode: VideoToolPageMode
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
    @State private var playbackTimeObserverOwner: AVPlayer?
    @State private var isPlayerExpanded = false
    @State private var usesLibVLCPlayback = false
    #if os(macOS) && canImport(VLCKit)
    @StateObject private var libVLCPlaybackController = LibVLCPlaybackController()
    #endif
    @State private var playbackErrorText = "-"
    @State private var errorAlertMessage = ""
    @State private var showErrorAlert = false
    @State private var isAnalyzingJointAngles = false
    @State private var jointAngleStatusText = "-"
    @State private var jointAngleResultsByView: [CyclingCameraView: VideoJointAngleAnalysisResult] = [:]
    @State private var jointAngleErrorText = "-"
    @State private var jointAngleMaxSamples = 360
    @State private var autoCaptureDurationSeconds = 30.0
    @State private var autoCaptureStatusText = "-"
    @State private var reportExportStatusText = "-"
    @State private var captureGuidanceByView: [CyclingCameraView: VideoCaptureGuidance] = [:]
    @State private var isRunningFlowComplianceCheck = false
    @State private var flowComplianceChecked = false
    @State private var flowCompliancePassed = false
    @State private var flowComplianceMessage = L10n.choose(
        simplifiedChinese: "待检查：导入视频后执行合规检查。",
        english: "Pending: import video and run compliance check."
    )
    @State private var flowComplianceFailureDetails: [String] = []
    @State private var virtualSaddleDeltaMM = 0.0
    @State private var virtualSetbackDeltaMM = 0.0
    @State private var selectedJointAnalysisView: CyclingCameraView = .side
    @State private var frontCameraVideoURL: URL?
    @State private var sideCameraVideoURL: URL?
    @State private var rearCameraVideoURL: URL?
    @State private var activeVideoImportTarget: VideoImportTarget?
    @AppStorage("fricu.video.player.fitting.mode.v1") private var videoFittingModeRawValue = VideoFittingMode.fit.rawValue
    @AppStorage("fricu.video.player.force.avplayer.v1") private var forceAVPlayerForPlayback = false
    @AppStorage("fricu.video.fitting.pose.model.v1") private var poseEstimationModelRawValue = VideoPoseEstimationModel.auto.rawValue
    private let validator = VideoDownloadRequestValidator()
    private let executor = VideoDownloadExecutor()
    private let jointAngleAnalyzer = VideoJointAngleAnalyzer()
    private let reportExporter = VideoFittingReportExporter()

    init(pageMode: VideoToolPageMode = .downloader) {
        self.pageMode = pageMode
    }

    private var isFittingPage: Bool {
        pageMode == .fitting
    }

    private var validationResult: VideoDownloadValidationResult {
        validator.validate(rawText: sourceURLText)
    }

    private var videoFittingMode: VideoFittingMode {
        get { VideoFittingMode(rawValue: videoFittingModeRawValue) ?? .fit }
        set { videoFittingModeRawValue = newValue.rawValue }
    }

    private var shouldPreferAVPlayerForFitting: Bool {
        guard isFittingPage else { return false }
        return forceAVPlayerForPlayback || videoFittingMode.requiresAVPlayer
    }

    private var activePlaybackFittingMode: VideoFittingMode {
        isFittingPage ? videoFittingMode : .fit
    }

    private var selectedPoseModel: VideoPoseEstimationModel {
        get { VideoPoseEstimationModel(rawValue: poseEstimationModelRawValue) ?? .auto }
        set { poseEstimationModelRawValue = newValue.rawValue }
    }

    private var activeOverlaySample: VideoJointAngleSample? {
        guard let result = selectedJointAngleResult, !result.samples.isEmpty else { return nil }
        return result.samples.min(by: {
            abs($0.timeSeconds - playbackCurrentSeconds) < abs($1.timeSeconds - playbackCurrentSeconds)
        })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(
                    isFittingPage
                        ? L10n.choose(simplifiedChinese: "视频 Fitting", english: "Video Fitting")
                        : L10n.choose(simplifiedChinese: "视频下载", english: "Video Downloader")
                )
                    .font(.largeTitle.bold())

                if !isFittingPage {
                    GroupBox(L10n.choose(simplifiedChinese: "视频下载流程", english: "Video Download Workflow")) {
                        VStack(alignment: .leading, spacing: 12) {
                            fittingFlowCard(
                                step: 1,
                                title: L10n.choose(simplifiedChinese: "导入视频链接", english: "Paste Video URL"),
                                subtitle: downloadLinkStepSubtitle,
                                state: downloadLinkStepState
                            ) {
                                TextField(
                                    L10n.choose(
                                        simplifiedChinese: "输入视频链接（https://...）",
                                        english: "Paste video URL (https://...)"
                                    ),
                                    text: $sourceURLText
                                )
                                .textFieldStyle(.roundedBorder)
                                .disabled(isDownloading)
                            }

                            fittingFlowCard(
                                step: 2,
                                title: L10n.choose(simplifiedChinese: "校验平台与链接", english: "Validate Platform and URL"),
                                subtitle: downloadValidationStepSubtitle,
                                state: downloadValidationStepState
                            ) {
                                VStack(alignment: .leading, spacing: 8) {
                                    validationMessage
                                    statusRow(title: "URL", value: normalizedURLText)
                                    statusRow(
                                        title: L10n.choose(simplifiedChinese: "平台", english: "Platform"),
                                        value: selectedPlatformText
                                    )
                                }
                            }

                            fittingFlowCard(
                                step: 3,
                                title: L10n.choose(simplifiedChinese: "设置下载参数", english: "Set Download Parameters"),
                                subtitle: L10n.choose(
                                    simplifiedChinese: "清晰度与速度可独立选择，默认优先 AVPlayer 兼容格式。",
                                    english: "Quality and speed are configurable; default prioritizes AVPlayer-compatible output."
                                ),
                                state: downloadConfigurationStepState
                            ) {
                                HStack(spacing: 14) {
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
                                }
                            }

                            fittingFlowCard(
                                step: 4,
                                title: L10n.choose(simplifiedChinese: "执行下载", english: "Run Download"),
                                subtitle: currentJobStateText,
                                state: downloadExecutionStepState
                            ) {
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

                            fittingFlowCard(
                                step: 5,
                                title: L10n.choose(simplifiedChinese: "回放与后续处理", english: "Playback and Follow-up"),
                                subtitle: downloadPlaybackStepSubtitle,
                                state: downloadPlaybackStepState
                            ) {
                                VStack(alignment: .leading, spacing: 8) {
                                    statusRow(
                                        title: L10n.choose(simplifiedChinese: "输出文件", english: "Output File"),
                                        value: downloadedVideoURL?.lastPathComponent ?? L10n.choose(simplifiedChinese: "未下载", english: "Not downloaded")
                                    )
                                    statusRow(
                                        title: L10n.choose(simplifiedChinese: "输出路径", english: "Output Path"),
                                        value: outputLocationText
                                    )
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                if isFittingPage {
                    GroupBox(L10n.choose(simplifiedChinese: "本地视频", english: "Local Video")) {
                        VStack(alignment: .leading, spacing: 10) {
                            statusRow(
                                title: L10n.choose(simplifiedChinese: "当前文件", english: "Current File"),
                                value: downloadedVideoURL?.lastPathComponent ?? L10n.choose(simplifiedChinese: "未设置", english: "Not set")
                            )
                            HStack(spacing: 10) {
                                Button(L10n.choose(simplifiedChinese: "选择视频", english: "Choose Video")) {
                                    presentPrimaryFittingVideoImporter()
                                }
                                .buttonStyle(.borderedProminent)

                                Button(L10n.choose(simplifiedChinese: "清除", english: "Clear")) {
                                    resetPlaybackAndAnalysisFeedback()
                                }
                                .buttonStyle(.bordered)
                                .disabled(downloadedVideoURL == nil)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    GroupBox(L10n.choose(simplifiedChinese: "视频 Fitting 流程", english: "Video Fitting Workflow")) {
                        VStack(alignment: .leading, spacing: 12) {
                            fittingFlowCard(
                                step: 1,
                                title: L10n.choose(simplifiedChinese: "导入视频", english: "Import Video"),
                                subtitle: downloadedVideoURL?.lastPathComponent ?? L10n.choose(simplifiedChinese: "先选择本地视频文件", english: "Select a local video first"),
                                state: analyzableLocalVideoURL == nil ? .pending : .done
                            ) {
                                HStack(spacing: 10) {
                                    Button(L10n.choose(simplifiedChinese: "选择视频", english: "Choose Video")) {
                                        presentPrimaryFittingVideoImporter()
                                    }
                                    .buttonStyle(.borderedProminent)

                                    Button(L10n.choose(simplifiedChinese: "清除", english: "Clear")) {
                                        resetPlaybackAndAnalysisFeedback()
                                    }
                                    .buttonStyle(.bordered)
                                    .disabled(downloadedVideoURL == nil)
                                }
                            }

                            fittingFlowCard(
                                step: 2,
                                title: L10n.choose(simplifiedChinese: "检查视频合规（含畸变与骨骼对位）", english: "Compliance Check (Distortion + Skeleton Alignment)"),
                                subtitle: flowComplianceMessage,
                                state: flowComplianceStepState
                            ) {
                                VStack(alignment: .leading, spacing: 8) {
                                    Button(
                                        isRunningFlowComplianceCheck
                                            ? L10n.choose(simplifiedChinese: "检查中...", english: "Checking...")
                                            : L10n.choose(simplifiedChinese: "检查视频合规", english: "Run Compliance Check")
                                    ) {
                                        handleRunFlowComplianceCheckTapped()
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .disabled(isRunningFlowComplianceCheck || !hasAnyCameraSource)

                                    ForEach(supportedCyclingViews) { view in
                                        captureGuidanceRow(for: view)
                                    }

                                    if !flowComplianceFailureDetails.isEmpty {
                                        Text(flowComplianceFailureDetails.joined(separator: "\n\n"))
                                            .font(.caption)
                                            .foregroundStyle(.orange)
                                    }

                                    Text(
                                        L10n.choose(
                                            simplifiedChinese: "标定建议：相机与曲柄平面尽量垂直；前视对准车身中线；后视确保左右髋可见；避免逆光与滚动快门拖影。",
                                            english: "Calibration guide: keep camera orthogonal to crank plane; center bike in front view; keep both hips visible in rear view; avoid backlight and rolling-shutter blur."
                                        )
                                    )
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }
                            }

                            fittingFlowCard(
                                step: 3,
                                title: L10n.choose(simplifiedChinese: "识别骨骼关节", english: "Recognize Skeleton Joints"),
                                subtitle: L10n.choose(simplifiedChinese: "先跑单机位识别，验证关节可稳定跟踪", english: "Run single-view recognition first to confirm stable tracking"),
                                state: skeletonRecognitionStepState
                            ) {
                                HStack(spacing: 10) {
                                    Picker(
                                        L10n.choose(simplifiedChinese: "分析视角", english: "Analysis View"),
                                        selection: $selectedJointAnalysisView
                                    ) {
                                        ForEach(supportedCyclingViews) { view in
                                            Text(view.displayName).tag(view)
                                        }
                                    }
                                    .pickerStyle(.segmented)

                                    Button(
                                        isAnalyzingJointAngles
                                            ? L10n.choose(simplifiedChinese: "识别中...", english: "Recognizing...")
                                            : L10n.choose(simplifiedChinese: "识别当前视角关节", english: "Recognize Selected View")
                                    ) {
                                        handleAnalyzeJointAnglesTapped()
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .disabled(isAnalyzingJointAngles || !canRunPostComplianceSteps || sourceVideoURL(for: selectedJointAnalysisView) == nil)
                                }
                            }

                            fittingFlowCard(
                                step: 4,
                                title: L10n.choose(simplifiedChinese: "分配机位（前 / 侧 / 后）", english: "Assign Views (Front / Side / Rear)"),
                                subtitle: L10n.choose(simplifiedChinese: "每个机位可单独配置视频；未设置时回退当前视频", english: "Each camera view can use a dedicated file; unset views fallback to current video"),
                                state: viewAssignmentStepState
                            ) {
                                VStack(alignment: .leading, spacing: 8) {
                                    jointAnalysisSourceRow(for: .front)
                                    jointAnalysisSourceRow(for: .side)
                                    jointAnalysisSourceRow(for: .rear)
                                }
                            }

                            fittingFlowCard(
                                step: 5,
                                title: L10n.choose(simplifiedChinese: "分析并导出报告 / 视频", english: "Analyze and Export Report / Video"),
                                subtitle: L10n.choose(simplifiedChinese: "通过合规后才能执行最终分析和导出", english: "Final analysis/export is available only after compliance passes"),
                                state: reportStepState
                            ) {
                                VStack(alignment: .leading, spacing: 10) {
                                    Stepper(
                                        L10n.choose(
                                            simplifiedChinese: "长时段采集时长 \(String(format: "%.0f", autoCaptureDurationSeconds))s（20-60s）",
                                            english: "Long capture duration \(String(format: "%.0f", autoCaptureDurationSeconds))s (20-60s)"
                                        ),
                                        value: $autoCaptureDurationSeconds,
                                        in: 20.0...60.0,
                                        step: 5.0
                                    )
                                    .frame(maxWidth: 300, alignment: .leading)

                                    HStack(spacing: 10) {
                                        Button(
                                            isAnalyzingJointAngles
                                                ? L10n.choose(simplifiedChinese: "分析中...", english: "Analyzing...")
                                                : L10n.choose(simplifiedChinese: "分析全部机位", english: "Analyze All Views")
                                        ) {
                                            handleAnalyzeAllCameraViewsTapped()
                                        }
                                        .buttonStyle(.borderedProminent)
                                        .disabled(isAnalyzingJointAngles || !canRunPostComplianceSteps || !hasAnyCameraSource)

                                        Button(
                                            isAnalyzingJointAngles
                                                ? L10n.choose(simplifiedChinese: "处理中...", english: "Running...")
                                                : L10n.choose(simplifiedChinese: "自动检测踩踏并采集+分析", english: "Auto detect pedaling + capture + analyze")
                                        ) {
                                            handleAutoCaptureAndAnalyzeTapped()
                                        }
                                        .buttonStyle(.bordered)
                                        .disabled(isAnalyzingJointAngles || !canRunPostComplianceSteps || !hasAnyCameraSource)
                                    }

                                    HStack(spacing: 10) {
                                        Button(L10n.choose(simplifiedChinese: "导出 PDF 报告", english: "Export PDF Report")) {
                                            handleExportPDFReportTapped()
                                        }
                                        .buttonStyle(.bordered)
                                        .disabled(isAnalyzingJointAngles || !canRunPostComplianceSteps || jointAngleResultsByView.isEmpty)

                                        Button(L10n.choose(simplifiedChinese: "导出报告视频", english: "Export Report Videos")) {
                                            handleExportReportVideosTapped()
                                        }
                                        .buttonStyle(.bordered)
                                        .disabled(isAnalyzingJointAngles || !canRunPostComplianceSteps || !hasAnyCameraSource)
                                    }

                                    if autoCaptureStatusText != "-" {
                                        Text(autoCaptureStatusText)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    if reportExportStatusText != "-" {
                                        Text(reportExportStatusText)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                GroupBox(L10n.choose(simplifiedChinese: "状态说明", english: "Status")) {
                    VStack(alignment: .leading, spacing: 8) {
                        if !isFittingPage {
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
                        }
                        statusRow(
                            title: L10n.choose(simplifiedChinese: "输出路径", english: "Output"),
                            value: outputLocationText
                        )
                        statusRow(
                            title: L10n.choose(simplifiedChinese: "播放内核", english: "Playback Engine"),
                            value: playbackEngineText
                        )
                        if isFittingPage {
                            statusRow(
                                title: L10n.choose(simplifiedChinese: "视频 Fitting", english: "Video Fitting"),
                                value: videoFittingMode.displayName
                            )
                        }
                        statusRow(
                            title: L10n.choose(simplifiedChinese: "播放测试", english: "Playback"),
                            value: playbackStatusText
                        )
                        if isFittingPage {
                            statusRow(
                                title: L10n.choose(simplifiedChinese: "关节角分析", english: "Joint Angle Analysis"),
                                value: jointAngleStatusText
                            )
                        }
                    }
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox(L10n.choose(simplifiedChinese: "播放测试", english: "Playback Test")) {
                    VStack(alignment: .leading, spacing: 10) {
                        if isFittingPage {
                            HStack(spacing: 10) {
                                Label(
                                    L10n.choose(simplifiedChinese: "视频 Fitting", english: "Video Fitting"),
                                    systemImage: videoFittingMode.symbol
                                )
                                .font(.subheadline.weight(.semibold))

                                Picker(
                                    L10n.choose(simplifiedChinese: "视频 Fitting", english: "Video Fitting"),
                                    selection: $videoFittingModeRawValue
                                ) {
                                    ForEach(VideoFittingMode.allCases) { mode in
                                        Label(mode.displayName, systemImage: mode.symbol).tag(mode.rawValue)
                                    }
                                }
                                .appDropdownTheme(width: 180, compact: true)
                                .disabled(isDownloading)

                                Toggle(
                                    isOn: $forceAVPlayerForPlayback
                                ) {
                                    Text(L10n.choose(simplifiedChinese: "强制 AVPlayer", english: "Force AVPlayer"))
                                        .font(.caption)
                                }
                                .toggleStyle(.switch)
                                .disabled(isDownloading)
                            }
                        }

                        if usesLibVLCPlayback, downloadedVideoURL != nil {
                            #if os(macOS) && canImport(VLCKit)
                            ZStack {
                                EmbeddedLibVLCPlayerView(controller: libVLCPlaybackController)
                                if isFittingPage, let sample = activeOverlaySample {
                                    JointWireframeOverlay(sample: sample)
                                        .padding(10)
                                        .allowsHitTesting(false)
                                }
                            }
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
                            ZStack {
                                EmbeddedAVPlayerView(
                                    player: player,
                                    fittingMode: activePlaybackFittingMode
                                )
                                if isFittingPage, let sample = activeOverlaySample {
                                    JointWireframeOverlay(sample: sample)
                                        .padding(10)
                                        .allowsHitTesting(false)
                                }
                            }
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
                                    simplifiedChinese: isFittingPage ? "选择本地视频后会在这里加载播放器。" : "下载成功后会在这里自动加载播放器。",
                                    english: isFittingPage ? "The player appears here after selecting a local video." : "The player will appear here automatically after a successful download."
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

                if isFittingPage {
                    GroupBox(L10n.choose(simplifiedChinese: "视频关节角分析（Beta）", english: "Video Joint Angle Analysis (Beta)")) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            Text(L10n.choose(simplifiedChinese: "分析视角", english: "Analysis View"))
                                .font(.subheadline.weight(.semibold))
                            Picker(
                                L10n.choose(simplifiedChinese: "分析视角", english: "Analysis View"),
                                selection: $selectedJointAnalysisView
                            ) {
                                ForEach(supportedCyclingViews) { view in
                                    Text(view.displayName).tag(view)
                                }
                            }
                            .pickerStyle(.segmented)
                        }

                        HStack(spacing: 10) {
                            Text(L10n.choose(simplifiedChinese: "骨骼模型", english: "Skeleton Model"))
                                .font(.subheadline.weight(.semibold))
                            Picker(
                                L10n.choose(simplifiedChinese: "骨骼模型", english: "Skeleton Model"),
                                selection: $poseEstimationModelRawValue
                            ) {
                                ForEach(VideoPoseEstimationModel.allCases) { model in
                                    Text(model.displayName).tag(model.rawValue)
                                }
                            }
                            .appDropdownTheme(width: 300, compact: true)
                        }

                        Stepper(
                            L10n.choose(
                                simplifiedChinese: "采样帧数上限 \(jointAngleMaxSamples)",
                                english: "Max sampled frames \(jointAngleMaxSamples)"
                            ),
                            value: $jointAngleMaxSamples,
                            in: 120...720,
                            step: 60
                        )
                        .frame(maxWidth: 320, alignment: .leading)

                        jointAnalysisSourceRow(for: .front)
                        jointAnalysisSourceRow(for: .side)
                        jointAnalysisSourceRow(for: .rear)

                        HStack(spacing: 10) {
                            Button(
                                isAnalyzingJointAngles
                                    ? L10n.choose(simplifiedChinese: "分析中...", english: "Analyzing...")
                                    : L10n.choose(simplifiedChinese: "分析当前视角", english: "Analyze Selected View")
                            ) {
                                handleAnalyzeJointAnglesTapped()
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isAnalyzingJointAngles || !canRunPostComplianceSteps || sourceVideoURL(for: selectedJointAnalysisView) == nil)

                            Button(
                                L10n.choose(simplifiedChinese: "分析全部机位", english: "Analyze All Views")
                            ) {
                                handleAnalyzeAllCameraViewsTapped()
                            }
                            .buttonStyle(.bordered)
                            .disabled(isAnalyzingJointAngles || !canRunPostComplianceSteps || !hasAnyCameraSource)
                        }

                        if !hasAnyCameraSource {
                            Text(
                                L10n.choose(
                                    simplifiedChinese: "请先为前/侧/后视角至少选择一个本地视频。未单独设置时会回退使用当前下载视频。",
                                    english: "Choose at least one local video for front/side/rear. If a dedicated source is not set, the current downloaded video is used as fallback."
                                )
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        } else if !canRunPostComplianceSteps {
                            Text(
                                L10n.choose(
                                    simplifiedChinese: "请先完成上方“视频合规检查（畸变/骨骼对位）”，未通过时会拒绝分析流程。",
                                    english: "Run the compliance check above (distortion/skeleton alignment) first. Analysis is blocked until it passes."
                                )
                            )
                            .font(.caption)
                            .foregroundStyle(.orange)
                        }

                        if isAnalyzingJointAngles {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .controlSize(.small)
                                Text(L10n.choose(simplifiedChinese: "正在识别人体彩点并计算关节指标...", english: "Detecting body keypoints and computing fitting metrics..."))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        if let result = selectedJointAngleResult {
                            jointAnalysisResultSection(result: result)
                        } else {
                            Text(
                                L10n.choose(
                                    simplifiedChinese: "当前视角暂无分析结果。",
                                    english: "No analysis result for the selected view yet."
                                )
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }

                        if jointAngleErrorText != "-" {
                            Text(jointAngleErrorText)
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
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
            if !isFittingPage {
                resetJobFeedback()
            }
        }
        .onDisappear {
            removePlaybackTimeObserverIfNeeded()
        }
        .onChange(of: videoFittingModeRawValue) { _, _ in
            if isFittingPage {
                refreshPlaybackForDisplayModeChangeIfNeeded()
            }
        }
        .onChange(of: forceAVPlayerForPlayback) { _, _ in
            if isFittingPage {
                refreshPlaybackForDisplayModeChangeIfNeeded()
            }
        }
        .fileImporter(
            isPresented: isVideoImporterPresented,
            allowedContentTypes: [.movie, .mpeg4Movie, .quickTimeMovie],
            allowsMultipleSelection: false
        ) { result in
            handleVideoImportResult(result)
        }
    }

    private var isVideoImporterPresented: Binding<Bool> {
        Binding(
            get: { activeVideoImportTarget != nil },
            set: { isPresented in
                if !isPresented {
                    activeVideoImportTarget = nil
                }
            }
        )
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
        if shouldPreferAVPlayerForFitting {
            return "AVPlayer"
        }
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

    private var analyzableLocalVideoURL: URL? {
        guard let localURL = downloadedVideoURL else { return nil }
        guard localURL.isFileURL else { return nil }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: localURL.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            return nil
        }
        return localURL
    }

    private var selectedJointAngleResult: VideoJointAngleAnalysisResult? {
        jointAngleResultsByView[selectedJointAnalysisView]
    }

    private var supportedCyclingViews: [CyclingCameraView] {
        [.front, .side, .rear]
    }

    private var hasAnyCameraSource: Bool {
        sourceVideoURL(for: .front) != nil ||
        sourceVideoURL(for: .side) != nil ||
        sourceVideoURL(for: .rear) != nil
    }

    private var hasSourceInput: Bool {
        !sourceURLText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var downloadLinkStepState: VideoFittingFlowState {
        switch validationResult {
        case .emptyInput:
            return .pending
        case .invalidURL, .unsupportedPlatform:
            return .blocked
        case .valid:
            return .done
        }
    }

    private var downloadLinkStepSubtitle: String {
        switch validationResult {
        case .emptyInput:
            return L10n.choose(
                simplifiedChinese: "支持 YouTube / Instagram 链接，粘贴后自动识别平台。",
                english: "Paste a YouTube/Instagram URL and the platform will be detected automatically."
            )
        case .invalidURL:
            return L10n.choose(
                simplifiedChinese: "链接格式无效，请使用完整 https 地址。",
                english: "Invalid URL format. Use a full https link."
            )
        case .unsupportedPlatform:
            return L10n.choose(
                simplifiedChinese: "当前仅支持 YouTube / Instagram。",
                english: "Only YouTube/Instagram are supported."
            )
        case let .valid(platform, normalizedURL):
            return L10n.choose(
                simplifiedChinese: "已识别 \(platform.displayName)：\(normalizedURL.absoluteString)",
                english: "Detected \(platform.displayName): \(normalizedURL.absoluteString)"
            )
        }
    }

    private var downloadValidationStepState: VideoFittingFlowState {
        switch validationResult {
        case .emptyInput:
            return .pending
        case .invalidURL, .unsupportedPlatform:
            return .blocked
        case .valid:
            return .done
        }
    }

    private var downloadValidationStepSubtitle: String {
        switch validationResult {
        case .emptyInput:
            return L10n.choose(
                simplifiedChinese: "等待输入可校验的链接。",
                english: "Waiting for a link to validate."
            )
        case .invalidURL:
            return L10n.choose(
                simplifiedChinese: "校验失败：链接结构不合法。",
                english: "Validation failed: malformed URL."
            )
        case .unsupportedPlatform:
            return L10n.choose(
                simplifiedChinese: "校验失败：平台不在支持范围。",
                english: "Validation failed: platform not supported."
            )
        case let .valid(platform, _):
            return L10n.choose(
                simplifiedChinese: "校验通过：\(platform.displayName) 链接可下载。",
                english: "Validation passed: \(platform.displayName) link is ready for download."
            )
        }
    }

    private var downloadConfigurationStepState: VideoFittingFlowState {
        if isDownloading { return .running }
        if !isDownloadReady {
            return hasSourceInput ? .blocked : .pending
        }
        return hasDownloadAttempt ? .done : .ready
    }

    private var downloadExecutionStepState: VideoFittingFlowState {
        if isDownloading { return .running }
        if downloadedVideoURL != nil { return .done }
        if hasDownloadAttempt { return .blocked }
        return isDownloadReady ? .ready : .pending
    }

    private var downloadPlaybackStepState: VideoFittingFlowState {
        guard downloadedVideoURL != nil else { return .pending }
        if playbackErrorText != "-" { return .blocked }
        return (usesLibVLCPlayback || playbackPlayer != nil) ? .done : .ready
    }

    private var downloadPlaybackStepSubtitle: String {
        if let file = downloadedVideoURL?.lastPathComponent {
            if playbackErrorText != "-" {
                return L10n.choose(
                    simplifiedChinese: "文件 \(file) 已下载，但当前播放器加载失败。",
                    english: "Downloaded \(file), but playback failed on current player."
                )
            }
            return L10n.choose(
                simplifiedChinese: "文件 \(file) 已就绪，可在下方播放器预览或进入 Fitting。",
                english: "File \(file) is ready. Preview below or continue to fitting."
            )
        }
        return L10n.choose(
            simplifiedChinese: "下载成功后会自动进入可回放状态。",
            english: "Playback becomes available after a successful download."
        )
    }

    private var canRunPostComplianceSteps: Bool {
        flowComplianceChecked && flowCompliancePassed
    }

    private var hasAnyJointRecognitionResult: Bool {
        !jointAngleResultsByView.isEmpty
    }

    private var flowComplianceStepState: VideoFittingFlowState {
        if isRunningFlowComplianceCheck { return .running }
        if !hasAnyCameraSource { return .pending }
        if !flowComplianceChecked { return .ready }
        return flowCompliancePassed ? .done : .blocked
    }

    private var skeletonRecognitionStepState: VideoFittingFlowState {
        if isAnalyzingJointAngles { return .running }
        if !canRunPostComplianceSteps { return .blocked }
        return hasAnyJointRecognitionResult ? .done : .ready
    }

    private var viewAssignmentStepState: VideoFittingFlowState {
        if !canRunPostComplianceSteps { return .blocked }
        let explicitCount = supportedCyclingViews.filter { explicitCameraVideoURL(for: $0) != nil }.count
        return explicitCount > 0 ? .done : .ready
    }

    private var reportStepState: VideoFittingFlowState {
        if isAnalyzingJointAngles { return .running }
        if !canRunPostComplianceSteps { return .blocked }
        return hasAnyJointRecognitionResult ? .ready : .pending
    }

    private func preflightQualityGate(
        plans: [(CyclingCameraView, URL)]
    ) async -> (passed: [(CyclingCameraView, URL)], failures: [String]) {
        var passed: [(CyclingCameraView, URL)] = []
        var failures: [String] = []
        for (view, url) in plans {
            let guidance = await evaluateCaptureGuidance(for: url)
            await MainActor.run {
                captureGuidanceByView[view] = guidance
            }
            if guidance.qualityGatePass {
                passed.append((view, url))
            } else {
                failures.append(qualityGateFailureMessage(view: view, guidance: guidance))
            }
        }
        return (passed, failures)
    }

    private func qualityGateFailureMessage(view: CyclingCameraView, guidance: VideoCaptureGuidance) -> String {
        let fpsText = String(format: "%.1f", guidance.fps)
        let lumaText = guidance.luma.map { String(format: "%.2f", $0) } ?? "--"
        let sharpnessText = guidance.sharpness.map { String(format: "%.3f", $0) } ?? "--"
        let occlusionText = guidance.occlusionRatio.map { String(format: "%.0f%%", $0 * 100) } ?? "--"
        let distortionText = guidance.distortionRisk.map { String(format: "%.0f%%", $0 * 100) } ?? "--"
        let alignText = guidance.skeletonAlignability.map { String(format: "%.0f%%", $0 * 100) } ?? "--"
        let tips = guidance.gateFailureTips
        let detailLines = tips.map { "• \($0)" }.joined(separator: "\n")
        return L10n.choose(
            simplifiedChinese: "\(view.displayName) 机位未通过质量门控（FPS \(fpsText) / 亮度 \(lumaText) / 清晰 \(sharpnessText) / 遮挡 \(occlusionText) / 畸变风险 \(distortionText) / 对位可识别 \(alignText)）。\n重拍指令：\n\(detailLines)\n请重拍后再分析。",
            english: "\(view.displayName) failed quality gate (FPS \(fpsText) / Luma \(lumaText) / Sharpness \(sharpnessText) / Occlusion \(occlusionText) / Distortion risk \(distortionText) / Skeleton alignability \(alignText)).\nRetake instructions:\n\(detailLines)\nPlease retake before analysis."
        )
    }

    private func resetFlowComplianceState() {
        isRunningFlowComplianceCheck = false
        flowComplianceChecked = false
        flowCompliancePassed = false
        flowComplianceMessage = L10n.choose(
            simplifiedChinese: "待检查：导入视频后执行合规检查。",
            english: "Pending: import video and run compliance check."
        )
        flowComplianceFailureDetails = []
    }

    private func handleRunFlowComplianceCheckTapped() {
        let plans = supportedCyclingViews.compactMap { view -> (CyclingCameraView, URL)? in
            guard let url = sourceVideoURL(for: view) else { return nil }
            return (view, url)
        }
        guard !plans.isEmpty else {
            flowComplianceChecked = false
            flowCompliancePassed = false
            flowComplianceMessage = L10n.choose(
                simplifiedChinese: "未检测到可用视频，请先导入视频。",
                english: "No usable video found. Import a video first."
            )
            flowComplianceFailureDetails = []
            return
        }

        isRunningFlowComplianceCheck = true
        flowComplianceMessage = L10n.choose(
            simplifiedChinese: "正在检查视频合规（畸变/骨骼对位）...",
            english: "Checking compliance (distortion/skeleton alignment)..."
        )
        flowComplianceFailureDetails = []

        Task {
            let gate = await preflightQualityGate(plans: plans)
            let uniqueFailures = gate.failures.reduce(into: [String]()) { partial, item in
                if !partial.contains(item) {
                    partial.append(item)
                }
            }
            await MainActor.run {
                isRunningFlowComplianceCheck = false
                flowComplianceChecked = true
                flowCompliancePassed = uniqueFailures.isEmpty
                if uniqueFailures.isEmpty {
                    flowComplianceMessage = L10n.choose(
                        simplifiedChinese: "合规通过：可进入后续关节识别与报告流程。",
                        english: "Compliance passed. Continue to joint recognition and reporting."
                    )
                    flowComplianceFailureDetails = []
                    jointAngleErrorText = "-"
                    if jointAngleStatusText == "-" || jointAngleStatusText == L10n.choose(simplifiedChinese: "等待分析", english: "Waiting for analysis") {
                        jointAngleStatusText = L10n.choose(simplifiedChinese: "可分析", english: "Ready")
                    }
                } else {
                    flowComplianceMessage = L10n.choose(
                        simplifiedChinese: "合规未通过：已拒绝后续流程，请先按指令重拍。",
                        english: "Compliance failed: downstream flow is blocked. Retake videos first."
                    )
                    flowComplianceFailureDetails = uniqueFailures
                    jointAngleStatusText = L10n.choose(simplifiedChinese: "需重拍", english: "Retake required")
                    jointAngleErrorText = uniqueFailures.joined(separator: "\n\n")
                }
            }
        }
    }

    private func sourceVideoURL(for view: CyclingCameraView) -> URL? {
        switch view {
        case .front:
            return frontCameraVideoURL ?? analyzableLocalVideoURL
        case .side:
            return sideCameraVideoURL ?? analyzableLocalVideoURL
        case .rear:
            return rearCameraVideoURL ?? analyzableLocalVideoURL
        case .auto:
            return analyzableLocalVideoURL
        }
    }

    private func cameraVideoPathText(for view: CyclingCameraView) -> String {
        if let explicit = {
            switch view {
            case .front: return frontCameraVideoURL
            case .side: return sideCameraVideoURL
            case .rear: return rearCameraVideoURL
            case .auto: return nil
            }
        }() {
            return explicit.lastPathComponent
        }
        if analyzableLocalVideoURL != nil {
            return L10n.choose(simplifiedChinese: "使用当前下载视频", english: "Using current downloaded video")
        }
        return L10n.choose(simplifiedChinese: "未设置", english: "Not set")
    }

    private func resetPlaybackAndAnalysisFeedback() {
        downloadedVideoURL = nil
        outputLocationText = "-"
        extractedMediaURLText = "-"
        jointAngleStatusText = "-"
        jointAngleErrorText = "-"
        jointAngleResultsByView = [:]
        autoCaptureStatusText = "-"
        reportExportStatusText = "-"
        captureGuidanceByView = [:]
        resetFlowComplianceState()
        frontCameraVideoURL = nil
        sideCameraVideoURL = nil
        rearCameraVideoURL = nil
        removePlaybackTimeObserverIfNeeded()
        playbackPlayer = nil
        playbackCurrentSeconds = 0
        playbackDurationSeconds = 0
        usesLibVLCPlayback = false
        #if os(macOS) && canImport(VLCKit)
        libVLCPlaybackController.stop()
        #endif
        playbackErrorText = "-"
    }

    private func handlePrimaryFittingVideoImportResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let selectedURL = urls.first else { return }
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: selectedURL.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
                playbackErrorText = L10n.choose(
                    simplifiedChinese: "所选文件不可用，请重新选择视频文件。",
                    english: "Selected file is unavailable. Choose another video file."
                )
                return
            }
            outputLocationText = selectedURL.path
            configurePlaybackPlayer(with: selectedURL, fallbackMediaURLText: "-")
        case .failure(let error):
            playbackErrorText = L10n.choose(
                simplifiedChinese: "导入视频失败：\(error.localizedDescription)",
                english: "Failed to import video: \(error.localizedDescription)"
            )
        }
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
            jointAngleResultsByView = [:]
            jointAngleErrorText = "-"
            jointAngleStatusText = L10n.choose(simplifiedChinese: "等待分析", english: "Waiting for analysis")
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
        isAnalyzingJointAngles = false
        jobStateText = ""
        jointAngleStatusText = "-"
        jointAngleResultsByView = [:]
        jointAngleErrorText = "-"
        autoCaptureStatusText = "-"
        reportExportStatusText = "-"
        captureGuidanceByView = [:]
        resetFlowComplianceState()
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
        jointAngleStatusText = L10n.choose(simplifiedChinese: "可分析", english: "Ready")
        jointAngleResultsByView = [:]
        jointAngleErrorText = "-"
        autoCaptureStatusText = "-"
        removePlaybackTimeObserverIfNeeded()
        playbackPlayer = nil
        playbackCurrentSeconds = 0
        playbackDurationSeconds = 0
        usesLibVLCPlayback = false
        playbackErrorText = "-"
        resetFlowComplianceState()
        refreshAllCaptureGuidance()

        #if os(macOS) && canImport(VLCKit)
        let selector = EmbeddedPlaybackEngineSelector()
        let selectedEngine = selector.preferredEngine(isMacOSPlatform: true, isLibVLCAvailable: true)
        if selectedEngine == .libVLC && !shouldPreferAVPlayerForFitting {
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
        playbackTimeObserverOwner = player
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
        guard let existingObserver = playbackTimeObserver else {
            playbackTimeObserver = nil
            playbackTimeObserverOwner = nil
            return
        }
        let owner = playbackTimeObserverOwner
        playbackTimeObserver = nil
        playbackTimeObserverOwner = nil
        owner?.removeTimeObserver(existingObserver)
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

    /// Re-configures local playback when fitting policy changes.
    private func refreshPlaybackForDisplayModeChangeIfNeeded() {
        guard !isDownloading else { return }
        guard let localURL = downloadedVideoURL else { return }
        configurePlaybackPlayer(with: localURL, fallbackMediaURLText: extractedMediaURLText)
    }

    private func handleAnalyzeJointAnglesTapped() {
        guard canRunPostComplianceSteps else {
            jointAngleStatusText = L10n.choose(simplifiedChinese: "流程已阻止", english: "Flow blocked")
            jointAngleErrorText = L10n.choose(
                simplifiedChinese: "请先完成并通过“视频合规检查（畸变/骨骼对位）”后再执行识别。",
                english: "Complete and pass the compliance check (distortion/skeleton alignment) before recognition."
            )
            return
        }
        let requestedView = selectedJointAnalysisView
        guard let localURL = sourceVideoURL(for: requestedView) else {
            jointAngleStatusText = L10n.choose(simplifiedChinese: "不可分析", english: "Unavailable")
            jointAngleErrorText = L10n.choose(
                simplifiedChinese: "当前视角没有可分析的本地视频文件。",
                english: "No analyzable local video file is available for the selected view."
            )
            return
        }

        isAnalyzingJointAngles = true
        jointAngleErrorText = "-"
        jointAngleStatusText = L10n.choose(simplifiedChinese: "质量检测中", english: "Quality checking")
        jointAngleResultsByView[requestedView] = nil

        Task {
            let gate = await preflightQualityGate(plans: [(requestedView, localURL)])
            guard gate.passed.first != nil else {
                await MainActor.run {
                    isAnalyzingJointAngles = false
                    jointAngleStatusText = L10n.choose(simplifiedChinese: "需重拍", english: "Retake required")
                    jointAngleErrorText = gate.failures.joined(separator: "\n\n")
                }
                return
            }

            await MainActor.run {
                jointAngleStatusText = L10n.choose(simplifiedChinese: "分析中", english: "Analyzing")
            }
            do {
                let result = try await jointAngleAnalyzer.analyze(
                    videoURL: localURL,
                    maxSamples: jointAngleMaxSamples,
                    requestedView: requestedView,
                    preferredModel: selectedPoseModel
                )
                await MainActor.run {
                    isAnalyzingJointAngles = false
                    jointAngleResultsByView[requestedView] = result
                    jointAngleResultsByView[result.resolvedView] = result
                    jointAngleStatusText = L10n.choose(simplifiedChinese: "已完成", english: "Completed")
                }
            } catch {
                await MainActor.run {
                    isAnalyzingJointAngles = false
                    jointAngleStatusText = L10n.choose(simplifiedChinese: "失败", english: "Failed")
                    jointAngleErrorText = error.localizedDescription
                }
            }
        }
    }

    private func handleAnalyzeAllCameraViewsTapped() {
        guard canRunPostComplianceSteps else {
            jointAngleStatusText = L10n.choose(simplifiedChinese: "流程已阻止", english: "Flow blocked")
            jointAngleErrorText = L10n.choose(
                simplifiedChinese: "请先完成并通过“视频合规检查（畸变/骨骼对位）”后再分析全部机位。",
                english: "Complete and pass the compliance check (distortion/skeleton alignment) before all-view analysis."
            )
            return
        }
        let plans = supportedCyclingViews.compactMap { view -> (CyclingCameraView, URL)? in
            guard let url = sourceVideoURL(for: view) else { return nil }
            return (view, url)
        }
        guard !plans.isEmpty else {
            jointAngleStatusText = L10n.choose(simplifiedChinese: "不可分析", english: "Unavailable")
            jointAngleErrorText = L10n.choose(
                simplifiedChinese: "请先配置至少一个机位视频文件。",
                english: "Configure at least one camera view video first."
            )
            return
        }

        isAnalyzingJointAngles = true
        jointAngleErrorText = "-"
        jointAngleStatusText = L10n.choose(simplifiedChinese: "质量检测中", english: "Quality checking")

        Task {
            let gate = await preflightQualityGate(plans: plans)
            guard !gate.passed.isEmpty else {
                await MainActor.run {
                    isAnalyzingJointAngles = false
                    jointAngleStatusText = L10n.choose(simplifiedChinese: "需重拍", english: "Retake required")
                    jointAngleErrorText = gate.failures.joined(separator: "\n\n")
                }
                return
            }

            await MainActor.run {
                jointAngleStatusText = L10n.choose(simplifiedChinese: "分析中", english: "Analyzing")
            }
            var mergedResults: [CyclingCameraView: VideoJointAngleAnalysisResult] = [:]
            var failures: [String] = gate.failures
            for (view, url) in gate.passed {
                do {
                    let result = try await jointAngleAnalyzer.analyze(
                        videoURL: url,
                        maxSamples: jointAngleMaxSamples,
                        requestedView: view,
                        preferredModel: selectedPoseModel
                    )
                    mergedResults[view] = result
                    mergedResults[result.resolvedView] = result
                } catch {
                    let failLabel = view.displayName
                    failures.append("\(failLabel): \(error.localizedDescription)")
                }
            }

            await MainActor.run {
                isAnalyzingJointAngles = false
                for (view, result) in mergedResults {
                    jointAngleResultsByView[view] = result
                }
                if failures.isEmpty {
                    jointAngleStatusText = L10n.choose(simplifiedChinese: "已完成", english: "Completed")
                    jointAngleErrorText = "-"
                } else if mergedResults.isEmpty {
                    jointAngleStatusText = L10n.choose(simplifiedChinese: "失败", english: "Failed")
                    jointAngleErrorText = failures.joined(separator: "\n")
                } else {
                    jointAngleStatusText = L10n.choose(simplifiedChinese: "部分完成", english: "Partially completed")
                    jointAngleErrorText = failures.joined(separator: "\n")
                }
            }
        }
    }

    private func handleAutoCaptureAndAnalyzeTapped() {
        guard canRunPostComplianceSteps else {
            autoCaptureStatusText = L10n.choose(
                simplifiedChinese: "合规检查未通过，已阻止自动采集+分析流程。",
                english: "Compliance check is not passed. Auto capture/analyze is blocked."
            )
            return
        }
        let plans = supportedCyclingViews.compactMap { view -> (CyclingCameraView, URL)? in
            guard let url = sourceVideoURL(for: view) else { return nil }
            return (view, url)
        }
        guard !plans.isEmpty else {
            autoCaptureStatusText = L10n.choose(
                simplifiedChinese: "没有可用机位视频，无法自动采集。",
                english: "No source video available for auto capture."
            )
            return
        }

        isAnalyzingJointAngles = true
        autoCaptureStatusText = L10n.choose(simplifiedChinese: "质量门控检测中...", english: "Running quality gate...")
        jointAngleErrorText = "-"
        jointAngleStatusText = L10n.choose(simplifiedChinese: "质量检测中", english: "Quality checking")

        Task {
            let gate = await preflightQualityGate(plans: plans)
            guard !gate.passed.isEmpty else {
                await MainActor.run {
                    isAnalyzingJointAngles = false
                    autoCaptureStatusText = L10n.choose(
                        simplifiedChinese: "质量门控未通过，已阻止分析，请按重拍指令重新采集。",
                        english: "Quality gate failed; analysis blocked. Retake videos with the instructions."
                    )
                    jointAngleStatusText = L10n.choose(simplifiedChinese: "需重拍", english: "Retake required")
                    jointAngleErrorText = gate.failures.joined(separator: "\n\n")
                }
                return
            }

            await MainActor.run {
                autoCaptureStatusText = L10n.choose(simplifiedChinese: "自动检测踩踏中...", english: "Detecting pedaling...")
                jointAngleStatusText = L10n.choose(simplifiedChinese: "分析中", english: "Analyzing")
            }
            var results: [CyclingCameraView: VideoJointAngleAnalysisResult] = [:]
            var failures: [String] = gate.failures

            for (view, sourceURL) in gate.passed {
                do {
                    let scoutingResult = try await jointAngleAnalyzer.analyze(
                        videoURL: sourceURL,
                        maxSamples: 120,
                        requestedView: view,
                        preferredModel: selectedPoseModel
                    )
                    let captureWindow = suggestedCaptureWindow(
                        from: scoutingResult,
                        preferredDuration: autoCaptureDurationSeconds
                    )
                    let clipURL = makeAutoCaptureClipURL(view: view)
                    let exportedURL = try await reportExporter.exportClip(
                        sourceURL: sourceURL,
                        startSeconds: captureWindow.start,
                        durationSeconds: captureWindow.duration,
                        outputURL: clipURL
                    )

                    let result = try await jointAngleAnalyzer.analyze(
                        videoURL: exportedURL,
                        maxSamples: jointAngleMaxSamples,
                        requestedView: view,
                        preferredModel: selectedPoseModel
                    )
                    results[view] = result
                    results[result.resolvedView] = result

                    await MainActor.run {
                        setCameraVideoURL(exportedURL, for: view)
                    }
                } catch {
                    failures.append("\(view.displayName): \(error.localizedDescription)")
                }
            }

            await MainActor.run {
                isAnalyzingJointAngles = false
                for (view, result) in results {
                    jointAngleResultsByView[view] = result
                }
                if let selectedURL = sourceVideoURL(for: selectedJointAnalysisView) {
                    configurePlaybackPlayer(with: selectedURL, fallbackMediaURLText: extractedMediaURLText)
                }

                if failures.isEmpty, !results.isEmpty {
                    autoCaptureStatusText = L10n.choose(
                        simplifiedChinese: "自动采集完成：已检测踩踏并生成分析片段，再完成分析。",
                        english: "Auto capture completed: pedaling detected, analysis clips captured, and analysis finished."
                    )
                    jointAngleStatusText = L10n.choose(simplifiedChinese: "已完成", english: "Completed")
                } else if results.isEmpty {
                    autoCaptureStatusText = L10n.choose(
                        simplifiedChinese: "自动采集失败。",
                        english: "Auto capture failed."
                    )
                    jointAngleStatusText = L10n.choose(simplifiedChinese: "失败", english: "Failed")
                } else {
                    autoCaptureStatusText = L10n.choose(
                        simplifiedChinese: "自动采集部分完成，请查看失败机位信息。",
                        english: "Auto capture partially completed. Check failed views."
                    )
                    jointAngleStatusText = L10n.choose(simplifiedChinese: "部分完成", english: "Partially completed")
                }

                jointAngleErrorText = failures.isEmpty ? "-" : failures.joined(separator: "\n")
            }
        }
    }

    private func handleExportPDFReportTapped() {
        guard canRunPostComplianceSteps else {
            reportExportStatusText = L10n.choose(
                simplifiedChinese: "合规检查未通过，已阻止报告导出。",
                english: "Compliance check is not passed. Export is blocked."
            )
            return
        }
        let exportResults = exportedResultsByView()
        guard !exportResults.isEmpty else {
            reportExportStatusText = L10n.choose(
                simplifiedChinese: "暂无可导出的分析结果。",
                english: "No analysis result to export."
            )
            return
        }

        do {
            let outputURL = makeReportOutputURL(suffix: "fitting-report", fileExtension: "pdf")
            try reportExporter.exportPDF(
                resultsByView: exportResults,
                preferredModel: selectedPoseModel,
                outputURL: outputURL
            )
            reportExportStatusText = L10n.choose(
                simplifiedChinese: "PDF 已导出：\(outputURL.lastPathComponent)",
                english: "PDF exported: \(outputURL.lastPathComponent)"
            )
        } catch {
            reportExportStatusText = error.localizedDescription
        }
    }

    private func handleExportReportVideosTapped() {
        guard canRunPostComplianceSteps else {
            reportExportStatusText = L10n.choose(
                simplifiedChinese: "合规检查未通过，已阻止报告视频导出。",
                english: "Compliance check is not passed. Report video export is blocked."
            )
            return
        }
        let plans = supportedCyclingViews.compactMap { view -> (CyclingCameraView, URL)? in
            guard let url = sourceVideoURL(for: view) else { return nil }
            return (view, url)
        }
        guard !plans.isEmpty else {
            reportExportStatusText = L10n.choose(
                simplifiedChinese: "暂无可导出的视频机位。",
                english: "No video view available for export."
            )
            return
        }

        isAnalyzingJointAngles = true
        reportExportStatusText = L10n.choose(simplifiedChinese: "导出视频中...", english: "Exporting videos...")

        Task {
            var failures: [String] = []
            var exportedNames: [String] = []

            for (view, sourceURL) in plans {
                do {
                    let referenceResult: VideoJointAngleAnalysisResult
                    if let existing = jointAngleResultsByView[view] {
                        referenceResult = existing
                    } else {
                        let gate = await preflightQualityGate(plans: [(view, sourceURL)])
                        guard gate.passed.first != nil else {
                            failures.append(contentsOf: gate.failures)
                            continue
                        }
                        referenceResult = try await jointAngleAnalyzer.analyze(
                            videoURL: sourceURL,
                            maxSamples: 120,
                            requestedView: view,
                            preferredModel: selectedPoseModel
                        )
                    }
                    let captureWindow = suggestedCaptureWindow(
                        from: referenceResult,
                        preferredDuration: autoCaptureDurationSeconds
                    )
                    let overlayResult: VideoJointAngleAnalysisResult
                    if analysisResultCoversWindow(referenceResult, start: captureWindow.start, duration: captureWindow.duration) {
                        overlayResult = referenceResult
                    } else {
                        overlayResult = try await jointAngleAnalyzer.analyze(
                            videoURL: sourceURL,
                            maxSamples: jointAngleMaxSamples,
                            requestedView: view,
                            preferredModel: selectedPoseModel
                        )
                    }
                    let outputURL = makeReportOutputURL(
                        suffix: "fitting-\(view.rawValue)",
                        fileExtension: "mov"
                    )
                    _ = try await reportExporter.exportAnnotatedClip(
                        sourceURL: sourceURL,
                        analysisResult: overlayResult,
                        startSeconds: captureWindow.start,
                        durationSeconds: captureWindow.duration,
                        outputURL: outputURL
                    )
                    exportedNames.append(outputURL.lastPathComponent)
                } catch {
                    failures.append("\(view.displayName): \(error.localizedDescription)")
                }
            }

            await MainActor.run {
                isAnalyzingJointAngles = false
                if failures.isEmpty {
                    reportExportStatusText = L10n.choose(
                        simplifiedChinese: "报告视频（骨架+角度烧录）已导出：\(exportedNames.joined(separator: ", "))",
                        english: "Annotated report videos exported: \(exportedNames.joined(separator: ", "))"
                    )
                } else {
                    reportExportStatusText = L10n.choose(
                        simplifiedChinese: "部分导出失败：\(failures.joined(separator: " | "))",
                        english: "Partial export failure: \(failures.joined(separator: " | "))"
                    )
                }
            }
        }
    }

    private func analysisResultCoversWindow(
        _ result: VideoJointAngleAnalysisResult,
        start: Double,
        duration: Double
    ) -> Bool {
        let end = start + duration
        guard result.durationSeconds + 0.35 >= end else { return false }
        guard !result.samples.isEmpty else { return false }
        let first = result.samples.first?.timeSeconds ?? 0
        let last = result.samples.last?.timeSeconds ?? 0
        return first <= start + 0.5 && last + 0.35 >= end
    }

    private func suggestedCaptureWindow(
        from result: VideoJointAngleAnalysisResult,
        preferredDuration: Double
    ) -> (start: Double, duration: Double) {
        let duration = min(max(1.0, preferredDuration), max(1.2, result.durationSeconds))
        if let cycle = result.cadenceCycles.first {
            let start = min(max(0, cycle.startTimeSeconds), max(0, result.durationSeconds - duration))
            return (start, duration)
        }

        if let phaseSample = result.samples.first(where: { $0.crankPhaseDeg != nil }) {
            let start = min(max(0, phaseSample.timeSeconds - 0.8), max(0, result.durationSeconds - duration))
            return (start, duration)
        }

        let start = max(0, (result.durationSeconds - duration) * 0.35)
        return (start, duration)
    }

    private func makeAutoCaptureClipURL(view: CyclingCameraView) -> URL {
        let base = makeReportDirectoryURL()
        let stamp = DateFormatter.fricuCompactTimestamp.string(from: Date())
        return base.appendingPathComponent("auto-capture-\(view.rawValue)-\(stamp).mov")
    }

    private func makeReportOutputURL(suffix: String, fileExtension: String) -> URL {
        let base = makeReportDirectoryURL()
        let stamp = DateFormatter.fricuCompactTimestamp.string(from: Date())
        return base.appendingPathComponent("fricu-\(suffix)-\(stamp).\(fileExtension)")
    }

    private func makeReportDirectoryURL() -> URL {
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Downloads", isDirectory: true)
        let directory = downloads.appendingPathComponent("FricuFittingReports", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func exportedResultsByView() -> [CyclingCameraView: VideoJointAngleAnalysisResult] {
        var output: [CyclingCameraView: VideoJointAngleAnalysisResult] = [:]
        for view in supportedCyclingViews {
            if let result = jointAngleResultsByView[view] {
                output[view] = result
            }
        }
        return output
    }

    private func projectedBDCKneeAngle(
        baseline: Double,
        saddleDeltaMM: Double,
        setbackDeltaMM: Double
    ) -> Double {
        // Approximation for fast virtual fitting preview:
        // +2.5mm saddle height ~ +1deg extension; +1mm setback ~ +0.04deg extension at BDC.
        let saddleDeltaDeg = saddleDeltaMM / 2.5
        let setbackDeltaDeg = setbackDeltaMM * 0.04
        return baseline + saddleDeltaDeg + setbackDeltaDeg
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

    @ViewBuilder
    private func jointAnalysisSourceRow(for view: CyclingCameraView) -> some View {
        HStack(spacing: 8) {
            Text(view.displayName)
                .font(.subheadline.weight(.semibold))
                .frame(width: 64, alignment: .leading)
            Text(cameraVideoPathText(for: view))
                .font(.caption)
                .lineLimit(1)
                .foregroundStyle(.secondary)

            Spacer()

            Button(L10n.choose(simplifiedChinese: "选择视频", english: "Choose")) {
                presentCameraVideoImporter(for: view)
            }
            .buttonStyle(.bordered)
            .disabled(isAnalyzingJointAngles || !canRunPostComplianceSteps)

            Button(L10n.choose(simplifiedChinese: "清除", english: "Clear")) {
                setCameraVideoURL(nil, for: view)
            }
            .buttonStyle(.bordered)
            .disabled(isAnalyzingJointAngles || !canRunPostComplianceSteps || explicitCameraVideoURL(for: view) == nil)
        }
    }

    private func presentPrimaryFittingVideoImporter() {
        activeVideoImportTarget = .primary
    }

    private func presentCameraVideoImporter(for view: CyclingCameraView) {
        switch view {
        case .front:
            activeVideoImportTarget = .camera(.front)
        case .side:
            activeVideoImportTarget = .camera(.side)
        case .rear:
            activeVideoImportTarget = .camera(.rear)
        case .auto:
            break
        }
    }

    private func handleVideoImportResult(_ result: Result<[URL], Error>) {
        let target = activeVideoImportTarget
        activeVideoImportTarget = nil
        guard let target else { return }
        switch target {
        case .primary:
            handlePrimaryFittingVideoImportResult(result)
        case .camera(let view):
            handleCameraVideoImportResult(result, for: view)
        }
    }

    private func handleCameraVideoImportResult(_ result: Result<[URL], Error>, for view: CyclingCameraView) {
        switch result {
        case .success(let urls):
            guard let selectedURL = urls.first else { return }
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: selectedURL.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
                jointAngleErrorText = L10n.choose(
                    simplifiedChinese: "所选文件不可用，请重新选择视频文件。",
                    english: "Selected file is unavailable. Choose another video file."
                )
                return
            }
            setCameraVideoURL(selectedURL, for: view)
            jointAngleErrorText = "-"
            jointAngleStatusText = L10n.choose(simplifiedChinese: "可分析", english: "Ready")
        case .failure(let error):
            jointAngleErrorText = L10n.choose(
                simplifiedChinese: "导入视频失败：\(error.localizedDescription)",
                english: "Failed to import video: \(error.localizedDescription)"
            )
        }
    }

    private func explicitCameraVideoURL(for view: CyclingCameraView) -> URL? {
        switch view {
        case .front:
            return frontCameraVideoURL
        case .side:
            return sideCameraVideoURL
        case .rear:
            return rearCameraVideoURL
        case .auto:
            return nil
        }
    }

    private func setCameraVideoURL(_ url: URL?, for view: CyclingCameraView) {
        switch view {
        case .front:
            frontCameraVideoURL = url
        case .side:
            sideCameraVideoURL = url
        case .rear:
            rearCameraVideoURL = url
        case .auto:
            return
        }
        jointAngleResultsByView[view] = nil
        resetFlowComplianceState()
        if let url {
            Task {
                let guidance = await evaluateCaptureGuidance(for: url)
                await MainActor.run {
                    captureGuidanceByView[view] = guidance
                }
            }
        } else {
            captureGuidanceByView.removeValue(forKey: view)
        }
    }

    @ViewBuilder
    private func jointAnalysisResultSection(result: VideoJointAngleAnalysisResult) -> some View {
        let durationText = String(format: "%.1f", result.durationSeconds)
        let modelText: String = {
            switch result.modelUsed {
            case .mediaPipeBlazePoseGHUM:
                return L10n.choose(simplifiedChinese: "BlazePose GHUM", english: "BlazePose GHUM")
            case .appleVision, .auto:
                if result.used3DAngleFrameCount > 0 {
                    return L10n.choose(
                        simplifiedChinese: "Vision 3D 优先（\(result.used3DAngleFrameCount) 帧）",
                        english: "Vision 3D preferred (\(result.used3DAngleFrameCount) frames)"
                    )
                }
                return L10n.choose(simplifiedChinese: "Vision 2D", english: "Vision 2D")
            }
        }()
        Text(
            L10n.choose(
                simplifiedChinese: "视角: \(result.resolvedView.displayName) · 模型: \(modelText) · 主侧: \(result.dominantSide.displayName) · 有效帧 \(result.analyzedFrameCount)/\(result.targetFrameCount) · 视频时长 \(durationText)s",
                english: "View: \(result.resolvedView.displayName) · model: \(modelText) · dominant side: \(result.dominantSide.displayName) · valid frames \(result.analyzedFrameCount)/\(result.targetFrameCount) · duration \(durationText)s"
            )
        )
        .font(.caption)
        .foregroundStyle(.secondary)

        HStack(spacing: 12) {
            jointAngleStatsCard(
                title: L10n.choose(simplifiedChinese: "膝关节角", english: "Knee Angle"),
                stats: result.kneeStats,
                tint: .orange
            )
            jointAngleStatsCard(
                title: L10n.choose(simplifiedChinese: "髋关节角", english: "Hip Angle"),
                stats: result.hipStats,
                tint: .blue
            )
        }

        fittingRangeDashboard(result: result)
        longDurationStabilitySection(result: result)
        if !result.adjustmentPlan.isEmpty {
            adjustmentDecisionSection(result.adjustmentPlan)
        }

        switch result.resolvedView {
        case .side:
            if !result.sideCheckpoints.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.choose(simplifiedChinese: "侧视角关键点（0/3/9/12 点）", english: "Side View Checkpoints (0/3/9/12)"))
                        .font(.caption.weight(.semibold))
                    HStack(spacing: 8) {
                        ForEach(result.sideCheckpoints) { snapshot in
                            sideCheckpointCard(snapshot)
                        }
                    }
                }
            }
            if let cadenceSummary = result.cadenceSummary {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.choose(simplifiedChinese: "踏频周期分段 + BDC + 座高建议", english: "Cadence Segments + BDC + Saddle Height"))
                        .font(.caption.weight(.semibold))

                    HStack(spacing: 10) {
                        metricCard(
                            title: L10n.choose(simplifiedChinese: "周期数", english: "Cycle Count"),
                            value: "\(cadenceSummary.cycleCount)",
                            tint: .cyan
                        )
                        metricCard(
                            title: L10n.choose(simplifiedChinese: "平均踏频", english: "Avg Cadence"),
                            value: String(format: "%.1f rpm", cadenceSummary.meanCadenceRPM),
                            tint: .cyan
                        )
                        metricCard(
                            title: L10n.choose(simplifiedChinese: "BDC 膝角均值", english: "BDC Knee Mean"),
                            value: cadenceSummary.bdcKneeStats.map { String(format: "%.1f°", $0.mean) } ?? "--",
                            tint: .orange
                        )
                    }

                    if let recommendation = cadenceSummary.saddleHeightRecommendation {
                        let directionColor = saddleAdjustmentColor(recommendation.direction)
                        Text(
                            L10n.choose(
                                simplifiedChinese: "座高建议区间：目标 BDC 膝角 \(String(format: "%.0f-%.0f°", recommendation.targetKneeAngleMinDeg, recommendation.targetKneeAngleMaxDeg))。当前 \(String(format: "%.1f°", recommendation.meanBDCKneeAngleDeg))，建议\(saddleAdjustmentText(recommendation.direction)) \(String(format: "%.0f-%.0f mm", recommendation.suggestedAdjustmentMinMM, recommendation.suggestedAdjustmentMaxMM))。",
                                english: "Saddle recommendation: target BDC knee angle \(String(format: "%.0f-%.0f°", recommendation.targetKneeAngleMinDeg, recommendation.targetKneeAngleMaxDeg)). Current \(String(format: "%.1f°", recommendation.meanBDCKneeAngleDeg)); \(saddleAdjustmentText(recommendation.direction)) by \(String(format: "%.0f-%.0f mm", recommendation.suggestedAdjustmentMinMM, recommendation.suggestedAdjustmentMaxMM))."
                            )
                        )
                        .font(.caption)
                        .foregroundStyle(directionColor)

                        VStack(alignment: .leading, spacing: 6) {
                            Text(L10n.choose(simplifiedChinese: "虚拟调整预览（不改动真实数据）", english: "Virtual Adjustment Preview (no data mutation)"))
                                .font(.caption.weight(.semibold))
                            HStack(spacing: 10) {
                                Text(L10n.choose(simplifiedChinese: "座高 Δ", english: "Saddle Δ"))
                                    .font(.caption)
                                Slider(value: $virtualSaddleDeltaMM, in: -20...20, step: 1)
                                Text(String(format: "%.0f mm", virtualSaddleDeltaMM))
                                    .font(.caption.monospacedDigit())
                                    .frame(width: 68, alignment: .trailing)
                            }
                            HStack(spacing: 10) {
                                Text(L10n.choose(simplifiedChinese: "后移 Δ", english: "Setback Δ"))
                                    .font(.caption)
                                Slider(value: $virtualSetbackDeltaMM, in: -20...20, step: 1)
                                Text(String(format: "%.0f mm", virtualSetbackDeltaMM))
                                    .font(.caption.monospacedDigit())
                                    .frame(width: 68, alignment: .trailing)
                            }
                            let projected = projectedBDCKneeAngle(
                                baseline: recommendation.meanBDCKneeAngleDeg,
                                saddleDeltaMM: virtualSaddleDeltaMM,
                                setbackDeltaMM: virtualSetbackDeltaMM
                            )
                            Text(
                                L10n.choose(
                                    simplifiedChinese: "预测 BDC 膝角：\(String(format: "%.1f°", projected))（目标 \(String(format: "%.0f-%.0f°", recommendation.targetKneeAngleMinDeg, recommendation.targetKneeAngleMaxDeg))）",
                                    english: "Projected BDC knee angle: \(String(format: "%.1f°", projected)) (target \(String(format: "%.0f-%.0f°", recommendation.targetKneeAngleMinDeg, recommendation.targetKneeAngleMaxDeg)))"
                                )
                            )
                            .font(.caption)
                            .foregroundStyle((recommendation.targetKneeAngleMinDeg...recommendation.targetKneeAngleMaxDeg).contains(projected) ? .green : .orange)
                        }
                    }

                    if !result.cadenceCycles.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(result.cadenceCycles.prefix(6))) { cycle in
                                cadenceCycleRow(cycle)
                            }
                        }
                    }
                }
            }
        case .front:
            if let alignment = result.frontAlignment {
                HStack(spacing: 10) {
                    metricCard(
                        title: L10n.choose(simplifiedChinese: "膝-足对位均值", english: "Knee-Foot Mean"),
                        value: String(format: "%.3f", alignment.meanKneeFootOffset),
                        tint: .teal
                    )
                    metricCard(
                        title: L10n.choose(simplifiedChinese: "最大偏移", english: "Max Offset"),
                        value: String(format: "%.3f", alignment.maxKneeFootOffset),
                        tint: .teal
                    )
                    metricCard(
                        title: L10n.choose(simplifiedChinese: "左右不对称", english: "Asymmetry"),
                        value: String(format: "%.3f", alignment.kneeTrackAsymmetry),
                        tint: .mint
                    )
                    metricCard(
                        title: L10n.choose(simplifiedChinese: "膝宽/髋宽", english: "Knee/Hip Width"),
                        value: String(format: "%.3f", alignment.hipKneeWidthRatio),
                        tint: .indigo
                    )
                }
            }
            if let trajectory = result.frontTrajectory {
                HStack(spacing: 10) {
                    metricCard(
                        title: L10n.choose(simplifiedChinese: "膝轨迹宽度", english: "Knee Path Width"),
                        value: String(format: "%.3f", trajectory.kneeTrajectorySpanNorm),
                        tint: trajectory.kneeTrajectorySpanNorm <= 0.36 ? .green : .orange
                    )
                    metricCard(
                        title: L10n.choose(simplifiedChinese: "踝轨迹宽度", english: "Ankle Path Width"),
                        value: String(format: "%.3f", trajectory.ankleTrajectorySpanNorm),
                        tint: trajectory.ankleTrajectorySpanNorm <= 0.28 ? .green : .orange
                    )
                    metricCard(
                        title: L10n.choose(simplifiedChinese: "足尖轨迹宽度", english: "Toe Path Width"),
                        value: trajectory.toeTrajectorySpanNorm.map { String(format: "%.3f", $0) } ?? "--",
                        tint: (trajectory.toeTrajectorySpanNorm ?? 0.0) <= 0.34 ? .green : .orange
                    )
                    metricCard(
                        title: L10n.choose(simplifiedChinese: "膝踝合理占比", english: "Knee-Ankle In-Range"),
                        value: String(format: "%.0f%%", trajectory.kneeOverAnkleInRangeRatio * 100.0),
                        tint: trajectory.kneeOverAnkleInRangeRatio >= 0.7 ? .green : .orange
                    )
                }
                Text(frontTrajectorySummary(trajectory))
                    .font(.caption)
                    .foregroundStyle(frontTrajectoryStatusColor(trajectory))
            }
            if let assessment = result.frontAutoAssessment {
                frontAutoAssessmentSection(assessment)
            }
        case .rear:
            HStack(spacing: 10) {
                if let pelvic = result.rearPelvic {
                    metricCard(
                        title: L10n.choose(simplifiedChinese: "平均盆骨倾斜", english: "Mean Pelvic Tilt"),
                        value: String(format: "%.1f°", pelvic.meanPelvicTiltDeg),
                        tint: .purple
                    )
                    metricCard(
                        title: L10n.choose(simplifiedChinese: "最大倾斜", english: "Max Pelvic Tilt"),
                        value: String(format: "%.1f°", pelvic.maxPelvicTiltDeg),
                        tint: .purple
                    )
                    metricCard(
                        title: L10n.choose(simplifiedChinese: "左髋下沉占比", english: "Left Hip Drop Ratio"),
                        value: String(format: "%.0f%%", pelvic.leftHipDropRatio * 100),
                        tint: .pink
                    )
                }
                if let coordination = result.rearCoordination {
                    metricCard(
                        title: L10n.choose(simplifiedChinese: "左右膝横向相关", english: "Knee Lateral Corr."),
                        value: String(format: "%.2f", coordination.kneeLateralCorrelation),
                        tint: .brown
                    )
                    metricCard(
                        title: L10n.choose(simplifiedChinese: "顺拐判定", english: "Shun-Guai"),
                        value: coordination.isShunGuaiSuspected
                            ? L10n.choose(simplifiedChinese: "疑似", english: "Suspected")
                            : L10n.choose(simplifiedChinese: "未见明显异常", english: "Not obvious"),
                        tint: coordination.isShunGuaiSuspected ? .red : .green
                    )
                }
            }
            if let stability = result.rearStability {
                HStack(spacing: 10) {
                    metricCard(
                        title: L10n.choose(simplifiedChinese: "重心平均漂移", english: "Mean CoM Shift"),
                        value: String(format: "%.3f", stability.meanCenterShiftNorm),
                        tint: stability.meanCenterShiftNorm <= 0.10 ? .green : .orange
                    )
                    metricCard(
                        title: L10n.choose(simplifiedChinese: "重心最大漂移", english: "Max CoM Shift"),
                        value: String(format: "%.3f", stability.maxCenterShiftNorm),
                        tint: stability.maxCenterShiftNorm <= 0.22 ? .green : .orange
                    )
                    metricCard(
                        title: L10n.choose(simplifiedChinese: "重心偏置", english: "CoM Lateral Bias"),
                        value: String(format: "%.3f", stability.lateralBias),
                        tint: abs(stability.lateralBias) <= 0.05 ? .green : .orange
                    )
                }
                Text(rearStabilitySummary(stability: stability, pelvic: result.rearPelvic, coordination: result.rearCoordination))
                    .font(.caption)
                    .foregroundStyle(rearStabilityStatusColor(stability: stability, pelvic: result.rearPelvic, coordination: result.rearCoordination))
            }
            if let assessment = result.rearAutoAssessment {
                rearAutoAssessmentSection(assessment)
            }
        case .auto:
            EmptyView()
        }

        if !result.fittingHints.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.choose(simplifiedChinese: "精度提示", english: "Precision Hints"))
                    .font(.caption.weight(.semibold))
                ForEach(Array(result.fittingHints.enumerated()), id: \.offset) { _, hint in
                    Text("• \(hint)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }

        Chart {
            ForEach(result.samples) { sample in
                if let knee = sample.kneeAngleDeg {
                    LineMark(
                        x: .value("Time", sample.timeSeconds),
                        y: .value("Knee", knee)
                    )
                    .foregroundStyle(.orange)
                }
                if let hip = sample.hipAngleDeg {
                    LineMark(
                        x: .value("Time", sample.timeSeconds),
                        y: .value("Hip", hip)
                    )
                    .foregroundStyle(.blue)
                }
            }
        }
        .frame(height: 210)
        .chartYAxis {
            AxisMarks(position: .trailing)
        }
        .chartXAxisLabel(L10n.choose(simplifiedChinese: "时间(s)", english: "Time (s)"))
        .chartYAxisLabel(L10n.choose(simplifiedChinese: "角度(°)", english: "Angle (°)"))
        .chartLegend(position: .bottom, spacing: 12)
    }

    @ViewBuilder
    private func adjustmentDecisionSection(_ steps: [BikeFitAdjustmentStep]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.choose(simplifiedChinese: "AI 调整顺序（先改什么）", english: "AI Adjustment Sequence"))
                .font(.caption.weight(.semibold))
            ForEach(steps.prefix(4)) { step in
                adjustmentDecisionCard(step)
            }
        }
    }

    @ViewBuilder
    private func adjustmentDecisionCard(_ step: BikeFitAdjustmentStep) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("#\(step.priority)")
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(step.title)
                    .font(.caption.weight(.semibold))
                Spacer()
                Text(String(format: L10n.choose(simplifiedChinese: "影响 %.0f", english: "Impact %.0f"), step.impactScore))
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(adjustmentImpactColor(step.impactScore).opacity(0.14), in: Capsule())
                    .foregroundStyle(adjustmentImpactColor(step.impactScore))
            }
            Text(step.rationale)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(
                L10n.choose(
                    simplifiedChinese: "每步限制：\(step.maxAdjustmentPerStep)",
                    english: "Step limit: \(step.maxAdjustmentPerStep)"
                )
            )
            .font(.caption2)
            Text(
                L10n.choose(
                    simplifiedChinese: "复测条件：\(step.retestCondition)",
                    english: "Retest: \(step.retestCondition)"
                )
            )
            .font(.caption2)
            .foregroundStyle(.secondary)
            Text(
                L10n.choose(
                    simplifiedChinese: "达标：\(step.successCriteria)",
                    english: "Success: \(step.successCriteria)"
                )
            )
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func frontAutoAssessmentSection(_ assessment: FrontTrajectoryAssessment) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(L10n.choose(simplifiedChinese: "前视自动判定（膝/踝/足尖轨迹）", english: "Front Auto Assessment"))
                    .font(.caption.weight(.semibold))
                Spacer()
                Text(riskBadgeText(level: assessment.riskLevel, score: assessment.riskScore))
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(riskColor(assessment.riskLevel).opacity(0.14), in: Capsule())
                    .foregroundStyle(riskColor(assessment.riskLevel))
            }

            assessmentLine(
                label: L10n.choose(simplifiedChinese: "膝轨迹", english: "Knee Path"),
                value: String(format: "%.3f", assessment.kneeSpanNorm),
                rangeText: String(format: "%.2f-%.2f", assessment.kneeRangeMinNorm, assessment.kneeRangeMaxNorm),
                pass: assessment.kneeSpanInRange
            )
            assessmentLine(
                label: L10n.choose(simplifiedChinese: "踝轨迹", english: "Ankle Path"),
                value: String(format: "%.3f", assessment.ankleSpanNorm),
                rangeText: String(format: "%.2f-%.2f", assessment.ankleRangeMinNorm, assessment.ankleRangeMaxNorm),
                pass: assessment.ankleSpanInRange
            )
            if let toe = assessment.toeSpanNorm, let toePass = assessment.toeSpanInRange {
                assessmentLine(
                    label: L10n.choose(simplifiedChinese: "足尖轨迹", english: "Toe Path"),
                    value: String(format: "%.3f", toe),
                    rangeText: String(format: "%.2f-%.2f", assessment.toeRangeMinNorm, assessment.toeRangeMaxNorm),
                    pass: toePass
                )
            }
            assessmentLine(
                label: L10n.choose(simplifiedChinese: "膝踝合理占比", english: "Knee-Ankle Ratio"),
                value: String(format: "%.0f%%", assessment.inRangeRatio * 100),
                rangeText: L10n.choose(
                    simplifiedChinese: ">= \(String(format: "%.0f%%", assessment.inRangeRatioMin * 100))",
                    english: ">= \(String(format: "%.0f%%", assessment.inRangeRatioMin * 100))"
                ),
                pass: assessment.inRangeRatioPass
            )
            if let asym = assessment.kneeTrackAsymmetry, let pass = assessment.asymmetryPass {
                assessmentLine(
                    label: L10n.choose(simplifiedChinese: "左右不对称", english: "Asymmetry"),
                    value: String(format: "%.3f", asym),
                    rangeText: String(format: "<= %.2f", assessment.asymmetryMax),
                    pass: pass
                )
            }

            if !assessment.flags.isEmpty {
                Text("• \(assessment.flags.joined(separator: "；"))")
                    .font(.caption2)
                    .foregroundStyle(riskColor(assessment.riskLevel))
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func rearAutoAssessmentSection(_ assessment: RearStabilityAssessment) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(L10n.choose(simplifiedChinese: "后视自动判定（盆骨/重心/顺拐风险）", english: "Rear Auto Assessment"))
                    .font(.caption.weight(.semibold))
                Spacer()
                Text(riskBadgeText(level: assessment.riskLevel, score: assessment.riskScore))
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(riskColor(assessment.riskLevel).opacity(0.14), in: Capsule())
                    .foregroundStyle(riskColor(assessment.riskLevel))
            }

            if let meanPelvic = assessment.meanPelvicTiltDeg, let pass = assessment.meanPelvicPass {
                assessmentLine(
                    label: L10n.choose(simplifiedChinese: "平均盆骨倾斜", english: "Mean Pelvic Tilt"),
                    value: String(format: "%.1f°", meanPelvic),
                    rangeText: String(format: "abs <= %.1f°", assessment.meanPelvicTiltThresholdDeg),
                    pass: pass
                )
            }
            if let maxPelvic = assessment.maxPelvicTiltDeg, let pass = assessment.maxPelvicPass {
                assessmentLine(
                    label: L10n.choose(simplifiedChinese: "最大盆骨倾斜", english: "Max Pelvic Tilt"),
                    value: String(format: "%.1f°", maxPelvic),
                    rangeText: String(format: "<= %.1f°", assessment.maxPelvicTiltThresholdDeg),
                    pass: pass
                )
            }
            assessmentLine(
                label: L10n.choose(simplifiedChinese: "重心平均漂移", english: "Mean CoM Shift"),
                value: String(format: "%.3f", assessment.meanCenterShiftNorm),
                rangeText: String(format: "<= %.2f", assessment.meanCenterShiftThreshold),
                pass: assessment.meanCenterShiftPass
            )
            assessmentLine(
                label: L10n.choose(simplifiedChinese: "重心峰值漂移", english: "Max CoM Shift"),
                value: String(format: "%.3f", assessment.maxCenterShiftNorm),
                rangeText: String(format: "<= %.2f", assessment.maxCenterShiftThreshold),
                pass: assessment.maxCenterShiftPass
            )
            assessmentLine(
                label: L10n.choose(simplifiedChinese: "重心偏置", english: "Lateral Bias"),
                value: String(format: "%.3f", assessment.lateralBias),
                rangeText: String(format: "abs <= %.2f", assessment.lateralBiasThreshold),
                pass: assessment.lateralBiasPass
            )
            if let corr = assessment.kneeLateralCorrelation {
                assessmentLine(
                    label: L10n.choose(simplifiedChinese: "顺拐相关系数", english: "Shun-guai Corr."),
                    value: String(format: "%.2f", corr),
                    rangeText: String(format: "< %.2f", assessment.shunGuaiCorrelationThreshold),
                    pass: assessment.shunGuaiPass
                )
            }

            if !assessment.flags.isEmpty {
                Text("• \(assessment.flags.joined(separator: "；"))")
                    .font(.caption2)
                    .foregroundStyle(riskColor(assessment.riskLevel))
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func assessmentLine(label: String, value: String, rangeText: String, pass: Bool) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption2)
            Text(value)
                .font(.caption2.monospacedDigit())
            Text("(\(rangeText))")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
            Text(pass ? "OK" : "OUT")
                .font(.caption2.monospacedDigit().weight(.semibold))
                .foregroundStyle(pass ? .green : .red)
        }
    }

    private func riskBadgeText(level: FittingRiskLevel, score: Double) -> String {
        let levelText: String = {
            switch level {
            case .low:
                return L10n.choose(simplifiedChinese: "低风险", english: "Low")
            case .moderate:
                return L10n.choose(simplifiedChinese: "中风险", english: "Moderate")
            case .high:
                return L10n.choose(simplifiedChinese: "高风险", english: "High")
            }
        }()
        return "\(levelText) \(String(format: "%.0f", score))"
    }

    private func riskColor(_ level: FittingRiskLevel) -> Color {
        switch level {
        case .low:
            return .green
        case .moderate:
            return .orange
        case .high:
            return .red
        }
    }

    @ViewBuilder
    private func longDurationStabilitySection(result: VideoJointAngleAnalysisResult) -> some View {
        if let long = result.longDurationStability {
            let bdcDelta = valueDelta(late: long.lateBDCKneeAngleDeg, early: long.earlyBDCKneeAngleDeg)
            let kneeFatigueDelta = valueDelta(late: long.lateKneeAngleDeg, early: long.earlyKneeAngleDeg)
            let hipFatigueDelta = valueDelta(late: long.lateHipAngleDeg, early: long.earlyHipAngleDeg)
            let windowValue = L10n.choose(
                simplifiedChinese: String(format: "%.0fs · %d 周期", long.analyzedDurationSeconds, long.cycleCount),
                english: String(format: "%.0fs · %d cycles", long.analyzedDurationSeconds, long.cycleCount)
            )

            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.choose(simplifiedChinese: "长时段稳定性（20-60 秒）", english: "Long-duration Stability (20-60s)"))
                    .font(.caption.weight(.semibold))

                HStack(spacing: 10) {
                    metricCard(
                        title: L10n.choose(simplifiedChinese: "分析窗口", english: "Window"),
                        value: windowValue,
                        tint: long.cycleCount >= 12 ? .green : .orange
                    )
                    metricCard(
                        title: L10n.choose(simplifiedChinese: "BDC 均值", english: "BDC Mean"),
                        value: long.meanBDCKneeAngleDeg.map { String(format: "%.1f°", $0) } ?? "--",
                        tint: .orange
                    )
                    metricCard(
                        title: L10n.choose(simplifiedChinese: "BDC 漂移", english: "BDC Drift"),
                        value: long.bdcKneeDriftDegPerMin.map { String(format: "%+.2f°/min", $0) } ?? "--",
                        tint: (abs(long.bdcKneeDriftDegPerMin ?? 0) <= 1.6) ? .green : .orange
                    )
                    metricCard(
                        title: L10n.choose(simplifiedChinese: "相位漂移", english: "Phase Drift"),
                        value: long.phaseDriftDegPerMin.map { String(format: "%+.2f°/min", $0) } ?? "--",
                        tint: (abs(long.phaseDriftDegPerMin ?? 0) <= 2.5) ? .green : .orange
                    )
                }

                HStack(spacing: 10) {
                    metricCard(
                        title: L10n.choose(simplifiedChinese: "相位误差均值", english: "Mean Phase Error"),
                        value: long.meanBDCPhaseErrorDeg.map { String(format: "%.1f°", $0) } ?? "--",
                        tint: (long.meanBDCPhaseErrorDeg ?? 0) <= 16 ? .green : .orange
                    )
                    metricCard(
                        title: L10n.choose(simplifiedChinese: "踏频漂移", english: "Cadence Drift"),
                        value: long.cadenceDriftRPMPerMin.map { String(format: "%+.2f rpm/min", $0) } ?? "--",
                        tint: (abs(long.cadenceDriftRPMPerMin ?? 0) <= 2.2) ? .green : .orange
                    )
                    metricCard(
                        title: L10n.choose(simplifiedChinese: "疲劳后膝角变化", english: "Fatigue Knee Delta"),
                        value: kneeFatigueDelta.map { String(format: "%+.1f°", $0) } ?? "--",
                        tint: (abs(kneeFatigueDelta ?? 0) <= 4.0) ? .green : .orange
                    )
                    metricCard(
                        title: L10n.choose(simplifiedChinese: "疲劳后髋角变化", english: "Fatigue Hip Delta"),
                        value: hipFatigueDelta.map { String(format: "%+.1f°", $0) } ?? "--",
                        tint: (abs(hipFatigueDelta ?? 0) <= 3.5) ? .green : .orange
                    )
                }

                if bdcDelta != nil || kneeFatigueDelta != nil || hipFatigueDelta != nil {
                    Text(longDurationStabilitySummary(stats: long, bdcDelta: bdcDelta, kneeDelta: kneeFatigueDelta, hipDelta: hipFatigueDelta))
                        .font(.caption)
                        .foregroundStyle(longDurationStabilityStatusColor(stats: long, bdcDelta: bdcDelta, kneeDelta: kneeFatigueDelta, hipDelta: hipFatigueDelta))
                }
            }
        } else if result.durationSeconds < 20 {
            Text(
                L10n.choose(
                    simplifiedChinese: "当前片段不足 20 秒，无法输出 20-60 秒稳定性统计（BDC、相位漂移、疲劳后姿态变化）。",
                    english: "Clip is shorter than 20s, so 20-60s stability metrics (BDC, phase drift, fatigue posture change) are unavailable."
                )
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func metricCard(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
            Text(value)
                .font(.caption.monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
    }

    private func saddleAdjustmentText(_ direction: SaddleHeightAdjustmentDirection) -> String {
        switch direction {
        case .raise:
            return L10n.choose(simplifiedChinese: "升高座高", english: "raise saddle")
        case .lower:
            return L10n.choose(simplifiedChinese: "降低座高", english: "lower saddle")
        case .keep:
            return L10n.choose(simplifiedChinese: "保持当前座高（可微调）", english: "keep saddle height (fine-tune)")
        }
    }

    private func frontTrajectorySummary(_ trajectory: FrontTrajectoryStats) -> String {
        var flags: [String] = []
        if trajectory.kneeTrajectorySpanNorm > 0.36 {
            flags.append(L10n.choose(simplifiedChinese: "膝轨迹偏宽", english: "knee path too wide"))
        }
        if trajectory.ankleTrajectorySpanNorm > 0.28 {
            flags.append(L10n.choose(simplifiedChinese: "踝轨迹偏宽", english: "ankle path too wide"))
        }
        if let toeSpan = trajectory.toeTrajectorySpanNorm, toeSpan > 0.34 {
            flags.append(L10n.choose(simplifiedChinese: "足尖轨迹偏宽", english: "toe path too wide"))
        }
        if trajectory.kneeOverAnkleInRangeRatio < 0.70 {
            flags.append(L10n.choose(simplifiedChinese: "膝踝对位不稳定", english: "knee-ankle alignment unstable"))
        }
        if flags.isEmpty {
            return L10n.choose(
                simplifiedChinese: "前视图评估：膝-踝-足尖轨迹整体在合理范围内。",
                english: "Front-view assessment: knee-ankle-toe tracks are within a reasonable range."
            )
        }
        return L10n.choose(
            simplifiedChinese: "前视图评估：\(flags.joined(separator: "，"))。",
            english: "Front-view assessment: \(flags.joined(separator: ", "))."
        )
    }

    private func frontTrajectoryStatusColor(_ trajectory: FrontTrajectoryStats) -> Color {
        let toeOK = trajectory.toeTrajectorySpanNorm.map { $0 <= 0.34 } ?? true
        let allOK = trajectory.kneeTrajectorySpanNorm <= 0.36 &&
            trajectory.ankleTrajectorySpanNorm <= 0.28 &&
            toeOK &&
            trajectory.kneeOverAnkleInRangeRatio >= 0.70
        return allOK ? .green : .orange
    }

    private func rearStabilitySummary(
        stability: RearStabilityStats,
        pelvic: RearPelvicStats?,
        coordination: PedalingCoordinationStats?
    ) -> String {
        var flags: [String] = []
        if let pelvic, pelvic.maxPelvicTiltDeg > 6.0 {
            flags.append(L10n.choose(simplifiedChinese: "盆骨倾斜偏大", english: "pelvic tilt too high"))
        }
        if stability.meanCenterShiftNorm > 0.10 {
            flags.append(L10n.choose(simplifiedChinese: "重心平均漂移偏大", english: "mean CoM drift too high"))
        }
        if stability.maxCenterShiftNorm > 0.22 {
            flags.append(L10n.choose(simplifiedChinese: "重心最大漂移偏大", english: "max CoM drift too high"))
        }
        if abs(stability.lateralBias) > 0.05 {
            flags.append(L10n.choose(simplifiedChinese: "重心左右偏置明显", english: "lateral CoM bias is noticeable"))
        }
        if coordination?.isShunGuaiSuspected == true {
            flags.append(L10n.choose(simplifiedChinese: "疑似顺拐", english: "possible shun-guai pattern"))
        }
        if flags.isEmpty {
            return L10n.choose(
                simplifiedChinese: "后视图评估：盆骨稳定、重心漂移控制良好，未见明显顺拐。",
                english: "Rear-view assessment: pelvic and CoM stability are good, with no obvious shun-guai."
            )
        }
        return L10n.choose(
            simplifiedChinese: "后视图评估：\(flags.joined(separator: "，"))。",
            english: "Rear-view assessment: \(flags.joined(separator: ", "))."
        )
    }

    private func rearStabilityStatusColor(
        stability: RearStabilityStats,
        pelvic: RearPelvicStats?,
        coordination: PedalingCoordinationStats?
    ) -> Color {
        let pelvicOK = (pelvic?.maxPelvicTiltDeg ?? 0) <= 6.0
        let comOK = stability.meanCenterShiftNorm <= 0.10 &&
            stability.maxCenterShiftNorm <= 0.22 &&
            abs(stability.lateralBias) <= 0.05
        let coordOK = coordination?.isShunGuaiSuspected != true
        return (pelvicOK && comOK && coordOK) ? .green : .orange
    }

    private func longDurationStabilitySummary(
        stats: LongDurationStabilityStats,
        bdcDelta: Double?,
        kneeDelta: Double?,
        hipDelta: Double?
    ) -> String {
        var flags: [String] = []
        if stats.cycleCount < 12 {
            flags.append(L10n.choose(simplifiedChinese: "有效周期偏少", english: "too few valid cycles"))
        }
        if abs(stats.phaseDriftDegPerMin ?? 0) > 2.5 {
            flags.append(L10n.choose(simplifiedChinese: "相位漂移偏大", english: "phase drift too high"))
        }
        if abs(stats.bdcKneeDriftDegPerMin ?? 0) > 1.6 {
            flags.append(L10n.choose(simplifiedChinese: "BDC 膝角漂移偏大", english: "BDC knee drift too high"))
        }
        if abs(stats.cadenceDriftRPMPerMin ?? 0) > 2.2 {
            flags.append(L10n.choose(simplifiedChinese: "踏频稳定性不足", english: "cadence stability is weak"))
        }
        if abs(kneeDelta ?? 0) > 4.0 || abs(hipDelta ?? 0) > 3.5 || abs(bdcDelta ?? 0) > 4.0 {
            flags.append(L10n.choose(simplifiedChinese: "疲劳后姿态变化明显", english: "posture changes noticeably under fatigue"))
        }
        if flags.isEmpty {
            return L10n.choose(
                simplifiedChinese: "长时段评估：BDC、相位与踏频整体稳定，疲劳后姿态变化在可控范围。",
                english: "Long-duration assessment: BDC, phase, and cadence stay stable; post-fatigue posture change remains controlled."
            )
        }
        return L10n.choose(
            simplifiedChinese: "长时段评估：\(flags.joined(separator: "，"))。",
            english: "Long-duration assessment: \(flags.joined(separator: ", "))."
        )
    }

    private func longDurationStabilityStatusColor(
        stats: LongDurationStabilityStats,
        bdcDelta: Double?,
        kneeDelta: Double?,
        hipDelta: Double?
    ) -> Color {
        let driftOK = abs(stats.phaseDriftDegPerMin ?? 0) <= 2.5 &&
            abs(stats.bdcKneeDriftDegPerMin ?? 0) <= 1.6 &&
            abs(stats.cadenceDriftRPMPerMin ?? 0) <= 2.2
        let postureOK = abs(kneeDelta ?? 0) <= 4.0 &&
            abs(hipDelta ?? 0) <= 3.5 &&
            abs(bdcDelta ?? 0) <= 4.0
        let cyclesOK = stats.cycleCount >= 12
        return (driftOK && postureOK && cyclesOK) ? .green : .orange
    }

    private func adjustmentImpactColor(_ score: Double) -> Color {
        if score >= 80 { return .red }
        if score >= 60 { return .orange }
        if score >= 40 { return .yellow }
        return .green
    }

    private func valueDelta(late: Double?, early: Double?) -> Double? {
        guard let late, let early else { return nil }
        return late - early
    }

    private func saddleAdjustmentColor(_ direction: SaddleHeightAdjustmentDirection) -> Color {
        switch direction {
        case .raise:
            return .orange
        case .lower:
            return .purple
        case .keep:
            return .green
        }
    }

    @ViewBuilder
    private func cadenceCycleRow(_ cycle: CadenceCycleSegment) -> some View {
        let bdcText = cycle.bdcKneeAngleDeg.map { String(format: "%.1f°", $0) } ?? "--"
        Text(
            L10n.choose(
                simplifiedChinese: "周期 #\(cycle.id + 1) · \(String(format: "%.1f", cycle.cadenceRPM)) rpm · BDC \(bdcText) · \(String(format: "%.2f", cycle.startTimeSeconds))s-\(String(format: "%.2f", cycle.endTimeSeconds))s",
                english: "Cycle #\(cycle.id + 1) · \(String(format: "%.1f", cycle.cadenceRPM)) rpm · BDC \(bdcText) · \(String(format: "%.2f", cycle.startTimeSeconds))s-\(String(format: "%.2f", cycle.endTimeSeconds))s"
            )
        )
        .font(.caption2.monospacedDigit())
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func sideCheckpointCard(_ snapshot: SideCheckpointSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(snapshot.checkpoint.displayName) 点")
                .font(.caption.weight(.semibold))
            Text(String(format: "T %.2fs", snapshot.timeSeconds))
                .font(.caption2.monospacedDigit())
            Text(String(format: "P %.0f°", snapshot.phaseDeg))
                .font(.caption2.monospacedDigit())
            Text(String(format: "Δ %.0f°", snapshot.phaseErrorDeg))
                .font(.caption2.monospacedDigit())
            Text(String(format: "K %@", snapshot.kneeAngleDeg.map { String(format: "%.1f°", $0) } ?? "--"))
                .font(.caption2.monospacedDigit())
            Text(String(format: "H %@", snapshot.hipAngleDeg.map { String(format: "%.1f°", $0) } ?? "--"))
                .font(.caption2.monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func fittingRangeDashboard(result: VideoJointAngleAnalysisResult) -> some View {
        let kneeRange = result.kneeStats.map { $0.max - $0.min } ?? 0
        let hipRange = result.hipStats.map { $0.max - $0.min } ?? 0
        let strongRatio = result.samples.isEmpty
            ? 0
            : Double(result.samples.filter { $0.confidence >= 0.55 }.count) / Double(result.samples.count)

        HStack(spacing: 10) {
            metricCard(
                title: L10n.choose(simplifiedChinese: "膝角活动范围", english: "Knee ROM"),
                value: result.kneeStats == nil ? "--" : String(format: "%.1f°", kneeRange),
                tint: (kneeRange >= 25 && kneeRange <= 95) ? .green : .orange
            )
            metricCard(
                title: L10n.choose(simplifiedChinese: "髋角活动范围", english: "Hip ROM"),
                value: result.hipStats == nil ? "--" : String(format: "%.1f°", hipRange),
                tint: (hipRange >= 12 && hipRange <= 70) ? .green : .orange
            )
            metricCard(
                title: L10n.choose(simplifiedChinese: "高置信帧占比", english: "High-confidence Ratio"),
                value: String(format: "%.0f%%", strongRatio * 100),
                tint: strongRatio >= 0.6 ? .green : .orange
            )
        }
    }

    @ViewBuilder
    private func fittingFlowCard<Content: View>(
        step: Int,
        title: String,
        subtitle: String,
        state: VideoFittingFlowState,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(step)")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .frame(width: 18, height: 18)
                    .background(state.color.opacity(0.16), in: Circle())
                    .foregroundStyle(state.color)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Label(flowStateLabel(state), systemImage: state.symbol)
                    .font(.caption)
                    .foregroundStyle(state.color)
            }
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func flowStateLabel(_ state: VideoFittingFlowState) -> String {
        switch state {
        case .pending:
            return L10n.choose(simplifiedChinese: "待执行", english: "Pending")
        case .running:
            return L10n.choose(simplifiedChinese: "执行中", english: "Running")
        case .blocked:
            return L10n.choose(simplifiedChinese: "已阻止", english: "Blocked")
        case .ready:
            return L10n.choose(simplifiedChinese: "可执行", english: "Ready")
        case .done:
            return L10n.choose(simplifiedChinese: "已完成", english: "Done")
        }
    }

    @ViewBuilder
    private func captureGuidanceRow(for view: CyclingCameraView) -> some View {
        let guidance = captureGuidanceByView[view]
        HStack(spacing: 10) {
            Text(view.displayName)
                .font(.caption.weight(.semibold))
                .frame(width: 64, alignment: .leading)

            Text(
                guidance.map {
                    let lumaText = $0.luma.map { String(format: "%.2f", $0) } ?? "--"
                    let sharpnessText = $0.sharpness.map { String(format: "%.3f", $0) } ?? "--"
                    let occlusionText = $0.occlusionRatio.map { String(format: "%.0f%%", $0 * 100) } ?? "--"
                    let distortionText = $0.distortionRisk.map { String(format: "%.0f%%", $0 * 100) } ?? "--"
                    let alignText = $0.skeletonAlignability.map { String(format: "%.0f%%", $0 * 100) } ?? "--"
                    return L10n.choose(
                        simplifiedChinese: "FPS \(String(format: "%.1f", $0.fps)) · 亮度 \(lumaText) · 清晰 \(sharpnessText) · 遮挡 \(occlusionText) · 畸变风险 \(distortionText) · 对位 \(alignText)",
                        english: "FPS \(String(format: "%.1f", $0.fps)) · Luma \(lumaText) · Sharpness \(sharpnessText) · Occlusion \(occlusionText) · Distortion \(distortionText) · Align \(alignText)"
                    )
                } ?? L10n.choose(simplifiedChinese: "未检测", english: "Not measured")
            )
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)

            Spacer()

            if let guidance {
                Label(
                    guidance.qualityGatePass
                        ? L10n.choose(simplifiedChinese: "通过", english: "Pass")
                        : L10n.choose(simplifiedChinese: "需优化", english: "Improve"),
                    systemImage: guidance.qualityGatePass ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                )
                .font(.caption)
                .foregroundStyle(guidance.qualityGatePass ? .green : .orange)
            }
        }
    }

    private func refreshAllCaptureGuidance() {
        for view in supportedCyclingViews {
            guard let url = sourceVideoURL(for: view) else {
                captureGuidanceByView.removeValue(forKey: view)
                continue
            }
            Task {
                let guidance = await evaluateCaptureGuidance(for: url)
                await MainActor.run {
                    captureGuidanceByView[view] = guidance
                }
            }
        }
    }

    private func evaluateCaptureGuidance(for url: URL) async -> VideoCaptureGuidance {
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
                maxSamples: 7
            )
            let poseQuality = estimatePoseTrackingQuality(
                url: url,
                durationSeconds: durationSeconds,
                maxSamples: 7
            )
            return VideoCaptureGuidance(
                fps: fps,
                luma: frameStats.luma,
                sharpness: frameStats.sharpness,
                occlusionRatio: poseQuality.occlusionRatio,
                distortionRisk: poseQuality.distortionRisk,
                skeletonAlignability: poseQuality.skeletonAlignability
            )
        }.value
    }

    nonisolated private func sampleFrameQualityStats(
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

    nonisolated private func estimatePoseTrackingQuality(
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
                visibilityRatios.append(Double(visibleCount) / Double(jointNames.count))
                alignabilityRatios.append(poseFrameAlignable(points: points) ? 1 : 0)
                distortionRisks.append(estimateDistortionRisk(points: points))
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

    nonisolated private func poseFrameAlignable(
        points: [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint]
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

    nonisolated private func estimateDistortionRisk(
        points: [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint]
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
            return CGPoint(x: CGFloat(recognized.location.x), y: CGFloat(recognized.location.y))
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

    nonisolated private func sampleTimes(durationSeconds: Double?, count: Int) -> [CMTime] {
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

    nonisolated private func frameLumaAndSharpness(from cgImage: CGImage, context: CIContext) -> (luma: Double?, sharpness: Double?) {
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

    nonisolated private func areaAverageLuma(for image: CIImage, context: CIContext) -> Double? {
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

    nonisolated private func clamped(_ value: Double, min minValue: Double, max maxValue: Double) -> Double {
        Swift.max(minValue, Swift.min(maxValue, value))
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

    @ViewBuilder
    private func jointAngleStatsCard(title: String, stats: JointAngleStats?, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
            if let stats {
                Text(String(format: "Min %.1f°", stats.min))
                    .font(.caption.monospacedDigit())
                Text(String(format: "Avg %.1f°", stats.mean))
                    .font(.caption.monospacedDigit())
                Text(String(format: "Max %.1f°", stats.max))
                    .font(.caption.monospacedDigit())
                Text("n=\(stats.sampleCount)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            } else {
                Text("--")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
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

struct VideoFittingPageView: View {
    var body: some View {
        VideoDownloaderPageView(pageMode: .fitting)
    }
}

private extension DateFormatter {
    static let fricuCompactTimestamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()
}

private struct JointWireframeOverlay: View {
    let sample: VideoJointAngleSample

    var body: some View {
        GeometryReader { proxy in
            let overlayPoints = pointOverlays(size: proxy.size)
            ZStack {
                wireframePath(points: [sample.leftHip, sample.leftKnee, sample.leftAnkle, sample.leftToe], size: proxy.size)
                    .stroke(Color.green.opacity(0.85), style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                wireframePath(points: [sample.rightHip, sample.rightKnee, sample.rightAnkle, sample.rightToe], size: proxy.size)
                    .stroke(Color.orange.opacity(0.85), style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))

                ForEach(overlayPoints.indices, id: \.self) { idx in
                    let item = overlayPoints[idx]
                    Circle()
                        .fill(item.color)
                        .frame(width: 6, height: 6)
                        .position(item.position)
                }
            }
            .background(.clear)
        }
    }

    private func wireframePath(points: [PoseJointPoint?], size: CGSize) -> Path {
        let mapped = points.compactMap { mapPoint($0, size: size) }
        guard let start = mapped.first else { return Path() }
        var path = Path()
        path.move(to: start)
        for point in mapped.dropFirst() {
            path.addLine(to: point)
        }
        return path
    }

    private func pointOverlays(size: CGSize) -> [(position: CGPoint, color: Color)] {
        let leftPoints = [sample.leftHip, sample.leftKnee, sample.leftAnkle, sample.leftToe]
            .compactMap { mapPoint($0, size: size) }
            .map { ($0, Color.green.opacity(0.92)) }
        let rightPoints = [sample.rightHip, sample.rightKnee, sample.rightAnkle, sample.rightToe]
            .compactMap { mapPoint($0, size: size) }
            .map { ($0, Color.orange.opacity(0.92)) }
        return leftPoints + rightPoints
    }

    private func mapPoint(_ point: PoseJointPoint?, size: CGSize) -> CGPoint? {
        guard let point else { return nil }
        return CGPoint(
            x: point.x * size.width,
            y: (1.0 - point.y) * size.height
        )
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
    let fittingMode: VideoFittingMode

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .floating
        view.showsFullScreenToggleButton = true
        view.player = player
        view.videoGravity = fittingMode.avVideoGravity
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        nsView.player = player
        nsView.videoGravity = fittingMode.avVideoGravity
    }
}
#else
/// iOS fallback wrapper for embedded AVPlayer playback.
private struct EmbeddedAVPlayerView: UIViewControllerRepresentable {
    let player: AVPlayer
    let fittingMode: VideoFittingMode

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.videoGravity = fittingMode.avVideoGravity
        return controller
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        uiViewController.player = player
        uiViewController.videoGravity = fittingMode.avVideoGravity
    }
}
#endif
