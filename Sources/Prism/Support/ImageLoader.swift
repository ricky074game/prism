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

    /// Decodes straight to the display size. The full-size bitmap is never
    /// materialised, so peak memory is bounded by the *displayed* size.
    nonisolated static func downsample(data: Data, to pointSize: CGSize) -> UIImage? {
        let scale = UIScreen.main.scale
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
    @State private var didAnimate = false

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .transition(.opacity)
            } else {
                placeholder()
            }
        }
        .task(id: url) { await load() }
        .motion(Motion.quick, value: image != nil)
    }

    private func load() async {
        guard let url else { return }
        image = await ImageLoader.shared.image(for: url, targetSize: targetSize)
    }
}

/// The default placeholder: a slow shimmer over the surface colour. Calm enough
/// that a screen full of them doesn't strobe.
struct ShimmerPlaceholder: View {
    @State private var phase: CGFloat = -1

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
                withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
    }
}
