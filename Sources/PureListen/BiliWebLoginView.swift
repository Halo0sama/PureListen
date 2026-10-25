import SwiftUI
import WebKit
import PureListenCore

// MARK: - 哔哩哔哩网页登录窗口
//
// 真浏览器引擎加载登录页(扫码/账密均可), SESSDATA 出现在 Cookie 存储即登录成功;
// 也可点「完成」立即收割当前 Cookie。
//
// 560×720, 玻璃标题栏 + 圆角网页卡片。Cookie 收割逻辑与旧版保持一致。

struct BiliWebLoginView: View {
    @EnvironmentObject var state: AppState

    /// 仅 DEBUG 截图: 用本地占位页替代真实站点, 不联网。
    var previewMode: Bool = false

    @StateObject private var box = BiliWebBox()
    @State private var windowBox = BiliWindowBox()
    @State private var hint: String?

    var body: some View {
        AlbumTintProvider(url: state.currentCoverURL, intensity: 0.8) {
            VStack(spacing: 0) {
                toolbar
                webCard
                    .padding(.horizontal, DS.Space.l)
                    .padding(.top, DS.Space.m)
                    .padding(.bottom, DS.Space.l)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // 让玻璃工具条与窗口红绿灯同处一行, 而不是被安全区推到下面。
            .ignoresSafeArea(edges: .top)
        }
        .background {
            WindowAccessor { window in windowBox.window = window }
        }
        .animation(DS.Motion.standard, value: hint)
    }

    // MARK: 统一工具栏
    //
    // 与红绿灯同一行: 左侧留出 78pt 给窗口按钮, 右侧「完成」内缩 12pt,
    // 整条是浮在封面氛围上的玻璃, 而不是第二条 titlebar。

    private var toolbar: some View {
        HStack(spacing: DS.Space.l) {
            DSIconButton(systemName: "chevron.left", size: 26, iconSize: 11,
                         help: "返回净听") {
                closeWindow()
            }

            VStack(alignment: .leading, spacing: 0) {
                Text("哔哩哔哩 · 网页登录")
                    .font(.system(size: 13, weight: .semibold))
                    .tracking(DS.Tracking.tight)
                    .foregroundStyle(DS.Palette.textPrimary)
                Text(hint ?? "扫码或账密登录，检测到登录态后自动完成")
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(hint == nil ? DS.Palette.textTertiary : DS.Palette.amber)
                    .lineLimit(1)
            }

            Spacer(minLength: DS.Space.m)

            DSPillButton(title: "完成", systemImage: "checkmark", prominent: true) {
                complete()
            }
            .help("立即完成并保存登录态")
        }
        // 左侧给窗口红绿灯让位; 右侧内缩 12pt。
        .padding(.leading, 78)
        .padding(.trailing, DS.Space.l)
        .frame(maxWidth: .infinity)
        .frame(height: 52)
        .dsGlass(in: Rectangle(),
                 fallbackFill: DS.Palette.canvasElevated.opacity(0.97))
        .overlay(alignment: .bottom) { DSSoftDivider() }
    }

    // MARK: 网页卡片

    private var webCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: DS.Radius.art, style: .continuous)
                .fill(DS.Palette.canvasElevated)
            BiliWebView(onCookies: { cookies in
                state.finishBiliWebLogin(webCookies: cookies)
            }, box: box, mockHTML: previewMode ? Self.mockHTML() : nil)
        }
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.art, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: DS.Radius.art, style: .continuous)
                .strokeBorder(DS.Palette.hairline, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
    }

    // MARK: 动作

    private func complete() {
        Task {
            let cookies = await box.harvest()
            if cookies["SESSDATA"]?.isEmpty == false {
                state.finishBiliWebLogin(webCookies: cookies)
                closeWindow()
            } else {
                hint = "还没有检测到登录态，请先在网页里完成登录"
            }
        }
    }

    private func closeWindow() {
        (windowBox.window ?? NSApp.keyWindow)?.close()
    }

    // MARK: 截图占位页 (本地 HTML, 不联网)

    private static func mockHTML() -> String {
        let logo = "<div class='logo'>b</div>"
        let qr = qrSVG()
        return """
        <!doctype html><html><head><meta charset="utf-8">\
        <meta name="viewport" content="width=device-width, initial-scale=1"><style>
        *{box-sizing:border-box}
        html,body{height:100%}
        body{margin:0;font-family:-apple-system,BlinkMacSystemFont,"PingFang SC",sans-serif;
             background:#fff;color:#18191c;display:flex;justify-content:center;align-items:flex-start}
        .shell{width:100%;max-width:560px;padding:30px 30px 22px}
        .head{display:flex;align-items:center;gap:9px;margin-bottom:28px}
        .logo{width:28px;height:28px;border-radius:7px;background:#FB7299;color:#fff;
              display:flex;align-items:center;justify-content:center;font-weight:700;font-size:15px}
        .brand{font-size:17px;font-weight:600;letter-spacing:-.2px;white-space:nowrap}
        .brand em{font-style:normal;color:#FB7299}
        .grid{display:flex;gap:32px;align-items:flex-start}
        .qrcol{flex:0 0 auto}
        .qrwrap{width:172px;padding:11px;border:1px solid #e5e6eb;border-radius:12px;
                box-shadow:0 5px 18px rgba(0,0,0,.05)}
        .qr{width:148px;height:148px;display:block}
        .qrnote{margin-top:10px;font-size:10.5px;color:#9499a0;text-align:center;white-space:nowrap}
        .side{flex:1;min-width:0;padding-top:2px}
        .tabs{display:flex;gap:18px;border-bottom:1px solid #eef0f3;padding-bottom:10px;
              margin-bottom:18px;font-size:13.5px;white-space:nowrap}
        .tabs b{color:#18191c;font-weight:600}
        .tabs i{font-style:normal;color:#9499a0}
        .field{height:40px;border:1px solid #e5e6eb;border-radius:9px;margin-bottom:11px;
               display:flex;align-items:center;padding:0 12px;color:#9499a0;font-size:12.5px}
        .primary{height:40px;border-radius:9px;background:#FB7299;color:#fff;font-weight:600;
                 font-size:14px;display:flex;align-items:center;justify-content:center;
                 margin-top:14px;letter-spacing:.3px}
        .hint{margin-top:12px;font-size:10.5px;color:#9499a0;line-height:1.75}
        .hint a{color:#FB7299;text-decoration:none}
        .foot{margin-top:26px;text-align:center;font-size:10px;color:#c9ccd0;line-height:1.8}
        </style></head><body><div class="shell">
          <div class="head">\(logo)<div class="brand">哔哩哔哩 <em>·</em> 登录</div></div>
          <div class="grid">
            <div class="qrcol">
              <div class="qrwrap">\(qr)</div>
              <div class="qrnote">请使用哔哩哔哩客户端扫码</div>
            </div>
            <div class="side">
              <div class="tabs"><b>扫码登录</b><i>密码登录</i><i>短信登录</i></div>
              <div class="field">手机号 / 邮箱</div>
              <div class="field">密码</div>
              <div class="primary">登录</div>
              <div class="hint">未注册的手机号将自动创建账号<br>
                登录即代表同意 <a>用户协议</a> 与 <a>隐私政策</a></div>
            </div>
          </div>
          <div class="foot">哔哩哔哩 (゜-゜)つロ 干杯~<br>净听 PureListen · 网页登录预览占位页</div>
        </div></body></html>
        """
    }

    /// 确定性的二维码纹样(仅用于截图占位, 不是可扫的码)。
    private static func qrSVG(side: Int = 25) -> String {
        var state: UInt64 = 0x9e37_79b9_7f4a_7c15
        func next() -> UInt64 {
            state ^= state << 13
            state ^= state >> 7
            state ^= state << 17
            return state
        }
        func finderDark(_ x: Int, _ y: Int, _ baseX: Int, _ baseY: Int) -> Bool {
            let dx = x - baseX, dy = y - baseY
            if dx < 0 || dy < 0 || dx > 6 || dy > 6 { return false }
            if dx == 0 || dx == 6 || dy == 0 || dy == 6 { return true }
            return dx >= 2 && dx <= 4 && dy >= 2 && dy <= 4
        }
        var cells = ""
        for y in 0..<side {
            for x in 0..<side {
                let inFinder = finderDark(x, y, 0, 0)
                    || finderDark(x, y, side - 7, 0)
                    || finderDark(x, y, 0, side - 7)
                let isDark = inFinder || next() % 2 == 0
                if isDark {
                    cells += "<rect x='\(x)' y='\(y)' width='1' height='1'/>"
                }
            }
        }
        return """
        <svg class='qr' viewBox='0 0 \(side) \(side)' shape-rendering='crispEdges'>\
        <rect width='\(side)' height='\(side)' fill='white'/>\
        <g fill='#18191c'>\(cells)</g></svg>
        """
    }
}

