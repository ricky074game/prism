import SwiftUI

@MainActor
@Observable
final class ChannelModel {
    private(set) var detail: ChannelDetail?
    private(set) var videos: [Video] = []
    private(set) var posts: [CommunityPost] = []
    private(set) var playlists: [Playlist] = []
    private(set) var isLoading = true
    private(set) var error: String?

    var tab: ChannelService.Tab = .videos

    /// Exposed so the shorts player can carry on paging from where the channel
    /// screen left off instead of starting the creator's list again.
    private(set) var continuation: String?

    private var isPaging = false
    private var loaded: Set<ChannelService.Tab> = []

    func load(channelID: String) async {
        isLoading = true
        error = nil
        defer { isLoading = false }

        if DemoData.isEnabled {
            detail = DemoData.channel
            videos = DemoData.videos
            posts = DemoData.posts
            playlists = DemoData.playlists
            loaded = Set(ChannelService.Tab.allCases)
            return
        }

        do {
            let (detail, contents) = try await ChannelService.shared.load(channelID: channelID, tab: tab)
            self.detail = detail
            apply(contents)
            loaded.insert(tab)
        } catch {
            self.error = "Couldn't load this channel."
        }
    }

    func select(_ new: ChannelService.Tab, channelID: String) async {
        guard new != tab else { return }
        tab = new
        continuation = nil

        // Each tab keeps what it already fetched, so flicking between them
        // doesn't re-request.
        if loaded.contains(new), !currentIsEmpty { return }

        isLoading = true
        defer { isLoading = false }

        if let contents = try? await ChannelService.shared.tab(channelID: channelID, tab: new) {
            apply(contents)
            loaded.insert(new)
        }
    }

    private var currentIsEmpty: Bool {
        switch tab {
        case .posts: posts.isEmpty
        case .playlists: playlists.isEmpty
        default: videos.isEmpty
        }
    }

    private func apply(_ contents: ChannelService.TabContents) {
        switch tab {
        case .posts: posts = contents.posts
        case .playlists: playlists = contents.playlists
        default: videos = contents.videos
        }
        continuation = contents.continuation
    }

    func loadMoreIfNeeded(at video: Video) async {
        guard let continuation, !isPaging,
              let index = videos.firstIndex(of: video),
              index >= videos.count - 4
        else { return }

        isPaging = true
        defer { isPaging = false }

        // The tab travels with the request: a shorts page parsed as videos
        // comes back empty and reads as "no more shorts".
        if let more = try? await ChannelService.shared.more(continuation: continuation, tab: tab) {
            videos.append(contentsOf: more.videos)
            self.continuation = more.continuation
        }
    }
}

/// A channel.
struct ChannelScreen: View {
    let channelID: String
    var channelName: String = ""

