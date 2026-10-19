import Foundation

struct Preset: Identifiable, Hashable, Decodable {
    let id: String
    let name: String
}

struct CameraStatus: Decodable {
    var privacy: Bool?
    var led: Bool?
    var dayNight: String?
    var motion: Bool?
    var flip: Bool?
    var presets: [Preset]?
    var model: String?
    var name: String?
    var firmware: String?
}

/// Talks to the camera's local Tapo API through a long-lived Python helper (pytapo).
@MainActor
final class TapoControl: ObservableObject {
    enum State: Equatable { case disconnected, installing, connecting, connected, failed(String) }

    @Published private(set) var state: State = .disconnected
    @Published var status = CameraStatus()
    @Published var busy = false
    @Published var lastError: String?

    private var process: Process?
    private var stdin: FileHandle?
    private var nextID = 1
    private var pending: [Int: CheckedContinuation<Any?, Error>] = [:]
    private var lineBuffer = Data()

    private var venv: URL { Tools.supportDir.appendingPathComponent("venv") }
    private var venvPython: String { venv.appendingPathComponent("bin/python3").path }

    func connect(_ s: CameraSettings) async {
        disconnect()
        guard !s.cloudPassword.isEmpty else {
            state = .failed("Add your Tapo account password in Settings to enable pan/tilt and camera controls.")
            return
        }
        do {
            try await ensureRuntime()
            state = .connecting
            try launchHelper()
            let raw = try await call("connect", ["host": s.host, "user": "admin", "password": s.cloudPassword,
                                                 "cloudPassword": s.cloudPassword])
            status = try decode(raw)
            state = .connected
        } catch {
            state = .failed(error.localizedDescription)
            disconnect(keepState: true)
        }
    }

    func disconnect(keepState: Bool = false) {
        process?.terminate()
        process = nil
        stdin = nil
        for (_, c) in pending { c.resume(throwing: HelperError("disconnected")) }
        pending.removeAll()
        if !keepState { state = .disconnected }
    }

    // MARK: Commands

    func move(x: Int, y: Int) { fire("move", ["x": x, "y": y]) }
    func calibrate() { fire("calibrate") }
    func gotoPreset(_ p: Preset) { fire("presetGoto", ["id": p.id]) }
    func reboot() { fire("reboot") }

    func savePreset(name: String) {
        Task { if let raw = await run("presetSave", ["name": name]), let list: [Preset] = try? decode(raw) { status.presets = list } }
    }

    func deletePreset(_ p: Preset) {
        Task { if let raw = await run("presetDelete", ["id": p.id]), let list: [Preset] = try? decode(raw) { status.presets = list } }
    }

    func setPrivacy(_ on: Bool) { status.privacy = on; fire("privacy", ["on": on]) }
    func setLED(_ on: Bool) { status.led = on; fire("led", ["on": on]) }
    func setMotion(_ on: Bool) { status.motion = on; fire("motion", ["on": on]) }
    func setFlip(_ on: Bool) { status.flip = on; fire("flip", ["on": on]) }
    func setDayNight(_ mode: String) { status.dayNight = mode; fire("dayNight", ["mode": mode]) }
    func setAlarm(_ on: Bool) { fire("alarm", ["on": on]) }

    func refresh() {
        Task { if let raw = await run("status"), let s: CameraStatus = try? decode(raw) { status = s } }
    }

    private func fire(_ cmd: String, _ args: [String: Any] = [:]) {
        Task { _ = await run(cmd, args) }
    }

    @discardableResult
    private func run(_ cmd: String, _ args: [String: Any] = [:]) async -> Any? {
        guard state == .connected else { return nil }
        busy = true
        defer { busy = false }
        do {
            let r = try await call(cmd, args)
            lastError = nil
            return r
        } catch {
            lastError = "\(cmd): \(error.localizedDescription)"
            return nil
        }
    }

    // MARK: Python runtime

