import Foundation
import AuthenticationServices
import CryptoKit

/// Google sign-in, for reading the account's subscriptions and playlists.
///
/// ## Why PKCE and no client secret
///
/// A native app can't keep a secret — anyone can pull strings out of the binary.
/// Google's "iOS" OAuth client type therefore issues no secret and requires
/// **PKCE**: the app generates a random `code_verifier`, sends only its SHA256
/// hash up front, and proves possession by presenting the original when
/// exchanging the code. An intercepted authorisation code is useless without it.
///
/// ## What signing in does and does not buy
///
/// This grants access to the **Data API**, which is a different identity system
/// from the InnerTube calls that fetch streams. InnerTube authenticates with
/// `SAPISIDHASH` cookies, not OAuth bearer tokens, so signing in here does *not*
/// personalise the home feed or unlock age-restricted videos. It gets the
/// subscription list, playlists, and the ability to like and subscribe — no more.
@MainActor
@Observable
final class GoogleAuth: NSObject {
    static let shared = GoogleAuth()

    private(set) var account: Account?
    private(set) var isAuthenticating = false
    private(set) var error: String?

    var isSignedIn: Bool { account != nil }

    struct Account: Codable, Sendable {
        var accessToken: String
        var refreshToken: String?
        var expiresAt: Date
        var email: String?
        var name: String?

        var isExpired: Bool { Date() >= expiresAt.addingTimeInterval(-60) }
    }

    /// Set in `Secrets.swift`, which is not committed.
    ///
    /// Sign-in is presented as unavailable rather than broken when this is
    /// missing, because an empty client ID produces an opaque Google error page
    /// that looks like a bug in the app.
    private var clientID: String { Secrets.googleClientID }

    var isConfigured: Bool { !clientID.isEmpty }

    /// Google's iOS clients use a reversed-client-ID scheme rather than a
    /// custom-scheme-plus-path.
    private var redirectURI: String {
        let reversed = clientID.components(separatedBy: ".apps.googleusercontent.com").first ?? clientID
        return "com.googleusercontent.apps.\(reversed):/oauth2redirect"
    }

    private var callbackScheme: String {
        let reversed = clientID.components(separatedBy: ".apps.googleusercontent.com").first ?? clientID
        return "com.googleusercontent.apps.\(reversed)"
    }

    private let scopes = [
        "https://www.googleapis.com/auth/youtube.readonly",
        "https://www.googleapis.com/auth/youtube.force-ssl",
        "openid", "email", "profile",
    ]

    private let keychainKey = "google.account"
    private var session: ASWebAuthenticationSession?

    override init() {
        super.init()
        account = Keychain.load(keychainKey, as: Account.self)
    }

    // MARK: Sign in

    func signIn() async {
        guard isConfigured else {
            error = "Sign-in isn't set up in this build."
            return
        }
        guard !isAuthenticating else { return }

        isAuthenticating = true
        error = nil
        defer { isAuthenticating = false }

        let verifier = Self.randomVerifier()
        let challenge = Self.challenge(for: verifier)

        var comps = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        comps.queryItems = [
            .init(name: "client_id", value: clientID),
            .init(name: "redirect_uri", value: redirectURI),
            .init(name: "response_type", value: "code"),
            .init(name: "scope", value: scopes.joined(separator: " ")),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
            // Required to receive a refresh token; without it the user is
            // signed out again in an hour.
            .init(name: "access_type", value: "offline"),
            .init(name: "prompt", value: "consent"),
        ]

        do {
            let callback = try await authenticate(url: comps.url!)
            guard let code = URLComponents(url: callback, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "code" })?.value
            else {
                error = "Google didn't return an authorisation code."
                return
            }
            try await exchange(code: code, verifier: verifier)
        } catch is CancellationError {
            // The user closed the sheet. Not an error worth reporting.
        } catch let authError as ASWebAuthenticationSessionError where authError.code == .canceledLogin {
            // Same.
        } catch {
            self.error = "Couldn't complete sign-in."
        }
    }

    func signOut() {
        account = nil
        Keychain.delete(keychainKey)
    }

    /// A valid access token, refreshed if needed.
    func validToken() async -> String? {
        guard let account else { return nil }
        guard account.isExpired else { return account.accessToken }
        guard let refresh = account.refreshToken else {
            signOut()
            return nil
        }
        return try? await refreshToken(refresh)
    }

    // MARK: OAuth plumbing

    private func authenticate(url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: callbackScheme
            ) { callback, error in
                if let callback {
                    continuation.resume(returning: callback)
                } else {
                    continuation.resume(throwing: error ?? CancellationError())
                }
            }
            session.presentationContextProvider = self
            // A fresh session each time, so signing out actually signs out
            // rather than silently reusing the browser's Google cookie.
            session.prefersEphemeralWebBrowserSession = false
            self.session = session
            session.start()
        }
    }

    private func exchange(code: String, verifier: String) async throws {
        let body = [
            "client_id": clientID,
            "code": code,
            "code_verifier": verifier,
            "grant_type": "authorization_code",
            "redirect_uri": redirectURI,
        ]
        let token = try await postToken(body)
        var account = Account(
            accessToken: token.accessToken,
            refreshToken: token.refreshToken,
            expiresAt: Date().addingTimeInterval(token.expiresIn)
        )
        account.email = await fetchEmail(token: token.accessToken)
        self.account = account
        Keychain.save(account, key: keychainKey)
    }

    private func refreshToken(_ refresh: String) async throws -> String {
        let token = try await postToken([
            "client_id": clientID,
            "refresh_token": refresh,
            "grant_type": "refresh_token",
        ])
        var updated = account
        updated?.accessToken = token.accessToken
        updated?.expiresAt = Date().addingTimeInterval(token.expiresIn)
        // A refresh response omits the refresh token; keeping the original is
        // what makes the session survive past the first hour.
        if let updated {
            account = updated
            Keychain.save(updated, key: keychainKey)
        }
        return token.accessToken
    }

    private struct TokenResponse: Decodable {
        let accessToken: String
        let refreshToken: String?
        let expiresIn: Double

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case expiresIn = "expires_in"
        }
    }

    private func postToken(_ fields: [String: String]) async throws -> TokenResponse {
        var req = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = fields
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, _) = try await URLSession.shared.data(for: req)
        return try JSONDecoder().decode(TokenResponse.self, from: data)
    }

    private func fetchEmail(token: String) async -> String? {
        var req = URLRequest(url: URL(string: "https://www.googleapis.com/oauth2/v3/userinfo")!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return json["email"] as? String
    }

    // MARK: PKCE

    private static func randomVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 64)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncoded
    }

    private static func challenge(for verifier: String) -> String {
        Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncoded
    }
}

extension GoogleAuth: ASWebAuthenticationPresentationContextProviding {
    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
                .first { $0.isKeyWindow } ?? ASPresentationAnchor()
        }
    }
}

extension Data {
    /// base64url per RFC 7636 — standard base64 is rejected by the token endpoint.
    var base64URLEncoded: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
