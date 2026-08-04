import SwiftUI
import AVFoundation

/// Where a vertical feed's videos come from.
enum ShortsSource: Equatable {
    /// The Shorts tab — whatever YouTube is surfacing.
    case discover
    /// One creator's shorts, opened at a position the user picked.
    ///
    /// The already-fetched page travels with the case rather than being
    /// re-requested: the channel screen has the list on screen when the tap
    /// happens, so re-fetching it would put a spinner between the tap and the
    /// video for no new information.
    case channel(id: String, videos: [Video], start: Int, continuation: String?)
}

@MainActor
@Observable
final class ShortsFeedModel {
    private(set) var videos: [Video] = []
    private(set) var isLoading = true

    private var continuation: String?
    private var channelID: String?
    private var isPaging = false

    func load(_ source: ShortsSource) async {
        switch source {
        case .discover:
            isLoading = true
            defer { isLoading = false }

            if DemoData.isEnabled {
                videos = DemoData.videos
                return
            }
            if let page = try? await FeedRepository.shared.shorts() {
                videos = page.videos
                continuation = page.continuation
            }

        case let .channel(id, seed, _, token):
            channelID = id
            videos = seed
            continuation = token
            isLoading = false
        }
    }

    /// Keeps the list ahead of the swipe, so scrolling past the last fetched
    /// short continues into the creator's back catalogue instead of stopping.
    func loadMoreIfNeeded(at index: Int) async {
        guard !isPaging, let token = continuation, index >= videos.count - 3 else { return }

        isPaging = true
        defer { isPaging = false }

        guard let channelID, !channelID.isEmpty else { return }
        guard let page = try? await ChannelService.shared.more(continuation: token, tab: .shorts)
        else { return }

        // A continuation that hands back what's already on screen would grow
        // the list without moving it forward, and the pool would re-prepare
        // players for duplicate ids.
        let known = Set(videos.map(\.id))
        videos.append(contentsOf: page.videos.filter { !known.contains($0.id) })
        continuation = page.continuation
    }
}

/// The vertical feed.
///
/// Built on `TabView(.page)` rotated 90°, which gets UIKit's paging scroll view
/// and its momentum for free.
///
/// The performance work is in `ShortsPlayerPool`: only three `AVPlayer`s ever
/// exist, and the neighbouring items are pre-rolled so a swipe starts playing
/// immediately instead of buffering after the gesture lands.
struct ShortsFeed: View {
    let source: ShortsSource
    /// Set when the feed is presented over something else, which puts a close
    /// button in the corner. The Shorts tab has the rail or the tab bar for
    /// that and passes nil.
    var onClose: (() -> Void)?

    @Environment(\.prismLayout) private var layout
    @State private var model = ShortsFeedModel()
    @State private var pool = ShortsPlayerPool()
    @State private var index = 0

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()

                if model.videos.isEmpty {
                    if model.isLoading {
                        ProgressView().tint(.white)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        EmptyState(
                            icon: "play.square.stack",
                            title: "No shorts right now",
                            message: "Pull the feed again in a moment."
                        )
                    }
                } else {
                    pager(in: geo.size)
                }

                if let onClose {
                    closeButton(onClose)
                }
            }
        }
        .ignoresSafeArea()
        .task {
            await model.load(source)
            if case let .channel(_, videos, start, _) = source {
                // Clamped: the caller's index came from a list that may have
                // been filtered on the way in.
                index = min(max(0, start), max(0, videos.count - 1))
            }
            pool.configure(videos: model.videos)
            await pool.activate(index: index)
        }
        .onChange(of: index) { _, new in
            Haptics.selection()
            Task {
                await pool.activate(index: new)
                await model.loadMoreIfNeeded(at: new)
            }
        }
        .onChange(of: model.videos.count) { _, _ in
            pool.configure(videos: model.videos)
        }
        .onDisappear { pool.pauseAll() }
    }

    private func pager(in size: CGSize) -> some View {
        TabView(selection: $index) {
            ForEach(Array(model.videos.enumerated()), id: \.element.id) { i, video in
                ShortCell(
                    video: video,
                    player: pool.player(for: i),
                    isCurrent: i == index,
                    // A short stretched across an iPad is a 9:16 video in a
                    // 4:3 hole; the cell keeps its own aspect and lets the
                    // blurred backdrop own the rest.
                    contentWidth: layout.isWide
                        ? min(size.width, size.height * 9 / 16)
                        : size.width
                )
                .frame(width: size.width, height: size.height)
                .rotationEffect(.degrees(-90))
                // `rotationEffect` moves pixels, not layout. Without this the
                // cell still *measures* portrait inside a landscape page, and
                // the mismatch pushes every short down the screen — which is
                // what put a black band across the top of the feed on both
                // devices. Re-framing after the rotation makes the footprint
                // match the page it sits in.
                .frame(width: size.height, height: size.width)
                .tag(i)
            }
        }
        .frame(width: size.height, height: size.width)
        .rotationEffect(.degrees(90), anchor: .topLeading)
        .offset(x: size.width)
        .tabViewStyle(.page(indexDisplayMode: .never))
    }

    private func closeButton(_ action: @escaping () -> Void) -> some View {
        VStack {
            HStack {
                Button {
                    action()
                    Haptics.impact(.soft)
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(.black.opacity(0.45), in: Circle())
                        .overlay(Circle().strokeBorder(.white.opacity(0.14)))
                }
                .accessibilityLabel("Close")

                Spacer()
            }
            Spacer()
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.top, Metrics.Space.huge + Metrics.Space.md)
    }
}

/// One full-screen short.
struct ShortCell: View {
    let video: Video
    let player: AVPlayer?
    let isCurrent: Bool
    /// The width the video itself occupies. Narrower than the cell on iPad.
    var contentWidth: CGFloat?

