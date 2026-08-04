import SwiftUI

@MainActor
@Observable
final class LibraryModel {
    private(set) var liked: [Video] = []
    private(set) var watchLater: [Video] = []
    private(set) var history: [Video] = []
    private(set) var playlists: [Playlist] = []
    private(set) var trending: [Video] = []
    private(set) var isLoading = false

    func load(signedIn: Bool) async {
        if DemoData.isEnabled {
            history = DemoData.videos
            liked = Array(DemoData.videos.shuffledStable(seed: 3).prefix(4))
            watchLater = Array(DemoData.videos.reversed().prefix(3))
            playlists = DemoData.playlists
            return
        }

        isLoading = true
        defer { isLoading = false }

        // Not FEtrending — YouTube retired the Trending tab and that browse id
        // now returns HTTP 400. The discovery feed gives the screen something
        // real to show while signed out.
        async let discoverTask = try? FeedRepository.shared.discoveryFeed()

        if signedIn {
            // These surfaces only return the user's own data when the request
            // carries account authentication; anonymously they come back empty.
            async let likedTask = try? PlaylistService.shared.contents(playlistID: "VLLL")
            async let laterTask = try? PlaylistService.shared.contents(playlistID: "VLWL")
            async let historyTask = try? PlaylistService.shared.contents(playlistID: "FEhistory")

            liked = await likedTask?.videos ?? []
            watchLater = await laterTask?.videos ?? []
            history = await historyTask?.videos ?? []
        }

        trending = await discoverTask ?? []
    }
}

struct LibraryScreen: View {
    @Environment(Router.self) private var router
    @Environment(\.prismLayout) private var layout
    @State private var model = LibraryModel()
    @State private var auth = GoogleAuth.shared
    @State private var session = AccountSession.shared

