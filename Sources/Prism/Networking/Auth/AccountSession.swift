import Foundation
import SwiftUI
import Observation

/// Signs InnerTube requests as the user's YouTube account.
///
/// ## Why this is not cookies
///
/// The obvious approach — sign in through a web view, keep the Google cookies,
/// send a `SAPISIDHASH` header — does not work with the clients this app uses.
/// Verified directly: `VISIONOS` returns identical anonymous results whether the
/// `SAPISIDHASH` header is correct, deliberately wrong, or absent entirely. It
/// never validates it. The mobile and headset clients simply don't support
/// cookie auth; only the WEB-family clients do, and those now need a BotGuard
/// PO token, JavaScript signature solving, and give up the HLS manifest.
///
/// What the playback path does accept is `Authorization: Bearer`, from a
/// **first-party YouTube OAuth client**. That is enforced per client on Google's
/// authorization server rather than by scope: the TV client is allowed to
/// request the legacy `http://gdata.youtube.com` scope, and asking it for
/// `youtube.readonly` instead returns `restricted_client`. A Cloud project you
/// register yourself gets the mirror image — the ordinary YouTube scopes, never
/// the legacy one.
///
/// Both first-party clients are registered as limited-input devices and reject
/// every redirect URI, so the **device-code flow** isn't a preference here, it
/// is the only grant type they support.
///
/// That buys a lot:
/// - Keeps `VISIONOS` and its HLS manifest, so playback is unchanged.
/// - No web view, no cookie jar, no PO token, no JavaScript.
/// - The user never types a password into this app — they authorise it on
///   google.com, and can revoke it there like any other device.
@MainActor
@Observable
final class AccountSession {
    static let shared = AccountSession()

    private(set) var isSignedIn = false
    private(set) var pendingCode: DeviceCode?
    private(set) var isPolling = false
    private(set) var error: String?

    /// The credentials YouTube's own TV client uses. These are public — they
    /// ship inside every smart TV — and the device flow is designed around a
    /// client that cannot keep a secret.
    private enum TV {
        static let clientID = "861556708454-d6dlm3lh05idd8npek18k6be8ba3oc68.apps.googleusercontent.com"
        static let clientSecret = "SboVhoG9s0rNafixCSGGKXAT"

        /// Three scopes, and the middle one is the reason there is only one
        /// sign-in in this app rather than two.
        ///
        /// - `gdata.youtube.com` is the legacy first-party scope InnerTube's
        ///   playback path wants.
        /// - `auth/youtube` is the ordinary Data API read/write scope, covering
        ///   subscriptions, ratings and playlist edits.
        ///
        /// The TV client is allowlisted for both, so a single token authenticates
        /// InnerTube *and* googleapis.com — no separate OAuth client, and nothing
        /// to register in Cloud Console.
        ///
        /// `youtube.force-ssl` is deliberately absent: requesting it alongside
        /// these returns `invalid_scope`, and `auth/youtube` already grants the
        /// same read/write access.
        static let scope = [
            "http://gdata.youtube.com",
            "https://www.googleapis.com/auth/youtube",
            "https://www.googleapis.com/auth/youtube-paid-content",
        ].joined(separator: " ")
        static let codeURL = URL(string: "https://www.youtube.com/o/oauth2/device/code")!
        static let tokenURL = URL(string: "https://www.youtube.com/o/oauth2/token")!
    }

    struct DeviceCode: Sendable, Equatable {
        /// Shown to the user, e.g. `RCP-RBN-PRVT`.
        let userCode: String
        let verificationURL: String
        let deviceCode: String
        let interval: Int
        let expiresAt: Date

        /// The consent page with the code already filled in.
        ///
        /// The device flow was designed for televisions, where a second device
        /// does the typing. Here both are the same phone, so there's no reason
        /// to make anyone read a code off one screen and type it into another —
        /// `google.com/device?user_code=` carries it through to the page, which
        /// populates the field itself. The code is still shown as a fallback in
        /// case the page ever stops honouring the parameter.
        var prefilledURL: URL? {
            var components = URLComponents(string: verificationURL)
            components?.queryItems = [URLQueryItem(name: "user_code", value: userCode)]
            return components?.url
        }
    }

    private struct Token: Codable, Sendable {
        var accessToken: String
        var refreshToken: String
        var expiresAt: Date

        var isExpired: Bool { Date() >= expiresAt.addingTimeInterval(-120) }
    }

    private var token: Token? {
        didSet { isSignedIn = token != nil }
    }

    private let keychainKey = "youtube.tv.token"
    private var pollTask: Task<Void, Never>?

    init() {
        token = Keychain.load(keychainKey, as: Token.self)
        isSignedIn = token != nil
    }

    // MARK: Sign in

