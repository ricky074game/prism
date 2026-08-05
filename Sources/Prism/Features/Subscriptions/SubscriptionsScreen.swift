import SwiftUI

@MainActor
@Observable
final class SubscriptionsModel {
    private(set) var channels: [SubscribedChannel] = []
    private(set) var videos: [Video] = []
    private(set) var isLoading = false
    private(set) var error: String?

    func load() async {
        if DemoData.isEnabled {
            videos = DemoData.videos
            return
        }
        guard AccountSession.shared.isSignedIn else { return }

        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            // InnerTube's subscription feed, not the Data API.
            //
            // The Data API cannot work here at all: the token comes from
            // YouTube's own TV OAuth client, and YouTube Data API v3 is
            // *disabled* on that Google project — every call returns HTTP 403
            // "has not been used in project 861556708454 before or it is
            // disabled". That project isn't ours to enable. One InnerTube
            // browse replaces a subscription list plus a request per channel,
            // and it returns the feed already merged and ordered.
            let page = try await FeedRepository.shared.feed(.subscriptions)
            videos = page.videos

            // The full list, and which of them have posted recently.
            //
            // Two sources because neither has both halves: the channel list
            // carries no "new uploads" flag, and the feed only mentions
            // channels that posted. A channel is dotted when it appears in the
            // feed, and dotted channels sort to the front — which is the
            // ordering that makes the strip worth glancing at.
            let all = (try? await ChannelService.shared.subscriptions()) ?? []
            let fresh = Set(page.videos.map(\.channelID).filter { !$0.isEmpty })

            channels = all
                .map { SubscribedChannel(channel: $0, hasNewVideos: fresh.contains($0.id)) }
                .sorted { lhs, rhs in
                    lhs.hasNewVideos == rhs.hasNewVideos
                        ? lhs.channel.name.localizedCaseInsensitiveCompare(rhs.channel.name) == .orderedAscending
                        : lhs.hasNewVideos
                }

        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? "Couldn't load your subscriptions."
        }
    }
}

/// A subscribed channel, plus whether it's posted anything in the current feed.
struct SubscribedChannel: Identifiable, Hashable {
    let channel: Channel
    let hasNewVideos: Bool

    var id: String { channel.id }
}

struct SubscriptionsScreen: View {
    @Environment(Router.self) private var router
    @Environment(\.prismLayout) private var layout
    @State private var model = SubscriptionsModel()
    @State private var session = AccountSession.shared

    private var signedIn: Bool { session.isSignedIn }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: Metrics.Space.xl) {
                if !signedIn && !DemoData.isEnabled {
                    SignInPrompt()
                        .padding(.top, Metrics.Space.huge)
                } else {
                    if !model.channels.isEmpty {
                        channelStrip
                    }

                    if let error = model.error {
                        Text(error)
                            .font(Type.meta)
                            .foregroundStyle(Palette.warning)
                            .padding(.horizontal, layout.gutter)
                    }

                    uploads

                    if model.isLoading {
                        ProgressView().tint(Palette.refract).padding(Metrics.Space.xxl)
                    }
                }

                Color.clear.frame(height: layout.bottomInset)
            }
            .padding(.top, Metrics.Space.sm)
            .pageWidth(layout)
        }
        .scrollIndicators(.hidden)
        .background(Palette.ink)
        .safeAreaInset(edge: .top, spacing: 0) { ScreenHeader(title: "Subscriptions") }
        .task { await model.load() }
        .onChange(of: signedIn) { _, now in
            if now { Task { await model.load() } }
        }
    }

    @ViewBuilder
    private var uploads: some View {
        if layout.columns > 1 {
            LazyVGrid(columns: layout.gridColumns, spacing: Metrics.Space.xl) {
                ForEach(model.videos) { video in card(video, width: layout.cellWidth) }
            }
            .padding(.horizontal, layout.gutter)
        } else {
            ForEach(model.videos) { video in
                card(video).padding(.horizontal, layout.gutter)
            }
        }
    }

    private func card(_ video: Video, width: CGFloat? = nil) -> some View {
        VideoCard(video: video,
                  onTap: { router.open(video) },
                  onTapChannel: { router.openChannel(id: $0, name: video.channelName) },
                  width: width)
    }

    /// The channels you follow, as a horizontal strip of avatars.
    private var channelStrip: some View {
        ScrollView(.horizontal) {
            HStack(spacing: Metrics.Space.lg) {
                ForEach(model.channels) { entry in
                    Button {
                        router.openChannel(id: entry.channel.id, name: entry.channel.name)
                    } label: {
                        VStack(spacing: Metrics.Space.sm) {
                            RemoteImage(url: entry.channel.thumbnailURL, targetSize: CGSize(width: 120, height: 120)) {
                                Circle().fill(Palette.surfaceRaised)
                            }
                            .frame(width: 52, height: 52)
                            .clipShape(Circle())
                            .overlay(Circle().strokeBorder(Palette.line))
                            // The dot marks a channel that's in the current
                            // feed. Drawn outside the avatar's clip so it isn't
                            // cropped by the circle.
                            .overlay(alignment: .topTrailing) {
                                if entry.hasNewVideos {
                                    Circle()
                                        .fill(Palette.refract)
                                        .frame(width: 11, height: 11)
                                        .overlay(Circle().strokeBorder(Palette.ink, lineWidth: 2))
                                        .offset(x: 2, y: -2)
                                }
                            }

                            Text(entry.channel.name)
                                .font(Type.labelSmall)
                                .foregroundStyle(entry.hasNewVideos ? Palette.textPrimary : Palette.textSecondary)
                                .lineLimit(1)
                                .frame(maxWidth: 64)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(entry.hasNewVideos
                        ? "\(entry.channel.name), new videos"
                        : entry.channel.name)
                }
            }
            .padding(.horizontal, layout.gutter)
        }
        .scrollIndicators(.hidden)
    }
}

/// Shown when nobody is signed in.
///
/// It states exactly what signing in does and does not do, because the honest
/// answer is narrower than people expect — it reads your subscription feed, and
/// it does not personalise the home feed.
struct SignInPrompt: View {
    var body: some View {
        VStack(spacing: Metrics.Space.lg) {
            PrismMark().frame(width: 40, height: 40)

            VStack(spacing: Metrics.Space.sm) {
                Text("See the channels you follow")
                    .font(Type.title(18))
                    .foregroundStyle(Palette.textPrimary)
                    .multilineTextAlignment(.center)

                Text("Prism reads your subscription feed from your YouTube account. Your tokens stay in this device's Keychain and are never sent anywhere else.")
                    .font(Type.meta)
                    .foregroundStyle(Palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Goes to the account screen rather than starting the flow here.
            // Signing in is a device-code exchange — a code to read and a page
            // to open on another device — and that needs somewhere to live.
            // The button used to say sign-in "isn't set up in this build",
            // which was only ever true of the optional Cloud client.
            NavigationLink {
                AccountScreen()
            } label: {
                Text("Sign in")
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

struct ScreenHeader: View {
    let title: String

    @Environment(\.prismLayout) private var layout

    var body: some View {
        HStack {
            Text(title)
                .font(Type.title(layout.isWide ? 28 : 22))
                .foregroundStyle(Palette.textPrimary)
            Spacer()
        }
        .padding(.horizontal, layout.gutter)
        .padding(.vertical, Metrics.Space.md)
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(Palette.ink.opacity(0.5))
                .ignoresSafeArea(edges: .top)
        }
    }
}
