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
