import Foundation

enum IntervalsAPIError: Error, LocalizedError {
    case missingAPIKey
    case badResponse
    case requestFailed(Int, String)
    case malformedPayload

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Intervals.icu API key is missing. Add it in Settings first."
        case .badResponse:
            return "Intervals.icu returned an invalid response."
        case let .requestFailed(code, body):
            return "Intervals.icu request failed (\(code)): \(body)"
        case .malformedPayload:
            return "Intervals.icu returned unexpected JSON payload."
        }
    }
}

final class IntervalsAPIClient {
    private let apiKey: String
    private let session: URLSession
    private let baseURL = URL(string: "https://intervals.icu")!

    init(apiKey: String, session: URLSession = .shared) {
        self.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.session = session
    }

    func fetchActivities(oldest: Date, newest: Date, profile: AthleteProfile) async throws -> [Activity] {
        var components = URLComponents(url: baseURL.appending(path: "/api/v1/athlete/0/activities"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "oldest", value: IntervalsDateFormatter.day.string(from: oldest)),
            URLQueryItem(name: "newest", value: IntervalsDateFormatter.day.string(from: newest))
        ]

        let data = try await send(request: request(url: components?.url, method: "GET"))
        guard let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw IntervalsAPIError.malformedPayload
        }

        return rows.compactMap { row in
            guard let id = row["id"] else { return nil }
            let externalID = "intervals:\(JSONValue.string(id) ?? "unknown")"

            let date = IntervalsDateFormatter.parseDateTimeLocal(JSONValue.string(row["start_date_local"]))
                ?? IntervalsDateFormatter.parseDateTimeLocal(JSONValue.string(row["start_date"]))
                ?? Date()

            let sport = mapActivityType(JSONValue.string(row["type"]) ?? "Ride")
            let durationSec = max(1, Int(JSONValue.double(row["moving_time"]) ?? 0))
            let distanceKm = max(0, (JSONValue.double(row["distance"]) ?? 0) / 1000.0)
            let avgHR = JSONValue.int(row["average_heartrate"])
            let np = JSONValue.int(row["weighted_average_watts"])
            let avgPower = JSONValue.int(row["average_watts"])
            let tss = JSONValue.int(row["icu_training_load"]) ?? TSSEstimator.estimate(
                durationSec: durationSec,
                sport: sport,
                avgPower: avgPower,
                normalizedPower: np,
                avgHeartRate: avgHR,
                profile: profile,
                date: date
            )
            let notes = [JSONValue.string(row["name"]), JSONValue.string(row["description"])]
                .compactMap { $0 }
                .joined(separator: " · ")

            return Activity(
                date: date,
                sport: sport,
                durationSec: durationSec,
                distanceKm: distanceKm,
                tss: max(0, tss),
                normalizedPower: np ?? avgPower,
                avgHeartRate: avgHR,
                notes: notes.isEmpty ? "Synced from Intervals.icu" : notes,
                externalID: externalID
            )
        }
    }

    func uploadActivity(_ activity: Activity) async throws -> String {
        let externalID = normalizedExternalID(for: activity)
        let fileData: Data
        let ext: String

        if
            let encoded = activity.sourceFileBase64,
            let decoded = Data(base64Encoded: encoded),
            let fileType = activity.sourceFileType,
            !fileType.isEmpty
        {
            fileData = decoded
            ext = fileType
        } else {
            fileData = TCXWriter.export(activity: activity)
            ext = "tcx"
        }

        var components = URLComponents(url: baseURL.appending(path: "/api/v1/athlete/0/activities"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "name", value: activity.notes.isEmpty ? "Fricu Activity" : activity.notes),
            URLQueryItem(name: "description", value: "Uploaded from Fricu"),
            URLQueryItem(name: "external_id", value: externalID)
        ]

        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"activity.\(ext)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType(for: ext))\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        var req = request(url: components?.url, method: "POST")
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.httpBody = body

        let data = try await send(request: req)
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let id = JSONValue.string(json["id"] ?? json["activity_id"]) {
            return "intervals:\(id)"
        }

        return externalID
    }

    func fetchWorkouts(oldest: Date, newest: Date) async throws -> [PlannedWorkout] {
        var components = URLComponents(url: baseURL.appending(path: "/api/v1/athlete/0/events"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "oldest", value: IntervalsDateFormatter.day.string(from: oldest)),
            URLQueryItem(name: "newest", value: IntervalsDateFormatter.day.string(from: newest))
        ]

        let data = try await send(request: request(url: components?.url, method: "GET"))
        guard let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw IntervalsAPIError.malformedPayload
        }

        return rows
            .filter { row in
                let category = (JSONValue.string(row["category"]) ?? "").uppercased()
                return category == "WORKOUT" || category.isEmpty
            }
            .map { row in
                let name = JSONValue.string(row["name"]) ?? "Intervals Workout"
                let description = JSONValue.string(row["description"]) ?? ""
                let movingTime = JSONValue.int(row["moving_time"]) ?? 0
                let sport = mapActivityType(JSONValue.string(row["type"]) ?? "Ride")
                let scheduledDate = IntervalsDateFormatter.parseDateTimeLocal(JSONValue.string(row["start_date_local"]))
                    ?? IntervalsDateFormatter.parseDateTimeLocal(JSONValue.string(row["start_date"]))

                let segments = WorkoutDescriptionParser.parse(description: description, fallbackMovingTimeSec: movingTime)
                let externalID = JSONValue.string(row["external_id"]) ?? JSONValue.string(row["id"]).map { "intervals:\($0)" }

                return PlannedWorkout(
                    createdAt: scheduledDate ?? Date(),
                    name: name,
                    sport: sport,
                    segments: segments,
                    scheduledDate: scheduledDate,
                    externalID: externalID
                )
            }
    }

    func upsertWorkouts(_ workouts: [PlannedWorkout]) async throws {
        let payload: [[String: Any]] = workouts.map { workout in
            let externalID = workout.externalID?.hasPrefix("intervals:") == true ? workout.externalID! : "fricu-workout-\(workout.id.uuidString)"
            let startDate = workout.scheduledDate ?? workout.createdAt
            return [
                "category": "WORKOUT",
                "start_date_local": IntervalsDateFormatter.dateTimeLocal.string(from: startDate),
                "type": eventType(for: workout.sport),
                "name": workout.name,
                "description": WorkoutDescriptionParser.render(segments: workout.segments),
                "moving_time": workout.totalMinutes * 60,
                "target": "POWER",
                "external_id": externalID
            ]
        }

        var components = URLComponents(url: baseURL.appending(path: "/api/v1/athlete/0/events/bulk"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "upsert", value: "true")]

        var req = request(url: components?.url, method: "POST")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)
        _ = try await send(request: req)
    }

    func fetchEvents(oldest: Date, newest: Date) async throws -> [CalendarEvent] {
        var components = URLComponents(url: baseURL.appending(path: "/api/v1/athlete/0/events"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "oldest", value: IntervalsDateFormatter.day.string(from: oldest)),
            URLQueryItem(name: "newest", value: IntervalsDateFormatter.day.string(from: newest))
        ]

        let data = try await send(request: request(url: components?.url, method: "GET"))
        guard let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw IntervalsAPIError.malformedPayload
        }

        return rows.compactMap { row in
            let start = IntervalsDateFormatter.parseDateTimeLocal(JSONValue.string(row["start_date_local"]))
                ?? IntervalsDateFormatter.parseDateTimeLocal(JSONValue.string(row["start_date"]))

            guard let startDate = start else { return nil }

            let endDate = IntervalsDateFormatter.parseDateTimeLocal(JSONValue.string(row["end_date_local"]))
                ?? IntervalsDateFormatter.parseDateTimeLocal(JSONValue.string(row["end_date"]))

            let type = JSONValue.string(row["type"]) ?? "Other"
            let category = (JSONValue.string(row["category"]) ?? "OTHER").uppercased()
            let name = JSONValue.string(row["name"]) ?? "\(type) event"
            let notes = JSONValue.string(row["description"]) ?? ""
            let externalID = JSONValue.string(row["external_id"])
                ?? JSONValue.string(row["id"]).map { "intervals:event:\($0)" }

            return CalendarEvent(
                startDate: startDate,
                endDate: endDate,
                type: type,
                category: category,
                name: name,
                notes: notes,
                externalID: externalID
            )
        }
    }

    func fetchWellness(oldest: Date, newest: Date) async throws -> [WellnessSample] {
        var components = URLComponents(url: baseURL.appending(path: "/api/v1/athlete/0/wellness"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "oldest", value: IntervalsDateFormatter.day.string(from: oldest)),
            URLQueryItem(name: "newest", value: IntervalsDateFormatter.day.string(from: newest))
        ]

        let data = try await send(request: request(url: components?.url, method: "GET"))
        guard let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw IntervalsAPIError.malformedPayload
        }

        return rows.compactMap { row in
            let dateString = JSONValue.string(row["id"]) ?? JSONValue.string(row["date"])
            guard let date = IntervalsDateFormatter.parseDay(dateString) else { return nil }

            let hrv = JSONValue.double(row["hrv"]) ?? JSONValue.double(row["rmssd"]) ?? JSONValue.double(row["hrv_rmssd"])
            let restingHR = JSONValue.double(row["resting_hr"]) ?? JSONValue.double(row["restingHR"])
            let weight = JSONValue.double(row["weight"]) ?? JSONValue.double(row["weight_kg"])
            let sleepHours = parseSleepHours(row)
            let sleepScore = JSONValue.double(row["sleep_score"]) ?? JSONValue.double(row["sleepScore"])

            return WellnessSample(
                date: date,
                hrv: hrv,
                restingHR: restingHR,
                weightKg: weight,
                sleepHours: sleepHours,
                sleepScore: sleepScore
            )
        }
    }

    private func parseSleepHours(_ row: [String: Any]) -> Double? {
        if let hours = JSONValue.double(row["sleep_hours"]) ?? JSONValue.double(row["sleepHours"]) {
            return max(0, hours)
        }
        if let sec = JSONValue.double(row["sleep_seconds"]) ?? JSONValue.double(row["sleep_duration_sec"]) {
            return max(0, sec) / 3600.0
        }
        if let min = JSONValue.double(row["sleep_minutes"]) ?? JSONValue.double(row["sleep_duration_min"]) {
            return max(0, min) / 60.0
        }
        return nil
    }

    private func normalizedExternalID(for activity: Activity) -> String {
        if let existing = activity.externalID, !existing.isEmpty {
            return existing
        }
        return "fricu-activity-\(activity.id.uuidString)"
    }

    private func request(url: URL?, method: String) -> URLRequest {
        var req = URLRequest(url: url ?? baseURL)
        req.httpMethod = method
        req.timeoutInterval = 45

        let token = Data("API_KEY:\(apiKey)".utf8).base64EncodedString()
        req.setValue("Basic \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        return req
    }

    private func send(request: URLRequest) async throws -> Data {
        guard !apiKey.isEmpty else {
            throw IntervalsAPIError.missingAPIKey
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw IntervalsAPIError.badResponse
        }

        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw IntervalsAPIError.requestFailed(http.statusCode, body)
        }

        return data
    }

    private func mapActivityType(_ raw: String) -> SportType {
        let value = raw.lowercased()
        if value.contains("run") { return .running }
        if value.contains("swim") { return .swimming }
        if value.contains("ride") || value.contains("bike") || value.contains("cycle") { return .cycling }
        return .strength
    }

    private func eventType(for sport: SportType) -> String {
        switch sport {
        case .cycling: return "Ride"
        case .running: return "Run"
        case .swimming: return "Swim"
        case .strength: return "WeightTraining"
        }
    }

    private func mimeType(for ext: String) -> String {
        switch ext.lowercased() {
        case "gpx": return "application/gpx+xml"
        case "tcx": return "application/vnd.garmin.tcx+xml"
        default: return "application/octet-stream"
        }
    }
}

