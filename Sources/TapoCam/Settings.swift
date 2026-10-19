import Foundation
import Security

/// Connection details. Non-secret fields live in UserDefaults, passwords in the Keychain.
struct CameraSettings: Equatable {
    var host = ""
    /// "Camera Account" created in the Tapo app (Advanced Settings → Camera Account). Used for RTSP video.
    var streamUser = ""
    var streamPassword = ""
    /// Tapo cloud account password. Used (with user "admin") for pan/tilt and settings.
    var cloudPassword = ""
    var highQuality = true
    var panStep = 15

    var isConfigured: Bool { !host.isEmpty && !streamUser.isEmpty && !streamPassword.isEmpty }

    func rtspURL(high: Bool? = nil) -> String {
        let user = streamUser.addingPercentEncoding(withAllowedCharacters: .urlUserAllowed) ?? streamUser
        let pass = streamPassword.addingPercentEncoding(withAllowedCharacters: .urlPasswordAllowed) ?? streamPassword
        return "rtsp://\(user):\(pass)@\(host):554/\((high ?? highQuality) ? "stream1" : "stream2")"
    }

    static func load() -> CameraSettings {
        let d = UserDefaults.standard
        var s = CameraSettings()
        s.host = d.string(forKey: "host") ?? ""
        s.streamUser = d.string(forKey: "streamUser") ?? ""
        s.highQuality = d.object(forKey: "highQuality") as? Bool ?? true
        s.panStep = d.object(forKey: "panStep") as? Int ?? 15
        s.streamPassword = Keychain.get("streamPassword") ?? ""
        s.cloudPassword = Keychain.get("cloudPassword") ?? ""
        return s
    }

    func save() {
        let d = UserDefaults.standard
        d.set(host, forKey: "host")
        d.set(streamUser, forKey: "streamUser")
        d.set(highQuality, forKey: "highQuality")
        d.set(panStep, forKey: "panStep")
        Keychain.set("streamPassword", streamPassword)
        Keychain.set("cloudPassword", cloudPassword)
    }
}

enum Keychain {
    private static let service = "com.endless.TapoCam"

    static func get(_ key: String) -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: service,
                                kSecAttrAccount as String: key,
                                kSecReturnData as String: true]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func set(_ key: String, _ value: String) {
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                   kSecAttrService as String: service,
                                   kSecAttrAccount as String: key]
        SecItemDelete(base as CFDictionary)
        guard !value.isEmpty else { return }
        var add = base
        add[kSecValueData as String] = Data(value.utf8)
        SecItemAdd(add as CFDictionary, nil)
    }
}

enum Tools {
    static func find(_ name: String) -> String? {
        ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"]
            .map { "\($0)/\(name)" }
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static var supportDir: URL {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TapoCam", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func outputDir(_ base: FileManager.SearchPathDirectory) -> URL {
        let url = FileManager.default.urls(for: base, in: .userDomainMask)[0]
            .appendingPathComponent("TapoCam", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static var timestamp: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return f.string(from: Date())
    }
}
