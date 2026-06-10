//
//  FrameStore.swift
//  garage-vision
//
//  Bridges the camera's background capture queue and the async detection loop.
//  The loop asks for a single frame; the next delivered camera frame is converted
//  to JPEG and handed back. This avoids converting every 30fps frame when we only
//  need one every ~2 seconds.
//

import Foundation
import CoreVideo
import CoreImage
import UIKit

nonisolated final class FrameStore: @unchecked Sendable {
    private let lock = NSLock()
    private var pending: CheckedContinuation<Data?, Never>?
    private var wantsFrame = false
    private var generation = 0
    private let ciContext = CIContext()

    /// Longest-side cap for the uploaded image. Kept high (near-native) so the
    /// workflow's driveway zone — which is calibrated to a full portrait frame —
    /// lines up with the vehicle detections. Only guards against absurd sizes.
    private let maxDimension: CGFloat = 3840

    /// Suspend until the next camera frame arrives (as JPEG), or `nil` on timeout.
    func requestFrame(timeout: TimeInterval) async -> Data? {
        await withCheckedContinuation { (cont: CheckedContinuation<Data?, Never>) in
            lock.lock()
            generation &+= 1
            let gen = generation
            let stale = pending
            pending = cont
            wantsFrame = true
            lock.unlock()

            stale?.resume(returning: nil)   // supersede any in-flight request

            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { [weak self] in
                self?.fulfillIfCurrent(gen, nil)
            }
        }
    }

    /// Called from the capture delegate on the camera's background queue.
    func submit(_ pixelBuffer: CVPixelBuffer) {
        lock.lock()
        guard wantsFrame, pending != nil else { lock.unlock(); return }
        wantsFrame = false
        let gen = generation
        lock.unlock()

        let data = jpeg(from: pixelBuffer)
        fulfillIfCurrent(gen, data)
    }

    private func fulfillIfCurrent(_ gen: Int, _ data: Data?) {
        lock.lock()
        guard gen == generation, let cont = pending else { lock.unlock(); return }
        pending = nil
        wantsFrame = false
        lock.unlock()
        cont.resume(returning: data)
    }

    private func jpeg(from pixelBuffer: CVPixelBuffer) -> Data? {
        var image = CIImage(cvPixelBuffer: pixelBuffer)
        let longest = max(image.extent.width, image.extent.height)
        if longest > maxDimension {
            let scale = maxDimension / longest
            image = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        }
        guard let cg = ciContext.createCGImage(image, from: image.extent) else { return nil }
        return UIImage(cgImage: cg).jpegData(compressionQuality: 0.7)
    }
}
