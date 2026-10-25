import AppKit
import Combine
import SwiftUI
import PureListenCore

// 净听 PureListen: 菜单栏应用, 网易云音乐无损独占输出到 3.5mm 耳机孔。
// 不进 Dock, 常驻菜单栏。界面视觉遵循 macOS 27 Golden Gate: Liquid Glass、同心圆角、单一音乐色。

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var statusBar: NSStatusItem!
    var popover: NSPopover!
    let state = AppState()

    private var cancellables = Set<AnyCancellable>()
    private var biliWebLoginWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        let rootView = ContentView().environmentObject(state)
        let hosting = NSHostingController(rootView: rootView)
        hosting.preferredContentSize = NSSize(width: DS.Size.popoverWidth,
                                              height: DS.Size.popoverHeight)
        popover.contentViewController = hosting
        // 顺序很重要: 先挂 contentViewController, 再定 contentSize, 否则 NSPopover 会按
        // SwiftUI 内容的理想尺寸撑大自己。
        popover.contentSize = NSSize(width: DS.Size.popoverWidth, height: DS.Size.popoverHeight)

        statusBar = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusBar.button {
            button.image = StatusItemIcon.image(playing: false)
            button.imagePosition = .imageOnly
            button.action = #selector(statusItemClicked(_:))
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = "净听"
        }

        state.onOpenNowPlaying = { [weak self] in
            guard let self else { return }
            self.popover.performClose(nil)
            NowPlayingWindowController.shared.show(state: self.state)
        }
        state.onOpenBiliWebLogin = { [weak self] in
            self?.openBiliWebLoginWindow()
        }

        // 播放状态变化时同步菜单栏图标(播放时声波弧度略大)。
        state.$playerState
            .receive(on: RunLoop.main)
            .sink { [weak self] playerState in
                guard let self, let button = self.statusBar.button else { return }
                let playing: Bool = {
                    if case .playing = playerState { return true }
                    return false
                }()
                button.image = StatusItemIcon.image(playing: playing)
            }
            .store(in: &cancellables)

        Task { await state.restoreSession() }
    }

    func openBiliWebLoginWindow() {
        popover.performClose(nil)
        if let window = biliWebLoginWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let hosting = NSHostingController(rootView: BiliWebLoginView().environmentObject(state))
        let window = NSWindow(contentViewController: hosting)
        window.title = "哔哩哔哩 · 网页登录"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable,
                            .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.setContentSize(NSSize(width: 560, height: 720))
        window.minSize = NSSize(width: 480, height: 560)
        window.isReleasedWhenClosed = false
        window.center()
        biliWebLoginWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        state.shutdown()
    }

    // MARK: - 菜单栏交互

    @objc func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp {
            showContextMenu()
            return
        }
        togglePopover(sender)
    }

    private func showContextMenu() {
        guard let button = statusBar.button else { return }
        let menu = NSMenu()
        menu.autoenablesItems = false

        // 正在播放摘要(不可点, 只作为上下文)
        if !state.trackStatus.title.isEmpty {
            let title = state.trackStatus.title
            let artist = state.trackStatus.artist
            let header = NSMenuItem(title: artist.isEmpty ? title : "\(title) — \(artist)",
                                    action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)
            menu.addItem(.separator())
        }

        let isPlaying: Bool = {
            if case .playing = state.playerState { return true }
            return false
        }()
        menu.addItem(withTitle: isPlaying ? "暂停" : "播放",
                     action: #selector(menuTogglePlayPause), keyEquivalent: "").target = self
        menu.addItem(withTitle: "下一首", action: #selector(menuNext), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "正在播放窗口…", action: #selector(menuOpenWindow),
                     keyEquivalent: "").target = self
        menu.addItem(withTitle: "设置…", action: #selector(menuOpenSettings),
                     keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出净听", action: #selector(menuQuit),
                     keyEquivalent: "q").target = self

        menu.popUp(positioning: nil,
                   at: NSPoint(x: 0, y: button.bounds.minY - 4),
                   in: button)
    }

    @objc private func menuTogglePlayPause() { state.playPause() }
    @objc private func menuNext() { state.playNext() }

    @objc private func menuOpenWindow() {
        NowPlayingWindowController.shared.show(state: state)
    }

    @objc private func menuOpenSettings() {
        NowPlayingWindowController.shared.show(state: state, section: .settings)
    }

    @objc private func menuQuit() {
        NSApp.terminate(nil)
    }

    // MARK: - Popover

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

// MARK: - 菜单栏图标

/// 菜单栏模板图标: 用品牌标记渲染成单色 template image, 菜单栏自动适配浅/深色。
enum StatusItemIcon {
    static func image(playing: Bool) -> NSImage {
        let size = NSSize(width: 17, height: 17)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.black.setStroke()
            NSColor.black.setFill()

            let center = CGPoint(x: rect.midX, y: rect.midY)
            let radius = min(rect.width, rect.height) / 2

            // 外圈: 一张唱片, 右上留一道约 22° 的开口; 播放时略微加粗。
            let ringWidth: CGFloat = playing ? 2.0 : 1.8
            let ringRadius = radius - ringWidth / 2 - 0.5
            let ring = NSBezierPath()
            ring.lineWidth = ringWidth
            ring.lineCapStyle = .round
            ring.appendArc(withCenter: center, radius: ringRadius,
                           startAngle: 314, endAngle: 654, clockwise: false)
            ring.stroke()

            // 中心点: 唱针落点。
            let dotRadius: CGFloat = playing ? 1.85 : 1.75
            NSBezierPath(ovalIn: NSRect(x: center.x - dotRadius, y: center.y - dotRadius,
                                        width: dotRadius * 2, height: dotRadius * 2)).fill()
            return true
        }
        image.isTemplate = true
        return image
    }
}
