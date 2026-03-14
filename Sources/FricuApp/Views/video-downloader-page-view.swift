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
    case directMedia

    var id: String { rawValue }

    /// Human-readable platform name.
    var displayName: String {
        switch self {
        case .youtube:
            return "YouTube"
        case .instagram:
            return "Instagram"
        case .directMedia:
            return L10n.choose(simplifiedChinese: "直链视频", english: "Direct Media")
        }
    }

    /// List of accepted host suffixes for each platform.
    var acceptedHostSuffixes: [String] {
        switch self {
        case .youtube:
            return ["youtube.com", "youtu.be", "m.youtube.com"]
        case .instagram:
            return ["instagram.com", "www.instagram.com"]
        case .directMedia:
            return []
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

        if isLikelyDirectMediaURL(parsedURL) {
            return .valid(platform: .directMedia, normalizedURL: parsedURL)
        }

        guard let matchedPlatform = VideoDownloadPlatform.allCases.first(where: { platform in
            guard platform != .directMedia else { return false }
            return platform.acceptedHostSuffixes.contains(where: { suffix in
                host == suffix || host.hasSuffix("." + suffix)
            })
        }) else {
            return .unsupportedPlatform
        }

        return .valid(platform: matchedPlatform, normalizedURL: parsedURL)
    }

    private func isLikelyDirectMediaURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return false
        }
        let ext = url.pathExtension.lowercased()
        let allowed = Set([
            "mp4", "mov", "m4v", "webm", "mkv", "avi", "wmv",
            "m3u8", "ts"
        ])
        return allowed.contains(ext)
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

/// Resolves writable app-scoped directories for download/import/report assets.
struct VideoWorkspaceDirectoryResolver {
    enum Kind {
        case downloads
        case fittingReports
        case imports
    }

    func resolve(kind: Kind) throws -> URL {
        let fm = FileManager.default
        let folderName: String
        switch kind {
        case .downloads:
            folderName = "FricuDownloads"
        case .fittingReports:
            folderName = "FricuFittingReports"
        case .imports:
            folderName = "FricuImportedVideos"
        }

        #if os(iOS)
        let root = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fm.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? fm.temporaryDirectory
        let appRoot = root.appendingPathComponent("Fricu", isDirectory: true)
        let target = appRoot.appendingPathComponent(folderName, isDirectory: true)
        #else
        let root = fm.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fm.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        let target = root.appendingPathComponent(folderName, isDirectory: true)
        #endif

        do {
            try fm.createDirectory(at: target, withIntermediateDirectories: true)
            return target
        } catch {
            throw VideoDownloadExecutionError.commandFailed(
                reason: L10n.choose(
                    simplifiedChinese: "无法创建输出目录：\(error.localizedDescription)",
                    english: "Unable to create output directory: \(error.localizedDescription)"
                )
            )
        }
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
        #elseif os(iOS)
        try await downloadOnIOS(sourceURL: sourceURL, quality: quality, speedMode: speedMode)
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
        try VideoWorkspaceDirectoryResolver().resolve(kind: .downloads)
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

    #if os(iOS)
    private func downloadOnIOS(
        sourceURL: URL,
        quality _: VideoDownloadQuality,
        speedMode _: VideoDownloadSpeedMode
    ) async throws -> VideoDownloadResult {
        let fm = FileManager.default
        let outputDirectory = try VideoWorkspaceDirectoryResolver().resolve(kind: .downloads)

        let isDirect = isLikelyDirectMediaURL(sourceURL) || (try await remoteAppearsVideoAsset(sourceURL))
        guard isDirect else {
            throw VideoDownloadExecutionError.commandFailed(
                reason: L10n.choose(
                    simplifiedChinese: "iPad 端仅支持直链视频下载（mp4/mov/m3u8 等）。YouTube/Instagram 页面链接请先在服务端或 Mac 端解析后再下载。",
                    english: "On iPad, only direct media URLs are supported (mp4/mov/m3u8, etc.). Resolve YouTube/Instagram page links on server/macOS first, then download."
                )
            )
        }

        let (tempURL, response) = try await URLSession.shared.download(from: sourceURL)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw VideoDownloadExecutionError.commandFailed(
                reason: L10n.choose(
                    simplifiedChinese: "下载失败，HTTP \(http.statusCode)。",
                    english: "Download failed, HTTP \(http.statusCode)."
                )
            )
        }

        let ext = resolveFileExtension(sourceURL: sourceURL, response: response)
        let suggested = (response.suggestedFilename?.isEmpty == false)
            ? response.suggestedFilename!
            : "video-\(DateFormatter.fricuCompactTimestamp.string(from: Date())).\(ext)"
        let fileName = sanitizeFileName(suggested)
        let outputURL = outputDirectory.appendingPathComponent(fileName, isDirectory: false)

        if fm.fileExists(atPath: outputURL.path) {
            try fm.removeItem(at: outputURL)
        }
        do {
            try fm.moveItem(at: tempURL, to: outputURL)
        } catch {
            throw VideoDownloadExecutionError.commandFailed(
                reason: L10n.choose(
                    simplifiedChinese: "写入 iPad App 目录失败：\(error.localizedDescription)",
                    english: "Failed writing into iPad app directory: \(error.localizedDescription)"
                )
            )
        }

        return VideoDownloadResult(outputURL: outputURL, extractedMediaURL: sourceURL.absoluteString)
    }

    private func remoteAppearsVideoAsset(_ sourceURL: URL) async throws -> Bool {
        var request = URLRequest(url: sourceURL)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 20
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse,
               let contentType = http.value(forHTTPHeaderField: "Content-Type")?.lowercased() {
                return contentType.hasPrefix("video/") || contentType.contains("application/vnd.apple.mpegurl")
            }
        } catch {
            // Fallback to extension-based detection.
        }
        return false
    }

    private func isLikelyDirectMediaURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return false
        }
        let ext = url.pathExtension.lowercased()
        let allowed = Set([
            "mp4", "mov", "m4v", "webm", "mkv", "avi", "wmv",
            "m3u8", "ts"
        ])
        return allowed.contains(ext)
    }

    private func resolveFileExtension(sourceURL: URL, response: URLResponse) -> String {
        let sourceExt = sourceURL.pathExtension.lowercased()
        if !sourceExt.isEmpty {
            return sourceExt
        }
        if let mime = response.mimeType, let type = UTType(mimeType: mime) {
            if let preferred = type.preferredFilenameExtension {
                return preferred
            }
        }
        if let suggested = response.suggestedFilename {
            let ext = URL(fileURLWithPath: suggested).pathExtension.lowercased()
            if !ext.isEmpty { return ext }
        }
        return "mp4"
    }

    private func sanitizeFileName(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "video-\(UUID().uuidString).mp4" }
        let invalid = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let parts = trimmed.components(separatedBy: invalid)
        let normalized = parts.joined(separator: "_")
        return normalized.isEmpty ? "video-\(UUID().uuidString).mp4" : normalized
    }
    #endif
}

