import Foundation

/// Build-time configuration.
///
/// ## You probably don't need this
///
/// Signing in through Settings → Account already covers the Data API. The device
/// flow requests `https://www.googleapis.com/auth/youtube` alongside the
/// InnerTube scopes, so one token authenticates both and subscriptions, liking
/// and subscribing work with no Cloud project at all.
///
/// The only reason to register your own client is quota: the shared path uses
/// the YouTube TV client's allocation. A private client gives you your own
/// ~10,000 units a day.
///
/// If you want that:
///
/// 1. Google Cloud Console → create a project → enable **YouTube Data API v3**
/// 2. APIs & Services → Credentials → Create Credentials → **OAuth client ID**
/// 3. Application type **iOS**, bundle ID `com.prism.client`
/// 4. Paste the client ID below
///
/// This step cannot be scripted — `gcloud` has never been able to create
/// general OAuth clients, and the IAP commands that came closest were retired
/// in January 2026. The consent screen can stay in Testing mode with your own
/// account added as a test user; that allows 100 users and needs no
/// verification.
enum Secrets {
    /// Looks like `123456789-abcdefg.apps.googleusercontent.com`.
    ///
    /// Left empty, sign-in is presented as unavailable rather than failing with
    /// an opaque Google error page.
    static let googleClientID: String = {
        // An override lets CI and local builds inject one without editing source.
        if let fromEnv = Bundle.main.object(forInfoDictionaryKey: "GoogleClientID") as? String,
           !fromEnv.isEmpty, !fromEnv.hasPrefix("$") {
            return fromEnv
        }
        return ""
    }()
}
