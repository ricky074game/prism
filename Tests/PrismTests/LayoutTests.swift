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
    private let iPhoneMaxLandscape = PrismLayout(width: 956, height: 440)
    private let iPadMini = PrismLayout(width: 744, height: 1133)
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
        // The smallest iPad still has to qualify, or the rail is iPad-Pro-only.
        XCTAssertTrue(iPadMini.isWide)
    }

    /// A landscape iPhone 16 Pro is 852pt wide — wider than an iPad mini in
    /// portrait. A width-only threshold hands it the rail, the grid and the
    /// up-next sidebar in a window 393pt tall. The short edge is what actually
    /// separates the families.
    func testLandscapePhonesAreNotIPads() {
        XCTAssertFalse(iPhoneLandscape.isWide)
        XCTAssertEqual(iPhoneLandscape.columns, 1)
        XCTAssertNil(iPhoneLandscape.watchSidebar)

        // The widest phone there is, in its widest orientation.
        XCTAssertGreaterThan(iPhoneMaxLandscape.width, iPadMini.width)
        XCTAssertFalse(iPhoneMaxLandscape.isWide)
        XCTAssertEqual(iPhoneMaxLandscape.columns, 1)
        XCTAssertNil(iPhoneMaxLandscape.watchSidebar)
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

        // A window with the shape for a rail but not the room for two cells
        // gets one honest column rather than two 290pt ones.
        let narrowWithRail = PrismLayout(width: 700, height: 1000)
        XCTAssertTrue(narrowWithRail.isWide)
        XCTAssertEqual(narrowWithRail.columns, 1)
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
