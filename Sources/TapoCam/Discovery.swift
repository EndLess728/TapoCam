import Foundation
import Network

/// Finds Tapo cameras on the local /24 by probing the ports they always expose (ONVIF 2020 + RTSP 554).
enum Discovery {
    static func scan() async -> [String] {
        guard let prefix = localPrefix() else { return [] }
        return await withTaskGroup(of: String?.self) { group in
            for i in 1...254 {
                let host = "\(prefix).\(i)"
                group.addTask {
                    guard await isOpen(host, 2020) else { return nil }
                    return await isOpen(host, 554) ? host : nil
                }
            }
            var found: [String] = []
            for await h in group { if let h { found.append(h) } }
            return found.sorted { $0.split(separator: ".").last.flatMap { Int($0) } ?? 0 < $1.split(separator: ".").last.flatMap { Int($0) } ?? 0 }
        }
    }

    static func isOpen(_ host: String, _ port: UInt16, timeout: Double = 1.5) async -> Bool {
        await withCheckedContinuation { cont in
            let conn = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!, using: .tcp)
            let once = Once()
            let finish: @Sendable (Bool) -> Void = { ok in
                guard once.claim() else { return }
                conn.cancel()
                cont.resume(returning: ok)
            }
            conn.stateUpdateHandler = { state in
                switch state {
                case .ready: finish(true)
                case .failed, .waiting: finish(false)
                default: break
                }
            }
            conn.start(queue: .global())
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { finish(false) }
        }
    }

    /// First three octets of this Mac's IPv4 address on Wi-Fi/Ethernet.
    static func localPrefix() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }
        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let ifa = ptr.pointee
            guard let addr = ifa.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) else { continue }
            let name = String(cString: ifa.ifa_name)
            guard name.hasPrefix("en") else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
            let ip = String(cString: host)
            let parts = ip.split(separator: ".")
            if parts.count == 4 { return parts.prefix(3).joined(separator: ".") }
        }
        return nil
    }
}

private final class Once: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    func claim() -> Bool { lock.lock(); defer { lock.unlock() }; if done { return false }; done = true; return true }
}
