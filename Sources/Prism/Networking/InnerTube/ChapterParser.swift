import Foundation

/// Extracts chapter markers.
///
/// YouTube exposes chapters two ways, and neither is reliable alone:
///
/// - As structured `chapterRenderer` entries in the player response, when the
///   creator's timestamps were recognised.
/// - As plain timestamps in the description, which is where they start life.
///
/// The structured form is preferred when present; the description is parsed as a
/// fallback using the same rule YouTube itself applies — the list must begin at
/// `0:00`, otherwise the timestamps are references to other videos rather than a
/// chapter list.
enum ChapterParser {

    static func chapters(from playerJSON: [String: Any], description: String?) -> [Chapter] {
        let structured = fromRenderers(playerJSON)
        if !structured.isEmpty { return structured }
        guard let description else { return [] }
        return fromDescription(description)
    }

    // MARK: Structured

    private static func fromRenderers(_ json: Any) -> [Chapter] {
        var found: [Chapter] = []
        var stack: [Any] = [json]

        while let node = stack.popLast() {
            switch node {
            case let dict as [String: Any]:
                if let chapter = dict["chapterRenderer"] as? [String: Any],
                   let ms = chapter["timeRangeStartMillis"] as? Int {
                    let title = (chapter["title"] as? [String: Any])
                        .flatMap { $0["simpleText"] as? String }
                        ?? ""
                    found.append(Chapter(
                        id: found.count,
                        title: title,
                        start: Double(ms) / 1000,
                        thumbnailURL: nil
                    ))
                }
                stack.append(contentsOf: dict.values)
            case let array as [Any]:
                stack.append(contentsOf: array)
            default:
                continue
            }
        }
        return found.sorted { $0.start < $1.start }
    }

    // MARK: Description

    /// Matches `0:00`, `1:23`, `1:02:33` at the start of a line, followed by a title.
    private static let pattern = try? NSRegularExpression(
        pattern: #"^\s*(?:\(|\[)?(\d{1,2}:)?(\d{1,2}):(\d{2})(?:\)|\])?[\s\-–—:.)]*(.+)$"#,
        options: [.anchorsMatchLines]
    )

    static func fromDescription(_ description: String) -> [Chapter] {
        guard let pattern else { return [] }

        let range = NSRange(description.startIndex..., in: description)
        var found: [Chapter] = []

        for match in pattern.matches(in: description, range: range) {
            func group(_ i: Int) -> String? {
                guard let r = Range(match.range(at: i), in: description) else { return nil }
                return String(description[r])
            }

            let hours = Double(group(1)?.dropLast() ?? "") ?? 0
            guard let minutes = Double(group(2) ?? ""),
                  let seconds = Double(group(3) ?? ""),
                  let title = group(4)?.trimmingCharacters(in: .whitespaces),
                  !title.isEmpty
            else { continue }

            found.append(Chapter(
                id: found.count,
                title: title,
                start: hours * 3600 + minutes * 60 + seconds,
                thumbnailURL: nil
            ))
        }

        // YouTube's own rule: a real chapter list starts at zero. Without this,
        // any description that cites a timestamp in another video produces a
        // bogus chapter list.
        guard let first = found.first, first.start == 0, found.count >= 3 else { return [] }

        // Timestamps must increase; a list that jumps backwards is a tracklist
        // or a set of references, not chapters.
        var ascending: [Chapter] = []
        for chapter in found {
            if let last = ascending.last, chapter.start <= last.start { continue }
            ascending.append(Chapter(
                id: ascending.count,
                title: chapter.title,
                start: chapter.start,
                thumbnailURL: chapter.thumbnailURL
            ))
        }

        return ascending.count >= 3 ? ascending : []
    }
}
