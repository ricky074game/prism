import XCTest
@testable import Prism

/// Tests for which continuation token gets followed.
///
/// A channel tab carries three of them. Only one belongs to the content grid;
/// the others drive the About panel and the channel's engagement panels. Taking
/// the first one a whole-tree walk happens to reach appends a channel
/// description where page two of the videos should be — and because the parser
/// then finds no videos in that response, it reads as "this channel has no more
/// uploads" rather than as a bug.
///
/// Shapes confirmed against live `browse` responses for three channels on
/// 2026-08-04: every channel tab returned three tokens, the About one was
/// reached first, and the grid's own token returned 48 fresh items per page
/// with no repeats across four pages.
final class ContinuationTests: XCTestCase {

    /// A channel tab: an About continuation alongside the grid's own.
    private var channelTab: [String: Any] {
        [
            "contents": [
                "twoColumnBrowseResultsRenderer": [
                    "tabs": [[
                        "tabRenderer": [
                            "content": [
                                "richGridRenderer": [
                                    "contents": [
                                        ["richItemRenderer": ["content": [
                                            "videoRenderer": [
                                                "videoId": "aaaaaaaaaaa",
                                                "title": ["simpleText": "An upload"],
                                            ],
                                        ]]],
                                        ["continuationItemRenderer": [
                                            "continuationEndpoint": [
                                                "continuationCommand": ["token": "GRID_TOKEN"],
                                            ],
                                        ]],
                                    ],
                                ],
                            ],
                        ],
                    ]],
                ],
            ],
            "engagementPanels": [[
                "engagementPanelSectionListRenderer": [
                    "content": [
                        "sectionListRenderer": [
                            "contents": [[
                                "continuationItemRenderer": [
                                    "continuationEndpoint": [
                                        "continuationCommand": ["token": "ABOUT_TOKEN"],
                                    ],
                                ],
                            ]],
                        ],
                    ],
                ],
            ]],
        ]
    }

    func testGridContinuationWinsOverTheAboutPanel() {
        XCTAssertEqual(FeedParser.continuationToken(from: channelTab), "GRID_TOKEN")
    }

    /// The walk is a stack over unordered dictionary values, so "first found"
    /// is not stable between runs. Repeating it makes an order-dependent
    /// implementation fail rather than pass four times out of five.
    func testTheChoiceIsNotAnAccidentOfDictionaryOrder() {
        for _ in 0..<200 {
            XCTAssertEqual(FeedParser.continuationToken(from: channelTab), "GRID_TOKEN")
        }
    }

    /// Continuation responses have no grid to look inside — the items arrive as
    /// a bare append action with the next token trailing them. Search is the
    /// same shape. Both have to keep working through the fallback.
    func testGridlessResponsesStillPage() {
        let appendAction: [String: Any] = [
            "onResponseReceivedActions": [[
                "appendContinuationItemsAction": [
                    "continuationItems": [
                        ["richItemRenderer": ["content": [
                            "videoRenderer": [
                                "videoId": "bbbbbbbbbbb",
                                "title": ["simpleText": "Next page"],
                            ],
                        ]]],
                        ["continuationItemRenderer": [
                            "continuationEndpoint": [
                                "continuationCommand": ["token": "PAGE_3"],
                            ],
                        ]],
                    ],
                ],
            ]],
        ]

        XCTAssertEqual(FeedParser.continuationToken(from: appendAction), "PAGE_3")
    }

    func testNoContinuationIsNotAnError() {
        let lastPage: [String: Any] = [
            "contents": ["richGridRenderer": ["contents": [[
                "richItemRenderer": ["content": [
                    "videoRenderer": ["videoId": "ccccccccccc", "title": ["simpleText": "Last"]],
                ]],
            ]]]],
        ]

        XCTAssertNil(FeedParser.continuationToken(from: lastPage))
    }
}
