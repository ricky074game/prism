import Foundation

/// The official YouTube Data API v3, used only for the account-specific things
/// InnerTube can't give an anonymous session.
///
/// Quota is the binding constraint and it is tighter than most documentation
/// suggests: `search.list` has its own bucket of roughly **100 calls a day**,
/// separate from the ~10,000 units shared by everything else. So search stays on
/// InnerTube, which is unmetered, and this is reserved for subscriptions,
/// playlists, and writes — all of which cost 1–50 units.
actor YouTubeDataAPI {
    static let shared = YouTubeDataAPI()

    private let base = URL(string: "https://www.googleapis.com/youtube/v3/")!

    /// The bearer token for Data API calls.
    ///
    /// Comes from the same YouTube sign-in that authenticates InnerTube: the
    /// device flow requests `auth/youtube` alongside the InnerTube scopes, so one
    /// token covers both and there is no separate OAuth client to register.
    ///
    /// A self-registered OAuth client is still honoured if one is configured,
    /// which keeps the door open for anyone who wants their own quota rather
    /// than sharing the TV client's.
    private static func token() async -> String? {
        if let session = await AccountSession.shared.accessToken() { return session }
        return await GoogleAuth.shared.validToken()
    }

    enum APIError: LocalizedError {
        case notSignedIn
        case quotaExceeded
        case http(Int)

        var errorDescription: String? {
            switch self {
            case .notSignedIn: "Sign in to see this."
            case .quotaExceeded: "You've hit today's YouTube API limit. It resets at midnight Pacific."
            case .http(let code): "YouTube returned \(code)."
            }
        }
    }

    private func get(_ path: String, query: [String: String]) async throws -> [String: Any] {
        guard let token = await Self.token() else {
            throw APIError.notSignedIn
        }

        var comps = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        comps.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }

        var req = URLRequest(url: comps.url!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw APIError.http(-1) }

        // 403 covers both quota exhaustion and permission problems; the body
        // distinguishes them and the difference matters to the user.
        if http.statusCode == 403,
           let body = String(data: data, encoding: .utf8),
           body.contains("quota") {
            throw APIError.quotaExceeded
        }
        guard (200..<300).contains(http.statusCode) else { throw APIError.http(http.statusCode) }

        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    /// The signed-in account's subscriptions. 1 unit per call, 50 per page.
    func subscriptions(pageToken: String? = nil) async throws -> (channels: [Channel], next: String?) {
        var query = [
            "part": "snippet",
            "mine": "true",
            "maxResults": "50",
            "order": "alphabetical",
        ]
        query["pageToken"] = pageToken

        let json = try await get("subscriptions", query: query)
        let items = json["items"] as? [[String: Any]] ?? []

        let channels: [Channel] = items.compactMap { item in
            guard let snippet = item["snippet"] as? [String: Any],
                  let title = snippet["title"] as? String,
                  let resource = snippet["resourceId"] as? [String: Any],
                  let channelID = resource["channelId"] as? String
            else { return nil }

            let thumbURL = (snippet["thumbnails"] as? [String: Any])
                .flatMap { ($0["medium"] ?? $0["default"]) as? [String: Any] }
                .flatMap { $0["url"] as? String }
                .flatMap(URL.init(string:))

            return Channel(id: channelID, name: title, handle: nil, thumbnailURL: thumbURL, subscriberText: nil)
        }

        return (channels, json["nextPageToken"] as? String)
    }

    /// Recent uploads for a channel.
    ///
    /// Deliberately avoids `search.list`, which would exhaust the ~100/day
    /// bucket after a handful of channels. A channel's uploads playlist ID is
    /// its channel ID with the second character changed from `C` to `U`, and
    /// `playlistItems.list` costs 1 unit.
    func uploads(channelID: String, limit: Int = 10) async throws -> [Video] {
        var playlistID = channelID
        guard playlistID.count > 2 else { return [] }
        let index = playlistID.index(playlistID.startIndex, offsetBy: 1)
        playlistID.replaceSubrange(index...index, with: "U")

        let json = try await get("playlistItems", query: [
            "part": "snippet,contentDetails",
            "playlistId": playlistID,
            "maxResults": String(limit),
        ])

        let items = json["items"] as? [[String: Any]] ?? []
        return items.compactMap { item in
            guard let snippet = item["snippet"] as? [String: Any],
                  let title = snippet["title"] as? String,
                  let details = item["contentDetails"] as? [String: Any],
                  let videoID = details["videoId"] as? String
            else { return nil }

            return Video(
                id: videoID,
                title: title,
                channelName: snippet["videoOwnerChannelTitle"] as? String ?? "",
                channelID: channelID,
                channelThumbnailURL: nil,
                thumbnailURL: Video.thumbnail(videoID),
                duration: 0,
                viewCountText: "",
                publishedText: Self.relativeDate(snippet["publishedAt"] as? String),
                isLive: false,
                isShort: false
            )
        }
    }

    /// Like or remove a rating. 50 units.
    func rate(videoID: String, rating: String) async throws {
        guard let token = await Self.token() else { throw APIError.notSignedIn }

        var comps = URLComponents(url: base.appendingPathComponent("videos/rate"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            URLQueryItem(name: "id", value: videoID),
            URLQueryItem(name: "rating", value: rating),
        ]

        var req = URLRequest(url: comps.url!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("0", forHTTPHeaderField: "Content-Length")

        _ = try await URLSession.shared.data(for: req)
    }

    /// Subscribe to or unsubscribe from a channel. 50 units either way.
    ///
    /// Unsubscribing needs the *subscription's* id rather than the channel's, so
    /// it costs an extra lookup to find which subscription points at this
    /// channel.
    func setSubscription(channelID: String, subscribed: Bool) async throws {
        guard let token = await Self.token() else { throw APIError.notSignedIn }
        guard !channelID.isEmpty else { return }

        if subscribed {
            var request = URLRequest(url: base.appendingPathComponent("subscriptions")
                .appending(queryItems: [URLQueryItem(name: "part", value: "snippet")]))
            request.httpMethod = "POST"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: [
                "snippet": ["resourceId": ["kind": "youtube#channel", "channelId": channelID]]
            ])
            _ = try await URLSession.shared.data(for: request)
        } else {
            let json = try await get("subscriptions", query: [
                "part": "id",
                "mine": "true",
                "forChannelId": channelID,
            ])
            guard let items = json["items"] as? [[String: Any]],
                  let id = items.first?["id"] as? String
            else { return }

            var request = URLRequest(url: base.appendingPathComponent("subscriptions")
                .appending(queryItems: [URLQueryItem(name: "id", value: id)]))
            request.httpMethod = "DELETE"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            _ = try await URLSession.shared.data(for: request)
        }
    }

    /// "3 days ago" from an ISO-8601 timestamp.
    private static func relativeDate(_ iso: String?) -> String {
        guard let iso, let date = ISO8601DateFormatter().date(from: iso) else { return "" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
