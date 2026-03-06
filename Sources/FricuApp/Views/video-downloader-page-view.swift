import SwiftUI

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

/// A dedicated page for preparing YouTube and Instagram video download jobs.
struct VideoDownloaderPageView: View {
    @State private var sourceURLText = ""
    private let validator = VideoDownloadRequestValidator()

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

                        validationMessage

                        HStack(spacing: 12) {
                            Button(L10n.choose(simplifiedChinese: "开始下载", english: "Start Download")) {
                                // Reserved for future downloader integration.
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(!isDownloadReady)

                            Button(L10n.choose(simplifiedChinese: "清空", english: "Clear")) {
                                sourceURLText = ""
                            }
                            .buttonStyle(.bordered)
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
                            value: isDownloadReady
                                ? L10n.choose(simplifiedChinese: "可执行", english: "Ready")
                                : L10n.choose(simplifiedChinese: "等待有效链接", english: "Waiting for valid link")
                        )
                    }
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(20)
        }
    }

    /// Indicates whether the current input is ready for a download action.
    private var isDownloadReady: Bool {
        if case .valid = validationResult {
            return true
        }
        return false
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
