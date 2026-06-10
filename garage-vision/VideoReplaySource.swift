//
//  VideoReplaySource.swift
//  garage-vision
//
//  A "fake live stream": plays a bundled recording (parking.mov) on a loop and
//  samples upright frames from it on demand, so the full detection pipeline can
//  be exercised without the live camera.
//
//  Frames are pulled from the PLAYER's own video output (AVPlayerItemVideoOutput),
//  not a separate AVAssetImageGenerator. On a real device the two would compete
//  for the limited hardware video decoder on a 4K clip and the generator hangs;
//  sharing the player's decode session avoids that.
//

import AVFoundation
import CoreImage
import UIKit
import SwiftUI

nonisolated final class VideoReplaySource: FrameProviding, @unchecked Sendable {
    let player: AVPlayer
    private let asset: AVURLAsset
    private let output: AVPlayerItemVideoOutput
    private let ciContext = CIContext()
    private let outputColorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    private let maxDimension: CGFloat = 1320
    private var orientation: CGImagePropertyOrientation = .up
    private var loopObserver: NSObjectProtocol?

    /// Fails if the bundled video is missing.
    init?(resource: String = "parking", ext: String = "mov") {
        guard let url = Bundle.main.url(forResource: resource, withExtension: ext) else { return nil }
        let asset = AVURLAsset(url: url)
        self.asset = asset

        let item = AVPlayerItem(asset: asset)
        let attrs: [String: Any] = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: attrs)
        item.add(output)
        self.output = output

        let player = AVPlayer(playerItem: item)
        player.isMuted = true
        player.actionAtItemEnd = .none
        self.player = player

        loopObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { [weak player] _ in
            player?.seek(to: .zero)
            player?.play()
        }
    }

    deinit {
        if let loopObserver { NotificationCenter.default.removeObserver(loopObserver) }
    }

    func configure() async throws {
        // Learn the display orientation so portrait phone video comes out upright.
        if let track = try await asset.loadTracks(withMediaType: .video).first {
            let transform = try await track.load(.preferredTransform)
            orientation = Self.orientation(from: transform)
        }
    }

    func start() { DispatchQueue.main.async { self.player.play() } }
    func stop() { DispatchQueue.main.async { self.player.pause() } }

    func captureFrame() async -> Data? {
        let time = await MainActor.run { self.player.currentTime() }
        guard time.isNumeric,
              let pixelBuffer = output.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: nil) else {
            return nil
        }

        var image = CIImage(cvPixelBuffer: pixelBuffer).oriented(orientation)
        // The recorded clip is a mirrored selfie; flip it horizontally so it matches
        // the un-mirrored live camera (the workflow has no flip step).
        let e = image.extent
        image = image.transformed(by: CGAffineTransform(translationX: e.minX + e.maxX, y: 0).scaledBy(x: -1, y: 1))
        let longest = max(image.extent.width, image.extent.height)
        if longest > maxDimension {
            let scale = maxDimension / longest
            image = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        }
        // Convert HDR (BT.2020 HLG) into plain sRGB so the model sees a natural,
        // non-blown-out image instead of crushed midtones / clipped highlights.
        guard let cg = ciContext.createCGImage(image, from: image.extent,
                                               format: .RGBA8, colorSpace: outputColorSpace) else {
            return nil
        }
        return UIImage(cgImage: cg).jpegData(compressionQuality: 0.7)
    }

    private static func orientation(from t: CGAffineTransform) -> CGImagePropertyOrientation {
        let (a, b, c, d) = (t.a.rounded(), t.b.rounded(), t.c.rounded(), t.d.rounded())
        if a == 0 && b == 1 && c == -1 && d == 0 { return .right }   // 90° CW (portrait)
        if a == 0 && b == -1 && c == 1 && d == 0 { return .left }    // 90° CCW
        if a == -1 && b == 0 && c == 0 && d == -1 { return .down }   // 180°
        return .up
    }
}

/// SwiftUI view that plays the replay video.
struct VideoPreview: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerView {
        let view = PlayerView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspectFill
        view.playerLayer.wantsExtendedDynamicRangeContent = false   // tone HDR down to SDR for the preview
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