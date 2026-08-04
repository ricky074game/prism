import AVFoundation
import Combine
import MediaPlayer
import Observation

/// The playback engine.
///
/// ## Why compositing
///
/// YouTube serves high-quality video and audio as *separate* files. AVPlayer
/// takes one URL, so the two are stitched into an `AVMutableComposition` — two
/// `AVURLAsset`s, one track each, no re-encoding and no download. AVFoundation
/// streams both over HTTP range requests and decodes in hardware.
///
/// ## Why the fast-start path exists
///
/// Building that composition requires loading track metadata from both assets
/// before the first frame can appear — two network round-trips. That is the
/// difference between "instant" and "a beat of black screen", so PRISM starts
/// the single-file progressive rendition immediately, then swaps to the
/// high-quality composition at the same timestamp once it is ready. The swap is
/// invisible: same frame, better pixels.
@MainActor
@Observable
final class PlayerEngine {

    // MARK: Observable state

    private(set) var currentTime: Double = 0
    private(set) var duration: Double = 0
    private(set) var bufferedTime: Double = 0
    private(set) var isPlaying = false
    private(set) var isBuffering = false
    private(set) var currentQuality: VideoQuality = .auto
    private(set) var error: String?

    /// Set for a moment after a skip so the UI can announce what was removed.
    private(set) var lastSkip: SponsorSegment?

    var segments: [SponsorSegment] = []
    var chapters: [Chapter] = []
    var categoryActions: [SegmentCategory: SegmentAction] = [:]

    /// The chapter containing the playhead, shown above the scrubber.
    var currentChapter: Chapter? {
        chapters.last { $0.start <= currentTime }
    }

    /// True once there is a real item that can put pixels on screen. Drives the
    /// poster-frame crossfade.
    private(set) var hasVideo = false

    var progress: Double { duration > 0 ? currentTime / duration : 0 }
    var bufferedProgress: Double { duration > 0 ? bufferedTime / duration : 0 }

    // MARK: AVFoundation

    let player = AVPlayer()

    private var source: PlaybackSource?
    private var timeObserver: Any?
    private var cancellables = Set<AnyCancellable>()
    private var upgradeTask: Task<Void, Never>?
    private var isSwapping = false

    init() {
        player.automaticallyWaitsToMinimizeStalling = true
        player.actionAtItemEnd = .pause
        configureSession()
        observePlayer()
    }

    // No `deinit` cleanup of time observers: the properties are main-actor
    // isolated and `deinit` is nonisolated, so touching them there is a data
    // race. `AVPlayer` releases its own observers when it deallocates, and the
    // engine outlives every view that uses it, so an explicit `teardown()` is
    // the right hook — not `deinit`.

    // MARK: Session

