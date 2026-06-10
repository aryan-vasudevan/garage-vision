//
//  VideoReplaySource.swift
//  garage-vision
//
//  A "fake live stream": plays a bundled recording (parking.mov) on a loop and
//  samples upright frames from it on demand, so the full detection pipeline can
//  be exercised without the live camera. Frames are pulled with the track's
//  preferred transform applied, so portrait phone video comes out upright.
//

import AVFoundation
import UIKit
import SwiftUI

nonisolated final class VideoReplaySource: FrameProviding, @unchecked Sendable {
    let player: AVQueuePlayer
    private let looper: AVPlayerLooper
    private let imageGenerator: AVAssetImageGenerator

    /// Fails if the bundled video is missing.
    init?(resource: String = "parking", ext: String = "mov") {
        guard let url = Bundle.main.url(forResource: resource, withExtension: ext) else { return nil }
        let asset = AVURLAsset(url: url)
        let item = AVPlayerItem(asset: asset)
        let queue = AVQueuePlayer()
        queue.isMuted = true
        self.player = queue
        self.looper = AVPlayerLooper(player: queue, templateItem: item)

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true        // upright frames
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        generator.maximumSize = CGSize(width: 1320, height: 4000)  // cap width ~1320 (plenty for OCR)
        self.imageGenerator = generator
    }

    func configure() async throws {}

    func start() { DispatchQueue.main.async { self.player.play() } }
    func stop() { DispatchQueue.main.async { self.player.pause() } }

    func captureFrame() async -> Data? {
        let time = await MainActor.run { self.player.currentTime() }
        guard time.isNumeric else { return nil }
        do {
            let result = try await imageGenerator.image(at: time)
            return UIImage(cgImage: result.image).jpegData(compressionQuality: 0.7)
        } catch {
            return nil
        }
    }
}

/// SwiftUI view that plays the replay video.
struct VideoPreview: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerView {
        let view = PlayerView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PlayerView, context: Context) {
        uiView.playerLayer.player = player
    }

    final class PlayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}