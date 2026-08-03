import Foundation

/// One comment.
struct Comment: Identifiable, Sendable, Hashable {
    let id: String
    let text: String
    let authorName: String
    let authorAvatarURL: URL?
    let authorChannelID: String
    let isVerified: Bool
    let isCreator: Bool
    /// Pre-formatted by YouTube ("151K") — re-deriving it only loses the
    /// localisation YouTube already did.
    let likeText: String
    let replyCount: Int
    let publishedText: String
    let isPinned: Bool
    let isHearted: Bool
    /// 0 for a top-level comment, 1 for a reply.
    let replyLevel: Int

    /// Token that loads this comment's replies, when it has any.
    let repliesToken: String?
}

/// Parses comments out of an InnerTube `/next` continuation response.
///
/// ## Why this is not the obvious shape
///
/// Nearly every guide describes `commentRenderer` objects nested in the
/// response. That format is **gone** — a live response now contains zero of
/// them. Comments moved to an entity/mutation model:
///
/// - The *ordering* lives in `commentViewModel` entries, each holding a
///   `commentKey`.
/// - The *data* lives separately in
///   `frameworkUpdates.entityBatchUpdate.mutations[].payload.commentEntityPayload`,
///   keyed by that same string.
///
/// So the parser builds a dictionary of payloads, then walks the view-models in
/// order and joins. A parser written against the old format silently returns an
/// empty list rather than failing loudly, which is the worst kind of broken.
enum CommentParser {

    static func comments(from json: [String: Any]) -> (comments: [Comment], continuation: String?) {
        let payloads = entityPayloads(from: json)
        let replies = replyTokens(from: json)
        var viewModels: [[String: Any]] = []

        harvest(json, key: "commentViewModel") { viewModels.append($0) }
        // Replies wrap the same view-model one level down.
        harvest(json, key: "commentThreadRenderer") { thread in
            if let vm = (thread["commentViewModel"] as? [String: Any])?["commentViewModel"] as? [String: Any] {
                viewModels.append(vm)
            }
        }

        var seen = Set<String>()
        var result: [Comment] = []

        for vm in viewModels {
            guard let key = vm["commentKey"] as? String,
                  let payload = payloads[key],
                  seen.insert(key).inserted
            else { continue }
            if let comment = build(key: key, payload: payload, viewModel: vm, repliesToken: replies[key]) {
                result.append(comment)
            }
        }

        return (result, continuationToken(from: json))
    }

    // MARK: Joining

    private static func entityPayloads(from json: [String: Any]) -> [String: [String: Any]] {
        guard let updates = json["frameworkUpdates"] as? [String: Any],
              let batch = updates["entityBatchUpdate"] as? [String: Any],
              let mutations = batch["mutations"] as? [[String: Any]]
        else { return [:] }

        var map: [String: [String: Any]] = [:]
        for mutation in mutations {
            guard let payload = mutation["payload"] as? [String: Any],
                  let comment = payload["commentEntityPayload"] as? [String: Any]
            else { continue }
            // `key` and `entityKey` are the same string in practice, but index
            // both so a mismatch can't drop the comment.
            if let key = comment["key"] as? String { map[key] = comment }
            if let key = mutation["entityKey"] as? String { map[key] = comment }
        }
        return map
    }

    private static func build(
        key: String,
        payload: [String: Any],
        viewModel: [String: Any],
        repliesToken: String?
    ) -> Comment? {
        let props = payload["properties"] as? [String: Any] ?? [:]
        let author = payload["author"] as? [String: Any] ?? [:]
        let toolbar = payload["toolbar"] as? [String: Any] ?? [:]

        let content = (props["content"] as? [String: Any])?["content"] as? String ?? ""
        guard !content.isEmpty else { return nil }

        let avatar = (author["avatarThumbnailUrl"] as? String).flatMap(URL.init(string:))

        // `heartActive` is null rather than false when the creator hasn't
        // hearted, so a plain Bool cast would be wrong.
        let hearted = (toolbar["heartActive"] as? Bool) ?? false

        return Comment(
            id: key,
            text: content,
            authorName: author["displayName"] as? String ?? "",
            authorAvatarURL: avatar,
            authorChannelID: author["channelId"] as? String ?? "",
            isVerified: author["isVerified"] as? Bool ?? false,
            isCreator: author["isCreator"] as? Bool ?? false,
            likeText: toolbar["likeCountNotliked"] as? String ?? "",
            replyCount: Int(toolbar["replyCount"] as? String ?? "") ?? 0,
            publishedText: props["publishedTime"] as? String ?? "",
            isPinned: (viewModel["pinnedText"] as? String) != nil,
            isHearted: hearted,
            replyLevel: props["replyLevel"] as? Int ?? 0,
            repliesToken: repliesToken
        )
    }

    // MARK: Continuations

    /// The token for the next page of comments.
    ///
    /// Skips reply continuations, which also appear as
    /// `continuationItemRenderer` but must not be treated as "more comments".
    static func continuationToken(from json: [String: Any]) -> String? {
        var token: String?
        harvest(json, key: "continuationItemRenderer") { renderer in
            guard token == nil else { return }
            let button = renderer["button"] as? [String: Any]
            let isReplyButton = button != nil
            guard !isReplyButton else { return }
            token = (renderer["continuationEndpoint"] as? [String: Any])
                .flatMap { $0["continuationCommand"] as? [String: Any] }
                .flatMap { $0["token"] as? String }
        }
        return token
    }

    /// The token that opens a comment's replies.
    static func replyTokens(from json: [String: Any]) -> [String: String] {
        var map: [String: String] = [:]
        harvest(json, key: "commentThreadRenderer") { thread in
            guard let vm = (thread["commentViewModel"] as? [String: Any])?["commentViewModel"] as? [String: Any],
                  let key = vm["commentKey"] as? String
            else { return }
            var found: String?
            harvest(thread, key: "continuationItemRenderer") { renderer in
                guard found == nil else { return }
                found = (renderer["continuationEndpoint"] as? [String: Any])
                    .flatMap { $0["continuationCommand"] as? [String: Any] }
                    .flatMap { $0["token"] as? String }
            }
            if let found { map[key] = found }
        }
        return map
    }

    /// Finds the token that loads the comment section for a video, from a
    /// `/next` response.
    static func commentSectionToken(from nextJSON: [String: Any]) -> String? {
        var token: String?
        harvest(nextJSON, key: "itemSectionRenderer") { section in
            guard token == nil,
                  section["sectionIdentifier"] as? String == "comment-item-section",
                  let contents = section["contents"] as? [[String: Any]]
            else { return }
            for item in contents {
                if let renderer = item["continuationItemRenderer"] as? [String: Any] {
                    token = (renderer["continuationEndpoint"] as? [String: Any])
                        .flatMap { $0["continuationCommand"] as? [String: Any] }
                        .flatMap { $0["token"] as? String }
                }
            }
        }
        return token
    }

    // MARK: Tree walking

    private static func harvest(_ root: Any, key: String, body: ([String: Any]) -> Void) {
        var stack: [Any] = [root]
        while let node = stack.popLast() {
            switch node {
            case let dict as [String: Any]:
                if let hit = dict[key] as? [String: Any] { body(hit) }
                stack.append(contentsOf: dict.values)
            case let array as [Any]:
                stack.append(contentsOf: array)
            default:
                continue
            }
        }
    }
}
