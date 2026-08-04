import SwiftUI

struct RootView: View {
    @Environment(Router.self) private var router
    @Environment(Settings.self) private var settings

    /// Screenshot runs open Search and Settings directly, since both are
    /// presented modally and can't be reached by setting a tab.
    @State private var showSearchForScreenshot = DemoData.screen == "search"
    @State private var showSettingsForScreenshot = DemoData.screen == "settings"

    var body: some View {
        @Bindable var router = router

        // The whole app's layout is decided once, here, from the size the app
        // actually has. Every screen reads it out of the environment rather
        // than measuring for itself, so a Split View resize moves all of them
        // together and there's one place to change a breakpoint.
        GeometryReader { geo in
            let layout = PrismLayout(width: geo.size.width, height: geo.size.height)

            Group {
                if layout.isWide {
                    railLayout(router: $router.tab)
                } else {
                    barLayout(router: $router.tab)
                }
            }
            .environment(\.prismLayout, layout)
        }
        .overlay {
            if router.isWatchExpanded, let video = router.nowPlaying {
                WatchScreen(video: video)
                    .transition(.move(edge: .bottom))
                    .zIndex(10)
            }
        }
        .motion(Motion.hero, value: router.isWatchExpanded)
        .motion(Motion.standard, value: router.nowPlaying?.id)
        .task { router.applyLaunchScreen() }
        .fullScreenCover(isPresented: $showSearchForScreenshot) { SearchScreen() }
        .sheet(isPresented: $showSettingsForScreenshot) {
            NavigationStack { SettingsScreen() }
        }
    }

    // MARK: Chrome

    private func barLayout(router tab: Binding<Router.Tab>) -> some View {
        ZStack(alignment: .bottom) {
            Palette.ink.ignoresSafeArea()

            content

            // The mini player docks directly above the tab bar and is the
            // persistent handle back into whatever is playing.
            if router.nowPlaying != nil && !router.isWatchExpanded {
                MiniPlayerBar()
                    .padding(.bottom, TabBar.height + Metrics.Space.xs)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(2)
            }

            TabBar(selection: tab, tabs: visibleTabs)
                .zIndex(3)
        }
    }

    private func railLayout(router tab: Binding<Router.Tab>) -> some View {
        HStack(spacing: 0) {
            SideRail(selection: tab, tabs: visibleTabs)

            ZStack(alignment: .bottomTrailing) {
                Palette.ink.ignoresSafeArea()

                content

                // Full-width across an iPad would make the mini player a
                // letterbox strip; it stays a card in the corner instead.
                if router.nowPlaying != nil && !router.isWatchExpanded {
                    MiniPlayerBar()
                        .frame(maxWidth: 460)
                        .padding(Metrics.Space.lg)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .zIndex(2)
                }
            }
        }
    }

    private var visibleTabs: [Router.Tab] {
        settings.showShorts ? Router.Tab.allCases : Router.Tab.allCases.filter { $0 != .shorts }
    }

    @ViewBuilder
    private var content: some View {
        ZStack {
            ForEach(visibleTabs) { tab in
                // All tabs stay mounted so switching preserves scroll position
                // and in-flight loads. `opacity` rather than a conditional keeps
                // the view identity stable.
                NavigationStack(path: router.path(for: tab)) {
                    screen(for: tab)
                        .navigationDestination(for: ChannelRoute.self) { route in
                            ChannelScreen(channelID: route.id, channelName: route.name)
                        }
                }
                .opacity(router.tab == tab ? 1 : 0)
                .allowsHitTesting(router.tab == tab)
            }
        }
    }

    @ViewBuilder
    private func screen(for tab: Router.Tab) -> some View {
        switch tab {
        case .home: HomeScreen()
        case .shorts: ShortsScreen()
        case .subscriptions: SubscriptionsScreen()
        case .library: LibraryScreen()
        }
    }
}

/// The bottom bar.
///
/// Built by hand rather than with `TabView` so the selection indicator can be a
/// single shared shape that slides between items — a `matchedGeometryEffect`
/// across a `TabView`'s own bar isn't possible.
struct TabBar: View {
    @Binding var selection: Router.Tab
    let tabs: [Router.Tab]

    static let height: CGFloat = 58

    @Namespace private var indicator

    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs) { tab in
                item(tab)
            }
        }
        .frame(height: Self.height)
        .background {
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                Rectangle().fill(Palette.ink.opacity(0.55))
            }
            .ignoresSafeArea(edges: .bottom)
        }
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Palette.line)
                .frame(height: 0.5)
        }
    }

    private func item(_ tab: Router.Tab) -> some View {
        let isSelected = selection == tab

        return Button {
            guard selection != tab else { return }
            selection = tab
            Haptics.selection()
        } label: {
            VStack(spacing: 4) {
                ZStack {
                    if isSelected {
                        Capsule()
                            .fill(Palette.refract.opacity(0.16))
                            .matchedGeometryEffect(id: "tabIndicator", in: indicator)
                            .frame(width: 46, height: 28)
                    }
                    Image(systemName: isSelected ? tab.selectedIcon : tab.icon)
                        .font(.system(size: 17, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? Palette.refract : Palette.textTertiary)
                        .symbolEffect(.bounce, value: isSelected)
                }
                .frame(height: 28)

                Text(tab.title)
                    .font(Type.labelSmall)
                    .foregroundStyle(isSelected ? Palette.textPrimary : Palette.textTertiary)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .motion(Motion.quick, value: isSelected)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }
}
