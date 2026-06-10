//
//  RoboflowClient.swift
//  garage-vision
//
//  Calls a Roboflow Hosted Workflow with a single image and extracts any
//  recognized plate strings from the response.
//

import Foundation

enum RoboflowError: LocalizedError {
    case badConfiguration
    case network
    case http(Int, String)

    var errorDescription: String? {
        switch self {
        case .badConfiguration: return "Roboflow workspace/workflow/endpoint is invalid."
        case .network: return "No response from Roboflow."
        case .http(let code, _): return "Roboflow returned HTTP \(code)."
        }
    }
}

struct RoboflowClient {
    var apiKey: String
    var workspace: String
    var workflowID: String
    var endpoint: String

    struct Result {
        let plates: [String]
        let rawResponse: String
    }

    func runWorkflow(imageJPEG: Data) async throws -> Result {
        let trimmedEndpoint = endpoint.hasSuffix("/") ? String(endpoint.dropLast()) : endpoint
        guard let url = URL(string: "\(trimmedEndpoint)/infer/workflows/\(workspace)/\(workflowID)") else {
            throw RoboflowError.badConfiguration
        }

        let body: [String: Any] = [
            "api_key": apiKey,
            "inputs": ["image": ["type": "base64", "value": imageJPEG.base64EncodedString()]]
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw RoboflowError.network }
        let raw = String(data: data, encoding: .utf8) ?? ""
        guard (200..<300).contains(http.statusCode) else {
            throw RoboflowError.http(http.statusCode, raw)
        }

        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
        return Result(plates: Self.extractPlates(from: decoded), rawResponse: raw)
    }

    /// Keys whose string values are treated as candidate plate text.
    /// TODO: tighten this to the exact output name of YOUR workflow once it's built,
    /// e.g. just ["plate_text"] — right now it casts a wide net and relies on the
    /// plate-match step to filter out noise (detection class names, etc).
    static let plateKeys = [
        "plate", "license", "ocr", "recognized", "registration", "text", "label", "prediction"
    ]

    static func extractPlates(from value: JSONValue) -> [String] {
        var found: [String] = []

        func walk(_ value: JSONValue, key: String?) {
            switch value {
            case .string(let s):
                if let key = key?.lowercased(),
                   plateKeys.contains(where: { key.contains($0) }) {
                    let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty { found.append(trimmed) }
                }
            case .array(let arr):
                arr.forEach { walk($0, key: key) }
            case .object(let obj):
                for (k, v) in obj { walk(v, key: k) }
            case .number, .bool, .null:
                break
            }
        }

        walk(value, key: nil)

        // De-duplicate while preserving order.
        var seen = Set<String>()
        return found.filter { seen.insert($0).inserted }
    }
}

/// Minimal recursive JSON model so we can read an arbitrarily-shaped workflow response.
enum JSONValue: Decodable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let b = try? container.decode(Bool.self) {
            self = .bool(b)
        } else if let n = try? container.decode(Double.self) {
            self = .number(n)
        } else if let s = try? container.decode(String.self) {
            self = .string(s)
        } else if let a = try? container.decode([JSONValue].self) {
            self = .array(a)
        } else if let o = try? container.decode([String: JSONValue].self) {
            self = .object(o)
        } else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Unsupported JSON value")
            )
        }
    }
}
