//
//  ESP32Client.swift
//  garage-vision
//
//  Fires a simple HTTP GET at the ESP32's LAN address to trigger the garage.
//

import Foundation

enum ESP32Error: LocalizedError {
    case badURL
    case http(Int)
    case noResponse

    var errorDescription: String? {
        switch self {
        case .badURL: return "ESP32 address is invalid."
        case .http(let code): return "ESP32 returned HTTP \(code)."
        case .noResponse: return "No response from ESP32."
        }
    }
}

struct ESP32Client {
    /// IP or IP:port, e.g. "192.168.1.50" or "192.168.1.50:80".
    var host: String
    /// Trigger path, e.g. "/open".
    var path: String

    func trigger() async throws {
        let normalizedPath = path.hasPrefix("/") ? path : "/\(path)"
        guard let url = URL(string: "http://\(host)\(normalizedPath)") else {
            throw ESP32Error.badURL
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ESP32Error.noResponse }
        guard (200..<300).contains(http.statusCode) else { throw ESP32Error.http(http.statusCode) }
    }
}
