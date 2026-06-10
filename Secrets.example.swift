//
//  Secrets.example.swift  —  TEMPLATE (committed)
//
//  This file is NOT part of the app target. To configure the app:
//    1. Copy it into the app folder as `garage-vision/Secrets.swift`
//    2. Fill in your real values
//
//  `garage-vision/Secrets.swift` is git-ignored, so your real credentials
//  never get committed. Get a Roboflow API key at app.roboflow.com/settings/api
//
//      cp Secrets.example.swift garage-vision/Secrets.swift
//

import Foundation

enum Secrets {
    /// Roboflow private API key (app.roboflow.com/settings/api).
    static let roboflowAPIKey = "YOUR_ROBOFLOW_API_KEY"

    /// ESP32 address on your LAN — IP or IP:port, e.g. "192.168.1.50" or "10.0.0.214:80".
    static let esp32Host = "192.168.1.50"

    /// The license plate that should open the garage. Spaces/dashes/case are ignored.
    static let targetPlate = "ABC1234"
}