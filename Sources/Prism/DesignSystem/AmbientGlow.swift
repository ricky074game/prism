import SwiftUI
import UIKit

/// Light spill.
///
/// A prism throws colour past its own edges, and so does this: the dominant
/// colours of a thumbnail bleed out behind it as a soft halo, so the interface
/// is lit *by* the content rather than sitting next to it. It is the second half
/// of the app's visual thesis, after the spectrum scrubber.
///
/// Cost control matters here, because this sits behind scrolling content:
/// - The glow is the same image, downsampled to 16×9 **pixels** and blurred.
///   At that size the blur is essentially free and the result is a smooth
///   approximation of the image's colour field.
/// - `drawingGroup()` flattens it into one offscreen texture, so the blur is
///   rasterised once instead of every frame.
struct AmbientGlow: View {
    let image: UIImage?
    var intensity: Double = 0.55
    var blur: CGFloat = 60

    var body: some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .blur(radius: blur, opaque: false)
                .opacity(intensity)
                .drawingGroup()
                .allowsHitTesting(false)
        }
    }
}

/// Loads a thumbnail already reduced to a colour field, for use as a glow source.
@MainActor
@Observable
final class GlowSource {
    private(set) var image: UIImage?

    private var task: Task<Void, Never>?

    func load(_ url: URL?) {
        task?.cancel()
        guard let url else { image = nil; return }

        task = Task { [weak self] in
            // 16×9 points is enough colour information for a 60pt blur.
            let tiny = await ImageLoader.shared.image(for: url, targetSize: CGSize(width: 16, height: 9))
            guard !Task.isCancelled else { return }
            self?.image = tiny
        }
    }
}

// MARK: - Glass

/// The app's one surface treatment: a translucent panel with a hairline top
/// edge, used for anything that floats over content.
struct GlassPanel<Content: View>: View {
    var cornerRadius: CGFloat = Metrics.Radius.card
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(0.14), .white.opacity(0.03)],
                            startPoint: .top, endPoint: .bottom
                        ),
                        lineWidth: 0.5
                    )
            }
    }
}
