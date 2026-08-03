import Foundation

/// A video as it appears in a feed, search result, or related list.
struct Video: Identifiable, Sendable, Hashable {
    let id: String
    let title: String
    let channelName: String
    let channelID: String
    let channelThumbnailURL: URL?
    let thumbnailURL: URL?
    /// Seconds. Zero for live streams.
    let duration: Double
    /// Pre-formatted by YouTube ("1.2M views") — parsing and re-formatting it
    /// only loses the localisation YouTube already did.
    let viewCountText: String
    let publishedText: String
    let isLive: Bool
    let isShort: Bool

    var durationText: String { isLive ? "LIVE" : duration.timecode }

    /// The highest-quality still. `maxresdefault` isn't generated for every
    /// video, so `hqdefault` is the safe universal choice for feed cells.
    static func thumbnail(_ id: String, quality: String = "hqdefault") -> URL? {
        URL(string: "https://i.ytimg.com/vi/\(id)/\(quality).jpg")
    }
}

struct Channel: Identifiable, Sendable, Hashable {
    let id: String
    let name: String
    let handle: String?
    let thumbnailURL: URL?
    let subscriberText: String?
}

/// A chapter marker parsed from the video description or YouTube's own data.
struct Chapter: Identifiable, Sendable, Hashable {
    let id: Int
    let title: String
    let start: Double
    let thumbnailURL: URL?
}

/// A named home-feed row.
struct FeedSection: Identifiable, Sendable {
    let id: String
    let title: String
    let videos: [Video]
}
