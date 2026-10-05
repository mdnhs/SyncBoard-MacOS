//
//  GoogleDriveAuthManager.swift
//  SyncBoard
//

import AppKit
import AuthenticationServices
import CryptoKit
import Observation
import Security

enum GoogleDriveAuthError: LocalizedError {
    case missingClientID
    case userCancelled
    case invalidCallback
    case requestFailed(String)
    case noRefreshToken

    var errorDescription: String? {
        switch self {
        case .missingClientID:
            return "Set GoogleDriveConfig.clientID to your OAuth Client ID before connecting."
        case .userCancelled:
            return "Sign-in was cancelled."
        case .invalidCallback:
            return "Google didn't return an authorization code."
        case .requestFailed(let message):
            return "Google sign-in failed: \(message)"
        case .noRefreshToken:
            return "Google Drive isn't connected. Please connect again."
        }
    }
}

/// Handles the Google OAuth 2.0 + PKCE installed-app flow (sign-in via the
/// system browser, token exchange, refresh, sign-out) and the Keychain
/// storage of the resulting refresh token. Knows nothing about Drive's
/// file API — that's `GoogleDriveSyncService`'s job.
@MainActor
@Observable
final class GoogleDriveAuthManager {
    static let shared = GoogleDriveAuthManager()

    private(set) var accountEmail: String?
    var isConnected: Bool {
        accountEmail != nil && hasRefreshToken
    }

    /// Mirrors the Keychain entry, which only this class writes, so hot paths
    /// like per-keystroke `scheduleSync()` don't hit the Keychain each time.
    private var hasRefreshToken: Bool
    private var accessToken: String?
    private var accessTokenExpiry: Date?
    private var refreshTask: Task<TokenResponse, Error>?
    private var webAuthSession: ASWebAuthenticationSession?
    private let presentationProvider = PresentationAnchorProvider()

    private enum Keys {
        static let refreshToken = "refreshToken"
        static let emailStorageKey = "com.nazmulhsourab.SyncBoard.accountEmail"
    }

    private init() {
        let storedEmail = UserDefaults.standard.string(forKey: Keys.emailStorageKey)
        hasRefreshToken = KeychainStore.string(forKey: Keys.refreshToken) != nil
        if let storedEmail, hasRefreshToken {
            self.accountEmail = storedEmail
        } else {
            // Clean up any stale state
            self.accountEmail = nil
            UserDefaults.standard.removeObject(forKey: Keys.emailStorageKey)
        }
    }

    func connect() async throws {
        guard GoogleDriveConfig.isConfigured else {
            throw GoogleDriveAuthError.missingClientID
        }

        let verifier = Self.makeCodeVerifier()
        let challenge = Self.codeChallenge(for: verifier)
        let authURL = Self.makeAuthorizationURL(codeChallenge: challenge)

        let code = try await startWebAuthSession(url: authURL)
        let tokens = try await exchangeCodeForTokens(code: code, verifier: verifier)
        guard let refreshToken = tokens.refreshToken else {
            throw GoogleDriveAuthError.requestFailed(
                "Google didn't return a refresh token. Remove SyncBoard's access at https://myaccount.google.com/permissions and try connecting again."
            )
        }
        KeychainStore.set(refreshToken, forKey: Keys.refreshToken)
        hasRefreshToken = KeychainStore.string(forKey: Keys.refreshToken) != nil
        accessToken = tokens.accessToken
        accessTokenExpiry = Date().addingTimeInterval(tokens.expiresIn)

        let email = try await fetchAccountEmail(accessToken: tokens.accessToken)
        UserDefaults.standard.set(email, forKey: Keys.emailStorageKey)
        accountEmail = email
    }

    func disconnect() {
        KeychainStore.removeValue(forKey: Keys.refreshToken)
        hasRefreshToken = false
        UserDefaults.standard.removeObject(forKey: Keys.emailStorageKey)
        accessToken = nil
        accessTokenExpiry = nil
        accountEmail = nil
    }

