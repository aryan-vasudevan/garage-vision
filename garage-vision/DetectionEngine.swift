//
//  DetectionEngine.swift
//  garage-vision
//
//  The ~2s loop: grab a frame -> Custom Workflow 5 -> match plate -> trigger ESP32.
//  Frames come from a swappable FrameProviding source (live camera or video replay).
//

import Foundation
import Combine

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
    @Published private(set) var lastPlates: [String] = []
    @Published private(set) var lastTrigger: Date?
    @Published private(set) var lastOpenedPlate: String?
    @Published private(set) var log: [LogEntry] = []
    /// Bumped each time the opener actually fires, to drive the on-screen flash/haptic.
    @Published private(set) var openPulse = 0

    private(set) var source: FrameProviding

    private var loopTask: Task<Void, Never>?

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
        } catch {
            status = .error(error.localizedDescription)
            addLog("Source error: \(error.localizedDescription)")
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
        addLog("Stopped.")
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
        do {
            let result = try await roboflow.detectPlate(in: jpeg)
            guard isRunning else { return }
            lastPlates = result.plates

            if let match = result.plates.first(where: { AppConfig.plateMatches($0) }) {
                status = .matched
                addLog("Matched plate: \(match)")
                await maybeTrigger(plate: match)
            } else {
                status = .scanning
                if result.plates.isEmpty {
                    addLog(result.carsInZone > 0
                           ? "Car in zone, no plate read yet."
                           : "No car in driveway zone.")
                } else {
                    addLog("Saw plate(s): \(result.plates.joined(separator: ", "))")
                }
            }
        } catch {
            guard isRunning else { return }
            status = .error(error.localizedDescription)
            addLog("Inference error: \(error.localizedDescription)")
        }
    }

    private func maybeTrigger(plate: String) async {
        if let last = lastTrigger, Date().timeIntervalSince(last) < AppConfig.cooldownSeconds {
            let wait = Int((AppConfig.cooldownSeconds - Date().timeIntervalSince(last)).rounded())
            addLog("In cooldown (\(wait)s) — not re-triggering.")
            return
        }

        do {
            try await ESP32Client(host: AppConfig.esp32Host, path: AppConfig.esp32Path).trigger()
            lastTrigger = Date()
            lastOpenedPlate = plate
            openPulse += 1
            addLog("✅ Sent OPEN signal to ESP32.")
        } catch {
            addLog("ESP32 error: \(error.localizedDescription)")
        }
    }

    // MARK: - Log

    private func addLog(_ message: String) {
        log.insert(LogEntry(date: Date(), message: message), at: 0)
        if log.count > 50 { log.removeLast(log.count - 50) }
    }
}