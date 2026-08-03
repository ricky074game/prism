import SwiftUI
import UIKit
import CryptoKit

/// Thumbnail loading.
///
/// `AsyncImage` is not usable in a scrolling feed: it decodes full-resolution
/// JPEGs on the main thread, keeps no memory cache, and restarts its request
/// every time the view is recycled. In a feed of 1280×720 thumbnails displayed
/// at 180pt wide that is ~10× the pixels needed, decoded in the worst possible
/// place.
///
/// This loader instead:
/// - **Downsamples during decode** via `CGImageSourceCreateThumbnailAtIndex`, so
///   the full bitmap never exists in memory.
/// - Caches decoded `UIImage`s in an `NSCache` keyed by URL *and target size*,
///   with a cost function so the cache evicts by bytes rather than count.
/// - Lets `URLCache` handle bytes-on-disk, which it already does well.
/// - Coalesces duplicate in-flight requests, so a URL appearing twice in a feed
///   is fetched once.
actor ImageLoader {
    static let shared = ImageLoader()

    private let memory: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.totalCostLimit = 96 * 1024 * 1024   // ~96MB of decoded bitmaps
        c.countLimit = 400
        return c
    }()

    private var inFlight: [String: Task<UIImage?, Never>] = [:]

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(
            memoryCapacity: 32 * 1024 * 1024,
            diskCapacity: 512 * 1024 * 1024
        )
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.httpMaximumConnectionsPerHost = 8
        return URLSession(configuration: config)
    }()

    private func key(_ url: URL, _ size: CGSize) -> String {
        "\(url.absoluteString)|\(Int(size.width))x\(Int(size.height))"
    }

    /// Memory-cache lookup only — never touches the network.
    ///
    /// Lets a view render a cached image immediately instead of fading it in.
    func cached(for url: URL, targetSize: CGSize) -> UIImage? {
        memory.object(forKey: key(url, targetSize) as NSString)
    }

    func image(for url: URL, targetSize: CGSize) async -> UIImage? {
        let k = key(url, targetSize)

        if let cached = memory.object(forKey: k as NSString) { return cached }
        if let running = inFlight[k] { return await running.value }

        let task = Task<UIImage?, Never> { [session] in
            guard let (data, _) = try? await session.data(from: url) else { return nil }
            return Self.downsample(data: data, to: targetSize)
        }
        inFlight[k] = task

        let image = await task.value
        inFlight[k] = nil

        if let image {
            // Cost in bytes so eviction tracks real memory pressure.
            let cost = Int(image.size.width * image.size.height * image.scale * image.scale * 4)
            memory.setObject(image, forKey: k as NSString, cost: cost)
        }
        return image
    }

    /// Warm the cache for URLs about to scroll into view.
    func prefetch(_ urls: [URL], targetSize: CGSize) {
        for url in urls {
            let k = key(url, targetSize)
            guard memory.object(forKey: k as NSString) == nil, inFlight[k] == nil else { continue }
            Task { _ = await image(for: url, targetSize: targetSize) }
        }
    }

    /// Screen scale, captured once at launch.
    ///
    /// `UIScreen.main` is main-actor isolated and `downsample` runs off the main
    /// actor by design, so this is read once from `PrismApp.init` rather than
    /// per call. A lazy `static let` would be worse, not better: it initialises
    /// on first *access*, which here is a background decode.
    ///
    /// 3.0 is the right default — every device with a notch or Dynamic Island
    /// is @3x, and a wrong guess costs a slightly soft or slightly large
    /// thumbnail for one frame, not a crash.
    nonisolated(unsafe) static var screenScale: CGFloat = 3.0

    /// Decodes straight to the display size. The full-size bitmap is never
    /// materialised, so peak memory is bounded by the *displayed* size.
    nonisolated static func downsample(data: Data, to pointSize: CGSize) -> UIImage? {
        let scale = screenScale
        let maxPixel = max(pointSize.width, pointSize.height) * scale
        guard maxPixel > 0 else { return UIImage(data: data) }

        let srcOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let src = CGImageSourceCreateWithData(data as CFData, srcOptions) else { return nil }

        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,   // decode now, off the main thread
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ] as CFDictionary

        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, options) else { return nil }
        return UIImage(cgImage: cg, scale: scale, orientation: .up)
    }

    func clearMemory() { memory.removeAllObjects() }
}

// MARK: - View

/// Drop-in thumbnail view. Fades in only on a genuine network load — a cache hit
/// renders immediately, because animating in something that was already there
/// reads as slowness.
struct RemoteImage<Placeholder: View>: View {
    let url: URL?
    let targetSize: CGSize
    var contentMode: ContentMode = .fill
    @ViewBuilder var placeholder: () -> Placeholder

    @State private var image: UIImage?
    @State private var opacity: Double = 0

    var body: some View {
        ZStack {
            // The placeholder stays mounted underneath rather than being
            // swapped out by a transition. A `.transition` here would be
            // driven by the same transaction as the placeholder's own
            // `repeatForever` shimmer, and a repeating animation in the
            // transaction can leave the fade stranded part-way — thumbnails
            // render permanently washed out.
            if image == nil {
                placeholder()
            }

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .opacity(opacity)
            }
        }
        .task(id: url) { await load() }
    }

    private func load() async {
        guard let url else { return }

        // A cache hit renders instantly — animating in something that was
        // already in memory just reads as slowness.
        if let cached = await ImageLoader.shared.cached(for: url, targetSize: targetSize) {
            image = cached
            opacity = 1
            return
        }

        let loaded = await ImageLoader.shared.image(for: url, targetSize: targetSize)
        guard let loaded else { return }
        image = loaded
        withAnimation(.easeOut(duration: 0.22)) { opacity = 1 }
    }
}

/// The default placeholder: a slow shimmer over the surface colour. Calm enough
/// that a screen full of them doesn't strobe.
struct ShimmerPlaceholder: View {
    @State private var phase: CGFloat = -1

    /// Screenshot runs render the plain fill. A `repeatForever` animation means
    /// the render loop never settles, so a captured frame can catch the sweep
    /// mid-flight and look like a rendering fault rather than a loading state.
    private var animates: Bool { !DemoData.isEnabled }

    var body: some View {
        Rectangle()
            .fill(Palette.surfaceRaised)
            .overlay {
                GeometryReader { geo in
                    LinearGradient(
                        colors: [.clear, .white.opacity(0.05), .clear],
                        startPoint: .leading, endPoint: .trailing
                    )
                    .frame(width: geo.size.width * 0.6)
                    .offset(x: phase * geo.size.width * 1.6)
                }
            }
            .clipped()
            .onAppear {
                guard animates else { return }
                // Scoped to its own transaction so the repeating animation
                // can't be inherited by anything drawn alongside it.
                withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
    }
}
