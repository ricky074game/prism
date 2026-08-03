import XCTest
@testable import Prism

/// Tests for the two surfaces YouTube has migrated to view-models.
///
/// Both of these broke the obvious implementation, and both broke *silently* —
/// a parser written against the documented `*Renderer` shapes returns an empty
/// list rather than throwing, so it reads as "no comments" or "empty playlist"
/// instead of "broken parser". These fixtures are trimmed from real responses
/// captured on 2026-08-03 to make that failure loud if it ever regresses.
final class EntityFormatTests: XCTestCase {

    // MARK: Comments

    /// Shape confirmed against a live `/next` continuation response: zero
    /// `commentRenderer`s, 40 `commentViewModel`s, 20 `commentEntityPayload`
    /// mutations, joined by `commentKey`.
    private var commentsFixture: [String: Any] {
        [
            "frameworkUpdates": [
                "entityBatchUpdate": [
                    "mutations": [
                        [
                            "entityKey": "KEY1",
                            "payload": [
                                "commentEntityPayload": [
                                    "key": "KEY1",
                                    "properties": [
                                        "content": ["content": "Phantastic Gus is my spirit animal."],
                                        "publishedTime": "6 years ago (edited)",
                                        "replyLevel": 0,
                                    ],
                                    "author": [
                                        "displayName": "@MarkRober",
                                        "channelId": "UCY1kMZp36IQSyNx_9h4mpCg",
                                        "isVerified": true,
                                        "isCreator": true,
                                        "avatarThumbnailUrl": "https://yt3.ggpht.com/abc",
                                    ],
                                    // `likeCountNotliked` is a formatted string,
                                    // and `heartActive` is null rather than false.
                                    "toolbar": [
                                        "likeCountNotliked": "151K",
                                        "replyCount": "592",
                                        "heartActive": NSNull(),
                                    ],
                                ]
                            ],
                        ]
                    ]
                ]
            ],
            "contents": [
                ["commentViewModel": ["commentKey": "KEY1"]]
            ],
        ]
    }

    func testCommentsParseFromEntityMutations() {
        let (comments, _) = CommentParser.comments(from: commentsFixture)

        XCTAssertEqual(comments.count, 1)
        let comment = comments[0]
        XCTAssertEqual(comment.text, "Phantastic Gus is my spirit animal.")
        XCTAssertEqual(comment.authorName, "@MarkRober")
        XCTAssertEqual(comment.likeText, "151K")
        XCTAssertEqual(comment.replyCount, 592)
        XCTAssertTrue(comment.isCreator)
        XCTAssertTrue(comment.isVerified)
    }

    func testNullHeartIsNotTreatedAsHearted() {
        // A plain Bool cast on `heartActive` would be wrong: the field is null,
        // not false, when the creator hasn't hearted the comment.
        let (comments, _) = CommentParser.comments(from: commentsFixture)
        XCTAssertFalse(comments[0].isHearted)
    }

    func testViewModelWithoutAPayloadIsDropped() {
        // Ordering and data arrive separately; a view-model whose payload is
        // missing must not produce an empty-bodied comment.
        var fixture = commentsFixture
        fixture["contents"] = [
            ["commentViewModel": ["commentKey": "KEY1"]],
            ["commentViewModel": ["commentKey": "MISSING"]],
        ]
        let (comments, _) = CommentParser.comments(from: fixture)
        XCTAssertEqual(comments.count, 1)
    }

    func testClassicRendererFormatYieldsNothing() {
        // Documents the reason this parser exists: the old shape is gone, and a
        // parser built for it finds nothing rather than failing loudly.
        let old: [String: Any] = [
            "contents": [["commentRenderer": [
                "contentText": ["runs": [["text": "hello"]]],
                "authorText": ["simpleText": "@someone"],
            ]]]
        ]
        let (comments, _) = CommentParser.comments(from: old)
        XCTAssertTrue(comments.isEmpty)
    }

    // MARK: Playlists

