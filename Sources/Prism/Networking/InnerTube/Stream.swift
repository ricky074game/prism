import Foundation
import AVFoundation

/// One downloadable rendition of a video.
struct Stream: Sendable, Identifiable, Equatable {
    let itag: Int
    let url: URL
    let mimeType: String
    let codecs: String
    let bitrate: Int
    let width: Int?
    let height: Int?
    let fps: Int?
    let qualityLabel: String?
    let audioChannels: Int?
    let contentLength: Int?

    var id: Int { itag }

    var isVideo: Bool { mimeType.hasPrefix("video/") }
    var isAudio: Bool { mimeType.hasPrefix("audio/") }
    /// A progressive stream carries both tracks in one file — playable by
    /// AVPlayer with no compositing.
    var isProgressive: Bool { isVideo && codecs.contains(",") }

    var container: String {
        mimeType.contains("mp4") ? "mp4" : mimeType.contains("webm") ? "webm" : "unknown"
    }

    /// AVFoundation has no WebM demuxer, so VP9/Opus-in-WebM is unplayable
    /// regardless of how good the bitrate looks. Filtering here rather than at
    /// the call site keeps that knowledge in one place.
    var isPlayableByAVFoundation: Bool {
        guard container == "mp4" else { return false }
        if isAudio { return codecs.hasPrefix("mp4a") || codecs.hasPrefix("ec-3") || codecs.hasPrefix("ac-3") }
        return codecs.hasPrefix("avc1") || codecs.hasPrefix("av01") || codecs.hasPrefix("hvc1")
    }

    var isAV1: Bool { codecs.hasPrefix("av01") }
    var isH264: Bool { codecs.hasPrefix("avc1") }

    init?(json: [String: Any]) {
        // A format carrying `signatureCipher` needs the player's JS to be
        // deciphered. ANDROID_VR returns plain URLs; if we ever see a ciphered
        // one we skip it rather than shipping a broken stream.
        guard let urlString = json["url"] as? String, let url = URL(string: urlString) else { return nil }
        guard let itag = json["itag"] as? Int else { return nil }

        let mime = json["mimeType"] as? String ?? ""
        self.itag = itag
        self.url = url
        self.mimeType = mime.components(separatedBy: ";").first ?? mime
        self.codecs = Self.parseCodecs(from: mime)
        self.bitrate = json["bitrate"] as? Int ?? 0
        self.width = json["width"] as? Int
        self.height = json["height"] as? Int
        self.fps = json["fps"] as? Int
        self.qualityLabel = json["qualityLabel"] as? String
        self.audioChannels = json["audioChannels"] as? Int
        self.contentLength = Int(json["contentLength"] as? String ?? "")
    }

    private static func parseCodecs(from mime: String) -> String {
        guard let range = mime.range(of: "codecs=\"") else { return "" }
        let rest = mime[range.upperBound...]
        guard let end = rest.firstIndex(of: "\"") else { return "" }
        return String(rest[..<end])
    }
}

/// Everything needed to start playback, plus the metadata shown around it.
struct PlaybackSource: Sendable {
    let videoID: String
    let title: String
    let author: String
    let channelID: String
    let duration: Double
    let isLive: Bool
    let viewCount: Int
    let streams: [Stream]

    var playable: [Stream] { streams.filter(\.isPlayableByAVFoundation) }

    /// Distinct video qualities on offer, best first — what the quality menu shows.
    var availableQualities: [VideoQuality] {
        let heights = Set(playable.filter { $0.isVideo && !$0.isProgressive }.compactMap(\.height))
        return VideoQuality.allCases.filter { q in
            q == .auto || heights.contains { $0 >= q.minHeight && $0 <= q.maxHeight }
        }
    }
}

