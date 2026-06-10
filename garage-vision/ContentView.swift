//
//  ContentView.swift
//  garage-vision
//

import SwiftUI
import UIKit

@MainActor
final class AppModel {
    let camera = CameraManager()
    let engine: DetectionEngine

    init() {
        engine = DetectionEngine(camera: camera)
    }
}

struct ContentView: View {
    @State private var model = AppModel()

    var body: some View {
        MainView(engine: model.engine, camera: model.camera)
    }
}

struct MainView: View {
    @ObservedObject var engine: DetectionEngine
    let camera: CameraManager

    var body: some View {
        ZStack {
            if engine.cameraReady {
                CameraPreview(session: camera.session)
                    .ignoresSafeArea()
            } else {
                Color.black.ignoresSafeArea()
            }

            VStack {
                statusBar
                Spacer()
                logPanel
                controls
            }
            .padding()
        }
        .task { await engine.prepareCamera() }
        .onChange(of: engine.isRunning) { _, running in
            UIApplication.shared.isIdleTimerDisabled = running
        }
    }

    // MARK: - Pieces

    private var statusBar: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 12, height: 12)
            Text(statusText)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
            Spacer()
        }
        .padding(12)
        .background(.black.opacity(0.55), in: Capsule())
    }

    private var logPanel: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !engine.lastPlates.isEmpty {
                Text("Last seen: \(engine.lastPlates.joined(separator: ", "))")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
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
            if !AppConfig.isConfigured {
                Text("Set your values in Secrets.swift to enable watching")
                    .font(.caption2)
                    .foregroundStyle(.yellow)
            }
            HStack(spacing: 12) {
                Button {
                    engine.isRunning ? engine.stop() : engine.start()
                } label: {
                    Label(engine.isRunning ? "Stop" : "Start",
                          systemImage: engine.isRunning ? "stop.fill" : "play.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .tint(engine.isRunning ? .red : .green)
                .disabled(!engine.cameraReady || !AppConfig.isConfigured)

                Button {
                    engine.sendTestSignal()
                } label: {
                    Label("Test ESP32", systemImage: "wifi")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.bordered)
                .tint(.white)
                .disabled(AppConfig.esp32Host.isEmpty)
            }
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
        case .scanning: return "Watching driveway"
        case .processing: return "Analyzing frame…"
        case .matched: return "Plate matched!"
        case .error(let message): return message
        }
    }
}

#Preview {
    ContentView()
}