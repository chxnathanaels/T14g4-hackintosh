import AppKit
import SwiftUI

enum Pref {
    static let maxSize = "maxSize"
    static let bitRateMbps = "bitRateMbps"
    static let maxFps = "maxFps"
    static let audio = "audio"
    static let screenOff = "screenOffWhileMirroring"
    static let stayAwake = "stayAwake"
    static let autoReconnect = "autoReconnect"
    static let lastSerial = "lastSerial"
    static let lastAddress = "lastAddress"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            maxSize: 1920, bitRateMbps: 8, maxFps: 60, audio: true,
            screenOff: false, stayAwake: true, autoReconnect: true,
        ])
    }
}

final class AppModel: ObservableObject, ScrcpySessionDelegate {
    static let shared = AppModel()

    enum Status: Equatable {
        case idle
        case connecting(String)
        case mirroring(String)
        case error(String)
    }

    @Published var devices: [ADBDevice] = []
    @Published var status: Status = .idle
    @Published var toast: String?
    @Published var phoneScreenOff = false
    @Published var busy: String?

    let adbAvailable = ADB.shared.path != nil
    let renderer = H264Renderer()
    private(set) var session: ScrcpySession?
    private var mirrorWindow: MirrorWindowController?
    private var refreshTimer: Timer?
    private var clipboardTimer: Timer?
    private var reconnectTimer: Timer?
    private var lastPasteboardCount = NSPasteboard.general.changeCount
    private var lastDeviceClipboard: String?
    private var toastWork: DispatchWorkItem?

    var deviceName: String {
        if case .mirroring(let n) = status { return n }
        if case .connecting(let n) = status { return n }
        return ""
    }

    var isMirroring: Bool {
        if case .mirroring = status { return true }
        return false
    }

    // MARK: Devices

    func startRefreshing() {
        refreshDevices()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { [weak self] _ in
            self?.refreshDevices()
        }
    }

    func refreshDevices(then: (() -> Void)? = nil) {
        guard adbAvailable else { return }
        DispatchQueue.global(qos: .utility).async {
            let list = ADB.shared.devices()
            DispatchQueue.main.async {
                if list != self.devices { self.devices = list }
                then?()
            }
        }
    }

    func background(_ label: String, _ work: @escaping () throws -> String?) {
        busy = label
        DispatchQueue.global(qos: .userInitiated).async {
            var message: String?
            do { message = try work() } catch {
                message = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            }
            DispatchQueue.main.async {
                self.busy = nil
                if let message { self.showToast(message) }
                self.refreshDevices()
            }
        }
    }

    func connect(address: String) {
        let address = address.trimmingCharacters(in: .whitespaces)
        guard !address.isEmpty else { return }
        background("Connecting to \(address)…") {
            try ADB.shared.connect(address: address)
            UserDefaults.standard.set(address, forKey: Pref.lastAddress)
            return "Connected to \(address)"
        }
    }

    func pair(address: String, code: String) {
        let address = address.trimmingCharacters(in: .whitespaces)
        let code = code.trimmingCharacters(in: .whitespaces)
        guard !address.isEmpty, !code.isEmpty else { return }
        background("Pairing…") {
            _ = try ADB.shared.pair(address: address, code: code)
            return "Paired. Now connect with the address shown under Wireless debugging."
        }
    }

    func switchToWiFi(_ device: ADBDevice) {
        background("Switching \(device.displayName) to Wi-Fi…") {
            let address = try ADB.shared.switchToWiFi(serial: device.serial)
            UserDefaults.standard.set(address, forKey: Pref.lastAddress)
            return "Connected over Wi-Fi at \(address). You can unplug the cable."
        }
    }

    // MARK: Mirroring

    func mirror(_ device: ADBDevice) {
        guard device.isReady else { return }
        reconnectTimer?.invalidate()
        session?.delegate = nil
        session?.stop()
        renderer.reset()

        let d = UserDefaults.standard
        var opts = ScrcpySession.Options()
        opts.maxSize = d.integer(forKey: Pref.maxSize)
        opts.bitRate = d.integer(forKey: Pref.bitRateMbps) * 1_000_000
        opts.maxFps = d.integer(forKey: Pref.maxFps)
        opts.audio = d.bool(forKey: Pref.audio)
        opts.stayAwake = d.bool(forKey: Pref.stayAwake)

        d.set(device.serial, forKey: Pref.lastSerial)
        phoneScreenOff = false
        status = .connecting(device.displayName)
        let s = ScrcpySession(serial: device.serial, options: opts, renderer: renderer)
        s.delegate = self
        session = s
        showMirrorWindow()
        s.start()
    }

    func disconnect(closeWindow: Bool = true) {
        reconnectTimer?.invalidate()
        session?.delegate = nil
        session?.stop()
        session = nil
        clipboardTimer?.invalidate()
        status = .idle
        if closeWindow { mirrorWindow?.close() }
    }