/// A dedicated page for preparing social/direct video download jobs.
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
        simplifiedChinese: "待检查：先分配前 / 侧 / 后机位视频，再执行合规检查。",
        english: "Pending: assign front/side/rear videos first, then run compliance check."
    )
    @State private var flowComplianceFailureDetails: [String] = []
    @State private var virtualSaddleDeltaMM = 0.0
    @State private var virtualSetbackDeltaMM = 0.0
    @State private var selectedJointAnalysisView: CyclingCameraView = .side
    @State private var selectedFittingResultTab: VideoFittingResultTab = .overview
    @State private var frontCameraVideoURL: URL?
    @State private var sideCameraVideoURL: URL?
    @State private var rearCameraVideoURL: URL?
    @State private var activeVideoImportTarget: VideoImportTarget?
    @State private var isVideoImporterSheetPresented = false
    @AppStorage("fricu.video.player.fitting.mode.v1") private var videoFittingModeRawValue = VideoFittingMode.fit.rawValue
    @AppStorage("fricu.video.player.force.avplayer.v1") private var forceAVPlayerForPlayback = false
    @AppStorage("fricu.video.fitting.pose.model.v1") private var poseEstimationModelRawValue = VideoPoseEstimationModel.auto.rawValue
    private let validator = VideoDownloadRequestValidator()
    private let executor = VideoDownloadExecutor()
    private let fittingFlowPlanningService = VideoFittingFlowPlanningService()
    private let preflightQualityGateService = VideoFittingPreflightQualityGateService()
    private let qualityProbeService = VideoCaptureQualityProbeService()
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
                    VideoFittingSessionSummaryCard(summary: fittingSessionSummary)

                    GroupBox(L10n.choose(simplifiedChinese: "视频 Fitting 流程", english: "Video Fitting Workflow")) {
                        VStack(alignment: .leading, spacing: 12) {
                            fittingFlowCard(
                                step: 1,
                                title: L10n.choose(simplifiedChinese: "分配机位（前 / 侧 / 后）", english: "Assign Views (Front / Side / Rear)"),
                                subtitle: L10n.choose(
                                    simplifiedChinese: "流程起点：先为每个机位选择独立视频；缺失机位将缺少对应分析结果。",
                                    english: "Flow starts here: assign dedicated videos for each view first; missing views will miss corresponding analysis outputs."
                                ),
                                state: viewAssignmentStepState
                            ) {
                                VStack(alignment: .leading, spacing: 10) {
                                    VideoFittingCaptureGuidePanel(
                                        highlightMissingSetup: !hasAnyAssignedCameraSources
                                    )

                                    VideoFittingCameraViewCards(
                                        cards: cameraViewCardSummaries,
                                        isBusy: isAnalyzingJointAngles,
                                        chooseAction: { view in
                                            presentCameraVideoImporter(for: view)
                                        },
                                        clearAction: { view in
                                            setCameraVideoURL(nil, for: view)
                                        }
                                    )

                                    if !missingRequiredCameraViews.isEmpty {
                                        Text(
                                            L10n.choose(
                                                simplifiedChinese: "每张机位卡都会直接说明缺失后会失去什么结论；补齐三机位后，分析覆盖最完整。",
                                                english: "Each view card explains what conclusion is missing. Fill all three views for complete coverage."
                                            )
                                        )
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    }
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
                                    .disabled(isRunningFlowComplianceCheck || !hasAnyAssignedCameraSources)

                                    VideoFittingComplianceResultCardsView(summaries: complianceViewSummaries)

                                    if let recoverySummary = fittingFailureRecoverySummary {
                                        VideoFittingFailureRecoveryPanel(
                                            summary: recoverySummary,
                                            isRetrying: isRunningFlowComplianceCheck,
                                            retryAction: handleRunFlowComplianceCheckTapped
                                        )
                                    }

                                    if !missingRequiredCameraViews.isEmpty {
                                        Text(
                                            L10n.choose(
                                                simplifiedChinese: "提示：未配置机位不会阻止合规检查，但会导致该机位结果缺失。",
                                                english: "Tip: unassigned views won't block compliance check, but their analysis outputs will be missing."
                                            )
                                        )
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
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

                                    HStack(spacing: 10) {
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

                                    if !canRunPostComplianceSteps {
                                        Text(
                                            L10n.choose(
                                                simplifiedChinese: "请先完成并通过上方合规检查，再执行关节识别。",
                                                english: "Complete and pass the compliance check above before running joint recognition."
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

                                    VideoFittingJointRecognitionQualityPanel(summary: selectedJointRecognitionQualitySummary)

                                    if selectedJointAngleResult != nil {
                                        Text(
                                            L10n.choose(
                                                simplifiedChinese: "当前视角已生成结果。请在下方“分析并导出报告 / 视频”中的结果标签页查看结论、指标、建议与证据。",
                                                english: "The selected view already produced a result. Review conclusions, metrics, suggestions, and evidence in the result tabs below."
                                            )
                                        )
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
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
                            }

                            fittingFlowCard(
                                step: 4,
                                title: L10n.choose(simplifiedChinese: "分析并导出报告 / 视频", english: "Analyze and Export Report / Video"),
                                subtitle: L10n.choose(simplifiedChinese: "通过合规后才能执行最终分析和导出", english: "Final analysis/export is available only after compliance passes"),
                                state: reportStepState
                            ) {
                                VStack(alignment: .leading, spacing: 10) {
                                    VideoFittingResultTabBar(selection: $selectedFittingResultTab)

                                    fittingResultTabContent()

                                    statusRow(
                                        title: L10n.choose(simplifiedChinese: "输出路径", english: "Output"),
                                        value: outputLocationText
                                    )
                                    statusRow(
                                        title: L10n.choose(simplifiedChinese: "播放内核", english: "Playback Engine"),
                                        value: playbackEngineText
                                    )
                                    statusRow(
                                        title: L10n.choose(simplifiedChinese: "视频 Fitting", english: "Video Fitting"),
                                        value: videoFittingMode.displayName
                                    )
                                    statusRow(
                                        title: L10n.choose(simplifiedChinese: "播放测试", english: "Playback"),
                                        value: playbackStatusText
                                    )
                                    statusRow(
                                        title: L10n.choose(simplifiedChinese: "关节角分析", english: "Joint Angle Analysis"),
                                        value: jointAngleStatusText
                                    )

                                    let capabilityMatrix = fittingCapabilityMatrix
                                    Text(
                                        L10n.choose(
                                            simplifiedChinese: "能力覆盖：\(capabilityMatrix.availableCount)/\(capabilityMatrix.statuses.count)",
                                            english: "Capability coverage: \(capabilityMatrix.availableCount)/\(capabilityMatrix.statuses.count)"
                                        )
                                    )
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(capabilityMatrix.unavailableCount == 0 ? .green : .orange)

                                    ForEach(capabilityMatrix.statuses) { status in
                                        HStack(spacing: 8) {
                                            Image(systemName: status.isAvailable ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                                .foregroundStyle(status.isAvailable ? .green : .orange)
                                                .font(.caption)
                                            Text(status.capability.title)
                                                .font(.caption.weight(.semibold))
                                            Text(status.message)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                            Spacer(minLength: 0)
                                        }
                                    }

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

                                    fittingPlaybackPanel()

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
                                        .disabled(isAnalyzingJointAngles || !canRunPostComplianceSteps)

                                        Button(
                                            isAnalyzingJointAngles
                                                ? L10n.choose(simplifiedChinese: "处理中...", english: "Running...")
                                                : L10n.choose(simplifiedChinese: "自动检测踩踏并采集+分析", english: "Auto detect pedaling + capture + analyze")
                                        ) {
                                            handleAutoCaptureAndAnalyzeTapped()
                                        }
                                        .buttonStyle(.bordered)
                                        .disabled(isAnalyzingJointAngles || !canRunPostComplianceSteps)
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
                                        .disabled(isAnalyzingJointAngles || !canRunPostComplianceSteps)
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

                if !isFittingPage {
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
                }

                if !isFittingPage {
                    GroupBox(L10n.choose(simplifiedChinese: "播放测试", english: "Playback Test")) {
                    VStack(alignment: .leading, spacing: 10) {
                        if usesLibVLCPlayback, downloadedVideoURL != nil {
                            #if os(macOS) && canImport(VLCKit)
                            ZStack {
                                EmbeddedLibVLCPlayerView(controller: libVLCPlaybackController)
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
            isPresented: $isVideoImporterSheetPresented,
            allowedContentTypes: [.movie, .mpeg4Movie, .quickTimeMovie],
            allowsMultipleSelection: false
        ) { result in
            handleVideoImportResult(result)
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

    @ViewBuilder
    private func fittingPlaybackPanel() -> some View {
        if usesLibVLCPlayback, downloadedVideoURL != nil {
            #if os(macOS) && canImport(VLCKit)
            ZStack {
                EmbeddedLibVLCPlayerView(controller: libVLCPlaybackController)
                if let sample = activeOverlaySample {
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
                if let sample = activeOverlaySample {
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
                    simplifiedChinese: "选择本地视频后会在这里加载播放器。",
                    english: "The player appears here after selecting a local video."
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

    private var assignedCameraViews: Set<CyclingCameraView> {
        Set(supportedCyclingViews.filter { explicitCameraVideoURL(for: $0) != nil })
    }

    private var fittingWorkflowSnapshot: VideoFittingWorkflowSnapshot {
        VideoFittingWorkflowSnapshot(
            assignedViewCount: assignedCameraViews.count,
            requiredViewCount: supportedCyclingViews.count,
            isComplianceRunning: isRunningFlowComplianceCheck,
            complianceChecked: flowComplianceChecked,
            compliancePassed: flowCompliancePassed,
            isAnalyzing: isAnalyzingJointAngles,
            hasRecognitionResults: hasAnyJointRecognitionResult
        )
    }

    private var fittingWorkflowStates: VideoFittingWorkflowStates {
        VideoFittingWorkflowResolver.resolve(from: fittingWorkflowSnapshot)
    }

    private var fittingCapabilityMatrix: VideoFittingCapabilityMatrix {
        VideoFittingCapabilityMatrix.build(assignedViews: assignedCameraViews)
    }

    private var fittingSessionSummary: VideoFittingSessionSummary {
        VideoFittingSessionSummaryResolver.resolve(
            snapshot: fittingWorkflowSnapshot,
            states: fittingWorkflowStates,
            capabilityMatrix: fittingCapabilityMatrix
        )
    }

    private var selectedFittingResultOverviewSummary: VideoFittingResultOverviewSummary {
        VideoFittingResultOverviewSummaryResolver.resolve(
            result: selectedJointAngleResult,
            qualitySummary: selectedJointRecognitionQualitySummary,
            selectedView: selectedJointAnalysisView
        )
    }

    private var missingRequiredCameraViews: [CyclingCameraView] {
        supportedCyclingViews.filter { explicitCameraVideoURL(for: $0) == nil }
    }


    private var cameraViewCardSummaries: [VideoFittingCameraViewCardSummary] {
        supportedCyclingViews.map { view in
            VideoFittingCameraViewCardSummaryResolver.resolve(
                view: view,
                sourceURL: explicitCameraVideoURL(for: view),
                guidance: captureGuidanceByView[view],
                hasAnalysisResult: jointAngleResultsByView[view] != nil
            )
        }
    }

    private var complianceViewSummaries: [VideoFittingComplianceViewSummary] {
        supportedCyclingViews.map { view in
            VideoFittingComplianceViewSummaryResolver.resolve(
                view: view,
                sourceURL: explicitCameraVideoURL(for: view),
                guidance: captureGuidanceByView[view]
            )
        }
    }

    private var fittingFailureRecoverySummary: VideoFittingFailureRecoverySummary? {
        VideoFittingFailureRecoverySummaryResolver.resolve(
            supportedViews: supportedCyclingViews,
            sourceURL: { explicitCameraVideoURL(for: $0) },
            guidanceByView: captureGuidanceByView,
            complianceChecked: flowComplianceChecked,
            compliancePassed: flowCompliancePassed
        )
    }

    private var selectedJointRecognitionQualitySummary: VideoFittingJointRecognitionQualitySummary {
        VideoFittingJointRecognitionQualitySummaryResolver.resolve(
            selectedView: selectedJointAnalysisView,
            sourceURL: sourceVideoURL(for: selectedJointAnalysisView),
            guidance: captureGuidanceByView[selectedJointAnalysisView],
            result: selectedJointAngleResult
        )
    }

    private var hasAnyAssignedCameraSources: Bool {
        fittingWorkflowSnapshot.hasAnyAssignedView
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
                simplifiedChinese: "支持 YouTube / Instagram 链接；iPad 也可使用 mp4/mov/m3u8 等直链。",
                english: "Supports YouTube/Instagram links; on iPad you can also use direct mp4/mov/m3u8 URLs."
            )
        case .invalidURL:
            return L10n.choose(
                simplifiedChinese: "链接格式无效，请使用完整 https 地址。",
                english: "Invalid URL format. Use a full https link."
            )
        case .unsupportedPlatform:
            return L10n.choose(
                simplifiedChinese: "当前仅支持 YouTube / Instagram 或直链视频地址。",
                english: "Only YouTube/Instagram or direct media URLs are supported."
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
                simplifiedChinese: "校验失败：平台不在支持范围（仅 YouTube / Instagram / 直链视频）。",
                english: "Validation failed: platform not supported (YouTube / Instagram / direct media only)."
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
        fittingWorkflowStates.canRunPostCompliance
    }

    private var hasAnyJointRecognitionResult: Bool {
        !jointAngleResultsByView.isEmpty
    }

    private var flowComplianceStepState: VideoFittingFlowState {
        uiFlowState(for: fittingWorkflowStates.compliance)
    }

    private var skeletonRecognitionStepState: VideoFittingFlowState {
        uiFlowState(for: fittingWorkflowStates.skeletonRecognition)
    }

    private var viewAssignmentStepState: VideoFittingFlowState {
        uiFlowState(for: fittingWorkflowStates.viewAssignment)
    }

    private var reportStepState: VideoFittingFlowState {
        uiFlowState(for: fittingWorkflowStates.report)
    }

    private func runPreflightQualityGate(
        plans: [(CyclingCameraView, URL)]
    ) async -> VideoFittingPreflightQualityGateResult {
        let gate = await preflightQualityGateService.run(
            plans: plans,
            evaluateGuidance: { url in
                await qualityProbeService.evaluateCaptureGuidance(for: url)
            }
        )
        await MainActor.run {
            captureGuidanceByView.merge(gate.guidanceByView) { _, latest in latest }
        }
        return gate
    }

    private func resetFlowComplianceState() {
        isRunningFlowComplianceCheck = false
        flowComplianceChecked = false
        flowCompliancePassed = false
        flowComplianceMessage = L10n.choose(
            simplifiedChinese: "待检查：请先为前 / 侧 / 后分别配置视频，再执行合规检查。",
            english: "Pending: assign front/side/rear videos first, then run compliance check."
        )
        flowComplianceFailureDetails = []
    }

    private func handleRunFlowComplianceCheckTapped() {
        if !hasAnyAssignedCameraSources {
            flowComplianceChecked = false
            flowCompliancePassed = false
            flowComplianceMessage = L10n.choose(
                simplifiedChinese: "请先至少配置一个机位视频，再执行合规检查。",
                english: "Assign at least one view video before running compliance check."
            )
            flowComplianceFailureDetails = []
            return
        }
        let plans = fittingFlowPlanningService.assignedPlans(
            supportedViews: supportedCyclingViews,
            sourceVideoURL: { view in sourceVideoURL(for: view) }
        )
        guard !plans.isEmpty else {
            flowComplianceChecked = false
            flowCompliancePassed = false
            flowComplianceMessage = L10n.choose(
                simplifiedChinese: "未检测到可用机位视频，请先分配机位。",
                english: "No usable view video found. Assign view videos first."
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
            let gate = await runPreflightQualityGate(plans: plans)
            let uniqueFailures = fittingFlowPlanningService.uniqueFailures(gate.failures)
            await MainActor.run {
                isRunningFlowComplianceCheck = false
                flowComplianceChecked = true
                flowCompliancePassed = uniqueFailures.isEmpty
                if uniqueFailures.isEmpty {
                    if missingRequiredCameraViews.isEmpty {
                        flowComplianceMessage = L10n.choose(
                            simplifiedChinese: "合规通过：可进入后续关节识别与报告流程。",
                            english: "Compliance passed. Continue to joint recognition and reporting."
                        )
                    } else {
                        let missingText = missingRequiredCameraViews.map(\.displayName).joined(separator: " / ")
                        flowComplianceMessage = L10n.choose(
                            simplifiedChinese: "合规通过（已配置机位）：可继续分析。未配置机位（\(missingText)）将缺少对应结果。",
                            english: "Compliance passed for assigned views. Continue analysis; unassigned views (\(missingText)) will have no corresponding results."
                        )
                    }
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
            return frontCameraVideoURL
        case .side:
            return sideCameraVideoURL
        case .rear:
            return rearCameraVideoURL
        case .auto:
            return analyzableLocalVideoURL
        }
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
            do {
                let persistedURL = try persistImportedVideoToSandbox(from: selectedURL, prefix: "primary")
                outputLocationText = persistedURL.path
                configurePlaybackPlayer(with: persistedURL, fallbackMediaURLText: "-")
            } catch {
                playbackErrorText = L10n.choose(
                    simplifiedChinese: "导入视频失败：\(error.localizedDescription)",
                    english: "Failed to import video: \(error.localizedDescription)"
                )
            }
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
                simplifiedChinese: "请先输入可识别的 YouTube / Instagram 链接，或可直接下载的视频直链。",
                english: "Provide a valid YouTube/Instagram URL, or a direct downloadable media URL."
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
                simplifiedChinese: "当前仅支持 YouTube / Instagram 链接或直链视频地址。",
                english: "Only YouTube/Instagram links or direct media URLs are supported."
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
        let requestedView = selectedJointAnalysisView
        let localURL = sourceVideoURL(for: requestedView)
        if let blocked = VideoFittingFlowGuardPolicy.analyzeSelectedView(
            canRunPostCompliance: canRunPostComplianceSteps,
            hasRequestedViewVideo: localURL != nil
        ) {
            switch blocked {
            case .complianceRequired:
                jointAngleStatusText = L10n.choose(simplifiedChinese: "流程已阻止", english: "Flow blocked")
                jointAngleErrorText = L10n.choose(
                    simplifiedChinese: "请先完成并通过“视频合规检查（畸变/骨骼对位）”后再执行识别。",
                    english: "Complete and pass the compliance check (distortion/skeleton alignment) before recognition."
                )
            case .selectedViewVideoMissing:
                jointAngleStatusText = L10n.choose(simplifiedChinese: "不可分析", english: "Unavailable")
                jointAngleErrorText = L10n.choose(
                    simplifiedChinese: "当前视角没有可分析的本地视频文件。",
                    english: "No analyzable local video file is available for the selected view."
                )
            case .assignedViewsMissing, .analysisResultsMissing:
                break
            }
            return
        }
        guard let localURL else { return }

        isAnalyzingJointAngles = true
        jointAngleErrorText = "-"
        jointAngleStatusText = L10n.choose(simplifiedChinese: "质量检测中", english: "Quality checking")
        jointAngleResultsByView[requestedView] = nil

        Task {
            let gate = await runPreflightQualityGate(plans: [(requestedView, localURL)])
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
        let plans = fittingFlowPlanningService.assignedPlans(
            supportedViews: supportedCyclingViews,
            sourceVideoURL: { view in sourceVideoURL(for: view) }
        )
        if let blocked = VideoFittingFlowGuardPolicy.analyzeAllViews(
            canRunPostCompliance: canRunPostComplianceSteps,
            hasAnyAssignedViewVideo: !plans.isEmpty
        ) {
            switch blocked {
            case .complianceRequired:
                jointAngleStatusText = L10n.choose(simplifiedChinese: "流程已阻止", english: "Flow blocked")
                jointAngleErrorText = L10n.choose(
                    simplifiedChinese: "请先完成并通过“视频合规检查（畸变/骨骼对位）”后再分析全部机位。",
                    english: "Complete and pass the compliance check (distortion/skeleton alignment) before all-view analysis."
                )
            case .assignedViewsMissing:
                jointAngleStatusText = L10n.choose(simplifiedChinese: "不可分析", english: "Unavailable")
                jointAngleErrorText = L10n.choose(
                    simplifiedChinese: "请先配置至少一个机位视频文件。",
                    english: "Configure at least one camera view video first."
                )
            case .selectedViewVideoMissing, .analysisResultsMissing:
                break
            }
            return
        }

        isAnalyzingJointAngles = true
        jointAngleErrorText = "-"
        jointAngleStatusText = L10n.choose(simplifiedChinese: "质量检测中", english: "Quality checking")

        Task {
            let gate = await runPreflightQualityGate(plans: plans)
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
        let plans = fittingFlowPlanningService.assignedPlans(
            supportedViews: supportedCyclingViews,
            sourceVideoURL: { view in sourceVideoURL(for: view) }
        )
        if let blocked = VideoFittingFlowGuardPolicy.autoCaptureAndAnalyze(
            canRunPostCompliance: canRunPostComplianceSteps,
            hasAnyAssignedViewVideo: !plans.isEmpty
        ) {
            switch blocked {
            case .complianceRequired:
                autoCaptureStatusText = L10n.choose(
                    simplifiedChinese: "合规检查未通过，已阻止自动采集+分析流程。",
                    english: "Compliance check is not passed. Auto capture/analyze is blocked."
                )
            case .assignedViewsMissing:
                autoCaptureStatusText = L10n.choose(
                    simplifiedChinese: "没有可用机位视频，无法自动采集。",
                    english: "No source video available for auto capture."
                )
            case .selectedViewVideoMissing, .analysisResultsMissing:
                break
            }
            return
        }

        isAnalyzingJointAngles = true
        autoCaptureStatusText = L10n.choose(simplifiedChinese: "质量门控检测中...", english: "Running quality gate...")
        jointAngleErrorText = "-"
        jointAngleStatusText = L10n.choose(simplifiedChinese: "质量检测中", english: "Quality checking")

        Task {
            let gate = await runPreflightQualityGate(plans: plans)
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
                    let captureWindow = VideoFittingCaptureWindowPolicy.suggestedCaptureWindow(
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
        let exportResults = fittingFlowPlanningService.exportedResultsByView(
            resultsByView: jointAngleResultsByView,
            supportedViews: supportedCyclingViews
        )
        if let blocked = VideoFittingFlowGuardPolicy.exportPDF(
            canRunPostCompliance: canRunPostComplianceSteps,
            hasAnyAnalysisResult: !exportResults.isEmpty
        ) {
            switch blocked {
            case .complianceRequired:
                reportExportStatusText = L10n.choose(
                    simplifiedChinese: "合规检查未通过，已阻止报告导出。",
                    english: "Compliance check is not passed. Export is blocked."
                )
            case .analysisResultsMissing:
                reportExportStatusText = L10n.choose(
                    simplifiedChinese: "暂无可导出的分析结果。",
                    english: "No analysis result to export."
                )
            case .selectedViewVideoMissing, .assignedViewsMissing:
                break
            }
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
        let plans = fittingFlowPlanningService.assignedPlans(
            supportedViews: supportedCyclingViews,
            sourceVideoURL: { view in sourceVideoURL(for: view) }
        )
        if let blocked = VideoFittingFlowGuardPolicy.exportReportVideos(
            canRunPostCompliance: canRunPostComplianceSteps,
            hasAnyAssignedViewVideo: !plans.isEmpty
        ) {
            switch blocked {
            case .complianceRequired:
                reportExportStatusText = L10n.choose(
                    simplifiedChinese: "合规检查未通过，已阻止报告视频导出。",
                    english: "Compliance check is not passed. Report video export is blocked."
                )
            case .assignedViewsMissing:
                reportExportStatusText = L10n.choose(
                    simplifiedChinese: "暂无可导出的视频机位。",
                    english: "No video view available for export."
                )
            case .selectedViewVideoMissing, .analysisResultsMissing:
                break
            }
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
                        let gate = await runPreflightQualityGate(plans: [(view, sourceURL)])
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
                    let captureWindow = VideoFittingCaptureWindowPolicy.suggestedCaptureWindow(
                        from: referenceResult,
                        preferredDuration: autoCaptureDurationSeconds
                    )
                    let overlayResult: VideoJointAngleAnalysisResult
                    if VideoFittingCaptureWindowPolicy.analysisResultCoversWindow(
                        referenceResult,
                        start: captureWindow.start,
                        duration: captureWindow.duration
                    ) {
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
        if let resolved = try? VideoWorkspaceDirectoryResolver().resolve(kind: .fittingReports) {
            return resolved
        }
        let fallback = FileManager.default.temporaryDirectory
            .appendingPathComponent("fricu/FricuFittingReports", isDirectory: true)
        try? FileManager.default.createDirectory(at: fallback, withIntermediateDirectories: true)
        return fallback
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
                simplifiedChinese: "无法获取应用可写输出目录，请检查权限后重试。",
                english: "Unable to resolve a writable app output directory. Check permissions and retry."
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

    private func presentPrimaryFittingVideoImporter() {
        activeVideoImportTarget = .primary
        isVideoImporterSheetPresented = true
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
        if activeVideoImportTarget != nil {
            isVideoImporterSheetPresented = true
        }
    }

    private func handleVideoImportResult(_ result: Result<[URL], Error>) {
        let target = activeVideoImportTarget
        isVideoImporterSheetPresented = false
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
            do {
                let persistedURL = try persistImportedVideoToSandbox(from: selectedURL, prefix: view.rawValue)
                setCameraVideoURL(persistedURL, for: view)
                jointAngleErrorText = "-"
                jointAngleStatusText = L10n.choose(simplifiedChinese: "可分析", english: "Ready")
            } catch {
                jointAngleErrorText = L10n.choose(
                    simplifiedChinese: "导入视频失败：\(error.localizedDescription)",
                    english: "Failed to import video: \(error.localizedDescription)"
                )
            }
        case .failure(let error):
            jointAngleErrorText = L10n.choose(
                simplifiedChinese: "导入视频失败：\(error.localizedDescription)",
                english: "Failed to import video: \(error.localizedDescription)"
            )
        }
    }

    private func persistImportedVideoToSandbox(from selectedURL: URL, prefix: String) throws -> URL {
        let fm = FileManager.default
        #if os(iOS)
        let hasScopedAccess = selectedURL.startAccessingSecurityScopedResource()
        defer {
            if hasScopedAccess {
                selectedURL.stopAccessingSecurityScopedResource()
            }
        }
        #endif

        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: selectedURL.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            throw NSError(
                domain: "Fricu.VideoImport",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey: L10n.choose(
                        simplifiedChinese: "所选文件不可用，请重新选择视频文件。",
                        english: "Selected file is unavailable. Choose another video file."
                    )
                ]
            )
        }

        let destinationDirectory = try VideoWorkspaceDirectoryResolver().resolve(kind: .imports)
        let originalName = selectedURL.deletingPathExtension().lastPathComponent
        let cleanedBase = sanitizeImportedFileName(originalName.isEmpty ? "video" : originalName)
        let ext = selectedURL.pathExtension.isEmpty ? "mp4" : selectedURL.pathExtension
        let stamp = DateFormatter.fricuCompactTimestamp.string(from: Date())
        let destinationURL = destinationDirectory
            .appendingPathComponent("\(prefix)-\(cleanedBase)-\(stamp).\(ext)", isDirectory: false)

        if fm.fileExists(atPath: destinationURL.path) {
            try fm.removeItem(at: destinationURL)
        }
        do {
            try fm.copyItem(at: selectedURL, to: destinationURL)
            return destinationURL
        } catch {
            throw NSError(
                domain: "Fricu.VideoImport",
                code: 2,
                userInfo: [
                    NSLocalizedDescriptionKey: L10n.choose(
                        simplifiedChinese: "复制视频到 App 目录失败：\(error.localizedDescription)",
                        english: "Failed to copy video into app directory: \(error.localizedDescription)"
                    )
                ]
            )
        }
    }

    private func sanitizeImportedFileName(_ value: String) -> String {
        let invalid = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let pieces = value.components(separatedBy: invalid)
        let normalized = pieces.joined(separator: "_").trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? "video" : normalized
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
                let guidance = await qualityProbeService.evaluateCaptureGuidance(for: url)
                await MainActor.run {
                    captureGuidanceByView[view] = guidance
                }
            }
        } else {
            captureGuidanceByView.removeValue(forKey: view)
        }
    }

    @ViewBuilder
    private func fittingResultTabContent() -> some View {
        switch selectedFittingResultTab {
        case .overview:
            fittingResultOverviewTab()
        case .metrics:
            fittingResultMetricsTab()
        case .suggestions:
            fittingResultSuggestionsTab()
        case .evidence:
            fittingResultEvidenceTab()
        }
    }

    @ViewBuilder
    private func fittingResultOverviewTab() -> some View {
        let summary = selectedFittingResultOverviewSummary
        VideoFittingResultSectionCard(
            title: L10n.choose(simplifiedChinese: "核心结论", english: "Core Conclusion"),
            subtitle: L10n.choose(simplifiedChinese: "先看这里，快速了解当前机位最重要的判断。", english: "Start here for the most important conclusion of the current view.")
        ) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(summary.headline)
                            .font(.title3.weight(.bold))
                        Text(summary.detail)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    VideoFittingResultBadge(
                        text: summary.riskTitle,
                        tint: fittingResultToneColor(summary.tone)
                    )
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.choose(simplifiedChinese: "风险提示", english: "Risk"))
                        .font(.caption.weight(.semibold))
                    Text(summary.riskDetail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !summary.availableConclusions.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L10n.choose(simplifiedChinese: "当前可输出结论", english: "Available Conclusions"))
                            .font(.caption.weight(.semibold))
                        flowLayout(tags: summary.availableConclusions, tint: fittingResultToneColor(summary.tone))
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.choose(simplifiedChinese: "推荐下一步动作", english: "Recommended Next Actions"))
                        .font(.caption.weight(.semibold))
                    if summary.nextActions.isEmpty {
                        Text(L10n.choose(simplifiedChinese: "暂无额外动作。", english: "No extra action is needed right now."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(summary.nextActions.enumerated()), id: \.offset) { _, action in
                            Text("• \(action)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }

    private func fittingResultMetricsTab() -> some View {
        guard let result = selectedJointAngleResult else {
            return AnyView(fittingResultEmptyState(for: .metrics))
        }

        return AnyView(VStack(alignment: .leading, spacing: 12) {
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

            VideoFittingResultSectionCard(
                title: L10n.choose(simplifiedChinese: "结果元信息", english: "Result Metadata"),
                subtitle: L10n.choose(simplifiedChinese: "先确认当前结果来自哪个机位、模型和样本范围。", english: "Confirm the source view, model, and sample range first.")
            ) {
                Text(
                    L10n.choose(
                        simplifiedChinese: "视角: \(result.resolvedView.displayName) · 模型: \(modelText) · 主侧: \(result.dominantSide.displayName) · 有效帧 \(result.analyzedFrameCount)/\(result.targetFrameCount) · 视频时长 \(durationText)s",
                        english: "View: \(result.resolvedView.displayName) · model: \(modelText) · dominant side: \(result.dominantSide.displayName) · valid frames \(result.analyzedFrameCount)/\(result.targetFrameCount) · duration \(durationText)s"
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

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

            switch result.resolvedView {
            case .side:
                if !result.sideCheckpoints.isEmpty {
                    VideoFittingResultSectionCard(
                        title: L10n.choose(simplifiedChinese: "侧视关键点", english: "Side Checkpoints"),
                        subtitle: L10n.choose(simplifiedChinese: "0 / 3 / 6 / 9 点的关节快照。", english: "Joint snapshots at 0 / 3 / 6 / 9 o'clock.")
                    ) {
                        HStack(spacing: 8) {
                            ForEach(result.sideCheckpoints) { snapshot in
                                sideCheckpointCard(snapshot)
                            }
                        }
                    }
                }
                if let cadenceSummary = result.cadenceSummary {
                    VideoFittingResultSectionCard(
                        title: L10n.choose(simplifiedChinese: "踏频周期与 BDC", english: "Cadence Cycles and BDC"),
                        subtitle: L10n.choose(simplifiedChinese: "用于判断节奏稳定性、BDC 膝角与座高区间。", english: "Used to assess cadence stability, BDC knee angle, and saddle range.")
                    ) {
                        VStack(alignment: .leading, spacing: 10) {
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
                                Text(
                                    L10n.choose(
                                        simplifiedChinese: "座高建议区间：目标 BDC 膝角 \(String(format: "%.0f-%.0f°", recommendation.targetKneeAngleMinDeg, recommendation.targetKneeAngleMaxDeg))。当前 \(String(format: "%.1f°", recommendation.meanBDCKneeAngleDeg))，建议\(saddleAdjustmentText(recommendation.direction)) \(String(format: "%.0f-%.0f mm", recommendation.suggestedAdjustmentMinMM, recommendation.suggestedAdjustmentMaxMM))。",
                                        english: "Saddle recommendation: target BDC knee angle \(String(format: "%.0f-%.0f°", recommendation.targetKneeAngleMinDeg, recommendation.targetKneeAngleMaxDeg)). Current \(String(format: "%.1f°", recommendation.meanBDCKneeAngleDeg)); \(saddleAdjustmentText(recommendation.direction)) by \(String(format: "%.0f-%.0f mm", recommendation.suggestedAdjustmentMinMM, recommendation.suggestedAdjustmentMaxMM))."
                                    )
                                )
                                .font(.caption)
                                .foregroundStyle(saddleAdjustmentColor(recommendation.direction))
                            }
                        }
                    }
                }
            case .front:
                if let alignment = result.frontAlignment {
                    VideoFittingResultSectionCard(
                        title: L10n.choose(simplifiedChinese: "前视对位", english: "Front Alignment"),
                        subtitle: L10n.choose(simplifiedChinese: "主要看膝 / 踝 / 足尖与中线关系。", english: "Focus on knee / ankle / toe alignment to the centerline.")
                    ) {
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
                }
                if let trajectory = result.frontTrajectory {
                    VideoFittingResultSectionCard(
                        title: L10n.choose(simplifiedChinese: "前视轨迹", english: "Front Trajectory"),
                        subtitle: frontTrajectorySummary(trajectory)
                    ) {
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
                    }
                }
            case .rear:
                VideoFittingResultSectionCard(
                    title: L10n.choose(simplifiedChinese: "后视稳定性", english: "Rear Stability"),
                    subtitle: result.rearStability.map { rearStabilitySummary(stability: $0, pelvic: result.rearPelvic, coordination: result.rearCoordination) }
                        ?? L10n.choose(simplifiedChinese: "用于判断盆骨稳定、重心漂移与顺拐风险。", english: "Used to assess pelvic stability, center-of-mass drift, and crossover risk.")
                ) {
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
                }
            case .auto:
                EmptyView()
            }
        })
    }

    @ViewBuilder
    private func fittingResultSuggestionsTab() -> some View {
        let summary = selectedFittingResultOverviewSummary

        VStack(alignment: .leading, spacing: 12) {
            VideoFittingResultSectionCard(
                title: L10n.choose(simplifiedChinese: "建议优先级", english: "Suggested Next Steps"),
                subtitle: L10n.choose(simplifiedChinese: "把调整动作写成能直接执行的步骤。", english: "Turn the fitting output into concrete actions.")
            ) {
                if summary.nextActions.isEmpty {
                    Text(L10n.choose(simplifiedChinese: "暂无建议，先完成分析。", english: "No suggestion yet. Complete analysis first."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(summary.nextActions.enumerated()), id: \.offset) { index, action in
                        Text("\(index + 1). \(action)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            if let result = selectedJointAngleResult, !result.adjustmentPlan.isEmpty {
                adjustmentDecisionSection(result.adjustmentPlan)
            } else {
                VideoFittingResultSectionCard(
                    title: L10n.choose(simplifiedChinese: "动作调整建议", english: "Adjustment Suggestions"),
                    subtitle: L10n.choose(simplifiedChinese: "真实分析结果接入后，这里会显示座高、前后位置等建议。", english: "Real analysis will surface saddle height, setback, and other recommendations here.")
                ) {
                    Text(L10n.choose(simplifiedChinese: "当前没有可执行调整建议。", english: "No executable adjustment suggestion is available yet."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let result = selectedJointAngleResult, !result.fittingHints.isEmpty {
                VideoFittingResultSectionCard(
                    title: L10n.choose(simplifiedChinese: "精度与拍摄提示", english: "Precision and Capture Hints"),
                    subtitle: L10n.choose(simplifiedChinese: "这些提示帮助你判断是否需要补标记点或重拍。", english: "These hints help you decide whether to add markers or retake the video.")
                ) {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(result.fittingHints.enumerated()), id: \.offset) { _, hint in
                            Text("• \(hint)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }

    private func fittingResultEvidenceTab() -> some View {
        guard let result = selectedJointAngleResult else {
            return AnyView(fittingResultEmptyState(for: .evidence))
        }

        return AnyView(VStack(alignment: .leading, spacing: 12) {
            VideoFittingResultSectionCard(
                title: L10n.choose(simplifiedChinese: "关键帧与叠加线", english: "Keyframes and Overlays"),
                subtitle: L10n.choose(simplifiedChinese: "这里保留证据位，后续可平滑接入真实关键帧和叠加线。", english: "Evidence placeholders live here and can be smoothly replaced with real keyframes and overlays.")
            ) {
                HStack(spacing: 10) {
                    fittingEvidencePlaceholderCard(
                        title: L10n.choose(simplifiedChinese: "关键帧", english: "Keyframes"),
                        detail: L10n.choose(simplifiedChinese: "将展示代表性帧位与时刻。", english: "Will show representative frames and timestamps.")
                    )
                    fittingEvidencePlaceholderCard(
                        title: L10n.choose(simplifiedChinese: "骨架叠加线", english: "Skeleton Overlay"),
                        detail: L10n.choose(simplifiedChinese: "将展示骨架对位和角度叠加。", english: "Will show skeleton alignment and angle overlays.")
                    )
                    fittingEvidencePlaceholderCard(
                        title: L10n.choose(simplifiedChinese: "置信度", english: "Confidence"),
                        detail: selectedJointRecognitionQualitySummary.confidenceText
                    )
                }
            }

            if result.resolvedView == .side && !result.sideCheckpoints.isEmpty {
                VideoFittingResultSectionCard(
                    title: L10n.choose(simplifiedChinese: "关键点证据", english: "Checkpoint Evidence"),
                    subtitle: L10n.choose(simplifiedChinese: "0 / 3 / 6 / 9 点位快照可作为关键证据。", english: "0 / 3 / 6 / 9 checkpoints serve as key evidence.")
                ) {
                    HStack(spacing: 8) {
                        ForEach(result.sideCheckpoints) { snapshot in
                            sideCheckpointCard(snapshot)
                        }
                    }
                }
            }

            VideoFittingResultSectionCard(
                title: L10n.choose(simplifiedChinese: "角度证据曲线", english: "Angle Evidence Chart"),
                subtitle: L10n.choose(simplifiedChinese: "展示本次识别生成的膝角 / 髋角时序曲线。", english: "Shows knee and hip time-series curves produced by this recognition run.")
            ) {
                fittingEvidenceChart(result: result)
            }
        })
    }

    private func fittingResultEmptyState(for tab: VideoFittingResultTab) -> some View {
        let title: String
        let detail: String
        switch tab {
        case .overview:
            title = L10n.choose(simplifiedChinese: "等待核心结论", english: "Awaiting overview")
            detail = L10n.choose(simplifiedChinese: "先完成合规检查和骨点识别，这里会优先展示结论与风险。", english: "Complete compliance and skeleton recognition first. This tab will highlight conclusions and risks.")
        case .metrics:
            title = L10n.choose(simplifiedChinese: "等待指标结果", english: "Awaiting metrics")
            detail = L10n.choose(simplifiedChinese: "识别完成后，这里会显示角度、轨迹和稳定性指标。", english: "Metrics, trajectories, and stability outputs appear here after recognition.")
        case .suggestions:
            title = L10n.choose(simplifiedChinese: "等待动作建议", english: "Awaiting suggestions")
            detail = L10n.choose(simplifiedChinese: "结果产出后，这里会整理为可执行的调整建议。", english: "Actionable fitting suggestions appear here after analysis.")
        case .evidence:
            title = L10n.choose(simplifiedChinese: "等待证据内容", english: "Awaiting evidence")
            detail = L10n.choose(simplifiedChinese: "关键帧、叠加线和置信度证据会显示在这里。", english: "Keyframes, overlays, and confidence evidence will appear here.")
        }

        return VideoFittingResultEmptyStateCard(
            title: title,
            detail: detail,
            footnote: L10n.choose(
                simplifiedChinese: "当前可先在上方完成合规检查与骨点识别。",
                english: "You can complete compliance and skeleton recognition above first."
            )
        )
    }

    @ViewBuilder
    private func fittingEvidencePlaceholderCard(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
            Spacer(minLength: 0)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
        .padding(12)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private func fittingEvidenceChart(result: VideoJointAngleAnalysisResult) -> some View {
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
    private func flowLayout(tags: [String], tint: Color) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 8, alignment: .leading)], alignment: .leading, spacing: 8) {
            ForEach(tags, id: \.self) { tag in
                Text(tag)
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(tint.opacity(0.10), in: Capsule())
                    .foregroundStyle(tint)
            }
        }
    }

    private func fittingResultToneColor(_ tone: VideoFittingResultRiskTone) -> Color {
        switch tone {
        case .low:
            return .green
        case .moderate:
            return .orange
        case .high:
            return .red
        case .pending:
            return .secondary
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
                    Text(L10n.choose(simplifiedChinese: "侧视角关键点（0/3/6/9 点）", english: "Side View Checkpoints (0/3/6/9)"))
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

    private func uiFlowState(for state: VideoFittingStepState) -> VideoFittingFlowState {
        switch state {
        case .pending:
            return .pending
        case .running:
            return .running
        case .blocked:
            return .blocked
        case .ready:
            return .ready
        case .done:
            return .done
        }
    }

    private func refreshAllCaptureGuidance() {
        for view in supportedCyclingViews {
            guard let url = sourceVideoURL(for: view) else {
                captureGuidanceByView.removeValue(forKey: view)
                continue
            }
            Task {
                let guidance = await qualityProbeService.evaluateCaptureGuidance(for: url)
                await MainActor.run {
                    captureGuidanceByView[view] = guidance
                }
            }
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
