import Foundation

/// Fetches and caches the lists of videos each screen shows.
actor FeedRepository {
    static let shared = FeedRepository()

    private let client = InnerTubeClient.shared
    private var cache: [String: (fetched: Date, videos: [Video], continuation: String?)] = [:]
    private let ttl: TimeInterval = 300

    /// InnerTube browse IDs for the built-in surfaces.
    enum Surface: String {
        case home = "FEwhat_to_watch"
        case trending = "FEtrending"
        case subscriptions = "FEsubscriptions"
        case library = "FElibrary"
        case history = "FEhistory"
    }

    struct Page: Sendable {
        let videos: [Video]
        let continuation: String?
    }

    func feed(_ surface: Surface, refresh: Bool = false) async throws -> Page {
        let key = surface.rawValue

        if !refresh, let hit = cache[key], Date().timeIntervalSince(hit.fetched) < ttl {
            return Page(videos: hit.videos, continuation: hit.continuation)
        }

        let json = try await client.browse(browseID: surface.rawValue)
        let videos = FeedParser.videos(from: json)
        let token = FeedParser.continuationToken(from: json)

        cache[key] = (Date(), videos, token)
        return Page(videos: videos, continuation: token)
    }

    func more(_ surface: Surface, continuation: String) async throws -> Page {
        let json = try await client.browse(browseID: surface.rawValue, continuation: continuation)
        let videos = FeedParser.videos(from: json)
        let token = FeedParser.continuationToken(from: json)

        if var hit = cache[surface.rawValue] {
            hit.videos.append(contentsOf: videos)
            hit.continuation = token
            cache[surface.rawValue] = hit
        }
        return Page(videos: videos, continuation: token)
    }

    func search(_ query: String, continuation: String? = nil) async throws -> Page {
        let json = try await client.search(query, continuation: continuation)
        return Page(
            videos: FeedParser.videos(from: json),
            continuation: FeedParser.continuationToken(from: json)
        )
    }

    /// Shorts come from the home surface's reel shelves, filtered to the
    /// vertical format.
    func shorts(refresh: Bool = false) async throws -> Page {
        let json = try await client.browse(browseID: Surface.home.rawValue)
        var found = FeedParser.shorts(from: json)
        if found.isEmpty {
            // Some regions don't surface a reel shelf on home; searching is a
            // dependable fallback.
            let alt = try await client.search("#shorts")
            found = FeedParser.videos(from: alt).filter { $0.duration > 0 && $0.duration <= 90 }
        }
        return Page(videos: found, continuation: nil)
    }

    /// Related videos for the watch screen's up-next list.
    func related(to videoID: String) async throws -> [Video] {
        let json = try await client.next(videoID: videoID)
        return FeedParser.videos(from: json).filter { $0.id != videoID }
    }

    func clear() { cache.removeAll() }
}
