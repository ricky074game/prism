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

        if DemoData.isEnabled {
            results = DemoData.videos
            return
        }

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

    /// Measured here rather than inherited: this is presented as a cover, so it
    /// owns the whole window and its own size is the authoritative one.
    @State private var layout = PrismLayout()

    var body: some View {
        GeometryReader { geo in
            content
                .onAppear { layout = PrismLayout(width: geo.size.width, height: geo.size.height) }
                .onChange(of: geo.size) { _, size in
                    layout = PrismLayout(width: size.width, height: size.height)
                }
                .environment(\.prismLayout, layout)
        }
    }

    /// Rows rather than cards: search is a scanning task, and two columns of
    /// compact rows keep more candidates on screen than one column of posters.
    @ViewBuilder
    private var results: some View {
        if layout.columns > 1 {
            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible(), spacing: layout.gutter, alignment: .top),
                    count: min(2, layout.columns)
                ),
                spacing: Metrics.Space.lg
            ) {
                ForEach(model.results) { video in row(video) }
            }
        } else {
            LazyVStack(spacing: Metrics.Space.lg) {
                ForEach(model.results) { video in row(video) }
            }
        }
    }

    private func row(_ video: Video) -> some View {
        VideoRow(video: video) {
            router.open(video)
            dismiss()
        }
    }

    private var content: some View {
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
                        results
                            .padding(layout.gutter)
                            .pageWidth(layout)
                    }
                    .scrollIndicators(.hidden)
                }
            }
            .background(Palette.ink.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
        .onAppear {
            if DemoData.isEnabled {
                model.query = "swift programming"
                model.search(model.query)
            } else {
                focused = true
            }
        }
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
        .frame(maxWidth: layout.maxContentWidth)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, layout.gutter)
        .padding(.vertical, Metrics.Space.md)
    }
}
