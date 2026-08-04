import SwiftUI

/// PRISM's colour system.
///
/// The app is built on a cool ink base so that video content — the only truly
/// colourful thing on screen — always reads as the brightest object. Bars and
/// controls recede; content advances.
///
/// The accent pair (`refract` → `disperse`) is the refraction gradient: the
/// violet and cyan that a prism throws at opposite ends of its spectrum. It is
/// used sparingly, and never on top of video.
enum Palette {

    // MARK: Substrate

    /// Page background. Near-black with a blue cast so OLED blacks in video
    /// don't look warm against it.
    static let ink = Color(hex: 0x08090E)
    /// Cards, sheets, the bottom bar.
    static let surface = Color(hex: 0x12141C)
    /// Anything sitting on top of `surface` — menus, elevated chips.
    static let surfaceRaised = Color(hex: 0x1A1D28)
    /// Pressed / selected fill.
    static let surfaceActive = Color(hex: 0x232735)
    /// Hairlines. Deliberately low contrast — structure should be felt, not read.
    static let line = Color(hex: 0x262A38)

    // MARK: Ink on substrate

    static let textPrimary = Color(hex: 0xF0F1F5)
    static let textSecondary = Color(hex: 0x9096A8)
    static let textTertiary = Color(hex: 0x5C6273)

    // MARK: Refraction — the accent pair

    static let refract = Color(hex: 0x7C6FFF)   // violet
    static let disperse = Color(hex: 0x22D3EE)  // cyan

    static let refractGradient = LinearGradient(
        colors: [refract, disperse],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // MARK: Status

    static let live = Color(hex: 0xFF4D6D)
    static let success = Color(hex: 0x4ADE80)
    static let warning = Color(hex: 0xFFC24D)

    /// The spectrum. Each SponsorBlock category owns one band of it, so the
    /// scrubber reads as a literal dispersion of the timeline.
    ///
    /// Hues are ordered around the wheel rather than picked ad hoc, which keeps
    /// adjacent segments legible when they abut on the scrubber.
    enum Segment {
        static let sponsor = Color(hex: 0xFF4D6D)        // rose
        static let selfPromo = Color(hex: 0xFFC24D)      // amber
        static let interaction = Color(hex: 0xA78BFA)    // violet
        static let intro = Color(hex: 0x22D3EE)          // cyan
        static let outro = Color(hex: 0x38BDF8)          // sky
        static let preview = Color(hex: 0x60A5FA)        // blue
        static let musicOffTopic = Color(hex: 0x4ADE80)  // green
        static let filler = Color(hex: 0x94A3B8)         // slate
        static let highlight = Color(hex: 0xF472B6)      // pink
    }
}

extension Color {
    /// `Color(hex: 0x7C6FFF)` — terser than the string form and validated at
    /// compile time.
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}
