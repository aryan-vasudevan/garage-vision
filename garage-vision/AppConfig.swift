//
//  AppConfig.swift
//  garage-vision
//
//  Non-secret configuration. Secrets (API key, ESP32 host, target plate) live in
//  the git-ignored Secrets.swift — see Secrets.example.swift.
//

import Foundation

enum AppConfig {
    // MARK: Roboflow Hosted Workflow
    static let roboflowEndpoint = "https://serverless.roboflow.com"
    static let roboflowWorkspace = "dev-m9yee"
    static let roboflowWorkflowID = "custom-workflow-5"
    static var roboflowAPIKey: String { Secrets.roboflowAPIKey }

    // MARK: ESP32 garage trigger
    static var esp32Host: String { Secrets.esp32Host }
    static let esp32Path = "/open"

    // MARK: Plate matching
    static var targetPlate: String { Secrets.targetPlate }

    // MARK: Loop timing
    // The Roboflow round-trip (~1.4s idle, ~2.2s when reading a plate) is the real
    // floor — the loop runs back-to-back whenever a cycle exceeds this. 1.0s removes
    // idle wait between scans; lower buys nothing. Raise it to spend fewer credits.
    static let intervalSeconds: Double = 1.0
    static let cooldownSeconds: Double = 30.0

    // MARK: Helpers

    /// Strip everything but letters/digits and uppercase, so "ABC-1234" == "abc 1234".
    static func normalizedPlate(_ raw: String) -> String {
        raw.uppercased().filter { $0.isLetter || $0.isNumber }
    }

    /// True if an OCR result matches the configured target plate.
    static func plateMatches(_ candidate: String) -> Bool {
        let target = normalizedPlate(targetPlate)
        guard !target.isEmpty else { return false }
        return normalizedPlate(candidate) == target
    }

    /// Enough to run detection (needs a real Roboflow key). ESP32/plate only affect
    /// whether a match actually triggers the opener — handy for replay testing.
    static var canRun: Bool {
        roboflowAPIKey != "YOUR_ROBOFLOW_API_KEY" && !roboflowAPIKey.isEmpty
    }

    /// True once every placeholder secret has been replaced with real values.
    static var isConfigured: Bool {
        canRun && !esp32Host.isEmpty && !targetPlate.isEmpty && targetPlate != "ABC1234"
    }
}