import SwiftUI
import Observation

/// User preferences, persisted to `UserDefaults`.
@MainActor
@Observable
final class Settings {
    var categoryActions: [SegmentCategory: SegmentAction] {
        didSet { persistActions() }
    }

    var preferredQuality: VideoQuality {
        didSet { defaults.set(preferredQuality.rawValue, forKey: Keys.quality) }
    }

    var sponsorBlockEnabled: Bool {
        didSet { defaults.set(sponsorBlockEnabled, forKey: Keys.sponsorBlock) }
    }

    var hapticsEnabled: Bool {
        didSet {
            defaults.set(hapticsEnabled, forKey: Keys.haptics)
            Haptics.isEnabled = hapticsEnabled
        }
    }

    /// The ambient light-spill behind the player and hero card.
    var ambientGlow: Bool {
        didSet { defaults.set(ambientGlow, forKey: Keys.glow) }
    }

    /// Hides the Shorts tab entirely for people who don't want the format.
    var showShorts: Bool {
        didSet { defaults.set(showShorts, forKey: Keys.shorts) }
    }

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let actions = "segment.actions"
        static let quality = "quality.preferred"
        static let sponsorBlock = "sponsorblock.enabled"
        static let haptics = "haptics.enabled"
        static let glow = "ambient.glow"
        static let shorts = "shorts.visible"
    }

    init() {
        let d = UserDefaults.standard
        d.register(defaults: [
            Keys.sponsorBlock: true,
            Keys.haptics: true,
            Keys.glow: true,
            Keys.shorts: true,
        ])

        sponsorBlockEnabled = d.bool(forKey: Keys.sponsorBlock)
        hapticsEnabled = d.bool(forKey: Keys.haptics)
        ambientGlow = d.bool(forKey: Keys.glow)
        showShorts = d.bool(forKey: Keys.shorts)
        preferredQuality = VideoQuality(rawValue: d.string(forKey: Keys.quality) ?? "") ?? .auto

        if let raw = d.dictionary(forKey: Keys.actions) as? [String: String] {
            var restored: [SegmentCategory: SegmentAction] = [:]
            for (k, v) in raw {
                if let c = SegmentCategory(rawValue: k), let a = SegmentAction(rawValue: v) {
                    restored[c] = a
                }
            }
            categoryActions = restored
        } else {
            categoryActions = Dictionary(
                uniqueKeysWithValues: SegmentCategory.allCases.map { ($0, $0.defaultAction) }
            )
        }

        Haptics.isEnabled = hapticsEnabled
    }

    /// Categories worth requesting from the API — anything fully ignored is
    /// left out of the query rather than filtered after the fact.
    var enabledCategories: Set<SegmentCategory> {
        guard sponsorBlockEnabled else { return [] }
        return Set(categoryActions.filter { $0.value != .ignore }.keys)
    }

    private func persistActions() {
        let raw = Dictionary(uniqueKeysWithValues: categoryActions.map { ($0.key.rawValue, $0.value.rawValue) })
        defaults.set(raw, forKey: Keys.actions)
    }
}
