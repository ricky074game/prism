import Foundation
import SwiftUI
import WebKit
import CryptoKit
import Observation

/// The user's real YouTube session, established by signing in through a web view.
///
/// ## Why this exists alongside OAuth
///
/// There are two separate identity systems and they are not interchangeable:
///
/// - **OAuth** (`GoogleAuth`) authenticates the *Data API*. It uses bearer
///   tokens and unlocks subscriptions, ratings and playlist writes.
/// - **Cookies** authenticate *InnerTube* — the API that actually returns video
///   streams. InnerTube ignores OAuth bearer tokens entirely; it wants a
///   `SAPISIDHASH` signature derived from the session cookies.
///
/// Only the cookie path can lift the age gate, because the age gate lives on
/// the player endpoint. This is why "sign in with Google" alone was never going
/// to make restricted videos play.
///
/// ## What is stored
///
/// The cookies are a live credential for the user's Google account. They stay in
/// this device's cookie store and the derived hash is recomputed per request —
/// nothing is transmitted anywhere except youtube.com, exactly as a browser
/// would. There is still real risk here, which the sign-in screen states plainly.
@MainActor
@Observable
final class AccountSession {
    static let shared = AccountSession()

    private(set) var isSignedIn = false
    private(set) var accountName: String?

    /// The cookie InnerTube signs requests with.
    private var sapisid: String?
    /// Present when the account is one of several signed into the browser.
    private var authUser = "0"

    private let store = WKWebsiteDataStore.default()

    init() {
        Task { await restore() }
    }

    // MARK: Session

    /// Reads cookies the web view left behind and decides whether we're signed in.
    func restore() async {
        let cookies = await store.httpCookieStore.allCookies()
        adopt(cookies)
    }

    /// Called when the sign-in web view reports success.
    func adopt(_ cookies: [HTTPCookie]) {
        // Mirror into the shared storage so plain URLSession requests carry
        // them; WKWebView keeps its own jar otherwise.
        for cookie in cookies where cookie.domain.contains("youtube.com") || cookie.domain.contains("google.com") {
            HTTPCookieStorage.shared.setCookie(cookie)
        }

        // Either name works; __Secure-3PAPISID is the one that survives
        // third-party cookie restrictions.
        let names = ["SAPISID", "__Secure-3PAPISID", "__Secure-1PAPISID"]
        sapisid = cookies.first { names.contains($0.name) && !$0.value.isEmpty }?.value

        isSignedIn = sapisid != nil
    }

    func signOut() async {
        sapisid = nil
        isSignedIn = false
        accountName = nil

        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        let records = await store.dataRecords(ofTypes: types)
        let google = records.filter { $0.displayName.contains("google") || $0.displayName.contains("youtube") }
        await store.removeData(ofTypes: types, for: google)

        for cookie in HTTPCookieStorage.shared.cookies ?? [] {
            if cookie.domain.contains("youtube.com") || cookie.domain.contains("google.com") {
                HTTPCookieStorage.shared.deleteCookie(cookie)
            }
        }
    }

    // MARK: Request signing

    /// Headers that authenticate an InnerTube request as this account.
    ///
    /// The signature is `SHA1("<unix seconds> <SAPISID> <origin>")`, sent as
    /// `SAPISIDHASH <unix seconds>_<hex>`. It is recomputed per request — the
    /// timestamp is part of the hashed input, so a cached value stops being
    /// valid almost immediately.
    func authHeaders(origin: String = "https://www.youtube.com") -> [String: String] {
        guard let sapisid else { return [:] }

        let timestamp = Int(Date().timeIntervalSince1970)
        let digest = Insecure.SHA1.hash(data: Data("\(timestamp) \(sapisid) \(origin)".utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()

        return [
            "Authorization": "SAPISIDHASH \(timestamp)_\(hex)",
            "X-Origin": origin,
            "Origin": origin,
            "X-Goog-AuthUser": authUser,
        ]
    }
}

// MARK: - Sign-in web view

/// Presents Google's own sign-in page.
///
/// Deliberately Google's real page in a web view rather than a form of our own:
/// the credentials are never seen by this app, two-factor and passkeys work, and
/// the user can see the address bar domain is Google's.
struct AccountSignInView: UIViewRepresentable {
    let onFinished: ([HTTPCookie]) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onFinished: onFinished) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .black
        // A desktop-ish agent avoids Google's "this browser may not be secure"
        // block, which fires on embedded web views advertising themselves.
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

        webView.load(URLRequest(url: URL(string: "https://accounts.google.com/ServiceLogin?service=youtube&continue=https://www.youtube.com/")!))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        let onFinished: ([HTTPCookie]) -> Void
        private var reported = false

        init(onFinished: @escaping ([HTTPCookie]) -> Void) {
            self.onFinished = onFinished
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Landing back on youtube.com means the flow completed.
            guard let host = webView.url?.host, host.contains("youtube.com"), !reported else { return }

            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
                guard let self else { return }
                let hasSession = cookies.contains {
                    ["SAPISID", "__Secure-3PAPISID"].contains($0.name) && !$0.value.isEmpty
                }
                guard hasSession else { return }
                self.reported = true
                self.onFinished(cookies)
            }
        }
    }
}
