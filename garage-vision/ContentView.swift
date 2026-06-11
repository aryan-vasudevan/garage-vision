//
//  ContentView.swift
//  garage-vision
//

import SwiftUI
import UIKit

@MainActor
final class AppModel {
    let camera = CameraManager()
    let replay = VideoReplaySource()          // nil if the bundled video is missing
    let engine: DetectionEngine

    init() {
        engine = DetectionEngine(source: camera)
    }
}

struct ContentView: View {
    @State private var model = AppModel()

    var body: some View {
        MainView(engine: model.engine, camera: model.camera, replay: model.replay)
    }
}

struct MainView: View {
    @ObservedObject var engine: DetectionEngine
    let camera: CameraManager
    let replay: VideoReplaySource?

    @State private var useReplay = false
    @State private var flashOpacity = 0.0

    var body: some View {
        ZStack {
            preview

            // Green flash when the opener fires.
            Color.green.opacity(flashOpacity).ignoresSafeArea().allowsHitTesting(false)

            VStack {
                statusBar
                indicators
                if replay != nil { sourcePicker }
                Spacer()
                openedBanner
                logPanel
                controls
            }
            .padding()
        }
        .task {
            LocalNetworkPrimer.shared.prime(host: AppConfig.esp32Host)   // surface the Local Network prompt
            await engine.prepareSource()
        }
        .onChange(of: engine.isRunning) { _, running in
            UIApplication.shared.isIdleTimerDisabled = running
        }
        .onChange(of: engine.openPulse) { _, _ in
            flashOpacity = 0.6
            withAnimation(.easeOut(duration: 0.8)) { flashOpacity = 0.0 }
        }
        .sensoryFeedback(.success, trigger: engine.openPulse)
    }

    // MARK: - Preview

    @ViewBuilder
    private var preview: some View {
        if useReplay, let replay {
            VideoPreview(player: replay.player).ignoresSafeArea()
        } else if engine.sourceReady && !useReplay {
            CameraPreview(session: camera.session).ignoresSafeArea()
        } else {
            Color.black.ignoresSafeArea()
        }
    }

    // MARK: - Pieces

    private var statusBar: some View {
        HStack(spacing: 8) {
            Circle().fill(statusColor).frame(width: 12, height: 12)
            Text(statusText)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
            Spacer()
        }
        .padding(12)
        .background(.black.opacity(0.55), in: Capsule())
    }

    private var indicators: some View {
        HStack(spacing: 10) {
            pill(engine.carInZone ? "Car in Driveway" : "No Car in Driveway",
                 background: engine.carInZone ? .blue : .black.opacity(0.55))
            pill(engine.lastPlateText ?? "No plate",
                 background: engine.lastPlateMatched ? .green
                           : (engine.lastPlateText != nil ? .blue : .black.opacity(0.55)))
        }
    }

    private func pill(_ text: String, background: Color) -> some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(background, in: Capsule())
            .animation(.easeInOut(duration: 0.2), value: background)
    }

    private var sourcePicker: some View {
        HStack(spacing: 0) {
            sourceButton("Camera", selected: !useReplay) { setReplay(false) }
            sourceButton("Video (Test env)", selected: useReplay) { setReplay(true) }
        }
        .padding(3)
        .background(.black.opacity(0.55), in: Capsule())
        .disabled(engine.isRunning)
        .opacity(engine.isRunning ? 0.5 : 1)
    }

    private func sourceButton(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(selected ? Color.gray : Color.clear, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func setReplay(_ on: Bool) {
        guard let replay, on != useReplay else { return }
        useReplay = on
        Task { await engine.switchSource(to: on ? replay : camera) }
    }

    @ViewBuilder
    private var openedBanner: some View {
        if let date = engine.lastTrigger, let plate = engine.lastOpenedPlate {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.seal.fill")
                Text("Opened for \(plate) at \(date, format: .dateTime.hour().minute().second())")
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14).padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(.green.opacity(0.85), in: RoundedRectangle(cornerRadius: 12))
            .padding(.bottom, 4)
        }
    }

    private var logPanel: some View {
        VStack(alignment: .leading, spacing: 4) {
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(engine.log) { entry in
                        Text("\(entry.date, format: .dateTime.hour().minute().second())  \(entry.message)")
                            .font(.caption2.monospaced())
                            .foregroundStyle(.white.opacity(0.85))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .frame(height: 130)
        }
        .padding(10)
        .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
    }

    private var controls: some View {
        VStack(spacing: 8) {
            if !AppConfig.canRun {
                Text("Set your Roboflow key in Secrets.swift to enable detection")
                    .font(.caption2).foregroundStyle(.yellow)
            } else if !AppConfig.isConfigured {
                Text("Set targetPlate + esp32Host in Secrets.swift to actually open the garage")
                    .font(.caption2).foregroundStyle(.yellow)
            }
            HStack(spacing: 12) {
                Button {
                    engine.isRunning ? engine.stop() : engine.start()
                } label: {
                    Label(engine.isRunning ? "Stop" : "Start",
                          systemImage: engine.isRunning ? "stop.fill" : "play.fill")
                        .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .tint(engine.isRunning ? .red : .green)
                .disabled(!engine.sourceReady || !AppConfig.canRun)

                Button {
                    engine.sendTestSignal()
                } label: {
                    Label("Test ESP32", systemImage: "wifi")
                        .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent).tint(.gray)
                .disabled(AppConfig.esp32Host.isEmpty)
            }

            Button {
                engine.saveCurrentFrame()
            } label: {
                Label("Save Frame (calibrate zone)", systemImage: "camera.viewfinder")
                    .font(.subheadline).frame(maxWidth: .infinity).padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent).tint(.gray)
            .disabled(!engine.isRunning)
        }
    }

    private var statusColor: Color {
        switch engine.status {
        case .stopped: return .gray
        case .scanning: return .green
        case .processing: return .blue
        case .matched: return .yellow
        case .error: return .red
        }
    }

    private var statusText: String {
        switch engine.status {
        case .stopped: return "Stopped"
        case .scanning: return useReplay ? "Watching video" : "Watching driveway"
        case .processing: return "Analyzing frame…"
        case .matched: return "Plate matched!"
        case .error(let message): return message
        }
    }
}

#Preview {
    ContentView()
}