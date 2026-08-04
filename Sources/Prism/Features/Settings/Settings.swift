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

    /// Seconds jumped by a double-tap on either side of the player, and by the
    /// on-screen skip buttons.
    var seekInterval: Int {
        didSet { defaults.set(seekInterval, forKey: Keys.seek) }
    }

    /// Turn captions on automatically when a video has them.
    var autoCaptions: Bool {
        didSet { defaults.set(autoCaptions, forKey: Keys.autoCaptions) }
    }

    /// Remembered across videos, the way every other player behaves.
    var playbackRate: Double {
        didSet { defaults.set(playbackRate, forKey: Keys.rate) }
    }

    static let seekOptions = [5, 10, 15, 30, 45, 60]
    static let rateOptions: [Double] = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let actions = "segment.actions"
        static let quality = "quality.preferred"
        static let sponsorBlock = "sponsorblock.enabled"
        static let haptics = "haptics.enabled"
        static let glow = "ambient.glow"
        static let shorts = "shorts.visible"
        static let seek = "player.seekInterval"
        static let autoCaptions = "player.autoCaptions"
        static let rate = "player.rate"
    }

    init() {
        let d = UserDefaults.standard
        d.register(defaults: [
            Keys.sponsorBlock: true,
            Keys.haptics: true,
            Keys.glow: true,
            Keys.shorts: true,
            Keys.seek: 10,
            Keys.autoCaptions: false,
            Keys.rate: 1.0,
        ])

        sponsorBlockEnabled = d.bool(forKey: Keys.sponsorBlock)
        hapticsEnabled = d.bool(forKey: Keys.haptics)
        ambientGlow = d.bool(forKey: Keys.glow)
        showShorts = d.bool(forKey: Keys.shorts)
        seekInterval = d.integer(forKey: Keys.seek)
        autoCaptions = d.bool(forKey: Keys.autoCaptions)
        playbackRate = d.double(forKey: Keys.rate)
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
