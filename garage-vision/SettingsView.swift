//
//  SettingsView.swift
//  garage-vision
//

import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Roboflow Workflow") {
                    LabeledField("API Key", text: $settings.roboflowAPIKey, secure: true)
                    LabeledField("Workspace", text: $settings.roboflowWorkspace)
                    LabeledField("Workflow ID", text: $settings.roboflowWorkflowID)
                    LabeledField("Endpoint", text: $settings.roboflowEndpoint)
                }

                Section("Plate") {
                    LabeledField("My Plate", text: $settings.targetPlate)
                    Text("Compared case-insensitively, ignoring spaces and dashes.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("ESP32 Garage Trigger") {
                    LabeledField("IP / Host", text: $settings.esp32Host, placeholder: "192.168.1.50")
                    LabeledField("Path", text: $settings.esp32Path, placeholder: "/open")
                }

                Section("Timing") {
                    Stepper(value: $settings.intervalSeconds, in: 1...30, step: 0.5) {
                        Text("Scan every \(settings.intervalSeconds, specifier: "%.1f")s")
                    }
                    Stepper(value: $settings.cooldownSeconds, in: 5...300, step: 5) {
                        Text("Cooldown \(Int(settings.cooldownSeconds))s")
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct LabeledField: View {
    let label: String
    @Binding var text: String
    var secure: Bool = false
    var placeholder: String = ""

    init(_ label: String, text: Binding<String>, secure: Bool = false, placeholder: String = "") {
        self.label = label
        self._text = text
        self.secure = secure
        self.placeholder = placeholder
    }

    var body: some View {
        HStack {
            Text(label)
                .frame(width: 110, alignment: .leading)
            if secure {
                SecureField(placeholder, text: $text)
            } else {
                TextField(placeholder, text: $text)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
        }
    }
}