    @Environment(Router.self) private var router
    @Environment(\.prismLayout) private var layout
    @State private var model = ChannelModel()
    @State private var isShuffling = false
    /// The short the user tapped, which is also what presents the vertical
    /// player.
    @State private var openedShort: ShortsEntry?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Metrics.Space.lg, pinnedViews: [.sectionHeaders]) {
                header

                Section {
                    content
                } header: {
                    tabStrip
                }
            }
            .padding(.bottom, layout.bottomInset)
            .pageWidth(layout)
        }
        .scrollIndicators(.hidden)
        .background(Palette.ink.ignoresSafeArea())
        .navigationTitle(model.detail?.name ?? channelName)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            // Screenshot runs land on a specific tab, so each capture is one
            // deterministic launch rather than a launch plus a tap.
            switch DemoData.screen {
            case "channel-shorts": model.tab = .shorts
            case "posts": model.tab = .posts
            default: break
            }
            await model.load(channelID: channelID)
        }
        .fullScreenCover(item: $openedShort) { entry in
            ShortsFeed(
                source: .channel(
                    id: channelID,
                    videos: model.videos,
                    start: entry.index,
                    continuation: model.continuation
                ),
                onClose: { openedShort = nil }
            )
            // Modal content is a separate presentation host, so the layout is
            // handed over explicitly rather than assumed to be inherited.
            .environment(\.prismLayout, layout)
        }
    }

    // MARK: Header

    @ViewBuilder
    private var header: some View {
        VStack(alignment: .leading, spacing: Metrics.Space.lg) {
            if let banner = model.detail?.bannerURL {
                Color.clear
                    .aspectRatio(6.2 / 1, contentMode: .fit)
                    .overlay {
                        RemoteImage(url: banner, targetSize: CGSize(width: 1600, height: 260)) {
                            Rectangle().fill(Palette.surfaceRaised)
                        }
                    }
                    .clipped()
            }

            HStack(alignment: .center, spacing: Metrics.Space.lg) {
                RemoteImage(url: model.detail?.avatarURL, targetSize: CGSize(width: 240, height: 240)) {
                    Circle().fill(Palette.surfaceRaised)
                }
                .frame(width: avatarSize, height: avatarSize)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(Palette.line))

                VStack(alignment: .leading, spacing: 3) {
                    Text(model.detail?.name ?? channelName)
                        .font(Type.title(layout.isWide ? 26 : 19))
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(1)

                    // The handle gets its own line: joined with the counts it
                    // reliably overflows on long handles, and truncating hides
                    // the video count entirely.
                    if let handle = model.detail?.handle, !handle.isEmpty {
                        Text(handle)
                            .font(Type.meta)
                            .foregroundStyle(Palette.textSecondary)
                            .lineLimit(1)
                    }

                    Text(counts)
                        .font(Type.meta)
                        .foregroundStyle(Palette.textTertiary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, layout.gutter)

            if let description = model.detail?.description, !description.isEmpty {
                Text(description)
                    .font(Type.meta)
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(2)
                    .frame(maxWidth: 760, alignment: .leading)
                    .padding(.horizontal, layout.gutter)
            }

            actions
        }
    }

    private var avatarSize: CGFloat { layout.isWide ? 104 : 72 }

    private var counts: String {
        [model.detail?.subscriberText, model.detail?.videoCountText]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    private var actions: some View {
        HStack(spacing: Metrics.Space.sm) {
            Button {
                Task { await shuffle() }
            } label: {
                HStack(spacing: 6) {
                    if isShuffling {
                        ProgressView().controlSize(.small).tint(Palette.ink)
                    } else {
                        Image(systemName: "shuffle").font(.system(size: 13, weight: .bold))
                    }
                    Text(isShuffling ? "Picking…" : "Play something")
                        .font(Type.label)
                }
                .foregroundStyle(Palette.ink)
                .padding(.horizontal, Metrics.Space.lg)
                .padding(.vertical, Metrics.Space.md - 1)
                .background(Palette.refractGradient, in: Capsule())
            }
            .disabled(isShuffling)

            PillButton(icon: "bell", title: "Subscribe") {}

            Spacer(minLength: 0)
        }
        .padding(.horizontal, layout.gutter)
    }

    /// Opens a random upload — the quickest way into a channel you don't know.
    private func shuffle() async {
        isShuffling = true
        defer { isShuffling = false }

        // Use what's already loaded when possible; only ask the network if the
        // videos tab hasn't been fetched.
        if let pick = model.videos.randomElement() {
            Haptics.impact(.medium)
            router.open(pick)
            return
        }
        // `try?` on a method already returning an optional gives a double
        // optional, so it's flattened rather than bound twice.
        let fetched = try? await ChannelService.shared.randomVideo(channelID: channelID)
        if let pick = fetched ?? nil {
            Haptics.impact(.medium)
            router.open(pick)
        }
    }

    // MARK: Tabs

    private var tabStrip: some View {
        ScrollView(.horizontal) {
            HStack(spacing: Metrics.Space.sm) {
                ForEach(ChannelService.Tab.allCases) { tab in
                    let isActive = model.tab == tab
                    Button {
                        Task { await model.select(tab, channelID: channelID) }
                        Haptics.selection()
                    } label: {
                        Text(tab.title)
                            .font(Type.label)
                            .foregroundStyle(isActive ? Palette.ink : Palette.textSecondary)
                            .padding(.horizontal, Metrics.Space.md)
                            .padding(.vertical, Metrics.Space.sm)
                            .background {
                                if isActive {
                                    Capsule().fill(Palette.refractGradient)
                                } else {
                                    Capsule().fill(Palette.surface)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, layout.gutter)
            .padding(.vertical, Metrics.Space.sm)
        }
        .scrollIndicators(.hidden)
        .background(Palette.ink)
    }

    @ViewBuilder
    private var content: some View {
        if model.isLoading {
            ProgressView().tint(Palette.refract)
                .frame(maxWidth: .infinity)
                .padding(Metrics.Space.huge)
        } else if let error = model.error {
            EmptyState(icon: "wifi.exclamationmark", title: "Couldn't load", message: error)
        } else {
            switch model.tab {
            case .shorts:
                shortsGrid

            case .posts:
                if model.posts.isEmpty {
                    EmptyState(icon: "text.bubble", title: "No posts",
                               message: "This channel hasn't posted anything.")
                } else {
                    ForEach(model.posts) { post in
                        CommunityPostCard(post: post) { router.open($0) }
                            // Posts are prose. Run across a 1400pt iPad they'd
                            // be unreadable, so the column stays a column.
                            .frame(maxWidth: 720, alignment: .leading)
                            .padding(.horizontal, layout.gutter)
                    }
                }

            case .playlists:
                ForEach(model.playlists) { playlist in
                    NavigationLink {
                        PlaylistScreen(playlist: playlist)
                    } label: {
                        HStack(spacing: Metrics.Space.md) {
                            Image(systemName: "list.bullet")
                                .foregroundStyle(Palette.textSecondary)
                                .frame(width: 40, height: 40)
                                .background(Palette.surfaceRaised, in: RoundedRectangle(cornerRadius: Metrics.Radius.sm))
                            Text(playlist.title)
                                .font(Type.body)
                                .foregroundStyle(Palette.textPrimary)
                                .lineLimit(2)
                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: 720, alignment: .leading)
                        .padding(.horizontal, layout.gutter)
                    }
                    .buttonStyle(.plain)
                }

            default:
                uploads
            }
        }
    }

    @ViewBuilder
    private var uploads: some View {
        if layout.columns > 1 {
            LazyVGrid(columns: layout.gridColumns, spacing: Metrics.Space.xl) {
                ForEach(model.videos) { video in
                    VideoCard(video: video,
                              onTap: { router.open(video) },
                              width: layout.cellWidth)
                        .task { await model.loadMoreIfNeeded(at: video) }
                }
            }
            .padding(.horizontal, layout.gutter)
        } else {
            ForEach(model.videos) { video in
                VideoRow(video: video) { router.open(video) }
                    .padding(.horizontal, layout.gutter)
                    .task { await model.loadMoreIfNeeded(at: video) }
            }
        }
    }

    // MARK: Shorts

    /// Posters, not rows.
    ///
    /// A short's thumbnail *is* the content — 9:16 tiles show what's in the
    /// video at a glance, where a row of 16:9 crops shows the middle third of
    /// each one and nothing else.
    private var shortsGrid: some View {
        LazyVGrid(columns: shortsColumns, spacing: Metrics.Space.lg) {
            ForEach(Array(model.videos.enumerated()), id: \.element.id) { index, video in
                Button {
                    openedShort = ShortsEntry(id: index)
                    Haptics.impact(.medium)
                } label: {
                    ShortPoster(video: video)
                }
                .buttonStyle(PressableStyle(isPressed: .constant(false), scale: 0.96))
                .task { await model.loadMoreIfNeeded(at: video) }
            }
        }
        .padding(.horizontal, layout.gutter)
    }

    private var shortsColumns: [GridItem] {
        let count = layout.isWide ? max(4, min(7, Int(layout.contentWidth / 210))) : 3
        return Array(repeating: GridItem(.flexible(), spacing: Metrics.Space.md, alignment: .top), count: count)
    }
}

/// One tile in a channel's Shorts grid.
struct ShortPoster: View {
    let video: Video

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.Space.sm) {
            Color.clear
                .aspectRatio(9 / 16, contentMode: .fit)
                .overlay {
                    RemoteImage(url: video.thumbnailURL, targetSize: CGSize(width: 360, height: 640), contentMode: .fill) {
                        ShimmerPlaceholder()
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: Metrics.Radius.md, style: .continuous))
                .overlay(alignment: .bottomLeading) {
                    if !video.viewCountText.isEmpty {
                        Text(video.viewCountText)
                            .font(Type.readoutSmall)
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.6), radius: 3)
                            .padding(Metrics.Space.sm)
                    }
                }

            Text(video.title)
                .font(Type.labelSmall)
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(video.title)
    }
}

/// The grid position that was tapped.
///
/// A bare `Int` would be the whole payload, but `fullScreenCover(item:)` needs
/// something `Identifiable` and conforming `Int` itself would leak that
/// conformance into every file in the app.
struct ShortsEntry: Identifiable, Hashable {
    let id: Int
    var index: Int { id }
}
