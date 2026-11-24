import AppKit

/// Shows the phone screen and turns mouse, trackpad and keyboard input into touches and key events.
final class MirrorView: NSView {
    private let model: AppModel
    private var touching = false

    init(model: AppModel) {
        self.model = model
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.cornerRadius = 16
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        layer?.addSublayer(model.renderer.layer)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        model.renderer.layer.frame = bounds
        CATransaction.commit()
    }

    // MARK: Coordinates

    private var videoSize: (Int, Int)? {
        guard let s = model.session, s.videoWidth > 0, s.videoHeight > 0 else { return nil }
        return (s.videoWidth, s.videoHeight)
    }

    /// Rect of the video inside the view (aspect fit).
    private func videoRect(_ w: Int, _ h: Int) -> CGRect {
        let b = bounds
        let scale = min(b.width / CGFloat(w), b.height / CGFloat(h))
        let size = CGSize(width: CGFloat(w) * scale, height: CGFloat(h) * scale)
        return CGRect(x: b.midX - size.width / 2, y: b.midY - size.height / 2, width: size.width, height: size.height)
    }

    private func devicePoint(_ event: NSEvent) -> (Int32, Int32, UInt16, UInt16)? {
        guard let (w, h) = videoSize else { return nil }
        let p = convert(event.locationInWindow, from: nil)
        let r = videoRect(w, h)
        let fx = max(0, min(1, (p.x - r.minX) / r.width))
        let fy = max(0, min(1, (r.maxY - p.y) / r.height))
        return (Int32(fx * CGFloat(w - 1)), Int32(fy * CGFloat(h - 1)), UInt16(w), UInt16(h))
    }

    // MARK: Mouse → touch

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        guard let (x, y, w, h) = devicePoint(event) else { return }
        touching = true
        model.send(Control.touch(.down, x: x, y: y, width: w, height: h))
    }

    override func mouseDragged(with event: NSEvent) {
        guard touching, let (x, y, w, h) = devicePoint(event) else { return }
        model.send(Control.touch(.move, x: x, y: y, width: w, height: h))
    }

    override func mouseUp(with event: NSEvent) {
        guard touching else { return }
        touching = false
        guard let (x, y, w, h) = devicePoint(event) else { return }
        model.send(Control.touch(.up, x: x, y: y, width: w, height: h))
    }

    override func rightMouseDown(with event: NSEvent) { model.send(Control.backOrScreenOn(.down)) }
    override func rightMouseUp(with event: NSEvent) { model.send(Control.backOrScreenOn(.up)) }

    override func otherMouseDown(with event: NSEvent) {
        if event.buttonNumber == 2 { model.send(Control.keycode(.down, AKey.home)) }
    }

    override func otherMouseUp(with event: NSEvent) {
        if event.buttonNumber == 2 { model.send(Control.keycode(.up, AKey.home)) }
    }

    override func scrollWheel(with event: NSEvent) {
        guard let (x, y, w, h) = devicePoint(event) else { return }
        var dx = Float(event.scrollingDeltaX)
        var dy = Float(event.scrollingDeltaY)
        if event.hasPreciseScrollingDeltas {
            dx /= 10
            dy /= 10
        }
        guard dx != 0 || dy != 0 else { return }
        model.send(Control.scroll(x: x, y: y, width: w, height: h, h: -dx, v: dy))
    }

    // MARK: Keyboard

    private static let specialKeys: [UInt16: Int32] = [
        36: AKey.enter, 76: AKey.enter, 51: AKey.del, 117: AKey.forwardDel, 48: AKey.tab,
        53: AKey.back, 123: AKey.dpadLeft, 124: AKey.dpadRight, 125: AKey.dpadDown, 126: AKey.dpadUp,
        115: AKey.moveHome, 119: AKey.moveEnd, 116: AKey.pageUp, 121: AKey.pageDown,
    ]

    private func meta(_ flags: NSEvent.ModifierFlags) -> Int32 {
        var m: Int32 = 0
        if flags.contains(.shift) { m |= AKey.metaShiftOn }
        if flags.contains(.control) { m |= AKey.metaCtrlOn }
        if flags.contains(.option) { m |= AKey.metaAltOn }
        return m
    }

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags
        if flags.contains(.command) {
            super.keyDown(with: event)
            return
        }
        if let code = MirrorView.specialKeys[event.keyCode] {
            model.send(Control.keycode(.down, code, repeatCount: event.isARepeat ? 1 : 0, meta: meta(flags)))
            return
        }
        if flags.contains(.control),
           let c = event.charactersIgnoringModifiers?.lowercased().unicodeScalars.first,
           c.value >= 97, c.value <= 122 {
            let code = AKey.a + Int32(c.value - 97)
            model.send(Control.keycode(.down, code, meta: meta(flags)))
            model.send(Control.keycode(.up, code, meta: meta(flags)))
            return
        }
        if let text = event.characters, !text.isEmpty,
           text.unicodeScalars.allSatisfy({ $0.value >= 32 && $0.value != 127 && !(0xF700...0xF8FF).contains($0.value) }) {
            model.send(Control.text(text))
        }
    }

    override func keyUp(with event: NSEvent) {
        if let code = MirrorView.specialKeys[event.keyCode], !event.modifierFlags.contains(.command) {
            model.send(Control.keycode(.up, code, meta: meta(event.modifierFlags)))
        }
    }

    // Standard Edit menu actions, routed to the phone while the mirror has focus.
    @objc func paste(_ sender: Any?) { model.pasteFromMac() }
    @objc func copy(_ sender: Any?) { model.copyFromPhone(cut: false) }
    @objc func cut(_ sender: Any?) { model.copyFromPhone(cut: true) }
    @objc func selectAll(_ sender: Any?) {
        model.send(Control.keycode(.down, AKey.a, meta: AKey.metaCtrlOn))
        model.send(Control.keycode(.up, AKey.a, meta: AKey.metaCtrlOn))
    }

    // MARK: Drag and drop

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        model.isMirroring ? .copy : []
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self],
                                                         options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        guard !urls.isEmpty else { return false }
        model.sendFiles(urls)
        return true
    }
}
