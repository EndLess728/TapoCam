import AppKit

/// Records the camera's original stream to MP4 without re-encoding.
@MainActor
final class Recorder: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var startedAt: Date?
    private var process: Process?
    private var input: Pipe?
    private var file: URL?

    func start(url: String) -> String? {
        guard !isRecording else { return nil }
        guard let ffmpeg = Tools.find("ffmpeg") else { return "ffmpeg not found" }
        let out = Tools.outputDir(.moviesDirectory).appendingPathComponent("Tapo \(Tools.timestamp).mp4")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: ffmpeg)
        p.arguments = ["-hide_banner", "-loglevel", "error", "-rtsp_transport", "tcp", "-i", url,
                       "-c:v", "copy", "-c:a", "aac", "-movflags", "+faststart", "-y", out.path]
        let stdin = Pipe()
        p.standardInput = stdin
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        p.terminationHandler = { [weak self] _ in
            Task { @MainActor in self?.finished() }
        }
        do { try p.run() } catch { return error.localizedDescription }
        process = p; input = stdin; file = out
        isRecording = true
        startedAt = Date()
        return nil
    }

    func stop() {
        // "q" makes ffmpeg finalise the MP4 cleanly.
        input?.fileHandleForWriting.write(Data("q".utf8))
        let p = process
        DispatchQueue.global().asyncAfter(deadline: .now() + 5) { if p?.isRunning == true { p?.interrupt() } }
    }

    private func finished() {
        isRecording = false
        startedAt = nil
        process = nil; input = nil
        if let file, FileManager.default.fileExists(atPath: file.path) {
            NSWorkspace.shared.activateFileViewerSelecting([file])
        }
        file = nil
    }
}

enum Snapshot {
    static func save(_ image: CGImage) -> URL? {
        let url = Tools.outputDir(.picturesDirectory).appendingPathComponent("Tapo \(Tools.timestamp).png")
        let rep = NSBitmapImageRep(cgImage: image)
        guard let data = rep.representation(using: .png, properties: [:]), (try? data.write(to: url)) != nil else { return nil }
        return url
    }
}
