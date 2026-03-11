import Foundation
import XCTest
@testable import FricuApp

/// End-to-end persistence tests for app profile/activity state and server data.
final class ProfilePersistenceIntegrationTests: XCTestCase {
    override func setUp() {
        super.setUp()
        StatefulRemoteRepositoryURLProtocolStub.reset()
    }

    override func tearDown() {
        StatefulRemoteRepositoryURLProtocolStub.reset()
        super.tearDown()
    }

    /// Simulates app restart: save to server, recreate repository, and read back profile + activities.
    func testProfileAndActivitiesRoundTripAcrossRepositoryRestart() throws {
        let accountID = makeAccountID("roundtrip")
        try cleanAccountArtifacts(accountID: accountID)

        let repository = try makeRepository(accountID: accountID)
        var profile = AthleteProfile.default
        profile.cyclingFTPWatts = 312
        profile.runningFTPWatts = 298
        profile.cyclingThresholdHeartRate = 178
        profile.intervalsAPIKey = "intervals-key-1"
        profile.stravaClientID = "strava-id-a"

        try repository.saveProfile(profile)

        let activity = Activity(
            id: UUID(uuidString: "A622C9F0-5CE8-47F2-84E8-A6D39C8D1C75")!,
            date: Date(timeIntervalSince1970: 1_773_017_100),
            sport: .cycling,
            durationSec: 3600,
            distanceKm: 31.4,
            tss: 72,
            normalizedPower: 231,
            avgHeartRate: 149,
            notes: "persistence-test"
        )
        try repository.saveActivities([activity])

        // "Restart" by constructing a new repository instance for the same account.
        let reloadedRepository = try makeRepository(accountID: accountID)
        let loadedProfile = try reloadedRepository.loadProfile()
        let loadedActivities = try reloadedRepository.loadActivities()

        XCTAssertEqual(loadedProfile.cyclingFTPWatts, 312)
        XCTAssertEqual(loadedProfile.runningFTPWatts, 298)
        XCTAssertEqual(loadedProfile.cyclingThresholdHeartRate, 178)
        XCTAssertEqual(loadedProfile.intervalsAPIKey, "intervals-key-1")
        XCTAssertEqual(loadedActivities.count, 1)
        XCTAssertEqual(loadedActivities[0].id, activity.id)
        XCTAssertEqual(loadedActivities[0].normalizedPower, 231)
        XCTAssertEqual(loadedActivities[0].avgHeartRate, 149)

        let requests = StatefulRemoteRepositoryURLProtocolStub.requests
        XCTAssertTrue(requests.contains { $0.value(forHTTPHeaderField: "X-Account-Id") == accountID })
        XCTAssertTrue(requests.contains { $0.value(forHTTPHeaderField: "X-Log-Id")?.hasPrefix("cli-profile-") == true })
        XCTAssertTrue(requests.contains { $0.value(forHTTPHeaderField: "X-Log-Id")?.hasPrefix("cli-activities-") == true })
    }

    /// Verifies offline read fallback from local profile cache when GET fails.
    func testLoadProfileFallsBackToCacheWhenServerUnavailable() throws {
        let accountID = makeAccountID("cache-fallback")
        try cleanAccountArtifacts(accountID: accountID)

        let onlineRepository = try makeRepository(accountID: accountID)
        var profile = AthleteProfile.default
        profile.cyclingFTPWatts = 299
        profile.stravaClientID = "cached-value"
        try onlineRepository.saveProfile(profile)

        StatefulRemoteRepositoryURLProtocolStub.failGetProfile = true
        let offlineRepository = try makeRepository(accountID: accountID)
        let loaded = try offlineRepository.loadProfile()

        XCTAssertEqual(loaded.cyclingFTPWatts, 299)
        XCTAssertEqual(loaded.stravaClientID, "cached-value")
    }

