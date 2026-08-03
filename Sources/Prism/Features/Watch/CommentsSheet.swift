import SwiftUI

@MainActor
@Observable
final class CommentsModel {
    private(set) var comments: [Comment] = []
    private(set) var totalText: String?
    private(set) var isLoading = false
    private(set) var error: String?
    private(set) var expandedReplies: [String: [Comment]] = [:]
    private(set) var loadingReplies: Set<String> = []

    var sort: CommentService.Sort = .top

    private var continuation: String?
    private var isPaging = false
    private var videoID: String?

    func load(videoID: String) async {
        self.videoID = videoID
        isLoading = true
        error = nil
        defer { isLoading = false }

        if DemoData.isEnabled {
            comments = DemoData.comments
            totalText = "4,281"
            return
        }

        do {
            let page = try await CommentService.shared.comments(for: videoID, sort: sort)
            comments = page.comments
            continuation = page.continuation
            totalText = page.totalText
        } catch {
            self.error = "Couldn't load comments."
        }
    }

    func changeSort(_ new: CommentService.Sort) async {
        guard new != sort, let videoID else { return }
        sort = new
        comments = []
        expandedReplies = [:]
        await load(videoID: videoID)
    }

    func loadMoreIfNeeded(at comment: Comment) async {
        guard let continuation, !isPaging,
              let index = comments.firstIndex(of: comment),
              index >= comments.count - 5
        else { return }

        isPaging = true
        defer { isPaging = false }

        if let page = try? await CommentService.shared.more(continuation: continuation) {
            comments.append(contentsOf: page.comments)
            self.continuation = page.continuation
        }
    }

    func toggleReplies(for comment: Comment) async {
        if expandedReplies[comment.id] != nil {
            expandedReplies[comment.id] = nil
            return
        }
        guard let token = comment.repliesToken else { return }

        loadingReplies.insert(comment.id)
        defer { loadingReplies.remove(comment.id) }

        if let page = try? await CommentService.shared.replies(token: token) {
            // The thread's own comment comes back with the replies; drop it so
            // it isn't shown twice.
            expandedReplies[comment.id] = page.comments.filter { $0.id != comment.id }
        }
    }
}

/// Comments.
///
/// Presented as a sheet rather than inline below the video, so the video stays
/// on screen while reading — the thing people actually do.
struct CommentsSheet: View {
    let video: Video

    @Environment(\.dismiss) private var dismiss
    @State private var model = CommentsModel()

