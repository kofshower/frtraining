import Foundation
import Network

private final class StravaOAuthResolutionGate: @unchecked Sendable {
    private var resolved = false
    private let lock = NSLock()

    func once(_ action: () -> Void) {
        lock.lock()
        defer { lock.unlock() }
        guard !resolved else { return }
        resolved = true
        action()
    }
}

struct StravaOAuthCallbackPayload {
    var code: String?
    var state: String?
    var error: String?
    var errorDescription: String?
}

final class StravaOAuthLocalCallbackServer: @unchecked Sendable {
    private let host: String
    private let port: UInt16
    private let callbackPath: String

    init(redirectURI: String) throws {
        guard let url = URL(string: redirectURI),
              let scheme = url.scheme?.lowercased(),
              scheme == "http",
              let host = url.host,
              host.lowercased() == "127.0.0.1" || host.lowercased() == "localhost"
        else {
            throw StravaAPIError.invalidOAuthRedirectURI
        }

        guard let rawPort = url.port, rawPort > 0, rawPort <= Int(UInt16.max) else {
            throw StravaAPIError.invalidOAuthRedirectURI
        }

        let path = url.path.trimmingCharacters(in: .whitespacesAndNewlines)
        self.host = host
        self.port = UInt16(rawPort)
        self.callbackPath = path.isEmpty ? "/callback" : path
    }

    func awaitCallback(timeoutSec: UInt64 = 240) async throws -> StravaOAuthCallbackPayload {
        return try await withThrowingTaskGroup(of: StravaOAuthCallbackPayload.self) { group in
            group.addTask { [host, port, callbackPath] in
                try await Self.waitForSingleCallback(host: host, port: port, expectedPath: callbackPath)
            }
            group.addTask {
                try await Task.sleep(nanoseconds: timeoutSec * 1_000_000_000)
                throw StravaAPIError.oauthTimeout
            }

            guard let result = try await group.next() else {
                throw StravaAPIError.oauthTimeout
            }
            group.cancelAll()
            return result
        }
    }

    private static func waitForSingleCallback(
        host: String,
        port: UInt16,
        expectedPath: String
    ) async throws -> StravaOAuthCallbackPayload {
        guard let endpointPort = NWEndpoint.Port(rawValue: port) else {
            throw StravaAPIError.invalidOAuthRedirectURI
        }

        return try await withCheckedThrowingContinuation { continuation in
            let queue = DispatchQueue(label: "fricu.strava.oauth.callback")
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true

            let listener: NWListener
            do {
                listener = try NWListener(using: parameters, on: endpointPort)
            } catch {
                continuation.resume(throwing: error)
                return
            }

            let gate = StravaOAuthResolutionGate()
            let finish: @Sendable (Result<StravaOAuthCallbackPayload, Error>) -> Void = { result in
                gate.once {
                    listener.cancel()
                    continuation.resume(with: result)
                }
            }

            listener.stateUpdateHandler = { state in
                switch state {
                case .failed(let error):
                    finish(.failure(error))
                default:
                    break
                }
            }

            listener.newConnectionHandler = { connection in
                connection.start(queue: queue)
                readHTTPRequest(on: connection, buffer: Data()) { result in
                    switch result {
                    case .failure:
                        sendResponse(
                            on: connection,
                            statusLine: "HTTP/1.1 400 Bad Request",
                            html: "<html><body><h3>Bad request</h3></body></html>"
                        )
                    case .success(let requestText):
                        guard let target = parseTargetPath(from: requestText) else {
                            sendResponse(
                                on: connection,
                                statusLine: "HTTP/1.1 400 Bad Request",
                                html: "<html><body><h3>Missing request path</h3></body></html>"
                            )
                            return
                        }

                        guard let fullURL = URL(string: "http://\(host):\(port)\(target)"),
                              let components = URLComponents(url: fullURL, resolvingAgainstBaseURL: false)
                        else {
                            sendResponse(
                                on: connection,
                                statusLine: "HTTP/1.1 400 Bad Request",
                                html: "<html><body><h3>Invalid callback url</h3></body></html>"
                            )
                            return
                        }

                        guard normalizePath(components.path) == normalizePath(expectedPath) else {
                            sendResponse(
                                on: connection,
                                statusLine: "HTTP/1.1 404 Not Found",
                                html: "<html><body><h3>Not Found</h3></body></html>"
                            )
                            return
                        }

                        let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
                        let callback = StravaOAuthCallbackPayload(
                            code: query["code"],
                            state: query["state"],
                            error: query["error"],
                            errorDescription: query["error_description"]
                        )
                        let successHTML = """
                        <html><body style="font-family:-apple-system,sans-serif;">
                        <h3>Strava OAuth received</h3>
                        <p>You can return to Fricu now.</p>
                        </body></html>
                        """
                        sendResponse(on: connection, statusLine: "HTTP/1.1 200 OK", html: successHTML)
                        finish(.success(callback))
                    }
                }
            }

            listener.start(queue: queue)
        }
    }

    private static func normalizePath(_ path: String) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "/" }
        return trimmed.hasPrefix("/") ? trimmed : "/\(trimmed)"
    }

    private static func parseTargetPath(from request: String) -> String? {
        guard let firstLine = request.components(separatedBy: "\r\n").first else {
            return nil
        }
        let parts = firstLine.split(separator: " ")
        guard parts.count >= 2 else {
            return nil
        }
        return String(parts[1])
    }

    private static func readHTTPRequest(
        on connection: NWConnection,
        buffer: Data,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { data, _, isComplete, error in
            if let error {
                completion(.failure(error))
                return
            }

            var merged = buffer
            if let data {
                merged.append(data)
            }

            let headerTerminator = Data([0x0D, 0x0A, 0x0D, 0x0A]) // \r\n\r\n
            if merged.range(of: headerTerminator) != nil || isComplete {
                let request = String(data: merged, encoding: .utf8) ?? ""
                completion(.success(request))
                return
            }

            readHTTPRequest(on: connection, buffer: merged, completion: completion)
        }
    }

    private static func sendResponse(on connection: NWConnection, statusLine: String, html: String) {
        let body = Data(html.utf8)
        var header = Data()
        header.append(Data("\(statusLine)\r\n".utf8))
        header.append(Data("Content-Type: text/html; charset=utf-8\r\n".utf8))
        header.append(Data("Cache-Control: no-store\r\n".utf8))
        header.append(Data("Content-Length: \(body.count)\r\n".utf8))
        header.append(Data("Connection: close\r\n\r\n".utf8))

        var response = Data()
        response.append(header)
        response.append(body)

        connection.send(content: response, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
