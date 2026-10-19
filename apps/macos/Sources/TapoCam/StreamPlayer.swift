import AppKit
import ImageIO

/// Pulls the RTSP stream through ffmpeg, which re-emits it as a pipe of JPEG frames.
@MainActor
final class StreamPlayer: ObservableObject {
    enum State: Equatable { case idle, connecting, playing, failed(String) }

    @Published private(set) var frame: CGImage?
    @Published private(set) var state: State = .idle
    @Published private(set) var fps = 0

    private var process: Process?
    private var url: String?
    private var generation = 0
    private var retryTask: Task<Void, Never>?
    private var frameCount = 0
    private var fpsTimer: Timer?

    func play(url: String) {
        stop()
        self.url = url
        state = .connecting
        start()
        fpsTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.fps = self.frameCount
                self.frameCount = 0
            }
        }
    }

    func stop() {
        generation += 1
        retryTask?.cancel()
        fpsTimer?.invalidate()
        process?.terminate()
        process = nil
        url = nil
        fps = 0
        state = .idle
    }

    private func start() {
        guard let url else { return }
        guard let ffmpeg = Tools.find("ffmpeg") else {
            state = .failed("ffmpeg not found. Install it with: brew install ffmpeg")
            return
        }
        generation += 1
        let gen = generation
        let p = Process()
        p.executableURL = URL(fileURLWithPath: ffmpeg)
        p.arguments = ["-hide_banner", "-loglevel", "error",
                       "-rtsp_transport", "tcp", "-timeout", "5000000",
                       "-fflags", "nobuffer", "-flags", "low_delay",
                       "-hwaccel", "videotoolbox",
                       "-i", url, "-an",
                       "-f", "image2pipe", "-c:v", "mjpeg", "-q:v", "4", "-"]
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        p.standardInput = FileHandle.nullDevice

        let parser = JPEGStreamParser()
        let errLog = ErrorLog()
        out.fileHandleForReading.readabilityHandler = { [weak self] h in
            let data = h.availableData
            guard !data.isEmpty else { h.readabilityHandler = nil; return }
            for jpeg in parser.feed(data) {
                guard let src = CGImageSourceCreateWithData(jpeg as CFData, nil),
                      let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { continue }
                Task { @MainActor [weak self] in
                    guard let self, self.generation == gen else { return }
                    self.frame = img
                    self.frameCount += 1
                    if self.state != .playing { self.state = .playing }
                }
            }
        }
        err.fileHandleForReading.readabilityHandler = { h in
            let data = h.availableData
            guard !data.isEmpty else { h.readabilityHandler = nil; return }
            errLog.append(data)
        }
        p.terminationHandler = { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.generation == gen else { return }
                let log = errLog.text
                self.state = .failed(Self.explain(log))
                // Tapo blocks an IP after repeated failed logins, so don't hammer it with a bad password.
                let authFailed = log.contains("401") || log.lowercased().contains("unauthorized")
                self.retryTask = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(authFailed ? 60 : 3))
                    guard !Task.isCancelled, let self, self.generation == gen else { return }
                    self.state = .connecting
                    self.start()
                }
            }
        }
        do {
            try p.run()
            process = p
        } catch {
            state = .failed("Could not start ffmpeg: \(error.localizedDescription)")
        }
    }

    private static func explain(_ log: String) -> String {
        let l = log.lowercased()
        if l.contains("401") || l.contains("unauthorized") {
            return "The camera refused the login. Check the Camera Account (Tapo app → Camera Settings → Advanced Settings → Camera Account). Retrying in 60 s…"
        }
        if l.contains("connection refused") || l.contains("timed out") || l.contains("no route") || l.contains("host is down") {
            return "Can't reach the camera. Check its IP address and that it's on the same Wi-Fi. Retrying…"
        }
        let last = log.split(separator: "\n").last.map(String.init) ?? ""
        return last.isEmpty ? "Stream ended. Retrying…" : "\(last) Retrying…"
    }
}

/// Splits a byte stream of concatenated JPEGs on SOI (FFD8) / EOI (FFD9) markers.
final class JPEGStreamParser: @unchecked Sendable {
    private var buffer = Data()

    func feed(_ data: Data) -> [Data] {
        buffer.append(data)
        var frames: [Data] = []
        while true {
            guard let soi = buffer.firstRange(of: Data([0xFF, 0xD8])) else { buffer.removeAll(); break }
            guard let eoi = buffer[soi.upperBound...].firstRange(of: Data([0xFF, 0xD9])) else {
                if soi.lowerBound > buffer.startIndex { buffer.removeSubrange(buffer.startIndex..<soi.lowerBound) }
                break
            }
            frames.append(Data(buffer[soi.lowerBound..<eoi.upperBound]))
            buffer.removeSubrange(buffer.startIndex..<eoi.upperBound)
        }
        // Only the newest frame matters for a live view.
        return frames.suffix(1)
    }
}

final class ErrorLog: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    func append(_ d: Data) { lock.lock(); data.append(d); if data.count > 8192 { data = data.suffix(4096) }; lock.unlock() }
    var text: String { lock.lock(); defer { lock.unlock() }; return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) }
}
