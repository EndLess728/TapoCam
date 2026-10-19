import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State var settings: CameraSettings
    let onSave: (CameraSettings) -> Void
    @State private var scanning = false
    @State private var found: [String] = []

    init(initial: CameraSettings, onSave: @escaping (CameraSettings) -> Void) {
        _settings = State(initialValue: initial)
        self.onSave = onSave
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Camera Settings").font(.title2.bold()).padding([.horizontal, .top], 20)
            Form {
                Section {
                    HStack {
                        TextField("IP address", text: $settings.host, prompt: Text("192.168.0.x"))
                        Button {
                            Task { await scan() }
                        } label: {
                            if scanning { ProgressView().controlSize(.small) } else { Text("Find") }
                        }
                        .disabled(scanning)
                    }
                    if !found.isEmpty {
                        Picker("Found", selection: $settings.host) {
                            ForEach(found, id: \.self) { Text($0).tag($0) }
                        }
                    }
                } header: {
                    Text("Camera")
                }

                Section {
                    TextField("Username", text: $settings.streamUser)
                    SecureField("Password", text: $settings.streamPassword)
                } header: {
                    Text("Camera Account (for video)")
                } footer: {
                    Text("Create this in the Tapo app: Camera → ⚙︎ → Advanced Settings → Camera Account.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section {
                    SecureField("Tapo account password", text: $settings.cloudPassword)
                } header: {
                    Text("Tapo Account (for pan/tilt & settings)")
                } footer: {
                    Text("The password you sign in to the Tapo app with. It's stored in your Mac's Keychain and only sent to the camera.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Connect") {
                    settings.host = settings.host.trimmingCharacters(in: .whitespaces)
                    onSave(settings)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!settings.isConfigured)
            }
            .padding(20)
        }
        .frame(width: 480)
        .task { if settings.host.isEmpty { await scan() } }
    }

    private func scan() async {
        scanning = true
        found = await Discovery.scan()
        if settings.host.isEmpty, let first = found.first { settings.host = first }
        scanning = false
    }
}
