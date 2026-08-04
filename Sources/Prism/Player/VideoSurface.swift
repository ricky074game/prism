import SwiftUI
import AVFoundation

/// The video itself.
///
/// Wraps `AVPlayerLayer` directly rather than using `VideoPlayer`, for two
/// reasons: `VideoPlayer` ships Apple's own controls that can't be removed, and
/// it offers no control over `videoGravity`. Both matter — PRISM draws its own
/// controls, and Shorts needs aspect-fill while the watch screen needs aspect-fit.
struct VideoSurface: UIViewRepresentable {
    let player: AVPlayer
    var gravity: AVLayerVideoGravity = .resizeAspect
    /// Given the layer once it exists, so Picture in Picture can attach to the
    /// same layer rather than starting a second player.
    var onLayerReady: ((AVPlayerLayer) -> Void)?

    func makeUIView(context: Context) -> PlayerLayerView {
        let view = PlayerLayerView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = gravity
        view.backgroundColor = .black
        onLayerReady?(view.playerLayer)
        return view
    }

    func updateUIView(_ view: PlayerLayerView, context: Context) {
        if view.playerLayer.player !== player {
            view.playerLayer.player = player
            onLayerReady?(view.playerLayer)
        }
        if view.playerLayer.videoGravity != gravity {
            view.playerLayer.videoGravity = gravity
        }
    }
}

/// A `UIView` whose backing layer *is* the player layer.
///
/// Using `layerClass` avoids a second layer and a manual frame-sync on every
/// bounds change — the layer resizes with the view for free.
final class PlayerLayerView: UIView {
    override static var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}
