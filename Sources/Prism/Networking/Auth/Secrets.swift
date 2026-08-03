import Foundation

/// Build-time configuration.
///
/// The Google OAuth client ID is not a secret in the cryptographic sense —
/// native OAuth clients have no secret at all, which is exactly why PKCE exists
/// — but it is *account-specific*. Each person building Prism registers their
/// own iOS OAuth client in Google Cloud Console and puts the ID here, rather
/// than sharing one and pooling everyone's API quota.
///
/// To set it up:
///
/// 1. Google Cloud Console → create a project → enable **YouTube Data API v3**
/// 2. APIs & Services → Credentials → Create Credentials → **OAuth client ID**
/// 3. Application type **iOS**, bundle ID `com.prism.client`
/// 4. Paste the client ID below
///
/// The consent screen can stay in Testing mode; add your own Google account as
/// a test user. That allows up to 100 users and needs no Google verification.
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
