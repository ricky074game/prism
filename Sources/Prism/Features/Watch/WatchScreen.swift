import SwiftUI
import AVFoundation

@MainActor
@Observable
final class WatchModel {
    private(set) var source: PlaybackSource?
    private(set) var related: [Video] = []
    private(set) var isLoading = true
    private(set) var error: String?

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
    }
}

struct WatchScreen: View {
    let video: Video

    @Environment(Router.self) private var router
    @Environment(PlayerEngine.self) private var player
    @Environment(Settings.self) private var settings

    @State private var model = WatchModel()
    @State private var glow = GlowSource()
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                playerPane(width: geo.size.width)
                details
            }
            .background(Palette.ink.ignoresSafeArea())
            .offset(y: dragOffset)
            .gesture(dismissGesture)
        }
        .ignoresSafeArea(edges: .bottom)
        .task {
            glow.load(video.thumbnailURL)
            await model.load(video: video, into: player, settings: settings)
        }
    }

    // MARK: Player

    private func playerPane(width: CGFloat) -> some View {
        ZStack {
            Color.black

            VideoSurface(player: player.player, gravity: .resizeAspect)

            if player.isBuffering {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white)
            }

            PlayerControls(video: video)
        }
        .frame(width: width, height: width * 9 / 16)
        .clipped()
        .background {
            if settings.ambientGlow {
                AmbientGlow(image: glow.image, intensity: 0.4, blur: 70)
                    .scaleEffect(1.3)
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

    private var details: some View {
        ScrollView {
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

                if !player.segments.isEmpty {
                    SegmentSummary(segments: player.segments, duration: player.duration)
                }

                Divider().overlay(Palette.line)

                upNext
            }
            .padding(.horizontal, Metrics.gutter)
            .padding(.top, Metrics.Space.lg)
            .padding(.bottom, Metrics.Space.huge * 2)
        }
        .scrollIndicators(.hidden)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Metrics.Space.sm) {
            Text(model.source?.title ?? video.title)
                .font(Type.cardTitleLarge)
                .foregroundStyle(Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: Metrics.Space.sm) {
                Text(video.channelName)
                    .font(Type.metaEmphasis)
                    .foregroundStyle(Palette.textSecondary)
                if !video.viewCountText.isEmpty {
                    Circle().fill(Palette.textTertiary).frame(width: 3, height: 3)
                    Text(video.viewCountText).font(Type.meta).foregroundStyle(Palette.textTertiary)
                }
            }
        }
    }

    private var actionRow: some View {
        ScrollView(.horizontal) {
            HStack(spacing: Metrics.Space.sm) {
                PillButton(icon: "hand.thumbsup", title: "Like")
                PillButton(icon: "hand.thumbsdown", title: nil)
                PillButton(icon: "bell", title: "Subscribe", prominent: true)
                PillButton(icon: "square.and.arrow.up", title: "Share")
                PillButton(icon: "text.alignleft", title: "Description")
            }
            .padding(.horizontal, 2)
        }
        .scrollIndicators(.hidden)
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

    var body: some View {
        Button {} label: {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 13, weight: .semibold))
                if let title { Text(title).font(Type.label) }
            }
            .foregroundStyle(prominent ? Palette.ink : Palette.textPrimary)
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

/// A legend for what the scrubber is showing — how much of this video isn't
/// the video.
struct SegmentSummary: View {
    let segments: [SponsorSegment]
    let duration: Double

    private var grouped: [(category: SegmentCategory, total: Double)] {
        Dictionary(grouping: segments.filter { !$0.isPointOfInterest && !$0.isFullVideo }, by: \.category)
            .map { ($0.key, $0.value.reduce(0) { $0 + $1.duration }) }
            .sorted { $0.total > $1.total }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.Space.md) {
            HStack(spacing: 6) {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Palette.textTertiary)
                Text("SEGMENTS")
                    .font(Type.readoutSmall)
                    .tracking(1)
                    .foregroundStyle(Palette.textTertiary)
            }

            FlowRow(spacing: Metrics.Space.sm) {
                ForEach(grouped, id: \.category) { item in
                    HStack(spacing: 5) {
                        Circle().fill(item.category.color).frame(width: 6, height: 6)
                        Text(item.category.title).font(Type.labelSmall)
                            .foregroundStyle(Palette.textSecondary)
                        Text("\(Int(item.total))s").font(Type.readoutSmall)
                            .foregroundStyle(Palette.textTertiary)
                    }
                    .padding(.horizontal, Metrics.Space.sm + 2)
                    .padding(.vertical, 5)
                    .background(Palette.surface, in: Capsule())
                }
            }
        }
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
