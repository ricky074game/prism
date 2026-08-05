import SwiftUI
import AVFoundation

@MainActor
@Observable
final class WatchModel {
    private(set) var source: PlaybackSource?
    private(set) var related: [Video] = []
    private(set) var isLoading = true
    private(set) var error: String?
    /// nil until known. The button starts neutral rather than claiming you
    /// aren't subscribed to a channel you follow.
    private(set) var isSubscribed: Bool?

    func load(video: Video, into player: PlayerEngine, settings: Settings) async {
        isLoading = true
        error = nil

        if DemoData.isEnabled {
            // Fixture segments give the scrubber real dispersion to draw
            // without depending on the network.
            player.categoryActions = settings.categoryActions
            player.poseForDemo(
                duration: video.duration > 0 ? video.duration : 596,
                at: 132,
                segments: DemoData.segments
            )
            related = Array(DemoData.videos.dropFirst())
            isLoading = false
            return
        }

        // Segments and related videos are fetched alongside playback rather than
        // before it — neither should delay the first frame.
        async let segmentsTask = SponsorBlockService.shared.segments(
            for: video.id,
            enabled: settings.enabledCategories
        )
        async let relatedTask = try? FeedRepository.shared.related(to: video.id)

        do {
            let source = try await InnerTubeClient.shared.player(videoID: video.id)
            self.source = source
            player.categoryActions = settings.categoryActions
            await player.load(source: source, quality: settings.preferredQuality)
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? "Couldn't load this video."
        }

        player.segments = await segmentsTask
        related = await relatedTask ?? []
        isLoading = false

        // Asked for after the video is up: it costs a second round-trip and
        // nothing about playback waits on it.
        isSubscribed = await FeedRepository.shared.isSubscribed(toChannelOf: video.id)
    }
}

struct WatchScreen: View {
    let video: Video

    @Environment(Router.self) private var router
    @Environment(PlayerEngine.self) private var player
    @Environment(Settings.self) private var settings
    @Environment(\.prismLayout) private var layout

    @State private var model = WatchModel()
    @State private var glow = GlowSource()
    @State private var dragOffset: CGFloat = 0
    @State private var isLiked = false
    @State private var isDisliked = false
    @State private var isSubscribed = false
    @State private var knowsSubscription = false
    @State private var showDescription = false
    @State private var showComments = false
    @State private var isFullscreen = false
    @State private var session = AccountSession.shared
    @State private var pip = PictureInPictureController()

    private var isSignedIn: Bool { session.isSignedIn }

