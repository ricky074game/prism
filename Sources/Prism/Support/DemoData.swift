import Foundation

/// Fixture data for screenshots and previews.
///
/// CI runners are frequently rate-limited by YouTube, so screenshot runs launch
/// with `-prism-demo` and render this instead. It exercises exactly the same
/// views as live data — only the source differs — so a screenshot is still an
/// honest picture of the app.
enum DemoData {

    static var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("-prism-demo")
    }

    /// Which screen to open on launch, so each screenshot is one deterministic
    /// `simctl launch`.
    static var screen: String? {
        guard let i = ProcessInfo.processInfo.arguments.firstIndex(of: "-prism-screen"),
              i + 1 < ProcessInfo.processInfo.arguments.count
        else { return nil }
        return ProcessInfo.processInfo.arguments[i + 1]
    }

    static let videos: [Video] = [
        make("aqz-KE-bpKQ", "Big Buck Bunny — the open movie that became a test pattern",
             "Blender Foundation", 596, "14M views", "3 years ago"),
        make("LXb3EKWsInQ", "Costa Rica in 4K — shot entirely on a drone over six weeks",
             "Jacob + Katie Schwarz", 302, "42M views", "6 years ago"),
        make("hFZFjoX2cGg", "How a CPU actually executes an instruction",
             "Branch Education", 1140, "8.2M views", "1 year ago"),
        make("jNQXAC9IVRw", "Me at the zoo", "jawed", 19, "352M views", "20 years ago"),
        make("9bZkp7q19f0", "The making of a 120fps render pipeline",
             "Two Minute Papers", 743, "1.1M views", "8 months ago"),
        make("kJQP7kiw5Fk", "Field recording: a thunderstorm in the Atacama",
             "Ambient Atlas", 3612, "620K views", "2 months ago"),
        make("60ItHLz5WEA", "Why bridges resonate — and the one that shook itself apart",
             "Practical Engineering", 921, "5.4M views", "1 year ago"),
        make("RgKAFK5djSk", "Every lens I own, ranked by how often I actually use it",
             "Negative Space", 1455, "310K views", "3 weeks ago"),
    ]

    /// A representative spread: one long sponsor, a short intro, a self-promo
    /// near the end — enough for the scrubber to show real dispersion.
    static let segments: [SponsorSegment] = [
        SponsorSegment(id: "d1", category: .intro, start: 0, end: 14.5,
                       actionType: "skip", locked: true, votes: 42),
        SponsorSegment(id: "d2", category: .sponsor, start: 96, end: 168,
                       actionType: "skip", locked: true, votes: 128),
        SponsorSegment(id: "d3", category: .interaction, start: 240, end: 252,
                       actionType: "skip", locked: false, votes: 17),
        SponsorSegment(id: "d4", category: .selfpromo, start: 470, end: 512,
                       actionType: "skip", locked: false, votes: 33),
        SponsorSegment(id: "d5", category: .outro, start: 560, end: 596,
                       actionType: "skip", locked: true, votes: 61),
    ]

    static let playlists: [Playlist] = [
        Playlist(id: "PL1", title: "Things that explain themselves", author: "You",
                 thumbnailURL: nil, videoCountText: "42 videos"),
        Playlist(id: "PL2", title: "Watch on the good speakers", author: "You",
                 thumbnailURL: nil, videoCountText: "18 videos"),
        Playlist(id: "PL3", title: "Long-form, no rush", author: "You",
                 thumbnailURL: nil, videoCountText: "7 videos"),
    ]

    static let comments: [Comment] = [
        Comment(
            id: "c1",
            text: "The bit at 4:12 where the whole thing resonates and then just… stops. I've watched it six times.",
            authorName: "@practicalengineering",
            authorAvatarURL: nil,
            authorChannelID: "UC1",
            isVerified: true,
            isCreator: true,
            likeText: "12K",
            replyCount: 84,
            publishedText: "2 months ago",
            isPinned: true,
            isHearted: false,
            replyLevel: 0,
            repliesToken: "demo-replies"
        ),
        Comment(
            id: "c2",
            text: "Rendered this on a 2014 Mac Mini overnight as a test. Took eleven hours. Worth it.",
            authorName: "@fern",
            authorAvatarURL: nil,
            authorChannelID: "UC2",
            isVerified: false,
            isCreator: false,
            likeText: "3.4K",
            replyCount: 12,
            publishedText: "3 weeks ago",
            isPinned: false,
            isHearted: true,
            replyLevel: 0,
            repliesToken: "demo-replies"
        ),
        Comment(
            id: "c3",
            text: "Genuinely the clearest explanation of this I've found, and I say that having sat through a semester of it.",
            authorName: "@quietmachines",
            authorAvatarURL: nil,
            authorChannelID: "UC3",
            isVerified: false,
            isCreator: false,
            likeText: "941",
            replyCount: 0,
            publishedText: "5 days ago",
            isPinned: false,
            isHearted: false,
            replyLevel: 0,
            repliesToken: nil
        ),
        Comment(
            id: "c4",
            text: "Came for the render, stayed for the tangent about bearing tolerances.",
            authorName: "@oldgrowth",
            authorAvatarURL: nil,
            authorChannelID: "UC4",
            isVerified: false,
            isCreator: false,
            likeText: "228",
            replyCount: 3,
            publishedText: "1 day ago",
            isPinned: false,
            isHearted: false,
            replyLevel: 0,
            repliesToken: "demo-replies"
        ),
    ]

    private static func make(
        _ id: String, _ title: String, _ channel: String,
        _ duration: Double, _ views: String, _ published: String
    ) -> Video {
        Video(
            id: id,
            title: title,
            channelName: channel,
            channelID: "UC" + id,
            channelThumbnailURL: nil,
            thumbnailURL: Video.thumbnail(id),
            duration: duration,
            viewCountText: views,
            publishedText: published,
            isLive: false,
            isShort: false
        )
    }
}
