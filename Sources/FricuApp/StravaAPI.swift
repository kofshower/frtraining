import Foundation

enum StravaAPIError: Error, LocalizedError {
    case missingAccessToken
    case missingRefreshConfig
    case missingClientConfig
    case oauthTimeout
    case invalidOAuthRedirectURI
    case oauthStateMismatch
    case oauthMissingCode
    case oauthDenied(String)
    case badResponse
    case requestFailed(Int, String)
    case malformedPayload

    var errorDescription: String? {
        switch self {
        case .missingAccessToken:
            return "Strava access token 缺失，请在 Settings 中填写。"
        case .missingRefreshConfig:
            return "Strava refresh 配置不完整（client id/secret/refresh token）。"
        case .missingClientConfig:
            return "Strava OAuth 配置不完整（client id/client secret）。"
        case .oauthTimeout:
            return "Strava OAuth 超时，请重试。"
        case .invalidOAuthRedirectURI:
            return "Strava OAuth 回调地址无效，请使用 http://127.0.0.1:端口/callback。"
        case .oauthStateMismatch:
            return "Strava OAuth state 校验失败，请重试。"
        case .oauthMissingCode:
            return "Strava OAuth 回调未返回授权码。"
        case let .oauthDenied(message):
            return "Strava OAuth 被拒绝：\(message)"
        case .badResponse:
            return "Strava 返回了无效响应。"
        case let .requestFailed(code, body):
            return "Strava 请求失败 (\(code)): \(body)"
        case .malformedPayload:
            return "Strava 返回了无法解析的数据。"
        }
    }
}

struct StravaAuthUpdate {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Int?
}

final class StravaAPIClient {
    private let session: URLSession
    private let authorizeURL = URL(string: "https://www.strava.com/oauth/authorize")!
    private let authURL = URL(string: "https://www.strava.com/oauth/token")!
    private let apiBase = URL(string: "https://www.strava.com/api/v3")!
    static let defaultOAuthScopes = [
        "read",
        "read_all",
        "activity:read_all",
        "profile:read_all",
        "activity:write"
    ]

    init(session: URLSession = .shared) {
        self.session = session
    }

    func buildAuthorizationURL(
        clientID: String,
        redirectURI: String,
        state: String,
        scopes: [String] = StravaAPIClient.defaultOAuthScopes
    ) -> URL? {
        let id = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return nil }

