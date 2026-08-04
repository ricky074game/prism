import UIKit

/// The window's safe area, read from UIKit.
///
/// A `GeometryProxy` is the usual way to get this and it doesn't work here: the
/// shorts feed deliberately ignores the safe area so the video can run to the
/// edges of the screen, and a proxy inside a view that ignores the safe area
/// reports zero for it. Taking 34pt off the overlay's clearance is exactly how
/// the title ended up half-hidden behind the home indicator.
///
/// The window knows regardless of what any view has chosen to ignore.
enum WindowInsets {
    @MainActor
    static var bottom: CGFloat {
        keyWindow?.safeAreaInsets.bottom ?? 0
    }

    @MainActor
    static var top: CGFloat {
        keyWindow?.safeAreaInsets.top ?? 0
    }

    @MainActor
    private static var keyWindow: UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
    }
}
