import SwiftUI

/// The docked player.
///
/// Sits above the tab bar once the watch screen is collapsed. Tapping anywhere
/// but the controls expands it back; swiping it down ends playback. A one-pixel
/// progress line along the bottom is the only progress indicator that fits here,
/// and it's enough.
struct MiniPlayerBar: View {
    @Environment(Router.self) private var router
    @Environment(PlayerEngine.self) private var player

    @State private var dragOffset: CGFloat = 0

    var body: some View {
        if let video = router.nowPlaying {
            HStack(spacing: Metrics.Space.md) {
                RemoteImage(url: video.thumbnailURL, targetSize: CGSize(width: 160, height: 90)) {
                    Rectangle().fill(Palette.surfaceRaised)
                }
                .frame(width: 62, height: 35)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 1) {
                    Text(video.title)
                        .font(Type.label)
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(1)
                    Text(video.channelName)
                        .font(Type.labelSmall)
                        .foregroundStyle(Palette.textTertiary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Button {
                    player.togglePlayPause()
                } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Palette.textPrimary)
                        .frame(width: 36, height: 36)
                        .contentTransition(.symbolEffect(.replace))
                }
                .accessibilityLabel(player.isPlaying ? "Pause" : "Play")

                Button {
                    player.teardown()
                    router.closeWatch()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Palette.textSecondary)
                        .frame(width: 36, height: 36)
                }
                .accessibilityLabel("Close player")
            }
            .padding(.horizontal, Metrics.Space.md)
            .padding(.vertical, Metrics.Space.sm)
            .background {
                GlassPanel(cornerRadius: Metrics.Radius.md) { Color.clear }
            }
            .overlay(alignment: .bottom) {
                GeometryReader { geo in
                    Rectangle()
                        .fill(Palette.refractGradient)
                        .frame(width: geo.size.width * player.progress, height: 2)
                }
                .frame(height: 2)
                .padding(.horizontal, 1)
            }
            .padding(.horizontal, Metrics.Space.sm)
            .offset(y: dragOffset)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(Motion.hero) { router.isWatchExpanded = true }
            }
            .gesture(
                DragGesture(minimumDistance: 10)
                    .onChanged { v in dragOffset = max(0, v.translation.height) }
                    .onEnded { v in
                        if v.translation.height > 50 {
                            player.teardown()
                            router.closeWatch()
                        }
                        withAnimation(Motion.standard) { dragOffset = 0 }
                    }
            )
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Now playing: \(video.title)")
        }
    }
}
