import AVKit
import AVFoundation
import Observation

/// Picture in Picture.
///
/// Driven by `AVPictureInPictureController` attached to the same `AVPlayerLayer`
/// the watch screen already renders, so the handoff is a genuine continuation
/// rather than a second player starting from scratch.
///
/// Two things make it work at all, and both are easy to miss:
///
/// - The audio session must be `.playback` and **active**. With the default
///   session, iOS tears PiP down the moment the app backgrounds.
/// - `canStartPictureInPictureAutomaticallyFromInline` is what makes PiP begin
///   when the user swipes home, which is when people actually want it. Without
///   it they'd have to find the button first.
@MainActor
@Observable
final class PictureInPictureController: NSObject {
    private(set) var isSupported = AVPictureInPictureController.isPictureInPictureSupported()
    private(set) var isActive = false
    private(set) var isPossible = false

    private var controller: AVPictureInPictureController?

    /// Attaches to a layer. Called when the video surface appears.
    func attach(to layer: AVPlayerLayer) {
        guard isSupported else { return }
        guard controller?.playerLayer !== layer else { return }

        let controller = AVPictureInPictureController(playerLayer: layer)
        controller?.delegate = self
        controller?.canStartPictureInPictureAutomaticallyFromInline = true
        self.controller = controller

        // `isPictureInPicturePossible` only turns true once the layer has real
        // video to show, so it's observed rather than read once.
        possibleObservation = controller?.observe(\.isPictureInPicturePossible, options: [.initial, .new]) { [weak self] controller, _ in
            Task { @MainActor in self?.isPossible = controller.isPictureInPicturePossible }
        }
    }

    private var possibleObservation: NSKeyValueObservation?

    func toggle() {
        guard let controller else { return }
        if controller.isPictureInPictureActive {
            controller.stopPictureInPicture()
        } else {
            controller.startPictureInPicture()
        }
    }

    func detach() {
        possibleObservation?.invalidate()
        possibleObservation = nil
        controller = nil
        isPossible = false
    }
}

extension PictureInPictureController: AVPictureInPictureControllerDelegate {
    nonisolated func pictureInPictureControllerDidStartPictureInPicture(_ controller: AVPictureInPictureController) {
        Task { @MainActor in isActive = true }
    }

    nonisolated func pictureInPictureControllerDidStopPictureInPicture(_ controller: AVPictureInPictureController) {
        Task { @MainActor in isActive = false }
    }

    /// Called when the user taps the restore button in the PiP window. Answering
    /// `true` tells the system the app has put its own UI back — the watch
    /// screen is still mounted underneath, so there is nothing to rebuild.
    nonisolated func pictureInPictureController(
        _ controller: AVPictureInPictureController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completion: @escaping (Bool) -> Void
    ) {
        completion(true)
    }
}
