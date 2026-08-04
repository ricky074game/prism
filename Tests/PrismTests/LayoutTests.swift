import XCTest
@testable import Prism

/// Tests for the layout decisions.
///
/// Screenshots catch how a screen looks on the one device CI happens to boot.
/// These pin the rules that decide *which* layout it gets, at the sizes nobody
/// takes a screenshot of — Slide Over, a Split View half, a resized Stage
/// Manager window. Every one of those is a real width the app can be handed.
final class LayoutTests: XCTestCase {

    // Real point sizes, portrait unless noted.
    private let iPhone = PrismLayout(width: 393, height: 852)
    private let iPhoneLandscape = PrismLayout(width: 852, height: 393)
    private let iPadPortrait = PrismLayout(width: 1032, height: 1376)
    private let iPadLandscape = PrismLayout(width: 1376, height: 1032)
    private let slideOver = PrismLayout(width: 320, height: 1180)
    private let splitHalf = PrismLayout(width: 507, height: 1024)

    // MARK: Which chrome

    func testPhoneKeepsTheBottomBar() {
        XCTAssertFalse(iPhone.isWide)
        XCTAssertEqual(iPhone.columns, 1)
        XCTAssertEqual(iPhone.gutter, Metrics.gutter)
    }

    func testIPadGetsTheRail() {
        XCTAssertTrue(iPadPortrait.isWide)
        XCTAssertTrue(iPadLandscape.isWide)
    }

    /// The whole reason this keys on size rather than on `userInterfaceIdiom`:
    /// a rail crushed into a 320pt Slide Over panel is the classic iPad port
    /// mistake, and the idiom says "iPad" the entire time.
    func testNarrowMultitaskingWindowsGetThePhoneLayout() {
        XCTAssertFalse(slideOver.isWide)
        XCTAssertEqual(slideOver.columns, 1)

        XCTAssertFalse(splitHalf.isWide)
        XCTAssertEqual(splitHalf.columns, 1)
    }

    // MARK: Columns

    func testColumnsAreMeasuredAgainstContentNotTheWindow() {
        // The rail's 92pt is not available to the grid, and counting it would
        // over-count by most of a cell.
        XCTAssertEqual(iPadPortrait.contentWidth, 1032 - SideRail.width)
        XCTAssertEqual(iPhone.contentWidth, 393)
    }

    func testColumnCountsStayInRange() {
        XCTAssertEqual(iPadPortrait.columns, 2)
        XCTAssertEqual(iPadLandscape.columns, 3)

        // Never more than four, however wide the window gets.
        XCTAssertEqual(PrismLayout(width: 4000, height: 1200).columns, 4)
        // And never fewer than two once the rail is showing, or the grid would
        // be a single column beside a navigation rail.
        XCTAssertEqual(PrismLayout(width: 700, height: 1000).columns, 2)
    }

    // MARK: Watch screen

    func testUpNextGetsAColumnOnlyWhereItFits() {
        XCTAssertNotNil(iPadLandscape.watchSidebar)

        // Portrait iPad has the width but not the shape: a sidebar there would
        // squeeze the video into a third of a tall window.
        XCTAssertNil(iPadPortrait.watchSidebar)
        // A landscape phone is the right shape and nowhere near wide enough.
        XCTAssertNil(iPhoneLandscape.watchSidebar)
        XCTAssertNil(iPhone.watchSidebar)
    }

    func testSidebarLeavesTheVideoTheMajorityOfTheWindow() throws {
        let sidebar = try XCTUnwrap(iPadLandscape.watchSidebar)
        XCTAssertLessThan(sidebar, iPadLandscape.width / 2)
        XCTAssertGreaterThanOrEqual(sidebar, 300)
    }

    // MARK: Hero

    func testHeroWidensOnIPad() {
        XCTAssertEqual(iPhone.heroAspect, 16 / 9, accuracy: 0.001)
        XCTAssertGreaterThan(iPadLandscape.heroAspect, 16 / 9)

        // The point of widening it: a 16:9 hero at this width would be taller
        // than the window it has to share with the rest of the feed.
        let wide = iPadLandscape
        let heroHeight = wide.contentWidth / wide.heroAspect
        XCTAssertLessThan(heroHeight, wide.height * 0.6)
    }

    // MARK: Chrome insets

    func testScrollViewsClearWhicheverChromeIsShowing() {
        // A phone has a bar to clear.
        XCTAssertGreaterThan(iPhone.bottomChrome, TabBar.height)
        // An iPad doesn't, and padding for one would leave a dead strip.
        XCTAssertLessThan(iPadLandscape.bottomChrome, TabBar.height)
    }
}
