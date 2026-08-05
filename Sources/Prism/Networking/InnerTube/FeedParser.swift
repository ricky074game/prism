import Foundation

/// Turns InnerTube's renderer soup into `Video` values.
///
/// InnerTube responses nest content differently per surface — search buries
/// results under `twoColumnSearchResultsRenderer.primaryContents…`, home uses
/// `richGridRenderer`, a channel uses tabs. Those paths also change without
/// notice.
///
/// Rather than hard-code any of them, this parser **walks the whole tree and
/// harvests every renderer of a known type, wherever it happens to live**. The
/// shapes of the leaf renderers are far more stable than the scaffolding around
/// them, so this survives the layout churn that breaks path-based parsers.
enum FeedParser {

    // MARK: Entry points

    static func videos(from json: [String: Any]) -> [Video] {
        var found: [Video] = []
        var seen = Set<String>()

        harvest(json, key: "videoRenderer") { r in
            if let v = video(from: r), seen.insert(v.id).inserted { found.append(v) }
        }
        harvest(json, key: "compactVideoRenderer") { r in
            if let v = video(from: r), seen.insert(v.id).inserted { found.append(v) }
        }
        harvest(json, key: "gridVideoRenderer") { r in
            if let v = video(from: r), seen.insert(v.id).inserted { found.append(v) }
        }
        // The current format. YouTube is migrating surfaces from the old
        // *Renderer objects to view-models; playlists have already moved
        // entirely, returning zero videoRenderers and 100 lockupViewModels.
        harvest(json, key: "lockupViewModel") { r in
            if let v = lockup(from: r), seen.insert(v.id).inserted { found.append(v) }
        }
        // The TV client's shape, which is what the signed-in surfaces return.
        // It shares nothing with the others: no `videoId` field at all, and the
        // title lives under `metadata.tileMetadataRenderer`.
        harvest(json, key: "tileRenderer") { r in
            if let v = tile(from: r), seen.insert(v.id).inserted { found.append(v) }
        }
        // Home-feed items wrap a videoRenderer one level down.
        harvest(json, key: "richItemRenderer") { r in
            guard let inner = r["content"] as? [String: Any] else { return }
            for k in ["videoRenderer", "reelItemRenderer", "shortsLockupViewModel"] {
                if let vr = inner[k] as? [String: Any],
                   let v = video(from: vr, isShort: k != "videoRenderer"),
                   seen.insert(v.id).inserted {
                    found.append(v)
                }
            }
        }
        return found
    }

    static func shorts(from json: [String: Any]) -> [Video] {
        var found: [Video] = []
        var seen = Set<String>()

        // The current shape. Shorts moved to their own view-model and share
        // almost nothing with `videoRenderer`: the id is in `entityId` or the
        // tap endpoint, and the title lives under `overlayMetadata` keyed on
        // `content` rather than `text` — so the generic renderer parser finds no
        // title and silently drops every item.
        harvest(json, key: "shortsLockupViewModel") { r in
            if let v = shortsLockup(from: r), seen.insert(v.id).inserted { found.append(v) }
        }
        // Older surfaces.
        harvest(json, key: "reelItemRenderer") { r in
            if let v = video(from: r, isShort: true), seen.insert(v.id).inserted { found.append(v) }
        }
        return found
    }

