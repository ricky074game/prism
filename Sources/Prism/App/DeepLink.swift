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

        // The host is established *before* anything is read out of the URL.
        // Checking `?v=` first is the tempting order — it's the canonical form —
        // and it quietly accepts `https://example.com/watch?v=…`, which is a
        // stranger's query string deciding what this app opens.
        let segments: [String]
        if url.scheme == "prism" {
            // Read from the raw string rather than `host` and `path`. A URL's
            // host is *case-insensitive* and gets lowercased on parsing, while
            // video ids are case-sensitive — so `prism://dQw4w9WgXcQ` came back
            // as `dqw4w9wgxcq`, an id for a different video or for none.
            let body = url.absoluteString.dropFirst("prism://".count)
            segments = body.split(separator: "?")
                .first
                .map { $0.split(separator: "/").map(String.init) } ?? []
        } else {
            // Only YouTube's hosts. Any site can put `?v=` in a URL, and
            // opening those would be trusting a stranger's query string.
            let host = (components?.host ?? "").lowercased()
            guard host == "youtu.be" || host == "youtube.com" || host.hasSuffix(".youtube.com")
            else { return nil }

            // youtu.be puts the id straight after the host.
            let path = (components?.path ?? "").split(separator: "/").map(String.init)
            if host == "youtu.be", let id = path.first, isVideoID(id) { return .video(id) }
            segments = path
        }

        // `?v=` is canonical, and by here the source is known to be trusted.
        if let v = components?.queryItems?.first(where: { $0.name == "v" })?.value,
           isVideoID(v) {
            return .video(v)
        }

        // prism://<id>
        if url.scheme == "prism", segments.count == 1, isVideoID(segments[0]) {
            return .video(segments[0])
        }

        // /shorts/<id>, /embed/<id>, /live/<id>, /v/<id>, /watch/<id>
        if segments.count >= 2,
           ["shorts", "embed", "live", "v", "watch"].contains(segments[0].lowercased()),
           isVideoID(segments[1]) {
            return .video(segments[1])
        }

        // /channel/UC…
        if let index = segments.firstIndex(where: { $0.lowercased() == "channel" }),
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