        var components = URLComponents(url: authorizeURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: id),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "approval_prompt", value: "auto"),
            URLQueryItem(name: "scope", value: scopes.joined(separator: ",")),
            URLQueryItem(name: "state", value: state)
        ]
        return components?.url
    }

    func ensureAccessToken(profile: AthleteProfile) async throws -> StravaAuthUpdate {
        let now = Int(Date().timeIntervalSince1970)
        let hasRefreshConfig = hasRefreshConfig(profile)
        let sanitizedAccessToken = normalizeAccessToken(profile.stravaAccessToken)
        let sanitizedRefreshToken = profile.stravaRefreshToken.trimmingCharacters(in: .whitespacesAndNewlines)

        if hasRefreshConfig {
            let accessValid = !sanitizedAccessToken.isEmpty && ((profile.stravaAccessTokenExpiresAt ?? 0) > now + 120)
            if accessValid {
                return StravaAuthUpdate(
                    accessToken: sanitizedAccessToken,
                    refreshToken: sanitizedRefreshToken,
                    expiresAt: profile.stravaAccessTokenExpiresAt
                )
            }

            return try await refreshToken(
                clientID: profile.stravaClientID.trimmingCharacters(in: .whitespacesAndNewlines),
                clientSecret: profile.stravaClientSecret.trimmingCharacters(in: .whitespacesAndNewlines),
                refreshToken: sanitizedRefreshToken
            )
        }

        guard !sanitizedAccessToken.isEmpty else {
            throw StravaAPIError.missingRefreshConfig
        }

        return StravaAuthUpdate(
            accessToken: sanitizedAccessToken,
            refreshToken: sanitizedRefreshToken,
            expiresAt: profile.stravaAccessTokenExpiresAt
        )
    }

    func forceRefreshAccessToken(profile: AthleteProfile) async throws -> StravaAuthUpdate {
        guard hasRefreshConfig(profile) else {
            throw StravaAPIError.missingRefreshConfig
        }

        return try await refreshToken(
            clientID: profile.stravaClientID.trimmingCharacters(in: .whitespacesAndNewlines),
            clientSecret: profile.stravaClientSecret.trimmingCharacters(in: .whitespacesAndNewlines),
            refreshToken: profile.stravaRefreshToken.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    func exchangeAuthorizationCode(
        clientID: String,
        clientSecret: String,
        code: String,
        redirectURI: String
    ) async throws -> StravaAuthUpdate {
        let id = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        let secret = clientSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        let authCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty, !secret.isEmpty else {
            throw StravaAPIError.missingClientConfig
        }
        guard !authCode.isEmpty else {
            throw StravaAPIError.oauthMissingCode
        }

        var req = URLRequest(url: authURL)
        req.httpMethod = "POST"
        req.timeoutInterval = 45
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        let body = [
            "client_id": id,
            "client_secret": secret,
            "grant_type": "authorization_code",
            "code": authCode,
            "redirect_uri": redirectURI
        ]
        .map { "\($0.key)=\($0.value.urlQueryEncoded)" }
        .joined(separator: "&")
        req.httpBody = body.data(using: .utf8)

        let data = try await send(req, debugLabel: "POST /oauth/token (authorization_code)")
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw StravaAPIError.malformedPayload
        }
        guard let access = JSONValue.string(json["access_token"]), !access.isEmpty else {
            throw StravaAPIError.malformedPayload
        }
        return StravaAuthUpdate(
            accessToken: access,
            refreshToken: JSONValue.string(json["refresh_token"]) ?? "",
            expiresAt: JSONValue.int(json["expires_at"])
        )
    }

    func fetchActivities(
        accessToken: String,
        oldest: Date,
        newest: Date,
        profile: AthleteProfile,
        includeDetails: Bool = true
    ) async throws -> [Activity] {
        guard !accessToken.isEmpty else {
            throw StravaAPIError.missingAccessToken
        }

        let after = Int(oldest.timeIntervalSince1970)
        let before = Int(newest.timeIntervalSince1970)
        var page = 1
        let perPage = 200
        var results: [Activity] = []
        var detailFetchDisabled = !includeDetails
        var detailCache: [String: [String: Any]] = [:]

        while true {
            var components = URLComponents(url: apiBase.appending(path: "/athlete/activities"), resolvingAgainstBaseURL: false)
            components?.queryItems = [
                URLQueryItem(name: "after", value: String(after)),
                URLQueryItem(name: "before", value: String(before)),
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "per_page", value: String(perPage))
            ]

            var req = URLRequest(url: components?.url ?? apiBase)
            req.httpMethod = "GET"
            req.timeoutInterval = 45
            req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            req.setValue("application/json", forHTTPHeaderField: "Accept")

            let data = try await send(req, debugLabel: "GET /api/v3/athlete/activities")
            guard let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                throw StravaAPIError.malformedPayload
            }

            var mapped: [Activity] = []
            mapped.reserveCapacity(rows.count)

            for row in rows {
                guard let id = JSONValue.string(row["id"]) else { continue }

                var detail: [String: Any]?
                if !detailFetchDisabled {
                    if let cached = detailCache[id] {
                        detail = cached
                    } else {
                        do {
                            let fetched = try await fetchActivityDetail(accessToken: accessToken, activityID: id)
                            detailCache[id] = fetched
                            detail = fetched
                        } catch let StravaAPIError.requestFailed(code, _) where code == 429 {
                            // Respect rate limit: keep summary pull usable.
                            detailFetchDisabled = true
                        } catch {
                            // Ignore per-activity detail failures and keep summary pull usable.
                        }
                    }
                }

                let date = DateParsers.parseISO8601(JSONValue.string(field("start_date_local", detail: detail, summary: row)) ?? "")
                    ?? DateParsers.parseISO8601(JSONValue.string(field("start_date", detail: detail, summary: row)) ?? "")
                    ?? Date()

                let sport = mapSport(JSONValue.string(field("sport_type", detail: detail, summary: row))
                    ?? JSONValue.string(field("type", detail: detail, summary: row))
                    ?? "")
                let durationSec = max(
                    1,
                    JSONValue.int(field("moving_time", detail: detail, summary: row))
                        ?? JSONValue.int(field("elapsed_time", detail: detail, summary: row))
                        ?? 0
                )
                let distanceKm = max(0, (JSONValue.double(field("distance", detail: detail, summary: row)) ?? 0) / 1000.0)
                let avgHR = JSONValue.int(field("average_heartrate", detail: detail, summary: row))
                let avgPower = JSONValue.int(field("average_watts", detail: detail, summary: row))
                let np = JSONValue.int(field("weighted_average_watts", detail: detail, summary: row))
                let name = JSONValue.string(field("name", detail: detail, summary: row)) ?? "Strava Activity"
                let tss = TSSEstimator.estimate(
                    durationSec: durationSec,
                    sport: sport,
                    avgPower: avgPower,
                    normalizedPower: np,
                    avgHeartRate: avgHR,
                    profile: profile,
                    date: date
                )

                let mergedPayload = mergedPayloadJSON(summary: row, detail: detail)
                let note = composeActivityNotes(name: name, summary: row, detail: detail)

                mapped.append(
                    Activity(
                        date: date,
                        sport: sport,
                        durationSec: durationSec,
                        distanceKm: distanceKm,
                        tss: tss,
                        normalizedPower: np ?? avgPower,
                        avgHeartRate: avgHR,
                        notes: note,
                        externalID: "strava:\(id)",
                        platformPayloadJSON: mergedPayload
                    )
                )
            }

            results.append(contentsOf: mapped)

            if rows.count < perPage {
                break
            }
            page += 1
            if page > 20 {
                break
            }
        }

        return results
    }

    func uploadActivityFile(
        accessToken: String,
        fileData: Data,
        fileExtension: String,
        name: String,
        description: String,
        externalID: String
    ) async throws -> String {
        guard !accessToken.isEmpty else {
            throw StravaAPIError.missingAccessToken
        }

        let boundary = "Boundary-\(UUID().uuidString)"
        var req = URLRequest(url: apiBase.appending(path: "/uploads"))
        req.httpMethod = "POST"
        req.timeoutInterval = 60
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let dataType = normalizedDataType(fileExtension)
        req.httpBody = buildUploadBody(
            boundary: boundary,
            fileData: fileData,
            fileExtension: dataType,
            name: name,
            description: description,
            externalID: externalID
        )

        let data: Data
        do {
            data = try await send(req)
        } catch let StravaAPIError.requestFailed(code, body) where code == 422 {
            if let duplicateID = parseDuplicateActivityID(body) {
                return "strava:\(duplicateID)"
            }
            throw StravaAPIError.requestFailed(code, body)
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw StravaAPIError.malformedPayload
        }

        if let activityID = JSONValue.string(json["activity_id"]) {
            return "strava:\(activityID)"
        }

        guard let uploadID = JSONValue.int(json["id"]) else {
            throw StravaAPIError.malformedPayload
        }

        let activityID = try await pollUploadUntilReady(accessToken: accessToken, uploadID: uploadID)
        return activityID.map { "strava:\($0)" } ?? "strava:upload:\(uploadID)"
    }

    private func fetchActivityDetail(accessToken: String, activityID: String) async throws -> [String: Any] {
        var components = URLComponents(url: apiBase.appending(path: "/activities/\(activityID)"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "include_all_efforts", value: "true")]

        var req = URLRequest(url: components?.url ?? apiBase.appending(path: "/activities/\(activityID)"))
        req.httpMethod = "GET"
        req.timeoutInterval = 45
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        let data = try await send(req, debugLabel: "POST /oauth/token (refresh_token)")
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw StravaAPIError.malformedPayload
        }
        return json
    }

    private func field(_ key: String, detail: [String: Any]?, summary: [String: Any]) -> Any? {
        if let detail, let value = detail[key] {
            return value
        }
        return summary[key]
    }

    private func composeActivityNotes(
        name: String,
        summary: [String: Any],
        detail: [String: Any]?
    ) -> String {
        let description = JSONValue.string(field("description", detail: detail, summary: summary))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let location = JSONValue.string(field("location_city", detail: detail, summary: summary))
            ?? JSONValue.string(field("location_country", detail: detail, summary: summary))
        let trainer = parseBool(field("trainer", detail: detail, summary: summary))
        let commute = parseBool(field("commute", detail: detail, summary: summary))
        let privateRide = parseBool(field("private", detail: detail, summary: summary))
        let kilojoules = JSONValue.double(field("kilojoules", detail: detail, summary: summary))
        let calories = JSONValue.double(field("calories", detail: detail, summary: summary))
        let elevation = JSONValue.double(field("total_elevation_gain", detail: detail, summary: summary))

        var tags: [String] = []
        if let trainer, trainer { tags.append("trainer") }
        if let commute, commute { tags.append("commute") }
        if let privateRide, privateRide { tags.append("private") }
        if let location, !location.isEmpty { tags.append(location) }
        if let kj = kilojoules, kj > 0 { tags.append("kJ \(Int(kj.rounded()))") }
        if let cal = calories, cal > 0 { tags.append("kcal \(Int(cal.rounded()))") }
        if let elev = elevation, elev > 0 { tags.append("elev \(Int(elev.rounded()))m") }
        if detail != nil { tags.append("detail") }

        var lines: [String] = [name]
        if let description, !description.isEmpty {
            lines.append(description)
        }
        if !tags.isEmpty {
            lines.append(tags.joined(separator: " · "))
        }
        return lines.joined(separator: "\n")
    }

    private func mergedPayloadJSON(summary: [String: Any], detail: [String: Any]?) -> String? {
        var merged = summary
        if let detail {
            for (key, value) in detail {
                merged[key] = value
            }
        }
        guard JSONSerialization.isValidJSONObject(merged),
              let data = try? JSONSerialization.data(withJSONObject: merged, options: [.sortedKeys])
        else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private func parseBool(_ value: Any?) -> Bool? {
        switch value {
        case let bool as Bool:
            return bool
        case let int as Int:
            return int != 0
        case let num as NSNumber:
            return num.intValue != 0
        case let str as String:
            let lower = str.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if ["1", "true", "yes", "y"].contains(lower) { return true }
            if ["0", "false", "no", "n"].contains(lower) { return false }
            return nil
        default:
            return nil
        }
    }

    private func refreshToken(clientID: String, clientSecret: String, refreshToken: String) async throws -> StravaAuthUpdate {
        var req = URLRequest(url: authURL)
        req.httpMethod = "POST"
        req.timeoutInterval = 45
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        let body = [
            "client_id": clientID,
            "client_secret": clientSecret,
            "grant_type": "refresh_token",
            "refresh_token": refreshToken
        ]
        .map { "\($0.key)=\($0.value.urlQueryEncoded)" }
        .joined(separator: "&")

        req.httpBody = body.data(using: .utf8)

        let data = try await send(req, debugLabel: "POST /oauth/token (refresh_token)")
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw StravaAPIError.malformedPayload
        }

        guard let access = JSONValue.string(json["access_token"]), !access.isEmpty else {
            throw StravaAPIError.malformedPayload
        }

        return StravaAuthUpdate(
            accessToken: access,
            refreshToken: JSONValue.string(json["refresh_token"]) ?? refreshToken,
            expiresAt: JSONValue.int(json["expires_at"])
        )
    }

    private func send(_ request: URLRequest, debugLabel: String? = nil) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw StravaAPIError.badResponse
        }

        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            if let diagnostic = diagnosticMessage(for: request, label: debugLabel, responseBody: body) {
                throw StravaAPIError.requestFailed(http.statusCode, diagnostic)
            }
            throw StravaAPIError.requestFailed(http.statusCode, body)
        }

        return data
    }

    private func diagnosticMessage(for request: URLRequest, label: String?, responseBody: String) -> String? {
        var fields = Set<String>()
        if let items = URLComponents(url: request.url ?? apiBase, resolvingAgainstBaseURL: false)?.queryItems {
            for item in items where !item.name.isEmpty {
                fields.insert(item.name)
            }
        }
        if
            let body = request.httpBody,
            let bodyString = String(data: body, encoding: .utf8),
            let contentType = request.value(forHTTPHeaderField: "Content-Type")?.lowercased(),
            contentType.contains("application/x-www-form-urlencoded")
        {
            for pair in bodyString.split(separator: "&") {
                let key = pair.split(separator: "=", maxSplits: 1).first?.removingPercentEncoding ?? ""
                if !key.isEmpty {
                    fields.insert(key)
                }
            }
        }
        guard !fields.isEmpty || !(label?.isEmpty ?? true) else {
            return nil
        }
        let sortedFields = fields.sorted().joined(separator: ",")
        let requestLine = "request=\(label ?? request.httpMethod ?? "HTTP") fields=[\(sortedFields)]"
        return "\(requestLine); response=\(responseBody)"
    }

    private func pollUploadUntilReady(accessToken: String, uploadID: Int) async throws -> String? {
        var attempts = 0
        while attempts < 8 {
            let status = try await fetchUploadStatus(accessToken: accessToken, uploadID: uploadID)
            if let activityID = JSONValue.string(status["activity_id"]) {
                return activityID
            }

            if let error = JSONValue.string(status["error"]), !error.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if let duplicateID = parseDuplicateActivityID(error) {
                    return String(duplicateID)
                }
                throw StravaAPIError.requestFailed(422, error)
            }

            let uploadStatus = JSONValue.string(status["status"])?.lowercased() ?? ""
            if uploadStatus.contains("ready") || uploadStatus.contains("complete") {
                return JSONValue.string(status["activity_id"])
            }

            attempts += 1
            try await Task.sleep(nanoseconds: 2_000_000_000)
        }
        return nil
    }

    private func fetchUploadStatus(accessToken: String, uploadID: Int) async throws -> [String: Any] {
        var req = URLRequest(url: apiBase.appending(path: "/uploads/\(uploadID)"))
        req.httpMethod = "GET"
        req.timeoutInterval = 45
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let data = try await send(req)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw StravaAPIError.malformedPayload
        }
        return json
    }

    private func buildUploadBody(
        boundary: String,
        fileData: Data,
        fileExtension: String,
        name: String,
        description: String,
        externalID: String
    ) -> Data {
        func field(_ key: String, _ value: String) -> Data {
            var data = Data()
            data.append("--\(boundary)\r\n".data(using: .utf8)!)
            data.append("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n".data(using: .utf8)!)
            data.append("\(value)\r\n".data(using: .utf8)!)
            return data
        }

        var body = Data()
        body.append(field("data_type", fileExtension.lowercased()))
        body.append(field("name", name))
        body.append(field("description", description))
        body.append(field("external_id", externalID))

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"activity.\(fileExtension)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        return body
    }

    private func normalizedDataType(_ input: String) -> String {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch value {
        case "fit", "fit.gz", "tcx", "tcx.gz", "gpx", "gpx.gz":
            return value
        default:
            return "tcx"
        }
    }

    private func parseDuplicateActivityID(_ message: String) -> Int? {
        let lower = message.lowercased()
        guard lower.contains("duplicate") else {
            return nil
        }

        if let regex = try? NSRegularExpression(pattern: #"/activities/(\d+)"#) {
            let range = NSRange(location: 0, length: lower.utf16.count)
            if
                let match = regex.firstMatch(in: lower, options: [], range: range),
                let idRange = Range(match.range(at: 1), in: lower)
            {
                return Int(lower[idRange])
            }
        }

        let numbers = lower
            .split { !$0.isNumber }
            .compactMap { Int($0) }
            .filter { $0 >= 100_000 }
        return numbers.last
    }

    private func mapSport(_ raw: String) -> SportType {
        let value = raw.lowercased()
        if value.contains("run") { return .running }
        if value.contains("swim") { return .swimming }
        if value.contains("ride") || value.contains("bike") || value.contains("cycle") { return .cycling }
        return .strength
    }

    private func hasRefreshConfig(_ profile: AthleteProfile) -> Bool {
        !profile.stravaClientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !profile.stravaClientSecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !profile.stravaRefreshToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func normalizeAccessToken(_ token: String) -> String {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        let prefix = "bearer "
        if trimmed.lowercased().hasPrefix(prefix) {
            return String(trimmed.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return trimmed
    }
}

private extension String {
    var urlQueryEncoded: String {
        addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.subtracting(CharacterSet(charactersIn: "+&="))) ?? self
    }
}