    /// `tileRenderer` → `Video`. The TV client's cell.
    ///
    /// Nothing here lines up with the other renderers. The video id is often
    /// absent as a field entirely and has to be read out of the thumbnail URL —
    /// `i.ytimg.com/vi/<id>/…` — which is reliable precisely because the
    /// thumbnail is the one thing every tile has.
    private static func tile(from r: [String: Any]) -> Video? {
        let metadata = (r["metadata"] as? [String: Any])?["tileMetadataRenderer"] as? [String: Any]
        guard let title = (metadata?["title"] as? [String: Any])?["simpleText"] as? String
                ?? text(metadata?["title"]),
              !title.isEmpty
        else { return nil }

        let id = deepString(r, key: "videoId") ?? thumbnailVideoID(r)
        guard let id, id.count == 11 else { return nil }

        // The metadata lines are free-form: channel, views and age in some
        // order, sometimes fewer. Classified by shape, as elsewhere.
        var channel = "", views = "", age = ""
        var lineTexts: [String] = []
        harvest(metadata ?? [:], key: "lineItemRenderer") { item in
            if let t = text(item["text"]) ?? (item["text"] as? [String: Any])?["simpleText"] as? String {
                lineTexts.append(t)
            }
        }
        for part in lineTexts {
            // The lines carry "•" separators as items of their own, and the
            // tree walk doesn't preserve order — without this the bullet can
            // win the race to be read as the channel name.
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            guard trimmed.count > 2 else { continue }

            if trimmed.localizedCaseInsensitiveContains("view") { views = trimmed }
            else if trimmed.localizedCaseInsensitiveContains("ago") { age = trimmed }
            else if channel.isEmpty { channel = trimmed }
        }

        var duration: Double = 0
        harvest(r, key: "thumbnailOverlayTimeStatusRenderer") { overlay in
            guard duration == 0, let t = text(overlay["text"]) else { return }
            duration = parseDuration(t)
        }

        return Video(
            id: id,
            title: title,
            channelName: channel,
            channelID: "",
            channelThumbnailURL: nil,
            thumbnailURL: Video.thumbnail(id),
            duration: duration,
            viewCountText: views,
            publishedText: age,
            isLive: false,
            isShort: false
        )
    }

    /// `https://i.ytimg.com/vi/<id>/hqdefault.jpg` → `<id>`.
    private static func thumbnailVideoID(_ root: Any) -> String? {
        var stack: [Any] = [root]
        while let node = stack.popLast() {
            if let dict = node as? [String: Any] {
                if let url = dict["url"] as? String,
                   let range = url.range(of: "/vi/") {
                    let rest = url[range.upperBound...]
                    if let slash = rest.firstIndex(of: "/") {
                        let id = String(rest[..<slash])
                        if id.count == 11 { return id }
                    }
                }
                stack.append(contentsOf: dict.values)
            } else if let array = node as? [Any] {
                stack.append(contentsOf: array)
            }
        }
        return nil
    }

    /// `shortsLockupViewModel` → `Video`.
    private static func shortsLockup(from r: [String: Any]) -> Video? {
        // Prefer the tap endpoint; `entityId` is prefixed and only used as a
        // fallback when the endpoint shape changes.
        let fromTap = ((r["onTap"] as? [String: Any])?["innertubeCommand"] as? [String: Any])
            .flatMap { command -> String? in
                if let reel = command["reelWatchEndpoint"] as? [String: Any] {
                    return reel["videoId"] as? String
                }
                if let watch = command["watchEndpoint"] as? [String: Any] {
                    return watch["videoId"] as? String
                }
                return nil
            }
        let fromEntity = (r["entityId"] as? String)?
            .replacingOccurrences(of: "shorts-shelf-item-", with: "")

        guard let id = fromTap ?? fromEntity, id.count == 11 else { return nil }

        let overlay = r["overlayMetadata"] as? [String: Any]
        let title = (overlay?["primaryText"] as? [String: Any])?["content"] as? String
            ?? r["accessibilityText"] as? String
            ?? ""
        guard !title.isEmpty else { return nil }

        let views = (overlay?["secondaryText"] as? [String: Any])?["content"] as? String ?? ""

        return Video(
            id: id,
            title: title,
            channelName: "",
            channelID: "",
            channelThumbnailURL: nil,
            thumbnailURL: Video.thumbnail(id, quality: "oar2"),
            duration: 0,
            viewCountText: views,
            publishedText: "",
            isLive: false,
            isShort: true
        )
    }

