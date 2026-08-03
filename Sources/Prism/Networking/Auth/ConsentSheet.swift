import SwiftUI
import SafariServices

/// Presents Google's consent page.
///
/// `SFSafariViewController` rather than a `WKWebView`, for three reasons:
///
/// - **It shares Safari's cookies.** Someone already signed into Google in
///   Safari — most people — sees only a consent tap, not a password prompt.
/// - **Google trusts it.** Embedded web views get blocked with "this browser may
///   not be secure"; Safari View Controller does not.
/// - **The app cannot read it.** The password is typed into a process this app
///   has no access to, which is the honest arrangement for someone else's
///   credentials.
///
/// It's dismissed programmatically the moment polling reports success, so the
/// user never has to work out that they're finished and back out manually.
struct ConsentSheet: UIViewControllerRepresentable {
    let url: URL
    var onDismiss: () -> Void

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let config = SFSafariViewController.Configuration()
        config.entersReaderIfAvailable = false
        config.barCollapsingEnabled = true

        let controller = SFSafariViewController(url: url, configuration: config)
        controller.preferredControlTintColor = UIColor(Palette.refract)
        controller.preferredBarTintColor = UIColor(Palette.ink)
        controller.dismissButtonStyle = .cancel
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onDismiss: onDismiss) }

    final class Coordinator: NSObject, SFSafariViewControllerDelegate {
        let onDismiss: () -> Void

        init(onDismiss: @escaping () -> Void) {
            self.onDismiss = onDismiss
        }

        /// Fires when the user taps Cancel rather than finishing.
        func safariViewControllerDidFinish(_ controller: SFSafariViewController) {
            onDismiss()
        }
    }
}
