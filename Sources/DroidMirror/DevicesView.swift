import SwiftUI

struct DevicesView: View {
    @ObservedObject var model: AppModel
    @State private var connectAddress = UserDefaults.standard.string(forKey: Pref.lastAddress) ?? ""
    @State private var pairAddress = ""
    @State private var pairCode = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !model.adbAvailable {
                Label("adb wasn't found. Reinstall DroidMirror, or install Android platform-tools.",
                      systemImage: "exclamationmark.triangle")
                    .foregroundColor(.orange)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    if model.devices.isEmpty {
                        Text("No phones found. Plug in your phone with USB debugging on, or connect over Wi-Fi below.")
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.vertical, 6)
                    }
                    ForEach(model.devices) { device in
                        DeviceRow(model: model, device: device)
                        if device.id != model.devices.last?.id { Divider() }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(4)
            } label: {
                Text("Phones").font(.headline)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Text("On the phone: Developer options → Wireless debugging. Use the IP address & Port shown there.")
                        .font(.caption).foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        TextField("192.168.1.23:37159", text: $connectAddress)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { model.connect(address: connectAddress) }
                        Button("Connect") { model.connect(address: connectAddress) }
                            .disabled(connectAddress.isEmpty || model.busy != nil)
                    }
                }
                .padding(4)
            } label: {
                Text("Connect over Wi-Fi").font(.headline)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Text("First time only (Android 11+): Wireless debugging → Pair device with pairing code.")
                        .font(.caption).foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        TextField("IP address:port", text: $pairAddress)
                            .textFieldStyle(.roundedBorder)
                        TextField("Code", text: $pairCode)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 90)
                        Button("Pair") { model.pair(address: pairAddress, code: pairCode) }
                            .disabled(pairAddress.isEmpty || pairCode.isEmpty || model.busy != nil)
                    }
                }
                .padding(4)
            } label: {
                Text("Pair a new phone").font(.headline)
            }

            HStack {
                if let busy = model.busy {
                    ProgressView().controlSize(.small)
                    Text(busy).foregroundColor(.secondary)
                } else if let toast = model.toast {
                    Text(toast).foregroundColor(.secondary)
                } else if case .error(let e) = model.status {
                    Text(e).foregroundColor(.red)
                }
                Spacer()
            }
            .font(.callout)
            .frame(minHeight: 18)
        }
        .padding(20)
        .frame(width: 460)
    }
}

struct DeviceRow: View {
    @ObservedObject var model: AppModel
    let device: ADBDevice

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: device.isWireless ? "wifi" : "cable.connector")
                .frame(width: 20)
                .foregroundColor(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(device.displayName).font(.body.weight(.medium))
                Text(stateText).font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            if device.isReady && !device.isWireless {
                Button("Use Wi-Fi") { model.switchToWiFi(device) }
                    .disabled(model.busy != nil)
                    .help("Switch this phone to wireless debugging so you can unplug the cable")
            }
            Button(isCurrent ? "Show" : "Mirror") {
                if isCurrent { model.showMirrorWindow() } else { model.mirror(device) }
            }
            .disabled(!device.isReady)
        }
        .padding(.vertical, 2)
    }

    private var isCurrent: Bool { model.session?.serial == device.serial }

    private var stateText: String {
        switch device.state {
        case "device": return device.serial
        case "unauthorized": return "Allow USB debugging on the phone"
        case "offline": return "Offline: reconnect the phone"
        default: return device.state
        }
    }
}

struct SettingsView: View {
    @AppStorage(Pref.maxSize) private var maxSize = 1920
    @AppStorage(Pref.bitRateMbps) private var bitRate = 8
    @AppStorage(Pref.maxFps) private var maxFps = 60
    @AppStorage(Pref.audio) private var audio = true
    @AppStorage(Pref.screenOff) private var screenOff = false
    @AppStorage(Pref.stayAwake) private var stayAwake = true
    @AppStorage(Pref.autoReconnect) private var autoReconnect = true

    var body: some View {
        Form {
            Picker("Resolution", selection: $maxSize) {
                Text("1024").tag(1024)
                Text("1280").tag(1280)
                Text("1600").tag(1600)
                Text("1920").tag(1920)
                Text("Phone's native").tag(0)
            }
            Picker("Quality", selection: $bitRate) {
                Text("Low (4 Mbps)").tag(4)
                Text("Normal (8 Mbps)").tag(8)
                Text("High (16 Mbps)").tag(16)
                Text("Max (32 Mbps)").tag(32)
            }
            Picker("Frame rate", selection: $maxFps) {
                Text("30 fps").tag(30)
                Text("60 fps").tag(60)
                Text("90 fps").tag(90)
                Text("120 fps").tag(120)
            }
            Toggle("Play phone audio on the Mac (Android 11+)", isOn: $audio)
            Toggle("Turn phone screen off while mirroring", isOn: $screenOff)
            Toggle("Keep phone awake while mirroring", isOn: $stayAwake)
            Toggle("Reconnect automatically", isOn: $autoReconnect)
            Text("Changes apply the next time you connect.")
                .font(.caption).foregroundColor(.secondary)
        }
        .padding(20)
        .frame(width: 420)
    }
}
