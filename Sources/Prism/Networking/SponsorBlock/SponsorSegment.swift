import SwiftUI

/// A category of non-content segment, as classified by SponsorBlock's
/// contributors.
///
/// Raw values match the API's category strings exactly.
enum SegmentCategory: String, Codable, CaseIterable, Sendable {
    case sponsor
    case selfpromo
    case interaction
    case intro
    case outro
    case preview
    case musicOfftopic = "music_offtopic"
    case filler
    case poiHighlight = "poi_highlight"

    /// The band of PRISM's spectrum this category occupies.
    var color: Color {
        switch self {
        case .sponsor: Palette.Segment.sponsor
        case .selfpromo: Palette.Segment.selfPromo
        case .interaction: Palette.Segment.interaction
        case .intro: Palette.Segment.intro
        case .outro: Palette.Segment.outro
        case .preview: Palette.Segment.preview
        case .musicOfftopic: Palette.Segment.musicOffTopic
        case .filler: Palette.Segment.filler
        case .poiHighlight: Palette.Segment.highlight
        }
    }

    /// Shown in the skip toast. Written from the viewer's side of the screen —
    /// what was skipped, not what the API calls it.
    var title: String {
        switch self {
        case .sponsor: "Sponsor"
        case .selfpromo: "Self-promotion"
        case .interaction: "Subscribe reminder"
        case .intro: "Intro"
        case .outro: "Outro"
        case .preview: "Recap"
        case .musicOfftopic: "Non-music"
        case .filler: "Tangent"
        case .poiHighlight: "Highlight"
        }
    }

    var icon: String {
        switch self {
        case .sponsor: "dollarsign.circle.fill"
        case .selfpromo: "megaphone.fill"
        case .interaction: "hand.raised.fill"
        case .intro: "flag.fill"
        case .outro: "flag.checkered"
        case .preview: "rectangle.stack.fill"
        case .musicOfftopic: "music.note"
        case .filler: "text.bubble.fill"
        case .poiHighlight: "sparkles"
        }
    }

    /// What PRISM does with this category out of the box.
    ///
    /// Only the categories that are unambiguously not-the-video skip silently.
    /// `intro`/`outro` are shown but not skipped, because on plenty of channels
    /// the intro *is* the thing people came for.
    var defaultAction: SegmentAction {
        switch self {
        case .sponsor, .selfpromo, .interaction: .skip
        case .intro, .outro, .preview, .filler, .musicOfftopic: .show
        case .poiHighlight: .show
        }
    }
}

enum SegmentAction: String, Codable, CaseIterable, Sendable {
    /// Jump past it and say so.
    case skip
    /// Keep playing, drop the volume.
    case mute
    /// Draw it on the scrubber; don't intervene.
    case show
    /// Pretend it isn't there.
    case ignore

    var title: String {
        switch self {
        case .skip: "Skip"
        case .mute: "Mute"
        case .show: "Show only"
        case .ignore: "Ignore"
        }
    }
}

/// One contributed segment of a video.
struct SponsorSegment: Identifiable, Codable, Sendable, Equatable {
    let id: String
    let category: SegmentCategory
    let start: Double
    let end: Double
    /// SponsorBlock's own action type — `.poi` segments are a single point, and
    /// `.full` applies to the entire video rather than a range.
    let actionType: String
    let locked: Bool
    let votes: Int

    var duration: Double { max(0, end - start) }

    /// A point of interest is a marker, not a range, and must never be skipped.
    var isPointOfInterest: Bool { actionType == "poi" }
    /// A full-video label ("this entire video is a sponsor") is metadata, not a
    /// range to jump over.
    var isFullVideo: Bool { actionType == "full" }

    func contains(_ time: Double) -> Bool {
        time >= start && time < end
    }
}
