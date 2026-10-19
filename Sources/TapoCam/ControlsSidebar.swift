import SwiftUI

struct ControlsSidebar: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var control: TapoControl
    @State private var newPresetName = ""
    @State private var confirmReboot = false
    @State private var sirenOn = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                connectionBanner

                section("Pan & Tilt") {
                    PTZPad(step: model.settings.panStep) { control.move(x: $0, y: $1) }
                        .frame(maxWidth: .infinity)
                    HStack {
                        Text("Step")
                        Slider(value: Binding(get: { Double(model.settings.panStep) },
                                              set: { model.settings.panStep = Int($0); model.settings.save() }),
                               in: 5...45, step: 5)
                        Text("\(model.settings.panStep)°").monospacedDigit().frame(width: 32, alignment: .trailing)
                    }
                    .font(.callout)
                    Text("Tip: arrow keys move the camera too. Hold a button to keep moving.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                section("Presets") {
                    let presets = control.status.presets ?? []
                    if presets.isEmpty {
                        Text("No saved positions").font(.callout).foregroundStyle(.secondary)
                    }
                    ForEach(presets) { p in
                        HStack {
                            Button { control.gotoPreset(p) } label: {
                                Label(p.name, systemImage: "scope").frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.borderless)
                            Button { control.deletePreset(p) } label: { Image(systemName: "trash") }
                                .buttonStyle(.borderless).foregroundStyle(.secondary)
                                .help("Delete preset")
                        }
                    }
                    HStack {
                        TextField("Save current view as…", text: $newPresetName)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit(savePreset)
                        Button("Save", action: savePreset).disabled(newPresetName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }

                section("Camera") {
                    toggle("Privacy mode", "eye.slash", control.status.privacy) { control.setPrivacy($0) }
                    toggle("Status LED", "lightbulb", control.status.led) { control.setLED($0) }
                    toggle("Motion detection", "figure.walk.motion", control.status.motion) { control.setMotion($0) }
                    toggle("Flip image", "arrow.up.and.down.righttriangle.up.righttriangle.down", control.status.flip) { control.setFlip($0) }
                    HStack {
                        Label("Night vision", systemImage: "moon.stars")
                        Spacer()
                        Picker("", selection: Binding(get: { control.status.dayNight ?? "auto" }, set: { control.setDayNight($0) })) {
                            Text("Auto").tag("auto")
                            Text("On").tag("on")
                            Text("Off").tag("off")
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                    .disabled(control.state != .connected)
                }

                section("Actions") {
                    Button {
                        sirenOn.toggle()
                        control.setAlarm(sirenOn)
                    } label: {
                        Label(sirenOn ? "Stop siren" : "Sound siren", systemImage: sirenOn ? "speaker.slash.fill" : "light.beacon.max")
                            .frame(maxWidth: .infinity)
                    }
                    .tint(sirenOn ? .red : nil)
                    .buttonStyle(.borderedProminent)
                    HStack {
                        Button { control.calibrate() } label: { Label("Calibrate", systemImage: "scope").frame(maxWidth: .infinity) }
                            .help("Re-centre the pan/tilt motors")
                        Button { confirmReboot = true } label: { Label("Reboot", systemImage: "power").frame(maxWidth: .infinity) }
                    }
                    Button { control.refresh() } label: { Label("Refresh status", systemImage: "arrow.triangle.2.circlepath").frame(maxWidth: .infinity) }
                }
                .disabled(control.state != .connected)

                if let info = infoLine {
                    Text(info).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                }
            }
            .padding(16)
        }
        .background(.background.secondary)
        .confirmationDialog("Reboot the camera?", isPresented: $confirmReboot) {
            Button("Reboot", role: .destructive) { control.reboot() }
        } message: {
            Text("The live view will drop for about a minute.")
        }
    }

    private var infoLine: String? {
        let parts = [control.status.model, control.status.firmware.map { "FW \($0)" }, model.settings.host].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    @ViewBuilder private var connectionBanner: some View {
        switch control.state {
        case .installing:
            banner("Setting up camera controls (first launch only)…", progress: true)
        case .connecting:
            banner("Connecting to camera controls…", progress: true)
        case .failed(let msg):
            VStack(alignment: .leading, spacing: 8) {
                Label("Controls unavailable", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text(msg).font(.callout).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Settings…") { model.showSettings = true }
                    Button("Retry") { Task { await control.connect(model.settings) } }
                }
            }
            .padding(10)
            .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        case .connected:
            if let err = control.lastError {
                Text(err).font(.caption).foregroundStyle(.red)
            }
        case .disconnected:
            EmptyView()
        }
    }

    private func banner(_ text: String, progress: Bool) -> some View {
        HStack(spacing: 8) {
            if progress { ProgressView().controlSize(.small) }
            Text(text).font(.callout)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }

    private func savePreset() {
        let name = newPresetName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        control.savePreset(name: name)
        newPresetName = ""
    }

    private func section<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased()).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            content()
        }
    }

    private func toggle(_ title: String, _ icon: String, _ value: Bool?, set: @escaping (Bool) -> Void) -> some View {
        Toggle(isOn: Binding(get: { value ?? false }, set: set)) {
            Label(title, systemImage: icon)
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .disabled(control.state != .connected || value == nil)
    }
}

struct PTZPad: View {
    let step: Int
    let move: (Int, Int) -> Void

    var body: some View {
        Grid(horizontalSpacing: 6, verticalSpacing: 6) {
            GridRow {
                Color.clear.frame(width: 1, height: 1)
                arrow("chevron.up") { move(0, step) }
                Color.clear.frame(width: 1, height: 1)
            }
            GridRow {
                arrow("chevron.left") { move(-step, 0) }
                Image(systemName: "video.fill").foregroundStyle(.secondary).frame(width: 48, height: 48)
                arrow("chevron.right") { move(step, 0) }
            }
            GridRow {
                Color.clear.frame(width: 1, height: 1)
                arrow("chevron.down") { move(0, -step) }
                Color.clear.frame(width: 1, height: 1)
            }
        }
    }

    private func arrow(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 48, height: 48)
        }
        .buttonStyle(.bordered)
        .buttonRepeatBehavior(.enabled)
    }
}
