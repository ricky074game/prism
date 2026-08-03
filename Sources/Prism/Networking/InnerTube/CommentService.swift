import Foundation

/// Fetches comments.
///
/// Uses InnerTube rather than the Data API's `commentThreads.list`. The Data API
/// would cost quota per call and returns less — no pinned or hearted state, and
/// awkward reply handling — while InnerTube is unmetered and carries everything
/// the UI shows.
actor CommentService {
    static let shared = CommentService()

    private let client = InnerTubeClient.shared

    enum Sort: String, CaseIterable, Identifiable, Sendable {
        case top, newest
        var id: String { rawValue }
        var title: String { self == .top ? "Top comments" : "Newest first" }
    }

    struct Page: Sendable {
        let comments: [Comment]
        let continuation: String?
        /// Total as YouTube reports it, e.g. "4,281".
        let totalText: String?
    }

    /// Comments are two round-trips: `/next` for the video yields a token that
    /// opens the comment section, then that token is redeemed for the comments
    /// themselves. There is no single call that returns them.
    func comments(for videoID: String, sort: Sort = .top) async throws -> Page {
        let next = try await client.next(videoID: videoID)

        guard var token = CommentParser.commentSectionToken(from: next) else {
            // Creators can disable comments; that's a valid state, not a failure.
            return Page(comments: [], continuation: nil, totalText: nil)
        }

        if sort == .newest, let sorted = try? await sortToken(token, to: .newest) {
            token = sorted
        }

        let json = try await client.next(continuation: token)
        let parsed = CommentParser.comments(from: json)

        return Page(
            comments: parsed.comments,
            continuation: parsed.continuation,
            totalText: commentCount(from: json)
        )
    }

    func more(continuation: String) async throws -> Page {
        let json = try await client.next(continuation: continuation)
        let parsed = CommentParser.comments(from: json)
        return Page(comments: parsed.comments, continuation: parsed.continuation, totalText: nil)
    }

    /// Replies to one comment.
    func replies(token: String) async throws -> Page {
        let json = try await client.next(continuation: token)
        let parsed = CommentParser.comments(from: json)
        return Page(comments: parsed.comments, continuation: parsed.continuation, totalText: nil)
    }

    // MARK: Sorting

    /// The sort control is itself a continuation: the first comments response
    /// carries tokens for "Top" and "Newest", and switching means redeeming the
    /// other one.
    private func sortToken(_ token: String, to sort: Sort) async throws -> String? {
        let json = try await client.next(continuation: token)
        var tokens: [String] = []

        walk(json, key: "sortFilterSubMenuRenderer") { menu in
            guard let items = menu["subMenuItems"] as? [[String: Any]] else { return }
            for item in items {
                if let t = (item["serviceEndpoint"] as? [String: Any])
                    .flatMap({ $0["continuationCommand"] as? [String: Any] })
                    .flatMap({ $0["token"] as? String }) {
                    tokens.append(t)
                }
            }
        }
        // Menu order is [Top, Newest].
        return sort == .newest ? tokens.dropFirst().first : tokens.first
    }

    private func commentCount(from json: [String: Any]) -> String? {
        var count: String?
        walk(json, key: "commentsHeaderRenderer") { header in
            guard count == nil else { return }
            count = (header["countText"] as? [String: Any])
                .flatMap { ($0["runs"] as? [[String: Any]])?.first }
                .flatMap { $0["text"] as? String }
        }
        return count
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