    /// `.playback` keeps audio alive when the screen locks or the app
    /// backgrounds — the single most-requested behaviour in any video client.
    private func configureSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .moviePlayback, options: [])
        try? session.setActive(true)
    }

    // MARK: Loading

    /// Poses the engine mid-playback without a real item, so screenshot runs
    /// can show the scrubber with segments, a playhead and a buffer.
    func poseForDemo(duration: Double, at time: Double, segments: [SponsorSegment]) {
        self.duration = duration
        self.currentTime = time
        self.bufferedTime = min(duration, time + duration * 0.28)
        self.segments = segments
        self.isPlaying = true
        self.isBuffering = false
    }

    func load(source: PlaybackSource, quality: VideoQuality = .auto, startAt: Double = 0) async {
        self.source = source
        self.duration = source.duration
        self.currentQuality = quality
        self.chapters = source.chapters
        self.error = nil
        self.hasVideo = false
        upgradeTask?.cancel()

        // Best path: one HLS manifest. AVPlayer handles bitrate adaptation,
        // codec selection, subtitles and PiP itself, so there is nothing to
        // compose and only one round-trip before the first frame.
        //
        // Quality is still honoured — an explicit choice sets a bitrate ceiling
        // on the item rather than swapping to a different URL.
        if let hls = source.hlsManifestURL {
            let item = AVPlayerItem(url: hls)
            item.preferredForwardBufferDuration = 8
            // An explicit quality caps the ladder rather than pinning it: if the
            // network can't sustain that tier, dropping below it beats stalling.
            item.preferredPeakBitRate = Self.bitrateCeiling(for: quality)
            replaceItem(with: item, startAt: startAt)
            return
        }

        let selection = StreamSelector.select(from: source, quality: quality)

        // Fast path: a single file that already contains both tracks.
        if let progressive = selection.progressive {
            replaceItem(with: AVURLAsset(url: progressive.url, options: Self.assetOptions), startAt: startAt)
            return
        }

        // Show something immediately, then upgrade.
        if let fast = StreamSelector.fastStart(from: source), startAt == 0 {
            replaceItem(with: AVURLAsset(url: fast.url, options: Self.assetOptions), startAt: 0)
        }

        guard let video = selection.video, let audio = selection.audio else {
            if player.currentItem == nil { error = "No playable stream was returned for this video." }
            return
        }

        upgradeTask = Task { [weak self] in
            guard let self else { return }
            do {
                let composition = try await Self.compose(video: video, audio: audio)
                guard !Task.isCancelled else { return }
                let resume = self.currentTime > 1 ? self.currentTime : startAt
                self.replaceItem(with: composition, startAt: resume, preserveRate: true)
            } catch {
                // The fast-start rendition is already playing, so a failure here
                // costs quality, not playback.
                if self.player.currentItem == nil {
                    self.error = "Couldn't prepare high-quality playback."
                }
            }
        }
    }

    /// Options tuned for streaming rather than editing. Precise duration would
    /// force a full index scan before the first frame.
    private static let assetOptions: [String: Any] = [
        AVURLAssetPreferPreciseDurationAndTimingKey: false
    ]

    /// Peak bitrate for each quality tier, sized a little above YouTube's own
    /// H.264 ladder so the intended rung is always reachable.
    private static func bitrateCeiling(for quality: VideoQuality) -> Double {
        switch quality {
        case .auto, .p2160: 0          // 0 means "no cap"
        case .p1440: 12_000_000
        case .p1080: 6_000_000
        case .p720: 3_000_000
        case .p480: 1_500_000
        case .p360: 800_000
        case .p240: 400_000
        }
    }

    /// Stitches separate video and audio renditions into one playable asset.
    nonisolated private static func compose(video: Stream, audio: Stream) async throws -> AVMutableComposition {
        let videoAsset = AVURLAsset(url: video.url, options: assetOptions)
        let audioAsset = AVURLAsset(url: audio.url, options: assetOptions)

        // Both assets load concurrently — sequential loading would double the
        // time to first frame.
        async let videoTracks = videoAsset.loadTracks(withMediaType: .video)
        async let audioTracks = audioAsset.loadTracks(withMediaType: .audio)
        async let videoDuration = videoAsset.load(.duration)

        let (vTracks, aTracks, dur) = try await (videoTracks, audioTracks, videoDuration)

        guard let vTrack = vTracks.first, let aTrack = aTracks.first else {
            throw InnerTubeError.noFormats
        }

        let composition = AVMutableComposition()
        let range = CMTimeRange(start: .zero, duration: dur)

        let vComp = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        try vComp?.insertTimeRange(range, of: vTrack, at: .zero)

        let aComp = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        try aComp?.insertTimeRange(range, of: aTrack, at: .zero)

        return composition
    }

    private func replaceItem(with asset: AVAsset, startAt: Double, preserveRate: Bool = false) {
        let item = AVPlayerItem(asset: asset)
        // ~8s of read-ahead: enough to ride out a cell handover without holding
        // a huge buffer in memory.
        item.preferredForwardBufferDuration = 8
        replaceItem(with: item, startAt: startAt, preserveRate: preserveRate)
    }

    private func replaceItem(with item: AVPlayerItem, startAt: Double, preserveRate: Bool = false) {
        let wasPlaying = preserveRate ? isPlaying : true
        isSwapping = true

        observeItem(item)
        player.replaceCurrentItem(with: item)

        captionOptions = []
        activeCaption = .off
        Task { await loadCaptionOptions(for: item) }

        if startAt > 0 {
            // Completion-handler form: the bare `seek` resolves to the `async`
            // overload when this is reached from an async caller.
            player.seek(
                to: CMTime(seconds: startAt, preferredTimescale: 600),
                toleranceBefore: .zero,
                toleranceAfter: .zero,
                completionHandler: { _ in }
            )
        }
        if wasPlaying { player.play(); isPlaying = true }
        isSwapping = false
    }

    // MARK: Observation

    private func observePlayer() {
        // 4Hz is plenty for a scrubber and costs far less than the 30Hz that
        // periodic observers default to being used at.
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            // The observer callback is `@Sendable`, but we asked for `.main`,
            // so this genuinely runs on the main actor. `assumeIsolated` states
            // that to the compiler rather than hopping through a `Task`, which
            // would add a frame of latency to every scrubber update.
            MainActor.assumeIsolated {
                guard let self, !self.isSwapping else { return }
                self.currentTime = time.seconds
                self.updateBuffered()
                self.checkSegments(at: time.seconds)
                self.updateNowPlayingTime()
            }
        }

        player.publisher(for: \.timeControlStatus)
            .receive(on: RunLoop.main)
            .sink { [weak self] status in
                guard let self else { return }
                self.isPlaying = status == .playing
                self.isBuffering = status == .waitingToPlayAtSpecifiedRate
            }
            .store(in: &cancellables)
    }

    private func observeItem(_ item: AVPlayerItem) {
        item.publisher(for: \.status)
            .receive(on: RunLoop.main)
            .sink { [weak self] status in
                if status == .failed {
                    self?.error = item.error?.localizedDescription ?? "Playback failed."
                }
            }
            .store(in: &cancellables)

        // `isPlaybackLikelyToKeepUp` is the honest signal that pixels are
        // coming — `.readyToPlay` fires before the first frame is decoded, and
        // crossfading the poster on that shows a black flash.
        item.publisher(for: \.isPlaybackLikelyToKeepUp)
            .receive(on: RunLoop.main)
            .sink { [weak self] ready in
                if ready { self?.hasVideo = true }
            }
            .store(in: &cancellables)

        item.publisher(for: \.duration)
            .receive(on: RunLoop.main)
            .sink { [weak self] d in
                if d.isNumeric, d.seconds > 0 { self?.duration = d.seconds }
            }
            .store(in: &cancellables)
    }

    private func updateBuffered() {
        guard let item = player.currentItem,
              let range = item.loadedTimeRanges.first?.timeRangeValue
        else { return }
        bufferedTime = range.start.seconds + range.duration.seconds
    }

    // MARK: SponsorBlock

    /// Checked on the periodic tick rather than with `addBoundaryTimeObserver`.
    ///
    /// Boundary observers sound like the right tool, but they must be
    /// re-registered whenever the segment list or the item changes, they don't
    /// fire when a seek lands *inside* a segment, and they're unreliable across
    /// the composition swap. A comparison against a sorted array on a 4Hz tick
    /// is a rounding error of CPU and is correct in every one of those cases.
    private func checkSegments(at time: Double) {
        guard !segments.isEmpty else { return }

        for segment in segments where !segment.isPointOfInterest && !segment.isFullVideo {
            guard segment.contains(time) else { continue }
            let action = categoryActions[segment.category] ?? segment.category.defaultAction

            switch action {
            case .skip:
                // Only skip forward, and only if there's somewhere to land —
                // otherwise a segment at the very end causes a seek loop.
                guard segment.end < duration - 0.4, segment.end > time else { return }
                seek(to: segment.end)
                lastSkip = segment
                Haptics.impact(.soft)
                Task { [weak self] in
                    try? await Task.sleep(for: .seconds(3.5))
                    if self?.lastSkip?.id == segment.id { self?.lastSkip = nil }
                }
                return

            case .mute:
                player.isMuted = true
                return

            case .show, .ignore:
                return
            }
        }

        // Nothing applies at this timestamp — restore audio if a mute segment
        // muted us earlier.
        if player.isMuted { player.isMuted = false }
    }

    /// Puts back a segment the user didn't want skipped.
    func undoSkip() {
        guard let skip = lastSkip else { return }
        seek(to: skip.start)
        categoryActions[skip.category] = .show
        lastSkip = nil
    }

    // MARK: Transport

    func play() {
        player.play()
        // Restore the chosen speed; `play()` always resumes at 1×.
        if playbackRate != 1.0 { player.rate = Float(playbackRate) }
        isPlaying = true
        updateNowPlaying()
    }

    func pause() {
        player.pause()
        isPlaying = false
    }

    func togglePlayPause() { isPlaying ? pause() : play() }

    func seek(to seconds: Double) {
        let clamped = min(max(0, seconds), max(0, duration))
        currentTime = clamped
        // Zero tolerance would force a keyframe-exact seek and stall visibly;
        // a small window is imperceptible and much faster.
        player.seek(
            to: CMTime(seconds: clamped, preferredTimescale: 600),
            toleranceBefore: CMTime(seconds: 0.3, preferredTimescale: 600),
            toleranceAfter: CMTime(seconds: 0.3, preferredTimescale: 600)
        )
    }

    func skip(by delta: Double) { seek(to: currentTime + delta) }

    /// Playback speed. Kept separately from `rate` because pausing sets the
    /// player's rate to 0, and resuming must restore the chosen speed rather
    /// than snapping back to 1×.
    private(set) var playbackRate: Double = 1.0

    func setPlaybackRate(_ rate: Double) {
        playbackRate = rate
        if isPlaying { player.rate = Float(rate) }
    }

    // MARK: Captions

    /// Subtitle tracks offered by the current item.
    ///
    /// Nothing here is custom: the HLS manifest carries the subtitle renditions
    /// (35 languages on a typical video), so AVFoundation already exposes them
    /// as a media selection group and renders them itself. Prism only has to
    /// present the list and set the choice.
    private(set) var captionOptions: [CaptionOption] = []
    private(set) var activeCaption: CaptionOption?

    struct CaptionOption: Identifiable, Hashable, Sendable {
        let id: String
        let title: String
        /// Nil means "off".
        let languageCode: String?

        static let off = CaptionOption(id: "off", title: "Off", languageCode: nil)
    }

    private func loadCaptionOptions(for item: AVPlayerItem) async {
        guard let group = try? await item.asset.loadMediaSelectionGroup(for: .legible) else {
            captionOptions = []
            return
        }

        // `.filterMediaOptions` drops forced subtitles, which aren't a user
        // choice — they're burned-in translations for foreign-language dialogue.
        let options = AVMediaSelectionGroup.playableMediaSelectionOptions(from: group.options)

        captionOptions = [.off] + options.compactMap { option in
            guard let code = option.locale?.identifier else { return nil }
            return CaptionOption(
                id: code,
                title: option.displayName,
                languageCode: code
            )
        }
        activeCaption = .off
    }

    func selectCaption(_ option: CaptionOption) {
        guard let item = player.currentItem else { return }
        activeCaption = option

        Task {
            guard let group = try? await item.asset.loadMediaSelectionGroup(for: .legible) else { return }
            guard let code = option.languageCode else {
                item.select(nil, in: group)
                return
            }
            let match = AVMediaSelectionGroup.playableMediaSelectionOptions(from: group.options)
                .first { $0.locale?.identifier == code }
            item.select(match, in: group)
        }
    }

    func setRate(_ rate: Float) {
        player.rate = rate
        if rate > 0 { isPlaying = true }
    }

    func setQuality(_ quality: VideoQuality) async {
        guard let source, quality != currentQuality else { return }
        await load(source: source, quality: quality, startAt: currentTime)
    }

    func teardown() {
        upgradeTask?.cancel()
        player.replaceCurrentItem(with: nil)
        isPlaying = false
        segments = []
        currentTime = 0
        duration = 0
    }

    // MARK: Now Playing

    /// Populates Control Center and the lock screen.
    private func updateNowPlaying() {
        guard let source else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: source.title,
            MPMediaItemPropertyArtist: source.author,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
        ]
        info[MPNowPlayingInfoPropertyMediaType] = MPNowPlayingInfoMediaType.video.rawValue
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func updateNowPlayingTime() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
    }
}
