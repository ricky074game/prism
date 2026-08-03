import SwiftUI

/// Account sign-in.
///
/// Two sign-ins exist and they do different things, which is confusing enough
/// that the screen explains it rather than hiding it behind one button:
///
/// - **YouTube session** (cookies) — lifts the age gate, and makes history,
///   Watch Later and the home feed personal.
/// - **Google account** (OAuth) — subscriptions list, liking, playlist edits.
///
/// Most people want the first. It is also the one with real risk attached, so
/// that risk is stated on the screen and not buried.
struct AccountScreen: View {
    @State private var session = AccountSession.shared
    @State private var auth = GoogleAuth.shared
    @State private var showSignOutConfirm = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.Space.xxl) {
                youtubeSession
                googleAccount
                risk
            }
            .padding(Metrics.gutter)
            .padding(.bottom, Metrics.Space.huge)
        }
        .scrollIndicators(.hidden)
        .background(Palette.ink.ignoresSafeArea())
        .navigationTitle("Account")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Sign out of YouTube?", isPresented: $showSignOutConfirm, titleVisibility: .visible) {
            Button("Sign out", role: .destructive) {
                session.signOut()
            }
        } message: {
            Text("Age-restricted videos, history and Watch Later will stop working.")
        }
    }

    // MARK: Sections

    private var youtubeSession: some View {
        section(
            "YOUTUBE SESSION",
            note: "Unlocks age-restricted videos, your watch history, Watch Later, and a home feed based on what you actually watch."
        ) {
            if session.isSignedIn {
                statusRow(
                    icon: "checkmark.circle.fill",
                    tint: Palette.success,
                    title: "Signed in",
                    detail: session.accountName ?? "Your YouTube session is active."
                )

                Button(role: .destructive) {
                    showSignOutConfirm = true
                } label: {
                    Text("Sign out")
                        .font(Type.label)
                        .foregroundStyle(Palette.live)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, Metrics.Space.md)
                }
            } else if let code = session.pendingCode {
                deviceCodePanel(code)
            } else {
                Button {
                    Task { await session.beginSignIn() }
                } label: {
                    Text("Sign in to YouTube")
                        .font(Type.label)
                        .foregroundStyle(Palette.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Metrics.Space.md)
                        .background(Palette.refractGradient, in: Capsule())
                }
                .padding(.vertical, Metrics.Space.sm)
            }

            if let error = session.error {
                Text(error)
                    .font(Type.labelSmall)
                    .foregroundStyle(Palette.warning)
                    .padding(.bottom, Metrics.Space.md)
            }
        }
    }

    private var googleAccount: some View {
        section(
            "GOOGLE ACCOUNT",
            note: "Needed to read your subscription list and to like or subscribe from here."
        ) {
            if auth.isSignedIn {
                statusRow(
                    icon: "checkmark.circle.fill",
                    tint: Palette.success,
                    title: "Connected",
                    detail: auth.account?.email ?? "Signed in"
                )
                Button(role: .destructive) {
                    auth.signOut()
                } label: {
                    Text("Disconnect")
                        .font(Type.label)
                        .foregroundStyle(Palette.live)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, Metrics.Space.md)
                }
            } else if auth.isConfigured {
                Button {
                    Task { await auth.signIn() }
                } label: {
                    HStack(spacing: Metrics.Space.sm) {
                        if auth.isAuthenticating {
                            ProgressView().controlSize(.small).tint(Palette.textPrimary)
                        }
                        Text(auth.isAuthenticating ? "Signing in…" : "Connect Google account")
                            .font(Type.label)
                    }
                    .foregroundStyle(Palette.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Metrics.Space.md)
                    .background(Palette.surfaceRaised, in: Capsule())
                }
                .disabled(auth.isAuthenticating)
                .padding(.vertical, Metrics.Space.sm)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Not set up in this build")
                        .font(Type.metaEmphasis)
                        .foregroundStyle(Palette.textSecondary)
                    Text("Add a Google OAuth client ID in Secrets.swift to enable it. The YouTube session above works without this.")
                        .font(Type.labelSmall)
                        .foregroundStyle(Palette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, Metrics.Space.md)
            }
        }
    }

    /// Stated plainly rather than buried. Holding a Google session is a real
    /// trade-off and the user should make it knowingly.
    private var risk: some View {
        VStack(alignment: .leading, spacing: Metrics.Space.sm) {
            Label("Worth knowing", systemImage: "exclamationmark.triangle")
                .font(Type.labelSmall)
                .foregroundStyle(Palette.warning)

            Text("""
            You authorise Prism on google.com — your password is never typed into this app, and you can revoke access from your Google account page at any time, exactly like a television.

            Even so, using any third-party client with your account is against YouTube's Terms of Service, and accounts have been flagged for it. If that would cost you something, use a secondary account instead.
            """)
            .font(Type.labelSmall)
            .foregroundStyle(Palette.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Metrics.Space.lg)
        .background(Palette.warning.opacity(0.07), in: RoundedRectangle(cornerRadius: Metrics.Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.Radius.card, style: .continuous)
                .strokeBorder(Palette.warning.opacity(0.18))
        )
    }

    /// The code the user types on google.com/device.
    ///
    /// The code itself is the hero of this panel — large, monospaced, and
    /// letter-spaced, because it is read off one screen and typed into another.
    /// Grouping is preserved exactly as Google issues it.
    private func deviceCodePanel(_ code: AccountSession.DeviceCode) -> some View {
        VStack(spacing: Metrics.Space.lg) {
            VStack(spacing: Metrics.Space.sm) {
                Text("1. Go to")
                    .font(Type.labelSmall)
                    .foregroundStyle(Palette.textTertiary)

                Text(code.verificationURL.replacingOccurrences(of: "https://", with: ""))
                    .font(Type.bodyEmphasis)
                    .foregroundStyle(Palette.disperse)
            }

            VStack(spacing: Metrics.Space.sm) {
                Text("2. Enter this code")
                    .font(Type.labelSmall)
                    .foregroundStyle(Palette.textTertiary)

                Text(code.userCode)
                    .font(.system(size: 30, weight: .bold, design: .monospaced))
                    .tracking(3)
                    .foregroundStyle(Palette.textPrimary)
                    .textSelection(.enabled)
                    .padding(.horizontal, Metrics.Space.lg)
                    .padding(.vertical, Metrics.Space.md)
                    .background(Palette.surfaceRaised, in: RoundedRectangle(cornerRadius: Metrics.Radius.md, style: .continuous))
            }

            HStack(spacing: Metrics.Space.md) {
                Button {
                    UIPasteboard.general.string = code.userCode
                    Haptics.impact(.light)
                } label: {
                    Label("Copy code", systemImage: "doc.on.doc")
                        .font(Type.labelSmall)
                        .foregroundStyle(Palette.textPrimary)
                }

                Link(destination: URL(string: code.verificationURL)!) {
                    Label("Open page", systemImage: "arrow.up.right.square")
                        .font(Type.labelSmall)
                        .foregroundStyle(Palette.refract)
                }
            }

            HStack(spacing: Metrics.Space.sm) {
                ProgressView().controlSize(.small).tint(Palette.textTertiary)
                Text("Waiting for you to approve it…")
                    .font(Type.labelSmall)
                    .foregroundStyle(Palette.textTertiary)
            }

            Button("Cancel") { session.cancelSignIn() }
                .font(Type.labelSmall)
                .foregroundStyle(Palette.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Metrics.Space.lg)
    }

    // MARK: Building blocks

    @ViewBuilder
    private func section<C: View>(_ title: String, note: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: Metrics.Space.md) {
            Text(title)
                .font(Type.readoutSmall)
                .tracking(1.2)
                .foregroundStyle(Palette.textTertiary)

            Text(note)
                .font(Type.meta)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 0) { content() }
                .padding(.horizontal, Metrics.Space.lg)
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: Metrics.Radius.card, style: .continuous))
        }
    }

    private func statusRow(icon: String, tint: Color, title: String, detail: String) -> some View {
        HStack(spacing: Metrics.Space.md) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(tint)

            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(Type.bodyEmphasis).foregroundStyle(Palette.textPrimary)
                Text(detail).font(Type.labelSmall).foregroundStyle(Palette.textTertiary).lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, Metrics.Space.md)
    }
}
