import SwiftUI

/// Spacing, radii, and the motion vocabulary.
enum Metrics {
    /// A 4pt base grid. Every margin in the app is one of these.
    enum Space {
        static let hair: CGFloat = 2
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
        static let huge: CGFloat = 48
    }

    enum Radius {
        static let sm: CGFloat = 8
        static let md: CGFloat = 14
        /// Thumbnails. Large enough to feel soft, small enough that 16:9 corners
        /// don't eat the frame.
        static let card: CGFloat = 18
        static let sheet: CGFloat = 28
        static let pill: CGFloat = 999
    }

    /// Standard screen gutter.
    static let gutter: CGFloat = 16
}

/// Motion.
///
/// Everything is a spring — no eased curves — because springs are interruptible.
/// A user who reverses a gesture mid-flight should never have to wait for an
/// animation to finish playing out at them.
enum Motion {
    /// The workhorse. Used for anything that moves under a finger.
    static let standard = Animation.spring(response: 0.38, dampingFraction: 0.82)
    /// Snappier — chips, toggles, small state flips.
    static let quick = Animation.spring(response: 0.26, dampingFraction: 0.86)
    /// The hero transition (thumbnail → full player). Slightly looser so the
    /// scale-up has some weight to it.
    static let hero = Animation.spring(response: 0.5, dampingFraction: 0.86)
    /// Bouncy — reserved for the one or two places that should feel playful,
    /// like the like-button pop.
    static let pop = Animation.spring(response: 0.3, dampingFraction: 0.6)
    /// Long, soft ambient drift for the light-spill glow.
    static let ambient = Animation.easeInOut(duration: 1.2)

    /// Feed entrance stagger. Capped so that item 40 doesn't wait 4 seconds.
    static func stagger(_ index: Int, step: Double = 0.035, cap: Int = 8) -> Double {
        Double(min(index, cap)) * step
    }
}

// MARK: - Reduce Motion

extension View {
    /// Applies an animation unless the user has asked the system for less motion.
    ///
    /// Wrapping this once here means no call site has to remember the check.
    @ViewBuilder
    func motion<V: Equatable>(_ animation: Animation?, value: V) -> some View {
        modifier(MotionModifier(animation: animation, value: value))
    }
}

private struct MotionModifier<V: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let animation: Animation?
    let value: V

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : animation, value: value)
    }
}
