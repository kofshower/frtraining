import SwiftUI
import Foundation
import CryptoKit

struct AuthGateView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var auth: AuthController
    @State private var activeAccountID: String?

    var body: some View {
        Group {
            if let session = auth.currentSession {
                RootView()
                    .task(id: session.accountID) {
                        guard activeAccountID != session.accountID else { return }
                        store.activateAuthenticatedAccount(
                            accountID: session.accountID,
                            displayName: session.displayName
                        )
                        store.bootstrap()
                        activeAccountID = session.accountID
                    }
            } else {
                LoginView { session in
                    store.activateAuthenticatedAccount(
                        accountID: session.accountID,
                        displayName: session.displayName
                    )
                    store.bootstrap()
                    activeAccountID = session.accountID
                }
            }
        }
    }
}

private struct LoginView: View {
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var auth: AuthController
    @EnvironmentObject private var store: AppStore

    @State private var mode: LoginMode = .login
    @State private var username = ""
    @State private var password = ""
    @State private var displayName = ""
    @State private var statusText: String?
    @State private var isWorking = false
    @AppStorage("fricu.auth.google.client_id.v1") private var googleClientID = ""
    @AppStorage("fricu.auth.facebook.app_id.v1") private var facebookAppID = ""
    @AppStorage("fricu.auth.facebook.app_secret.v1") private var facebookAppSecret = ""

    let onAuthenticated: (AuthSession) -> Void

    private enum LoginMode: String, CaseIterable, Identifiable {
        case login
        case register

        var id: String { rawValue }
        var title: String {
            switch self {
            case .login:
                return L10n.choose(simplifiedChinese: "登录", english: "Login")
            case .register:
                return L10n.choose(simplifiedChinese: "注册", english: "Register")
            }
        }
    }

