import Foundation

struct Playlist: Identifiable, Sendable, Hashable {
    let id: String
    let title: String
    let author: String
    let thumbnailURL: URL?
    let videoCountText: String

    /// The browse id for a playlist is its id with a `VL` prefix. This trips
    /// people up constantly — browsing the bare playlist id returns nothing.
    var browseID: String { id.hasPrefix("VL") ? id : "VL" + id }
}

/// Playlists, and the signed-in user's library.
actor PlaylistService {
    static let shared = PlaylistService()

    private let client = InnerTubeClient.shared

    struct Contents: Sendable {
        let title: String
        let author: String
        let videos: [Video]
        let continuation: String?
    }

    /// Well-known browse ids.
    ///
    /// History and Watch Later only return the signed-in user's data when the
    /// request carries account authentication; anonymously they come back empty
    /// rather than erroring, which is why the UI checks sign-in state first.
    enum Library: String {
        case likedVideos = "VLLL"
        case watchLater = "VLWL"
        case history = "FEhistory"
        case library = "FElibrary"
    }

    func contents(playlistID: String) async throws -> Contents {
        let browseID = playlistID.hasPrefix("VL") || playlistID.hasPrefix("FE")
            ? playlistID
            : "VL" + playlistID

        let json = try await client.browse(browseID: browseID)
        return parse(json)
    }

    func more(continuation: String) async throws -> Contents {
        let json = try await client.browse(browseID: "", continuation: continuation)
        return parse(json)
    }

    private func parse(_ json: [String: Any]) -> Contents {
        Contents(
            title: title(from: json) ?? "Playlist",
            author: author(from: json) ?? "",
            videos: FeedParser.videos(from: json),
            continuation: FeedParser.continuationToken(from: json)
        )
    }

    private func title(from json: [String: Any]) -> String? {
        if let metadata = json["metadata"] as? [String: Any],
           let renderer = metadata["playlistMetadataRenderer"] as? [String: Any],
           let title = renderer["title"] as? String {
            return title
        }
        var found: String?
        walk(json, key: "playlistHeaderRenderer") { header in
            guard found == nil else { return }
            found = (header["title"] as? [String: Any])?["simpleText"] as? String
        }
        return found
    }

    private func author(from json: [String: Any]) -> String? {
        var found: String?
        walk(json, key: "playlistHeaderRenderer") { header in
            guard found == nil else { return }
            found = (header["ownerText"] as? [String: Any])
                .flatMap { ($0["runs"] as? [[String: Any]])?.first }
                .flatMap { $0["text"] as? String }
        }
        return found
    }

    /// Playlists shown on a browse surface.
    ///
    /// `nonisolated` because it only reads its argument — parsing needs none of
    /// the actor's state, and requiring an await would force every caller into
    /// an async context for no reason.
    nonisolated static func playlists(from json: [String: Any]) -> [Playlist] {
        var found: [Playlist] = []
        var seen = Set<String>()

        // Current format.
        walkStatic(json, key: "lockupViewModel") { lockup in
            guard let id = lockup["contentId"] as? String,
                  (lockup["contentType"] as? String ?? "").contains("PLAYLIST"),
                  seen.insert(id).inserted
            else { return }

            let metadata = (lockup["metadata"] as? [String: Any])?["lockupMetadataViewModel"] as? [String: Any]
            let title = (metadata?["title"] as? [String: Any])?["content"] as? String ?? ""
            guard !title.isEmpty else { return }

            found.append(Playlist(
                id: id,
                title: title,
                author: "",
                thumbnailURL: nil,
                videoCountText: ""
            ))
        }

        // Older surfaces still use the renderer.
        walkStatic(json, key: "playlistRenderer") { r in
            guard let id = r["playlistId"] as? String, seen.insert(id).inserted else { return }
            let title = (r["title"] as? [String: Any])?["simpleText"] as? String ?? ""
            guard !title.isEmpty else { return }

            found.append(Playlist(
                id: id,
                title: title,
                author: (r["shortBylineText"] as? [String: Any])
                    .flatMap { ($0["runs"] as? [[String: Any]])?.first }
                    .flatMap { $0["text"] as? String } ?? "",
                thumbnailURL: nil,
                videoCountText: (r["videoCount"] as? String).map { "\($0) videos" } ?? ""
            ))
        }

        return found
    }

    /// Static twin of `walk`, for the nonisolated parser above.
    nonisolated private static func walkStatic(_ root: Any, key: String, body: ([String: Any]) -> Void) {
        var stack: [Any] = [root]
        while let node = stack.popLast() {
            switch node {
            case let dict as [String: Any]:
                if let hit = dict[key] as? [String: Any] { body(hit) }
                stack.append(contentsOf: dict.values)
            case let array as [Any]:
                stack.append(contentsOf: array)
            default: continue
            }
        }
    }

    private func walk(_ root: Any, key: String, body: ([String: Any]) -> Void) {
        var stack: [Any] = [root]
        while let node = stack.popLast() {
            switch node {
            case let dict as [String: Any]:
                if let hit = dict[key] as? [String: Any] { body(hit) }
                stack.append(contentsOf: dict.values)
            case let array as [Any]:
                stack.append(contentsOf: array)
            default: continue
            }
        }
    }
}
