import SwiftUI

/// A community post.
///
/// Posts are a mixed bag — text, image sets, polls, or a linked video — so the
/// card renders whichever parts are present rather than assuming a shape.
struct CommunityPostCard: View {
    let post: CommunityPost
    var onOpenVideo: (Video) -> Void

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.Space.md) {
            header

            if !post.text.isEmpty {
                Text(post.text)
                    .font(Type.body)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(isExpanded ? nil : 4)
                    .fixedSize(horizontal: false, vertical: true)
                    .onTapGesture { withAnimation(Motion.quick) { isExpanded.toggle() } }
            }

            if !post.imageURLs.isEmpty { images }
            if !post.pollChoices.isEmpty { poll }

            if let video = post.attachedVideo {
                Button { onOpenVideo(video) } label: {
                    VideoRow(video: video) { onOpenVideo(video) }
                        .allowsHitTesting(false)
                }
                .buttonStyle(.plain)
            }

            footer
        }
        .padding(Metrics.Space.lg)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Metrics.Radius.card, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(post.author), \(post.publishedText). \(post.text)")
    }

    private var header: some View {
        HStack(spacing: Metrics.Space.sm) {
            RemoteImage(url: post.authorAvatarURL, targetSize: CGSize(width: 80, height: 80)) {
                Circle().fill(Palette.surfaceRaised)
            }
            .frame(width: 32, height: 32)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 1) {
                Text(post.author)
                    .font(Type.labelSmall)
                    .foregroundStyle(Palette.textPrimary)
                Text(post.publishedText)
                    .font(Type.readoutSmall)
                    .foregroundStyle(Palette.textTertiary)
            }

            Spacer(minLength: 0)
        }
    }

    /// One image fills the card; several scroll horizontally.
    @ViewBuilder
    private var images: some View {
        if post.imageURLs.count == 1 {
            RemoteImage(url: post.imageURLs[0], targetSize: CGSize(width: 800, height: 800), contentMode: .fit) {
                ShimmerPlaceholder()
            }
            .frame(maxHeight: 380)
            .clipShape(RoundedRectangle(cornerRadius: Metrics.Radius.md, style: .continuous))
        } else {
            ScrollView(.horizontal) {
                HStack(spacing: Metrics.Space.sm) {
                    ForEach(Array(post.imageURLs.enumerated()), id: \.offset) { _, url in
                        RemoteImage(url: url, targetSize: CGSize(width: 600, height: 600)) {
                            ShimmerPlaceholder()
                        }
                        .frame(width: 240, height: 240)
                        .clipShape(RoundedRectangle(cornerRadius: Metrics.Radius.md, style: .continuous))
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    /// Choices are shown but not tappable — voting needs an authenticated
    /// write this app doesn't make, and a control that looks interactive but
    /// isn't would be worse than a plain list.
    private var poll: some View {
        VStack(alignment: .leading, spacing: Metrics.Space.sm) {
            ForEach(Array(post.pollChoices.enumerated()), id: \.offset) { _, choice in
                HStack {
                    Text(choice)
                        .font(Type.meta)
                        .foregroundStyle(Palette.textSecondary)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, Metrics.Space.md)
                .padding(.vertical, Metrics.Space.sm)
                .background(Palette.surfaceRaised, in: Capsule())
            }
        }
    }

    private var footer: some View {
        HStack(spacing: Metrics.Space.lg) {
            if !post.likeText.isEmpty {
                Label(post.likeText, systemImage: "hand.thumbsup")
                    .font(Type.readoutSmall)
                    .foregroundStyle(Palette.textTertiary)
            }
            if !post.replyText.isEmpty {
                Label(post.replyText, systemImage: "bubble.right")
                    .font(Type.readoutSmall)
                    .foregroundStyle(Palette.textTertiary)
            }
            Spacer(minLength: 0)
        }
    }
}
