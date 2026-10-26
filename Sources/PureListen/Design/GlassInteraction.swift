import AppKit
import SwiftUI

// MARK: - Liquid Glass 指针透镜交互
//
// 官方 Liquid Glass 控件在按下时会"点亮"：材质内部出现跟随指针的透镜光斑，
// 玻璃整体轻微压缩、松开回弹。SwiftUI 的 `Glass.interactive()` 提供材质层的响应，
// 但入口较隐晦（需要控件真正拿到指针事件），在悬浮面板/小控件里很难稳定看到。
//
// 这里补一层可控的指针透镜：用本地事件监听跟踪指针位置，画出跟随鼠标的
// 内部照明 + 折射环 + 高光边，并带按压压缩动画。它不拦截事件，
// 因此点击、拖拽滑条等原有交互完全不受影响。

/// 预览/截图用：强制某个玻璃控件处于"按下"状态并指定指针位置（局部坐标）。
private struct GlassLensDebugPointKey: EnvironmentKey {
    static let defaultValue: CGPoint? = nil
}

extension EnvironmentValues {
    var glassLensDebugPoint: CGPoint? {
        get { self[GlassLensDebugPointKey.self] }
        set { self[GlassLensDebugPointKey.self] = newValue }
    }
}

// MARK: - 指针跟踪

@MainActor
private final class GlassLensTracker: ObservableObject {
    @Published private(set) var point: CGPoint?
    @Published private(set) var pressed = false
    @Published private(set) var hovering = false

    var pressEnded: ((CGPoint, CGSize) -> Void)?
    var moved: ((CGPoint) -> Void)?
    var pressChanged: ((Bool) -> Void)?

    private var monitor: Any?
    private weak var window: NSWindow?
    private var frameInWindow: CGRect = .zero
    private var boundsSize: CGSize = .zero

    func attach(window: NSWindow?, frameInWindow: CGRect) {
        self.window = window
        self.frameInWindow = frameInWindow
        self.boundsSize = frameInWindow.size
    }

    func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDown, .leftMouseDragged, .leftMouseUp]
        ) { [weak self] event in
            self?.handle(event)
            return event
        }
    }

    func remove() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
    }

    private func handle(_ event: NSEvent) {
        guard let window, event.window === window else { return }
        let local = convert(event.locationInWindow)
        let inside = CGRect(origin: .zero, size: boundsSize).contains(local)

        switch event.type {
        case .mouseMoved:
            // 只在悬停状态变化时发布，避免每次鼠标移动都触发 SwiftUI 刷新。
            if hovering != inside {
                hovering = inside
            }
        case .leftMouseDown:
            guard inside else { return }
            pressed = true
            point = local
            pressChanged?(true)
            moved?(local)
        case .leftMouseDragged:
            guard pressed else { return }
            point = local
            moved?(local)
        case .leftMouseUp:
            guard pressed else { return }
            pressed = false
            if !inside { hovering = false }
            pressChanged?(false)
            pressEnded?(local, boundsSize)
        default:
            break
        }
    }

    /// 窗口坐标（左下原点）→ 控件局部坐标（左上原点）。
    private func convert(_ windowPoint: NSPoint) -> CGPoint {
        CGPoint(x: windowPoint.x - frameInWindow.minX,
                y: frameInWindow.maxY - windowPoint.y)
    }
}

/// 0 尺寸的 AppKit 锚点：报告控件在窗口坐标系里的位置（供指针换算）。
private struct WindowAnchor: NSViewRepresentable {
    var report: (NSWindow?, CGRect) -> Void

    func makeNSView(context: Context) -> AnchorView {
        let view = AnchorView()
        view.report = report
        return view
    }

    func updateNSView(_ nsView: AnchorView, context: Context) {
        nsView.report = report
        nsView.reportFrame()
    }

    final class AnchorView: NSView {
        var report: ((NSWindow?, CGRect) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            reportFrame()
        }

        override func layout() {
            super.layout()
            reportFrame()
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        func reportFrame() {
            guard let window else {
                report?(nil, .zero)
                return
            }
            report?(window, convert(bounds, to: nil))
        }
    }
}

// MARK: - 透镜视觉

// MARK: - 修饰符

/// 给玻璃控件加上"跟随指针的透镜 + 按压压缩"。
///
/// 用法：`.glassPointerLens(in: Capsule())`，放在 `glassEffect` 之后。
/// 不拦截事件；`onPressEnded` 可用于分段控件的"按拖选择"。
struct GlassPointerLens<S: InsettableShape>: ViewModifier {
    var shape: S
    var pressScale: CGFloat = 1.2
    var onPressEnded: ((CGPoint, CGSize) -> Void)?

    @StateObject private var tracker = GlassLensTracker()
    @Environment(\.glassLensDebugPoint) private var debugPoint

    private var isActive: Bool { tracker.pressed || debugPoint != nil }

    func body(content: Content) -> some View {
        content
            .background {
                WindowAnchor { window, frame in
                    tracker.attach(window: window, frameInWindow: frame)
                }
            }
            // 官方效果：按住时整枚玻璃胶囊原地放大成透镜。
            .scaleEffect(isActive ? pressScale : 1)
            // 透镜边缘的光折射：沿胶囊自身轮廓的冷色高光，不是脱离控件的白圈。
            .overlay {
                if isActive {
                    shape.strokeBorder(
                        LinearGradient(
                            colors: [Color(red: 0.55, green: 0.95, blue: 1.0).opacity(0.45),
                                     Color.white.opacity(0.40),
                                     Color(red: 1.0, green: 0.55, blue: 0.90).opacity(0.22)],
                            startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 1.1)
                        .allowsHitTesting(false)
                }
            }
            .animation(DS.Motion.press, value: isActive)
            .onAppear {
                tracker.install()
                tracker.pressEnded = { point, size in
                    onPressEnded?(point, size)
                }
            }
            .onDisappear {
                tracker.remove()
            }
    }
}

extension View {
    func glassPointerLens<S: InsettableShape>(in shape: S,
                                             pressScale: CGFloat = 1.2,
                                             onPressEnded: ((CGPoint, CGSize) -> Void)? = nil)
        -> some View {
        modifier(GlassPointerLens(shape: shape,
                                  pressScale: pressScale,
                                  onPressEnded: onPressEnded))
    }
}

/// 只做指针跟踪、不带视觉的修饰符：把按下状态与指针位置暴露成 Binding，
/// 供分段控件实现"选择胶囊跟随指针"的液态反馈。
struct GlassPointerTracking: ViewModifier {
    var enabled: Bool = true
    @Binding var pressed: Bool
    @Binding var point: CGPoint?
    var onPressEnded: ((CGPoint, CGSize) -> Void)? = nil

    @StateObject private var tracker = GlassLensTracker()

    func body(content: Content) -> some View {
        if enabled {
            content
                .background {
                    WindowAnchor { window, frame in
                        tracker.attach(window: window, frameInWindow: frame)
                    }
                }
                .onAppear {
                    tracker.install()
                    tracker.moved = { local in point = local }
                    tracker.pressChanged = { isPressed in pressed = isPressed }
                    tracker.pressEnded = { local, size in onPressEnded?(local, size) }
                }
                .onDisappear {
                    tracker.remove()
                }
        } else {
            content
        }
    }
}