    /// Returns a valid access token, transparently refreshing it from the
    /// stored refresh token if the cached one is missing or close to expiry.
    /// Concurrent callers share a single in-flight refresh.
    func validAccessToken() async throws -> String {
        if let accessToken, let accessTokenExpiry, accessTokenExpiry > Date().addingTimeInterval(60) {
            return accessToken
        }
        if let refreshTask {
            return try await refreshTask.value.accessToken
        }
        guard let refreshToken = KeychainStore.string(forKey: Keys.refreshToken) else {
            // Clean up desynced account email if token was wiped
            disconnect()
            throw GoogleDriveAuthError.noRefreshToken
        }
        let task = Task { try await refreshAccessToken(refreshToken: refreshToken) }
        refreshTask = task
        defer { refreshTask = nil }
        let tokens = try await task.value
        accessToken = tokens.accessToken
        accessTokenExpiry = Date().addingTimeInterval(tokens.expiresIn)
        return tokens.accessToken
    }

    // MARK: - PKCE

    private static func makeCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 64)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncodedString()
    }

    private static func codeChallenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).base64URLEncodedString()
    }

    private static func makeAuthorizationURL(codeChallenge: String) -> URL {
        var components = URLComponents(url: GoogleDriveConfig.authorizationEndpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: GoogleDriveConfig.clientID),
            URLQueryItem(name: "redirect_uri", value: GoogleDriveConfig.redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: GoogleDriveConfig.scope),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent")
        ]
        return components.url!
    }

    // MARK: - Web auth session

    private func startWebAuthSession(url: URL) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: GoogleDriveConfig.redirectURLScheme
            ) { callbackURL, error in
                if let error {
                    let nsError = error as NSError
                    if nsError.domain == ASWebAuthenticationSessionErrorDomain,
                       nsError.code == ASWebAuthenticationSessionError.Code.canceledLogin.rawValue {
                        continuation.resume(throwing: GoogleDriveAuthError.userCancelled)
                    } else {
                        continuation.resume(throwing: error)
                    }
                    return
                }
                guard let callbackURL,
                      let code = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?
                        .queryItems?.first(where: { $0.name == "code" })?.value else {
                    continuation.resume(throwing: GoogleDriveAuthError.invalidCallback)
                    return
                }
                continuation.resume(returning: code)
            }
            session.presentationContextProvider = presentationProvider
            webAuthSession = session
            session.start()
        }
    }

    // MARK: - Token exchange

    private struct TokenResponse: Decodable {
        let accessToken: String
        let expiresIn: TimeInterval
        let refreshToken: String?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case expiresIn = "expires_in"
            case refreshToken = "refresh_token"
        }
    }

    private func exchangeCodeForTokens(code: String, verifier: String) async throws -> TokenResponse {
        var params = [
            "client_id": GoogleDriveConfig.clientID,
            "code": code,
            "code_verifier": verifier,
            "grant_type": "authorization_code",
            "redirect_uri": GoogleDriveConfig.redirectURI
        ]
        if !GoogleDriveConfig.clientSecret.isEmpty {
            params["client_secret"] = GoogleDriveConfig.clientSecret
        }
        return try await postForm(to: GoogleDriveConfig.tokenEndpoint, params: params)
    }

    private func refreshAccessToken(refreshToken: String) async throws -> TokenResponse {
        var params = [
            "client_id": GoogleDriveConfig.clientID,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token"
        ]
        if !GoogleDriveConfig.clientSecret.isEmpty {
            params["client_secret"] = GoogleDriveConfig.clientSecret
        }
        return try await postForm(to: GoogleDriveConfig.tokenEndpoint, params: params)
    }

    private func postForm<T: Decodable>(to url: URL, params: [String: String]) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = params
            .map { key, value in "\(key)=\(value.addingPercentEncoding(withAllowedCharacters: .urlFormValueAllowed) ?? value)" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw GoogleDriveAuthError.requestFailed(message)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func fetchAccountEmail(accessToken: String) async throws -> String {
        var request = URLRequest(url: GoogleDriveConfig.userInfoEndpoint)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await URLSession.shared.data(for: request)
        struct UserInfo: Decodable { let email: String }
        return try JSONDecoder().decode(UserInfo.self, from: data).email
    }
}

/// Separated from `GoogleDriveAuthManager` because `ASWebAuthenticationPresentationContextProviding`
/// requires `NSObject` conformance, which doesn't mix with the `@Observable` macro.
private final class PresentationAnchorProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApp.keyWindow ?? NSApp.windows.first ?? ASPresentationAnchor()
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

private extension CharacterSet {
    /// `.urlQueryAllowed` alone doesn't escape `+`, `&`, or `=`, which breaks
    /// `application/x-www-form-urlencoded` bodies when a token value contains them.
    static var urlFormValueAllowed: CharacterSet {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "+&=")
        return allowed
    }
}
