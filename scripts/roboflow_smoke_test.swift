#!/usr/bin/env swift
//
//  roboflow_smoke_test.swift
//
//  Smoke test for the Custom Workflow 5 integration. Runs the embedded workflow
//  (garage-vision/workflow.json) on one sample image via the same inline-spec
//  path the app uses, and asserts the expected output keys are present.
//
//  Usage:
//      export ROBOFLOW_API_KEY=...        # app.roboflow.com/settings/api
//      swift scripts/roboflow_smoke_test.swift [imageURL]
//
//  Exits 0 on success, 1 on failure. Skips (exit 0) if no API key is set.
//

import Foundation

let endpoint = "https://serverless.roboflow.com/infer/workflows"
let expectedKeys = ["cars_in_zone", "license_plates", "plate_text"]

func fail(_ message: String) -> Never { print("FAIL: \(message)"); exit(1) }

guard let apiKey = ProcessInfo.processInfo.environment["ROBOFLOW_API_KEY"], !apiKey.isEmpty else {
    print("SKIP: ROBOFLOW_API_KEY not set — set it to run the smoke test.")
    exit(0)
}

// Load the embedded workflow spec (the same file the app bundles).
let specURL = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("garage-vision/workflow.json")
guard let specData = try? Data(contentsOf: specURL),
      let spec = try? JSONSerialization.jsonObject(with: specData) else {
    fail("could not load \(specURL.path)")
}

// Default is a directly-loadable image (asserts the keys come back). Pass your
// own image URL as an argument for a richer check.
let imageURL = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "https://ultralytics.com/images/bus.jpg"

var request = URLRequest(url: URL(string: endpoint)!)
request.httpMethod = "POST"
request.setValue("application/json", forHTTPHeaderField: "Content-Type")
request.timeoutInterval = 60
request.httpBody = try! JSONSerialization.data(withJSONObject: [
    "api_key": apiKey,
    "specification": spec,
    "inputs": ["image": ["type": "url", "value": imageURL]]
])

let semaphore = DispatchSemaphore(value: 0)
URLSession.shared.dataTask(with: request) { data, response, error in
    defer { semaphore.signal() }
    if let error = error { fail("network error: \(error.localizedDescription)") }
    guard let http = response as? HTTPURLResponse else { fail("no HTTP response") }
    guard let data = data else { fail("empty body") }
    guard (200..<300).contains(http.statusCode) else {
        fail("HTTP \(http.statusCode): \(String(data: data.prefix(300), encoding: .utf8) ?? "")")
    }
    guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let outputs = root["outputs"] as? [[String: Any]],
          let first = outputs.first else {
        fail("response missing 'outputs' array")
    }
    let missing = expectedKeys.filter { first[$0] == nil }
    if !missing.isEmpty { fail("missing output keys: \(missing.joined(separator: ", "))") }
    let plate = first["plate_text"].map { "\($0)" } ?? "null"
    print("PASS: all expected output keys present. plate_text = \(plate)")
}.resume()
semaphore.wait()