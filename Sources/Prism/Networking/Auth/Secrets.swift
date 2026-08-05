import Foundation

/// Build-time configuration.
///
/// ## You probably don't need this
///
/// Signing in through Settings → Account covers everything the app actually
/// uses, because that data comes from InnerTube rather than the Data API.
///
/// It is worth being precise about why, since the obvious assumption is wrong
/// and was wrong in this file for a while. The device flow's token is issued to
/// YouTube's own TV OAuth client, and **YouTube Data API v3 is disabled on that
/// Google project** — every call returns HTTP 403, "has not been used in
/// project 861556708454 before or it is disabled". It isn't a quota limit and
/// it isn't a scope you can request; the project is Google's and you cannot
/// enable an API on it.
///
/// So a Cloud client of your own buys exactly one thing: the list of channels
/// you subscribe to, for the avatar strip. The subscription *feed*, history,
/// liked videos and Watch Later all come from InnerTube's TV client and need
/// none of this.
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
