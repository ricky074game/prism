import XCTest
@testable import Prism

/// Tests for the pure logic — parsing, selection, and segment rules.
///
/// These deliberately avoid the network. The live APIs are verified separately;
/// what's valuable to pin down here is the behaviour that has already broken
/// once, or that would break silently.
final class ParsingTests: XCTestCase {

    // MARK: Timecode

    func testTimecodeFormatsHoursOnlyWhenPresent() {
        XCTAssertEqual((0.0).timecode, "0:00")
        XCTAssertEqual((9.0).timecode, "0:09")
        XCTAssertEqual((69.0).timecode, "1:09")
        XCTAssertEqual((3609.0).timecode, "1:00:09")
        XCTAssertEqual((3661.0).timecode, "1:01:01")
    }

    func testTimecodeSurvivesGarbage() {
        // `duration` is 0 until AVFoundation reports one, and NaN shows up when
        // an item fails. Neither may render as "nan:nan".
        XCTAssertEqual(Double.nan.timecode, "0:00")
        XCTAssertEqual(Double.infinity.timecode, "0:00")
        XCTAssertEqual((-5.0).timecode, "0:00")
    }

    // MARK: SponsorBlock hashing

    func testHashPrefixMatchesServerBucketing() {
        // Verified against the live API: these IDs are all returned for /5f6b.
        XCTAssertEqual(SponsorBlockService.hashPrefix("dQw4w9WgXcQ"), "5f6b")
        XCTAssertEqual(SponsorBlockService.hashPrefix("hFZFjoX2cGg"), "fba1")
        XCTAssertEqual(SponsorBlockService.hashPrefix("dQw4w9WgXcQ", length: 6).count, 6)
    }

    // MARK: Segment rules

    func testDefaultActionsSkipOnlyUnambiguousInterruptions() {
        // Intros are shown, not skipped — on plenty of channels the intro is the
        // thing people came for.
        XCTAssertEqual(SegmentCategory.sponsor.defaultAction, .skip)
        XCTAssertEqual(SegmentCategory.selfpromo.defaultAction, .skip)
        XCTAssertEqual(SegmentCategory.interaction.defaultAction, .skip)
        XCTAssertEqual(SegmentCategory.intro.defaultAction, .show)
        XCTAssertEqual(SegmentCategory.outro.defaultAction, .show)
    }

    func testPointOfInterestIsNeverARange() {
        let poi = SponsorSegment(
            id: "a", category: .poiHighlight, start: 42, end: 42,
            actionType: "poi", locked: true, votes: 3
        )
        XCTAssertTrue(poi.isPointOfInterest)
        XCTAssertFalse(poi.isFullVideo)
        XCTAssertEqual(poi.duration, 0)
    }

    func testSegmentContainsIsHalfOpen() {
        let seg = SponsorSegment(
            id: "a", category: .sponsor, start: 10, end: 20,
            actionType: "skip", locked: false, votes: 0
        )
        XCTAssertTrue(seg.contains(10))
        XCTAssertTrue(seg.contains(19.99))
        // The end must be exclusive, or skipping to `end` re-enters the segment
        // and the player seeks in a loop.
        XCTAssertFalse(seg.contains(20))
    }

    // MARK: Stream selection

    func testWebMIsRejectedBecauseAVFoundationCannotDemuxIt() {
        let vp9 = Stream(json: [
            "itag": 248, "url": "https://example.com/a",
            "mimeType": "video/webm; codecs=\"vp9\"", "bitrate": 2_000_000, "height": 1080,
        ])
        XCTAssertNotNil(vp9)
        XCTAssertFalse(vp9!.isPlayableByAVFoundation)

        let h264 = Stream(json: [
            "itag": 137, "url": "https://example.com/b",
            "mimeType": "video/mp4; codecs=\"avc1.640028\"", "bitrate": 3_000_000, "height": 1080,
        ])
        XCTAssertTrue(h264!.isPlayableByAVFoundation)
        XCTAssertTrue(h264!.isH264)
    }