    /// Shape confirmed against a live playlist browse: zero
    /// `playlistVideoRenderer`s, 100 `lockupViewModel`s.
    private func lockupFixture(contentType: String = "LOCKUP_CONTENT_TYPE_VIDEO") -> [String: Any] {
        [
            "contents": [[
                "lockupViewModel": [
                    "contentId": "fOT0BUpITw8",
                    "contentType": contentType,
                    "metadata": [
                        "lockupMetadataViewModel": [
                            "title": ["content": "BELLAKEO (Video Oficial) - Peso Pluma, Anitta"],
                            "metadata": [
                                "contentMetadataViewModel": [
                                    "metadataRows": [
                                        ["metadataParts": [
                                            ["text": ["content": "Peso Pluma"]],
                                        ]],
                                        ["metadataParts": [
                                            ["text": ["content": "748M views"]],
                                            ["text": ["content": "2 years ago"]],
                                        ]],
                                    ]
                                ]
                            ],
                        ]
                    ],
                    "contentImage": [
                        "thumbnailViewModel": [
                            "overlays": [[
                                "thumbnailOverlayBadgeViewModel": [
                                    "thumbnailBadges": [[
                                        "thumbnailBadgeViewModel": ["text": "3:52"]
                                    ]]
                                ]
                            ]]
                        ]
                    ],
                ]
            ]]
        ]
    }

    func testPlaylistItemsParseFromLockupViewModel() {
        let videos = FeedParser.videos(from: lockupFixture())

        XCTAssertEqual(videos.count, 1)
        let video = videos[0]
        XCTAssertEqual(video.id, "fOT0BUpITw8")
        XCTAssertEqual(video.title, "BELLAKEO (Video Oficial) - Peso Pluma, Anitta")
        XCTAssertEqual(video.channelName, "Peso Pluma")
        XCTAssertEqual(video.viewCountText, "748M views")
        XCTAssertEqual(video.publishedText, "2 years ago")
        // Duration lives in a thumbnail badge, not alongside the other metadata.
        XCTAssertEqual(video.duration, 232)
    }

    func testLockupMetadataIsClassifiedByShapeNotPosition() {
        // Rows are positional in the response. Classifying by index would shift
        // everything when a row is absent; classifying by content survives it.
        var fixture = lockupFixture()
        var lockup = ((fixture["contents"] as! [[String: Any]])[0])["lockupViewModel"] as! [String: Any]
        var metadata = lockup["metadata"] as! [String: Any]
        var inner = metadata["lockupMetadataViewModel"] as! [String: Any]
        inner["metadata"] = ["contentMetadataViewModel": ["metadataRows": [
            ["metadataParts": [["text": ["content": "Some Channel"]]]],
            ["metadataParts": [["text": ["content": "5 days ago"]]]],
        ]]]
        metadata["lockupMetadataViewModel"] = inner
        lockup["metadata"] = metadata
        fixture["contents"] = [["lockupViewModel": lockup]]

        let videos = FeedParser.videos(from: fixture)
        XCTAssertEqual(videos.count, 1)
        XCTAssertEqual(videos[0].channelName, "Some Channel")
        XCTAssertEqual(videos[0].publishedText, "5 days ago")
        XCTAssertEqual(videos[0].viewCountText, "")
    }

    func testNonVideoLockupsAreIgnored() {
        // The same view-model renders playlists and channels; only videos belong
        // in a video feed.
        let videos = FeedParser.videos(from: lockupFixture(contentType: "LOCKUP_CONTENT_TYPE_PLAYLIST"))
        XCTAssertTrue(videos.isEmpty)
    }

    // MARK: Playlist ids

    func testPlaylistBrowseIDIsPrefixed() {
        // Browsing a bare playlist id returns nothing; the VL prefix is what
        // makes it a browse id.
        let playlist = Playlist(id: "PLabc123", title: "T", author: "A",
                                thumbnailURL: nil, videoCountText: "")
        XCTAssertEqual(playlist.browseID, "VLPLabc123")

        let already = Playlist(id: "VLPLabc123", title: "T", author: "A",
                               thumbnailURL: nil, videoCountText: "")
        XCTAssertEqual(already.browseID, "VLPLabc123")
    }
}
