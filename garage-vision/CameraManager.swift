//
//  CameraManager.swift
//  garage-vision
//
//  Owns the AVCaptureSession for the front camera and produces upright,
//  un-mirrored JPEG frames on demand. Marked `nonisolated` so its session work
//  stays off the main actor; UI state lives in DetectionEngine instead.
//

import AVFoundation
import CoreMedia

enum CameraError: LocalizedError {
    case permissionDenied
    case noCamera
    case cannotAddInput
    case cannotAddOutput

    var errorDescription: String? {
        switch self {
        case .permissionDenied: return "Camera access was denied. Enable it in Settings."
        case .noCamera: return "No front camera found on this device."
        case .cannotAddInput: return "Could not attach the camera input."
        case .cannotAddOutput: return "Could not attach the video output."
        }
    }
}

nonisolated final class CameraManager: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, FrameProviding, @unchecked Sendable {
    let session = AVCaptureSession()
    let frameStore = FrameStore()

    private let sessionQueue = DispatchQueue(label: "garage.camera.session")
    private let videoQueue = DispatchQueue(label: "garage.camera.video")
    private let videoOutput = AVCaptureVideoDataOutput()

    /// Request permission (if needed) and wire up the session. Throws on failure.
    func configure() async throws {
        try await ensureAuthorized()
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            sessionQueue.async {
                do {
                    try self.configureSession()
                    cont.resume()
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
    }

    func start() {
        sessionQueue.async {
            if !self.session.isRunning { self.session.startRunning() }
        }
    }

    func stop() {
        sessionQueue.async {
            if self.session.isRunning { self.session.stopRunning() }
        }
    }

    /// Grab the next frame as JPEG, or nil if none arrives in time.
    func captureFrame() async -> Data? {
        await frameStore.requestFrame(timeout: 2.0)
    }

    // MARK: - Setup

    private func ensureAuthorized() async throws {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return
        case .notDetermined:
            let granted = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
                AVCaptureDevice.requestAccess(for: .video) { cont.resume(returning: $0) }
            }
            if !granted { throw CameraError.permissionDenied }
        default:
            throw CameraError.permissionDenied
        }
    }

    private func configureSession() throws {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        session.sessionPreset = .high

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
            throw CameraError.noCamera
        }
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else { throw CameraError.cannotAddInput }
        session.addInput(input)

        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: videoQueue)
        guard session.canAddOutput(videoOutput) else { throw CameraError.cannotAddOutput }
        session.addOutput(videoOutput)

        if let connection = videoOutput.connection(with: .video) {
            // Rotate to portrait so plates read upright for OCR.
            if connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
            }
            // Do NOT mirror: a mirrored front-camera image flips the plate text.
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = false
            }
        }
    }

    // MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        frameStore.submit(pixelBuffer)
    }
}