// MARK: - 浏览器

struct BiliWebView: NSViewRepresentable {
    var onCookies: ([String: String]) -> Void
    var box: BiliWebBox
    /// 非 nil 时加载本地占位 HTML(截图), 否则加载真实登录页。
    var mockHTML: String? = nil

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()   // 干净会话
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        box.webView = webView
        if let mockHTML {
            webView.loadHTMLString(mockHTML, baseURL: nil)
        } else {
            webView.load(URLRequest(url: URL(string: "https://passport.bilibili.com/login")!))
        }
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onCookies: onCookies) }

    final class Coordinator: NSObject, WKNavigationDelegate {
        let onCookies: ([String: String]) -> Void
        weak var webView: WKWebView?
        private var pollTimer: Timer?

        init(onCookies: @escaping ([String: String]) -> Void) {
            self.onCookies = onCookies
            super.init()
            pollTimer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: true) { [weak self] _ in
                self?.checkCookies()
            }
            RunLoop.main.add(pollTimer!, forMode: .common)
        }

        deinit { pollTimer?.invalidate() }

        func checkCookies() {
            guard let store = webView?.configuration.websiteDataStore.httpCookieStore else { return }
            store.getAllCookies { [weak self] cookies in
                var dict: [String: String] = [:]
                for cookie in cookies where cookie.domain.contains("bilibili.com") {
                    dict[cookie.name] = cookie.value
                }
                if dict["SESSDATA"]?.isEmpty == false {
                    self?.pollTimer?.invalidate()
                    self?.onCookies(dict)
                }
            }
        }
    }
}

// MARK: - 辅助

/// 持有 WebView, 供「完成」按钮主动收割 Cookie。
@MainActor
final class BiliWebBox: ObservableObject {
    weak var webView: WKWebView?

    func harvest() async -> [String: String] {
        guard let store = webView?.configuration.websiteDataStore.httpCookieStore else { return [:] }
        return await withCheckedContinuation { continuation in
            store.getAllCookies { cookies in
                var dict: [String: String] = [:]
                for cookie in cookies where cookie.domain.contains("bilibili.com") {
                    dict[cookie.name] = cookie.value
                }
                continuation.resume(returning: dict)
            }
        }
    }
}

/// 弱持有本视图所在的 NSWindow, 不触发 SwiftUI 状态刷新。
final class BiliWindowBox {
    weak var window: NSWindow?
}

private struct WindowAccessor: NSViewRepresentable {
    var onChange: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async { onChange(view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { onChange(nsView.window) }
    }
}