    /// Verifies pending-write fallback and replay: write fails, local read still works, replay later succeeds.
    func testPendingProfileWriteReplaysAndBecomesServerReadable() throws {
        let accountID = makeAccountID("pending-replay")
        try cleanAccountArtifacts(accountID: accountID)

        let repository = try makeRepository(accountID: accountID)
        StatefulRemoteRepositoryURLProtocolStub.failPutProfile = true

        var profile = AthleteProfile.default
        profile.cyclingFTPWatts = 345
        profile.intervalsAPIKey = "pending-key"

        XCTAssertThrowsError(try repository.saveProfile(profile))
        XCTAssertEqual(try pendingWriteCount(accountID: accountID), 1)
        let queuedProfile = try queuedProfilePayload(accountID: accountID)
        XCTAssertEqual(queuedProfile?.cyclingFTPWatts, 345)
        XCTAssertEqual(queuedProfile?.intervalsAPIKey, "pending-key")

        StatefulRemoteRepositoryURLProtocolStub.failPutProfile = false
        try repository.flushPendingWrites()
        XCTAssertEqual(try pendingWriteCount(accountID: accountID), 0)

        let restarted = try makeRepository(accountID: accountID)
        let loadedFromServer = try restarted.loadProfile()
        XCTAssertEqual(loadedFromServer.cyclingFTPWatts, 345)
        XCTAssertEqual(loadedFromServer.intervalsAPIKey, "pending-key")
    }

    /// Verifies brand-new account fallback still yields a valid default profile.
    func testLoadProfileReturnsDefaultWhenNoServerNoLocalData() throws {
        let accountID = makeAccountID("default-fallback")
        try cleanAccountArtifacts(accountID: accountID)

        StatefulRemoteRepositoryURLProtocolStub.returnNotFoundForMissingProfile = true
        let repository = try makeRepository(accountID: accountID)
        let loaded = try repository.loadProfile()

        XCTAssertEqual(loaded.cyclingFTPWatts, AthleteProfile.default.cyclingFTPWatts)
        XCTAssertEqual(loaded.runningThresholdHeartRate, AthleteProfile.default.runningThresholdHeartRate)
    }

    func testAppSettingsRoundTripAcrossRepositoryRestartIncludesPerChartModes() throws {
        let accountID = makeAccountID("app-settings-chart-modes")
        try cleanAccountArtifacts(accountID: accountID)

        let repository = try makeRepository(accountID: accountID)
        let snapshot = AppSettingsSnapshot(
            trainerRiderConnectionStoreData: nil,
            appLanguageRawValue: "zh-Hans",
            chartDisplayModeRawValue: AppChartDisplayMode.bar.rawValue,
            chartDisplayModesByStorageKey: [
                "fricu.chart.display.mode.v2.dashboard.daily_tss": AppChartDisplayMode.flame.rawValue,
                "fricu.chart.display.mode.v2.activity.detail.hrpw_scatter": AppChartDisplayMode.pie.rawValue,
                "fricu.chart.bike.power": "scatter",
                "fricu.chart.real_map.speed": "area"
            ],
            nutritionUSDAAPIKey: nil,
            stravaPullRecentDays: 14,
            serverHost: "127.0.0.1",
            serverPort: 8080,
            serverBaseURL: "http://127.0.0.1:8080"
        )

        try repository.saveAppSettings(snapshot)

        let reloadedRepository = try makeRepository(accountID: accountID)
        let loaded = try reloadedRepository.loadAppSettings()

        XCTAssertEqual(loaded?.appLanguageRawValue, "zh-Hans")
        XCTAssertEqual(loaded?.chartDisplayModeRawValue, AppChartDisplayMode.bar.rawValue)
        XCTAssertEqual(
            loaded?.chartDisplayModesByStorageKey?["fricu.chart.display.mode.v2.dashboard.daily_tss"],
            AppChartDisplayMode.flame.rawValue
        )
        XCTAssertEqual(
            loaded?.chartDisplayModesByStorageKey?["fricu.chart.display.mode.v2.activity.detail.hrpw_scatter"],
            AppChartDisplayMode.pie.rawValue
        )
        XCTAssertEqual(loaded?.chartDisplayModesByStorageKey?["fricu.chart.bike.power"], "scatter")
        XCTAssertEqual(loaded?.chartDisplayModesByStorageKey?["fricu.chart.real_map.speed"], "area")
    }