    var body: some View {
        GeometryReader { geo in
            if isFullscreen {
                fullscreen(in: geo.size)
            } else if let sidebar = layout.watchSidebar {
                split(in: geo.size, sidebar: sidebar)
            } else {
                stacked(in: geo.size)
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .motion(Motion.hero, value: isFullscreen)
        .task {
            glow.load(video.thumbnailURL)
            await model.load(video: video, into: player, settings: settings)
        }
        // Seeded once, from the account. After that the local toggle owns it,
        // so tapping Subscribe doesn't get overwritten by a late answer.
        .onChange(of: model.isSubscribed) { _, actual in
            guard let actual, !knowsSubscription else { return }
            knowsSubscription = true
            isSubscribed = actual
        }
    }

    // MARK: Layouts

    /// The phone layout: player on top, everything else scrolling beneath it.
    private func stacked(in size: CGSize) -> some View {
        VStack(spacing: 0) {
            playerPane(width: size.width, height: size.width * 9 / 16)
            ScrollView {
                detailBlock(includingUpNext: true)
                    // Capped on a portrait iPad: the video is full-bleed but
                    // an up-next row run to 1000pt is mostly empty space with
                    // a thumbnail at one end.
                    .frame(maxWidth: layout.isWide ? 900 : .infinity)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, layout.gutter)
                    .padding(.top, Metrics.Space.lg)
                    .padding(.bottom, Metrics.Space.huge * 2)
            }
            .scrollIndicators(.hidden)
        }
        .background(Palette.ink.ignoresSafeArea())
        .offset(y: dragOffset)
        .gesture(dismissGesture)
    }

    /// The iPad landscape layout.
    ///
    /// Up next moves into its own column instead of living two screens below
    /// the video: on a 1366pt window the stacked layout leaves most of the
    /// right-hand half empty while the list nobody can see scrolls off the
    /// bottom.
    private func split(in size: CGSize, sidebar: CGFloat) -> some View {
        let main = size.width - sidebar
        // Capped against the window height so a wide window doesn't push the
        // title below the fold.
        let playerHeight = min(main * 9 / 16, size.height * 0.68)

        return HStack(spacing: 0) {
            VStack(spacing: 0) {
                playerPane(width: main, height: playerHeight)
                ScrollView {
                    detailBlock(includingUpNext: false)
                        .padding(.horizontal, layout.gutter)
                        .padding(.vertical, Metrics.Space.lg)
                }
                .scrollIndicators(.hidden)
            }
            .frame(width: main)

            Rectangle()
                .fill(Palette.line)
                .frame(width: 0.5)

            upNextColumn
                .frame(width: sidebar)
        }
        .background(Palette.ink.ignoresSafeArea())
    }

    /// Fills the window.
    ///
    /// The content is rotated rather than the device: forcing an orientation is
    /// unreliable across iOS versions and fights the user's rotation lock. But
    /// that only applies when the window is portrait — rotating a window that is
    /// *already* landscape, which is the normal case on iPad, would lay the
    /// video on its side.
    private func fullscreen(in size: CGSize) -> some View {
        ZStack {
            Color.black
            if size.width > size.height {
                playerPane(width: size.width, height: size.height)
            } else {
                playerPane(width: size.height, height: size.width)
                    .rotationEffect(.degrees(90))
                    .frame(width: size.width, height: size.height)
            }
        }
        .ignoresSafeArea()
        .statusBarHidden()
        .transition(.opacity)
    }

    // MARK: Player

    private func playerPane(width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            Color.black

            // Poster frame. Sits under the video layer for the whole session:
            // until the first frame decodes, the thumbnail stands in, so opening
            // a video never shows a black rectangle.
            RemoteImage(url: video.thumbnailURL, targetSize: CGSize(width: 800, height: 450), contentMode: .fit) {
                Color.black
            }
            .opacity(player.hasVideo ? 0 : 1)

            VideoSurface(player: player.player, gravity: .resizeAspect) { layer in
                pip.attach(to: layer)
            }

            if player.isBuffering {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white)
            }

            PlayerControls(video: video, isFullscreen: $isFullscreen, pip: pip)
        }
        .frame(width: width, height: height)
        .clipped()
        .background {
            if settings.ambientGlow {
                AmbientGlow(image: glow.image, intensity: 0.4, blur: 70)
                    .scaleEffect(1.3)
                    // Without a mask the spill ends on a hard rectangular edge
                    // that reads as a lighter panel behind the title.
                    .mask(
                        LinearGradient(
                            stops: [
                                .init(color: .white, location: 0),
                                .init(color: .white, location: 0.55),
                                .init(color: .clear, location: 1),
                            ],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
            }
        }
        .overlay(alignment: .bottom) {
            if let skip = player.lastSkip {
                SkipToast(segment: skip) { player.undoSkip() }
                    .padding(.bottom, Metrics.Space.xxl)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .motion(Motion.standard, value: player.lastSkip?.id)
    }

    // MARK: Below the fold

    /// Everything below the video. `Up next` is dropped when a sidebar is
    /// showing it instead.
    private func detailBlock(includingUpNext: Bool) -> some View {
        VStack(alignment: .leading, spacing: Metrics.Space.lg) {
            header
            actionRow

            if let error = model.error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(Type.meta)
                    .foregroundStyle(Palette.warning)
                    .padding(Metrics.Space.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Palette.warning.opacity(0.1), in: RoundedRectangle(cornerRadius: Metrics.Radius.md))
            }

            if includingUpNext {
                Divider().overlay(Palette.line)
                upNext
            }
        }
    }

    private var upNextColumn: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.Space.lg) {
                Text("Up next")
                    .font(Type.title(15))
                    .foregroundStyle(Palette.textPrimary)

                ForEach(model.related) { next in
                    VideoRow(video: next) { router.open(next) }
                }
            }
            .padding(.horizontal, Metrics.Space.lg)
            .padding(.vertical, Metrics.Space.lg)
        }
        .scrollIndicators(.hidden)
        .background(Palette.ink)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Metrics.Space.sm) {
            Text(model.source?.title ?? video.title)
                .font(Type.cardTitleLarge)
                .foregroundStyle(Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                router.openChannel(id: model.source?.channelID ?? video.channelID,
                                   name: video.channelName)
            } label: {
                channelLine
            }
            .buttonStyle(.plain)
            .disabled((model.source?.channelID ?? video.channelID).isEmpty)
        }
    }

    private var channelLine: some View {
        HStack(spacing: Metrics.Space.sm) {
            Text(video.channelName)
                .font(Type.metaEmphasis)
                .foregroundStyle(Palette.textSecondary)

            // Signals the name is a link. Omitted when there's no channel id to
            // open, so it never promises navigation that won't happen.
            if !(model.source?.channelID ?? video.channelID).isEmpty {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Palette.textTertiary)
            }

            if !video.viewCountText.isEmpty {
                Circle().fill(Palette.textTertiary).frame(width: 3, height: 3)
                Text(video.viewCountText).font(Type.meta).foregroundStyle(Palette.textTertiary)
            }

            Spacer(minLength: 0)
        }
    }

    private var actionRow: some View {
        ScrollView(.horizontal) {
            HStack(spacing: Metrics.Space.sm) {
                PillButton(icon: isLiked ? "hand.thumbsup.fill" : "hand.thumbsup",
                           title: "Like",
                           tint: isLiked ? Palette.refract : nil) {
                    isLiked.toggle()
                    Haptics.impact(.medium)
                    if isSignedIn {
                        Task {
                            try? await InnerTubeClient.shared.rate(
                                videoID: video.id,
                                rating: isLiked ? "like" : "none"
                            )
                        }
                    }
                }
                PillButton(icon: isDisliked ? "hand.thumbsdown.fill" : "hand.thumbsdown",
                           title: nil,
                           tint: isDisliked ? Palette.textPrimary : nil) {
                    isDisliked.toggle()
                    if isDisliked { isLiked = false }
                    Haptics.impact(.medium)
                    if isSignedIn {
                        Task {
                            try? await InnerTubeClient.shared.rate(
                                videoID: video.id,
                                rating: isDisliked ? "dislike" : "none"
                            )
                        }
                    }
                }

                PillButton(icon: isSubscribed ? "bell.fill" : "bell",
                           title: isSubscribed ? "Subscribed" : "Subscribe",
                           prominent: !isSubscribed) {
                    isSubscribed.toggle()
                    Haptics.impact(.medium)
                    if isSignedIn {
                        Task {
                            try? await InnerTubeClient.shared.setSubscription(
                                channelID: model.source?.channelID ?? video.channelID,
                                subscribed: isSubscribed
                            )
                        }
                    }
                }
                // ShareLink presents the system share sheet itself, so it is
                // the button rather than something a button opens.
                ShareLink(item: URL(string: "https://youtu.be/\(video.id)")!) {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.arrow.up").font(.system(size: 13, weight: .semibold))
                        Text("Share").font(Type.label)
                    }
                    .foregroundStyle(Palette.textPrimary)
                    .padding(.horizontal, Metrics.Space.md)
                    .padding(.vertical, Metrics.Space.sm + 1)
                    .background(Capsule().fill(Palette.surface))
                }

                PillButton(icon: "bubble.left", title: "Comments") { showComments = true }
                PillButton(icon: "text.alignleft", title: "Description") { showDescription = true }
            }
            .padding(.horizontal, 2)
        }
        .scrollIndicators(.hidden)
        .sheet(isPresented: $showDescription) {
            if let source = model.source {
                DescriptionSheet(source: source) { player.seek(to: $0) }
                    .presentationDetents([.medium, .large])
            }
        }
        .sheet(isPresented: $showComments) {
            CommentsSheet(video: video)
                .presentationDetents([.medium, .large])
        }
    }

    private var upNext: some View {
        VStack(alignment: .leading, spacing: Metrics.Space.lg) {
            Text("Up next")
                .font(Type.title(15))
                .foregroundStyle(Palette.textPrimary)

            ForEach(model.related) { next in
                VideoRow(video: next) { router.open(next) }
            }
        }
    }

    // MARK: Dismiss

    /// Dragging down collapses to the mini player rather than closing outright —
    /// the video keeps playing, which is the behaviour people expect.
    private var dismissGesture: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { v in
                dragOffset = max(0, v.translation.height)
            }
            .onEnded { v in
                if v.translation.height > 110 || v.predictedEndTranslation.height > 240 {
                    withAnimation(Motion.hero) { router.isWatchExpanded = false }
                    Haptics.impact(.soft)
                }
                withAnimation(Motion.standard) { dragOffset = 0 }
            }
    }
}

