import Foundation

protocol ScrcpySessionDelegate: AnyObject {
    func sessionDidConnect(_ session: ScrcpySession, deviceName: String)
    func session(_ session: ScrcpySession, videoSizeChanged width: Int, height: Int)
    func session(_ session: ScrcpySession, clipboardChanged text: String)
    func session(_ session: ScrcpySession, didEnd error: String?)
}

/// One mirroring session: pushes and starts scrcpy-server on the phone, then demuxes its streams.
final class ScrcpySession {
    struct Options {
        var maxSize = 1920
        var bitRate = 8_000_000
        var maxFps = 60
        var audio = true
        var stayAwake = true
    }

    static let serverVersion = "5.0.1"
    static let devicePath = "/data/local/tmp/scrcpy-server.jar"

    weak var delegate: ScrcpySessionDelegate?
    let serial: String
    let options: Options
    let renderer: H264Renderer

    private let scid = UInt32.random(in: 1..<0x7FFF_FFFF)
    private var port: UInt16 = 0
    private var server: Process?
    private var video: TCPSocket?
    private var audioSock: TCPSocket?
    private var control: TCPSocket?
    private var audioPlayer: AudioPlayer?
    private let sendQueue = DispatchQueue(label: "DroidMirror.control", qos: .userInteractive)
    private var serverLog = ""
    private let stateLock = NSLock()
    private var stopped = false
    private var ended = false

    private(set) var videoWidth = 0
    private(set) var videoHeight = 0

    init(serial: String, options: Options, renderer: H264Renderer) {
        self.serial = serial
        self.options = options
        self.renderer = renderer
    }

    private var socketName: String { String(format: "scrcpy_%08x", scid) }

    static func serverJarPath() -> String? {
        Bundle.main.resourceURL.map { $0.appendingPathComponent("scrcpy-server").path }
            .flatMap { FileManager.default.fileExists(atPath: $0) ? $0 : nil }
    }

    func start() {
        Thread.detachNewThread { [self] in
            do {
                try self.connect()
            } catch {
                self.finish(error: (error as? LocalizedError)?.errorDescription ?? "\(error)")
            }
        }
    }

    private func connect() throws {
        let adb = ADB.shared
        guard let jar = ScrcpySession.serverJarPath() else {
            throw ADBError.failed("scrcpy-server is missing from the app bundle.")
        }
        try adb.run(["-s", serial, "push", jar, ScrcpySession.devicePath])
        let portOut = try adb.run(["-s", serial, "forward", "tcp:0", "localabstract:\(socketName)"])
        guard let p = UInt16(portOut.split(separator: "\n").last?.trimmingCharacters(in: .whitespaces) ?? "") else {
            throw ADBError.failed("adb forward failed: \(portOut)")
        }
        port = p

        try launchServer()

        // The server listens only after it has started; retry until the first socket gets the dummy byte.
        var videoSocket: TCPSocket?
        for _ in 0..<100 {
            if isStopped { return }
            if let s = try? TCPSocket(port: port) {
                if (try? s.read(1)) != nil {
                    videoSocket = s
                    break
                }
                s.close()
            }
            if let proc = server, !proc.isRunning { break }
            Thread.sleep(forTimeInterval: 0.1)
        }
        guard let videoSocket else {
            throw ADBError.failed(serverError() ?? "Couldn't connect to the phone.")
        }
        video = videoSocket
        if options.audio { audioSock = try TCPSocket(port: port) }
        control = try TCPSocket(port: port)

        let meta = try videoSocket.read(64)
        let name = String(decoding: meta.prefix { $0 != 0 }, as: UTF8.self)
        DispatchQueue.main.async { self.delegate?.sessionDidConnect(self, deviceName: name) }

        if let audioSock {
            Thread.detachNewThread { [self] in self.audioLoop(audioSock) }
        }
        if let control {
            Thread.detachNewThread { [self] in self.controlLoop(control) }
        }
        videoLoop(videoSocket)
    }

