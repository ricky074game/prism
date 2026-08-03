import SwiftUI

/// Subscriptions.
///
/// Without a signed-in session YouTube has nothing personal to return, so this
/// screen is honest about that and offers the one action that fixes it, rather
/// than showing a generic feed pretending to be yours.
struct SubscriptionsScreen: View {
    @Environment(Router.self) private var router
    @State private var videos: [Video] = []
    @State private var isLoading = true

    var body: some View {
        ScrollView {
            LazyVStack(spacing: Metrics.Space.xl) {
                if !isLoading && videos.isEmpty {
                    signedOutState
                        .padding(.top, Metrics.Space.huge)
                }

                ForEach(videos) { video in
                    VideoCard(video: video) { router.open(video) }
                        .padding(.horizontal, Metrics.gutter)
                }

                Color.clear.frame(height: TabBar.height + Metrics.Space.xxl)
            }
            .padding(.top, Metrics.Space.sm)
        }
        .scrollIndicators(.hidden)
        .background(Palette.ink)
        .safeAreaInset(edge: .top, spacing: 0) { ScreenHeader(title: "Subscriptions") }
        .task {
            if let page = try? await FeedRepository.shared.feed(.subscriptions) {
                videos = page.videos
            }
            isLoading = false
        }
    }

    private var signedOutState: some View {
        VStack(spacing: Metrics.Space.lg) {
            PrismMark().frame(width: 40, height: 40)

            VStack(spacing: Metrics.Space.sm) {
                Text("Sign in to see your subscriptions")
                    .font(Type.title(17))
                    .foregroundStyle(Palette.textPrimary)
                    .multilineTextAlignment(.center)

                Text("Prism reads your subscription list from your Google account. Nothing is stored anywhere but this device.")
                    .font(Type.meta)
                    .foregroundStyle(Palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                // Wired up once the OAuth client ID is configured.
            } label: {
                Text("Sign in with Google")
                    .font(Type.label)
                    .foregroundStyle(Palette.ink)
                    .padding(.horizontal, Metrics.Space.xl)
                    .padding(.vertical, Metrics.Space.md)
                    .background(Palette.refractGradient, in: Capsule())
            }
        }
        .padding(.horizontal, Metrics.Space.xxl)
    }
}

struct LibraryScreen: View {
    @Environment(Router.self) private var router
    @State private var trending: [Video] = []

    var body: some View {
        ScrollView {
            LazyVStack(spacing: Metrics.Space.xl) {
                ForEach(trending) { video in
                    VideoCard(video: video) { router.open(video) }
                        .padding(.horizontal, Metrics.gutter)
                }
                Color.clear.frame(height: TabBar.height + Metrics.Space.xxl)
            }
            .padding(.top, Metrics.Space.sm)
        }
        .scrollIndicators(.hidden)
        .background(Palette.ink)
        .safeAreaInset(edge: .top, spacing: 0) { ScreenHeader(title: "Trending") }
        .task {
            if let page = try? await FeedRepository.shared.feed(.trending) {
                trending = page.videos
            }
        }
    }
}

struct ScreenHeader: View {
    let title: String

    var body: some View {
        HStack {
            Text(title)
                .font(Type.title(22))
                .foregroundStyle(Palette.textPrimary)
            Spacer()
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.vertical, Metrics.Space.md)
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(Palette.ink.opacity(0.5))
                .ignoresSafeArea(edges: .top)
        }
    }
}
