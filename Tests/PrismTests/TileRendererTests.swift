import XCTest
@testable import Prism

/// Tests for the TV client's cell format.
///
/// This is the shape every signed-in surface returns — subscriptions, history,
/// liked, Watch Later — because the account token is only valid on the TV
/// client. It shares nothing with `videoRenderer` or `lockupViewModel`: the
/// title is under `metadata.tileMetadataRenderer`, the id is in a tap endpoint,
/// and the channel, view count and age arrive as unordered line items with
/// literal "•" separators between them.
///
/// Fixture trimmed from a live `browse` of `VLLL` on 2026-08-04.
final class TileRendererTests: XCTestCase {

    private var likedPage: [String: Any] {
        [
            "contents": ["tvBrowseRenderer": ["content": ["sectionListRenderer": ["contents": [
                ["shelfRenderer": ["content": ["horizontalListRenderer": ["items": [
                    ["tileRenderer": tile],
                ]]]]],
            ]]]]],
        ]
    }

    private var tile: [String: Any] {
        [
            "header": ["tileHeaderRenderer": [
                "thumbnail": ["thumbnails": [[
                    "url": "https://i.ytimg.com/vi/oDRYmKRTpqU/hqdefault.jpg?sqp=-oaymwEm",
                    "width": 480, "height": 360,
                ]]],
                "thumbnailOverlays": [
                    ["thumbnailOverlayResumePlaybackRenderer": ["percentDurationWatched": 10]],
                    ["thumbnailOverlayTimeStatusRenderer": ["text": ["simpleText": "0:41"]]],
                ],
            ]],
            "metadata": ["tileMetadataRenderer": [
                "title": ["simpleText": "I Blindly Bought EVERY Offer"],
                "lines": [
                    ["lineRenderer": ["items": [
                        ["lineItemRenderer": ["text": ["runs": [["text": "BrawlReflex"]]]]],
                    ]]],
                    ["lineRenderer": ["items": [
                        ["lineItemRenderer": ["text": ["simpleText": "4.9M views"]]],
                        ["lineItemRenderer": ["text": ["simpleText": "•"]]],
                        ["lineItemRenderer": ["text": ["simpleText": "2 months ago"]]],
                    ]]],
                ],
            ]],
            "onSelectCommand": ["watchEndpoint": [
                "videoId": "oDRYmKRTpqU",
                "playlistId": "LL",
            ]],
        ]
    }

    func testTileParses() throws {
        let videos = FeedParser.videos(from: likedPage)
        XCTAssertEqual(videos.count, 1, "a tileRenderer must yield a video")

        let v = try XCTUnwrap(videos.first)
        XCTAssertEqual(v.id, "oDRYmKRTpqU")
        XCTAssertEqual(v.title, "I Blindly Bought EVERY Offer")
        XCTAssertEqual(v.channelName, "BrawlReflex")
        XCTAssertEqual(v.viewCountText, "4.9M views")
        XCTAssertEqual(v.publishedText, "2 months ago")
        XCTAssertEqual(v.duration, 41, accuracy: 0.5)
    }

    /// The tree walk is a stack over unordered dictionary values, so which line
    /// item is seen first is not stable between runs. Repeating it makes an
    /// order-dependent parser fail rather than pass most of the time — the "•"
    /// separator is a real item and would otherwise sometimes become the
    /// channel name.
    func testSeparatorNeverBecomesTheChannelName() {
        for _ in 0..<200 {
            let v = FeedParser.videos(from: likedPage).first
            XCTAssertEqual(v?.channelName, "BrawlReflex")
        }
    }

    /// Some tiles carry no `videoId` field at all; the thumbnail URL is the
    /// only place the id reliably appears.
    func testFallsBackToTheThumbnailForTheID() throws {
        var stripped = tile
        stripped["onSelectCommand"] = ["clickTrackingParams": "abc"]

        let videos = FeedParser.videos(from: ["x": ["tileRenderer": stripped]])
        XCTAssertEqual(videos.first?.id, "oDRYmKRTpqU")
    }

    /// A tile with no title is scaffolding, not content.
    func testUntitledTilesAreSkipped() {
        var untitled = tile
        untitled["metadata"] = ["tileMetadataRenderer": [:]]

        XCTAssertTrue(FeedParser.videos(from: ["x": ["tileRenderer": untitled]]).isEmpty)
    }
}
