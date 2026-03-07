import Foundation
import XCTest
@testable import FricuApp

/// Validates `RemoteHTTPRepository.loadActivities()` against different server payload shapes.
final class RemoteHTTPRepositoryActivitiesFallbackTests: XCTestCase {
    override func setUp() {
        super.setUp()
        RemoteHTTPRepositoryURLProtocolStub.reset()
    }

    override func tearDown() {
        RemoteHTTPRepositoryURLProtocolStub.reset()
        super.tearDown()
    }

    /// Ensures the repository can decode the standard activities array payload.
    func testLoadActivitiesDecodesArrayPayload() throws {
        RemoteHTTPRepositoryURLProtocolStub.handler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/v1/data/activities")
            let payload = """
            [
              {
                "id": "4EB89DA3-9F30-4B4A-96E2-62A0A6604AC9",
                "date": "2025-03-01T00:00:00Z",
                "sport": "cycling",
                "durationSec": 3600,
                "distanceKm": 40,
                "tss": 80,
                "normalizedPower": 220,
                "avgHeartRate": 145,
                "intervals": [],
                "notes": ""
              }
            ]
            """
            return Self.makeResponse(for: request, statusCode: 200, body: payload)
        }

        let repository = try makeRepository()
        let rows = try repository.loadActivities()
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.sport, .cycling)
        XCTAssertEqual(rows.first?.durationSec, 3600)
    }

    /// Ensures the repository can decode compatibility snapshot envelopes that contain `activities`.
    func testLoadActivitiesDecodesSnapshotEnvelopePayload() throws {
        RemoteHTTPRepositoryURLProtocolStub.handler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/v1/data/activities")
            let payload = """
            {
              "activities": [
                {
                  "id": "8F78A3F6-8A5C-4CD2-9F40-9C18A24540AB",
                  "date": "2025-03-02T00:00:00Z",
                  "sport": "running",
                  "durationSec": 1800,
                  "distanceKm": 6,
                  "tss": 45,
                  "normalizedPower": null,
                  "avgHeartRate": 152,
                  "intervals": [],
                  "notes": ""
                }
              ],
              "updatedAt": "2025-03-02T00:00:00Z"
            }
            """
            return Self.makeResponse(for: request, statusCode: 200, body: payload)
        }

        let repository = try makeRepository()
        let rows = try repository.loadActivities()
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.sport, .running)
        XCTAssertEqual(rows.first?.tss, 45)
    }

    /// Ensures malformed payloads still surface a decoding failure to callers.
    func testLoadActivitiesThrowsForInvalidPayload() throws {
        RemoteHTTPRepositoryURLProtocolStub.handler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            return Self.makeResponse(for: request, statusCode: 200, body: "{\"unexpected\":true}")
        }

        let repository = try makeRepository()
        XCTAssertThrowsError(try repository.loadActivities())
    }

    /// Creates a repository instance backed by URL protocol stubs.
    private func makeRepository() throws -> RemoteHTTPRepository {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RemoteHTTPRepositoryURLProtocolStub.self]
        let session = URLSession(configuration: configuration)
        return try RemoteHTTPRepository(baseURL: URL(string: "http://127.0.0.1:8080")!, session: session)
    }

    /// Builds a deterministic HTTP response tuple used by the URL protocol stub.
    private static func makeResponse(for request: URLRequest, statusCode: Int, body: String) -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        return (response, Data(body.utf8))
    }
}

/// URL loading stub for repository-level HTTP tests.
private final class RemoteHTTPRepositoryURLProtocolStub: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    /// Resets shared test state between tests.
    static func reset() {
        handler = nil
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let client else { return }
        do {
            guard let handler = Self.handler else {
                throw URLError(.badServerResponse)
            }
            let (response, data) = try handler(request)
            client.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client.urlProtocol(self, didLoad: data)
            client.urlProtocolDidFinishLoading(self)
        } catch {
            client.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
