//
//  FrameProviding.swift
//  garage-vision
//
//  A source of JPEG frames for the detection loop. Implemented by the live
//  camera (CameraManager) and the recorded-video replay (VideoReplaySource),
//  so the engine doesn't care which one is feeding it.
//

import Foundation

protocol FrameProviding: AnyObject, Sendable {
    /// Prepare the source (permissions, decoding setup). Throws on failure.
    func configure() async throws
    /// Begin producing frames.
    func start()
    /// Stop producing frames.
    func stop()
    /// The next available frame as JPEG, or nil if none is ready.
    func captureFrame() async -> Data?
    /// Start recording the raw footage of this run (camera only; no-op otherwise).
    func startRecording()
    /// Stop recording and persist the footage (camera saves it to Photos).
    func stopRecording()
}

extension FrameProviding {
    func startRecording() {}
    func stopRecording() {}
}