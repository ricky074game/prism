import Foundation

/// The client identity PRISM presents to YouTube's internal API.
///
/// Client choice is the single most consequential decision in this file. As of
/// 2026 most clients require a "GVS PO Token" — a proof-of-origin blob produced
/// by an obfuscated JavaScript VM — before they will hand out playable stream
/// URLs. A native app cannot generate one without embedding a JS engine and
/// running Google's BotGuard.
///
/// `ANDROID_VR` is the exception: it still returns full adaptive formats with no
/// PO Token. This was verified against the live API, not inferred from
/// documentation. `IOS` is deliberately *not* used — it now returns formats that
/// 403 on fetch.
///
/// If this ever breaks, the fix is almost always a new `clientVersion` or a
/// different entry here, not a rewrite of the app.
struct InnerTubeClientProfile: Sendable {
    let name: String
    let version: String
    let userAgent: String
    let extraContext: [String: Any]

    /// Primary. Verified to return adaptive formats up to 2160p without a PO Token.
    static let androidVR = InnerTubeClientProfile(
        name: "ANDROID_VR",
        version: "1.62.27",
        userAgent: "com.google.android.apps.youtube.vr.oculus/1.62.27 (Linux; U; Android 12L; eureka-user Build/SQ3A.220605.009.A1) gzip",
        extraContext: [
            "deviceMake": "Oculus",
            "deviceModel": "Quest 3",
            "osName": "Android",
            "osVersion": "12L",
            "androidSdkVersion": 32,
        ]
    )

    /// Used for metadata-only calls (search, browse). The web client is fine
    /// here because these responses carry no stream URLs to be gated.
    static let web = InnerTubeClientProfile(
        name: "WEB",
        version: "2.20260701.00.00",
        userAgent: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36",
        extraContext: [:]
    )

    func context(hl: String, gl: String) -> [String: Any] {
        var client: [String: Any] = [
            "clientName": name,
            "clientVersion": version,
            "hl": hl,
            "gl": gl,
        ]
        client.merge(extraContext) { a, _ in a }
        return ["client": client]
    }
}

enum InnerTubeError: LocalizedError {
    case badResponse(Int)
    case unplayable(reason: String)
    case noFormats
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .badResponse(let code): "YouTube returned \(code)."
        case .unplayable(let reason): reason
        case .noFormats: "No playable formats came back for this video."
        case .decoding(let what): "Couldn't read the response: \(what)."
        }
    }
}

/// A thin, dependency-free client for YouTube's internal `youtubei/v1` API.
///
/// Everything is `async` and decoding happens off the main actor.
actor InnerTubeClient {
    static let shared = InnerTubeClient()

    private let base = URL(string: "https://www.youtube.com/youtubei/v1/")!
    private let session: URLSession

    var locale: (hl: String, gl: String) = ("en", "US")

    init() {
        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = ["Accept-Language": "en-US,en;q=0.9"]
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 20
        config.waitsForConnectivity = true
        session = URLSession(configuration: config)
    }

    // MARK: Transport

    private func post(
        _ endpoint: String,
        body: [String: Any],
        profile: InnerTubeClientProfile
    ) async throws -> [String: Any] {
        var payload = body
        payload["context"] = profile.context(hl: locale.hl, gl: locale.gl)

        var req = URLRequest(url: base.appendingPathComponent(endpoint))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(profile.userAgent, forHTTPHeaderField: "User-Agent")
        req.setValue("https://www.youtube.com", forHTTPHeaderField: "Origin")
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw InnerTubeError.badResponse(-1)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw InnerTubeError.badResponse(http.statusCode)
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw InnerTubeError.decoding("root was not an object")
        }
        return json
    }

    // MARK: Playback

    /// Resolves everything needed to play a video: stream sets, duration, and
    /// the metadata shown around the player.
    func player(videoID: String) async throws -> PlaybackSource {
        let json = try await post(
            "player",
            body: [
                "videoId": videoID,
                "contentCheckOk": true,
                "racyCheckOk": true,
            ],
            profile: .androidVR
        )

        let playability = json["playabilityStatus"] as? [String: Any]
        let status = playability?["status"] as? String ?? "UNKNOWN"

        guard status == "OK" else {
            // Surface YouTube's own wording — it is usually more accurate about
            // *why* than anything we could invent (age gate, region, private).
            let reason = (playability?["reason"] as? String)
                ?? (playability?["messages"] as? [String])?.first
                ?? "This video can't be played."
            throw InnerTubeError.unplayable(reason: reason)
        }

        let streaming = json["streamingData"] as? [String: Any] ?? [:]
        let adaptive = (streaming["adaptiveFormats"] as? [[String: Any]]) ?? []
        let progressive = (streaming["formats"] as? [[String: Any]]) ?? []

        let details = json["videoDetails"] as? [String: Any] ?? [:]

        let streams = (adaptive + progressive).compactMap(Stream.init(json:))
        guard !streams.isEmpty else { throw InnerTubeError.noFormats }

        return PlaybackSource(
            videoID: videoID,
            title: details["title"] as? String ?? "",
            author: details["author"] as? String ?? "",
            channelID: details["channelId"] as? String ?? "",
            duration: Double(details["lengthSeconds"] as? String ?? "") ?? 0,
            isLive: details["isLiveContent"] as? Bool ?? false,
            viewCount: Int(details["viewCount"] as? String ?? "") ?? 0,
            streams: streams
        )
    }

    // MARK: Metadata

    func search(_ query: String, continuation: String? = nil) async throws -> [String: Any] {
        var body: [String: Any] = [:]
        if let continuation {
            body["continuation"] = continuation
        } else {
            body["query"] = query
            // EgIQAQ%3D%3D restricts results to videos.
            body["params"] = "EgIQAQ%3D%3D"
        }
        return try await post("search", body: body, profile: .web)
    }

    func browse(browseID: String, params: String? = nil, continuation: String? = nil) async throws -> [String: Any] {
        var body: [String: Any] = [:]
        if let continuation {
            body["continuation"] = continuation
        } else {
            body["browseId"] = browseID
            if let params { body["params"] = params }
        }
        return try await post("browse", body: body, profile: .web)
    }

    /// Related videos and the up-next queue for the watch screen.
    func next(videoID: String) async throws -> [String: Any] {
        try await post("next", body: ["videoId": videoID], profile: .web)
    }
}
