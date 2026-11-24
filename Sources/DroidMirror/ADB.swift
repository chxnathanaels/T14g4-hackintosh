import Foundation

struct ADBDevice: Identifiable, Hashable {
    let serial: String
    let state: String
    let model: String

    var id: String { serial }
    var isWireless: Bool { serial.contains(":") || serial.contains("._adb-tls-connect") }
    var isReady: Bool { state == "device" }
    var displayName: String { model.isEmpty ? serial : model.replacingOccurrences(of: "_", with: " ") }
}

enum ADBError: LocalizedError {
    case notFound
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .notFound: return "adb was not found."
        case .failed(let msg): return msg.isEmpty ? "adb command failed." : msg
        }
    }
}

/// Thin wrapper around the adb command-line tool.
final class ADB {
    static let shared = ADB()

    let path: String?

    private init() {
        path = ADB.locate()
        if let path {
            // Start the adb daemon detached from our pipes, so later reads don't hang on its inherited fds.
            let p = Process()
            p.executableURL = URL(fileURLWithPath: path)
            p.arguments = ["start-server"]
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
            try? p.run()
            p.waitUntilExit()
        }
    }

    static func locate() -> String? {
        var candidates: [String] = []
        if let res = Bundle.main.resourceURL {
            candidates.append(res.appendingPathComponent("platform-tools/adb").path)
        }
        let home = NSHomeDirectory()
        candidates += [
            "/opt/homebrew/bin/adb",
            "/usr/local/bin/adb",
            "\(home)/Library/Android/sdk/platform-tools/adb",
            "\(home)/platform-tools/adb",
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    @discardableResult
    func run(_ args: [String]) throws -> String {
        guard let path else { throw ADBError.notFound }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        p.standardInput = FileHandle.nullDevice
        try p.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let out = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        if p.terminationStatus != 0 { throw ADBError.failed(out) }
        return out
    }

    func devices() -> [ADBDevice] {
        guard let out = try? run(["devices", "-l"]) else { return [] }
        var result: [ADBDevice] = []
        for line in out.split(separator: "\n").dropFirst() {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 2 else { continue }
            let serial = String(parts[0])
            let state = String(parts[1])
            var model = ""
            for p in parts.dropFirst(2) where p.hasPrefix("model:") {
                model = String(p.dropFirst("model:".count))
            }
            result.append(ADBDevice(serial: serial, state: state, model: model))
        }
        // A phone paired over Wi-Fi can show up twice (IP and mDNS name); keep one entry per model+state.
        var seen = Set<String>()
        return result.filter { dev in
            guard dev.isWireless, !dev.model.isEmpty else { return true }
            return seen.insert("w-\(dev.model)").inserted
        }
    }

    func pair(address: String, code: String) throws -> String {
        let out = try run(["pair", address, code])
        guard out.lowercased().contains("success") else { throw ADBError.failed(out) }
        return out
    }

    func connect(address: String) throws {
        let out = try run(["connect", address])
        let lower = out.lowercased()
        guard lower.contains("connected to") || lower.contains("already connected") else {
            throw ADBError.failed(out)
        }
    }

    func disconnect(address: String) {
        _ = try? run(["disconnect", address])
    }

    /// Switches a USB-connected phone to adb over TCP and connects to it. Returns the address.
    func switchToWiFi(serial: String) throws -> String {
        let route = try run(["-s", serial, "shell", "ip", "route"])
        // e.g. "192.168.1.0/24 dev wlan0 proto kernel scope link src 192.168.1.23"
        var ip: String?
        for line in route.split(separator: "\n") where line.contains("wlan") {
            let parts = line.split(separator: " ")
            if let i = parts.firstIndex(of: "src"), i + 1 < parts.count { ip = String(parts[i + 1]) }
        }
        guard let ip else { throw ADBError.failed("Couldn't find the phone's Wi-Fi address. Is it on Wi-Fi?") }
        try run(["-s", serial, "tcpip", "5555"])
        Thread.sleep(forTimeInterval: 1.5)
        let address = "\(ip):5555"
        try connect(address: address)
        return address
    }
}