    private func ensureRuntime() async throws {
        if FileManager.default.isExecutableFile(atPath: venvPython),
           (try? await shell(venvPython, ["-c", "import pytapo"])) != nil { return }
        state = .installing
        guard let py = Tools.find("python3") else { throw HelperError("python3 not found. Install it with: brew install python") }
        if !FileManager.default.isExecutableFile(atPath: venvPython) {
            try await shell(py, ["-m", "venv", venv.path])
        }
        try await shell(venvPython, ["-m", "pip", "install", "--quiet", "--disable-pip-version-check", "pytapo"])
    }

    @discardableResult
    private func shell(_ exe: String, _ args: [String]) async throws -> String {
        try await withCheckedThrowingContinuation { cont in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: exe)
            p.arguments = args
            let out = Pipe()
            p.standardOutput = out
            p.standardError = out
            p.terminationHandler = { p in
                let text = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                if p.terminationStatus == 0 { cont.resume(returning: text) }
                else { cont.resume(throwing: HelperError("\(URL(fileURLWithPath: exe).lastPathComponent) failed: \(text.suffix(300))")) }
            }
            do { try p.run() } catch { cont.resume(throwing: error) }
        }
    }

    private var helperScript: String? {
        if let url = Bundle.main.url(forResource: "tapo_helper", withExtension: "py") { return url.path }
        // Running via `swift run`: use the shared copy in the repo.
        let dev = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../../shared/tapo_helper.py").standardized.path
        return FileManager.default.fileExists(atPath: dev) ? dev : nil
    }

    private func launchHelper() throws {
        guard let script = helperScript else { throw HelperError("tapo_helper.py missing from app bundle") }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: venvPython)
        p.arguments = ["-u", script]
        let inPipe = Pipe(), outPipe = Pipe()
        p.standardInput = inPipe
        p.standardOutput = outPipe
        p.standardError = FileHandle.nullDevice
        outPipe.fileHandleForReading.readabilityHandler = { [weak self] h in
            let data = h.availableData
            guard !data.isEmpty else { h.readabilityHandler = nil; return }
            Task { @MainActor [weak self] in self?.receive(data) }
        }
        p.terminationHandler = { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.process === p else { return }
                self.disconnect(keepState: true)
                if self.state == .connected { self.state = .failed("Control helper stopped. Click Reconnect.") }
            }
        }
        try p.run()
        process = p
        stdin = inPipe.fileHandleForWriting
    }

    private func receive(_ data: Data) {
        lineBuffer.append(data)
        while let nl = lineBuffer.firstIndex(of: 0x0A) {
            let line = lineBuffer[lineBuffer.startIndex..<nl]
            lineBuffer.removeSubrange(lineBuffer.startIndex...nl)
            guard let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  let id = obj["id"] as? Int, let cont = pending.removeValue(forKey: id) else { continue }
            if obj["ok"] as? Bool == true {
                cont.resume(returning: obj["result"])
            } else {
                cont.resume(throwing: HelperError(Self.friendly(obj["error"] as? String ?? "unknown error")))
            }
        }
    }

    private func call(_ cmd: String, _ args: [String: Any] = [:]) async throws -> Any? {
        guard let stdin else { throw HelperError("not connected") }
        let id = nextID
        nextID += 1
        var line = try JSONSerialization.data(withJSONObject: ["id": id, "cmd": cmd, "args": args])
        line.append(0x0A)
        return try await withCheckedThrowingContinuation { cont in
            pending[id] = cont
            stdin.write(line)
        }
    }

    private func decode<T: Decodable>(_ raw: Any?) throws -> T {
        let data = try JSONSerialization.data(withJSONObject: raw ?? NSNull(), options: .fragmentsAllowed)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private static func friendly(_ e: String) -> String {
        let l = e.lowercased()
        if l.contains("invalid authentication") || l.contains("-40401") || l.contains("password") {
            return "Tapo rejected the login. Use your Tapo app account password (not the camera account)."
        }
        if l.contains("temporary suspension") || l.contains("-40404") {
            return "Too many failed logins. The camera has locked logins for ~30 minutes."
        }
        return e
    }
}

struct HelperError: LocalizedError {
    let message: String
    init(_ m: String) { message = m }
    var errorDescription: String? { message }
}
