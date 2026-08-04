import Foundation

/// A channel's header — everything shown above its tabs.
struct ChannelDetail: Sendable, Hashable {
    let id: String
    let name: String
    let handle: String
    let subscriberText: String
    let videoCountText: String
    let description: String
    let avatarURL: URL?
    let bannerURL: URL?
}

/// One community post.
struct CommunityPost: Identifiable, Sendable, Hashable {
    let id: String
    let author: String
    let authorAvatarURL: URL?
    let text: String
    let publishedText: String
    let likeText: String
    let replyText: String
    /// Images attached to the post, in order.
    let imageURLs: [URL]
    /// Set when the post links a video.
    let attachedVideo: Video?
    /// Set when the post is a poll; the strings are the choices.
    let pollChoices: [String]
}

/// Channels: header, videos, shorts, playlists and posts.
actor ChannelService {
    static let shared = ChannelService()

    private let client = InnerTubeClient.shared

    /// Tab selectors.
    ///
    /// These `params` values are stable and are what the site itself sends;
    /// reading them out of the browse response each time would cost an extra
    /// round-trip for no benefit.
    enum Tab: String, CaseIterable, Identifiable, Sendable {
        case videos, shorts, live, playlists, posts

        var id: String { rawValue }

        var title: String {
            switch self {
            case .videos: "Videos"
            case .shorts: "Shorts"
            case .live: "Live"
            case .playlists: "Playlists"
            case .posts: "Posts"
            }
        }

        var params: String {
            switch self {
            case .videos: "EgZ2aWRlb3PyBgQKAjoA"
            case .shorts: "EgZzaG9ydHPyBgUKA5oBAA%3D%3D"
            case .live: "EgdzdHJlYW1z8gYECgJ6AA%3D%3D"
            case .playlists: "EglwbGF5bGlzdHPyBgQKAkIA"
            case .posts: "EgVwb3N0c_IGBAoCSgA%3D"
            }
        }
    }

    struct TabContents: Sendable {
        let videos: [Video]
        let posts: [CommunityPost]
        let playlists: [Playlist]
        let continuation: String?
    }

    // MARK: Header

    func detail(channelID: String) async throws -> ChannelDetail {
        let json = try await client.browse(browseID: channelID)
        return Self.parseHeader(json, channelID: channelID)
    }

    /// Header and the first tab in one call — the browse response already
    /// contains both, so fetching them separately would waste a round-trip.
    func load(channelID: String, tab: Tab = .videos) async throws -> (ChannelDetail, TabContents) {
        let json = try await client.browse(browseID: channelID, params: tab.params)
        return (Self.parseHeader(json, channelID: channelID), Self.parseTab(json, tab: tab))
    }

    func tab(channelID: String, tab: Tab) async throws -> TabContents {
        let json = try await client.browse(browseID: channelID, params: tab.params)
        return Self.parseTab(json, tab: tab)
    }

    func more(continuation: String) async throws -> TabContents {
        let json = try await client.browse(browseID: "", continuation: continuation)
        return Self.parseTab(json, tab: .videos)
    }

    /// Uploads, for the shuffle button.
    func randomVideo(channelID: String) async throws -> Video? {
        let contents = try await tab(channelID: channelID, tab: .videos)
        return contents.videos.randomElement()
    }

    // MARK: Parsing

    /// The header moved from `c4TabbedHeaderRenderer` to `pageHeaderRenderer`,
    /// where the name, handle, subscriber and video counts are no longer named
    /// fields — they arrive as an ordered list of metadata parts. They're
    /// classified by shape (a leading `@`, the word "subscriber", the word
    /// "video") rather than by position, so a missing row doesn't shift the
    /// rest.
    static func parseHeader(_ json: [String: Any], channelID: String) -> ChannelDetail {
        var name = "", handle = "", subs = "", videos = "", description = ""
        var avatar: URL?, banner: URL?

        walk(json, key: "pageHeaderViewModel") { header in
            if let title = (header["title"] as? [String: Any])?["dynamicTextViewModel"] as? [String: Any],
               let text = (title["text"] as? [String: Any])?["content"] as? String {
                name = text
            }

            if let rows = ((header["metadata"] as? [String: Any])?["contentMetadataViewModel"] as? [String: Any])?["metadataRows"] as? [[String: Any]] {
                let parts = rows.flatMap { ($0["metadataParts"] as? [[String: Any]]) ?? [] }
                    .compactMap { ($0["text"] as? [String: Any])?["content"] as? String }
                for part in parts {
                    if part.hasPrefix("@") { handle = part }
                    else if part.localizedCaseInsensitiveContains("subscriber") { subs = part }
                    else if part.localizedCaseInsensitiveContains("video") { videos = part }
                }
            }

            if let desc = ((header["description"] as? [String: Any])?["descriptionPreviewViewModel"] as? [String: Any]),
               let text = (desc["description"] as? [String: Any])?["content"] as? String {
                description = text
            }

            avatar = firstImageURL(header["image"])
            banner = lastImageURL(header["banner"])
        }

        // Older responses still use the previous header.
        if name.isEmpty {
            walk(json, key: "c4TabbedHeaderRenderer") { header in
                name = header["title"] as? String ?? name
                subs = (header["subscriberCountText"] as? [String: Any])
                    .flatMap { $0["simpleText"] as? String } ?? subs
                avatar = avatar ?? firstImageURL(header["avatar"])
                banner = banner ?? lastImageURL(header["banner"])
            }
        }

        return ChannelDetail(
            id: channelID,
            name: name,
            handle: handle,
            subscriberText: subs,
            videoCountText: videos,
            description: description,
            avatarURL: avatar,
            bannerURL: banner
        )
    }

    static func parseTab(_ json: [String: Any], tab: Tab) -> TabContents {
        TabContents(
            videos: tab == .shorts ? FeedParser.shorts(from: json) : FeedParser.videos(from: json),
            posts: tab == .posts ? parsePosts(json) : [],
            playlists: tab == .playlists ? PlaylistService.shared.playlists(from: json) : [],
            continuation: FeedParser.continuationToken(from: json)
        )
    }

    /// Community posts still use the classic renderer, unlike comments and
    /// playlists — YouTube's migration to view-models hasn't reached this
    /// surface yet.
    static func parsePosts(_ json: [String: Any]) -> [CommunityPost] {
        var found: [CommunityPost] = []
        var seen = Set<String>()

        walk(json, key: "backstagePostRenderer") { post in
            guard let id = post["postId"] as? String, seen.insert(id).inserted else { return }

            let text = ((post["contentText"] as? [String: Any])?["runs"] as? [[String: Any]] ?? [])
                .compactMap { $0["text"] as? String }
                .joined()

            let attachment = post["backstageAttachment"] as? [String: Any]

            var images: [URL] = []
            if let attachment {
                // A single image, or several under a multi-image renderer.
                walk(attachment, key: "backstageImageRenderer") { image in
                    if let url = lastImageURL(image["image"]) { images.append(url) }
                }
            }

            var attachedVideo: Video?
            if let attachment,
               let renderer = attachment["videoRenderer"] as? [String: Any] {
                attachedVideo = FeedParser.videos(from: ["v": ["videoRenderer": renderer]]).first
            }

            var poll: [String] = []
            if let attachment {
                walk(attachment, key: "pollRenderer") { pollRenderer in
                    poll = ((pollRenderer["choices"] as? [[String: Any]]) ?? []).compactMap {
                        (($0["text"] as? [String: Any])?["runs"] as? [[String: Any]])?
                            .compactMap { $0["text"] as? String }.joined()
                    }
                }
            }

            found.append(CommunityPost(
                id: id,
                author: (post["authorText"] as? [String: Any])
                    .flatMap { ($0["runs"] as? [[String: Any]])?.first }
                    .flatMap { $0["text"] as? String } ?? "",
                authorAvatarURL: firstImageURL(post["authorThumbnail"]),
                text: text,
                publishedText: (post["publishedTimeText"] as? [String: Any])
                    .flatMap { ($0["runs"] as? [[String: Any]])?.first }
                    .flatMap { $0["text"] as? String } ?? "",
                likeText: (post["voteCount"] as? [String: Any])
                    .flatMap { $0["simpleText"] as? String } ?? "",
                replyText: deepText(post["actionButtons"], key: "replyCount") ?? "",
                imageURLs: images,
                attachedVideo: attachedVideo,
                pollChoices: poll
            ))
        }

        return found
    }

    // MARK: Helpers

    /// Thumbnail lists come in several wrappers; both helpers dig for the first
    /// `thumbnails`/`sources` array they find rather than assuming a path.
    private static func firstImageURL(_ any: Any?) -> URL? { imageURL(any, last: false) }
    private static func lastImageURL(_ any: Any?) -> URL? { imageURL(any, last: true) }

    private static func imageURL(_ any: Any?, last: Bool) -> URL? {
        guard let any else { return nil }
        var result: URL?
        var stack: [Any] = [any]

        while let node = stack.popLast(), result == nil {
            if let dict = node as? [String: Any] {
                for key in ["thumbnails", "sources"] {
                    if let list = dict[key] as? [[String: Any]],
                       let raw = (last ? list.last : list.first)?["url"] as? String {
                        // Protocol-relative URLs appear on author thumbnails.
                        result = URL(string: raw.hasPrefix("//") ? "https:" + raw : raw)
                        break
                    }
                }
                if result == nil { stack.append(contentsOf: dict.values) }
            } else if let array = node as? [Any] {
                stack.append(contentsOf: array)
            }
        }
        return result
    }

    private static func deepText(_ root: Any?, key: String) -> String? {
        guard let root else { return nil }
        var stack: [Any] = [root]
        while let node = stack.popLast() {
            if let dict = node as? [String: Any] {
                if let s = dict[key] as? String { return s }
                stack.append(contentsOf: dict.values)
            } else if let array = node as? [Any] {
                stack.append(contentsOf: array)
            }
        }
        return nil
    }

    private static func walk(_ root: Any, key: String, body: ([String: Any]) -> Void) {
        var stack: [Any] = [root]
        while let node = stack.popLast() {
            if let dict = node as? [String: Any] {
                if let hit = dict[key] as? [String: Any] { body(hit) }
                stack.append(contentsOf: dict.values)
            } else if let array = node as? [Any] {
                stack.append(contentsOf: array)
            }
        }
    }
}
