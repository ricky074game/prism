import SwiftUI

/// How much room the app has, and what to do with it.
///
/// Keyed on the size the app *actually occupies* rather than on the device
/// idiom. A Slide Over panel and a third-width Split View are both 320-odd
/// points wide, and the phone layout is the correct layout at that width no
/// matter what hardware it's running on. Reading `UIDevice.current.userInterfaceIdiom`
/// instead is the usual way iPad ports end up with a side rail crushed into a
/// 320pt column.
struct PrismLayout: Equatable {
    var width: CGFloat = 390
    var height: CGFloat = 844

    /// The point where a side rail beats a bottom bar.
    ///
    /// Both dimensions, not just the width. A landscape iPhone 16 Pro is 852pt
    /// wide — wider than an iPad mini in portrait — so a width-only threshold
    /// hands a phone the rail, the grid and the sidebar in a window 393pt tall.
    /// What separates the two families is the *short* edge: no iPhone has more
    /// than 440pt of it in any orientation, and no iPad has less than 744.
    var isWide: Bool { min(width, height) >= 600 && max(width, height) >= 700 }

    var isLandscape: Bool { width > height }

    /// What's left for content once the rail has taken its column. Measuring
    /// columns against the full window width would consistently over-count by
    /// most of a cell on narrower iPads.
    var contentWidth: CGFloat { isWide ? width - SideRail.width : width }

    /// Feed columns.
    ///
    /// Derived from a target cell width rather than from device breakpoints, so
    /// every window size in between — Split View halves, Stage Manager, a
    /// resized window — lands somewhere sensible instead of on the nearest
    /// hard-coded case.
    /// One column is a legitimate answer even with a rail showing: a narrow
    /// Split View window has the shape for a rail but not the room for two
    /// cells, and 290pt cards are worse than one honest column.
    var columns: Int {
        guard isWide else { return 1 }
        return max(1, min(4, Int(contentWidth / 400)))
    }

    /// Screen gutter. Wider on iPad, where the phone's 16pt reads as no margin
    /// at all.
    var gutter: CGFloat { isWide ? 28 : Metrics.gutter }

    var gridColumns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(), spacing: gutter, alignment: .top),
            count: columns
        )
    }

    /// Content is capped and centred on very wide windows. Line lengths past
    /// this are unreadable and a four-across grid at 1600pt gives cells nobody
    /// asked for.
    var maxContentWidth: CGFloat { isWide ? 1500 : .infinity }

    /// The hero is a masthead, not a wall: at 1400pt a 16:9 card would be 790
    /// tall and fill the whole screen on its own, so it widens out instead.
    var heroAspect: CGFloat { isWide ? 2.4 : 16 / 9 }

    /// Width of the watch screen's "Up next" sidebar, or nil when the window is
    /// the wrong shape or size for one.
    ///
    /// The 1000pt floor is what's left over: take a 300pt column out of
    /// anything narrower and the video gets less room than it would have had
    /// stacked.
    var watchSidebar: CGFloat? {
        guard isWide, isLandscape, width >= 1000 else { return nil }
        return min(400, max(300, width * 0.28))
    }

    /// Bottom padding scroll views need to clear the chrome. With a side rail
    /// there is no bottom bar to clear.
    var bottomChrome: CGFloat {
        isWide ? Metrics.Space.xxl : TabBar.height + Metrics.Space.xxl
    }
}

private struct PrismLayoutKey: EnvironmentKey {
    static let defaultValue = PrismLayout()
}

extension EnvironmentValues {
    var prismLayout: PrismLayout {
        get { self[PrismLayoutKey.self] }
        set { self[PrismLayoutKey.self] = newValue }
    }
}

extension View {
    /// Caps and centres page content on wide windows, and is a no-op elsewhere.
    func pageWidth(_ layout: PrismLayout) -> some View {
        frame(maxWidth: layout.maxContentWidth)
            .frame(maxWidth: .infinity)
    }
}
