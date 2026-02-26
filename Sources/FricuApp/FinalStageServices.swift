import Foundation

enum WellnessConnectorError: Error, LocalizedError {
    case missingAccessToken(String)
    case badURL
    case requestFailed(Int, String)
    case malformedResponse

    var errorDescription: String? {
        switch self {
        case let .missingAccessToken(provider):
            return "\(provider) access token is missing."
        case .badURL:
            return "Bad connector URL."
        case let .requestFailed(code, body):
            return "Connector request failed (\(code)): \(body)"
        case .malformedResponse:
            return "Connector returned malformed response."
        }
    }
}

final class OuraAPIClient {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchWellness(accessToken: String, start: Date, end: Date) async throws -> [WellnessSample] {
        let token = accessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            throw WellnessConnectorError.missingAccessToken("Oura")
        }

        let startText = IntervalsDateFormatter.day.string(from: start)
        let endText = IntervalsDateFormatter.day.string(from: end)

        let sleepRows = try await fetchCollection(
            token: token,
            path: "daily_sleep",
            start: startText,
            end: endText
        )
        let readinessRows = try await fetchCollection(
            token: token,
            path: "daily_readiness",
            start: startText,
            end: endText
        )

        var byDay: [Date: WellnessSample] = [:]

        for row in sleepRows {
            guard let day = parseDay(JSONValue.string(row["day"]) ?? JSONValue.string(row["date"])) else { continue }
            var sample = byDay[day] ?? WellnessSample(date: day)

            if let hrv = JSONValue.double(row["average_hrv"]) ?? JSONValue.double(row["hrv"]) {
                sample.hrv = hrv
            }
            if let rhr = JSONValue.double(row["lowest_heart_rate"]) ?? JSONValue.double(row["resting_heart_rate"]) {
                sample.restingHR = rhr
            }
            if let sleepHours = parseOuraSleepHours(row: row) {
                sample.sleepHours = sleepHours
            }
            if let score = JSONValue.double(row["score"]) ?? JSONValue.double(row["sleep_score"]) {
                sample.sleepScore = score
            }
            byDay[day] = sample
        }

        for row in readinessRows {
            guard let day = parseDay(JSONValue.string(row["day"]) ?? JSONValue.string(row["date"])) else { continue }
            var sample = byDay[day] ?? WellnessSample(date: day)

            if sample.hrv == nil,
               let contributors = row["contributors"] as? [String: Any],
               let hrvBalance = JSONValue.double(contributors["hrv_balance"]) {
                sample.hrv = hrvBalance
            }
            if sample.sleepScore == nil,
               let readinessScore = JSONValue.double(row["score"]) {
                sample.sleepScore = readinessScore
            }
            byDay[day] = sample
        }

        return byDay.values.sorted { $0.date > $1.date }
    }

    private func fetchCollection(token: String, path: String, start: String, end: String) async throws -> [[String: Any]] {
        var rows: [[String: Any]] = []
        var nextToken: String?
        var page = 0

        repeat {
            guard var components = URLComponents(string: "https://api.ouraring.com/v2/usercollection/\(path)") else {
                throw WellnessConnectorError.badURL
            }

            var query: [URLQueryItem] = [
                URLQueryItem(name: "start_date", value: start),
                URLQueryItem(name: "end_date", value: end)
            ]
            if let nextToken {
                query.append(URLQueryItem(name: "next_token", value: nextToken))
            }
            components.queryItems = query

            guard let url = components.url else {
                throw WellnessConnectorError.badURL
            }

            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = 25
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")

            let data = try await sendWithRetry(request)
            guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let pageRows = root["data"] as? [[String: Any]] else {
                throw WellnessConnectorError.malformedResponse
            }

            rows.append(contentsOf: pageRows)
            nextToken = JSONValue.string(root["next_token"]) ?? JSONValue.string(root["nextToken"])
            page += 1
        } while nextToken != nil && page < 20

        return rows
    }

    private func parseDay(_ text: String?) -> Date? {
        guard let text else { return nil }
        return IntervalsDateFormatter.day.date(from: text)
    }

    private func parseOuraSleepHours(row: [String: Any]) -> Double? {
        if let sec = JSONValue.double(row["total_sleep_duration"]) {
            return max(0, sec) / 3600.0
        }
        if let ms = JSONValue.double(row["total_sleep_duration_ms"]) {
            return max(0, ms) / 3_600_000.0
        }
        if let min = JSONValue.double(row["sleep_duration"]) ?? JSONValue.double(row["sleep_duration_min"]) {
            return max(0, min) / 60.0
        }
        return nil
    }

    private func sendWithRetry(_ request: URLRequest, maxRetry: Int = 2) async throws -> Data {
        var attempt = 0
        while true {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw WellnessConnectorError.malformedResponse
            }

            if (200..<300).contains(http.statusCode) {
                return data
            }

            if (http.statusCode == 429 || (500..<600).contains(http.statusCode)), attempt < maxRetry {
                let delay: UInt64
                if let retryAfter = http.value(forHTTPHeaderField: "Retry-After"), let sec = Double(retryAfter) {
                    delay = UInt64(max(0.2, sec) * 1_000_000_000)
                } else {
                    delay = UInt64((0.5 + Double(attempt) * 0.7) * 1_000_000_000)
                }
                attempt += 1
                try await Task.sleep(nanoseconds: delay)
                continue
            }

            throw WellnessConnectorError.requestFailed(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
    }
}

enum GarminConnectAPIError: Error, LocalizedError {
    case missingAccessToken
    case requestFailed(Int, String)
    case malformedPayload
    case noUsableEndpoint([String])

    var errorDescription: String? {
        switch self {
        case .missingAccessToken:
            return "Garmin Connect access token 缺失，请在 Settings 中填写。"
        case let .requestFailed(code, body):
            return "Garmin Connect 请求失败 (\(code)): \(body)"
        case .malformedPayload:
            return "Garmin Connect 返回了无法解析的数据。"
        case let .noUsableEndpoint(errors):
            if errors.isEmpty {
                return "Garmin Connect API 不可用，请确认 token 权限或格式。"
            }
            return "Garmin Connect API 不可用：\(errors.joined(separator: " | "))"
        }
    }
}

final class GarminConnectAPIClient {
    private struct RequestHints {
        var authInput: String
        var connectCSRFToken: String?
        var preferChinaRegion: Bool
    }

    private enum AuthMode {
        case bearer(String)
        case authorization(String)
        case cookie(String)

        var key: String {
            switch self {
            case .bearer: return "Bearer"
            case .authorization: return "AuthorizationRaw"
            case .cookie: return "Cookie"
            }
        }
    }

