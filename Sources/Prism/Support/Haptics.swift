import UIKit

/// Haptic feedback.
///
/// Generators are retained and pre-warmed. Creating one at the call site adds
/// ~20ms of latency before the first tap fires, which is exactly the window in
/// which a scrub gesture needs to feel connected.
@MainActor
enum Haptics {
    private static let selectionGenerator = UISelectionFeedbackGenerator()
    private static var impactGenerators: [UIImpactFeedbackGenerator.FeedbackStyle: UIImpactFeedbackGenerator] = [:]
    private static let notificationGenerator = UINotificationFeedbackGenerator()

    static var isEnabled = true

    /// Call when a gesture is about to begin so the Taptic Engine is spun up.
    static func prepare() {
        selectionGenerator.prepare()
    }

    static func selection() {
        guard isEnabled else { return }
        selectionGenerator.selectionChanged()
        selectionGenerator.prepare()
    }

    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        guard isEnabled else { return }
        let gen = impactGenerators[style] ?? {
            let g = UIImpactFeedbackGenerator(style: style)
            impactGenerators[style] = g
            return g
        }()
        gen.impactOccurred()
        gen.prepare()
    }

    static func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        guard isEnabled else { return }
        notificationGenerator.notificationOccurred(type)
    }
}
