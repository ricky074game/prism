import SwiftUI

@MainActor
@Observable
final class SubscriptionsModel {
    private(set) var channels: [Channel] = []
    private(set) var videos: [Video] = []
    private(set) var isLoading = false
    private(set) var error: String?

    func load() async {
        if DemoData.isEnabled {
            videos = DemoData.videos
            return
        }
        guard GoogleAuth.shared.isSignedIn else { return }

        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            let (channels, _) = try await YouTubeDataAPI.shared.subscriptions()
            self.channels = channels

            // Uploads for the first handful of channels, fetched concurrently.
            // Bounded because each channel is a request and the point is a
            // glanceable feed, not an exhaustive one.
            let recent = await withTaskGroup(of: [Video].self) { group in
                for channel in channels.prefix(12) {
                    group.addTask {
                        (try? await YouTubeDataAPI.shared.uploads(channelID: channel.id, limit: 3)) ?? []
                    }
                }
                var all: [Video] = []
                for await batch in group { all.append(contentsOf: batch) }
                return all
            }
            videos = recent
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? "Couldn't load your subscriptions."
        }
    }
}

struct SubscriptionsScreen: View {
    @Environment(Router.self) private var router
    @Environment(\.prismLayout) private var layout
    @State private var model = SubscriptionsModel()
    @State private var auth = GoogleAuth.shared

    var body: some View {
        ScrollView {
            LazyVStack(spacing: Metrics.Space.xl) {
                if !auth.isSignedIn && !DemoData.isEnabled {
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

                Color.clear.frame(height: layout.bottomChrome)
            }
            .padding(.top, Metrics.Space.sm)
            .pageWidth(layout)
        }
        .scrollIndicators(.hidden)
        .background(Palette.ink)
        .safeAreaInset(edge: .top, spacing: 0) { ScreenHeader(title: "Subscriptions") }
        .task { await model.load() }
        .onChange(of: auth.isSignedIn) { _, signedIn in
            if signedIn { Task { await model.load() } }
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
                ForEach(model.channels) { channel in
                    VStack(spacing: Metrics.Space.sm) {
                        RemoteImage(url: channel.thumbnailURL, targetSize: CGSize(width: 120, height: 120)) {
                            Circle().fill(Palette.surfaceRaised)
                        }
                        .frame(width: 52, height: 52)
                        .clipShape(Circle())
                        .overlay(Circle().strokeBorder(Palette.line))

                        Text(channel.name)
                            .font(Type.labelSmall)
                            .foregroundStyle(Palette.textSecondary)
                            .lineLimit(1)
                            .frame(maxWidth: 64)
                    }
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
/// answer is narrower than people expect — it reads the subscription list, and
/// it does not personalise the home feed.
struct SignInPrompt: View {
    @State private var auth = GoogleAuth.shared

    var body: some View {
        VStack(spacing: Metrics.Space.lg) {
            PrismMark().frame(width: 40, height: 40)

            VStack(spacing: Metrics.Space.sm) {
                Text("See the channels you follow")
                    .font(Type.title(18))
                    .foregroundStyle(Palette.textPrimary)
                    .multilineTextAlignment(.center)

                Text("Prism reads your subscription list from your Google account. Your tokens stay in this device's Keychain and are never sent anywhere else.")
                    .font(Type.meta)
                    .foregroundStyle(Palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if auth.isConfigured {
                Button {
                    Task { await auth.signIn() }
                } label: {
                    HStack(spacing: Metrics.Space.sm) {
                        if auth.isAuthenticating {
                            ProgressView().tint(Palette.ink).controlSize(.small)
                        }
                        Text(auth.isAuthenticating ? "Signing in…" : "Sign in with Google")
                            .font(Type.label)
                    }
                    .foregroundStyle(Palette.ink)
                    .padding(.horizontal, Metrics.Space.xl)
                    .padding(.vertical, Metrics.Space.md)
                    .background(Palette.refractGradient, in: Capsule())
                }
                .disabled(auth.isAuthenticating)
            } else {
                // Better than a button that opens a broken Google page.
                VStack(spacing: Metrics.Space.xs) {
                    Text("Sign-in isn't set up in this build")
                        .font(Type.metaEmphasis)
                        .foregroundStyle(Palette.textSecondary)
                    Text("Add a Google OAuth client ID in Secrets.swift to enable it.")
                        .font(Type.labelSmall)
                        .foregroundStyle(Palette.textTertiary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, Metrics.Space.xs)
            }

            if let error = auth.error {
                Text(error)
                    .font(Type.labelSmall)
                    .foregroundStyle(Palette.warning)
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
