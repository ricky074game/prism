import SwiftUI

/// PRISM's signature control: a timeline that dispersed into its spectrum.
///
/// A plain scrubber tells you *where* you are. This one tells you *what is
/// ahead* — every sponsor, intro and self-promo in the video is drawn in place
/// as a band of colour, so the shape of the video is legible before you play it.
/// That is the whole thesis of the app rendered as one control.
///
/// Implementation notes, because this view is on the 120Hz path:
///
/// - The entire track is one `Canvas`. A ZStack of shapes would mean a separate
///   layer per segment and a layout pass per frame while dragging; `Canvas`
///   is a single draw call into one layer.
/// - It reads `progress` as a plain `Double`, not an `AVPlayer` observation, so
///   the owning view decides the update cadence.
/// - Drag state is local, so scrubbing never invalidates the player view.
struct SpectrumScrubber: View {
    /// 0…1 playhead position.
    let progress: Double
    /// 0…1 buffered-ahead position.
    let buffered: Double
    let duration: Double
    let segments: [SponsorSegment]
    /// Chapter boundaries in seconds, drawn as notches in the track.
    var chapters: [Double] = []

    let onScrub: (Double) -> Void
    let onScrubEnd: (Double) -> Void

    @State private var isDragging = false
    @State private var dragProgress: Double = 0
    @State private var lastHapticSegment: String?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Track height at rest and while held. The track thickens under the finger
    /// rather than growing a separate popover — the control you are touching
    /// should be the control that responds.
    private var trackHeight: CGFloat { isDragging ? 8 : 3.5 }
    private var shownProgress: Double { isDragging ? dragProgress : progress }

    var body: some View {
        VStack(spacing: Metrics.Space.sm) {
            if isDragging {
                readout
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
            }

            GeometryReader { geo in
                let w = geo.size.width

                ZStack(alignment: .leading) {
                    Canvas { ctx, size in
                        draw(in: &ctx, size: size)
                    }
                    .frame(height: trackHeight)
                    .clipShape(Capsule())
                    .frame(maxHeight: .infinity)

                    playhead(width: w)
                }
                .contentShape(Rectangle())
                .gesture(dragGesture(width: w))
            }
            .frame(height: 32)
        }
        .motion(Motion.quick, value: isDragging)
    }

    // MARK: Track

    private func draw(in ctx: inout GraphicsContext, size: CGSize) {
        let w = size.width
        let h = size.height

        // Unplayed track.
        ctx.fill(
            Path(CGRect(x: 0, y: 0, width: w, height: h)),
            with: .color(.white.opacity(0.18))
        )

        // Buffered-ahead. Sits between the track and the played fill so it reads
        // as "loaded but not reached".
        if buffered > 0 {
            ctx.fill(
                Path(CGRect(x: 0, y: 0, width: w * buffered, height: h)),
                with: .color(.white.opacity(0.28))
            )
        }

        // The spectrum. Drawn over the track but under the played fill, so
        // passed segments read as consumed rather than pending.
        if duration > 0 {
            for seg in segments where !seg.isFullVideo {
                let x = CGFloat(seg.start / duration) * w
                if seg.isPointOfInterest {
                    // A marker, not a range — 2pt tick.
                    ctx.fill(
                        Path(CGRect(x: x - 1, y: 0, width: 2, height: h)),
                        with: .color(seg.category.color)
                    )
                } else {
                    let segW = max(2, CGFloat(seg.duration / duration) * w)
                    ctx.fill(
                        Path(CGRect(x: x, y: 0, width: segW, height: h)),
                        with: .color(seg.category.color.opacity(0.95))
                    )
                }
            }
        }

        // Played fill — the refraction gradient.
        let playedW = w * shownProgress
        if playedW > 0 {
            ctx.fill(
                Path(CGRect(x: 0, y: 0, width: playedW, height: h)),
                with: .linearGradient(
                    Gradient(colors: [Palette.refract, Palette.disperse]),
                    startPoint: .zero,
                    endPoint: CGPoint(x: w, y: 0)
                )
            )
        }

        // Chapter notches, punched out of everything.
        if duration > 0, !chapters.isEmpty {
            for c in chapters where c > 0 && c < duration {
                let x = CGFloat(c / duration) * w
                ctx.blendMode = .destinationOut
                ctx.fill(Path(CGRect(x: x - 1, y: 0, width: 2, height: h)), with: .color(.black))
                ctx.blendMode = .normal
            }
        }
    }

    private func playhead(width: CGFloat) -> some View {
        Circle()
            .fill(.white)
            .frame(width: isDragging ? 16 : 11, height: isDragging ? 16 : 11)
            .shadow(color: Palette.refract.opacity(0.55), radius: isDragging ? 10 : 4)
            .offset(x: (width * shownProgress) - (isDragging ? 8 : 5.5))
            .allowsHitTesting(false)
    }

    // MARK: Read-out

    /// While scrubbing, the timestamp and — if the playhead is inside one — the
    /// name of the segment you're about to land in. Knowing you're about to drop
    /// into a sponsor is the point.
    private var readout: some View {
        let t = dragProgress * duration
        let seg = segments.first { !$0.isFullVideo && $0.contains(t) }

        return HStack(spacing: Metrics.Space.sm) {
            Text(t.timecode)
                .font(Type.readout)
                .foregroundStyle(Palette.textPrimary)

            if let seg {
                HStack(spacing: 4) {
                    Image(systemName: seg.category.icon).font(.system(size: 9, weight: .bold))
                    Text(seg.category.title).font(Type.labelSmall)
                }
                .foregroundStyle(seg.category.color)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(seg.category.color.opacity(0.16), in: Capsule())
            }

            Text(duration.timecode)
                .font(Type.readout)
                .foregroundStyle(Palette.textTertiary)
        }
        .padding(.horizontal, Metrics.Space.md)
        .padding(.vertical, Metrics.Space.sm)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.08)))
    }

    // MARK: Gesture

    private func dragGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { v in
                if !isDragging {
                    isDragging = true
                    Haptics.impact(.soft)
                }
                let p = min(max(0, v.location.x / width), 1)
                dragProgress = p
                hapticOnSegmentCrossing(at: p * duration)
                onScrub(p)
            }
            .onEnded { _ in
                onScrubEnd(dragProgress)
                isDragging = false
                lastHapticSegment = nil
                Haptics.impact(.rigid)
            }
    }

    /// A tick as the playhead enters or leaves a segment. You can feel the shape
    /// of the video without looking at the screen.
    private func hapticOnSegmentCrossing(at time: Double) {
        let current = segments.first { !$0.isFullVideo && $0.contains(time) }?.id
        if current != lastHapticSegment {
            if current != nil { Haptics.selection() }
            lastHapticSegment = current
        }
    }
}

// MARK: - Timecode

extension Double {
    /// `1:04:09` / `4:09` — hours only when there are hours.
    var timecode: String {
        guard isFinite, self >= 0 else { return "0:00" }
        let total = Int(self.rounded())
        let (h, m, s) = (total / 3600, (total % 3600) / 60, total % 60)
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
    }
}
