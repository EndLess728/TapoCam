import SwiftUI

struct ContentView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var player: StreamPlayer
    @EnvironmentObject var control: TapoControl
    @EnvironmentObject var recorder: Recorder
    @State private var showSidebar = true

    var body: some View {
        HStack(spacing: 0) {
            VideoPane()
            if showSidebar {
                Divider()
                ControlsSidebar()
                    .frame(width: 280)
                    .transition(.move(edge: .trailing))
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                StatusPill()
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Picker("Quality", selection: Binding(get: { model.settings.highQuality }, set: { model.setQuality(high: $0) })) {
                    Text("HD").tag(true)
                    Text("SD").tag(false)
                }
                .pickerStyle(.segmented)
                .help("HD = main stream, SD = lower bandwidth")

                Button { model.snapshot() } label: { Label("Snapshot", systemImage: "camera") }
                    .help("Save a snapshot to Pictures/TapoCam (⇧⌘S)")
                Button { model.toggleRecording() } label: {
                    Label(recorder.isRecording ? "Stop" : "Record",
                          systemImage: recorder.isRecording ? "stop.circle.fill" : "record.circle")
                }
                .foregroundStyle(recorder.isRecording ? .red : .primary)
                .help("Record to Movies/TapoCam (⇧⌘R)")
                Button { model.reconnect() } label: { Label("Reconnect", systemImage: "arrow.clockwise") }
                Button { model.showSettings = true } label: { Label("Settings", systemImage: "gearshape") }
                Button { withAnimation { showSidebar.toggle() } } label: { Label("Controls", systemImage: "sidebar.right") }
            }
        }
        .sheet(isPresented: $model.showSettings) {
            SettingsView(initial: model.settings) { model.apply($0) }
        }
    }
}

struct StatusPill: View {
    @EnvironmentObject var player: StreamPlayer
    @EnvironmentObject var control: TapoControl

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text).font(.callout).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 6)
    }

    private var color: Color {
        switch player.state {
        case .playing: .green
        case .connecting: .yellow
        case .failed: .red
        case .idle: .gray
        }
    }

    private var text: String {
        let name = control.status.name ?? control.status.model ?? "Camera"
        switch player.state {
        case .playing: return "\(name) · \(player.fps) fps"
        case .connecting: return "Connecting…"
        case .failed: return "Offline"
        case .idle: return "Not configured"
        }
    }
}

struct VideoPane: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var player: StreamPlayer
    @EnvironmentObject var control: TapoControl
    @EnvironmentObject var recorder: Recorder
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            Color.black
            if let frame = player.frame {
                Image(decorative: frame, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            }
            overlayMessage
            VStack {
                HStack {
                    if recorder.isRecording, let start = recorder.startedAt {
                        HStack(spacing: 6) {
                            Circle().fill(.red).frame(width: 10, height: 10)
                            Text(start, style: .timer).monospacedDigit()
                        }
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(.black.opacity(0.6), in: Capsule())
                        .foregroundStyle(.white)
                    }
                    Spacer()
                    if control.status.privacy == true {
                        Label("Privacy mode", systemImage: "eye.slash")
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(.black.opacity(0.6), in: Capsule())
                            .foregroundStyle(.white)
                    }
                }
                Spacer()
                if let toast = model.toast {
                    Text(toast)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(.regularMaterial, in: Capsule())
                        .transition(.opacity)
                }
            }
            .padding(12)
            .animation(.easeInOut, value: model.toast)
        }
        .contentShape(Rectangle())
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onAppear { focused = true }
        .onTapGesture { focused = true }
        .onKeyPress(keys: [.upArrow, .downArrow, .leftArrow, .rightArrow]) { press in
            let s = model.settings.panStep
            switch press.key {
            case .upArrow: control.move(x: 0, y: s)
            case .downArrow: control.move(x: 0, y: -s)
            case .leftArrow: control.move(x: -s, y: 0)
            default: control.move(x: s, y: 0)
            }
            return .handled
        }
    }

    @ViewBuilder private var overlayMessage: some View {
        switch player.state {
        case .connecting where player.frame == nil:
            VStack(spacing: 10) {
                ProgressView().controlSize(.large)
                Text("Connecting to \(model.settings.host)…").foregroundStyle(.white.opacity(0.8))
            }
        case .failed(let msg):
            VStack(spacing: 12) {
                Image(systemName: "video.slash").font(.system(size: 40))
                Text(msg).multilineTextAlignment(.center).frame(maxWidth: 420)
                HStack {
                    Button("Settings…") { model.showSettings = true }
                    Button("Retry now") { model.reconnect() }.keyboardShortcut(.defaultAction)
                }
            }
            .foregroundStyle(.white)
            .padding(24)
            .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 14))
        case .idle:
            VStack(spacing: 12) {
                Image(systemName: "web.camera").font(.system(size: 44))
                Text("Set up your Tapo camera to start watching.")
                Button("Set Up Camera…") { model.showSettings = true }.keyboardShortcut(.defaultAction)
            }
            .foregroundStyle(.white)
        default:
            EmptyView()
        }
    }
}
