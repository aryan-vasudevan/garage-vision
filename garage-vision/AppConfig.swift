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
    static let intervalSeconds: Double = 2.0
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

    /// True once the placeholder secrets have been replaced with real values.
    static var isConfigured: Bool {
        roboflowAPIKey != "YOUR_ROBOFLOW_API_KEY" && !roboflowAPIKey.isEmpty &&
        !esp32Host.isEmpty && !targetPlate.isEmpty
    }
}