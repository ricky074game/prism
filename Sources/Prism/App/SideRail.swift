import SwiftUI

/// The iPad navigation rail.
///
/// A bottom bar on a 13" screen puts every navigation control an arm's length
/// from where the eye is, and wastes the one dimension iPads have to spare. The
/// rail is the same four destinations rotated into the margin, and it takes over
/// the wordmark and the search/settings buttons from `PrismHeader` — which is
/// why that header hides itself at these widths rather than duplicating them.
struct SideRail: View {
    @Binding var selection: Router.Tab
    let tabs: [Router.Tab]

    static let width: CGFloat = 92

    @Namespace private var indicator
    @State private var showSearch = false
    @State private var showSettings = false

    var body: some View {
        VStack(spacing: Metrics.Space.xs) {
            mark
                .padding(.top, Metrics.Space.xl)
                .padding(.bottom, Metrics.Space.xl)

            ForEach(tabs) { tab in
                item(tab)
            }

            Spacer(minLength: Metrics.Space.xl)

            utility(icon: "magnifyingglass", label: "Search") { showSearch = true }
            utility(icon: "slider.horizontal.3", label: "Settings") { showSettings = true }
        }
        .padding(.bottom, Metrics.Space.lg)
        .frame(width: Self.width)
        .frame(maxHeight: .infinity)
        .background {
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                Rectangle().fill(Palette.ink.opacity(0.6))
            }
            .ignoresSafeArea()
        }
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Palette.line)
                .frame(width: 0.5)
                .ignoresSafeArea()
        }
        .fullScreenCover(isPresented: $showSearch) { SearchScreen() }
        .sheet(isPresented: $showSettings) {
            NavigationStack { SettingsScreen() }
        }
    }

    private var mark: some View {
        VStack(spacing: 6) {
            PrismMark().frame(width: 26, height: 26)
            Text("PRISM")
                .font(Type.display(10))
                .tracking(1.4)
                .foregroundStyle(Palette.textSecondary)
        }
        .accessibilityHidden(true)
    }

    private func item(_ tab: Router.Tab) -> some View {
        let isSelected = selection == tab

        return Button {
            guard selection != tab else { return }
            selection = tab
            Haptics.selection()
        } label: {
            VStack(spacing: 5) {
                ZStack {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .fill(Palette.refract.opacity(0.16))
                            .matchedGeometryEffect(id: "railIndicator", in: indicator)
                            .frame(width: 52, height: 34)
                    }
                    Image(systemName: isSelected ? tab.selectedIcon : tab.icon)
                        .font(.system(size: 19, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? Palette.refract : Palette.textTertiary)
                        .symbolEffect(.bounce, value: isSelected)
                }
                .frame(height: 34)

                Text(tab.title)
                    .font(Type.labelSmall)
                    .foregroundStyle(isSelected ? Palette.textPrimary : Palette.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Metrics.Space.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .motion(Motion.quick, value: isSelected)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    private func utility(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Palette.textSecondary)
                    .frame(width: 42, height: 42)
                    .background(Palette.surface, in: Circle())
                Text(label)
                    .font(Type.labelSmall)
                    .foregroundStyle(Palette.textTertiary)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, Metrics.Space.sm)
        .accessibilityLabel(label)
    }
}