    var body: some View {
        NavigationStack {
            Group {
                if model.isLoading && model.comments.isEmpty {
                    ProgressView().tint(Palette.refract)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if model.comments.isEmpty {
                    EmptyState(
                        icon: "bubble.left.and.bubble.right",
                        title: model.error == nil ? "No comments" : "Couldn't load comments",
                        message: model.error == nil
                            ? "Comments are turned off for this video."
                            : "Check your connection and try again."
                    )
                    .frame(maxHeight: .infinity)
                } else {
                    list
                }
            }
            .background(Palette.ink.ignoresSafeArea())
            .navigationTitle(model.totalText.map { "\($0) comments" } ?? "Comments")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { sortMenu }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(Type.label)
                        .foregroundStyle(Palette.refract)
                }
            }
        }
        .task { await model.load(videoID: video.id) }
    }

    private var sortMenu: some View {
        Menu {
            ForEach(CommentService.Sort.allCases) { option in
                Button {
                    Task { await model.changeSort(option) }
                } label: {
                    if model.sort == option {
                        Label(option.title, systemImage: "checkmark")
                    } else {
                        Text(option.title)
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "arrow.up.arrow.down").font(.system(size: 11, weight: .semibold))
                Text(model.sort == .top ? "Top" : "Newest").font(Type.labelSmall)
            }
            .foregroundStyle(Palette.textSecondary)
        }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Metrics.Space.xl) {
                ForEach(model.comments) { comment in
                    VStack(alignment: .leading, spacing: Metrics.Space.md) {
                        CommentRow(comment: comment)
                            .task { await model.loadMoreIfNeeded(at: comment) }

                        if comment.replyCount > 0, comment.repliesToken != nil {
                            repliesControl(for: comment)
                        }

                        if let replies = model.expandedReplies[comment.id] {
                            VStack(alignment: .leading, spacing: Metrics.Space.lg) {
                                ForEach(replies) { reply in
                                    CommentRow(comment: reply, isReply: true)
                                }
                            }
                            .padding(.leading, Metrics.Space.xxl)
                            .transition(.opacity)
                        }
                    }
                }
            }
            .padding(Metrics.gutter)
            .padding(.bottom, Metrics.Space.huge)
        }
        .scrollIndicators(.hidden)
    }

    private func repliesControl(for comment: Comment) -> some View {
        Button {
            Task { await model.toggleReplies(for: comment) }
        } label: {
            HStack(spacing: 6) {
                if model.loadingReplies.contains(comment.id) {
                    ProgressView().controlSize(.mini).tint(Palette.disperse)
                } else {
                    Image(systemName: model.expandedReplies[comment.id] != nil ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                }
                Text("\(comment.replyCount) \(comment.replyCount == 1 ? "reply" : "replies")")
                    .font(Type.labelSmall)
            }
            .foregroundStyle(Palette.disperse)
            .padding(.horizontal, Metrics.Space.md)
            .padding(.vertical, 6)
            .background(Palette.disperse.opacity(0.1), in: Capsule())
        }
        .padding(.leading, 46)
        .buttonStyle(.plain)
    }
}

struct CommentRow: View {
    let comment: Comment
    var isReply = false

    var body: some View {
        HStack(alignment: .top, spacing: Metrics.Space.md) {
            avatar

            VStack(alignment: .leading, spacing: 5) {
                header

                Text(comment.text)
                    .font(Type.body)
                    .foregroundStyle(Palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)

                footer
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(comment.authorName): \(comment.text)")
    }

    private var avatar: some View {
        RemoteImage(url: comment.authorAvatarURL, targetSize: CGSize(width: 96, height: 96)) {
            Circle().fill(Palette.surfaceRaised)
        }
        .frame(width: isReply ? 26 : 34, height: isReply ? 26 : 34)
        .clipShape(Circle())
    }

    private var header: some View {
        HStack(spacing: 5) {
            if comment.isPinned {
                Label("Pinned", systemImage: "pin.fill")
                    .font(Type.readoutSmall)
                    .foregroundStyle(Palette.textTertiary)
                    .labelStyle(.titleAndIcon)
            }

            Text(comment.authorName)
                .font(Type.labelSmall)
                // The creator's own comments get the accent, which is how you
                // spot them in a thread of hundreds.
                .foregroundStyle(comment.isCreator ? Palette.refract : Palette.textSecondary)
                .padding(.horizontal, comment.isCreator ? 6 : 0)
                .padding(.vertical, comment.isCreator ? 2 : 0)
                .background {
                    if comment.isCreator {
                        Capsule().fill(Palette.refract.opacity(0.14))
                    }
                }

            if comment.isVerified {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(Palette.textTertiary)
            }

            Text(comment.publishedText)
                .font(Type.readoutSmall)
                .foregroundStyle(Palette.textTertiary)
        }
    }

    private var footer: some View {
        HStack(spacing: Metrics.Space.lg) {
            HStack(spacing: 5) {
                Image(systemName: "hand.thumbsup").font(.system(size: 11))
                if !comment.likeText.isEmpty {
                    Text(comment.likeText).font(Type.readoutSmall)
                }
            }
            .foregroundStyle(Palette.textTertiary)

            Image(systemName: "hand.thumbsdown")
                .font(.system(size: 11))
                .foregroundStyle(Palette.textTertiary)

            if comment.isHearted {
                Image(systemName: "heart.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.live)
            }
        }
        .padding(.top, 2)
    }
}