    @State private var isLiked = false

    var body: some View {
        ZStack {
            backdrop
            column
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    /// A blurred copy behind the video, so a 16:9 short shown full-height has
    /// something better than black in the letterbox bars.
    ///
    /// Pinned to the cell explicitly. `contentMode: .fill` scales the image
    /// past the frame by design, and without a frame to clip to, the oversized
    /// image sets the size of the stack around it instead of the other way
    /// round.
    private var backdrop: some View {
        RemoteImage(url: video.thumbnailURL, targetSize: CGSize(width: 240, height: 135), contentMode: .fill) {
            Color.black
        }
        .blur(radius: 24)
        .overlay(Color.black.opacity(0.4))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    private var column: some View {
        ZStack {
            videoSurface
            overlay
        }
        .frame(maxWidth: contentWidth)
    }

    @ViewBuilder
    private var videoSurface: some View {
        // The thumbnail stands in for the video until the player is ready,
        // so a swipe never lands on a black rectangle.
        if player == nil {
            RemoteImage(url: video.thumbnailURL, targetSize: CGSize(width: 720, height: 1280), contentMode: .fit) {
                Color.clear
            }
        } else if let player {
            VideoSurface(player: player, gravity: .resizeAspectFill)
        }
    }

    private var overlay: some View {
        VStack {
            Spacer()
            HStack(alignment: .bottom, spacing: Metrics.Space.lg) {
                VStack(alignment: .leading, spacing: Metrics.Space.sm) {
                    if !video.channelName.isEmpty {
                        Text(video.channelName)
                            .font(Type.bodyEmphasis)
                            .foregroundStyle(.white)
                    }
                    Text(video.title)
                        .font(Type.meta)
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(2)
                }

                Spacer(minLength: 0)

                VStack(spacing: Metrics.Space.lg) {
                    ShortAction(icon: isLiked ? "heart.fill" : "heart",
                                tint: isLiked ? Palette.live : .white) {
                        isLiked.toggle()
                        Haptics.impact(.medium)
                    }
                    ShortAction(icon: "bubble.right") {}
                    ShortAction(icon: "square.and.arrow.up") {}
                }
            }
            .padding(.horizontal, Metrics.gutter)
            .padding(.bottom, TabBar.height + Metrics.Space.xl)
        }
        .background {
            LinearGradient(colors: [.clear, .black.opacity(0.55)],
                           startPoint: .center, endPoint: .bottom)
            .allowsHitTesting(false)
        }
    }
}

struct ShortAction: View {
    let icon: String
    var tint: Color = .white
    var action: () -> Void

    @State private var bump = false

    var body: some View {
        Button {
            action()
            withAnimation(Motion.pop) { bump.toggle() }
        } label: {
            Image(systemName: icon)
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(tint)
                .shadow(color: .black.opacity(0.4), radius: 6)
                .scaleEffect(bump ? 1.18 : 1)
                .frame(width: 46, height: 46)
        }
        .motion(Motion.pop, value: bump)
    }
}

/// Keeps at most three players alive: previous, current, next.
///
/// A player per cell would exhaust the decoder session limit within a dozen
/// swipes and stall the feed. Pre-rolling the neighbours is what makes the swipe
/// feel instant rather than merely fast.
@MainActor
@Observable
final class ShortsPlayerPool {
    private var players: [Int: AVPlayer] = [:]
    private var videos: [Video] = []
    private var prepareTasks: [Int: Task<Void, Never>] = [:]

    func configure(videos: [Video]) {
        self.videos = videos
    }

    func player(for index: Int) -> AVPlayer? { players[index] }

    func activate(index: Int) async {
        // Drop anything outside the window so decoders are released promptly.
        let keep = Set([index - 1, index, index + 1])
        for (i, player) in players where !keep.contains(i) {
            player.pause()
            player.replaceCurrentItem(with: nil)
            players[i] = nil
            prepareTasks[i]?.cancel()
            prepareTasks[i] = nil
        }

        for i in keep where i >= 0 && i < videos.count {
            await prepare(i)
        }

        for (i, player) in players {
            if i == index {
                player.seek(to: .zero, completionHandler: { _ in })
                player.play()
            } else {
                player.pause()
            }
        }
    }

    private func prepare(_ index: Int) async {
        guard players[index] == nil, prepareTasks[index] == nil,
              index >= 0, index < videos.count
        else { return }

        let video = videos[index]
        let task = Task { [weak self] in
            guard let source = try? await InnerTubeClient.shared.player(videoID: video.id) else { return }
            // Shorts are small; the progressive rendition is the right trade —
            // one file, no compositing, fastest possible start.
            guard let stream = StreamSelector.fastStart(from: source)
                ?? StreamSelector.select(from: source, quality: .p720).video
            else { return }

            guard !Task.isCancelled else { return }

            let item = AVPlayerItem(url: stream.url)
            item.preferredForwardBufferDuration = 4
            let player = AVPlayer(playerItem: item)
            player.isMuted = false
            player.actionAtItemEnd = .none

            // Shorts loop. The completion-handler form of `seek` is used
            // deliberately: the bare `seek(to:)` resolves to the `async`
            // overload inside a `@Sendable` closure and won't compile here.
            NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: item,
                queue: .main
            ) { _ in
                player.seek(to: .zero, completionHandler: { _ in
                    player.play()
                })
            }

            await MainActor.run { self?.players[index] = player }
        }

        prepareTasks[index] = task
        await task.value
        prepareTasks[index] = nil
    }

    func pauseAll() {
        players.values.forEach { $0.pause() }
    }
}
