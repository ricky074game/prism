import Foundation

/// Fetches and caches the lists of videos each screen shows.
actor FeedRepository {
    static let shared = FeedRepository()

    private let client = InnerTubeClient.shared
    private var cache: [String: (fetched: Date, videos: [Video], continuation: String?)] = [:]
    private let ttl: TimeInterval = 300

    /// InnerTube browse IDs for the built-in surfaces.
    ///
    /// `FEtrending` is deliberately absent — YouTube retired the Trending tab
    /// and the browse id now returns HTTP 400 "Request contains an invalid
    /// argument". Anything asking for trending gets the discovery feed instead.
    enum Surface: String {
        case home = "FEwhat_to_watch"
        case subscriptions = "FEsubscriptions"
        case library = "FElibrary"
        case history = "FEhistory"
    }

    /// Topics used to build a feed when there's nothing personal to show.
    ///
    /// Signed out, YouTube's home feed is genuinely empty — it replies "Try
    /// searching to get started", because with no watch history it has nothing
    /// to recommend. Rather than render that as a blank screen, Prism assembles
    /// a feed from a handful of broad searches. They're deliberately varied so
    /// the result reads as a discovery feed rather than one topic.
    private static let discoveryTopics = [
        "documentary", "how it's made", "live performance",
        "space", "cooking", "architecture", "field recording",
    ]

    struct Page: Sendable {
        let videos: [Video]
        let continuation: String?
    }

    func feed(_ surface: Surface, refresh: Bool = false) async throws -> Page {
        let key = surface.rawValue

        if !refresh, let hit = cache[key], Date().timeIntervalSince(hit.fetched) < ttl {
            return Page(videos: hit.videos, continuation: hit.continuation)
        }

        // Subscriptions and history are the account's, so they go through the
        // client the account token is valid for. Home stays on WEB: it works
        // signed out, and the personalised version isn't worth losing that.
        let json = PlaylistService.isPersonal(surface.rawValue)
            ? try await client.accountBrowse(browseID: surface.rawValue)
            : try await client.browse(browseID: surface.rawValue)
        var videos = FeedParser.videos(from: json)
        var token = FeedParser.continuationToken(from: json)

        // Signed out, home comes back with no items at all — YouTube has no
        // history to build recommendations from. Falling back keeps the app
        // from opening on a blank screen.
        if videos.isEmpty, surface == .home {
            videos = try await discoveryFeed()
            token = nil
        }

        cache[key] = (Date(), videos, token)
        return Page(videos: videos, continuation: token)
    }

    /// A feed assembled from several broad searches, interleaved.
    ///
    /// Searches run concurrently and results are round-robined rather than
    /// concatenated, so the feed doesn't open with seven documentaries followed
    /// by seven cooking videos.
    func discoveryFeed() async throws -> [Video] {
        let topics = Self.discoveryTopics.shuffled()

        let batches = await withTaskGroup(of: [Video].self) { group in
            for topic in topics.prefix(5) {
                group.addTask { [client] in
                    guard let json = try? await client.search(topic) else { return [] }
                    return Array(FeedParser.videos(from: json).prefix(6))
                }
            }
            var all: [[Video]] = []
            for await batch in group { all.append(batch) }
            return all
        }

        var interleaved: [Video] = []
        var seen = Set<String>()
        for index in 0..<(batches.map(\.count).max() ?? 0) {
            for batch in batches where index < batch.count {
                let video = batch[index]
                if seen.insert(video.id).inserted { interleaved.append(video) }
            }
        }
        return interleaved
    }

    func more(_ surface: Surface, continuation: String) async throws -> Page {
        // Page two of an account surface has to keep the account client, or it
        // fails exactly the way page one used to.
        let json = PlaylistService.isPersonal(surface.rawValue)
            ? try await client.accountBrowse(browseID: surface.rawValue, continuation: continuation)
            : try await client.browse(browseID: surface.rawValue, continuation: continuation)
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

    /// Shorts.
    ///
    /// Search is the primary source rather than the home shelf: signed out,
    /// home has no shelves at all, so the shelf-first order returned nothing.
    func shorts(refresh: Bool = false) async throws -> Page {
        let json = try await client.search("#shorts")
        var found = FeedParser.shorts(from: json)

        if found.isEmpty {
            // Home carries a reel shelf once there's a session behind it.
            let home = try await client.browse(browseID: Surface.home.rawValue)
            found = FeedParser.shorts(from: home)
        }
        if found.isEmpty {
            // Last resort — treat short regular results as shorts.
            found = FeedParser.videos(from: json).filter { $0.duration > 0 && $0.duration <= 90 }
        }
        return Page(videos: found, continuation: nil)
    }

    /// Related videos for the watch screen's up-next list.
    func related(to videoID: String) async throws -> [Video] {
        let json = try await client.next(videoID: videoID)
        return FeedParser.videos(from: json).filter { $0.id != videoID }
    }

    /// Whether the signed-in user already follows this video's channel.
    ///
    /// `nil` means "don't know" — signed out, or the request failed — which the
    /// UI shows as the neutral Subscribe state rather than asserting that you
    /// aren't subscribed.
    func isSubscribed(toChannelOf videoID: String) async -> Bool? {
        guard await AccountSession.shared.isSignedIn else { return nil }
        guard let json = try? await client.accountNext(videoID: videoID) else { return nil }

        var subscribed: Bool?
        FeedParser.walkForSubscribeState(json) { subscribed = $0 }
        return subscribed
    }

    func clear() { cache.removeAll() }
}