    func showMirrorWindow() {
        if mirrorWindow == nil { mirrorWindow = MirrorWindowController(model: self) }
        mirrorWindow?.showWindow(nil)
        mirrorWindow?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Called at launch: reconnect to the phone used last time.
    func autoConnect() {
        let d = UserDefaults.standard
        guard adbAvailable, let serial = d.string(forKey: Pref.lastSerial) else { return }
        let address = d.string(forKey: Pref.lastAddress)
        DispatchQueue.global().async {
            if let address, !ADB.shared.devices().contains(where: { $0.serial == serial && $0.isReady }) {
                try? ADB.shared.connect(address: address)
            }
            DispatchQueue.main.async {
                self.refreshDevices {
                    if let dev = self.devices.first(where: { $0.serial == serial && $0.isReady }) {
                        self.mirror(dev)
                    }
                }
            }
        }
    }

    private func scheduleReconnect(serial: String) {
        guard UserDefaults.standard.bool(forKey: Pref.autoReconnect) else { return }
        var attempts = 0
        reconnectTimer?.invalidate()
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] t in
            guard let self else { return t.invalidate() }
            attempts += 1
            if attempts > 40 || self.isMirroring { return t.invalidate() }
            if case .connecting = self.status { return }
            let address = UserDefaults.standard.string(forKey: Pref.lastAddress)
            DispatchQueue.global().async {
                if let address, serial.contains(":") || serial.contains("adb-") {
                    try? ADB.shared.connect(address: address)
                }
                DispatchQueue.main.async {
                    self.refreshDevices {
                        guard self.reconnectTimer?.isValid == true, !self.isMirroring else { return }
                        if let dev = self.devices.first(where: { $0.serial == serial && $0.isReady }) {
                            self.reconnectTimer?.invalidate()
                            self.mirror(dev)
                        }
                    }
                }
            }
        }
    }

    // MARK: Session delegate

    func sessionDidConnect(_ session: ScrcpySession, deviceName: String) {
        guard session === self.session else { return }
        status = .mirroring(deviceName.isEmpty ? session.serial : deviceName)
        startClipboardSync()
        if UserDefaults.standard.bool(forKey: Pref.screenOff) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.setPhoneScreen(on: false)
            }
        }
    }

    func session(_ session: ScrcpySession, videoSizeChanged width: Int, height: Int) {
        guard session === self.session else { return }
        mirrorWindow?.videoSizeChanged(width: width, height: height)
    }

    func session(_ session: ScrcpySession, clipboardChanged text: String) {
        guard session === self.session else { return }
        lastDeviceClipboard = text
        let pb = NSPasteboard.general
        if pb.string(forType: .string) != text {
            pb.clearContents()
            pb.setString(text, forType: .string)
        }
        lastPasteboardCount = pb.changeCount
    }

    func session(_ session: ScrcpySession, didEnd error: String?) {
        guard session === self.session else { return }
        self.session = nil
        clipboardTimer?.invalidate()
        if let error {
            status = .error(error)
            scheduleReconnect(serial: session.serial)
        } else {
            status = .idle
        }
    }

    // MARK: Clipboard

    private func startClipboardSync() {
        lastPasteboardCount = NSPasteboard.general.changeCount
        clipboardTimer?.invalidate()
        clipboardTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in
            guard let self else { return }
            let pb = NSPasteboard.general
            guard pb.changeCount != self.lastPasteboardCount else { return }
            self.lastPasteboardCount = pb.changeCount
            if let text = pb.string(forType: .string), text != self.lastDeviceClipboard {
                self.lastDeviceClipboard = text
                self.session?.send(Control.setClipboard(text, paste: false))
            }
        }
    }

    // MARK: Phone actions

    func send(_ msg: Data) { session?.send(msg) }

    func pressKey(_ code: Int32) {
        send(Control.keycode(.down, code))
        send(Control.keycode(.up, code))
    }

    func back() {
        send(Control.backOrScreenOn(.down))
        send(Control.backOrScreenOn(.up))
    }

    func home() { pressKey(AKey.home) }
    func recents() { pressKey(AKey.appSwitch) }
    func notifications() { send(Control.simple(.expandNotifications)) }
    func quickSettings() { send(Control.simple(.expandSettings)) }
    func rotate() { send(Control.simple(.rotateDevice)) }
    func volumeUp() { pressKey(AKey.volumeUp) }
    func volumeDown() { pressKey(AKey.volumeDown) }
    func power() { pressKey(AKey.power) }

    func setPhoneScreen(on: Bool) {
        send(Control.displayPower(on))
        phoneScreenOff = !on
    }

    func togglePhoneScreen() { setPhoneScreen(on: phoneScreenOff) }

    func pasteFromMac() {
        guard let text = NSPasteboard.general.string(forType: .string) else { return }
        lastDeviceClipboard = text
        send(Control.setClipboard(text, paste: true))
    }

    func copyFromPhone(cut: Bool) {
        send(Control.getClipboard(copyKey: cut ? 2 : 1))
    }

    // MARK: Files

    func sendFiles(_ urls: [URL]) {
        guard let serial = session?.serial else { return }
        let session = self.session
        background("Sending \(urls.count == 1 ? urls[0].lastPathComponent : "\(urls.count) files")…") {
            var done: [String] = []
            for url in urls {
                if url.pathExtension.lowercased() == "apk" {
                    try ADB.shared.run(["-s", serial, "install", "-r", url.path])
                    done.append("Installed \(url.lastPathComponent)")
                } else {
                    let dest = "/sdcard/Download/\(url.lastPathComponent)"
                    try ADB.shared.run(["-s", serial, "push", url.path, dest])
                    session?.send(Control.scanFile(dest))
                    done.append("\(url.lastPathComponent) → Download")
                }
            }
            return done.count == 1 ? done[0] : "Sent \(done.count) files to Download"
        }
    }

    // MARK: Toast

    func showToast(_ text: String) {
        toastWork?.cancel()
        toast = text
        let work = DispatchWorkItem { [weak self] in self?.toast = nil }
        toastWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: work)
    }
}
