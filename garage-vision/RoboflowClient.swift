//
//  RoboflowClient.swift
//  garage-vision
//
//  Runs the "Custom Workflow 5" pipeline on a single camera frame.
//
//  The workflow definition is embedded in the app (workflow.json) and POSTed
//  inline to Roboflow's serverless `/infer/workflows` endpoint, so the app runs
//  the exact pipeline regardless of the saved-workflow deploy/cache state. To
//  pull a freshly-tuned version from Roboflow, run scripts/pull_workflow.py.
//
//  Workflow outputs (grounded against the real definition):
//    - raw_vehicle_predictions : car/truck detections
//    - cars_in_zone            : detections inside the driveway zone (has .predictions[])
//    - license_plates          : rolled-up plate detections
//    - plate_text              : collapsed OCR text — null, or a list of strings
//

import Foundation

enum RoboflowError: LocalizedError {
    case missingSpec
    case http(status: Int, message: String)
    case emptyResponse
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .missingSpec:
            return "Bundled workflow.json is missing or unreadable."
        case .http(let status, _):
            return "Roboflow returned HTTP \(status)."
        case .emptyResponse:
            return "Roboflow returned no output."
        case .decoding(let detail):
            return "Could not parse Roboflow response: \(detail)"
        }
    }
}

struct RoboflowClient {
    var apiKey: String
    var endpoint: String

    /// Per-request timeout and retry policy for transient failures.
    var requestTimeout: TimeInterval = 15
    var maxAttempts: Int = 3

    struct Result {
        /// Recognized plate strings (empty when no plate was read).
        let plates: [String]
        /// Number of vehicles detected inside the driveway zone.
        let carsInZone: Int
        /// Number of license-plate boxes detected (before/independent of OCR).
        let platesDetected: Int
    }

    /// The embedded workflow specification, loaded once from the app bundle.
    private static let specification: [String: Any]? = {
        guard let url = Bundle.main.url(forResource: "workflow", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json
    }()

    private var runURL: URL? {
        let base = endpoint.hasSuffix("/") ? String(endpoint.dropLast()) : endpoint
        return URL(string: "\(base)/infer/workflows")
    }

    /// Run the workflow on one JPEG frame. Retries transient/5xx failures with
    /// exponential backoff; throws a typed `RoboflowError` on give-up.
    func detectPlate(in imageJPEG: Data) async throws -> Result {
        guard let spec = Self.specification else { throw RoboflowError.missingSpec }
        guard let url = runURL else { throw RoboflowError.emptyResponse }

        let body: [String: Any] = [
            "api_key": apiKey,
            "specification": spec,
            "inputs": ["image": ["type": "base64", "value": imageJPEG.base64EncodedString()]]
        ]
        let httpBody = try JSONSerialization.data(withJSONObject: body)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = httpBody
        request.timeoutInterval = requestTimeout

        var lastError: Error = RoboflowError.emptyResponse
        for attempt in 1...maxAttempts {
            do {
                return try await send(request)
            } catch let error as RoboflowError {
                // Don't retry client-side mistakes (bad key/spec, 4xx).
                if case .http(let status, _) = error, (400..<500).contains(status) { throw error }
                lastError = error
            } catch {
                lastError = error
            }

            if attempt < maxAttempts {
                let backoff = pow(2.0, Double(attempt - 1)) * 0.5   // 0.5s, 1s, ...
                try? await Task.sleep(nanoseconds: UInt64(backoff * 1_000_000_000))
            }
        }
        throw lastError
    }

    private func send(_ request: URLRequest) async throws -> Result {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw RoboflowError.emptyResponse }
        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data.prefix(500), encoding: .utf8) ?? ""
            throw RoboflowError.http(status: http.statusCode, message: message)
        }
        return try Self.parse(data)
    }

    /// Parse defensively from the real output keys.
    static func parse(_ data: Data) throws -> Result {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let outputs = root["outputs"] as? [[String: Any]],
              let first = outputs.first else {
            throw RoboflowError.decoding("missing 'outputs' array")
        }

        let plates = plateStrings(from: first["plate_text"])
        let carsInZone = detectionCount(from: first["cars_in_zone"])
        let platesDetected = detectionCount(from: first["license_plates"])
        return Result(plates: plates, carsInZone: carsInZone, platesDetected: platesDetected)
    }

    /// Count detections in an output that is either a `{predictions:[...]}` object
    /// or a list of such objects (the plate detector runs per car-crop, so it nests).
    private static func detectionCount(from value: Any?) -> Int {
        if let dict = value as? [String: Any], let preds = dict["predictions"] as? [Any] {
            return preds.count
        }
        if let array = value as? [Any] {
            return array.reduce(0) { total, element in
                if let dict = element as? [String: Any], let preds = dict["predictions"] as? [Any] {
                    return total + preds.count
                }
                return total
            }
        }
        return 0
    }

    /// `plate_text` is `null`, a string, or (nested) lists of strings — the OCR
    /// collapse yields shapes like `[["GWAK 022"]]`. Flatten recursively to plain strings.
    private static func plateStrings(from value: Any?) -> [String] {
        var out: [String] = []
        func walk(_ v: Any?) {
            switch v {
            case let s as String:
                let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { out.append(trimmed) }
            case let array as [Any]:
                array.forEach { walk($0) }
            default:
                break
            }
        }
        walk(value)
        return out
    }
}