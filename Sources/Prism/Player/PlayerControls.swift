import SwiftUI

/// The overlay controls.
///
/// Controls auto-hide after three seconds of playback and come back on tap. The
/// scrubber is exempt from the fade while it's being dragged, because hiding the
/// thing under the user's finger is never right.
struct PlayerControls: View {
    let video: Video

    @Environment(PlayerEngine.self) private var player
    @Environment(Router.self) private var router

    @State private var isVisible = true
    @State private var hideTask: Task<Void, Never>?
    @State private var showQuality = false

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

            VStack {
                topBar
                Spacer()
                centreTransport
                Spacer()
                bottomBar
            }
            .opacity(isVisible ? 1 : 0)
        }
        .contentShape(Rectangle())
        .onTapGesture { toggle() }
        .motion(Motion.standard, value: isVisible)
        .onAppear { scheduleHide() }
        .onChange(of: player.isPlaying) { _, playing in
            if playing { scheduleHide() } else { show() }
        }
        .sheet(isPresented: $showQuality) {
            QualitySheet()
                .presentationDetents([.medium])
                .presentationBackground(.ultraThinMaterial)
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

            Button { showQuality = true } label: {
                HStack(spacing: 5) {
                    Text(player.currentQuality.title).font(Type.labelSmall)
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 8, weight: .bold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(.black.opacity(0.3), in: Capsule())
            }
            .accessibilityLabel("Video quality")
        }
        .padding(Metrics.Space.md)
    }

    /// Three controls, evenly weighted: back ten, play/pause, forward ten.
    private var centreTransport: some View {
        HStack(spacing: Metrics.Space.huge) {
            transportButton("gobackward.10", size: 22) { player.skip(by: -10) }

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

            transportButton("goforward.10", size: 22) { player.skip(by: 10) }
        }
    }

    private func transportButton(_ icon: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button {
            action()
            Haptics.impact(.light)
        } label: {
            Image(systemName: icon)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
        }
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
