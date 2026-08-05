import SwiftUI

@main
struct PrismApp: App {
    @State private var router = Router()
    @State private var player = PlayerEngine()
    @State private var settings = Settings()
    /// Owned here, not by the watch screen. Collapsing to the mini player
    /// destroys that screen, and with it the controller and the layer PiP is
    /// attached to — which is why swiping down used to end any chance of
    /// Picture in Picture.
    @State private var pip = PictureInPictureController()

    init() {
        FontLoader.register()
        // Sampled here, on the main actor, so the off-actor image decoder never
        // has to touch UIScreen.
        ImageLoader.screenScale = UIScreen.main.scale
        UIScrollView.appearance().keyboardDismissMode = .interactive
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(router)
                .environment(player)
                .environment(settings)
                .environment(pip)
                .preferredColorScheme(.dark)
                .tint(Palette.refract)
        }
    }
}

/// A channel destination on a navigation stack.
struct ChannelRoute: Hashable, Sendable {
    let id: String
    let name: String
}

/// Navigation state.
///
/// The watch screen is not a pushed destination — it's an overlay that can
/// collapse to a mini player while the tabs stay interactive underneath, so it
/// lives here rather than in a `NavigationPath`.
@MainActor
@Observable
final class Router {
    var tab: Tab = .home
    var paths: [Tab: NavigationPath] = [:]

    var nowPlaying: Video?
    var isWatchExpanded = false

    enum Tab: String, CaseIterable, Identifiable {
        case home, shorts, subscriptions, library

        var id: String { rawValue }

        var title: String {
            switch self {
            case .home: "Home"
            case .shorts: "Shorts"
            case .subscriptions: "Subscriptions"
            case .library: "Library"
            }
        }

        var icon: String {
            switch self {
            case .home: "house"
            case .shorts: "play.square.stack"
            case .subscriptions: "square.stack.3d.up"
            case .library: "books.vertical"
            }
        }

        var selectedIcon: String { icon + ".fill" }
    }

    func open(_ video: Video) {
        nowPlaying = video
        isWatchExpanded = true
    }

    /// Pushes a channel onto the current tab's stack.
    ///
    /// Collapses the watch screen first — it's an overlay above the navigation
    /// stack, so pushing underneath it would look like nothing happened.
    func openChannel(id: String, name: String = "") {
        guard !id.isEmpty else { return }
        if isWatchExpanded { isWatchExpanded = false }

        var path = paths[tab] ?? NavigationPath()
        path.append(ChannelRoute(id: id, name: name))
        paths[tab] = path
    }

    /// Puts the app on a given screen at launch, for screenshot runs.
    func applyLaunchScreen() {
        guard let screen = DemoData.screen else { return }
        switch screen {
        case "shorts": tab = .shorts
        case "subscriptions": tab = .subscriptions
        case "library": tab = .library
        case "watch", "scrubber":
            tab = .home
            if let first = DemoData.videos.first { open(first) }
        case "channel", "channel-shorts":
            tab = .home
            paths[.home] = NavigationPath([ChannelRoute(id: "UCdemo", name: "Practical Engineering")])
        case "posts":
            tab = .home
            paths[.home] = NavigationPath([ChannelRoute(id: "UCdemo", name: "Practical Engineering")])
        default: tab = .home
        }
    }

    func closeWatch() {
        isWatchExpanded = false
        nowPlaying = nil
    }

    func path(for tab: Tab) -> Binding<NavigationPath> {
        Binding(
            get: { self.paths[tab] ?? NavigationPath() },
            set: { self.paths[tab] = $0 }
        )
    }
}
