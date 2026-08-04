import SwiftUI

/// Everything that isn't transport: speed, quality, captions.
///
/// One sheet rather than three separate menus, because these are the settings
/// people reach for mid-video and hunting through nested menus while something
/// is playing is the wrong experience.
struct PlayerOptionsSheet: View {
    @Environment(PlayerEngine.self) private var player
    @Environment(Settings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Metrics.Space.xxl) {
                    speed
                    captions
                    quality
                }
                .padding(Metrics.gutter)
                .padding(.bottom, Metrics.Space.huge)
            }
            .scrollIndicators(.hidden)
            .background(Palette.ink.ignoresSafeArea())
            .navigationTitle("Playback")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(Type.label)
                        .foregroundStyle(Palette.refract)
                }
            }
        }
    }

    // MARK: Speed

    private var speed: some View {
        section("SPEED") {
            // A row of pills rather than a menu: seven fixed values fit, and
            // one tap beats open-menu-then-tap when the video is running.
            FlowRow(spacing: Metrics.Space.sm) {
                ForEach(Settings.rateOptions, id: \.self) { rate in
                    let isActive = abs(player.playbackRate - rate) < 0.01
                    Button {
                        player.setPlaybackRate(rate)
                        settings.playbackRate = rate
                        Haptics.selection()
                    } label: {
                        Text(rate == 1.0 ? "Normal" : "\(formatted(rate))×")
                            .font(Type.label)
                            .foregroundStyle(isActive ? Palette.ink : Palette.textPrimary)
                            .padding(.horizontal, Metrics.Space.md)
                            .padding(.vertical, Metrics.Space.sm)
                            .background {
                                if isActive {
                                    Capsule().fill(Palette.refractGradient)
                                } else {
                                    Capsule().fill(Palette.surfaceRaised)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func formatted(_ rate: Double) -> String {
        rate.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(rate))
            : String(format: "%.2f", rate).replacingOccurrences(of: "0$", with: "", options: .regularExpression)
    }

    // MARK: Captions

    @ViewBuilder
    private var captions: some View {
        section("CAPTIONS") {
            if player.captionOptions.isEmpty {
                Text("This video has no captions.")
                    .font(Type.meta)
                    .foregroundStyle(Palette.textTertiary)
                    .padding(.vertical, Metrics.Space.md)
            } else {
                ForEach(player.captionOptions) { option in
                    row(
                        title: option.title,
                        isActive: player.activeCaption == option
                    ) {
                        player.selectCaption(option)
                        Haptics.selection()
                    }
                }
            }
        }
    }

    // MARK: Quality

    private var quality: some View {
        section("QUALITY") {
            ForEach(VideoQuality.allCases) { option in
                row(
                    title: option.title,
                    note: option.note,
                    isActive: player.currentQuality == option
                ) {
                    Task { await player.setQuality(option) }
                    settings.preferredQuality = option
                    Haptics.selection()
                }
            }
        }
    }

    // MARK: Building blocks

    @ViewBuilder
    private func section<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: Metrics.Space.md) {
            Text(title)
                .font(Type.readoutSmall)
                .tracking(1.2)
                .foregroundStyle(Palette.textTertiary)

            VStack(alignment: .leading, spacing: 0) { content() }
                .padding(.horizontal, Metrics.Space.lg)
                .padding(.vertical, Metrics.Space.xs)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: Metrics.Radius.card, style: .continuous))
        }
    }

    private func row(
        title: String,
        note: String? = nil,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: Metrics.Space.sm) {
                Text(title)
                    .font(Type.body)
                    .foregroundStyle(Palette.textPrimary)

                if let note {
                    Text(note)
                        .font(Type.labelSmall)
                        .foregroundStyle(Palette.textTertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Palette.surfaceRaised, in: Capsule())
                }

                Spacer(minLength: 0)

                if isActive {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Palette.refract)
                }
            }
            .padding(.vertical, Metrics.Space.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
