import Foundation

/// Turns a URL into something to open.
///
/// ## What this can and cannot do
///
/// It cannot make `https://youtube.com/…` links open Prism on their own. That
/// is a Universal Link, and iOS only routes one to an app when the *domain*
/// serves an `apple-app-site-association` file naming that app's team and
/// bundle id. The file has to be at `https://youtube.com/.well-known/…`, so
/// only Google can put Prism in it. No entitlement, no plist key and no
/// amount of local configuration substitutes — this is enforced by iOS
/// fetching the file from the domain itself.
///
/// What does work, and what this parses:
///
/// - `prism://` links, which Prism owns outright
/// - a YouTube URL handed over deliberately — from the share sheet, a
///   Shortcut, or another app calling `openURL` — since the id is in the URL
///   either way
enum DeepLink {
    case video(String)
    case channel(String)

    /// Every YouTube URL shape that carries a video id, plus Prism's own.
    ///
    ///     prism://watch?v=ID     prism://ID
    ///     youtu.be/ID            youtube.com/watch?v=ID
    ///     youtube.com/shorts/ID  youtube.com/embed/ID
    ///     youtube.com/live/ID    youtube.com/v/ID
    static func parse(_ url: URL) -> DeepLink? {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let host = (components?.host ?? "").lowercased()
        let path = components?.path ?? ""
        let segments = path.split(separator: "/").map(String.init)

        // Only YouTube's hosts and Prism's own scheme. Any site can put `?v=`
        // in a URL, and opening those as videos would be trusting a stranger's
        // query string.
        let isYouTube = host == "youtu.be"
            || host == "youtube.com"
            || host.hasSuffix(".youtube.com")
        guard isYouTube || url.scheme == "prism" else { return nil }

        // ?v= wins wherever it appears — it's the canonical form.
        if let v = components?.queryItems?.first(where: { $0.name == "v" })?.value,
           isVideoID(v) {
            return .video(v)
        }

        // youtu.be/<id>, and prism://<id> where the id lands in the host.
        if host == "youtu.be", let id = segments.first, isVideoID(id) {
            return .video(id)
        }
        if url.scheme == "prism", isVideoID(host) {
            return .video(host)
        }

        // /shorts/<id>, /embed/<id>, /live/<id>, /v/<id>, /watch/<id>
        if segments.count >= 2,
           ["shorts", "embed", "live", "v", "watch"].contains(segments[0].lowercased()),
           isVideoID(segments[1]) {
            return .video(segments[1])
        }

        // Channels: /channel/UC…, and prism://channel/UC…
        if let index = segments.firstIndex(of: "channel"),
           segments.count > index + 1,
           segments[index + 1].hasPrefix("UC") {
            return .channel(segments[index + 1])
        }

        return nil
    }

    /// Video ids are exactly 11 characters of the URL-safe alphabet. Checking
    /// that rather than "non-empty" keeps `/watch/about` from being opened as
    /// a video.
    private static func isVideoID(_ candidate: String) -> Bool {
        candidate.count == 11 && candidate.allSatisfy {
            $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_"
        }
    }
}
