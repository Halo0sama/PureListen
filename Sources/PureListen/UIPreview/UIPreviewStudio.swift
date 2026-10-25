#if DEBUG
import AppKit
import SwiftUI
import IOKit.pwr_mgt
import PureListenCore

/// 无音频 UI 预览工作室(Debug 专用)。
///
/// 用法:
/// ```
/// swift build
/// .build/debug/PureListen --ui-studio --out docs/design/screens
/// ```
///
/// 它不会碰任何音频设备: `AppState` 以 `previewMode` 构造, 不枚举音频、不启轮询、不联网。
/// 每个场景会被放进真实的 NSPopover / NSWindow 里渲染, 再由 `screencapture -l` 抓取,
/// 因此 Liquid Glass、材质、阴影都是真实系统渲染结果(而不是 ImageRenderer 的降级画面)。
@MainActor
enum UIPreviewStudio {

    // MARK: - 入口

    static var isRequested: Bool {
        CommandLine.arguments.contains("--ui-studio")
    }

    static func run() {
        let args = CommandLine.arguments
        let outDir = value(for: "--out", in: args) ?? "docs/design/screens"
        let only = value(for: "--only", in: args)
        let schemeArg = value(for: "--scheme", in: args) ?? "both"

        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        // 截图期间禁止显示器休眠, 否则 screencapture 会拿不到窗口内容。
        var assertionID: IOPMAssertionID = 0
        IOPMAssertionCreateWithName(kIOPMAssertionTypeNoDisplaySleep as CFString,
                                    IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                    "PureListen UI Studio" as CFString,
                                    &assertionID)


        PreviewArtwork.activate()

        let schemes: [PreviewScheme] = switch schemeArg {
        case "light": [.light]
        case "dark": [.dark]
        default: [.dark, .light]
        }

        let outputURL = URL(fileURLWithPath: outDir, isDirectory: true)
        try? FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)

        Task { @MainActor in
            // 给 AppKit 一点时间完成首次布局。
            try? await Task.sleep(nanoseconds: 300_000_000)

            var index = 0
            for scheme in schemes {
                NSApp.appearance = NSAppearance(named: scheme.appearanceName)
                for scene in UIPreviewCatalog.scenes() {
                    if let only, !scene.name.contains(only) { continue }
                    index += 1
                    await render(scene: scene, scheme: scheme, into: outputURL)
                }
            }
            print("[ui-studio] 完成 \(index) 张截图 → \(outputURL.path)")
            IOPMAssertionRelease(assertionID)
            NSApp.terminate(nil)
        }