    /// Asks Google for a code, then polls until the user approves it.
    func beginSignIn() async {
        error = nil
        pollTask?.cancel()

        guard let code = await requestDeviceCode() else {
            error = "Couldn't start sign-in. Check your connection."
            return
        }
        pendingCode = code
        isPolling = true

        pollTask = Task { [weak self] in
            await self?.poll(code)
        }
    }

    func cancelSignIn() {
        pollTask?.cancel()
        pendingCode = nil
        isPolling = false
    }

    func signOut() {
        pollTask?.cancel()
        token = nil
        pendingCode = nil
        isPolling = false
        Keychain.delete(keychainKey)
    }

    // MARK: Request signing

    /// A valid access token, refreshed if needed.
    ///
    /// Shared by InnerTube and the Data API — the same token authenticates both,
    /// because the sign-in requests scopes for each.
    func accessToken() async -> String? {
        await authHeaders()["Authorization"]?
            .replacingOccurrences(of: "Bearer ", with: "")
    }

    /// The header that authenticates an InnerTube request, refreshed if needed.
    ///
    /// Returns empty when signed out, which is what keeps the app fully working
    /// without an account.
    func authHeaders() async -> [String: String] {
        guard var current = token else { return [:] }

        if current.isExpired {
            guard let refreshed = await refresh(current.refreshToken) else {
                // The grant was revoked from the Google account page. Signing
                // out here means the UI reflects reality rather than looping on
                // a dead token.
                signOut()
                return [:]
            }
            current = refreshed
            token = refreshed
            Keychain.save(refreshed, key: keychainKey)
        }

        return ["Authorization": "Bearer \(current.accessToken)"]
    }

    // MARK: Device flow

    private func requestDeviceCode() async -> DeviceCode? {
        var request = URLRequest(url: TV.codeURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "client_id": TV.clientID,
            "scope": TV.scope,
            "device_id": UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased(),
            "device_model": "ytlr::",
        ])

        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let userCode = json["user_code"] as? String,
              let deviceCode = json["device_code"] as? String
        else { return nil }

        return DeviceCode(
            userCode: userCode,
            verificationURL: json["verification_url"] as? String ?? "https://www.google.com/device",
            deviceCode: deviceCode,
            interval: json["interval"] as? Int ?? 5,
            expiresAt: Date().addingTimeInterval(Double(json["expires_in"] as? Int ?? 1800))
        )
    }

    /// Polls the token endpoint at the interval Google asked for.
    ///
    /// `authorization_pending` is the normal state while the user is still
    /// typing the code, and must not be treated as an error.
    private func poll(_ code: DeviceCode) async {
        var interval = code.interval

        while !Task.isCancelled, Date() < code.expiresAt {
            try? await Task.sleep(for: .seconds(interval))
            guard !Task.isCancelled else { return }

            var request = URLRequest(url: TV.tokenURL)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONSerialization.data(withJSONObject: [
                "client_id": TV.clientID,
                "client_secret": TV.clientSecret,
                "code": code.deviceCode,
                "grant_type": "http://oauth.net/grant_type/device/1.0",
            ])

            guard let (data, _) = try? await URLSession.shared.data(for: request),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }

            if let access = json["access_token"] as? String,
               let refresh = json["refresh_token"] as? String {
                let expires = Double(json["expires_in"] as? Int ?? 3600)
                let new = Token(
                    accessToken: access,
                    refreshToken: refresh,
                    expiresAt: Date().addingTimeInterval(expires)
                )
                token = new
                Keychain.save(new, key: keychainKey)

                pendingCode = nil
                isPolling = false
                Haptics.notify(.success)
                return
            }

            switch json["error"] as? String {
            case "authorization_pending":
                continue                       // still waiting on the user
            case "slow_down":
                interval += 5                  // Google asking us to back off
            case "access_denied":
                error = "Sign-in was declined."
                pendingCode = nil
                isPolling = false
                return
            case "expired_token":
                error = "That code expired. Try again."
                pendingCode = nil
                isPolling = false
                return
            default:
                continue
            }
        }

        if !Task.isCancelled {
            error = "That code expired. Try again."
            pendingCode = nil
            isPolling = false
        }
    }

    private func refresh(_ refreshToken: String) async -> Token? {
        var request = URLRequest(url: TV.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "client_id": TV.clientID,
            "client_secret": TV.clientSecret,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token",
        ])

        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let access = json["access_token"] as? String
        else { return nil }

        return Token(
            accessToken: access,
            // A refresh response omits the refresh token; keeping the original
            // is what makes the session survive past the first hour.
            refreshToken: json["refresh_token"] as? String ?? refreshToken,
            expiresAt: Date().addingTimeInterval(Double(json["expires_in"] as? Int ?? 3600))
        )
    }
}
