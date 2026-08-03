import SwiftUI

/// Settings.
///
/// The SponsorBlock section is the reason this screen exists, so it leads. Each
/// category shows its spectrum colour next to a four-way action picker — the
/// same colours used on the scrubber, so the setting and its effect are
/// visibly the same object.
struct SettingsScreen: View {
    @Environment(Settings.self) private var settings
    @State private var session = AccountSession.shared
    @State private var auth = GoogleAuth.shared

    /// Says which of the two sign-ins are active, because "Signed in" alone
    /// would be ambiguous when they unlock different things.
    private var accountStatus: (title: String, detail: String) {
        switch (session.isSignedIn, auth.isSignedIn) {
        case (true, true): ("Signed in", "YouTube session and Google account")
        case (true, false): ("Signed in", "YouTube session only")
        case (false, true): ("Partly signed in", "Google account only — no age-restricted videos")
        case (false, false): ("Not signed in", "Sign in for history and age-restricted videos")
        }
    }

    var body: some View {
        @Bindable var settings = settings

        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.Space.xxl) {
                section("ACCOUNT") {
                    NavigationLink {
                        AccountScreen()
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(accountStatus.title)
                                    .font(Type.body)
                                    .foregroundStyle(Palette.textPrimary)
                                Text(accountStatus.detail)
                                    .font(Type.labelSmall)
                                    .foregroundStyle(Palette.textTertiary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Palette.textTertiary)
                        }
                        .padding(.vertical, Metrics.Space.md)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                section("PLAYBACK") {
                    row("Preferred quality") {
                        Menu {
                            ForEach(VideoQuality.allCases) { q in
                                Button(q.title) { settings.preferredQuality = q }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(settings.preferredQuality.title).font(Type.metaEmphasis)
                                Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .bold))
                            }
                            .foregroundStyle(Palette.refract)
                        }
                    }
                    toggleRow("Ambient glow", isOn: $settings.ambientGlow,
                              note: "Lights the interface with the video's colours.")
                    toggleRow("Haptics", isOn: $settings.hapticsEnabled)
                    toggleRow("Show Shorts", isOn: $settings.showShorts)
                }

                section("SPONSORBLOCK") {
                    toggleRow("Skip segments", isOn: $settings.sponsorBlockEnabled,
                              note: "Community-submitted segment data from sponsor.ajay.app.")

                    if settings.sponsorBlockEnabled {
                        ForEach(SegmentCategory.allCases, id: \.self) { category in
                            categoryRow(category, settings: settings)
                        }
                    }
                }

                HelperServerSection()

                section("ABOUT") {
                    row("Version") {
                        Text("1.0").font(Type.meta).foregroundStyle(Palette.textTertiary)
                    }
                    VStack(alignment: .leading, spacing: Metrics.Space.sm) {
                        Text("Prism is a personal client. It has no downloads, no ads, and sends no analytics anywhere.")
                            .font(Type.meta)
                            .foregroundStyle(Palette.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, Metrics.Space.xs)
                }
            }
            .padding(Metrics.gutter)
            .padding(.bottom, Metrics.Space.huge * 2)
        }
        .scrollIndicators(.hidden)
        .background(Palette.ink.ignoresSafeArea())
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Building blocks

    @ViewBuilder
    private func section<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: Metrics.Space.md) {
            Text(title)
                .font(Type.readoutSmall)
                .tracking(1.2)
                .foregroundStyle(Palette.textTertiary)

            VStack(spacing: 0) { content() }
                .padding(.horizontal, Metrics.Space.lg)
                .padding(.vertical, Metrics.Space.xs)
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: Metrics.Radius.card, style: .continuous))
        }
    }

    private func row<C: View>(_ title: String, @ViewBuilder trailing: () -> C) -> some View {
        HStack {
            Text(title).font(Type.body).foregroundStyle(Palette.textPrimary)
            Spacer()
            trailing()
        }
        .padding(.vertical, Metrics.Space.md)
    }

    private func toggleRow(_ title: String, isOn: Binding<Bool>, note: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Toggle(isOn: isOn) {
                Text(title).font(Type.body).foregroundStyle(Palette.textPrimary)
            }
            .tint(Palette.refract)

            if let note {
                Text(note)
                    .font(Type.labelSmall)
                    .foregroundStyle(Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, Metrics.Space.md)
    }

    private func categoryRow(_ category: SegmentCategory, settings: Settings) -> some View {
        HStack(spacing: Metrics.Space.md) {
            Circle()
                .fill(category.color)
                .frame(width: 8, height: 8)

            Text(category.title)
                .font(Type.body)
                .foregroundStyle(Palette.textPrimary)

            Spacer()

            Menu {
                ForEach(SegmentAction.allCases, id: \.self) { action in
                    Button(action.title) { settings.categoryActions[category] = action }
                }
            } label: {
                HStack(spacing: 4) {
                    Text((settings.categoryActions[category] ?? category.defaultAction).title)
                        .font(Type.labelSmall)
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 8, weight: .bold))
                }
                .foregroundStyle(Palette.textSecondary)
                .padding(.horizontal, Metrics.Space.sm + 2)
                .padding(.vertical, 5)
                .background(Palette.surfaceRaised, in: Capsule())
            }
        }
        .padding(.vertical, Metrics.Space.sm + 2)
    }
}
