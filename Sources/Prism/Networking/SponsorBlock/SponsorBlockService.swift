import Foundation
import CryptoKit

/// Fetches community-contributed segment data from SponsorBlock.
///
/// Uses the privacy-preserving endpoint: rather than asking "what's in video X",
/// PRISM sends only the **first four hex characters of sha256(videoID)** and
/// receives every video in that bucket (~100 videos), then filters locally. The
/// server therefore never learns which video is being watched.
///
/// Response shape verified against the live API:
/// ```
/// [ { "videoID": "eXjGWlJOhWg",
///     "segments": [ { "category": "intro",
///                     "actionType": "skip",
///                     "segment": [0, 14.827],
///                     "UUID": "5d6839…",
///                     "videoDuration": 3238.835,
///                     "locked": 0,        // Int, not Bool
///                     "votes": 0 } ] } ]
/// ```
actor SponsorBlockService {
    static let shared = SponsorBlockService()

    private let base = URL(string: "https://sponsor.ajay.app/api/")!
    private let session: URLSession
    /// Buckets are cached because one fetch covers ~100 videos — the next video
    /// the user opens is often already in hand.
    private var bucketCache: [String: (fetched: Date, videos: [BucketEntry])] = [:]
    private let bucketTTL: TimeInterval = 600

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 12
        config.urlCache = URLCache(memoryCapacity: 4 * 1024 * 1024, diskCapacity: 32 * 1024 * 1024)
        session = URLSession(configuration: config)
    }

    // MARK: Wire format

    private struct BucketEntry: Decodable {
        let videoID: String
        let segments: [WireSegment]
    }

    private struct WireSegment: Decodable {
        let category: String
        let actionType: String
        let segment: [Double]
        let UUID: String
        let locked: Int
        let votes: Int
        let videoDuration: Double?
    }

    // MARK: Fetch

    /// All segments for a video, already filtered to categories the user hasn't
    /// turned off and de-overlapped.
    func segments(for videoID: String, enabled: Set<SegmentCategory>) async -> [SponsorSegment] {
        guard !enabled.isEmpty else { return [] }

        let prefix = Self.hashPrefix(videoID)
        let bucket: [BucketEntry]

        if let cached = bucketCache[prefix], Date().timeIntervalSince(cached.fetched) < bucketTTL {
            bucket = cached.videos
        } else {
            guard let fetched = await fetchBucket(prefix: prefix, categories: enabled) else { return [] }
            bucketCache[prefix] = (Date(), fetched)
            bucket = fetched
        }

        let raw = bucket.first { $0.videoID == videoID }?.segments ?? []

        let mapped: [SponsorSegment] = raw.compactMap { w in
            guard w.segment.count == 2,
                  let category = SegmentCategory(rawValue: w.category),
                  enabled.contains(category)
            else { return nil }

            return SponsorSegment(
                id: w.UUID,
                category: category,
                start: w.segment[0],
                end: w.segment[1],
                actionType: w.actionType,
                locked: w.locked == 1,
                votes: w.votes
            )
        }

        return resolveOverlaps(mapped)
    }

    private func fetchBucket(prefix: String, categories: Set<SegmentCategory>) async -> [BucketEntry]? {
        var comps = URLComponents(
            url: base.appendingPathComponent("skipSegments").appendingPathComponent(prefix),
            resolvingAgainstBaseURL: false
        )!
        let cats = categories.map(\.rawValue)
        comps.queryItems = [
            URLQueryItem(name: "categories", value: try? String(data: JSONEncoder().encode(cats), encoding: .utf8) ?? "[]"),
            URLQueryItem(name: "actionTypes", value: #"["skip","mute","poi","full"]"#),
        ]
        guard let url = comps.url else { return nil }

        var req = URLRequest(url: url)
        // The project asks clients to identify themselves so abuse can be traced
        // to a client rather than to users.
        req.setValue("Prism/1.0 (github.com/ricky074game/prism)", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await session.data(for: req)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            return try JSONDecoder().decode([BucketEntry].self, from: data)
        } catch {
            // Segment data is an enhancement, never a blocker. A failure here
            // must not stop the video from playing.
            return nil
        }
    }

    // MARK: Rules

    /// `sha256(videoID)` → first 4 hex characters.
    nonisolated static func hashPrefix(_ videoID: String, length: Int = 4) -> String {
        let digest = SHA256.hash(data: Data(videoID.utf8))
        return digest.map { String(format: "%02x", $0) }.joined().prefix(length).lowercased()
    }

    /// Collapses overlapping submissions.
    ///
    /// Contributors often submit slightly different bounds for the same break.
    /// Playing those naively causes a double-skip that feels broken, so
    /// overlapping ranges of the same category are merged, keeping the
    /// best-supported one's identity.
    private func resolveOverlaps(_ segments: [SponsorSegment]) -> [SponsorSegment] {
        let ranges = segments.filter { !$0.isPointOfInterest && !$0.isFullVideo }
        let markers = segments.filter { $0.isPointOfInterest || $0.isFullVideo }

        let sorted = ranges.sorted { $0.start < $1.start }
        var merged: [SponsorSegment] = []

        for seg in sorted {
            guard let last = merged.last,
                  last.category == seg.category,
                  seg.start <= last.end
            else {
                merged.append(seg)
                continue
            }
            // Keep whichever submission the community trusts more.
            let winner = (seg.locked && !last.locked) || seg.votes > last.votes ? seg : last
            merged[merged.count - 1] = SponsorSegment(
                id: winner.id,
                category: last.category,
                start: last.start,
                end: max(last.end, seg.end),
                actionType: winner.actionType,
                locked: last.locked || seg.locked,
                votes: max(last.votes, seg.votes)
            )
        }

        return (merged + markers).sorted { $0.start < $1.start }
    }
}