        app.run()
    }

    private static func value(for flag: String, in args: [String]) -> String? {
        guard let i = args.firstIndex(of: flag), args.indices.contains(i + 1) else { return nil }
        return args[i + 1]
    }

    // MARK: - 单个场景渲染

    private static func render(scene: UIPreviewScene, scheme: PreviewScheme, into dir: URL) async {
        let state = UIPreviewData.makeState()
        scene.configure(state)

        let container = AnyView(
            scene.makeView()
                .environmentObject(state)
                .environment(\.controlActiveState, .key)
        )

        switch scene.presentation {
        case let .popover(size):
            await renderPopover(container, size: size, scene: scene, scheme: scheme, into: dir,
                                state: state)
        case let .window(config):
            await renderWindow(container, config: config, scene: scene, scheme: scheme, into: dir)
        }
    }

    private static func renderPopover(_ view: AnyView, size: CGSize, scene: UIPreviewScene,
                                      scheme: PreviewScheme, into dir: URL, state: AppState) async {
        // 用一枚 1pt 的透明锚点窗口承载 popover, 避免在菜单栏里留下真实状态栏图标。
        let anchor = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1, height: 1),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        anchor.isOpaque = false
        anchor.backgroundColor = .clear
        anchor.alphaValue = 0.01
        anchor.setFrameOrigin(scene.anchor ?? NSPoint(x: 1040, y: 792))

        let host = NSHostingView(rootView: view)
        host.frame = NSRect(origin: .zero, size: size)

        anchor.contentView = host
        anchor.orderFrontRegardless()

        let popover = NSPopover()
        popover.behavior = .applicationDefined
        popover.animates = false
        popover.contentSize = size
        popover.contentViewController = NSHostingController(rootView: view)

        popover.show(relativeTo: NSRect(x: 0, y: 0, width: 1, height: 1), of: host, preferredEdge: .minY)
        await settle(seconds: scene.settleTime)

        if let window = popover.contentViewController?.view.window {
            window.level = .statusBar
            window.orderFrontRegardless()
            print("[ui-studio] popover window #\(window.windowNumber) visible=\(window.isVisible) frame=\(window.frame) shown=\(popover.isShown)")
            let name = "\(scene.name)-\(scheme.suffix)"
            await capture(window: window, name: name, into: dir, shadow: scene.withShadow)
        } else {
            print("[ui-studio] ⚠︎ popover window 缺失: \(scene.name)")
        }

        popover.performClose(nil)
        anchor.orderOut(nil)
        await settle(seconds: 0.12)
    }

    private static func renderWindow(_ view: AnyView, config: PreviewWindowConfig,
                                     scene: UIPreviewScene, scheme: PreviewScheme, into dir: URL) async {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: config.size),
                              styleMask: config.styleMask,
                              backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = config.transparentTitlebar
        window.titleVisibility = config.transparentTitlebar ? .hidden : .visible
        window.title = config.title
        window.isOpaque = config.opaque
        window.backgroundColor = config.opaque ? .windowBackgroundColor : .clear
        window.hasShadow = scene.withShadow
        window.contentView = NSHostingView(rootView: view)
        window.center()
        window.level = .floating
        window.orderFrontRegardless()

        await settle(seconds: scene.settleTime)

        let name = "\(scene.name)-\(scheme.suffix)"
        await capture(window: window, name: name, into: dir, shadow: scene.withShadow)

        window.orderOut(nil)
        await settle(seconds: 0.12)
    }

    // MARK: - 截图

    /// 让 AppKit 控件进入 active 外观。只调用 activate, 不改 activation policy
    /// (在 macOS 27 上把未打包的 SwiftPM 可执行文件切成 regular 会崩在 MenuBarClientCore)。
    private static func wakeControls(for window: NSWindow) {
        // 激活 App 在 macOS 27 + 未打包的 SwiftPM 可执行文件上不可靠(会 hang 或崩在
        // MenuBarClientCore), 所以截图不依赖激活: SwiftUI 控件通过 controlActiveState
        // 注入 active 外观, 自绘控件(DSSwitch 等)不依赖窗口状态。
        _ = window
    }

    private static func capture(window: NSWindow, name: String, into dir: URL, shadow: Bool) async {
        wakeControls(for: window)
        await settle(seconds: 0.12)
        window.displayIfNeeded()
        let path = dir.appendingPathComponent("\(name).png")
        try? FileManager.default.removeItem(at: path)

        // 窗口被其他 App 盖住时 screencapture 可能拿不到内容, 重试几次。
        for attempt in 1...3 {
            window.orderFrontRegardless()
            wakeControls(for: window)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            // 一律不带阴影: 否则窗口阴影会把桌面/其它 App 的窗口内容一起拍进来。
            var args = ["-x", "-l", "\(window.windowNumber)", "-o"]
            args.append(path.path)
            process.arguments = args
            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                print("[ui-studio] ⚠︎ screencapture 失败: \(error)")
                return
            }
            if FileManager.default.fileExists(atPath: path.path) {
                print("[ui-studio] ✓ \(name).png")
                return
            }
            print("[ui-studio] ↻ 第 \(attempt) 次截图失败, 重试: \(name)")
            await settle(seconds: 0.25)
        }
        print("[ui-studio] ⚠︎ 未生成: \(name).png")
    }

    private static func settle(seconds: TimeInterval) async {
        try? await Task.sleep(nanoseconds: UInt64(max(seconds, 0.01) * 1_000_000_000))
    }
}

// MARK: - 场景描述

enum PreviewScheme {
    case light
    case dark

    var appearanceName: NSAppearance.Name {
        switch self {
        case .light: return .aqua
        case .dark: return .darkAqua
        }
    }

    var suffix: String {
        switch self {
        case .light: return "light"
        case .dark: return "dark"
        }
    }
}

enum PreviewPresentation {
    /// 菜单栏 popover(真实 NSPopover, 含系统圆角与箭头)。
    case popover(size: CGSize)
    /// 独立窗口。
    case window(PreviewWindowConfig)
}

struct PreviewWindowConfig {
    var size: CGSize
    var title: String = "净听"
    var styleMask: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable,
                                         .fullSizeContentView]
    var transparentTitlebar: Bool = true
    var opaque: Bool = false
}

struct UIPreviewScene {
    var name: String
    var presentation: PreviewPresentation
    var settleTime: TimeInterval = 0.75
    var withShadow: Bool = true
    /// popover 锚点(屏幕坐标, 左下角原点)。
    var anchor: NSPoint?
    var configure: (AppState) -> Void
    var makeView: () -> AnyView
}
#endif
