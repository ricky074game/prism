import SwiftUI

/// The Shorts tab.
///
/// Everything here lives in `ShortsFeed`, which the channel screen presents too
/// — the tab is just the discovery source pointed at it.
struct ShortsScreen: View {
    var body: some View {
        ShortsFeed(source: .discover)
    }
}

struct EmptyState: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: Metrics.Space.md) {
            Image(systemName: icon)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Palette.textTertiary)
            Text(title)
                .font(Type.title(17))
                .foregroundStyle(Palette.textPrimary)
            Text(message)
                .font(Type.meta)
                .foregroundStyle(Palette.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(Metrics.Space.huge)
    }
}