enum VideoQuality: String, CaseIterable, Identifiable, Sendable {
    case auto, p2160, p1440, p1080, p720, p480, p360, p240

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: "Auto"
        case .p2160: "2160p"
        case .p1440: "1440p"
        case .p1080: "1080p"
        case .p720: "720p"
        case .p480: "480p"
        case .p360: "360p"
        case .p240: "240p"
        }
    }

    /// Shown next to the highest tiers so the label explains itself.
    var note: String? {
        switch self {
        case .p2160, .p1440: "AV1"
        case .auto: "Recommended"
        default: nil
        }
    }

    var minHeight: Int {
        switch self {
        case .auto: 0
        case .p2160: 2160
        case .p1440: 1440
        case .p1080: 1080
        case .p720: 720
        case .p480: 480
        case .p360: 360
        case .p240: 240
        }
    }

    var maxHeight: Int { self == .auto ? .max : minHeight + 200 }
}

// MARK: - Selection

/// Picks which streams actually get played.
///
/// The rules encode two hardware facts:
///
/// 1. **H.264 is decoded in hardware on every iPhone ever made.** AV1 is only
///    hardware-decoded on A17 Pro / M3 and later; on anything older it falls to
///    a software decoder that will drain the battery and drop frames at 4K.
/// 2. **YouTube caps H.264 at 1080p.** Above that it only offers VP9 (WebM —
///    unplayable here) and AV1. So 1440p/2160p implies AV1, which implies a
///    hardware check.
enum StreamSelector {

    /// True when this device decodes AV1 in hardware.
    ///
    /// `VTIsHardwareDecodeSupported` is the honest answer straight from
    /// VideoToolbox — far better than maintaining a list of device model strings.
    static let supportsHardwareAV1: Bool = {
        if #available(iOS 16.0, *) {
            return VTIsHardwareDecodeSupported(kCMVideoCodecType_AV1)
        }
        return false
    }()

    struct Selection: Sendable {
        let video: Stream?
        let audio: Stream?
        /// Set when a single file carries both tracks; the player can then skip
        /// compositing entirely, which is meaningfully faster to first frame.
        let progressive: Stream?

        var needsComposition: Bool { progressive == nil && video != nil && audio != nil }
    }

    static func select(
        from source: PlaybackSource,
        quality: VideoQuality,
        preferEfficiency: Bool = false
    ) -> Selection {
        let playable = source.playable

        // Live streams and anything with no adaptive set fall back to whatever
        // single-file rendition exists.
        let adaptiveVideo = playable.filter { $0.isVideo && !$0.isProgressive }
        guard !adaptiveVideo.isEmpty else {
            let prog = playable.filter(\.isProgressive).max { $0.bitrate < $1.bitrate }
            return Selection(video: nil, audio: nil, progressive: prog)
        }

        let audio = bestAudio(from: playable)

        // Drop AV1 on hardware that can't decode it. A 4K software-decoded
        // stream is a worse experience than a hardware 1080p one, every time.
        let usable = adaptiveVideo.filter { supportsHardwareAV1 || !$0.isAV1 }

        let ceiling: Int = {
            switch quality {
            case .auto: return supportsHardwareAV1 ? 2160 : 1080
            default: return quality.minHeight
            }
        }()

        let candidates = usable.filter { ($0.height ?? 0) <= ceiling }
        let pool = candidates.isEmpty ? usable : candidates

        // Within a height, prefer H.264 unless efficiency was asked for —
        // it starts faster and costs less power on the common path.
        let best = pool.max { a, b in
            let ha = a.height ?? 0, hb = b.height ?? 0
            if ha != hb { return ha < hb }
            if a.isH264 != b.isH264 { return preferEfficiency ? a.isH264 : b.isH264 }
            return a.bitrate < b.bitrate
        }

        return Selection(video: best, audio: audio, progressive: nil)
    }

    private static func bestAudio(from streams: [Stream]) -> Stream? {
        streams
            .filter { $0.isAudio && $0.isPlayableByAVFoundation }
            .max { $0.bitrate < $1.bitrate }
    }

    /// The instant-start rendition: one file, no compositing, no track loading.
    /// Used to put a frame on screen while the high-quality set is prepared.
    static func fastStart(from source: PlaybackSource) -> Stream? {
        source.playable
            .filter(\.isProgressive)
            .min { ($0.height ?? 0) < ($1.height ?? 0) }
    }
}
