import SwiftUI

/// Account sign-in.
///
/// One sign-in, doing everything: the age gate, history, Watch Later, the
/// subscription feed, liking and subscribing.
///
/// It used to be two, because the second was assumed to be the only route to
/// the YouTube Data API. It isn't a route to anything — that API is disabled on
/// the TV client's Google project and answers every call with HTTP 403 — so the
/// features were rebuilt on InnerTube and the second account, its OAuth client
/// and its `Secrets.swift` configuration step were deleted.
///
/// This one carries real risk, so the screen states it rather than burying it.
struct AccountScreen: View {
    @State private var session = AccountSession.shared
    @State private var showSignOutConfirm = false
    @State private var showConsent = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.Space.xxl) {
                youtubeSession
                risk
            }
            .padding(Metrics.gutter)
            .padding(.bottom, Metrics.Space.huge)
        }
        .scrollIndicators(.hidden)
        .background(Palette.ink.ignoresSafeArea())
        .navigationTitle("Account")
        .navigationBarTitleDisplayMode(.inline)
        // Opens as soon as a code exists, so the normal path is: tap Sign in →
        // Safari sheet with the code already filled → tap Allow → sheet closes.
        .onChange(of: session.pendingCode) { _, code in
            showConsent = code != nil
        }
        // Polling succeeded, so the sheet has served its purpose — close it
        // rather than leaving the user to work out that they're done.
        .onChange(of: session.isSignedIn) { _, signedIn in
            if signedIn { showConsent = false }
        }
        .sheet(isPresented: $showConsent) {
            if let url = session.pendingCode?.prefilledURL {
                ConsentSheet(url: url) {
                    // Dismissed by hand. Polling continues, because the consent
                    // may still have been granted before they closed it.
                    showConsent = false
                }
                .ignoresSafeArea()
            }
        }
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
            "YOUTUBE ACCOUNT",
            note: "Unlocks age-restricted videos, your watch history, Watch Later, a home feed based on what you actually watch, and your subscriptions — plus liking and subscribing from here. This is the only sign-in most people need."
        ) {
            if session.isSignedIn {
                statusRow(
                    icon: "checkmark.circle.fill",
                    tint: Palette.success,
                    title: "Signed in",
                    detail: "Age-restricted videos and your history are available."
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

    /// Shown while waiting for approval.
    ///
    /// The consent page opens automatically with the code already filled in, so
    /// in the normal case nobody reads this panel at all — they tap Allow in the
    /// Safari sheet and it closes itself. The code stays visible as a fallback
    /// for the case where the sheet was dismissed, or the pre-fill stops working.
    private func deviceCodePanel(_ code: AccountSession.DeviceCode) -> some View {
        VStack(spacing: Metrics.Space.lg) {
            HStack(spacing: Metrics.Space.sm) {
                ProgressView().controlSize(.small).tint(Palette.refract)
                Text("Waiting for you to approve Prism…")
                    .font(Type.metaEmphasis)
                    .foregroundStyle(Palette.textPrimary)
            }

            VStack(spacing: Metrics.Space.sm) {
                Text("If the page didn't open, go to google.com/device and enter")
                    .font(Type.labelSmall)
                    .foregroundStyle(Palette.textTertiary)
                    .multilineTextAlignment(.center)

                Text(code.userCode)
                    .font(.system(size: 26, weight: .bold, design: .monospaced))
                    .tracking(3)
                    .foregroundStyle(Palette.textPrimary)
                    .textSelection(.enabled)
                    .padding(.horizontal, Metrics.Space.lg)
                    .padding(.vertical, Metrics.Space.md)
                    .background(Palette.surfaceRaised, in: RoundedRectangle(cornerRadius: Metrics.Radius.md, style: .continuous))
                    // Read as three groups rather than eleven letters.
                    .accessibilityLabel(code.userCode.map { String($0) }.joined(separator: " "))
            }

            HStack(spacing: Metrics.Space.xl) {
                Button {
                    UIPasteboard.general.string = code.userCode
                    Haptics.impact(.light)
                } label: {
                    Label("Copy code", systemImage: "doc.on.doc")
                        .font(Type.labelSmall)
                        .foregroundStyle(Palette.textSecondary)
                }

                Button {
                    showConsent = true
                } label: {
                    Label("Open page again", systemImage: "arrow.clockwise")
                        .font(Type.labelSmall)
                        .foregroundStyle(Palette.refract)
                }
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
