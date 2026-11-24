import AppKit
import SwiftUI

/// Phone-shaped window: a slim draggable bar with controls on top, the phone screen below.
final class MirrorWindowController: NSWindowController, NSWindowDelegate {
    static let barHeight: CGFloat = 34
    static let bezel: CGFloat = 6

    private let model: AppModel
    private let mirrorView: MirrorView
    private var videoAspect: CGFloat = 9.0 / 19.5 // width / height, until the phone reports its size

    init(model: AppModel) {
        self.model = model
        mirrorView = MirrorView(model: model)

        let height: CGFloat = min(760, (NSScreen.main?.visibleFrame.height ?? 900) - 80)
        let size = MirrorWindowController.windowSize(forScreenHeight: height - Self.barHeight - Self.bezel,
                                                     aspect: 9.0 / 19.5)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.title = "DroidMirror"
        window.backgroundColor = NSColor(white: 0.08, alpha: 1)
        window.isMovableByWindowBackground = false
        window.collectionBehavior = [.fullScreenNone]
        window.setFrameAutosaveName("DroidMirrorWindow")
        window.minSize = NSSize(width: 200, height: 360)
        if !window.setFrameUsingName("DroidMirrorWindow") { window.center() }
        super.init(window: window)
        window.delegate = self

        let root = NSView()
        root.wantsLayer = true

        let bar = NSHostingView(rootView: MirrorBar(model: model))
        bar.translatesAutoresizingMaskIntoConstraints = false
        mirrorView.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(mirrorView)
        root.addSubview(bar)
        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: root.topAnchor),
            bar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            bar.heightAnchor.constraint(equalToConstant: Self.barHeight),
            mirrorView.topAnchor.constraint(equalTo: bar.bottomAnchor),
            mirrorView.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: Self.bezel),
            mirrorView.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -Self.bezel),
            mirrorView.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -Self.bezel),
        ])
        window.contentView = root
        window.makeFirstResponder(mirrorView)
    }

    required init?(coder: NSCoder) { fatalError() }

    private static func windowSize(forScreenHeight h: CGFloat, aspect: CGFloat) -> NSSize {
        NSSize(width: (h * aspect).rounded() + 2 * bezel, height: h + barHeight + bezel)
    }

    func videoSizeChanged(width: Int, height: Int) {
        guard width > 0, height > 0, let window else { return }
        let newAspect = CGFloat(width) / CGFloat(height)
        let rotated = (newAspect > 1) != (videoAspect > 1)
        videoAspect = newAspect

        let frame = window.frame
        let content = window.contentRect(forFrameRect: frame)
        let visible = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? frame
        var screenH = content.height - Self.barHeight - Self.bezel
        if rotated {
            // Keep the long side about the same when the phone rotates.
            let longSide = max(content.width - 2 * Self.bezel, screenH)
            screenH = newAspect > 1 ? longSide / newAspect : longSide
        }
        var size = Self.windowSize(forScreenHeight: screenH, aspect: newAspect)
        if size.width > visible.width || size.height > visible.height {
            let s = min(visible.width / size.width, visible.height / size.height) * 0.95
            size = Self.windowSize(forScreenHeight: screenH * s, aspect: newAspect)
        }
        var newContent = NSRect(x: content.minX, y: content.maxY - size.height, width: size.width, height: size.height)
        if newContent.minY < visible.minY { newContent.origin.y = visible.minY }
        if newContent.maxX > visible.maxX { newContent.origin.x = visible.maxX - newContent.width }
        window.setFrame(window.frameRect(forContentRect: newContent), display: true, animate: true)
    }

    // Keep the phone's aspect ratio while resizing.
    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        let content = sender.contentRect(forFrameRect: NSRect(origin: .zero, size: frameSize))
        let screenW = max(100, content.width - 2 * Self.bezel)
        let size = NSSize(width: content.width, height: (screenW / videoAspect).rounded() + Self.barHeight + Self.bezel)
        return sender.frameRect(forContentRect: NSRect(origin: .zero, size: size)).size
    }

    func windowWillClose(_ notification: Notification) {
        model.disconnect(closeWindow: false)
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.makeFirstResponder(mirrorView)
    }
}

/// Top bar: device name or status on the left (after the window buttons), phone controls on the right.
struct MirrorBar: View {
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(spacing: 2) {
            Spacer().frame(width: 72)
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.85))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 4)
            if model.isMirroring {
                barButton("chevron.backward", "Back (Esc or right-click)") { model.back() }
                barButton("circle", "Home (⇧⌘H)") { model.home() }
                barButton("square.on.square", "Recent apps (⇧⌘A)") { model.recents() }
                barButton(model.phoneScreenOff ? "iphone.slash" : "iphone",
                          model.phoneScreenOff ? "Turn phone screen on" : "Turn phone screen off") {
                    model.togglePhoneScreen()
                }
                Menu {
                    Button("Notifications") { model.notifications() }
                    Button("Quick Settings") { model.quickSettings() }
                    Divider()
                    Button("Rotate") { model.rotate() }
                    Button("Volume Up") { model.volumeUp() }
                    Button("Volume Down") { model.volumeDown() }
                    Button("Power Button") { model.power() }
                    Divider()
                    Button("Disconnect") { model.disconnect() }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .foregroundColor(.white.opacity(0.85))
                .padding(.horizontal, 4)
            }
        }
        .padding(.trailing, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WindowDragArea())
        .background(Color(white: 0.08))
    }

    private var title: String {
        if let busy = model.busy { return busy }
        if let toast = model.toast { return toast }
        switch model.status {
        case .idle: return "Not connected"
        case .connecting(let n): return "Connecting to \(n)…"
        case .mirroring(let n): return n
        case .error(let e): return e
        }
    }

    private func barButton(_ symbol: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 24, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundColor(.white.opacity(0.85))
        .help(help)
    }
}

/// Empty area that moves the window when dragged (the bar has no real title bar under it).
struct WindowDragArea: NSViewRepresentable {
    final class DragView: NSView {
        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
    }

    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
