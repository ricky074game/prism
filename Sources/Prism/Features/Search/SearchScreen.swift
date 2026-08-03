import SwiftUI

@MainActor
@Observable
final class SearchModel {
    var query = ""
    private(set) var results: [Video] = []
    private(set) var isSearching = false
    private var task: Task<Void, Never>?

    /// Debounced so typing doesn't fire a request per keystroke.
    func search(_ text: String) {
        task?.cancel()
        guard text.count >= 2 else {
            results = []
            isSearching = false
            return
        }

        task = Task {
            try? await Task.sleep(for: .milliseconds(280))
            guard !Task.isCancelled else { return }

            isSearching = true
            if let page = try? await FeedRepository.shared.search(text), !Task.isCancelled {
                results = page.videos
            }
            isSearching = false
        }
    }
}

struct SearchScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(Router.self) private var router
    @State private var model = SearchModel()
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchField

                if model.results.isEmpty && !model.query.isEmpty && !model.isSearching {
                    EmptyState(
                        icon: "magnifyingglass",
                        title: "Nothing found",
                        message: "Try a different search."
                    )
                    .frame(maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: Metrics.Space.lg) {
                            ForEach(model.results) { video in
                                VideoRow(video: video) {
                                    router.open(video)
                                    dismiss()
                                }
                            }
                        }
                        .padding(Metrics.gutter)
                    }
                    .scrollIndicators(.hidden)
                }
            }
            .background(Palette.ink.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
        .onAppear { focused = true }
    }

    private var searchField: some View {
        HStack(spacing: Metrics.Space.md) {
            HStack(spacing: Metrics.Space.sm) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Palette.textTertiary)

                TextField("Search", text: $model.query)
                    .font(Type.body)
                    .foregroundStyle(Palette.textPrimary)
                    .focused($focused)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onChange(of: model.query) { _, new in model.search(new) }

                if !model.query.isEmpty {
                    Button {
                        model.query = ""
                        model.search("")
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(Palette.textTertiary)
                    }
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, Metrics.Space.md)
            .padding(.vertical, Metrics.Space.md - 2)
            .background(Palette.surface, in: Capsule())

            Button("Cancel") { dismiss() }
                .font(Type.label)
                .foregroundStyle(Palette.textSecondary)
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.vertical, Metrics.Space.md)
    }
}