    /// The token that fetches the next page.
    ///
    /// Deliberately *not* the first one in the tree. A channel tab carries
    /// three continuations, and the one a whole-tree walk reaches first belongs
    /// to the **About** panel — following it appends a channel description
    /// where the next page of videos should be, so paging looks like a channel
    /// that ran out of uploads after one page.
    ///
    /// Verified against live responses for three channels: the grid's own token
    /// is always inside `richGridRenderer`, and following it yields 48 fresh
    /// items a page with no repeats. Surfaces with no grid — search, and every
    /// continuation response, which arrives as a bare append action — fall
    /// through to the whole-tree walk and are unaffected.
    static func continuationToken(from json: [String: Any]) -> String? {
        for container in ["richGridRenderer", "gridRenderer", "reelShelfRenderer"] {
            var token: String?
            harvest(json, key: container) { grid in
                if token == nil { token = firstContinuation(in: grid) }
            }
            if let token { return token }
        }
        return firstContinuation(in: json)
    }

    /// Finds the watch page's subscribe button and reports its state.
    ///
    /// Confirmed against a live `next`: `subscribeButtonRenderer` carries both
    /// `subscribed` and the `channelId` it applies to. Signed out it is always
    /// false, which is why this is only consulted for a signed-in request.
    static func walkForSubscribeState(_ json: [String: Any], _ body: (Bool) -> Void) {
        var answered = false
        harvest(json, key: "subscribeButtonRenderer") { r in
            guard !answered, let state = r["subscribed"] as? Bool else { return }
            answered = true
            body(state)
        }
    }

    private static func firstContinuation(in root: Any) -> String? {
        var token: String?
        harvest(root, key: "continuationItemRenderer") { r in
            guard token == nil else { return }
            token = (r["continuationEndpoint"] as? [String: Any])
                .flatMap { $0["continuationCommand"] as? [String: Any] }
                .flatMap { $0["token"] as? String }
        }
        return token
    }

    // MARK: lockupViewModel → Video

    /// The view-model format.
    ///
    /// Structurally unlike the renderers: the video id is `contentId`, and the
    /// channel / views / age are an ordered list of metadata rows rather than
    /// named fields. The rows are positional — channel first, then any of views
    /// and age — so they're classified by shape rather than by index, which
    /// survives a missing row.
    private static func lockup(from r: [String: Any]) -> Video? {
        guard let id = r["contentId"] as? String, !id.isEmpty else { return nil }
        // The same view-model renders playlists and channels; only take videos.
        guard (r["contentType"] as? String ?? "").contains("VIDEO") else { return nil }

        let metadata = (r["metadata"] as? [String: Any])?["lockupMetadataViewModel"] as? [String: Any]
        guard let title = (metadata?["title"] as? [String: Any])?["content"] as? String,
              !title.isEmpty
        else { return nil }

        var channel = "", views = "", age = ""
        if let rows = ((metadata?["metadata"] as? [String: Any])?["contentMetadataViewModel"] as? [String: Any])?["metadataRows"] as? [[String: Any]] {
            let parts = rows.flatMap { ($0["metadataParts"] as? [[String: Any]]) ?? [] }
                .compactMap { ($0["text"] as? [String: Any])?["content"] as? String }
            for part in parts {
                if part.contains("views") { views = part }
                else if part.contains("ago") { age = part }
                else if channel.isEmpty { channel = part }
            }
        }

        return Video(
            id: id,
            title: title,
            channelName: channel,
            channelID: "",
            channelThumbnailURL: nil,
            thumbnailURL: Video.thumbnail(id),
            duration: lockupDuration(r),
            viewCountText: views,
            publishedText: age,
            isLive: false,
            isShort: false
        )
    }

    /// Duration lives in a thumbnail overlay badge rather than alongside the
    /// other metadata.
    private static func lockupDuration(_ r: [String: Any]) -> Double {
        var text: String?
        harvest(r, key: "thumbnailBadgeViewModel") { badge in
            guard text == nil, let t = badge["text"] as? String, t.contains(":") else { return }
            text = t
        }
        return parseDuration(text ?? "")
    }

    // MARK: Renderer → Video

