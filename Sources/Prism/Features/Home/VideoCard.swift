import SwiftUI

/// The standard feed cell.
///
/// Deliberately restrained: the thumbnail is the only saturated thing in the
/// row, and everything else is set in two greys. In a list of forty of these,
/// any additional colour reads as noise.
struct VideoCard: View {
    let video: Video
    var onTap: () -> Void

    @State private var isPressed = false

    private static let thumbSize = CGSize(width: 400, height: 225)

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: Metrics.Space.md) {
                thumbnail
                metadata
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(isPressed: $isPressed))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(video.title), \(video.channelName)")
        .accessibilityHint("Opens the video")
    }

    private var thumbnail: some View {
        // Ratio enforced by the container, so a thumbnail that isn't exactly
        // 16:9 fills the frame instead of letterboxing inside it.
        Color.clear
            .aspectRatio(16 / 9, contentMode: .fit)
            .overlay {
                RemoteImage(url: video.thumbnailURL, targetSize: Self.thumbSize) {
                    ShimmerPlaceholder()
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Metrics.Radius.card, style: .continuous))
        .overlay(alignment: .bottomTrailing) { durationBadge }
        .overlay {
            RoundedRectangle(cornerRadius: Metrics.Radius.card, style: .continuous)
                .strokeBorder(.white.opacity(0.06))
        }
    }

    @ViewBuilder
    private var durationBadge: some View {
        if video.isLive {
            HStack(spacing: 4) {
                Circle().fill(.white).frame(width: 5, height: 5)
                Text("LIVE").font(Type.readoutSmall)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Palette.live, in: Capsule())
            .padding(Metrics.Space.sm)
        } else if video.duration > 0 {
            Text(video.durationText)
                .font(Type.readoutSmall)
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .padding(Metrics.Space.sm)
        }
    }

    private var metadata: some View {
        HStack(alignment: .top, spacing: Metrics.Space.md) {
            avatar

            VStack(alignment: .leading, spacing: 3) {
                Text(video.title)
                    .font(Type.cardTitle)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                Text(subtitle)
                    .font(Type.meta)
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, Metrics.Space.xs)
    }

    @ViewBuilder
    private var avatar: some View {
        if let url = video.channelThumbnailURL {
            RemoteImage(url: url, targetSize: CGSize(width: 72, height: 72)) {
                Circle().fill(Palette.surfaceRaised)
            }
            .frame(width: 34, height: 34)
            .clipShape(Circle())
        } else {
            // Initial-in-a-circle rather than a generic person glyph: it
            // distinguishes channels from one another at a glance.
            Circle()
                .fill(Palette.surfaceRaised)
                .frame(width: 34, height: 34)
                .overlay {
                    Text(video.channelName.prefix(1).uppercased())
                        .font(Type.label)
                        .foregroundStyle(Palette.textSecondary)
                }
        }
    }

    /// Channel · views · age, dropping any part YouTube didn't give us so we
    /// never render a stray separator.
    private var subtitle: String {
        [video.channelName, video.viewCountText, video.publishedText]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }
}

/// Press feedback: a small, quick scale-down. Applied at the button level so the
/// whole cell responds as one object.
struct PressableStyle: ButtonStyle {
    @Binding var isPressed: Bool
    var scale: CGFloat = 0.975

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(Motion.quick, value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in
                isPressed = pressed
                if pressed { Haptics.impact(.light) }
            }
    }
}

/// Compact horizontal row, used for up-next and search results.
struct VideoRow: View {
    let video: Video
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: Metrics.Space.md) {
                Color.clear
                    .frame(width: 152, height: 152 * 9 / 16)
                    .overlay {
                        RemoteImage(url: video.thumbnailURL, targetSize: CGSize(width: 320, height: 180)) {
                            ShimmerPlaceholder()
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: Metrics.Radius.md, style: .continuous))
                .overlay(alignment: .bottomTrailing) {
                    if video.duration > 0 && !video.isLive {
                        Text(video.durationText)
                            .font(Type.readoutSmall)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 5))
                            .padding(5)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(video.title)
                        .font(Type.cardTitle)
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(video.channelName)
                        .font(Type.meta)
                        .foregroundStyle(Palette.textSecondary)
                        .lineLimit(1)

                    Text([video.viewCountText, video.publishedText].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(Type.meta)
                        .foregroundStyle(Palette.textTertiary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(isPressed: .constant(false), scale: 0.985))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(video.title), \(video.channelName)")
    }
}