    var body: some View {
        VStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Fricu")
                    .font(.largeTitle.weight(.heavy))
                Text(
                    L10n.choose(
                        simplifiedChinese: "登录后进入训练与数据页面；单账号仅对应一个运动员与一个骑行会话。",
                        english: "Sign in to access training/data pages; each account uses a single athlete and one trainer session."
                    )
                )
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Picker("", selection: $mode) {
                ForEach(LoginMode.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.segmented)

            VStack(alignment: .leading, spacing: 10) {
                TextField(L10n.choose(simplifiedChinese: "用户名", english: "Username"), text: $username)
                    .textFieldStyle(.roundedBorder)

                SecureField(L10n.choose(simplifiedChinese: "密码（至少6位）", english: "Password (min 6 chars)"), text: $password)
                    .textFieldStyle(.roundedBorder)

                if mode == .register {
                    TextField(L10n.choose(simplifiedChinese: "显示名称（可选）", english: "Display name (optional)"), text: $displayName)
                        .textFieldStyle(.roundedBorder)
                }
            }

            HStack(spacing: 10) {
                Button(mode == .login
                       ? L10n.choose(simplifiedChinese: "登录", english: "Login")
                       : L10n.choose(simplifiedChinese: "注册并登录", english: "Register and Sign In")) {
                    Task { await handlePrimaryAction() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isWorking)

                Button(L10n.choose(simplifiedChinese: "清空", english: "Clear")) {
                    username = ""
                    password = ""
                    displayName = ""
                    statusText = nil
                }
                .buttonStyle(.bordered)
                .disabled(isWorking)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 10) {
                Text(L10n.choose(simplifiedChinese: "第三方登录", english: "OAuth Sign In"))
                    .font(.headline)
                HStack(spacing: 10) {
                    Button("Google") {
                        Task { await handleGoogleLogin() }
                    }
                    .buttonStyle(.bordered)
                    .disabled(isWorking || googleClientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Button("Facebook") {
                        Task { await handleFacebookLogin() }
                    }
                    .buttonStyle(.bordered)
                    .disabled(
                        isWorking ||
                        facebookAppID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                        facebookAppSecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
                }

                DisclosureGroup(L10n.choose(simplifiedChinese: "OAuth 配置", english: "OAuth Config")) {
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Google Client ID", text: $googleClientID)
                            .textFieldStyle(.roundedBorder)
                        TextField("Facebook App ID", text: $facebookAppID)
                            .textFieldStyle(.roundedBorder)
                        SecureField("Facebook App Secret", text: $facebookAppSecret)
                            .textFieldStyle(.roundedBorder)
                        Text(
                            L10n.choose(
                                simplifiedChinese: "回调地址：Google http://127.0.0.1:53683/google-callback；Facebook http://127.0.0.1:53684/facebook-callback",
                                english: "Redirect URIs: Google http://127.0.0.1:53683/google-callback; Facebook http://127.0.0.1:53684/facebook-callback"
                            )
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.top, 6)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let statusText {
                Text(statusText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let authError = auth.lastError {
                Text(authError)
                    .font(.subheadline)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let storeError = store.lastError {
                Text(storeError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer(minLength: 0)
        }
        .padding(28)
        .frame(minWidth: 560, maxWidth: 640, minHeight: 560)
    }

    private func handlePrimaryAction() async {
        isWorking = true
        defer { isWorking = false }
        do {
            let session: AuthSession
            switch mode {
            case .login:
                session = try auth.loginLocal(username: username, password: password)
            case .register:
                session = try auth.registerLocal(username: username, password: password, displayName: displayName)
            }
            statusText = L10n.choose(
                simplifiedChinese: "登录成功：\(session.displayName)",
                english: "Signed in as \(session.displayName)"
            )
            onAuthenticated(session)
        } catch {
            statusText = error.localizedDescription
        }
    }

    private func handleGoogleLogin() async {
        isWorking = true
        defer { isWorking = false }
        do {
            let session = try await GoogleOAuthFlow.signIn(
                clientID: googleClientID,
                openURL: openURL
            ) { profile in
                try auth.loginOAuth(
                    provider: .google,
                    subject: profile.subject,
                    email: profile.email,
                    displayName: profile.displayName
                )
            }
            statusText = L10n.choose(
                simplifiedChinese: "Google 登录成功：\(session.displayName)",
                english: "Google sign-in success: \(session.displayName)"
            )
            onAuthenticated(session)
        } catch {
            statusText = error.localizedDescription
        }
    }

    private func handleFacebookLogin() async {
        isWorking = true
        defer { isWorking = false }
        do {
            let session = try await FacebookOAuthFlow.signIn(
                appID: facebookAppID,
                appSecret: facebookAppSecret,
                openURL: openURL
            ) { profile in
                try auth.loginOAuth(
                    provider: .facebook,
                    subject: profile.subject,
                    email: profile.email,
                    displayName: profile.displayName
                )
            }
            statusText = L10n.choose(
                simplifiedChinese: "Facebook 登录成功：\(session.displayName)",
                english: "Facebook sign-in success: \(session.displayName)"
            )
            onAuthenticated(session)
        } catch {
            statusText = error.localizedDescription
        }
    }
}

private struct OAuthUserProfile {
    var subject: String
    var email: String?
    var displayName: String?
}

private enum OAuthFlowError: LocalizedError {
    case invalidConfig(String)
    case callbackStateMismatch
    case callbackMissingCode
    case tokenExchangeFailed(String)
    case userInfoFailed(String)
    case invalidIDToken

    var errorDescription: String? {
        switch self {
        case let .invalidConfig(msg):
            return msg
        case .callbackStateMismatch:
            return L10n.choose(simplifiedChinese: "OAuth 状态校验失败", english: "OAuth state mismatch")
        case .callbackMissingCode:
            return L10n.choose(simplifiedChinese: "OAuth 回调缺少 code", english: "OAuth callback missing code")
        case let .tokenExchangeFailed(msg):
            return L10n.choose(simplifiedChinese: "OAuth token 交换失败：\(msg)", english: "OAuth token exchange failed: \(msg)")
        case let .userInfoFailed(msg):
            return L10n.choose(simplifiedChinese: "OAuth 用户信息获取失败：\(msg)", english: "OAuth user info failed: \(msg)")
        case .invalidIDToken:
            return L10n.choose(simplifiedChinese: "Google id_token 无效", english: "Invalid Google id_token")
        }
    }
}

private enum GoogleOAuthFlow {
    static func signIn(
        clientID: String,
        openURL: OpenURLAction,
        complete: (OAuthUserProfile) throws -> AuthSession
    ) async throws -> AuthSession {
        let normalizedClientID = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedClientID.isEmpty else {
            throw OAuthFlowError.invalidConfig(
                L10n.choose(simplifiedChinese: "请先配置 Google Client ID", english: "Google Client ID is required")
            )
        }

        let redirectURI = "http://127.0.0.1:53683/google-callback"
        let callbackServer = try StravaOAuthLocalCallbackServer(redirectURI: redirectURI)
        let state = UUID().uuidString.lowercased()
        let codeVerifier = PKCE.makeCodeVerifier()
        let codeChallenge = PKCE.makeCodeChallenge(verifier: codeVerifier)

        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            .init(name: "client_id", value: normalizedClientID),
            .init(name: "redirect_uri", value: redirectURI),
            .init(name: "response_type", value: "code"),
            .init(name: "scope", value: "openid email profile"),
            .init(name: "state", value: state),
            .init(name: "code_challenge", value: codeChallenge),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "access_type", value: "offline"),
            .init(name: "prompt", value: "consent")
        ]
        guard let authURL = components.url else {
            throw OAuthFlowError.invalidConfig("invalid google auth url")
        }
        await MainActor.run {
            openURL(authURL)
        }

        let callback = try await callbackServer.awaitCallback(timeoutSec: 240)
        if callback.state != state {
            throw OAuthFlowError.callbackStateMismatch
        }
        guard let code = callback.code, !code.isEmpty else {
            throw OAuthFlowError.callbackMissingCode
        }

        var req = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = formEncoded([
            "client_id": normalizedClientID,
            "redirect_uri": redirectURI,
            "grant_type": "authorization_code",
            "code": code,
            "code_verifier": codeVerifier
        ])

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let text = String(data: data, encoding: .utf8) ?? "unknown"
            throw OAuthFlowError.tokenExchangeFailed(text)
        }
        let obj = try jsonObject(data)
        guard let idToken = obj["id_token"] as? String else {
            throw OAuthFlowError.invalidIDToken
        }
        let payload = try decodeJWTPayload(idToken)
        guard let sub = payload["sub"] as? String, !sub.isEmpty else {
            throw OAuthFlowError.invalidIDToken
        }
        let email = payload["email"] as? String
        let name = payload["name"] as? String
        return try complete(OAuthUserProfile(subject: sub, email: email, displayName: name))
    }
}

private enum FacebookOAuthFlow {
    static func signIn(
        appID: String,
        appSecret: String,
        openURL: OpenURLAction,
        complete: (OAuthUserProfile) throws -> AuthSession
    ) async throws -> AuthSession {
        let normalizedAppID = appID.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedSecret = appSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedAppID.isEmpty, !normalizedSecret.isEmpty else {
            throw OAuthFlowError.invalidConfig(
                L10n.choose(
                    simplifiedChinese: "请先配置 Facebook App ID 与 App Secret",
                    english: "Facebook App ID/App Secret are required"
                )
            )
        }

        let redirectURI = "http://127.0.0.1:53684/facebook-callback"
        let callbackServer = try StravaOAuthLocalCallbackServer(redirectURI: redirectURI)
        let state = UUID().uuidString.lowercased()
        var authComponents = URLComponents(string: "https://www.facebook.com/v20.0/dialog/oauth")!
        authComponents.queryItems = [
            .init(name: "client_id", value: normalizedAppID),
            .init(name: "redirect_uri", value: redirectURI),
            .init(name: "state", value: state),
            .init(name: "scope", value: "public_profile,email"),
            .init(name: "response_type", value: "code")
        ]
        guard let authURL = authComponents.url else {
            throw OAuthFlowError.invalidConfig("invalid facebook auth url")
        }
        await MainActor.run {
            openURL(authURL)
        }

        let callback = try await callbackServer.awaitCallback(timeoutSec: 240)
        if callback.state != state {
            throw OAuthFlowError.callbackStateMismatch
        }
        guard let code = callback.code, !code.isEmpty else {
            throw OAuthFlowError.callbackMissingCode
        }

        var tokenComponents = URLComponents(string: "https://graph.facebook.com/v20.0/oauth/access_token")!
        tokenComponents.queryItems = [
            .init(name: "client_id", value: normalizedAppID),
            .init(name: "redirect_uri", value: redirectURI),
            .init(name: "client_secret", value: normalizedSecret),
            .init(name: "code", value: code)
        ]
        guard let tokenURL = tokenComponents.url else {
            throw OAuthFlowError.invalidConfig("invalid facebook token url")
        }
        let (tokenData, tokenResp) = try await URLSession.shared.data(from: tokenURL)
        guard let tokenHTTP = tokenResp as? HTTPURLResponse, (200..<300).contains(tokenHTTP.statusCode) else {
            let text = String(data: tokenData, encoding: .utf8) ?? "unknown"
            throw OAuthFlowError.tokenExchangeFailed(text)
        }
        let tokenObj = try jsonObject(tokenData)
        guard let accessToken = tokenObj["access_token"] as? String else {
            throw OAuthFlowError.tokenExchangeFailed("missing access_token")
        }

        var meComponents = URLComponents(string: "https://graph.facebook.com/me")!
        meComponents.queryItems = [
            .init(name: "fields", value: "id,name,email"),
            .init(name: "access_token", value: accessToken)
        ]
        guard let meURL = meComponents.url else {
            throw OAuthFlowError.userInfoFailed("invalid me url")
        }
        let (meData, meResp) = try await URLSession.shared.data(from: meURL)
        guard let meHTTP = meResp as? HTTPURLResponse, (200..<300).contains(meHTTP.statusCode) else {
            let text = String(data: meData, encoding: .utf8) ?? "unknown"
            throw OAuthFlowError.userInfoFailed(text)
        }
        let meObj = try jsonObject(meData)
        guard let id = meObj["id"] as? String, !id.isEmpty else {
            throw OAuthFlowError.userInfoFailed("missing id")
        }
        let email = meObj["email"] as? String
        let name = meObj["name"] as? String
        return try complete(OAuthUserProfile(subject: id, email: email, displayName: name))
    }
}

private enum PKCE {
    static func makeCodeVerifier() -> String {
        let base = UUID().uuidString.replacingOccurrences(of: "-", with: "") + UUID().uuidString.replacingOccurrences(of: "-", with: "")
        return String(base.prefix(64))
    }

    static func makeCodeChallenge(verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).base64URLEncodedString()
    }
}

private func formEncoded(_ dict: [String: String]) -> Data {
    let body = dict.map { key, value in
        "\(urlEncode(key))=\(urlEncode(value))"
    }
    .joined(separator: "&")
    return Data(body.utf8)
}

private func urlEncode(_ value: String) -> String {
    value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)?
        .replacingOccurrences(of: "+", with: "%2B")
        .replacingOccurrences(of: "&", with: "%26")
        .replacingOccurrences(of: "=", with: "%3D") ?? value
}

private func jsonObject(_ data: Data) throws -> [String: Any] {
    let any = try JSONSerialization.jsonObject(with: data)
    guard let object = any as? [String: Any] else {
        throw OAuthFlowError.userInfoFailed("invalid json object")
    }
    return object
}

private func decodeJWTPayload(_ jwt: String) throws -> [String: Any] {
    let parts = jwt.split(separator: ".")
    guard parts.count >= 2 else {
        throw OAuthFlowError.invalidIDToken
    }
    let payload = String(parts[1])
    guard let payloadData = Data(base64URLEncoded: payload) else {
        throw OAuthFlowError.invalidIDToken
    }
    return try jsonObject(payloadData)
}

private extension Data {
    init?(base64URLEncoded value: String) {
        var base64 = value.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padding = 4 - (base64.count % 4)
        if padding < 4 {
            base64 += String(repeating: "=", count: padding)
        }
        self.init(base64Encoded: base64)
    }

    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
