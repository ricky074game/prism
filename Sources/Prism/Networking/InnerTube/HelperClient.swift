import Foundation

/// Optional fallback to a personal helper server.
///
/// Prism resolves almost everything on-device. Two categories can't be reached
/// that way, and neither is fixable by trying harder in Swift:
///
/// - **"Made for kids" videos.** Every client that hands out plain stream URLs
///   refuses them outright.
/// - **SABR-only content.** Google is migrating delivery to a protobuf
///   streaming protocol where formats carry no URL at all.
///
/// `server/server.js` in this repo wraps yt-dlp, which handles both. The app
/// calls it *only* after direct extraction has already failed, so with no
/// server configured everything else still works exactly as before — this is a
/// safety net, not a dependency.
actor HelperClient {
    static let shared = HelperClient()

    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        // Extraction shells out to yt-dlp, which can take a while on a cold
        // request; the server caches, so only the first is slow.
        config.timeoutIntervalForRequest = 90
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: config)
    }

    /// Base URL from Settings, e.g. `http://192.168.1.20:8787`.
    static var baseURL: URL? {
        guard let raw = UserDefaults.standard.string(forKey: "helper.baseURL"),
              !raw.trimmingCharacters(in: .whitespaces).isEmpty,
              let url = URL(string: raw.trimmingCharacters(in: .whitespaces))
        else { return nil }
        return url
    }

    static var isConfigured: Bool { baseURL != nil }

    private struct Response: Decodable {
        let title: String?
        let author: String?
        let duration: Double?
        let progressiveUrl: URL?
        let videoUrl: URL?
        let audioUrl: URL?
        let height: Int?
        let vcodec: String?
        let acodec: String?
        let error: String?
    }

    /// True when the server answers. Used by Settings to give a real result
    /// rather than accepting any string as valid.
    func check(_ base: URL) async -> Bool {
        var request = URLRequest(url: base.appendingPathComponent("health"))
        request.timeoutInterval = 8
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return false }
        return json["ok"] as? Bool == true
    }

    /// Resolves a video the app couldn't resolve itself.
    func resolve(videoID: String) async throws -> PlaybackSource {
        guard let base = Self.baseURL else {
            throw InnerTubeError.unplayable(reason: "No helper server is set up.")
        }

        var components = URLComponents(
            url: base.appendingPathComponent("resolve"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "v", value: videoID)]

        let (data, response) = try await session.data(from: components.url!)
        let decoded = try JSONDecoder().decode(Response.self, from: data)

        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw InnerTubeError.unplayable(reason: decoded.error ?? "The helper server couldn't play this video.")
        }

        var streams: [Stream] = []
        if let url = decoded.progressiveUrl {
            streams.append(Stream(
                synthesizedURL: url,
                mimeType: "video/mp4",
                codecs: "\(decoded.vcodec ?? "avc1"),\(decoded.acodec ?? "mp4a")",
                height: decoded.height,
                itag: 9001
            ))
        }
        if let url = decoded.videoUrl {
            streams.append(Stream(
                synthesizedURL: url,
                mimeType: "video/mp4",
                codecs: decoded.vcodec ?? "avc1",
                height: decoded.height,
                itag: 9002
            ))
        }
        if let url = decoded.audioUrl {
            streams.append(Stream(
                synthesizedURL: url,
                mimeType: "audio/mp4",
                codecs: decoded.acodec ?? "mp4a",
                height: nil,
                itag: 9003
            ))
        }

        guard !streams.isEmpty else { throw InnerTubeError.noFormats }

        return PlaybackSource(
            videoID: videoID,
            title: decoded.title ?? "",
            author: decoded.author ?? "",
            channelID: "",
            duration: decoded.duration ?? 0,
            isLive: false,
            viewCount: 0,
            streams: streams,
            hlsManifestURL: nil,
            description: nil,
            chapters: []
        )
    }
}

extension Stream {
    /// Builds a `Stream` from a URL the helper resolved.
    ///
    /// The normal initialiser parses InnerTube's format JSON, which the helper
    /// doesn't return — it hands back already-selected URLs.
    init(synthesizedURL: URL, mimeType: String, codecs: String, height: Int?, itag: Int) {
        self.itag = itag
        self.url = synthesizedURL
        self.mimeType = mimeType
        self.codecs = codecs
        self.bitrate = 0
        self.width = nil
        self.height = height
        self.fps = nil
        self.qualityLabel = height.map { "\($0)p" }
        self.audioChannels = nil
        self.contentLength = nil
    }
}
