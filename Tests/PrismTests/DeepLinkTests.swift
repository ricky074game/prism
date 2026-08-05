import XCTest
@testable import Prism

/// Tests for link parsing.
///
/// Worth pinning tightly because the failure mode is silent: an unrecognised
/// URL opens nothing at all, and a *loosely* recognised one opens the wrong
/// thing — `/watch/about` as a video id, say.
final class DeepLinkTests: XCTestCase {

    private func video(_ string: String) -> String? {
        guard let url = URL(string: string), case .video(let id)? = DeepLink.parse(url) else { return nil }
        return id
    }

    func testEveryYouTubeShapeThatCarriesAnID() {
        let id = "dQw4w9WgXcQ"
        for url in [
            "https://www.youtube.com/watch?v=\(id)",
            "https://youtube.com/watch?v=\(id)&t=42s",
            "https://m.youtube.com/watch?v=\(id)",
            "https://youtu.be/\(id)",
            "https://youtu.be/\(id)?t=42",
            "https://www.youtube.com/shorts/\(id)",
            "https://www.youtube.com/embed/\(id)",
            "https://www.youtube.com/live/\(id)",
            "https://www.youtube.com/v/\(id)",
        ] {
            XCTAssertEqual(video(url), id, "failed to read an id from \(url)")
        }
    }

    func testPrismsOwnScheme() {
        let id = "dQw4w9WgXcQ"
        XCTAssertEqual(video("prism://\(id)"), id)
        XCTAssertEqual(video("prism://watch?v=\(id)"), id)
    }

    /// Video ids are case-sensitive and a URL's *host* is not — it's lowercased
    /// on parsing. Reading `prism://dQw4w9WgXcQ` out of the host therefore
    /// yielded `dqw4w9wgxcq`: a different video, or none at all.
    func testCaseSurvivesThePrismScheme() {
        for id in ["dQw4w9WgXcQ", "ABCDEFGHIJK", "abcdefghijk", "aB-dE_gHiJ0"] {
            XCTAssertEqual(video("prism://\(id)"), id)
            XCTAssertEqual(video("prism://watch?v=\(id)"), id)
        }
    }

    func testChannelLinks() {
        let channel = "UCMOqf8ab-42UUQIdVoKwjlQ"
        for url in ["https://www.youtube.com/channel/\(channel)", "prism://channel/\(channel)"] {
            guard let parsed = URL(string: url).flatMap(DeepLink.parse),
                  case .channel(let id) = parsed
            else { return XCTFail("not parsed as a channel: \(url)") }
            XCTAssertEqual(id, channel)
        }
    }

    /// An id is exactly 11 URL-safe characters. Accepting anything in that
    /// position turns ordinary pages into requests for videos that don't exist.
    func testThingsThatAreNotVideos() {
        for url in [
            "https://www.youtube.com/watch/about",
            "https://www.youtube.com/feed/subscriptions",
            "https://www.youtube.com/@PracticalEngineering",
            "https://www.youtube.com/shorts/",
            "prism://",
        ] {
            XCTAssertNil(video(url), "should not have been read as a video: \(url)")
        }
    }

    /// Any site can put `?v=` in a URL. Opening those would be trusting a
    /// stranger's query string.
    func testOnlyYouTubeHostsAreTrusted() {
        XCTAssertNil(video("https://example.com/watch?v=dQw4w9WgXcQ"))
        XCTAssertNil(video("https://youtube.com.evil.test/watch?v=dQw4w9WgXcQ"))
        XCTAssertEqual(video("https://music.youtube.com/watch?v=dQw4w9WgXcQ"), "dQw4w9WgXcQ")
    }

    /// The id is taken from `v=` wherever it appears, so tracking parameters
    /// and playlist context don't matter.
    func testExtraQueryParametersAreIgnored() {
        XCTAssertEqual(
            video("https://www.youtube.com/watch?app=desktop&v=dQw4w9WgXcQ&list=PL123&index=2"),
            "dQw4w9WgXcQ"
        )
    }
}