// MARK: - Pieces

struct PillButton: View {
    let icon: String
    var title: String?
    var prominent = false
    var tint: Color?
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .contentTransition(.symbolEffect(.replace))
                if let title { Text(title).font(Type.label) }
            }
            .foregroundStyle(prominent ? Palette.ink : (tint ?? Palette.textPrimary))
            .padding(.horizontal, Metrics.Space.md)
            .padding(.vertical, Metrics.Space.sm + 1)
            .background {
                if prominent {
                    Capsule().fill(Palette.refractGradient)
                } else {
                    Capsule().fill(Palette.surface)
                }
            }
        }
        .buttonStyle(PressableStyle(isPressed: .constant(false), scale: 0.94))
    }
}

/// Confirms a skip and offers to undo it.
///
/// Undo matters: a wrong skip is the only way SponsorBlock can actively harm the
/// experience, so putting the fix one tap away is what makes aggressive
/// defaults reasonable.
struct SkipToast: View {
    let segment: SponsorSegment
    var onUndo: () -> Void

    var body: some View {
        HStack(spacing: Metrics.Space.md) {
            Image(systemName: segment.category.icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(segment.category.color)

            VStack(alignment: .leading, spacing: 1) {
                Text("Skipped \(segment.category.title.lowercased())")
                    .font(Type.label)
                    .foregroundStyle(Palette.textPrimary)
                Text("\(Int(segment.duration))s")
                    .font(Type.readoutSmall)
                    .foregroundStyle(Palette.textTertiary)
            }

            Button("Undo", action: onUndo)
                .font(Type.label)
                .foregroundStyle(Palette.disperse)
        }
        .padding(.horizontal, Metrics.Space.lg)
        .padding(.vertical, Metrics.Space.md)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(segment.category.color.opacity(0.3)))
    }
}

/// Wrapping horizontal stack. SwiftUI has no built-in, and a `LazyVGrid` can't
/// size columns to content.
struct FlowRow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0

        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0

        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
