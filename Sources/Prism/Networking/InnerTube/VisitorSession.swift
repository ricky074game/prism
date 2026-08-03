import Foundation

/// Holds the `visitorData` token every InnerTube request needs.
///
/// This is the single most important piece of session state in the app, and the
/// least obvious. Without it, InnerTube answers `LOGIN_REQUIRED` for essentially
/// every video — which reads exactly like an IP ban and is almost always
/// misdiagnosed as one. With it, sustained bursts succeed without throttling.
///
/// The token is minted once from `youtubei/v1/visitor_id`, cached to disk, and
/// reused. It identifies a *session*, not a person — no account, no cookies.
actor VisitorSession {
    static let shared = VisitorSession()

    private var cached: String?
    private var mintTask: Task<String?, Never>?

    private let defaultsKey = "innertube.visitorData"
    private let mintedAtKey = "innertube.visitorData.mintedAt"
    /// Tokens keep working far longer than this, but refreshing weekly is cheap
    /// insurance against a stale one silently degrading results.
    private let maxAge: TimeInterval = 7 * 24 * 3600

    /// Returns a usable token, minting one if necessary.
    ///
    /// Concurrent callers share a single in-flight mint rather than each firing
    /// their own request.
    func token() async -> String? {
        if let cached { return cached }

        if let stored = UserDefaults.standard.string(forKey: defaultsKey) {
            let age = Date().timeIntervalSince1970 - UserDefaults.standard.double(forKey: mintedAtKey)
            if age < maxAge {
                cached = stored
                return stored
            }
        }

        if let mintTask { return await mintTask.value }

        let task = Task<String?, Never> { await Self.mint() }
        mintTask = task
        let minted = await task.value
        mintTask = nil

        if let minted {
            cached = minted
            UserDefaults.standard.set(minted, forKey: defaultsKey)
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: mintedAtKey)
        }
        return minted
    }

    /// Called when a request comes back `LOGIN_REQUIRED`, which is the symptom
    /// of a token that has gone stale.
    func invalidate() {
        cached = nil
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }

    private static func mint() async -> String? {
        let url = URL(string: "https://www.youtube.com/youtubei/v1/visitor_id?prettyPrint=false")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "context": [
                "client": [
                    "clientName": "WEB",
                    "clientVersion": "2.20260701.00.00",
                    "hl": "en",
                    "gl": "US",
                ]
            ]
        ])

        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let context = json["responseContext"] as? [String: Any],
              let visitorData = context["visitorData"] as? String
        else { return nil }

        return visitorData
    }
}
