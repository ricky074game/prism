import SwiftUI

/// The overlay controls.
///
/// Controls auto-hide after three seconds of playback and come back on tap. The
/// scrubber is exempt from the fade while it's being dragged, because hiding the
/// thing under the user's finger is never right.
struct PlayerControls: View {
    let video: Video
    @Binding var isFullscreen: Bool
    let pip: PictureInPictureController

    @Environment(PlayerEngine.self) private var player
    @Environment(Router.self) private var router

    @Environment(Settings.self) private var settings

    @State private var isVisible = true
    @State private var hideTask: Task<Void, Never>?
    @State private var showOptions = false
    /// Non-zero briefly after a double-tap, to show the ripple. Sign gives the
    /// direction.
    @State private var seekFlash = 0

    var body: some View {
        ZStack {
            // Scrim: only under the controls, so the middle of the frame stays
            // clear of the video.
            LinearGradient(
                colors: [.black.opacity(0.55), .clear, .clear, .black.opacity(0.65)],
                startPoint: .top, endPoint: .bottom
            )
            .opacity(isVisible ? 1 : 0)
            .allowsHitTesting(false)

            // Double-tap zones sit *under* the controls so the buttons still win
            // a hit. Each side is its own gesture target — a single gesture on
            // the whole frame can't tell left from right.
            HStack(spacing: 0) {
                seekZone(direction: -1)
                seekZone(direction: 1)
            }

            VStack {
                topBar
                Spacer()
                centreTransport
                Spacer()
                bottomBar
            }
            .opacity(isVisible ? 1 : 0)
            // Hidden controls must not swallow taps meant for the seek zones.
            .allowsHitTesting(isVisible)

            seekRipple
        }
        .motion(Motion.standard, value: isVisible)
        .onAppear { scheduleHide() }
        .onChange(of: player.isPlaying) { _, playing in
            if playing { scheduleHide() } else { show() }
        }
        .sheet(isPresented: $showOptions) {
            PlayerOptionsSheet()
                .presentationDetents([.medium, .large])
        }
    }

    // MARK: Double-tap seek

