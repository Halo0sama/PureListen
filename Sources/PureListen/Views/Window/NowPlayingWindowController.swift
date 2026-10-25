import AppKit
import SwiftUI
import PureListenCore

// MARK: - 分区

/// 「正在播放」窗口的分区。
enum NowPlayingSection: Hashable, CaseIterable {
    case nowPlaying
    case lyrics
    case signal
    case settings

    var title: String {
        switch self {
        case .nowPlaying: return "正在播放"
        case .lyrics: return "歌词"
        case .signal: return "播放链路"
        case .settings: return "设置"
        }
    }

    /// 侧边栏使用的 SF Symbol(单色、hierarchical, 选中时染音乐色)。
    var symbol: String {
        switch self {
        case .nowPlaying: return "play.square"
        case .lyrics: return "quote.bubble"
        case .signal: return "waveform"
        case .settings: return "gearshape"
        }
    }
}

// MARK: - 路由

/// 窗口内部的分区路由。窗口控制器持有唯一实例, 侧边栏与内容区共享。
@MainActor
final class WindowRouter: ObservableObject {
    @Published private(set) var section: NowPlayingSection

    init(section: NowPlayingSection = .nowPlaying) {
        self.section = section
    }

    func select(_ section: NowPlayingSection, animated: Bool = true) {
        guard section != self.section else { return }
        if animated {
            withAnimation(DS.Motion.page) { self.section = section }
        } else {
            self.section = section
        }
    }
}

// MARK: - 窗口控制器

/// 「正在播放」独立窗口: 真实 NSWindow + 全尺寸内容, chrome 由 SwiftUI 自己绘制。
@MainActor
final class NowPlayingWindowController: NSObject, NSWindowDelegate {
    static let shared = NowPlayingWindowController()

    private var window: NSWindow?
    private let router = WindowRouter()

    /// 打开(或聚焦)播放窗口; `section` 可指定落地分区。
    func show(state: AppState, section: NowPlayingSection = .nowPlaying) {
        if let window {
            router.select(section)
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let root = NowPlayingWindowView(router: router).environmentObject(state)
        let hosting = NSHostingController(rootView: root)
        hosting.view.wantsLayer = true

        let window = NSWindow(contentViewController: hosting)
        window.title = "净听"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.titlebarSeparatorStyle = .none
        window.toolbarStyle = .unified
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.collectionBehavior = [.fullScreenPrimary]
        window.setContentSize(NSSize(width: DS.Size.windowWidth, height: DS.Size.windowHeight))
        window.minSize = NSSize(width: 820, height: 560)
        window.delegate = self

        // 记住上次的位置与尺寸; 第一次打开时居中。
        let autosaveName = "PureListenNowPlayingWindow"
        if !window.setFrameUsingName(autosaveName) {
            window.center()
        }
        window.setFrameAutosaveName(autosaveName)

        router.select(section, animated: false)
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        // 窗口对象与 SwiftUI 状态保留, 再次打开时直接复用(避免重新加载封面与滚动位置)。
        NCLog.log("[窗口] 正在播放窗口关闭")
    }
}