    private var signedIn: Bool { session.isSignedIn || auth.isSignedIn }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Metrics.Space.xxl) {
                if !signedIn && !DemoData.isEnabled {
                    signedOutNote
                }

                shelf("Continue watching", model.history, icon: "clock.arrow.circlepath")
                shelf("Liked", model.liked, icon: "hand.thumbsup.fill")
                shelf("Watch later", model.watchLater, icon: "bookmark.fill")

                if !model.playlists.isEmpty {
                    playlistShelf
                }

                shelf("Discover", model.trending, icon: "sparkles")

                Color.clear.frame(height: layout.bottomInset)
            }
            .padding(.top, Metrics.Space.sm)
            .pageWidth(layout)
        }
        .scrollIndicators(.hidden)
        .background(Palette.ink)
        .safeAreaInset(edge: .top, spacing: 0) { ScreenHeader(title: "Library") }
        .task { await model.load(signedIn: signedIn) }
        .onChange(of: signedIn) { _, now in
            if now { Task { await model.load(signedIn: true) } }
        }
    }

    private var signedOutNote: some View {
        HStack(spacing: Metrics.Space.md) {
            Image(systemName: "person.crop.circle")
                .font(.system(size: 18))
                .foregroundStyle(Palette.textTertiary)

            VStack(alignment: .leading, spacing: 2) {
                Text("Sign in for your library")
                    .font(Type.metaEmphasis)
                    .foregroundStyle(Palette.textPrimary)
                Text("History, liked videos and Watch Later live on your account.")
                    .font(Type.labelSmall)
                    .foregroundStyle(Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(Metrics.Space.lg)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Metrics.Radius.card, style: .continuous))
        .padding(.horizontal, layout.gutter)
    }

    /// A horizontally scrolling row. Empty shelves are omitted entirely rather
    /// than shown as a header over nothing.
    @ViewBuilder
    private func shelf(_ title: String, _ videos: [Video], icon: String) -> some View {
        if !videos.isEmpty {
            VStack(alignment: .leading, spacing: Metrics.Space.md) {
                Label(title, systemImage: icon)
                    .font(Type.title(15))
                    .foregroundStyle(Palette.textPrimary)
                    .padding(.horizontal, layout.gutter)

                ScrollView(.horizontal) {
                    HStack(spacing: Metrics.Space.md) {
                        ForEach(videos) { video in
                            ShelfCard(video: video) { router.open(video) }
                        }
                    }
                    .padding(.horizontal, layout.gutter)
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    private var playlistShelf: some View {
        VStack(alignment: .leading, spacing: Metrics.Space.md) {
            Label("Playlists", systemImage: "list.bullet.rectangle")
                .font(Type.title(15))
                .foregroundStyle(Palette.textPrimary)
                .padding(.horizontal, layout.gutter)

            ScrollView(.horizontal) {
                HStack(spacing: Metrics.Space.md) {
                    ForEach(model.playlists) { playlist in
                        NavigationLink {
                            PlaylistScreen(playlist: playlist)
                        } label: {
                            PlaylistCard(playlist: playlist)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, layout.gutter)
            }
            .scrollIndicators(.hidden)
        }
    }
}

struct ShelfCard: View {
    let video: Video
    var onTap: () -> Void

    @Environment(\.prismLayout) private var layout

    /// Shelf cards grow on iPad — 196pt cards on a 1366pt row read as a
    /// phone screenshot pasted into the middle of a desk.
    private var cardWidth: CGFloat { layout.isWide ? 264 : 196 }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: Metrics.Space.sm) {
                Color.clear
                    .frame(width: cardWidth, height: cardWidth * 9 / 16)
                    .overlay {
                        RemoteImage(url: video.thumbnailURL, targetSize: CGSize(width: 400, height: 225)) {
                            ShimmerPlaceholder()
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: Metrics.Radius.md, style: .continuous))
                    .overlay(alignment: .bottomTrailing) {
                        if video.duration > 0 {
                            Text(video.durationText)
                                .font(Type.readoutSmall)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 5))
                                .padding(5)
                        }
                    }

                Text(video.title)
                    .font(Type.labelSmall)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(width: cardWidth, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)

                Text(video.channelName)
                    .font(Type.readoutSmall)
                    .foregroundStyle(Palette.textTertiary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(PressableStyle(isPressed: .constant(false), scale: 0.97))
        .accessibilityLabel("\(video.title), \(video.channelName)")
    }
}

struct PlaylistCard: View {
    let playlist: Playlist

    @Environment(\.prismLayout) private var layout

    /// Matched to `ShelfCard` so the two sit on the same rhythm.
    private var cardWidth: CGFloat { layout.isWide ? 264 : 196 }

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.Space.sm) {
            ZStack {
                RoundedRectangle(cornerRadius: Metrics.Radius.md, style: .continuous)
                    .fill(Palette.surfaceRaised)
                    .frame(width: cardWidth, height: cardWidth * 9 / 16)

                if let url = playlist.thumbnailURL {
                    RemoteImage(url: url, targetSize: CGSize(width: 400, height: 225)) { Color.clear }
                        .frame(width: cardWidth, height: cardWidth * 9 / 16)
                        .clipShape(RoundedRectangle(cornerRadius: Metrics.Radius.md, style: .continuous))
                }

                Image(systemName: "list.bullet")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Palette.textSecondary)
            }

            Text(playlist.title)
                .font(Type.labelSmall)
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(width: cardWidth, alignment: .leading)

            if !playlist.videoCountText.isEmpty {
                Text(playlist.videoCountText)
                    .font(Type.readoutSmall)
                    .foregroundStyle(Palette.textTertiary)
            }
        }
    }
}

/// One playlist's contents.
struct PlaylistScreen: View {
    let playlist: Playlist

    @Environment(Router.self) private var router
    @State private var videos: [Video] = []
    @State private var title = ""
    @State private var isLoading = true

    var body: some View {
        ScrollView {
            LazyVStack(spacing: Metrics.Space.lg) {
                ForEach(Array(videos.enumerated()), id: \.element.id) { index, video in
                    HStack(spacing: Metrics.Space.md) {
                        Text("\(index + 1)")
                            .font(Type.readout)
                            .foregroundStyle(Palette.textTertiary)
                            .frame(width: 22, alignment: .trailing)

                        VideoRow(video: video) { router.open(video) }
                    }
                }

                if isLoading {
                    ProgressView().tint(Palette.refract).padding(Metrics.Space.xxl)
                }

                Color.clear.frame(height: TabBar.height + Metrics.Space.xxl)
            }
            .padding(Metrics.gutter)
        }
        .scrollIndicators(.hidden)
        .background(Palette.ink.ignoresSafeArea())
        .navigationTitle(title.isEmpty ? playlist.title : title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            defer { isLoading = false }
            guard let contents = try? await PlaylistService.shared.contents(playlistID: playlist.id) else { return }
            title = contents.title
            videos = contents.videos
        }
    }
}

extension Array {
    /// Deterministic shuffle — screenshots must not change between runs.
    func shuffledStable(seed: Int) -> [Element] {
        enumerated()
            .sorted { ($0.offset &* 31 &+ seed) % 7 < ($1.offset &* 31 &+ seed) % 7 }
            .map(\.element)
    }
}
