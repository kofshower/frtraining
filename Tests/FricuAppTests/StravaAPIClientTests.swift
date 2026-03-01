import Foundation
import XCTest
@testable import FricuApp

final class StravaAPIClientTests: XCTestCase {
    override func setUp() {
        super.setUp()
        URLProtocolStub.reset()
    }

    override func tearDown() {
        URLProtocolStub.reset()
        super.tearDown()
    }

    func testEnsureAccessTokenUsesCachedAccessTokenWhenExpiryUnknown() async throws {
        URLProtocolStub.handler = { _ in
            XCTFail("should not hit network when cached token is usable")
            throw URLError(.badServerResponse)
        }

        var profile = AthleteProfile.default
        profile.stravaClientID = "12345"
        profile.stravaClientSecret = "secret"
        profile.stravaRefreshToken = "refresh-1"
        profile.stravaAccessToken = "cached-access"
        profile.stravaAccessTokenExpiresAt = nil

        let client = StravaAPIClient(session: makeStubbedSession())
        let auth = try await client.ensureAccessToken(profile: profile)

        XCTAssertEqual(auth.accessToken, "cached-access")
        XCTAssertEqual(auth.refreshToken, "refresh-1")
        XCTAssertNil(auth.expiresAt)
        XCTAssertEqual(URLProtocolStub.requests.count, 0)
    }

    func testEnsureAccessTokenRefreshesWhenCachedTokenExpired() async throws {
        let now = Int(Date().timeIntervalSince1970)
        URLProtocolStub.handler = { [self] request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.absoluteString, "https://www.strava.com/oauth/token")
            let body = self.bodyString(from: request)
            XCTAssertTrue(body.contains("grant_type=refresh_token"))
            XCTAssertTrue(body.contains("client_id=12345"))

            let payload = """
            {"access_token":"new-access","refresh_token":"new-refresh","expires_at":\(now + 3600)}
            """
            let data = Data(payload.utf8)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, data)
        }

        var profile = AthleteProfile.default
        profile.stravaClientID = "12345"
        profile.stravaClientSecret = "secret"
        profile.stravaRefreshToken = "refresh-1"
        profile.stravaAccessToken = "stale-access"
        profile.stravaAccessTokenExpiresAt = now - 60

        let client = StravaAPIClient(session: makeStubbedSession())
        let auth = try await client.ensureAccessToken(profile: profile)

        XCTAssertEqual(auth.accessToken, "new-access")
        XCTAssertEqual(auth.refreshToken, "new-refresh")
        XCTAssertEqual(auth.expiresAt, now + 3600)
        XCTAssertEqual(URLProtocolStub.requests.count, 1)
    }

    private func makeStubbedSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        return URLSession(configuration: configuration)
    }

    private func bodyString(from request: URLRequest) -> String {
        if let body = request.httpBody, !body.isEmpty {
            return String(data: body, encoding: .utf8) ?? ""
        }
        guard let stream = request.httpBodyStream else {
            return ""
        }
        stream.open()
        defer { stream.close() }

        var data = Data()
        let bufferSize = 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        while stream.hasBytesAvailable {
            let count = stream.read(buffer, maxLength: bufferSize)
            if count < 0 {
                break
            }
            if count == 0 {
                break
            }
            data.append(buffer, count: count)
        }
        return String(data: data, encoding: .utf8) ?? ""
    }
}

private final class URLProtocolStub: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    private static var storedRequests: [URLRequest] = []
    private static let lock = NSLock()

    static var requests: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return storedRequests
    }

    static func reset() {
        lock.lock()
        handler = nil
        storedRequests = []
        lock.unlock()
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
            URLProtocolStub.lock.lock()
            URLProtocolStub.storedRequests.append(request)
            let currentHandler = URLProtocolStub.handler
            URLProtocolStub.lock.unlock()

            guard let handler = currentHandler else {
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
