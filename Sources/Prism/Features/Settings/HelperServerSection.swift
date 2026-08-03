import SwiftUI

/// Configures the optional helper server.
///
/// Presented as genuinely optional, because it is: everything except
/// "made for kids" and SABR-only videos plays without it. The field verifies by
/// actually calling the server rather than accepting any string that parses as
/// a URL — a typo'd address that silently never works is worse than no field.
struct HelperServerSection: View {
    @AppStorage("helper.baseURL") private var baseURL = ""

    @State private var status: Status = .unknown
    @State private var isChecking = false

    enum Status {
        case unknown, reachable, unreachable

        var color: Color {
            switch self {
            case .unknown: Palette.textTertiary
            case .reachable: Palette.success
            case .unreachable: Palette.warning
            }
        }

        var text: String {
            switch self {
            case .unknown: "Not checked"
            case .reachable: "Reachable"
            case .unreachable: "No answer"
            }
        }

        var icon: String {
            switch self {
            case .unknown: "questionmark.circle"
            case .reachable: "checkmark.circle.fill"
            case .unreachable: "exclamationmark.triangle.fill"
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.Space.md) {
            Text("HELPER SERVER")
                .font(Type.readoutSmall)
                .tracking(1.2)
                .foregroundStyle(Palette.textTertiary)

            Text("Optional. Plays the handful of videos this app can't reach on its own — anything marked \"made for kids\", and videos Google has moved to its newer streaming protocol.")
                .font(Type.meta)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 0) {
                HStack(spacing: Metrics.Space.sm) {
                    Image(systemName: "server.rack")
                        .font(.system(size: 14))
                        .foregroundStyle(Palette.textTertiary)

                    TextField("http://192.168.1.20:8787", text: $baseURL)
                        .font(Type.body)
                        .foregroundStyle(Palette.textPrimary)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .onChange(of: baseURL) { _, _ in status = .unknown }

                    if !baseURL.isEmpty {
                        Button {
                            baseURL = ""
                            status = .unknown
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(Palette.textTertiary)
                        }
                        .accessibilityLabel("Clear address")
                    }
                }
                .padding(.vertical, Metrics.Space.md)

                Divider().overlay(Palette.line)

                HStack {
                    Label(status.text, systemImage: status.icon)
                        .font(Type.labelSmall)
                        .foregroundStyle(status.color)

                    Spacer()

                    Button {
                        Task { await check() }
                    } label: {
                        HStack(spacing: 5) {
                            if isChecking {
                                ProgressView().controlSize(.mini).tint(Palette.refract)
                            }
                            Text(isChecking ? "Checking…" : "Test connection")
                                .font(Type.labelSmall)
                        }
                        .foregroundStyle(Palette.refract)
                    }
                    .disabled(baseURL.isEmpty || isChecking)
                }
                .padding(.vertical, Metrics.Space.md)
            }
            .padding(.horizontal, Metrics.Space.lg)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: Metrics.Radius.card, style: .continuous))

            Text("Run `node server/server.js` on a machine on your network. It needs yt-dlp and Node installed. Leave this blank to skip it.")
                .font(Type.labelSmall)
                .foregroundStyle(Palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func check() async {
        guard let url = URL(string: baseURL.trimmingCharacters(in: .whitespaces)) else {
            status = .unreachable
            return
        }
        isChecking = true
        defer { isChecking = false }

        status = await HelperClient.shared.check(url) ? .reachable : .unreachable
        Haptics.notify(status == .reachable ? .success : .warning)
    }
}
