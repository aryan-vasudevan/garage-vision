//
//  DetectionEngine.swift
//  garage-vision
//
//  The ~2s loop: grab a frame -> Custom Workflow 5 -> match plate -> trigger ESP32.
//  Frames come from a swappable FrameProviding source (live camera or video replay).
//

import Foundation
import Combine
import UIKit

@MainActor
final class DetectionEngine: ObservableObject {
    enum Status: Equatable {
        case stopped
        case scanning
        case processing
        case matched
        case error(String)
    }

    struct LogEntry: Identifiable {
        let id = UUID()
        let date: Date
        let message: String
    }

    @Published private(set) var status: Status = .stopped
    @Published private(set) var isRunning = false
    @Published private(set) var sourceReady = false
    @Published private(set) var carInZone = false
    /// The most recent plate the OCR read (persists until a new one is read).
    @Published private(set) var lastPlateText: String?
    /// Whether `lastPlateText` matched the target plate.
    @Published private(set) var lastPlateMatched = false
    @Published private(set) var lastTrigger: Date?
    @Published private(set) var lastOpenedPlate: String?
    @Published private(set) var log: [LogEntry] = []
    /// Bumped each time the opener actually fires, to drive the on-screen flash/haptic.
    @Published private(set) var openPulse = 0

    private(set) var source: FrameProviding

    private var loopTask: Task<Void, Never>?
    private var warmedUp = false

    private var roboflow: RoboflowClient {
        RoboflowClient(apiKey: AppConfig.roboflowAPIKey, endpoint: AppConfig.roboflowEndpoint)
    }

    init(source: FrameProviding) {
        self.source = source
    }

    func prepareSource() async {
        guard !sourceReady else { return }
        do {
            try await source.configure()
            sourceReady = true
            addLog("Source ready.")
            warmUp()
        } catch {
            status = .error(error.localizedDescription)
            addLog("Source error: \(error.localizedDescription)")
        }
    }

    /// Fire one throwaway inference so Roboflow loads its models before the first
    /// real car appears (the serverless cold start is otherwise ~5-10s). Runs once.
    private func warmUp() {
        guard !warmedUp, AppConfig.canRun else { return }
        warmedUp = true
        Task {
            addLog("Warming up Roboflow…")
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: 96, height: 96))
            let jpeg = renderer.jpegData(withCompressionQuality: 0.5) { ctx in
                UIColor.darkGray.setFill()
                ctx.fill(CGRect(x: 0, y: 0, width: 96, height: 96))
            }
            _ = try? await roboflow.detectPlate(in: jpeg)
            addLog("Roboflow warm — ready.")
        }
    }

    /// Swap the frame source (camera <-> video). Only allowed while stopped.
    func switchSource(to newSource: FrameProviding) async {
        guard !isRunning else { return }
        source.stop()
        source = newSource
        sourceReady = false
        status = .stopped
        await prepareSource()
    }

    func start() {
        guard !isRunning, sourceReady else { return }
        isRunning = true
        status = .scanning
        addLog("Started watching.")
        loopTask = Task { [weak self] in await self?.runLoop() }
    }

    func stop() {
        isRunning = false
        loopTask?.cancel()
        loopTask = nil
        source.stop()
        status = .stopped
        carInZone = false
        lastPlateText = nil
        lastPlateMatched = false
        addLog("Stopped.")
    }

    /// Grab the exact frame the active source is sending to Roboflow and save it to
    /// Photos, so the driveway zone can be redrawn on the real live-camera framing.
    func saveCurrentFrame() {
        Task {
            guard let jpeg = await source.captureFrame(), let image = UIImage(data: jpeg) else {
                addLog("Couldn't grab a frame to save.")
                return
            }
            UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
            addLog("Saved frame to Photos (\(jpeg.count / 1024) KB) — redraw the zone on it.")
        }
    }

    /// Manually fire the ESP32 trigger once (test button). Bypasses detection and cooldown.
    func sendTestSignal() {
        Task {
            addLog("Manual trigger → ESP32…")
            do {
                try await ESP32Client(host: AppConfig.esp32Host, path: AppConfig.esp32Path).trigger()
                addLog("✅ ESP32 responded OK.")
            } catch {
                addLog("ESP32 error: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Loop

    private func runLoop() async {
        source.start()
        while isRunning && !Task.isCancelled {
            let started = Date()
            await tick()
            let elapsed = Date().timeIntervalSince(started)
            let remaining = max(0, AppConfig.intervalSeconds - elapsed)
            if remaining > 0 {
                try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
            }
        }
    }

    private func tick() async {
        guard let jpeg = await source.captureFrame() else {
            addLog("No frame available.")
            return
        }

        status = .processing
        addLog("Frame \(jpeg.count / 1024) KB → Roboflow…")
        let started = Date()
        do {
            let result = try await roboflow.detectPlate(in: jpeg)
            addLog("Roboflow replied in \(String(format: "%.1f", Date().timeIntervalSince(started)))s")
            guard isRunning else { return }
            carInZone = result.carsInZone > 0

            if let match = result.plates.first(where: { AppConfig.plateMatches($0) }) {
                lastPlateText = match
                lastPlateMatched = true
                status = .matched
                addLog("Matched plate: \(match)")
                await openAndStop(plate: match)
                return
            } else if let plate = result.plates.first {
                lastPlateText = plate
                lastPlateMatched = false
                status = .scanning
                addLog("Saw plate: \(plate)")
            } else {
                // No plate this frame — keep showing the last one we read.
                status = .scanning
                addLog(result.carsInZone > 0
                       ? "Car in zone, no plate read yet."
                       : "No car in driveway zone.")
            }
        } catch {
            guard isRunning else { return }
            status = .error(error.localizedDescription)
            addLog("Inference error: \(error.localizedDescription)")
        }
    }

    /// Plate matched: send the open signal once, then STOP the loop. The opener is a
    /// toggle, so we must not keep firing while the car sits in view — one shot per
    /// run. Tap Start again (or relaunch) to re-arm. If the ESP32 is unreachable we
    /// don't stop, so the next match retries.
    private func openAndStop(plate: String) async {
        do {
            try await ESP32Client(host: AppConfig.esp32Host, path: AppConfig.esp32Path).trigger()
        } catch {
            addLog("ESP32 error: \(error.localizedDescription) — will retry on next match.")
            return
        }
        lastTrigger = Date()
        lastOpenedPlate = plate
        openPulse += 1
        addLog("✅ Opened garage for \(plate). Stopping — tap Start (or relaunch) to re-arm.")

        // One-shot: end the inference loop but KEEP the source running so the live
        // preview stays up. Tap Start to re-arm, or Stop to fully end the camera.
        isRunning = false
        loopTask?.cancel()
        loopTask = nil
    }

    // MARK: - Log

    private func addLog(_ message: String) {
        log.insert(LogEntry(date: Date(), message: message), at: 0)
        if log.count > 50 { log.removeLast(log.count - 50) }
    }
}