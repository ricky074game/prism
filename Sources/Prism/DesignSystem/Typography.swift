import SwiftUI
import UIKit

/// PRISM's type system.
///
/// Two families, chosen for opposite reasons:
///
/// - **Archivo** (bundled, variable) carries the personality. It has a genuinely
///   wide Expanded axis, which gives headings an editorial, almost broadcast-
///   graphics confidence that the system face can't. Used with restraint —
///   wordmark, screen titles, and the now-playing title only.
/// - **SF Pro** (system) does everything else. Bundling a second text face would
///   cost a font-loading pass on every cold start and buy nothing: SF is the most
///   legible face on this display at 13pt, and it's already resident in memory.
///
/// Numerals in flowing text use `.monospacedDigit()` so counts and durations
/// don't jitter as they tick.
enum Type {

    // MARK: Display — Archivo

    /// The wordmark and hero moments. Expanded width, heavy.
    static func display(_ size: CGFloat) -> Font {
        .custom("Archivo-Expanded", size: size).weight(.bold)
    }

    /// Screen titles.
    static func title(_ size: CGFloat) -> Font {
        .custom("Archivo-SemiExpanded", size: size).weight(.semibold)
    }

    // MARK: Text — SF Pro

    /// Video titles in the feed. Tight leading; these wrap to two lines and
    /// should read as a single block, not two sentences.
    static let cardTitle = Font.system(size: 15, weight: .semibold)
    static let cardTitleLarge = Font.system(size: 19, weight: .semibold)

    /// Channel names, view counts, timestamps.
    static let meta = Font.system(size: 13, weight: .regular)
    static let metaEmphasis = Font.system(size: 13, weight: .medium)

    static let body = Font.system(size: 15, weight: .regular)
    static let bodyEmphasis = Font.system(size: 15, weight: .medium)

    /// Chips, tab labels, buttons.
    static let label = Font.system(size: 13, weight: .semibold)
    static let labelSmall = Font.system(size: 11, weight: .semibold)

    /// The scrubber read-out and duration badges. Monospaced because the
    /// scrubber is an instrument, and instruments have fixed-width read-outs.
    static let readout = Font.system(size: 12, weight: .medium, design: .monospaced)
    static let readoutSmall = Font.system(size: 10, weight: .semibold, design: .monospaced)
}

// MARK: - Font registration

enum FontLoader {
    /// Verifies the bundled faces registered.
    ///
    /// `UIAppFonts` in Info.plist does the actual registration at launch. This
    /// only checks the result, because a missing custom font fails *silently* —
    /// SwiftUI substitutes the system face and the app looks subtly wrong with
    /// nothing in the log to explain why.
    @discardableResult
    static func register() -> Bool {
        let required = ["Archivo-Expanded", "Archivo-SemiExpanded"]
        let available = Set(UIFont.familyNames.flatMap { UIFont.fontNames(forFamilyName: $0) })
        let missing = required.filter { !available.contains($0) }

        if !missing.isEmpty {
            // Registering by URL recovers the case where the font shipped but
            // wasn't listed in UIAppFonts.
            for name in missing {
                guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else {
                    assertionFailure("Missing bundled font: \(name).ttf")
                    continue
                }
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
        return missing.isEmpty
    }
}
