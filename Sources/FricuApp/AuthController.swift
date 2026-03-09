import Foundation
import CryptoKit
import Security

enum AuthProvider: String, Codable, CaseIterable {
    case local
    case google
    case facebook

    var displayName: String {
        switch self {
        case .local:
            return L10n.choose(simplifiedChinese: "账号密码", english: "Password")
        case .google:
            return "Google"
        case .facebook:
            return "Facebook"
        }
    }
}

struct AuthSession: Codable, Equatable {
    var accountID: String
    var displayName: String
    var provider: AuthProvider
    var username: String?
    var email: String?
    var signedInAt: Date
}

private struct LocalAuthAccount: Codable {
    var id: String
    var provider: AuthProvider
    var username: String?
    var email: String?
    var providerSubject: String?
    var displayName: String
    var passwordSaltHex: String?
    var passwordHashHex: String?
    var createdAt: Date
}

private enum AuthControllerError: LocalizedError {
    case invalidInput(String)
    case accountAlreadyExists
    case accountNotFound
    case invalidCredentials
    case oauthProfileMissing

    var errorDescription: String? {
        switch self {
        case let .invalidInput(message):
            return message
        case .accountAlreadyExists:
            return L10n.choose(simplifiedChinese: "账号已存在", english: "Account already exists")
        case .accountNotFound:
            return L10n.choose(simplifiedChinese: "账号不存在", english: "Account not found")
        case .invalidCredentials:
            return L10n.choose(simplifiedChinese: "账号或密码错误", english: "Invalid username or password")
        case .oauthProfileMissing:
            return L10n.choose(simplifiedChinese: "OAuth 信息不完整", english: "Incomplete OAuth profile")
        }
    }
}

@MainActor
final class AuthController: ObservableObject {
    @Published private(set) var currentSession: AuthSession?
    @Published private(set) var isBusy = false
    @Published private(set) var lastError: String?

    private var accounts: [LocalAuthAccount] = []
    private let accountsURL: URL
    private let sessionURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init() {
        let rootURL = AuthController.resolveStorageRoot()
        self.accountsURL = rootURL.appendingPathComponent("accounts.json")
        self.sessionURL = rootURL.appendingPathComponent("session.json")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
        loadFromDisk()
    }

    func registerLocal(username: String, password: String, displayName: String?) throws -> AuthSession {
        let normalizedUsername = try normalizeRequired(
            username,
            field: L10n.choose(simplifiedChinese: "用户名", english: "Username")
        )
        let normalizedPassword = try normalizeRequired(
            password,
            field: L10n.choose(simplifiedChinese: "密码", english: "Password")
        )
        guard normalizedPassword.count >= 6 else {
            throw AuthControllerError.invalidInput(
                L10n.choose(simplifiedChinese: "密码至少 6 位", english: "Password must be at least 6 characters")
            )
        }
        if accounts.contains(where: { ($0.username ?? "").caseInsensitiveCompare(normalizedUsername) == .orderedSame }) {
            throw AuthControllerError.accountAlreadyExists
        }

        let salt = Self.randomHex(bytes: 16)
        let hash = Self.hashPassword(password: normalizedPassword, saltHex: salt)
        let resolvedDisplayName = normalizeOptional(displayName) ?? normalizedUsername
        let account = LocalAuthAccount(
            id: UUID().uuidString.lowercased(),
            provider: .local,
            username: normalizedUsername,
            email: nil,
            providerSubject: nil,
            displayName: resolvedDisplayName,
            passwordSaltHex: salt,
            passwordHashHex: hash,
            createdAt: Date()
        )
        accounts.append(account)
        try persistAccounts()
        let session = makeSession(from: account)
        currentSession = session
        try persistSession(session)
        lastError = nil
        return session
    }

    func loginLocal(username: String, password: String) throws -> AuthSession {
        let normalizedUsername = try normalizeRequired(
            username,
            field: L10n.choose(simplifiedChinese: "用户名", english: "Username")
        )
        let normalizedPassword = try normalizeRequired(
            password,
            field: L10n.choose(simplifiedChinese: "密码", english: "Password")
        )
        guard let account = accounts.first(where: {
            ($0.username ?? "").caseInsensitiveCompare(normalizedUsername) == .orderedSame && $0.provider == .local
        }) else {
            throw AuthControllerError.accountNotFound
        }
        guard
            let saltHex = account.passwordSaltHex,
            let passwordHashHex = account.passwordHashHex
        else {
            throw AuthControllerError.invalidCredentials
        }
        let candidate = Self.hashPassword(password: normalizedPassword, saltHex: saltHex)
        guard candidate == passwordHashHex else {
            throw AuthControllerError.invalidCredentials
        }
        let session = makeSession(from: account)
        currentSession = session
        try persistSession(session)
        lastError = nil
        return session
    }

