import SwiftUI

/// The video description, with chapters promoted to tappable rows.
///
/// Chapters are the only part of a description most people ever want, so they're
/// lifted to the top as real controls rather than left as plain text that
/// happens to contain numbers.
struct DescriptionSheet: View {
    let source: PlaybackSource
    let onSeek: (Double) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Metrics.Space.xl) {
                    header

                    if !source.chapters.isEmpty {
                        chapters
                    }

                    if let description = source.description, !description.isEmpty {
                        Text(description)
                            .font(Type.body)
                            .foregroundStyle(Palette.textSecondary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(Metrics.gutter)
                .padding(.bottom, Metrics.Space.huge)
            }
            .scrollIndicators(.hidden)
            .background(Palette.ink.ignoresSafeArea())
            .navigationTitle("Description")
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

    private var header: some View {
        VStack(alignment: .leading, spacing: Metrics.Space.sm) {
            Text(source.title)
                .font(Type.cardTitleLarge)
                .foregroundStyle(Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: Metrics.Space.sm) {
                Text(source.author)
                    .font(Type.metaEmphasis)
                    .foregroundStyle(Palette.textSecondary)

                if source.viewCount > 0 {
                    Circle().fill(Palette.textTertiary).frame(width: 3, height: 3)
                    Text("\(source.viewCount.abbreviated) views")
                        .font(Type.meta)
                        .foregroundStyle(Palette.textTertiary)
                }
            }
        }
    }

    private var chapters: some View {
        VStack(alignment: .leading, spacing: Metrics.Space.md) {
            Text("CHAPTERS")
                .font(Type.readoutSmall)
                .tracking(1.2)
                .foregroundStyle(Palette.textTertiary)

            VStack(spacing: 0) {
                ForEach(source.chapters) { chapter in
                    Button {
                        onSeek(chapter.start)
                        dismiss()
                    } label: {
                        HStack(spacing: Metrics.Space.md) {
                            Text(chapter.start.timecode)
                                .font(Type.readout)
                                .foregroundStyle(Palette.disperse)
                                .frame(width: 56, alignment: .leading)

                            Text(chapter.title)
                                .font(Type.body)
                                .foregroundStyle(Palette.textPrimary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)

                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, Metrics.Space.md)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if chapter.id != source.chapters.last?.id {
                        Divider().overlay(Palette.line)
                    }
                }
            }
            .padding(.horizontal, Metrics.Space.lg)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: Metrics.Radius.card, style: .continuous))
        }
    }
}

extension Int {
    /// `1.2M`, `340K` — matches how YouTube writes counts, so the two don't
    /// disagree on the same screen.
    var abbreviated: String {
        let n = Double(self)
        switch self {
        case 1_000_000_000...:
            return String(format: "%.1fB", n / 1_000_000_000)
        case 1_000_000...:
            return String(format: "%.1fM", n / 1_000_000)
        case 1_000...:
            return String(format: "%.0fK", n / 1_000)
        default:
            return String(self)
        }
    }
}