    private let session: URLSession
    private let globalEndpointRoots = [
        "https://connectapi.garmin.com/activitylist-service/activities/search/activities",
        "https://connectapi.garmin.com/activity-service/activity/activities",
        "https://connect.garmin.com/proxy/activitylist-service/activities/search/activities",
        "https://connect.garmin.com/proxy/activity-service/activity/activities",
        "https://connect.garmin.com/modern/proxy/activitylist-service/activities/search/activities",
        "https://connect.garmin.com/modern/proxy/activity-service/activity/activities",
        "https://connect.garmin.com/activitylist-service/activities/search/activities",
        "https://connect.garmin.com/activity-service/activity/activities"
    ]
    private let chinaEndpointRoots = [
        "https://connectus.garmin.cn/gc-api/activitylist-service/activities/search/activities",
        "https://connectus.garmin.cn/gc-api/activity-service/activity/activities",
        "https://connectus.garmin.cn/activitylist-service/activities/search/activities",
        "https://connectus.garmin.cn/activity-service/activity/activities"
    ]
    private let globalWellnessRoots = [
        "https://connectapi.garmin.com/wellness-service/wellness",
        "https://connect.garmin.com/proxy/wellness-service/wellness",
        "https://connect.garmin.com/modern/proxy/wellness-service/wellness",
        "https://connect.garmin.com/wellness-service/wellness"
    ]
    private let chinaWellnessRoots = [
        "https://connectus.garmin.cn/gc-api/wellness-service/wellness",
        "https://connectus.garmin.cn/wellness-service/wellness"
    ]

    init(session: URLSession = .shared) {
        self.session = session
    }

    private var garminUserAgent: String {
        #if os(iOS)
            return "Mozilla/5.0 (iPad; CPU OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) FricuApp/1.0 Mobile/15E148 Safari/604.1"
        #else
            return "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/537.36 (KHTML, like Gecko) FricuApp/1.0 Safari/537.36"
        #endif
    }

    private var secCHUAPlatformValue: String {
        #if os(iOS)
            return "\"iOS\""
        #else
            return "\"macOS\""
        #endif
    }

    func fetchActivities(
        accessToken: String,
        connectCSRFToken: String? = nil,
        oldest: Date,
        newest: Date,
        profile: AthleteProfile
    ) async throws -> [Activity] {
        let token = accessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            throw GarminConnectAPIError.missingAccessToken
        }
        var hints = parseRequestHints(rawInput: token)
        if let explicitCSRF = connectCSRFToken?.trimmingCharacters(in: .whitespacesAndNewlines),
           !explicitCSRF.isEmpty {
            hints.connectCSRFToken = explicitCSRF
        }

        let startText = IntervalsDateFormatter.day.string(from: oldest)
        let endText = IntervalsDateFormatter.day.string(from: newest)
        let authModes = buildAuthModes(token: hints.authInput)
        let perPage = 100
        var start = 0
        var page = 0
        var pulled: [Activity] = []
        var seenExternalIDs = Set<String>()

        while page < 40 {
            let rows = try await fetchPage(
                start: start,
                limit: perPage,
                startDate: startText,
                endDate: endText,
                authModes: authModes,
                hints: hints
            )
            if rows.isEmpty {
                break
            }

            for row in rows {
                guard let activity = parseActivity(row: row, profile: profile) else { continue }
                guard activity.date >= oldest && activity.date <= newest else { continue }

                if let ext = activity.externalID {
                    if seenExternalIDs.contains(ext) { continue }
                    seenExternalIDs.insert(ext)
                }
                pulled.append(activity)
            }

            if rows.count < perPage {
                break
            }
            start += perPage
            page += 1
        }

