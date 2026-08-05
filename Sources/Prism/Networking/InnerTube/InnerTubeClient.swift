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

    /// Primary.
    ///
    /// The visionOS client is the one client that still returns a real
    /// `hlsManifestUrl` — verified across multiple videos — and it needs no PO
    /// Token, no API key, and no JavaScript signature solving. That manifest is
    /// worth a great deal: it carries a full H.264 ladder from 144p to 1080p,
    /// so AVPlayer gets adaptive bitrate, subtitles, AirPlay and Picture in
    /// Picture for free from a single URL.
    static let visionOS = InnerTubeClientProfile(
        name: "VISIONOS",
        version: "1.02",
        userAgent: "com.google.ios.youtube/1.02 (RealityDevice17,1; U; CPU visionOS 26_5 like Mac OS X)",
        extraContext: [
            "deviceMake": "Apple",
            "deviceModel": "RealityDevice17,1",
            "osName": "visionOS",
            "osVersion": "26.5.23O471",
        ]
    )

    /// Fallback, and the only route to >1080p.
    ///
    /// Returns adaptive formats (including 1440p/2160p AV1) but no HLS
    /// manifest, so using it means compositing separate audio and video.
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

    /// The only client that accepts our account token, and therefore the only
    /// route to the signed-in user's own data.
    ///
    /// The token comes from YouTube's TV OAuth client, and InnerTube checks the
    /// token against the client the request claims to be. Sent with any other
    /// client it isn't ignored — the whole request fails with HTTP 400
    /// "Request contains an invalid argument". Verified against live responses:
    /// an identical `browse` returns 200 without the header and 400 with it, on
    /// WEB, VISIONOS and ANDROID_VR alike.
    ///
    /// So this profile exists to be the *only* one the token is attached to.
    /// See `isAccountClient`.
    static let tv = InnerTubeClientProfile(
        name: "TVHTML5",
        version: "7.20250101.15.00",
        userAgent: "Mozilla/5.0 (ChromiumStylePlatform) Cobalt/Version",
        extraContext: [:]
    )

    /// Whether an account token may ride along with this client.
    var isAccountClient: Bool { name == "TVHTML5" }

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
        // Every request carries visitorData, in the context *and* the header.
        // Omitting it is what produces spurious LOGIN_REQUIRED failures.
        let visitorData = await VisitorSession.shared.token()

        var payload = body
        var context = profile.context(hl: locale.hl, gl: locale.gl)
        if let visitorData, var client = context["client"] as? [String: Any] {
            client["visitorData"] = visitorData
            context["client"] = client
        }
        payload["context"] = context

        var url = base.appendingPathComponent(endpoint)
        // No API key: it is no longer validated, and sending one adds nothing.
        url.append(queryItems: [URLQueryItem(name: "prettyPrint", value: "false")])

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(profile.userAgent, forHTTPHeaderField: "User-Agent")
        req.setValue("https://www.youtube.com", forHTTPHeaderField: "Origin")
        if let visitorData {
            req.setValue(visitorData, forHTTPHeaderField: "X-Goog-Visitor-Id")
        }

        // Sign as the user — but only on the client whose token this is.
        //
        // Attaching it everywhere is worse than useless: InnerTube rejects the
        // *whole request* with HTTP 400 when the token doesn't match the client
        // context, so signing in used to break playback, the feed and the
        // library all at once, and every failure was swallowed by a `try?` and
        // shown as "empty".
        if profile.isAccountClient {
            for (field, value) in await AccountSession.shared.authHeaders() {
                req.setValue(value, forHTTPHeaderField: field)
            }
        }
        req.httpShouldHandleCookies = true

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

    /// Resolves everything needed to play a video.
    ///
    /// Tries visionOS first for its HLS manifest, and falls back to the
    /// Android VR client's adaptive formats if that comes back without one.
    /// A video that fails on both is genuinely unplayable (age-gated,
    /// members-only, region-locked), not a transport problem.
    func player(videoID: String) async throws -> PlaybackSource {
        do {
            let source = try await resolve(videoID: videoID, profile: .visionOS)
            if source.hlsManifestURL != nil || !source.streams.isEmpty { return source }
        } catch let error as InnerTubeError {
            // An explicit "you can't watch this" is usually final — but a
            // helper server can reach content no in-app client can, so try that
            // before giving up on the user's behalf.
            if case .unplayable = error {
                if HelperClient.isConfigured,
                   let viaHelper = try? await HelperClient.shared.resolve(videoID: videoID) {
                    return viaHelper
                }
                throw error
            }
        }

        if let source = try? await resolve(videoID: videoID, profile: .androidVR) {
            return source
        }

        // Last resort. Reached when every in-app client failed for a reason
        // other than an explicit refusal.
        if HelperClient.isConfigured {
            return try await HelperClient.shared.resolve(videoID: videoID)
        }
        return try await resolve(videoID: videoID, profile: .androidVR)
    }

    private func resolve(videoID: String, profile: InnerTubeClientProfile) async throws -> PlaybackSource {
        var json = try await post(
            "player",
            body: [
                "videoId": videoID,
                "contentCheckOk": true,
                "racyCheckOk": true,
            ],
            profile: profile
        )

        var playability = json["playabilityStatus"] as? [String: Any]
        var status = playability?["status"] as? String ?? "UNKNOWN"

        // A stale visitorData reads as LOGIN_REQUIRED — but so does an age gate,
        // and those need opposite handling. Re-minting the token for an
        // age-restricted video throws away a perfectly good session token and
        // makes the *next* video pay for a fresh mint, so the reason is checked
        // before assuming the token is at fault.
        let reasonText = (playability?["reason"] as? String)?.lowercased() ?? ""
        let isAgeGate = reasonText.contains("age") || reasonText.contains("confirm your age")

        if status == "LOGIN_REQUIRED", !isAgeGate {
            await VisitorSession.shared.invalidate()
            json = try await post(
                "player",
                body: ["videoId": videoID, "contentCheckOk": true, "racyCheckOk": true],
                profile: profile
            )
            playability = json["playabilityStatus"] as? [String: Any]
            status = playability?["status"] as? String ?? "UNKNOWN"
        }

        guard status == "OK" else {
            // Surface YouTube's own wording — it is usually more accurate about
            // *why* than anything we could invent (age gate, region, private).
            var reason = (playability?["reason"] as? String)
                ?? (playability?["messages"] as? [String])?.first
                ?? "This video can't be played."

            // An age gate is the one failure the user can actually do something
            // about, so say what that is rather than repeating YouTube's
            // instruction to sign in on a screen that has no sign-in button.
            if isAgeGate {
                reason = await AccountSession.shared.isSignedIn
                    ? "This video is age-restricted, and your account isn't old enough to watch it."
                    : "This video is age-restricted. Sign in to your account in Settings to watch it."
            }

            throw InnerTubeError.unplayable(reason: reason)
        }

        let streaming = json["streamingData"] as? [String: Any] ?? [:]
        let adaptive = (streaming["adaptiveFormats"] as? [[String: Any]]) ?? []
        let progressive = (streaming["formats"] as? [[String: Any]]) ?? []

        let details = json["videoDetails"] as? [String: Any] ?? [:]

        let streams = (adaptive + progressive).compactMap(Stream.init(json:))
        let hls = (streaming["hlsManifestUrl"] as? String).flatMap(URL.init(string:))

        guard hls != nil || !streams.isEmpty else { throw InnerTubeError.noFormats }

        let description = details["shortDescription"] as? String
        let chapters = ChapterParser.chapters(from: json, description: description)

        return PlaybackSource(
            videoID: videoID,
            title: details["title"] as? String ?? "",
            author: details["author"] as? String ?? "",
            channelID: details["channelId"] as? String ?? "",
            duration: Double(details["lengthSeconds"] as? String ?? "") ?? 0,
            isLive: details["isLiveContent"] as? Bool ?? false,
            viewCount: Int(details["viewCount"] as? String ?? "") ?? 0,
            streams: streams,
            hlsManifestURL: hls,
            description: description,
            chapters: chapters
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

    /// A browse for the signed-in user's own data.
    ///
    /// Goes through the TV client because that's the only one the account token
    /// is valid for. Signed out it's a normal anonymous browse, so callers
    /// don't need to branch — they just get an empty result, which is the
    /// truth.
    func accountBrowse(browseID: String, continuation: String? = nil) async throws -> [String: Any] {
        var body: [String: Any] = [:]
        if let continuation {
            body["continuation"] = continuation
        } else {
            body["browseId"] = browseID
        }
        return try await post("browse", body: body, profile: .tv)
    }

    /// Related videos and the up-next queue for the watch screen.
    func next(videoID: String) async throws -> [String: Any] {
        try await post("next", body: ["videoId": videoID], profile: .web)
    }

    /// Redeems a continuation token — the next page of comments, replies, or a
    /// re-sorted comment list.
    func next(continuation: String) async throws -> [String: Any] {
        try await post("next", body: ["continuation": continuation], profile: .web)
    }
}