    private func launchServer() throws {
        guard let adbPath = ADB.shared.path else { throw ADBError.notFound }
        let params = [
            "scid=\(String(format: "%08x", scid))",
            "log_level=info",
            "tunnel_forward=true",
            "video_codec=h264",
            "max_size=\(options.maxSize)",
            "video_bit_rate=\(options.bitRate)",
            "max_fps=\(options.maxFps)",
            "audio=\(options.audio)",
            "audio_codec=raw",
            "control=true",
            "clipboard_autosync=true",
            "stay_awake=\(options.stayAwake)",
            "power_off_on_close=false",
        ]
        let p = Process()
        p.executableURL = URL(fileURLWithPath: adbPath)
        p.arguments = ["-s", serial, "shell", "CLASSPATH=\(ScrcpySession.devicePath)", "app_process", "/",
                       "com.genymobile.scrcpy.Server", ScrcpySession.serverVersion] + params
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        p.standardInput = FileHandle.nullDevice
        pipe.fileHandleForReading.readabilityHandler = { [weak self] h in
            let chunk = String(decoding: h.availableData, as: UTF8.self)
            guard let self, !chunk.isEmpty else { return }
            self.stateLock.lock()
            self.serverLog += chunk
            if self.serverLog.count > 20_000 { self.serverLog = String(self.serverLog.suffix(10_000)) }
            self.stateLock.unlock()
            NSLog("scrcpy-server: %@", chunk)
        }
        p.terminationHandler = { [weak self] _ in
            pipe.fileHandleForReading.readabilityHandler = nil
            self?.finish(error: self?.serverError())
        }
        try p.run()
        server = p
    }

    private func serverError() -> String? {
        stateLock.lock()
        defer { stateLock.unlock() }
        let lines = serverLog.split(separator: "\n").filter { $0.contains("ERROR") || $0.contains("Exception") }
        return lines.first.map { String($0) }
    }

    private var isStopped: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return stopped
    }

    // MARK: Streams

    private func videoLoop(_ s: TCPSocket) {
        do {
            let codec = try s.read(4).be32(0)
            if codec == 0 || codec == 1 {
                finish(error: serverError() ?? "The phone couldn't start screen capture.")
                return
            }
            guard codec == 0x6832_3634 else {
                finish(error: "Unexpected video codec.")
                return
            }
            while true {
                let header = try s.read(12)
                if header[header.startIndex] & 0x80 != 0 {
                    // Session packet: new capture size (first start, rotation, fold...)
                    let w = Int(header.be32(4)), h = Int(header.be32(8))
                    videoWidth = w
                    videoHeight = h
                    DispatchQueue.main.async { self.delegate?.session(self, videoSizeChanged: w, height: h) }
                    continue
                }
                let size = Int(header.be32(8))
                guard size > 0, size < 32 * 1024 * 1024 else { throw SocketError.closed }
                let packet = try s.read(size)
                renderer.handle(packet: packet)
            }
        } catch {
            finish(error: isStopped ? nil : (serverError() ?? "The connection to the phone was lost."))
        }
    }

    private func audioLoop(_ s: TCPSocket) {
        do {
            let codec = try s.read(4).be32(0)
            if codec == 0 { return } // phone can't capture audio (Android < 11); keep video
            if codec == 1 { return }
            guard codec == 0x0072_6177 else { return }
            let player = AudioPlayer()
            audioPlayer = player
            player.start()
            while true {
                let header = try s.read(12)
                let flags = header.be64(0)
                let size = Int(header.be32(8))
                guard size >= 0, size < 4 * 1024 * 1024 else { break }
                let packet = try s.read(size)
                if flags & (1 << 62) != 0 { continue } // config packet
                player.push(packet)
            }
        } catch {}
        audioPlayer?.stop()
    }

    private func controlLoop(_ s: TCPSocket) {
        do {
            while true {
                let type = try s.read(1)[0]
                switch type {
                case 0: // clipboard
                    let len = Int(try s.read(4).be32(0))
                    let text = String(decoding: try s.read(len), as: UTF8.self)
                    DispatchQueue.main.async { self.delegate?.session(self, clipboardChanged: text) }
                case 1: // clipboard ack
                    _ = try s.read(8)
                case 2: // uhid output
                    _ = try s.read(2)
                    let b = try s.read(2)
                    let len = Int(b[b.startIndex]) << 8 | Int(b[b.startIndex + 1])
                    _ = try s.read(len)
                default:
                    return
                }
            }
        } catch {}
    }

    // MARK: Control

    func send(_ msg: Data) {
        guard let control else { return }
        // Serial queue: touch down/move/up must reach the phone in order.
        sendQueue.async {
            try? control.write(msg)
        }
    }

    // MARK: Teardown

    func stop() {
        stateLock.lock()
        stopped = true
        stateLock.unlock()
        teardown()
    }

    private func teardown() {
        video?.close()
        audioSock?.close()
        control?.close()
        audioPlayer?.stop()
        if let server, server.isRunning { server.terminate() }
        let serial = self.serial, port = self.port
        if port != 0 {
            DispatchQueue.global().async {
                _ = try? ADB.shared.run(["-s", serial, "forward", "--remove", "tcp:\(port)"])
            }
        }
    }

    private func finish(error: String?) {
        stateLock.lock()
        if ended {
            stateLock.unlock()
            return
        }
        ended = true
        let wasStopped = stopped
        stateLock.unlock()
        teardown()
        DispatchQueue.main.async {
            self.delegate?.session(self, didEnd: wasStopped ? nil : error)
        }
    }
}
