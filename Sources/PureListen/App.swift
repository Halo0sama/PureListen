import AppKit
import SwiftUI
import PureListenCore

// 净听 PureListen: 菜单栏应用, 网易云音乐无损独占输出到 3.5mm 耳机孔。
// 不进 Dock, 常驻菜单栏。

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var statusBar: NSStatusItem!
    var popover: NSPopover!
    let state = AppState()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        popover = NSPopover()
        popover.contentSize = NSSize(width: 360, height: 560)
        popover.behavior = .transient
        popover.animates = true
        let rootView = ContentView().environmentObject(state)
        popover.contentViewController = NSHostingController(rootView: rootView)

        statusBar = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusBar.button {
            button.image = NSImage(systemSymbolName: "headphones", accessibilityDescription: "净听")
            button.action = #selector(togglePopover(_:))
            button.target = self
        }

        state.onOpenBiliWebLogin = { [weak self] in
            self?.openBiliWebLoginWindow()
        }
        Task { await state.restoreSession() }
    }

    private var biliWebLoginWindow: NSWindow?

    func openBiliWebLoginWindow() {
        if let window = biliWebLoginWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let hosting = NSHostingController(rootView: BiliWebLoginView().environmentObject(state))
        let window = NSWindow(contentViewController: hosting)
        window.title = "净听 · B站登录"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 520, height: 680))
        window.center()
        window.isReleasedWhenClosed = false
        biliWebLoginWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        state.shutdown()
    }

    @objc func togglePopover(_ sender: NSStatusBarButton) {
        guard let button = statusBar.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}