    private func makeRepository(accountID: String) throws -> RemoteHTTPRepository {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StatefulRemoteRepositoryURLProtocolStub.self]
        let session = URLSession(configuration: configuration)
        return try RemoteHTTPRepository(
            baseURL: URL(string: "http://127.0.0.1:8080")!,
            session: session,
            accountID: accountID
        )
    }

    private func makeAccountID(_ suffix: String) -> String {
        "persistence-\(suffix)-\(UUID().uuidString.lowercased())"
    }

    private func cleanAccountArtifacts(accountID: String) throws {
        let dir = accountArtifactsDirectory(accountID: accountID)
        if FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.removeItem(at: dir)
        }
    }

    private func pendingWriteCount(accountID: String) throws -> Int {
        let url = accountArtifactsDirectory(accountID: accountID).appendingPathComponent("remote_pending_writes.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return 0 }
        let data = try Data(contentsOf: url)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return 0
        }
        return json.count
    }

    private func queuedProfilePayload(accountID: String) throws -> AthleteProfile? {
        struct PendingWriteEnvelope: Decodable {
            var key: String
            var payload: Data
        }
        let url = accountArtifactsDirectory(accountID: accountID).appendingPathComponent("remote_pending_writes.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        let rows = try JSONDecoder().decode([PendingWriteEnvelope].self, from: data)
        guard let profileRow = rows.first(where: { $0.key == "profile" }) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(AthleteProfile.self, from: profileRow.payload)
    }

    private func accountArtifactsDirectory(accountID: String) -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let sanitized = sanitizedAccountID(accountID)
        return appSupport
            .appendingPathComponent("fricu", isDirectory: true)
            .appendingPathComponent("accounts", isDirectory: true)
            .appendingPathComponent(sanitized, isDirectory: true)
    }

    private func sanitizedAccountID(_ accountID: String) -> String {
        let mapped = accountID.map { character -> Character in
            if character.isASCII && (character.isLetter || character.isNumber || character == "-" || character == "_") {
                return character
            }
            return "_"
        }
        let value = String(mapped)
        return value.isEmpty ? "account" : value
    }
}

/// Stateful URL protocol used as an in-memory server for remote repository persistence tests.
private final class StatefulRemoteRepositoryURLProtocolStub: URLProtocol {
    static var storage: [String: Data] = [:]
    static var requests: [URLRequest] = []
    static var failPutProfile = false
    static var failGetProfile = false
    static var returnNotFoundForMissingProfile = false

    static func reset() {
        storage = [:]
        requests = []
        failPutProfile = false
        failGetProfile = false
        returnNotFoundForMissingProfile = false
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let client else { return }
        Self.requests.append(request)

        do {
            let accountID = request.value(forHTTPHeaderField: "X-Account-Id") ?? "__missing__"
            guard let path = request.url?.path else {
                throw URLError(.badURL)
            }
            let key = path.replacingOccurrences(of: "/v1/data/", with: "")
            let storageKey = "\(accountID)::\(key)"

            if request.httpMethod == "PUT" {
                if key == "profile", Self.failPutProfile {
                    throw URLError(.networkConnectionLost)
                }
                Self.storage[storageKey] = requestBodyData(from: request)
                send(statusCode: 204, body: Data(), client: client)
                return
            }

            if request.httpMethod == "GET" {
                if key == "profile", Self.failGetProfile {
                    throw URLError(.timedOut)
                }
                if let payload = Self.storage[storageKey] {
                    send(statusCode: 200, body: payload, client: client)
                    return
                }
                if key == "profile", Self.returnNotFoundForMissingProfile {
                    send(statusCode: 404, body: Data("{\"error\":\"not_found\"}".utf8), client: client)
                    return
                }
                send(statusCode: 200, body: Data("[]".utf8), client: client)
                return
            }

            send(statusCode: 405, body: Data(), client: client)
        } catch {
            client.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    private func send(statusCode: Int, body: Data, client: URLProtocolClient) {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client.urlProtocol(self, didLoad: body)
        client.urlProtocolDidFinishLoading(self)
    }

    private func requestBodyData(from request: URLRequest) -> Data {
        if let body = request.httpBody {
            return body
        }
        guard let stream = request.httpBodyStream else {
            return Data()
        }
        stream.open()
        defer { stream.close() }
        var buffer = [UInt8](repeating: 0, count: 4096)
        var data = Data()
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            if read > 0 {
                data.append(buffer, count: read)
            } else {
                break
            }
        }
        return data
    }
}