        return pulled.sorted { $0.date > $1.date }
    }

    func fetchWellness(
        accessToken: String,
        connectCSRFToken: String? = nil,
        start: Date,
        end: Date
    ) async throws -> [WellnessSample] {
        let token = accessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            throw GarminConnectAPIError.missingAccessToken
        }

        var hints = parseRequestHints(rawInput: token)
        if let explicitCSRF = connectCSRFToken?.trimmingCharacters(in: .whitespacesAndNewlines),
           !explicitCSRF.isEmpty {
            hints.connectCSRFToken = explicitCSRF
        }
        let authModes = buildAuthModes(token: hints.authInput)
        let dates = allDatesBetween(start: start, end: end)
        if dates.isEmpty { return [] }

        var samples: [WellnessSample] = []
        for day in dates {
            let wellness = try await fetchWellnessForDay(
                day: day,
                authModes: authModes,
                hints: hints
            )
            if wellness.hrv != nil || wellness.restingHR != nil || wellness.sleepHours != nil || wellness.sleepScore != nil {
                samples.append(wellness)
            }
        }

        return mergeWellnessSamples(samples).sorted { $0.date > $1.date }
    }

    func uploadActivityFile(
        accessToken: String,
        connectCSRFToken: String? = nil,
        fileData: Data,
        fileExtension: String = "fit",
        fileName: String = "activity.fit"
    ) async throws -> String {
        let token = accessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            throw GarminConnectAPIError.missingAccessToken
        }

        var hints = parseRequestHints(rawInput: token)
        if let explicitCSRF = connectCSRFToken?.trimmingCharacters(in: .whitespacesAndNewlines),
           !explicitCSRF.isEmpty {
            hints.connectCSRFToken = explicitCSRF
        }
        let authModes = buildAuthModes(token: hints.authInput)
        let urls = buildUploadURLs(
            fileExtension: fileExtension,
            preferChinaRegion: hints.preferChinaRegion
        )

        var endpointErrors: [String] = []
        for url in urls {
            for mode in authModes {
                do {
                    let uploadID = try await uploadFileToEndpoint(
                        url: url,
                        authMode: mode,
                        connectCSRFToken: hints.connectCSRFToken,
                        fileData: fileData,
                        fileName: fileName
                    )
                    return uploadID
                } catch let GarminConnectAPIError.requestFailed(code, body) {
                    let compactBody = body.replacingOccurrences(of: "\n", with: " ")
                    endpointErrors.append("\(url.absoluteString) [\(mode.key)] \(code) \(compactBody.prefix(120))")
                    if code == 401 || code == 403 || code == 404 || code == 400 {
                        continue
                    }
                } catch {
                    endpointErrors.append("\(url.absoluteString) [\(mode.key)] \(error.localizedDescription)")
                }
            }
        }

        throw GarminConnectAPIError.noUsableEndpoint(endpointErrors)
    }

    private func fetchWellnessForDay(
        day: Date,
        authModes: [AuthMode],
        hints: RequestHints
    ) async throws -> WellnessSample {
        let dayText = IntervalsDateFormatter.day.string(from: day)
        var sample = WellnessSample(date: day)

        let heartURLs = buildWellnessURLs(
            endpoint: "dailyHeartRate",
            query: [URLQueryItem(name: "date", value: dayText)],
            preferChinaRegion: hints.preferChinaRegion
        )
        if let heartAny = try await requestFirstSuccessfulJSON(urls: heartURLs, authModes: authModes, hints: hints) {
            if let rhr = extractFirstNumber(keys: [
                "restingheartRate", "restingheartrate", "resthr", "lowestheartRate", "lowestheartrate", "rhr"
            ], from: heartAny) {
                sample.restingHR = rhr
            }
        }

        let sleepURLs = buildWellnessURLs(
            endpoint: "dailySleepData",
            query: [URLQueryItem(name: "date", value: dayText)],
            preferChinaRegion: hints.preferChinaRegion
        )
        if let sleepAny = try await requestFirstSuccessfulJSON(urls: sleepURLs, authModes: authModes, hints: hints) {
            if let seconds = extractFirstNumber(keys: [
                "sleepTimeSeconds", "totalSleepSeconds", "totalSleepDuration", "durationInSeconds", "sleepDuration"
            ], from: sleepAny) {
                let hours = seconds > 1000 ? (seconds / 3600.0) : seconds
                sample.sleepHours = max(0, min(20, hours))
            }
            if let score = extractFirstNumber(keys: [
                "sleepScore", "overallSleepScore", "score"
            ], from: sleepAny), score >= 0, score <= 100 {
                sample.sleepScore = score
            }
        }

        let hrvURLsA = buildWellnessURLs(
            endpoint: "hrv",
            query: [
                URLQueryItem(name: "fromDate", value: dayText),
                URLQueryItem(name: "untilDate", value: dayText)
            ],
            preferChinaRegion: hints.preferChinaRegion
        )
        let hrvURLsB = buildWellnessURLs(
            endpoint: "dailyHrv",
            query: [URLQueryItem(name: "date", value: dayText)],
            preferChinaRegion: hints.preferChinaRegion
        )
        let hrvURLs = hrvURLsA + hrvURLsB
        if let hrvAny = try await requestFirstSuccessfulJSON(urls: hrvURLs, authModes: authModes, hints: hints) {
            if let hrv = extractFirstNumber(keys: [
                "hrv", "rmssd", "overnightHrv", "avgHrv", "hrvValue", "lastNightAvg", "dailyHrv"
            ], from: hrvAny) {
                sample.hrv = hrv
            }
        }

        return sample
    }

    private func allDatesBetween(start: Date, end: Date) -> [Date] {
        let cal = Calendar.current
        let first = cal.startOfDay(for: min(start, end))
        let last = cal.startOfDay(for: max(start, end))
        var rows: [Date] = []
        var cursor = first
        while cursor <= last {
            rows.append(cursor)
            guard let next = cal.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return rows
    }

    private func buildWellnessURLs(
        endpoint: String,
        query: [URLQueryItem],
        preferChinaRegion: Bool
    ) -> [URL] {
        let roots = preferChinaRegion ? (chinaWellnessRoots + globalWellnessRoots) : (globalWellnessRoots + chinaWellnessRoots)
        var urls: [URL] = []
        for root in roots {
            guard let rootURL = URL(string: root) else { continue }
            guard var components = URLComponents(url: rootURL.appendingPathComponent(endpoint), resolvingAgainstBaseURL: false) else { continue }
            components.queryItems = query
            if let url = components.url { urls.append(url) }
        }
        return Array(NSOrderedSet(array: urls).compactMap { $0 as? URL })
    }

    private func buildUploadURLs(fileExtension: String, preferChinaRegion: Bool) -> [URL] {
        let ext = fileExtension.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let suffix = ext.isEmpty ? ".fit" : ".\(ext)"

        let globalRoots = [
            "https://connectapi.garmin.com/upload-service/upload",
            "https://connect.garmin.com/proxy/upload-service/upload",
            "https://connect.garmin.com/modern/proxy/upload-service/upload",
            "https://connect.garmin.com/upload-service/upload"
        ]
        let chinaRoots = [
            "https://connectus.garmin.cn/gc-api/upload-service/upload",
            "https://connectus.garmin.cn/upload-service/upload"
        ]

        let roots = preferChinaRegion ? (chinaRoots + globalRoots) : (globalRoots + chinaRoots)
        var urls: [URL] = []
        for root in roots {
            guard let base = URL(string: root) else { continue }
            urls.append(base)
            urls.append(base.appendingPathComponent(suffix))
        }
        return Array(NSOrderedSet(array: urls).compactMap { $0 as? URL })
    }

    private func uploadFileToEndpoint(
        url: URL,
        authMode: AuthMode,
        connectCSRFToken: String?,
        fileData: Data,
        fileName: String
    ) async throws -> String {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/537.36 (KHTML, like Gecko) FricuApp/1.0 Safari/537.36",
            forHTTPHeaderField: "User-Agent"
        )
        let host = url.host?.lowercased() ?? ""
        let isChinaHost = host.hasSuffix(".garmin.cn")
        request.setValue(isChinaHost ? "zh-CN,zh;q=0.9,en;q=0.8" : "en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.setValue(isChinaHost ? "https://connectus.garmin.cn" : "https://connect.garmin.com", forHTTPHeaderField: "Origin")
        request.setValue(
            isChinaHost ? "https://connectus.garmin.cn/modern/activities" : "https://connect.garmin.com/modern/activities",
            forHTTPHeaderField: "Referer"
        )
        request.setValue("same-origin", forHTTPHeaderField: "Sec-Fetch-Site")
        request.setValue("cors", forHTTPHeaderField: "Sec-Fetch-Mode")
        request.setValue("empty", forHTTPHeaderField: "Sec-Fetch-Dest")
        request.setValue("u=1, i", forHTTPHeaderField: "Priority")
        if let connectCSRFToken, !connectCSRFToken.isEmpty {
            request.setValue(connectCSRFToken, forHTTPHeaderField: "Connect-Csrf-Token")
        }

        switch authMode {
        case let .bearer(token):
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        case let .authorization(raw):
            request.setValue(raw, forHTTPHeaderField: "Authorization")
        case let .cookie(cookie):
            request.setValue(cookie, forHTTPHeaderField: "Cookie")
            if let jwt = parseCookiePairs(cookie)["jwt_web"], looksLikeJWT(jwt) {
                request.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")
            }
        }

        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = buildUploadMultipartBody(boundary: boundary, fileData: fileData, fileName: fileName)

        let data = try await sendWithRetry(request)
        let uploadTag = parseUploadTagFromResponse(data, fallbackPrefix: "garmin:upload")
        return uploadTag
    }

    private func buildUploadMultipartBody(boundary: String, fileData: Data, fileName: String) -> Data {
        func textField(_ key: String, _ value: String) -> Data {
            var data = Data()
            data.append("--\(boundary)\r\n".data(using: .utf8)!)
            data.append("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n".data(using: .utf8)!)
            data.append("\(value)\r\n".data(using: .utf8)!)
            return data
        }

        var body = Data()
        body.append(textField("dataType", "fit"))
        body.append(textField("uploadSource", "Fricu"))
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        return body
    }

    private func parseUploadTagFromResponse(_ data: Data, fallbackPrefix: String) -> String {
        if let sanitized = try? sanitizeGarminJSONPayload(data),
           let any = try? JSONSerialization.jsonObject(with: sanitized) {
            if let string = extractFirstString(keys: [
                "activityId", "activityID", "id", "uploadId", "importId"
            ], from: any), !string.isEmpty {
                return "garmin:\(string)"
            }
            if let number = extractFirstNumber(keys: [
                "activityId", "activityID", "id", "uploadId", "importId"
            ], from: any) {
                return "garmin:\(Int(number.rounded()))"
            }
        }
        return "\(fallbackPrefix):\(Int(Date().timeIntervalSince1970))"
    }

    private func extractFirstString(keys: [String], from payload: Any) -> String? {
        let normalizedKeys = Set(keys.map { $0.lowercased().replacingOccurrences(of: "_", with: "") })
        var found: String?

        func walk(_ any: Any) {
            guard found == nil else { return }
            if let dict = any as? [String: Any] {
                for (key, value) in dict {
                    guard found == nil else { return }
                    let normalized = key.lowercased().replacingOccurrences(of: "_", with: "")
                    if normalizedKeys.contains(normalized), let text = JSONValue.string(value), !text.isEmpty {
                        found = text
                        return
                    }
                    walk(value)
                }
                return
            }
            if let array = any as? [Any] {
                for item in array {
                    walk(item)
                    if found != nil { return }
                }
            }
        }

        walk(payload)
        return found
    }

    private func requestFirstSuccessfulJSON(
        urls: [URL],
        authModes: [AuthMode],
        hints: RequestHints
    ) async throws -> Any? {
        var localAuthModes = authModes
        if hints.preferChinaRegion {
            localAuthModes.sort { lhs, rhs in
                switch (lhs, rhs) {
                case (.cookie, .cookie): return false
                case (.cookie, _): return true
                case (_, .cookie): return false
                default: return false
                }
            }
        }

        var sawCriticalAuthError = false
        for url in urls {
            for mode in localAuthModes {
                do {
                    return try await requestJSON(url: url, authMode: mode, connectCSRFToken: hints.connectCSRFToken)
                } catch let GarminConnectAPIError.requestFailed(code, _) {
                    if code == 401 || code == 403 {
                        sawCriticalAuthError = true
                    }
                    if code == 404 || code == 400 || code == 401 || code == 403 {
                        continue
                    }
                } catch {
                    continue
                }
            }
        }

        if sawCriticalAuthError {
            throw GarminConnectAPIError.requestFailed(403, "Garmin wellness endpoint unauthorized.")
        }
        return nil
    }

    private func requestJSON(
        url: URL,
        authMode: AuthMode,
        connectCSRFToken: String?
    ) async throws -> Any {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.setValue(garminUserAgent, forHTTPHeaderField: "User-Agent")
        let host = url.host?.lowercased() ?? ""
        let isChinaHost = host.hasSuffix(".garmin.cn")
        request.setValue(isChinaHost ? "zh-CN,zh;q=0.9,en;q=0.8" : "en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.setValue("same-origin", forHTTPHeaderField: "Sec-Fetch-Site")
        request.setValue("cors", forHTTPHeaderField: "Sec-Fetch-Mode")
        request.setValue("empty", forHTTPHeaderField: "Sec-Fetch-Dest")
        request.setValue("?0", forHTTPHeaderField: "Sec-CH-UA-Mobile")
        request.setValue(secCHUAPlatformValue, forHTTPHeaderField: "Sec-CH-UA-Platform")
        request.setValue("u=1, i", forHTTPHeaderField: "Priority")
        if let connectCSRFToken, !connectCSRFToken.isEmpty {
            request.setValue(connectCSRFToken, forHTTPHeaderField: "Connect-Csrf-Token")
        }

        switch authMode {
        case let .bearer(token):
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        case let .authorization(raw):
            request.setValue(raw, forHTTPHeaderField: "Authorization")
        case let .cookie(cookie):
            request.setValue(cookie, forHTTPHeaderField: "Cookie")
            if !isChinaHost, let jwt = parseCookiePairs(cookie)["jwt_web"], looksLikeJWT(jwt) {
                request.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")
            }
        }

        let data = try await sendWithRetry(request)
        let sanitized = try sanitizeGarminJSONPayload(data)
        return try JSONSerialization.jsonObject(with: sanitized)
    }

    private func extractFirstNumber(keys: [String], from payload: Any) -> Double? {
        let keySet = Set(keys.map { $0.lowercased() })
        let all = collectNumbers(from: payload, matching: keySet)
        return all.first
    }

    private func collectNumbers(from payload: Any, matching keys: Set<String>) -> [Double] {
        var rows: [Double] = []

        func walk(_ any: Any) {
            if let dict = any as? [String: Any] {
                for (key, value) in dict {
                    let normalized = key.lowercased().replacingOccurrences(of: "_", with: "")
                    if keys.contains(normalized), let number = JSONValue.double(value) {
                        rows.append(number)
                    }
                    walk(value)
                }
                return
            }

            if let array = any as? [Any] {
                for item in array { walk(item) }
            }
        }

        walk(payload)
        return rows.filter { $0.isFinite }
    }

    private func fetchPage(
        start: Int,
        limit: Int,
        startDate: String,
        endDate: String,
        authModes: [AuthMode],
        hints: RequestHints
    ) async throws -> [[String: Any]] {
        let urls = buildActivityListURLs(
            start: start,
            limit: limit,
            startDate: startDate,
            endDate: endDate,
            preferChinaRegion: hints.preferChinaRegion
        )
        var endpointErrors: [String] = []

        for url in urls {
            for mode in authModes {
                do {
                    return try await requestRows(
                        url: url,
                        authMode: mode,
                        connectCSRFToken: hints.connectCSRFToken
                    )
                } catch let GarminConnectAPIError.requestFailed(code, body) {
                    let compactBody = body.replacingOccurrences(of: "\n", with: " ")
                    endpointErrors.append("\(url.absoluteString) [\(mode.key)] \(code) \(compactBody.prefix(120))")
                    if code == 401 || code == 403 || code == 404 || code == 400 {
                        continue
                    }
                } catch {
                    endpointErrors.append("\(url.absoluteString) [\(mode.key)] \(error.localizedDescription)")
                }
            }
        }

        throw GarminConnectAPIError.noUsableEndpoint(endpointErrors)
    }

    private func buildActivityListURLs(
        start: Int,
        limit: Int,
        startDate: String,
        endDate: String,
        preferChinaRegion: Bool
    ) -> [URL] {
        var urls: [URL] = []
        let roots = preferChinaRegion ? (chinaEndpointRoots + globalEndpointRoots) : (globalEndpointRoots + chinaEndpointRoots)
        for root in roots {
            guard let rootURL = URL(string: root) else { continue }
            if root.contains("activitylist-service"),
               var dated = URLComponents(url: rootURL, resolvingAgainstBaseURL: false) {
                dated.queryItems = [
                    URLQueryItem(name: "start", value: String(start)),
                    URLQueryItem(name: "limit", value: String(limit)),
                    URLQueryItem(name: "startDate", value: startDate),
                    URLQueryItem(name: "endDate", value: endDate)
                ]
                if let datedURL = dated.url {
                    urls.append(datedURL)
                }
            }

            if var raw = URLComponents(url: rootURL, resolvingAgainstBaseURL: false) {
                raw.queryItems = [
                    URLQueryItem(name: "start", value: String(start)),
                    URLQueryItem(name: "limit", value: String(limit))
                ]
                if let rawURL = raw.url {
                    urls.append(rawURL)
                }
            }
        }
        return Array(NSOrderedSet(array: urls).compactMap { $0 as? URL })
    }

    private func requestRows(
        url: URL,
        authMode: AuthMode,
        connectCSRFToken: String?
    ) async throws -> [[String: Any]] {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 35
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(garminUserAgent, forHTTPHeaderField: "User-Agent")
        let host = url.host?.lowercased() ?? ""
        let isChinaHost = host.hasSuffix(".garmin.cn")
        request.setValue(isChinaHost ? "zh-CN,zh;q=0.9,en;q=0.8" : "en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.setValue(isChinaHost ? "https://connectus.garmin.cn" : "https://connect.garmin.com", forHTTPHeaderField: "Origin")
        request.setValue(
            isChinaHost ? "https://connectus.garmin.cn/modern/activities" : "https://connect.garmin.com/modern/activities",
            forHTTPHeaderField: "Referer"
        )
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        request.setValue("same-origin", forHTTPHeaderField: "Sec-Fetch-Site")
        request.setValue("cors", forHTTPHeaderField: "Sec-Fetch-Mode")
        request.setValue("empty", forHTTPHeaderField: "Sec-Fetch-Dest")
        request.setValue("?0", forHTTPHeaderField: "Sec-CH-UA-Mobile")
        request.setValue(secCHUAPlatformValue, forHTTPHeaderField: "Sec-CH-UA-Platform")
        request.setValue("NT", forHTTPHeaderField: "NK")
        request.setValue(host.isEmpty ? "connectapi.garmin.com" : host, forHTTPHeaderField: "DI-Backend")
        if let connectCSRFToken, !connectCSRFToken.isEmpty {
            request.setValue(connectCSRFToken, forHTTPHeaderField: "Connect-Csrf-Token")
        }

        switch authMode {
        case let .bearer(token):
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        case let .authorization(raw):
            request.setValue(raw, forHTTPHeaderField: "Authorization")
        case let .cookie(cookie):
            request.setValue(cookie, forHTTPHeaderField: "Cookie")
            if let jwt = parseCookiePairs(cookie)["jwt_web"], looksLikeJWT(jwt) {
                request.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")
            }
        }

        let data = try await sendWithRetry(request)
        let sanitized = try sanitizeGarminJSONPayload(data)
        let any = try JSONSerialization.jsonObject(with: sanitized)
        if let rows = any as? [[String: Any]] {
            return rows
        }
        if let root = any as? [String: Any] {
            if let rows = root["activities"] as? [[String: Any]] { return rows }
            if let rows = root["activityList"] as? [[String: Any]] { return rows }
            if let rows = root["data"] as? [[String: Any]] { return rows }
            if let rows = root["results"] as? [[String: Any]] { return rows }
            if let results = root["results"] as? [String: Any] {
                if let rows = results["activities"] as? [[String: Any]] { return rows }
                if let rows = results["data"] as? [[String: Any]] { return rows }
                if let rows = results["items"] as? [[String: Any]] { return rows }
            }
            if let payload = root["payload"] as? [String: Any], let rows = payload["activities"] as? [[String: Any]] {
                return rows
            }
            if root["message"] != nil || root["error"] != nil {
                throw GarminConnectAPIError.requestFailed(400, String(data: data, encoding: .utf8) ?? "")
            }
        }

        throw GarminConnectAPIError.malformedPayload
    }

    private func sanitizeGarminJSONPayload(_ data: Data) throws -> Data {
        guard var text = String(data: data, encoding: .utf8) else {
            return data
        }

        let lower = text.lowercased()
        if (lower.contains("<html") || lower.contains("<!doctype html")) && lower.contains("signin") {
            throw GarminConnectAPIError.requestFailed(401, "Garmin 返回登录页（会话已失效或被风控拦截）")
        }

        if text.hasPrefix(")]}',") {
            if let nl = text.firstIndex(of: "\n") {
                text = String(text[text.index(after: nl)...])
            } else {
                text = String(text.dropFirst(5))
            }
        }
        return Data(text.utf8)
    }

    private func sendWithRetry(_ request: URLRequest, maxRetry: Int = 2) async throws -> Data {
        var attempt = 0
        while true {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw GarminConnectAPIError.malformedPayload
            }

            if (200..<300).contains(http.statusCode) {
                return data
            }

            if (http.statusCode == 429 || (500..<600).contains(http.statusCode)), attempt < maxRetry {
                let delay: UInt64
                if let retryAfter = http.value(forHTTPHeaderField: "Retry-After"), let sec = Double(retryAfter) {
                    delay = UInt64(max(0.2, sec) * 1_000_000_000)
                } else {
                    delay = UInt64((0.5 + Double(attempt) * 0.7) * 1_000_000_000)
                }
                attempt += 1
                try await Task.sleep(nanoseconds: delay)
                continue
            }

            throw GarminConnectAPIError.requestFailed(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
    }

    private func buildAuthModes(token: String) -> [AuthMode] {
        let value = token.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = value.lowercased()
        var modes: [AuthMode] = []
        let cookiePairs = parseCookiePairs(value)
        let hasCookieShape = !cookiePairs.isEmpty || value.contains("=")

        if lower.hasPrefix("bearer ") || lower.hasPrefix("basic ") || lower.hasPrefix("oauth ") {
            modes.append(.authorization(value))
        } else if !hasCookieShape {
            modes.append(.bearer(value))
        }

        if hasCookieShape {
            if let jwt = cookiePairs["jwt_web"], looksLikeJWT(jwt) {
                modes.append(.bearer(jwt))
            }
            if let oauth = cookiePairs["oauth_token"], !oauth.isEmpty {
                modes.append(.bearer(oauth))
            }

            let cookie = canonicalCookieString(from: cookiePairs, fallback: value)
            if !cookie.isEmpty {
                modes.append(.cookie(cookie))
            }
        } else if looksLikeJWT(value) {
            modes.append(.bearer(value))
        }

        var deduped: [AuthMode] = []
        var seen = Set<String>()
        for mode in modes {
            let key: String
            switch mode {
            case let .bearer(t):
                key = "b:\(t)"
            case let .authorization(raw):
                key = "a:\(raw)"
            case let .cookie(c):
                key = "c:\(c)"
            }
            if !seen.contains(key) {
                seen.insert(key)
                deduped.append(mode)
            }
        }

        return deduped
    }

    private func parseCookiePairs(_ raw: String) -> [String: String] {
        var pairs: [String: String] = [:]
        for part in raw.split(separator: ";") {
            let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let idx = trimmed.firstIndex(of: "=") else { continue }
            let key = String(trimmed[..<idx]).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = String(trimmed[trimmed.index(after: idx)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty, !value.isEmpty else { continue }
            pairs[key] = value
        }
        return pairs
    }

    private func canonicalCookieString(from pairs: [String: String], fallback: String) -> String {
        let raw = fallback.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return "" }
        // Keep the original cookie string when possible. Garmin/Cloudflare may require
        // additional fields beyond session/JWT_WEB/SESSIONID (e.g. JWT_FGP, _cfuvid).
        if raw.contains(";") {
            return raw
        }
        guard !pairs.isEmpty else {
            return raw
        }

        return pairs
            .filter { !$0.key.isEmpty && !$0.value.isEmpty }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "; ")
    }

    private func looksLikeJWT(_ token: String) -> Bool {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.contains(";") else { return false }
        return trimmed.split(separator: ".").count == 3
    }

    private func parseRequestHints(rawInput: String) -> RequestHints {
        let text = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return RequestHints(authInput: "", connectCSRFToken: nil, preferChinaRegion: false)
        }

        let lowerText = text.lowercased()
        let preferChina = lowerText.contains("connectus.garmin.cn")
            || lowerText.contains("garmin.cn")
            || lowerText.contains("/gc-api/")

        if let cookie = extractCookieFromHeaderBlob(text) {
            let csrf = extractHeaderValue(name: "connect-csrf-token", from: text)
            return RequestHints(
                authInput: cookie,
                connectCSRFToken: csrf,
                preferChinaRegion: preferChina
            )
        }

        if !text.contains("\n") && !text.contains("\r") {
            let cookiePairs = parseCookiePairs(text)
            let csrf = cookiePairs["connect-csrf-token"] ?? cookiePairs["connectcsrftoken"]
            return RequestHints(authInput: text, connectCSRFToken: csrf, preferChinaRegion: preferChina)
        }

        var cookie: String?
        var csrf: String?

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            let lowered = line.lowercased()

            if lowered.hasPrefix("cookie:") {
                cookie = line.dropFirst("cookie:".count).trimmingCharacters(in: .whitespacesAndNewlines)
                continue
            }
            if lowered.hasPrefix("cookie ") {
                cookie = line.dropFirst("cookie".count).trimmingCharacters(in: .whitespacesAndNewlines)
                continue
            }
            if lowered.hasPrefix("connect-csrf-token:") {
                csrf = line.dropFirst("connect-csrf-token:".count).trimmingCharacters(in: .whitespacesAndNewlines)
                continue
            }
            if lowered.hasPrefix("connect-csrf-token ") {
                csrf = line.dropFirst("connect-csrf-token".count).trimmingCharacters(in: .whitespacesAndNewlines)
                continue
            }
            if lowered.hasPrefix("connect-csrf-token=") {
                csrf = line.dropFirst("connect-csrf-token=".count).trimmingCharacters(in: .whitespacesAndNewlines)
                continue
            }
        }

        let authInput = (cookie ?? text).trimmingCharacters(in: .whitespacesAndNewlines)
        if csrf == nil {
            let cookiePairs = parseCookiePairs(authInput)
            csrf = cookiePairs["connect-csrf-token"] ?? cookiePairs["connectcsrftoken"]
        }
        return RequestHints(authInput: authInput, connectCSRFToken: csrf, preferChinaRegion: preferChina)
    }

    private func extractHeaderValue(name: String, from text: String) -> String? {
        let lines = text.replacingOccurrences(of: "\r", with: "").components(separatedBy: .newlines)
        let key = name.lowercased()

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let lower = trimmed.lowercased()
            if lower.hasPrefix("\(key):") {
                return String(trimmed.dropFirst(key.count + 1)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if lower.hasPrefix("\(key) ") {
                return String(trimmed.dropFirst(key.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if lower.hasPrefix("\(key)=") {
                return String(trimmed.dropFirst(key.count + 1)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        let ns = text as NSString
        let pattern = "(?i)\\b" + NSRegularExpression.escapedPattern(for: name) + "\\b\\s*[:=]?\\s*([A-Za-z0-9-]{8,})"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(location: 0, length: ns.length)
        guard let match = regex.firstMatch(in: text, options: [], range: range), match.numberOfRanges > 1 else { return nil }
        let valueRange = match.range(at: 1)
        guard valueRange.location != NSNotFound else { return nil }
        return ns.substring(with: valueRange).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func extractCookieFromHeaderBlob(_ text: String) -> String? {
        let normalized = text.replacingOccurrences(of: "\r", with: "")
        let lines = normalized.components(separatedBy: .newlines)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let lower = trimmed.lowercased()
            if lower.hasPrefix("cookie:") {
                let value = String(trimmed.dropFirst("cookie:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
                if value.contains("="), value.contains(";") { return value }
            } else if lower.hasPrefix("cookie ") {
                let value = String(trimmed.dropFirst("cookie".count)).trimmingCharacters(in: .whitespacesAndNewlines)
                if value.contains("="), value.contains(";") { return value }
            }
        }

        let lower = normalized.lowercased()
        guard let cookieRange = lower.range(of: "cookie") else { return nil }
        var start = cookieRange.upperBound
        while start < lower.endIndex {
            let ch = lower[start]
            if ch == ":" || ch == "=" || ch == " " || ch == "\t" {
                start = lower.index(after: start)
                continue
            }
            break
        }

        let tailLower = lower[start...]
        let boundaries = [
            "\npriority", "\nsec-ch-ua", "\nuser-agent", "\naccept", "\n:method", "\n:path",
            " priority", " sec-ch-ua", " user-agent", " accept-encoding", " accept-language",
            " sec-fetch-", " :method", " :path", " connect-csrf-token"
        ]
        var end = lower.endIndex
        for marker in boundaries {
            if let r = tailLower.range(of: marker), r.lowerBound < end {
                end = r.lowerBound
            }
        }

        let value = normalized[start..<end].trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.contains("="), value.contains(";") else { return nil }
        return value
    }

    private func parseActivity(row: [String: Any], profile: AthleteProfile) -> Activity? {
        let activityID = JSONValue.string(row["activityId"])
            ?? JSONValue.string(row["activityID"])
            ?? JSONValue.string(row["activity_id"])
            ?? JSONValue.string(row["id"])

        guard let activityID else { return nil }

        let date = parseDate(row) ?? Date()
        let sport = parseSport(row)
        let durationSec = max(
            1,
            JSONValue.int(row["movingDuration"])
                ?? JSONValue.int(row["duration"])
                ?? JSONValue.int(row["elapsedDuration"])
                ?? Int((JSONValue.double(row["duration"]) ?? 0).rounded())
        )
        let distanceMeters = max(
            0,
            JSONValue.double(row["distance"])
                ?? JSONValue.double(row["distanceMeters"])
                ?? JSONValue.double(row["totalDistance"])
                ?? 0
        )
        let avgPower = JSONValue.int(row["averagePower"])
            ?? JSONValue.int(row["averageBikingPower"])
            ?? JSONValue.int(row["avgPower"])
        let normalizedPower = JSONValue.int(row["normalizedPower"])
            ?? JSONValue.int(row["normPower"])
            ?? JSONValue.int(row["weightedAveragePower"])
            ?? avgPower
        let avgHR = JSONValue.int(row["averageHR"])
            ?? JSONValue.int(row["averageHeartRate"])
            ?? JSONValue.int(row["avgHR"])
        let tss = JSONValue.int(row["tss"])
            ?? JSONValue.int(row["trainingStressScore"])
            ?? TSSEstimator.estimate(
                durationSec: durationSec,
                sport: sport,
                avgPower: avgPower,
                normalizedPower: normalizedPower,
                avgHeartRate: avgHR,
                profile: profile,
                date: date
            )
        let notes = JSONValue.string(row["activityName"])
            ?? JSONValue.string(row["title"])
            ?? "Garmin Connect Activity"

        return Activity(
            date: date,
            sport: sport,
            durationSec: durationSec,
            distanceKm: distanceMeters / 1000.0,
            tss: max(0, tss),
            normalizedPower: normalizedPower,
            avgHeartRate: avgHR,
            notes: notes,
            externalID: "garmin:\(activityID)"
        )
    }

    private func parseDate(_ row: [String: Any]) -> Date? {
        if let text = JSONValue.string(row["startTimeLocal"])
            ?? JSONValue.string(row["startTimeGMT"])
            ?? JSONValue.string(row["startTime"])
            ?? JSONValue.string(row["start_time"]) {
            if let parsed = DateParsers.parseISO8601(text) {
                return parsed
            }

            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = TimeZone.current
            f.dateFormat = "yyyy-MM-dd HH:mm:ss"
            if let parsed = f.date(from: text) {
                return parsed
            }
        }

        if let seconds = JSONValue.double(row["startTimeInSeconds"])
            ?? JSONValue.double(row["startTimeGMTInSeconds"])
            ?? JSONValue.double(row["beginTimestamp"]) {
            if seconds > 10_000_000_000 {
                return Date(timeIntervalSince1970: seconds / 1000.0)
            }
            return Date(timeIntervalSince1970: seconds)
        }

        return nil
    }

    private func parseSport(_ row: [String: Any]) -> SportType {
        var raw = JSONValue.string(row["activityType"])
            ?? JSONValue.string(row["sport"])
            ?? JSONValue.string(row["type"])

        if raw == nil, let type = row["activityType"] as? [String: Any] {
            raw = JSONValue.string(type["typeKey"])
                ?? JSONValue.string(type["parentTypeName"])
                ?? JSONValue.string(type["displayOrder"])
        }

        let lowered = (raw ?? "cycling").lowercased()
        if lowered.contains("run") { return .running }
        if lowered.contains("swim") { return .swimming }
        if lowered.contains("strength") || lowered.contains("gym") { return .strength }
        return .cycling
    }
}

final class WhoopAPIClient {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchWellness(accessToken: String, start: Date, end: Date) async throws -> [WellnessSample] {
        let token = accessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            throw WellnessConnectorError.missingAccessToken("WHOOP")
        }

        // WHOOP Developer API path may vary by account/app. This path is used as a default.
        guard var components = URLComponents(string: "https://api.prod.whoop.com/developer/v1/recovery") else {
            throw WellnessConnectorError.badURL
        }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        components.queryItems = [
            URLQueryItem(name: "start", value: iso.string(from: start)),
            URLQueryItem(name: "end", value: iso.string(from: end)),
            URLQueryItem(name: "limit", value: "200")
        ]

        guard let url = components.url else {
            throw WellnessConnectorError.badURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 25
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw WellnessConnectorError.malformedResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw WellnessConnectorError.requestFailed(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }

        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw WellnessConnectorError.malformedResponse
        }

        let rows = (root["records"] as? [[String: Any]])
            ?? (root["data"] as? [[String: Any]])
            ?? []

        var result: [WellnessSample] = []
        for row in rows {
            guard let date = parseDate(row["start"] ?? row["created_at"] ?? row["timestamp"]) else { continue }

            var hrv: Double?
            var restingHR: Double?

            if let score = row["score"] as? [String: Any] {
                hrv = JSONValue.double(score["hrv_rmssd_milli"]) ?? JSONValue.double(score["hrv"])
                restingHR = JSONValue.double(score["resting_heart_rate"])
            }

            if hrv == nil { hrv = JSONValue.double(row["hrv"]) }
            if restingHR == nil { restingHR = JSONValue.double(row["resting_heart_rate"]) }

            let sleepHours = parseWhoopSleepHours(row)
            let sleepScore = JSONValue.double(row["sleep_performance_percentage"]) ?? JSONValue.double(row["sleep_score"])
            result.append(
                WellnessSample(
                    date: Calendar.current.startOfDay(for: date),
                    hrv: hrv,
                    restingHR: restingHR,
                    weightKg: nil,
                    sleepHours: sleepHours,
                    sleepScore: sleepScore
                )
            )
        }

        return mergeWellnessSamples(result)
    }

    private func parseDate(_ any: Any?) -> Date? {
        if let text = JSONValue.string(any) {
            return DateParsers.parseISO8601(text)
        }
        return nil
    }

    private func parseWhoopSleepHours(_ row: [String: Any]) -> Double? {
        if let sec = JSONValue.double(row["sleep_duration_seconds"]) ?? JSONValue.double(row["sleep_duration"]) {
            if sec > 24 {
                return max(0, sec) / 3600.0
            }
            return max(0, sec)
        }
        if let score = row["score"] as? [String: Any] {
            if let ms = JSONValue.double(score["sleep_duration_milli"]) {
                return max(0, ms) / 3_600_000.0
            }
            if let min = JSONValue.double(score["sleep_duration_minutes"]) {
                return max(0, min) / 60.0
            }
        }
        return nil
    }
}

enum GarminConnectExportImporter {
    static func importJSON(at url: URL, profile: AthleteProfile) throws -> [Activity] {
        let data = try Data(contentsOf: url)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }

        let rows = (root["activities"] as? [[String: Any]])
            ?? (root["data"] as? [[String: Any]])
            ?? []

        var activities: [Activity] = []
        for row in rows {
            guard let activity = parseRow(row, profile: profile) else { continue }
            activities.append(activity)
        }

        return activities.sorted { $0.date > $1.date }
    }

    private static func parseRow(_ row: [String: Any], profile: AthleteProfile) -> Activity? {
        let date = parseDate(row["startTimeLocal"] ?? row["start_time"] ?? row["date"]) ?? Date()

        let sportRaw = JSONValue.string(row["activityType"])
            ?? JSONValue.string(row["sport"])
            ?? "cycling"

        let sport: SportType
        let lowered = sportRaw.lowercased()
        if lowered.contains("run") {
            sport = .running
        } else if lowered.contains("swim") {
            sport = .swimming
        } else if lowered.contains("strength") {
            sport = .strength
        } else {
            sport = .cycling
        }

        let durationSec = JSONValue.int(row["durationSec"])
            ?? JSONValue.int(row["duration"])
            ?? Int((JSONValue.double(row["movingDuration"]) ?? 0).rounded())

        let distanceMeters = JSONValue.double(row["distanceMeters"])
            ?? JSONValue.double(row["distance"])
            ?? 0

        let avgPower = JSONValue.int(row["averagePower"]) ?? JSONValue.int(row["avg_power"])
        let normalizedPower = JSONValue.int(row["normalizedPower"]) ?? JSONValue.int(row["np"])
        let avgHeartRate = JSONValue.int(row["averageHR"]) ?? JSONValue.int(row["avg_hr"])

        let tss = JSONValue.int(row["tss"]) ?? TSSEstimator.estimate(
            durationSec: durationSec,
            sport: sport,
            avgPower: avgPower,
            normalizedPower: normalizedPower ?? avgPower,
            avgHeartRate: avgHeartRate,
            profile: profile,
            date: date
        )

        return Activity(
            date: date,
            sport: sport,
            durationSec: max(1, durationSec),
            distanceKm: max(0, distanceMeters / 1000.0),
            tss: max(0, tss),
            normalizedPower: normalizedPower ?? avgPower,
            avgHeartRate: avgHeartRate,
            intervals: [],
            notes: "Imported from Garmin Connect export"
        )
    }

    private static func parseDate(_ any: Any?) -> Date? {
        guard let text = JSONValue.string(any) else { return nil }
        return DateParsers.parseISO8601(text)
    }
}

enum ActivityRepairMode: String, CaseIterable, Identifiable {
    case powerSpikes
    case heartRateSpikes
    case gpsDistance
    case torqueOutliers

    var id: String { rawValue }

    var title: String {
        switch self {
        case .powerSpikes: return "Power Spike 修复"
        case .heartRateSpikes: return "HR Spike 修复"
        case .gpsDistance: return "GPS 距离修复"
        case .torqueOutliers: return "扭矩异常修复"
        }
    }
}

enum ActivityRepairEngine {
    static func repaired(activity: Activity, mode: ActivityRepairMode, profile: AthleteProfile) -> Activity {
        var row = activity

        switch mode {
        case .powerSpikes:
            if let np = row.normalizedPower {
                let maxReasonable = Int(Double(profile.ftpWatts(for: row.sport)) * 1.9)
                row.normalizedPower = clamp(np, min: 50, max: max(200, maxReasonable))
            }

        case .heartRateSpikes:
            if let hr = row.avgHeartRate {
                row.avgHeartRate = clamp(hr, min: 50, max: 205)
            }

        case .gpsDistance:
            let hours = max(1.0 / 3600.0, Double(row.durationSec) / 3600.0)
            let speed = row.distanceKm / hours
            let limit: Double
            switch row.sport {
            case .cycling: limit = 65
            case .running: limit = 30
            case .swimming: limit = 8
            case .strength: limit = 15
            }
            if speed > limit {
                row.distanceKm = limit * hours
            }

        case .torqueOutliers:
            if let np = row.normalizedPower, np > 0 {
                let softened = Int((Double(np) * 0.96).rounded())
                row.normalizedPower = max(40, softened)
            }
        }

        row.tss = TSSEstimator.estimate(
            durationSec: row.durationSec,
            sport: row.sport,
            avgPower: row.normalizedPower,
            normalizedPower: row.normalizedPower,
            avgHeartRate: row.avgHeartRate,
            profile: profile,
            date: row.date
        )
        return row
    }

    private static func clamp(_ value: Int, min: Int, max: Int) -> Int {
        Swift.max(min, Swift.min(max, value))
    }
}

enum ActivityExporter {
    static func exportActivitiesJSON(activities: [Activity], to directory: URL) throws -> URL {
        let fm = FileManager.default
        if !fm.fileExists(atPath: directory.path) {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let fileName = "activities-export-\(formatter.string(from: Date())).json"
        let url = directory.appendingPathComponent(fileName)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(activities)
        try data.write(to: url, options: .atomic)
        return url
    }
}

func mergeWellnessSamples(_ samples: [WellnessSample]) -> [WellnessSample] {
    let calendar = Calendar.current
    var dict: [String: WellnessSample] = [:]

    for sample in samples {
        let day = calendar.startOfDay(for: sample.date)
        let normalizedAthlete = sample.athleteName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let athleteToken = (normalizedAthlete?.isEmpty == false)
            ? normalizedAthlete!.lowercased()
            : AthletePanel.unknownAthleteToken
        let key = "\(athleteToken)|\(day.timeIntervalSince1970)"
        var merged = dict[key] ?? WellnessSample(date: day, athleteName: sample.athleteName)
        if merged.athleteName == nil {
            merged.athleteName = sample.athleteName
        }
        if let hrv = sample.hrv { merged.hrv = hrv }
        if let rhr = sample.restingHR { merged.restingHR = rhr }
        if let w = sample.weightKg { merged.weightKg = w }
        if let sleepHours = sample.sleepHours { merged.sleepHours = sleepHours }
        if let sleepScore = sample.sleepScore { merged.sleepScore = sleepScore }
        dict[key] = merged
    }

    return dict.values.sorted { $0.date > $1.date }
}
