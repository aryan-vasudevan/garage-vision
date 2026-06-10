//
//  DetectionEngine.swift
//  garage-vision
//
//  The ~2s loop: grab a frame -> Roboflow workflow -> match plate -> trigger ESP32.
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
    @Published private(set) var cameraReady = false
    @Published private(set) var lastPlates: [String] = []
    @Published private(set) var lastTrigger: Date?
    @Published private(set) var log: [LogEntry] = []

    let camera: CameraManager
    let settings: AppSettings

    private var loopTask: Task<Void, Never>?

    init(camera: CameraManager, settings: AppSettings) {
        self.camera = camera
        self.settings = settings
    }

    func prepareCamera() async {
        guard !cameraReady else { return }
        do {
            try await camera.configure()
            cameraReady = true
            addLog("Camera ready.")
        } catch {
            status = .error(error.localizedDescription)
            addLog("Camera error: \(error.localizedDescription)")
        }
    }

    func start() {
        guard !isRunning, cameraReady else { return }
        isRunning = true
        status = .scanning
        addLog("Started watching.")
        loopTask = Task { [weak self] in await self?.runLoop() }
    }

    func stop() {
        isRunning = false
        loopTask?.cancel()
        loopTask = nil
        camera.stop()
        status = .stopped
        addLog("Stopped.")
    }

    // MARK: - Loop

    private func runLoop() async {
        camera.start()
        while isRunning && !Task.isCancelled {
            let started = Date()
            await tick()
            let elapsed = Date().timeIntervalSince(started)
            let remaining = max(0, settings.intervalSeconds - elapsed)
            if remaining > 0 {
                try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
            }
        }
    }

    private func tick() async {
        guard let jpeg = await camera.captureFrame() else {
            addLog("No camera frame available.")
            return
        }

        status = .processing
        let client = RoboflowClient(
            apiKey: settings.roboflowAPIKey,
            workspace: settings.roboflowWorkspace,
            workflowID: settings.roboflowWorkflowID,
            endpoint: settings.roboflowEndpoint
        )

        do {
            let result = try await client.runWorkflow(imageJPEG: jpeg)
            guard isRunning else { return }
            lastPlates = result.plates

            if let match = result.plates.first(where: { settings.plateMatches($0) }) {
                status = .matched
                addLog("Matched plate: \(match)")
                await maybeTrigger()
            } else {
                status = .scanning
                if result.plates.isEmpty {
                    addLog("No plate detected.")
                } else {
                    addLog("Saw: \(result.plates.joined(separator: ", "))")
                }
            }
        } catch {
            guard isRunning else { return }
            status = .error(error.localizedDescription)
            addLog("Inference error: \(error.localizedDescription)")
        }
    }

    private func maybeTrigger() async {
        if let last = lastTrigger, Date().timeIntervalSince(last) < settings.cooldownSeconds {
            let wait = Int((settings.cooldownSeconds - Date().timeIntervalSince(last)).rounded())
            addLog("In cooldown (\(wait)s) — not re-triggering.")
            return
        }

        do {
            try await ESP32Client(host: settings.esp32Host, path: settings.esp32Path).trigger()
            lastTrigger = Date()
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