enum WorkoutDescriptionParser {
    static func parse(description: String, fallbackMovingTimeSec: Int) -> [WorkoutSegment] {
        let lines = description
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var segments: [WorkoutSegment] = []

        for line in lines {
            if let segment = parseLine(line) {
                segments.append(segment)
            }
        }

        if segments.isEmpty {
            let fallbackMin = max(1, fallbackMovingTimeSec / 60)
            segments = [WorkoutSegment(minutes: fallbackMin, intensityPercentFTP: 70, note: "Imported from Intervals.icu")]
        }

        return segments
    }

    static func render(segments: [WorkoutSegment]) -> String {
        segments.map { seg in
            let note = seg.note.isEmpty ? "" : " \(seg.note)"
            return "- \(seg.minutes)m \(seg.intensityPercentFTP)%\(note)"
        }
        .joined(separator: "\n")
    }

    private static func parseLine(_ line: String) -> WorkoutSegment? {
        let clean = line
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "@", with: " ")
            .lowercased()

        let numbers = clean
            .split { !$0.isNumber }
            .compactMap { Int($0) }

        guard let first = numbers.first else { return nil }
        let minutes = max(1, first)
        let intensity = numbers.count > 1 ? min(180, max(30, numbers[1])) : 70

        return WorkoutSegment(minutes: minutes, intensityPercentFTP: intensity, note: line)
    }
}

enum JSONValue {
    static func string(_ any: Any?) -> String? {
        switch any {
        case let value as String:
            return value
        case let value as NSNumber:
            return value.stringValue
        default:
            return nil
        }
    }

    static func int(_ any: Any?) -> Int? {
        if let value = any as? Int { return value }
        if let value = any as? NSNumber { return value.intValue }
        if let value = any as? String, let int = Int(value) { return int }
        if let value = any as? String, let double = Double(value) { return Int(double) }
        return nil
    }

    static func double(_ any: Any?) -> Double? {
        if let value = any as? Double { return value }
        if let value = any as? NSNumber { return value.doubleValue }
        if let value = any as? String {
            if value.lowercased() == "infinity" { return nil }
            return Double(value)
        }
        return nil
    }
}

enum IntervalsDateFormatter {
    static let day: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static let dateTimeLocal: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return f
    }()

    static func parseDay(_ value: String?) -> Date? {
        guard let value else { return nil }
        return day.date(from: value)
    }

    static func parseDateTimeLocal(_ value: String?) -> Date? {
        guard let value else { return nil }
        if let parsed = dateTimeLocal.date(from: value) { return parsed }
        return DateParsers.parseISO8601(value)
    }
}