    func testCipheredFormatsAreDroppedRatherThanShippedBroken() {
        // No `url` means the format needs the player JS to decipher it.
        let ciphered = Stream(json: [
            "itag": 137,
            "signatureCipher": "s=abc&url=https%3A%2F%2Fexample.com",
            "mimeType": "video/mp4; codecs=\"avc1.640028\"", "bitrate": 3_000_000,
        ])
        XCTAssertNil(ciphered)
    }

    func testCodecParsingHandlesMultipleCodecs() {
        let progressive = Stream(json: [
            "itag": 18, "url": "https://example.com/c",
            "mimeType": "video/mp4; codecs=\"avc1.42001E, mp4a.40.2\"",
            "bitrate": 500_000, "height": 360,
        ])
        XCTAssertTrue(progressive!.isProgressive)
        XCTAssertEqual(progressive!.container, "mp4")
    }

    // MARK: Chapters

    func testChaptersRequireAZeroStartAndThreeEntries() {
        // A description citing another video's timestamp must not become a
        // chapter list.
        let references = """
        Great breakdown at 4:31 in this other video
        And 12:04 here
        """
        XCTAssertTrue(ChapterParser.fromDescription(references).isEmpty)

        let real = """
        0:00 Intro
        1:30 The setup
        4:12 How it fails
        9:45 What to do instead
        """
        let parsed = ChapterParser.fromDescription(real)
        XCTAssertEqual(parsed.count, 4)
        XCTAssertEqual(parsed.first?.start, 0)
        XCTAssertEqual(parsed.first?.title, "Intro")
        XCTAssertEqual(parsed.last?.start, 9 * 60 + 45)
    }

    func testChaptersRejectNonAscendingTimestamps() {
        let tracklist = """
        0:00 One
        5:00 Two
        2:00 Three
        """
        // Only two survive the ascending filter, which is below the minimum.
        XCTAssertTrue(ChapterParser.fromDescription(tracklist).isEmpty)
    }

    func testChaptersParseHourLongTimestamps() {
        let long = """
        0:00 Start
        1:02:33 Middle
        2:15:00 End
        """
        let parsed = ChapterParser.fromDescription(long)
        XCTAssertEqual(parsed.count, 3)
        XCTAssertEqual(parsed[1].start, 3753)
        XCTAssertEqual(parsed[2].start, 8100)
    }

    // MARK: Feed parsing

    func testFeedParserFindsRenderersAtAnyDepth() {
        // The real response buries these ~8 levels down and moves them between
        // releases; the parser must not care where they are.
        let json: [String: Any] = [
            "contents": ["a": ["b": ["c": [
                ["videoRenderer": [
                    "videoId": "abc12345678",
                    "title": ["runs": [["text": "A title"]]],
                    "lengthText": ["simpleText": "10:30"],
                    "ownerText": ["runs": [["text": "A channel"]]],
                    "viewCountText": ["simpleText": "1.2M views"],
                ]]
            ]]]]
        ]
        let videos = FeedParser.videos(from: json)
        XCTAssertEqual(videos.count, 1)
        XCTAssertEqual(videos[0].id, "abc12345678")
        XCTAssertEqual(videos[0].title, "A title")
        XCTAssertEqual(videos[0].duration, 630)
        XCTAssertEqual(videos[0].channelName, "A channel")
    }

    func testFeedParserDeduplicates() {
        let entry: [String: Any] = [
            "videoRenderer": [
                "videoId": "dup12345678",
                "title": ["simpleText": "Same"],
            ]
        ]
        let json: [String: Any] = ["a": [entry], "b": [entry]]
        XCTAssertEqual(FeedParser.videos(from: json).count, 1)
    }

    func testFeedParserSkipsEntriesWithoutATitle() {
        let json: [String: Any] = ["x": ["videoRenderer": ["videoId": "noTitle1234"]]]
        XCTAssertTrue(FeedParser.videos(from: json).isEmpty)
    }
}
