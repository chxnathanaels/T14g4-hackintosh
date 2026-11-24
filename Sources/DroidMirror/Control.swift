import Foundation

/// Encoders for scrcpy control messages (protocol of scrcpy-server 5.x).
enum Control {
    enum MsgType: UInt8 {
        case injectKeycode = 0, injectText = 1, injectTouch = 2, injectScroll = 3, backOrScreenOn = 4
        case expandNotifications = 5, expandSettings = 6, collapsePanels = 7
        case getClipboard = 8, setClipboard = 9, setDisplayPower = 10, rotateDevice = 11
        case resetVideo = 17, scanFile = 22
    }

    enum Action: UInt8 { case down = 0, up = 1, move = 2 }

    /// Pointer id scrcpy uses for a generic finger (injected as touch, so swipes behave like on the phone).
    static let fingerPointer: UInt64 = UInt64(bitPattern: -2)

    static func keycode(_ action: Action, _ code: Int32, repeatCount: Int32 = 0, meta: Int32 = 0) -> Data {
        var d = Data([MsgType.injectKeycode.rawValue, action.rawValue])
        d.appendBE(code)
        d.appendBE(repeatCount)
        d.appendBE(meta)
        return d
    }

    static func text(_ s: String) -> Data {
        var bytes = Array(s.utf8)
        if bytes.count > 300 { bytes = Array(bytes.prefix(300)) }
        var d = Data([MsgType.injectText.rawValue])
        d.appendBE(UInt32(bytes.count))
        d.append(contentsOf: bytes)
        return d
    }

    private static func position(_ x: Int32, _ y: Int32, _ w: UInt16, _ h: UInt16) -> Data {
        var d = Data()
        d.appendBE(x)
        d.appendBE(y)
        d.appendBE(w)
        d.appendBE(h)
        return d
    }

    static func touch(_ action: Action, x: Int32, y: Int32, width: UInt16, height: UInt16) -> Data {
        var d = Data([MsgType.injectTouch.rawValue, action.rawValue])
        d.appendBE(fingerPointer)
        d.append(position(x, y, width, height))
        d.appendBE(UInt16(action == .up ? 0 : 0xFFFF)) // pressure
        d.appendBE(UInt32(0)) // action button
        d.appendBE(UInt32(0)) // buttons
        return d
    }

    /// hScroll/vScroll range is [-16, 16].
    static func scroll(x: Int32, y: Int32, width: UInt16, height: UInt16, h: Float, v: Float) -> Data {
        func fp(_ value: Float) -> Int16 {
            let f = max(-1, min(1, value / 16))
            return Int16(max(-32768, min(32767, (f * 32768).rounded())))
        }
        var d = Data([MsgType.injectScroll.rawValue])
        d.append(position(x, y, width, height))
        d.appendBE(fp(h))
        d.appendBE(fp(v))
        d.appendBE(UInt32(0))
        return d
    }

    static func backOrScreenOn(_ action: Action) -> Data {
        Data([MsgType.backOrScreenOn.rawValue, action.rawValue])
    }

    static func simple(_ type: MsgType) -> Data { Data([type.rawValue]) }

    static func getClipboard(copyKey: UInt8) -> Data {
        Data([MsgType.getClipboard.rawValue, copyKey])
    }

    static func setClipboard(_ s: String, paste: Bool) -> Data {
        var d = Data([MsgType.setClipboard.rawValue])
        d.appendBE(UInt64(0)) // no ack requested
        d.append(paste ? 1 : 0)
        let bytes = Array(s.utf8.prefix(200_000))
        d.appendBE(UInt32(bytes.count))
        d.append(contentsOf: bytes)
        return d
    }

    static func displayPower(_ on: Bool) -> Data {
        Data([MsgType.setDisplayPower.rawValue, on ? 1 : 0])
    }

    static func scanFile(_ path: String) -> Data {
        var d = Data([MsgType.scanFile.rawValue])
        let bytes = Array(path.utf8)
        d.appendBE(UInt32(bytes.count))
        d.append(contentsOf: bytes)
        return d
    }
}

/// Android keycodes we send.
enum AKey {
    static let home: Int32 = 3, back: Int32 = 4, dpadUp: Int32 = 19, dpadDown: Int32 = 20
    static let dpadLeft: Int32 = 21, dpadRight: Int32 = 22, volumeUp: Int32 = 24, volumeDown: Int32 = 25
    static let power: Int32 = 26, tab: Int32 = 61, enter: Int32 = 66, del: Int32 = 67
    static let pageUp: Int32 = 92, pageDown: Int32 = 93, escape: Int32 = 111, forwardDel: Int32 = 112
    static let moveHome: Int32 = 122, moveEnd: Int32 = 123, appSwitch: Int32 = 187
    static let a: Int32 = 29 // A..Z are 29..54
    static let metaCtrlOn: Int32 = 0x1000 | 0x2000
    static let metaShiftOn: Int32 = 0x1 | 0x40
    static let metaAltOn: Int32 = 0x2 | 0x10
}
