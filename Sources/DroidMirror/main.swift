import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSMenuItemValidation {
    private let model = AppModel.shared
    private var devicesWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Pref.registerDefaults()
        buildMenu()
        buildStatusItem()
        model.startRefreshing()
        showDevices()
        model.autoConnect()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            if model.isMirroring { model.showMirrorWindow() } else { showDevices() }
        }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationWillTerminate(_ notification: Notification) {
        model.disconnect()
    }

    // MARK: Windows

    @objc func showDevices() {
        if devicesWindow == nil {
            let w = NSWindow(contentRect: .zero, styleMask: [.titled, .closable, .miniaturizable],
                             backing: .buffered, defer: false)
            w.title = "DroidMirror"
            w.contentView = NSHostingView(rootView: DevicesView(model: model))
            w.isReleasedWhenClosed = false
            w.center()
            devicesWindow = w
        }
        devicesWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func showSettings() {
        if settingsWindow == nil {
            let w = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
            w.title = "DroidMirror Settings"
            w.contentView = NSHostingView(rootView: SettingsView())
            w.isReleasedWhenClosed = false
            w.center()
            settingsWindow = w
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func showPhone() {
        if model.session != nil { model.showMirrorWindow() } else { showDevices() }
    }

    @objc func disconnect() { model.disconnect() }

    // MARK: Phone menu actions

    @objc func back() { model.back() }
    @objc func home() { model.home() }
    @objc func recents() { model.recents() }
    @objc func notifications() { model.notifications() }
    @objc func quickSettings() { model.quickSettings() }
    @objc func rotate() { model.rotate() }
    @objc func toggleScreen() { model.togglePhoneScreen() }
    @objc func volumeUp() { model.volumeUp() }
    @objc func volumeDown() { model.volumeDown() }
    @objc func power() { model.power() }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if item.tag == 1 { return model.isMirroring }
        if item.action == #selector(disconnect) { return model.session != nil }
        return true
    }

    // MARK: Menus

    private func item(_ title: String, _ action: Selector, _ key: String = "",
                      _ mods: NSEvent.ModifierFlags = .command, phone: Bool = false) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.keyEquivalentModifierMask = mods
        i.target = self
        if phone { i.tag = 1 }
        return i
    }

    private func buildMenu() {
        let main = NSMenu()

        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About DroidMirror", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(item("Settings…", #selector(showSettings), ","))
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide DroidMirror", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = appMenu.addItem(withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit DroidMirror", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        main.addItem(withTitle: "", action: nil, keyEquivalent: "").submenu = appMenu

        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(item("Phones…", #selector(showDevices), "d", [.command, .shift]))
        fileMenu.addItem(item("Show Phone", #selector(showPhone), "1"))
        fileMenu.addItem(item("Disconnect", #selector(disconnect), "w", [.command, .shift]))
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        main.addItem(withTitle: "File", action: nil, keyEquivalent: "").submenu = fileMenu

        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        main.addItem(withTitle: "Edit", action: nil, keyEquivalent: "").submenu = editMenu

        let phoneMenu = NSMenu(title: "Phone")
        phoneMenu.addItem(item("Back", #selector(back), "b", phone: true))
        phoneMenu.addItem(item("Home", #selector(home), "h", [.command, .shift], phone: true))
        phoneMenu.addItem(item("Recent Apps", #selector(recents), "a", [.command, .shift], phone: true))
        phoneMenu.addItem(.separator())
        phoneMenu.addItem(item("Notifications", #selector(notifications), "n", [.command, .shift], phone: true))
        phoneMenu.addItem(item("Quick Settings", #selector(quickSettings), "s", [.command, .shift], phone: true))
        phoneMenu.addItem(.separator())
        phoneMenu.addItem(item("Rotate", #selector(rotate), "r", phone: true))
        phoneMenu.addItem(item("Turn Phone Screen Off/On", #selector(toggleScreen), "o", [.command, .shift], phone: true))
        phoneMenu.addItem(item("Volume Up", #selector(volumeUp), String(Character(UnicodeScalar(NSUpArrowFunctionKey)!)), phone: true))
        phoneMenu.addItem(item("Volume Down", #selector(volumeDown), String(Character(UnicodeScalar(NSDownArrowFunctionKey)!)), phone: true))
        phoneMenu.addItem(item("Power Button", #selector(power), "p", phone: true))
        main.addItem(withTitle: "Phone", action: nil, keyEquivalent: "").submenu = phoneMenu

        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        main.addItem(withTitle: "Window", action: nil, keyEquivalent: "").submenu = windowMenu
        NSApp.windowsMenu = windowMenu

        NSApp.mainMenu = main
    }

    private func buildStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "iphone.gen3", accessibilityDescription: "DroidMirror")
            ?? NSImage(systemSymbolName: "iphone", accessibilityDescription: "DroidMirror")
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === statusItem?.menu else { return }
        menu.removeAllItems()
        let status: String
        switch model.status {
        case .idle: status = "Not connected"
        case .connecting(let n): status = "Connecting to \(n)…"
        case .mirroring(let n): status = "Mirroring \(n)"
        case .error(let e): status = e
        }
        let header = NSMenuItem(title: status, action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())
        menu.addItem(item("Show Phone", #selector(showPhone)))
        menu.addItem(item("Phones…", #selector(showDevices)))
        if model.session != nil { menu.addItem(item("Disconnect", #selector(disconnect))) }
        menu.addItem(.separator())
        menu.addItem(item("Settings…", #selector(showSettings)))
        menu.addItem(withTitle: "Quit DroidMirror", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