    private static func video(from r: [String: Any], isShort: Bool = false) -> Video? {
        // Shorts view-models use `entityId` / `onTap` instead of `videoId`.
        let id = (r["videoId"] as? String)
            ?? (r["entityId"] as? String)?.replacingOccurrences(of: "shorts-shelf-item-", with: "")
            ?? deepString(r, key: "videoId")
        guard let id, !id.isEmpty else { return nil }

        let title = text(r["title"])
            ?? text(r["headline"])
            ?? deepString(r, key: "text")
            ?? ""
        guard !title.isEmpty else { return nil }

        let lengthText = text(r["lengthText"]) ?? ""
        let live = (r["badges"] as? [[String: Any]])?.contains { badge in
            let style = (badge["metadataBadgeRenderer"] as? [String: Any])?["style"] as? String
            return style?.contains("LIVE") == true
        } ?? false

        let owner = text(r["ownerText"]) ?? text(r["longBylineText"]) ?? text(r["shortBylineText"]) ?? ""
        let channelID = (r["ownerText"] as? [String: Any])
            .flatMap { runs($0)?.first }
            .flatMap { ($0["navigationEndpoint"] as? [String: Any]) }
            .flatMap { ($0["browseEndpoint"] as? [String: Any]) }
            .flatMap { $0["browseId"] as? String }
            ?? ""

        return Video(
            id: id,
            title: title,
            channelName: owner,
            channelID: channelID,
            channelThumbnailURL: channelThumbnail(r),
            thumbnailURL: Video.thumbnail(id, quality: isShort ? "hq720" : "hqdefault"),
            duration: parseDuration(lengthText),
            viewCountText: text(r["viewCountText"]) ?? text(r["shortViewCountText"]) ?? "",
            publishedText: text(r["publishedTimeText"]) ?? "",
            isLive: live,
            isShort: isShort
        )
    }

    private static func channelThumbnail(_ r: [String: Any]) -> URL? {
        guard let renderer = r["channelThumbnailSupportedRenderers"] as? [String: Any],
              let inner = renderer["channelThumbnailWithLinkRenderer"] as? [String: Any],
              let thumb = inner["thumbnail"] as? [String: Any],
              let list = thumb["thumbnails"] as? [[String: Any]],
              let best = list.last?["url"] as? String
        else { return nil }
        return URL(string: best.hasPrefix("//") ? "https:" + best : best)
    }

    // MARK: Primitives

    /// InnerTube writes strings two ways: `{simpleText:}` and `{runs:[{text:}]}`.
    private static func text(_ any: Any?) -> String? {
        guard let dict = any as? [String: Any] else { return nil }
        if let simple = dict["simpleText"] as? String { return simple }
        if let runs = runs(dict) {
            let joined = runs.compactMap { $0["text"] as? String }.joined()
            return joined.isEmpty ? nil : joined
        }
        return nil
    }

    private static func runs(_ dict: [String: Any]) -> [[String: Any]]? {
        dict["runs"] as? [[String: Any]]
    }

    /// `"58:14"` / `"1:02:33"` → seconds.
    private static func parseDuration(_ s: String) -> Double {
        guard !s.isEmpty else { return 0 }
        let parts = s.split(separator: ":").compactMap { Double($0) }
        guard !parts.isEmpty else { return 0 }
        return parts.reduce(0) { $0 * 60 + $1 }
    }

    // MARK: Tree walking

    /// Calls `body` for every object stored under `key`, at any depth.
    ///
    /// Iterative rather than recursive: some responses nest 40+ levels and a
    /// recursive walk on a deeply-nested continuation can get uncomfortably
    /// close to the stack limit.
    private static func harvest(
        _ root: Any,
        key: String,
        body: ([String: Any]) -> Void
    ) {
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

    /// First string found under `key` at any depth.
    private static func deepString(_ root: Any, key: String) -> String? {
        var stack: [Any] = [root]
        while let node = stack.popLast() {
            switch node {
            case let dict as [String: Any]:
                if let s = dict[key] as? String { return s }
                stack.append(contentsOf: dict.values)
            case let array as [Any]:
                stack.append(contentsOf: array)
            default:
                continue
            }
        }
        return nil
    }
}
