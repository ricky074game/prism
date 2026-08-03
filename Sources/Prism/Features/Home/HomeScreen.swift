import SwiftUI

@MainActor
@Observable
final class HomeModel {
    private(set) var videos: [Video] = []
    private(set) var isLoading = false
    private(set) var error: String?
    private var continuation: String?
    private var isPaging = false

    func load(refresh: Bool = false) async {
        guard !isLoading else { return }
        isLoading = videos.isEmpty
        error = nil
        do {
            let page = try await FeedRepository.shared.feed(.home, refresh: refresh)
            videos = page.videos
            continuation = page.continuation
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? "Couldn't load your feed."
        }
        isLoading = false
    }

    /// Called when the feed is a few cells from the end, so the next page is
    /// already in place by the time the user reaches it.
    func loadMoreIfNeeded(currentItem: Video) async {
        guard let continuation, !isPaging,
              let index = videos.firstIndex(of: currentItem),
              index >= videos.count - 4
        else { return }

        isPaging = true
        defer { isPaging = false }

        if let page = try? await FeedRepository.shared.more(.home, continuation: continuation) {
            videos.append(contentsOf: page.videos)
            self.continuation = page.continuation
        }
    }
}

struct HomeScreen: View {
    @Environment(Router.self) private var router
    @State private var model = HomeModel()
    @State private var glow = GlowSource()
    @State private var hasAppeared = false

    var body: some View {
        ScrollView {
            LazyVStack(spacing: Metrics.Space.xl) {
                if let hero = model.videos.first {
                    HeroCard(video: hero, glow: glow) { router.open(hero) }
                        .padding(.horizontal, Metrics.gutter)
                }

                ForEach(Array(model.videos.dropFirst().enumerated()), id: \.element.id) { index, video in
                    VideoCard(video: video) { router.open(video) }
                        .padding(.horizontal, Metrics.gutter)
                        .task { await model.loadMoreIfNeeded(currentItem: video) }
                        .opacity(hasAppeared ? 1 : 0)
                        .offset(y: hasAppeared ? 0 : 14)
                        .animation(
                            Motion.standard.delay(Motion.stagger(index)),
                            value: hasAppeared
                        )
                }

                if model.isLoading { loadingState }
                if let error = model.error, model.videos.isEmpty { errorState(error) }

                Color.clear.frame(height: TabBar.height + Metrics.Space.xxl)
            }
            .padding(.top, Metrics.Space.sm)
        }
        .scrollIndicators(.hidden)
        .background(Palette.ink)
        .safeAreaInset(edge: .top, spacing: 0) { PrismHeader() }
        .refreshable { await model.load(refresh: true) }
        .task {
            guard model.videos.isEmpty else { return }
            await model.load()
            glow.load(model.videos.first?.thumbnailURL)
            withAnimation { hasAppeared = true }
        }
    }

    private var loadingState: some View {
        VStack(spacing: Metrics.Space.xl) {
            ForEach(0..<3, id: \.self) { _ in
                VStack(alignment: .leading, spacing: Metrics.Space.md) {
                    ShimmerPlaceholder()
                        .aspectRatio(16 / 9, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: Metrics.Radius.card, style: .continuous))
                    HStack(spacing: Metrics.Space.md) {
                        Circle().fill(Palette.surfaceRaised).frame(width: 34, height: 34)
                        VStack(alignment: .leading, spacing: 6) {
                            RoundedRectangle(cornerRadius: 4).fill(Palette.surfaceRaised).frame(height: 12)
                            RoundedRectangle(cornerRadius: 4).fill(Palette.surfaceRaised)
                                .frame(width: 140, height: 10)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, Metrics.gutter)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: Metrics.Space.md) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(Palette.textTertiary)
            Text(message)
                .font(Type.body)
                .foregroundStyle(Palette.textSecondary)
                .multilineTextAlignment(.center)
            Button("Try again") { Task { await model.load(refresh: true) } }
                .font(Type.label)
                .foregroundStyle(Palette.refract)
                .padding(.top, Metrics.Space.xs)
        }
        .padding(Metrics.Space.huge)
    }
}

// MARK: - Header

/// The wordmark sets the app's voice: Archivo Expanded, wide and confident,
/// with the refraction gradient applied to the mark itself rather than to any
/// surrounding chrome.
struct PrismHeader: View {
    @Environment(Router.self) private var router
    @State private var showSearch = false

    var body: some View {
        HStack(spacing: Metrics.Space.md) {
            HStack(spacing: 7) {
                PrismMark()
                    .frame(width: 19, height: 19)

                Text("PRISM")
                    .font(Type.display(17))
                    .tracking(1.6)
                    .foregroundStyle(Palette.textPrimary)
            }

            Spacer()

            Button { showSearch = true } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Palette.textPrimary)
                    .frame(width: 38, height: 38)
                    .background(Palette.surface, in: Circle())
            }
            .accessibilityLabel("Search")

            NavigationLink {
                SettingsScreen()
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Palette.textPrimary)
                    .frame(width: 38, height: 38)
                    .background(Palette.surface, in: Circle())
            }
            .accessibilityLabel("Settings")
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.vertical, Metrics.Space.sm)
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(Palette.ink.opacity(0.5))
                .ignoresSafeArea(edges: .top)
        }
        .fullScreenCover(isPresented: $showSearch) { SearchScreen() }
    }
}

/// The app mark: a triangle splitting a beam.
///
/// Drawn rather than shipped as an asset so it stays crisp at any size and can
/// take the gradient directly.
struct PrismMark: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            ZStack {
                // Incoming beam.
                Path { p in
                    p.move(to: CGPoint(x: 0, y: h * 0.52))
                    p.addLine(to: CGPoint(x: w * 0.42, y: h * 0.52))
                }
                .stroke(Palette.textSecondary, style: StrokeStyle(lineWidth: 1.4, lineCap: .round))

                // The prism.
                Path { p in
                    p.move(to: CGPoint(x: w * 0.46, y: h * 0.1))
                    p.addLine(to: CGPoint(x: w * 0.96, y: h * 0.9))
                    p.addLine(to: CGPoint(x: w * 0.2, y: h * 0.9))
                    p.closeSubpath()
                }
                .stroke(
                    LinearGradient(colors: [Palette.refract, Palette.disperse],
                                   startPoint: .top, endPoint: .bottom),
                    style: StrokeStyle(lineWidth: 1.6, lineJoin: .round)
                )
            }
        }
    }
}
