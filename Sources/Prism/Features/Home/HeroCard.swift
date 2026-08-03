import SwiftUI

/// The top of the feed.
///
/// The hero is the app's thesis stated once per session: a single video, large,
/// lit by its own colour. Everything below it is a quiet list — the contrast is
/// the point, and it's why the glow appears here and nowhere else in the feed.
struct HeroCard: View {
    let video: Video
    let glow: GlowSource
    var onTap: () -> Void

    @Environment(Settings.self) private var settings
    @State private var appeared = false

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: Metrics.Space.lg) {
                artwork
                caption
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(isPressed: .constant(false), scale: 0.985))
        .onAppear {
            withAnimation(Motion.hero.delay(0.05)) { appeared = true }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Featured: \(video.title), \(video.channelName)")
    }

    private var artwork: some View {
        // The aspect ratio has to be enforced on a *container* the image fills,
        // not on the image itself. Applying it to `RemoteImage` sizes the view
        // to the loaded bitmap's own ratio instead — YouTube's 4:3-padded
        // thumbnails then leave black bars inside the rounded rect.
        Color.clear
            .aspectRatio(16 / 9, contentMode: .fit)
            .overlay {
                RemoteImage(url: video.thumbnailURL, targetSize: CGSize(width: 800, height: 450)) {
                    ShimmerPlaceholder()
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Metrics.Radius.sheet, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Metrics.Radius.sheet, style: .continuous)
                .strokeBorder(.white.opacity(0.08))
        }
        .overlay(alignment: .topLeading) { featuredBadge }
        .overlay(alignment: .bottomTrailing) { playAffordance }
        .background {
            // The glow sits behind the artwork, scaled past its bounds so the
            // colour reads as spill rather than as a border.
            if settings.ambientGlow {
                AmbientGlow(image: glow.image, intensity: 0.5, blur: 48)
                    .scaleEffect(1.12)
                    .offset(y: 10)
                    // Faded at both ends, so the spill reads as light coming off
                    // the artwork rather than a tinted panel with a visible edge
                    // running under the title.
                    .mask(
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0),
                                .init(color: .white, location: 0.25),
                                .init(color: .white, location: 0.6),
                                .init(color: .clear, location: 1),
                            ],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .opacity(appeared ? 1 : 0)
                    .animation(Motion.ambient, value: glow.image != nil)
            }
        }
    }

    private var featuredBadge: some View {
        HStack(spacing: 5) {
            PrismMark().frame(width: 11, height: 11)
            Text("PICKED FOR YOU")
                .font(Type.readoutSmall)
                .tracking(0.8)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(.black.opacity(0.5), in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.12)))
        .padding(Metrics.Space.md)
    }

    private var playAffordance: some View {
        ZStack {
            Circle()
                .fill(.ultraThinMaterial)
                .overlay(Circle().strokeBorder(.white.opacity(0.18)))
            Image(systemName: "play.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .offset(x: 1.5)
        }
        .frame(width: 52, height: 52)
        .padding(Metrics.Space.md)
        .scaleEffect(appeared ? 1 : 0.7)
        .opacity(appeared ? 1 : 0)
    }

    private var caption: some View {
        VStack(alignment: .leading, spacing: Metrics.Space.sm) {
            Text(video.title)
                .font(Type.cardTitleLarge)
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: Metrics.Space.sm) {
                Text(video.channelName)
                    .font(Type.metaEmphasis)
                    .foregroundStyle(Palette.textSecondary)

                if !video.viewCountText.isEmpty {
                    Circle().fill(Palette.textTertiary).frame(width: 3, height: 3)
                    Text(video.viewCountText)
                        .font(Type.meta)
                        .foregroundStyle(Palette.textTertiary)
                }

                Spacer(minLength: 0)

                if video.duration > 0 {
                    Text(video.durationText)
                        .font(Type.readout)
                        .foregroundStyle(Palette.textSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Palette.surface, in: Capsule())
                }
            }
        }
        .padding(.horizontal, Metrics.Space.xs)
    }
}
