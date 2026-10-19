import SwiftUI

@main
struct TapoCamApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup("TapoCam") {
            ContentView()
                .environmentObject(model)
                .environmentObject(model.player)
                .environmentObject(model.control)
                .environmentObject(model.recorder)
                .frame(minWidth: 900, minHeight: 540)
        }
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Camera Settings…") { model.showSettings = true }.keyboardShortcut(",")
            }
            CommandMenu("Camera") {
                Button("Take Snapshot") { model.snapshot() }.keyboardShortcut("s", modifiers: [.command, .shift])
                Button(model.recorder.isRecording ? "Stop Recording" : "Start Recording") { model.toggleRecording() }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                Divider()
                Button("Reconnect") { model.reconnect() }.keyboardShortcut("r")
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var settings = CameraSettings.load()
    @Published var showSettings = false
    @Published var toast: String?

    let player = StreamPlayer()
    let control = TapoControl()
    let recorder = Recorder()

    init() {
        if settings.isConfigured { reconnect() } else { showSettings = true }
    }

    func apply(_ new: CameraSettings) {
        settings = new
        settings.save()
        reconnect()
    }

    func reconnect() {
        guard settings.isConfigured else { showSettings = true; return }
        player.play(url: settings.rtspURL())
        Task { await control.connect(settings) }
    }

    func setQuality(high: Bool) {
        settings.highQuality = high
        settings.save()
        player.play(url: settings.rtspURL())
    }

    func snapshot() {
        guard let frame = player.frame, let url = Snapshot.save(frame) else { show("No picture to save yet"); return }
        show("Saved to Pictures/TapoCam/\(url.lastPathComponent)")
    }

    func toggleRecording() {
        if recorder.isRecording { recorder.stop(); show("Recording saved to Movies/TapoCam") }
        else if let err = recorder.start(url: settings.rtspURL(high: true)) { show(err) }
    }

    func show(_ message: String) {
        toast = message
        Task {
            try? await Task.sleep(for: .seconds(3))
            if toast == message { toast = nil }
        }
    }
}
