//
//  AppSettings.swift
//  garage-vision
//
//  User-editable configuration, persisted in UserDefaults.
//

import Foundation
import Combine

@MainActor
final class AppSettings: ObservableObject {
    private let defaults = UserDefaults.standard

    // Roboflow Hosted Workflow
    @Published var roboflowAPIKey: String { didSet { defaults.set(roboflowAPIKey, forKey: Keys.apiKey) } }
    @Published var roboflowWorkspace: String { didSet { defaults.set(roboflowWorkspace, forKey: Keys.workspace) } }
    @Published var roboflowWorkflowID: String { didSet { defaults.set(roboflowWorkflowID, forKey: Keys.workflowID) } }
    @Published var roboflowEndpoint: String { didSet { defaults.set(roboflowEndpoint, forKey: Keys.endpoint) } }

    // Plate matching
    @Published var targetPlate: String { didSet { defaults.set(targetPlate, forKey: Keys.targetPlate) } }

    // ESP32 garage trigger
    @Published var esp32Host: String { didSet { defaults.set(esp32Host, forKey: Keys.esp32Host) } }
    @Published var esp32Path: String { didSet { defaults.set(esp32Path, forKey: Keys.esp32Path) } }

    // Loop timing
    @Published var intervalSeconds: Double { didSet { defaults.set(intervalSeconds, forKey: Keys.interval) } }
    @Published var cooldownSeconds: Double { didSet { defaults.set(cooldownSeconds, forKey: Keys.cooldown) } }

    init() {
        roboflowAPIKey = defaults.string(forKey: Keys.apiKey) ?? ""
        roboflowWorkspace = defaults.string(forKey: Keys.workspace) ?? ""
        roboflowWorkflowID = defaults.string(forKey: Keys.workflowID) ?? ""
        roboflowEndpoint = defaults.string(forKey: Keys.endpoint) ?? "https://serverless.roboflow.com"
        targetPlate = defaults.string(forKey: Keys.targetPlate) ?? ""
        esp32Host = defaults.string(forKey: Keys.esp32Host) ?? ""
        esp32Path = defaults.string(forKey: Keys.esp32Path) ?? "/open"
        let storedInterval = defaults.double(forKey: Keys.interval)
        intervalSeconds = storedInterval > 0 ? storedInterval : 2.0
        let storedCooldown = defaults.double(forKey: Keys.cooldown)
        cooldownSeconds = storedCooldown > 0 ? storedCooldown : 30.0
    }

    /// Strip everything but letters/digits and uppercase, so "ABC-1234" == "abc 1234".
    func normalizedPlate(_ raw: String) -> String {
        raw.uppercased().filter { $0.isLetter || $0.isNumber }
    }

    /// True if `candidate` (an OCR result) matches the configured target plate.
    func plateMatches(_ candidate: String) -> Bool {
        let target = normalizedPlate(targetPlate)
        guard !target.isEmpty else { return false }
        return normalizedPlate(candidate) == target
    }

    var isReady: Bool {
        !roboflowAPIKey.isEmpty && !roboflowWorkspace.isEmpty &&
        !roboflowWorkflowID.isEmpty && !targetPlate.isEmpty && !esp32Host.isEmpty
    }

    private enum Keys {
        static let apiKey = "roboflowAPIKey"
        static let workspace = "roboflowWorkspace"
        static let workflowID = "roboflowWorkflowID"
        static let endpoint = "roboflowEndpoint"
        static let targetPlate = "targetPlate"
        static let esp32Host = "esp32Host"
        static let esp32Path = "esp32Path"
        static let interval = "intervalSeconds"
        static let cooldown = "cooldownSeconds"
    }
}