    func loginOAuth(
        provider: AuthProvider,
        subject: String,
        email: String?,
        displayName: String?
    ) throws -> AuthSession {
        guard provider != .local else {
            throw AuthControllerError.oauthProfileMissing
        }
        let normalizedSubject = try normalizeRequired(subject, field: "subject")
        let normalizedEmail = normalizeOptional(email)
        let resolvedDisplayName = normalizeOptional(displayName) ?? normalizedEmail ?? "\(provider.displayName) User"

        if let existingIndex = accounts.firstIndex(where: {
            $0.provider == provider && $0.providerSubject == normalizedSubject
        }) {
            var updated = accounts[existingIndex]
            updated.email = normalizedEmail ?? updated.email
            updated.displayName = resolvedDisplayName
            accounts[existingIndex] = updated
            try persistAccounts()
            let session = makeSession(from: updated)
            currentSession = session
            try persistSession(session)
            lastError = nil
            return session
        }

        let account = LocalAuthAccount(
            id: UUID().uuidString.lowercased(),
            provider: provider,
            username: nil,
            email: normalizedEmail,
            providerSubject: normalizedSubject,
            displayName: resolvedDisplayName,
            passwordSaltHex: nil,
            passwordHashHex: nil,
            createdAt: Date()
        )
        accounts.append(account)
        try persistAccounts()
        let session = makeSession(from: account)
        currentSession = session
        try persistSession(session)
        lastError = nil
        return session
    }

    func logout() {
        currentSession = nil
        try? FileManager.default.removeItem(at: sessionURL)
        lastError = nil
    }

    func clearAllLocalAuthData() {
        accounts = []
        currentSession = nil
        try? FileManager.default.removeItem(at: accountsURL)
        try? FileManager.default.removeItem(at: sessionURL)
        lastError = nil
    }

    private func makeSession(from account: LocalAuthAccount) -> AuthSession {
        AuthSession(
            accountID: account.id,
            displayName: account.displayName,
            provider: account.provider,
            username: account.username,
            email: account.email,
            signedInAt: Date()
        )
    }

    private func persistAccounts() throws {
        let data = try encoder.encode(accounts)
        try data.write(to: accountsURL, options: .atomic)
    }

    private func persistSession(_ session: AuthSession) throws {
        let data = try encoder.encode(session)
        try data.write(to: sessionURL, options: .atomic)
    }

    private func loadFromDisk() {
        if let data = try? Data(contentsOf: accountsURL),
           let decoded = try? decoder.decode([LocalAuthAccount].self, from: data) {
            accounts = decoded
        } else {
            accounts = []
        }

        if let data = try? Data(contentsOf: sessionURL),
           let decoded = try? decoder.decode(AuthSession.self, from: data),
           accounts.contains(where: { $0.id == decoded.accountID }) {
            currentSession = decoded
        } else {
            currentSession = nil
        }
    }

    private func normalizeRequired(_ value: String, field: String) throws -> String {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            throw AuthControllerError.invalidInput(
                L10n.choose(
                    simplifiedChinese: "\(field)不能为空",
                    english: "\(field) cannot be empty"
                )
            )
        }
        return normalized
    }

    private func normalizeOptional(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }

    private static func resolveStorageRoot() -> URL {
        do {
            let appSupport = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let root = appSupport.appendingPathComponent("fricu/auth", isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            return root
        } catch {
            let fallback = FileManager.default.temporaryDirectory.appendingPathComponent("fricu-auth", isDirectory: true)
            try? FileManager.default.createDirectory(at: fallback, withIntermediateDirectories: true)
            return fallback
        }
    }

    private static func randomHex(bytes count: Int) -> String {
        var buffer = [UInt8](repeating: 0, count: count)
        let status = SecRandomCopyBytes(kSecRandomDefault, buffer.count, &buffer)
        if status != errSecSuccess {
            for index in buffer.indices {
                buffer[index] = UInt8.random(in: 0...255)
            }
        }
        return Data(buffer).map { String(format: "%02x", $0) }.joined()
    }

    private static func hashPassword(password: String, saltHex: String) -> String {
        let payload = Data("\(saltHex):\(password)".utf8)
        let digest = SHA256.hash(data: payload)
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }
}