    /// Half the frame. A single tap toggles the controls, a double-tap seeks by
    /// the interval chosen in Settings.
    private func seekZone(direction: Int) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture(count: 2) {
                let delta = Double(direction * settings.seekInterval)
                player.skip(by: delta)
                Haptics.impact(.medium)
                withAnimation(Motion.quick) { seekFlash = direction }
                Task {
                    try? await Task.sleep(for: .milliseconds(550))
                    withAnimation(Motion.quick) { seekFlash = 0 }
                }
                cancelHide()
                scheduleHide()
            }
            .onTapGesture { toggle() }
    }

    @ViewBuilder
    private var seekRipple: some View {
        if seekFlash != 0 {
            HStack(spacing: 0) {
                if seekFlash > 0 { Spacer() }
                VStack(spacing: 6) {
                    Image(systemName: seekFlash > 0 ? "goforward" : "gobackward")
                        .font(.system(size: 30, weight: .medium))
                    Text("\(settings.seekInterval)s")
                        .font(Type.readout)
                }
                .foregroundStyle(.white)
                .frame(width: 110, height: 110)
                .background(.black.opacity(0.35), in: Circle())
                if seekFlash < 0 { Spacer() }
            }
            .padding(.horizontal, Metrics.Space.xl)
            .transition(.opacity.combined(with: .scale(scale: 0.8)))
            .allowsHitTesting(false)
        }
    }

    // MARK: Bars

    private var topBar: some View {
        HStack(spacing: Metrics.Space.md) {
            Button {
                withAnimation(Motion.hero) { router.isWatchExpanded = false }
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(.black.opacity(0.3), in: Circle())
            }
            .accessibilityLabel("Minimise player")

            Spacer()

            // Only shown when the video actually has captions, so the control
            // never lies about what's available.
            if !player.captionOptions.isEmpty {
                Button {
                    let isOn = player.activeCaption?.languageCode != nil
                    if isOn {
                        player.selectCaption(.off)
                    } else if let first = player.captionOptions.first(where: { $0.languageCode != nil }) {
                        player.selectCaption(first)
                    }
                    Haptics.selection()
                } label: {
                    Image(systemName: player.activeCaption?.languageCode != nil
                          ? "captions.bubble.fill" : "captions.bubble")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(.black.opacity(0.3), in: Circle())
                }
                .accessibilityLabel(player.activeCaption?.languageCode != nil
                                    ? "Turn captions off" : "Turn captions on")
            }

            // Only offered once the layer actually has video — before that the
            // system would refuse to start and the button would look broken.
            if pip.isPossible {
                Button {
                    pip.toggle()
                    Haptics.impact(.medium)
                } label: {
                    Image(systemName: "pip.enter")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(.black.opacity(0.3), in: Circle())
                }
                .accessibilityLabel("Picture in Picture")
            }

            Button { showOptions = true } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(.black.opacity(0.3), in: Circle())
            }
            .accessibilityLabel("Playback options")
        }
        .padding(Metrics.Space.md)
    }

    /// Three controls, evenly weighted: back ten, play/pause, forward ten.
    private var centreTransport: some View {
        HStack(spacing: Metrics.Space.huge) {
            // The glyph follows the configured interval — SF Symbols ship
            // dedicated 5/10/15/30/45/60 variants, so the icon states the real
            // number instead of always claiming 10.
            transportButton("gobackward.\(settings.seekInterval)", fallback: "gobackward", size: 22) {
                player.skip(by: -Double(settings.seekInterval))
            }

            Button {
                player.togglePlayPause()
                Haptics.impact(.medium)
            } label: {
                ZStack {
                    Circle().fill(.black.opacity(0.34))
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(.white)
                        .contentTransition(.symbolEffect(.replace))
                        .offset(x: player.isPlaying ? 0 : 2)
                }
                .frame(width: 66, height: 66)
            }
            .accessibilityLabel(player.isPlaying ? "Pause" : "Play")

            transportButton("goforward.\(settings.seekInterval)", fallback: "goforward", size: 22) {
                player.skip(by: Double(settings.seekInterval))
            }
        }
    }

    private func transportButton(
        _ icon: String,
        fallback: String,
        size: CGFloat,
        action: @escaping () -> Void
    ) -> some View {
        // An interval with no matching symbol would otherwise render as a blank
        // square.
        let name = UIImage(systemName: icon) != nil ? icon : fallback
        return Button {
            action()
            Haptics.impact(.light)
        } label: {
            Image(systemName: name)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
        }
        .accessibilityLabel("\(fallback == "goforward" ? "Forward" : "Back") \(settings.seekInterval) seconds")
    }

    private var bottomBar: some View {
        VStack(spacing: Metrics.Space.xs) {
            SpectrumScrubber(
                progress: player.progress,
                buffered: player.bufferedProgress,
                duration: player.duration,
                segments: player.segments,
                chapters: player.chapters.map(\.start),
                onScrub: { _ in cancelHide() },
                onScrubEnd: { p in
                    player.seek(to: p * player.duration)
                    scheduleHide()
                }
            )

            HStack(spacing: Metrics.Space.sm) {
                Text(player.currentTime.timecode)
                    .font(Type.readout)
                    .foregroundStyle(.white)

                if let chapter = player.currentChapter {
                    Text(chapter.title)
                        .font(Type.labelSmall)
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(1)
                        .transition(.opacity)
                }

                Spacer(minLength: 0)

                Text(player.duration.timecode)
                    .font(Type.readout)
                    .foregroundStyle(.white.opacity(0.6))

                Button {
                    withAnimation(Motion.hero) { isFullscreen.toggle() }
                    Haptics.impact(.medium)
                } label: {
                    Image(systemName: isFullscreen
                          ? "arrow.down.right.and.arrow.up.left"
                          : "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                }
                .accessibilityLabel(isFullscreen ? "Exit full screen" : "Full screen")
            }
            .motion(Motion.quick, value: player.currentChapter?.id)
        }
        .padding(.horizontal, Metrics.Space.lg)
        .padding(.bottom, Metrics.Space.md)
    }

    // MARK: Visibility

    private func toggle() {
        if isVisible { hide() } else { show(); scheduleHide() }
    }

    private func show() {
        hideTask?.cancel()
        isVisible = true
    }

    private func hide() {
        hideTask?.cancel()
        isVisible = false
    }

    private func cancelHide() {
        hideTask?.cancel()
        isVisible = true
    }

    private func scheduleHide() {
        hideTask?.cancel()
        guard player.isPlaying else { return }
        // Screenshot runs keep the controls up — the scrubber is the thing
        // worth photographing.
        guard !DemoData.isEnabled else { return }
        hideTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            isVisible = false
        }
    }
}

/// Quality picker.
struct QualitySheet: View {
    @Environment(PlayerEngine.self) private var player
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Quality")
                .font(Type.title(19))
                .foregroundStyle(Palette.textPrimary)
                .padding(.horizontal, Metrics.gutter)
                .padding(.vertical, Metrics.Space.lg)

            ForEach(VideoQuality.allCases) { quality in
                Button {
                    Task { await player.setQuality(quality) }
                    dismiss()
                } label: {
                    HStack {
                        Text(quality.title)
                            .font(Type.body)
                            .foregroundStyle(Palette.textPrimary)

                        if let note = quality.note {
                            Text(note)
                                .font(Type.labelSmall)
                                .foregroundStyle(Palette.textTertiary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Palette.surface, in: Capsule())
                        }

                        Spacer()

                        if player.currentQuality == quality {
                            Image(systemName: "checkmark")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(Palette.refract)
                        }
                    }
                    .padding(.horizontal, Metrics.gutter)
                    .padding(.vertical, Metrics.Space.md)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            Spacer()
        }
        .background(Palette.ink.opacity(0.6))
    }
}
